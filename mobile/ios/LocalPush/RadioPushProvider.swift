import Network
import NetworkExtension
import UserNotifications

final class RadioPushProvider: NEAppPushProvider {
  private let queue = DispatchQueue(label: "dev.meshgrame.localpush")
  private var store: LocalPushStore?
  private var maintenance: DispatchSourceTimer?
  private var lease: Int32?
  private var radios: [LocalPushRadio] = []
  private var sessions: [PushRadioSession] = []
  private var closing = false
  private var stopCompletion: (() -> Void)?

  override func start(completionHandler: @escaping (Error?) -> Void) {
    queue.async {
      guard let bundleID = Bundle.main.bundleIdentifier, bundleID.hasSuffix(".LocalPush"),
            let store = LocalPushStore(appBundleID: String(bundleID.dropLast(".LocalPush".count))) else {
        completionHandler(CocoaError(.fileNoSuchFile))
        return
      }
      self.store = store
      CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
        { _, observer, _, _, _ in
          guard let observer else { return }
          let provider = Unmanaged<RadioPushProvider>.fromOpaque(observer).takeUnretainedValue()
          provider.queue.async { provider.reconcile() }
        },
        LocalPushStore.change.rawValue, nil, .deliverImmediately
      )
      let timer = DispatchSource.makeTimerSource(queue: self.queue)
      timer.schedule(deadline: .now() + 5, repeating: 5)
      timer.setEventHandler { [weak self] in self?.maintain() }
      self.maintenance = timer
      timer.resume()
      completionHandler(nil)
      self.reconcile()
    }
  }

  override func stop(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    queue.async {
      self.maintenance?.cancel()
      self.maintenance = nil
      CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
        LocalPushStore.change, nil
      )
      self.store = nil
      self.stopCompletion = completionHandler
      self.reconcile()
    }
  }

  override func handleTimerEvent() {
    queue.async { self.reconcile() }
  }

  private func reconcile() {
    guard !closing else { return }
    let desired = store?.readRadios() ?? []
    if lease != nil {
      if desired != radios { stopSessions() }
      return
    }
    guard let store, !desired.isEmpty, let lease = store.acquire() else {
      finishStop()
      return
    }
    // The app may have cleared the snapshot while the extension was taking the lock.
    guard store.readRadios() == desired else {
      close(lease)
      return
    }
    self.lease = lease
    radios = desired
    sessions = desired.compactMap { PushRadioSession($0, store: store, queue: queue) }
    sessions.forEach { $0.maintain() }
  }

  private func maintain() {
    reconcile()
    if !closing { sessions.forEach { $0.maintain() } }
  }

  private func stopSessions() {
    closing = true
    let group = DispatchGroup()
    for session in sessions {
      group.enter()
      session.stop { group.leave() }
    }
    group.notify(queue: queue) {
      self.sessions = []
      self.radios = []
      if let lease = self.lease { close(lease) }
      self.lease = nil
      self.closing = false
      self.reconcile()
    }
  }

  private func finishStop() {
    let completion = stopCompletion
    stopCompletion = nil
    completion?()
  }
}

private final class PushRadioSession {
  private let queue: DispatchQueue
  private let store: LocalPushStore
  private let radio: LocalPushRadio
  private let wire: RadioPushProtocol
  private let port: Network.NWEndpoint.Port
  private var connection: NWConnection?
  private var retryAfter = Date.distantPast
  private var buffer: [UInt8] = []
  private var known: Set<String> = []
  private var verified = false
  private var nextCommand = Date.distantPast
  private var drainDeadline: Date?
  private var identityDeadline = Date.distantPast
  private var stopCompletion: (() -> Void)?

  init?(_ radio: LocalPushRadio, store: LocalPushStore, queue: DispatchQueue) {
    guard let wire = RadioPushProtocol(rawValue: radio.network),
          let port = Network.NWEndpoint.Port(rawValue: radio.port) else { return nil }
    self.radio = radio
    self.wire = wire
    self.port = port
    self.store = store
    self.queue = queue
    known = radio.knownMessages
    known.formUnion(store.packets().compactMap { $0.1.radio == radio.key ? $0.1.messageID : nil })
  }

  func stop(_ completion: @escaping () -> Void) {
    guard let connection else { completion(); return }
    stopCompletion = completion
    connection.cancel()
  }

  private func connect() {
    verified = false
    drainDeadline = nil
    nextCommand = Date.distantPast
    identityDeadline = Date().addingTimeInterval(20)
    buffer.removeAll(keepingCapacity: true)
    let parameters = NWParameters.tcp
    parameters.requiredInterfaceType = .wifi
    let link = NWConnection(host: Network.NWEndpoint.Host(radio.host), port: port, using: parameters)
    connection = link
    link.stateUpdateHandler = { [weak self, weak link] state in
      guard let self, let link, self.connection === link else { return }
      switch state {
      case .ready:
        if self.stopCompletion == nil {
          self.send(self.wire.boot)
          self.receive(link)
        }
      case .failed(_):
        self.retry()
      case .cancelled:
        self.connection = nil
        let completion = self.stopCompletion
        self.stopCompletion = nil
        completion?()
      default:
        break
      }
    }
    link.start(queue: queue)
  }

  func maintain() {
    if connection == nil {
      if Date() >= retryAfter { connect() }
      return
    }
    if !verified {
      if Date() >= identityDeadline { retry() }
      return
    }
    switch wire {
    case .meshcore:
      if let drainDeadline {
        if Date() >= drainDeadline { retry() }
      } else if Date() >= nextCommand {
        drainInbox()
      }
    case .meshtastic:
      if Date() >= nextCommand {
        nextCommand = Date().addingTimeInterval(30)
        send(wire.encode([0x3a, 0x02, 0x08, 0x01]))
      }
    }
  }

  private func receive(_ link: NWConnection) {
    link.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self, weak link] data, _, ended, error in
      guard let self, let link, self.connection === link, self.stopCompletion == nil else { return }
      if let data {
        self.buffer.append(contentsOf: data)
        for frame in self.wire.frames(&self.buffer) { self.receiveFrame(frame) }
      }
      if ended || error != nil {
        self.retry()
      } else if self.stopCompletion == nil {
        self.receive(link)
      }
    }
  }

  private func receiveFrame(_ frame: [UInt8]) {
    if !verified {
      switch wire {
      case .meshcore:
        guard frame.first == 5, frame.count >= 36 else { return }
        guard RadioPushProtocol.hex(frame[4..<36]) == radio.publicKey else {
          retry()
          return
        }
        // Match the companion protocol version requested by the foreground client.
        send(wire.encode([22, 3]))
      case .meshtastic:
        guard let local = PushProto(frame)?.message(3) else { return }
        guard local[1] == radio.selfNode,
              local.bytes[12].map({ id in
                radio.hardwareID == nil || RadioPushProtocol.hex(id[...]) == radio.hardwareID
              }) ?? true else {
          retry()
          return
        }
      }
      verified = true
      if wire == .meshcore { drainInbox() }
      return
    }
    if let message = wire.message(frame, radio: radio) {
      receiveMessage(message, frame: frame, radio: radio)
    }
    if wire == .meshcore {
      switch frame.first {
      case 0x83 where drainDeadline == nil:
        drainInbox()
      case 7, 8, 16, 17, 27:
        drainInbox()
      case 1, 10:
        drainDeadline = nil
        nextCommand = Date().addingTimeInterval(15)
      default:
        break
      }
    }
  }

  private func drainInbox() {
    drainDeadline = Date().addingTimeInterval(10)
    send(wire.encode([10]))
  }

  private func receiveMessage(_ message: RadioPushProtocol.Message, frame: [UInt8], radio: LocalPushRadio) {
    guard !known.contains(message.id) else { return }
    do {
      try store.append(LocalPushPacket(
        radio: radio.key, receivedAt: Int64(Date().timeIntervalSince1970 * 1000),
        frame: Data(frame), messageID: message.id
      ))
    } catch {
      return
    }
    known.insert(message.id)
    let channel = message.chat.hasPrefix("ch:")
    let alerts = radio.alerts
    guard alerts.enabled, !radio.muted.contains(message.chat),
          radio.unmuted.contains(message.chat) || (channel ? alerts.channels : alerts.direct) else { return }
    let text: String
    if message.reaction {
      guard let target = message.reactionTarget,
            radio.ownMessages[message.chat]?.contains(target) == true else { return }
      text = alerts.reactionMessage
    } else if channel ? alerts.channelPreview : alerts.directPreview {
      text = alerts.names && channel && !message.author.isEmpty
        ? "\(message.author): \(message.text)" : message.text
    } else {
      text = alerts.newMessage
    }
    let content = UNMutableNotificationContent()
    content.title = alerts.names
      ? (radio.peers[message.chat] ?? (channel ? radio.name : message.author))
      : "Meshgram"
    content.body = text
    content.threadIdentifier = "\(radio.key)/\(message.chat)"
    content.sound = (channel ? alerts.channelSound : alerts.directSound) ? .default : nil
    UNUserNotificationCenter.current().add(UNNotificationRequest(
      identifier: "\(radio.key)/\(message.chat)", content: content, trigger: nil
    ))
  }

  private func send(_ data: Data) {
    guard let link = connection else { return }
    link.send(content: data, completion: .contentProcessed { [weak self, weak link] error in
      guard let self, let link, self.connection === link, error != nil else { return }
      self.retry()
    })
  }

  private func retry() {
    retryAfter = Date().addingTimeInterval(10)
    connection?.cancel()
  }
}
