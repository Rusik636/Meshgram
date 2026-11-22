// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import Foundation

struct LocalPushAlerts: Codable, Equatable {
  let enabled: Bool
  let direct: Bool
  let channels: Bool
  let directPreview: Bool
  let channelPreview: Bool
  let directSound: Bool
  let channelSound: Bool
  let names: Bool
  let newMessage: String
  let reactionMessage: String
}

struct LocalPushRadio: Codable, Equatable {
  let key: String
  let network: String
  let name: String
  let host: String
  let port: UInt16
  let selfNode: UInt32?
  let publicKey: String?
  let hardwareID: String?
  let muted: Set<String>
  let unmuted: Set<String>
  let ownMessages: [String: Set<String>]
  let alerts: LocalPushAlerts
  let peers: [String: String]
  let knownMessages: Set<String>
}

struct LocalPushPacket: Codable {
  let radio: String
  let receivedAt: Int64
  let frame: Data
  let messageID: String?
}

struct LocalPushStore {
  static let change = CFNotificationName("dev.meshgrame.client.local-push.session" as CFString)
  let folder: URL

  init?(appBundleID: String) {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group." + appBundleID + ".localpush"
    ) else { return nil }
    folder = container.appendingPathComponent("LocalPush", isDirectory: true)
  }

  private var state: URL { folder.appendingPathComponent("radio.json") }

  func prepare() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  func readRadios() -> [LocalPushRadio] {
    guard let data = try? Data(contentsOf: state) else { return [] }
    return (try? JSONDecoder().decode([LocalPushRadio].self, from: data)) ?? []
  }

  func setRadios(_ radios: [LocalPushRadio]) throws {
    if !radios.isEmpty {
      try write(radios, to: state)
    } else if FileManager.default.fileExists(atPath: state.path) {
      try FileManager.default.removeItem(at: state)
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), Self.change, nil, nil, true)
  }

  func acquire() -> Int32? {
    guard (try? prepare()) != nil else { return nil }
    let fd = open(folder.appendingPathComponent("session.lock").path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { return nil }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
      close(fd)
      return nil
    }
    return fd
  }

  func append(_ packet: LocalPushPacket) throws {
    let filename = "\(packet.receivedAt)-\(UUID().uuidString).json"
    try write(packet, to: folder.appendingPathComponent(filename))
  }

  func packets() -> [(String, LocalPushPacket)] {
    let files = (try? FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil
    )) ?? []
    return files.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
      let name = url.lastPathComponent
      guard Self.validPacketName(name), let data = try? Data(contentsOf: url),
            let packet = try? JSONDecoder().decode(LocalPushPacket.self, from: data) else { return nil }
      return (name, packet)
    }
  }

  func acknowledge(_ filenames: [String]) {
    for name in filenames where Self.validPacketName(name) {
      try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }
  }

  private static func validPacketName(_ name: String) -> Bool {
    name.range(of: #"^[0-9]+-[0-9A-Fa-f-]{36}\.json$"#, options: .regularExpression) != nil
  }

  private func write<T: Encodable>(_ value: T, to url: URL) throws {
    try prepare()
    // The radio may deliver packets while the phone is locked.
    try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}
