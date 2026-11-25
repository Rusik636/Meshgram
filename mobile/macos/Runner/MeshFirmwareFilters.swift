import Cocoa
import FlutterMacOS

final class MeshFirmwareFiltersFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let channel = FlutterMethodChannel(
      name: "meshgrame/firmware_filters/\(viewId)", binaryMessenger: messenger
    )
    return MeshFirmwareFiltersView(channel: channel, input: args as? [String: Any] ?? [:])
  }
}

private final class MeshFirmwareFiltersView: NSView {
  private struct Facet {
    let id: String
    let title: String
    let options: [String]

    init?(input: [String: Any]) {
      guard let id = input["id"] as? String, let title = input["title"] as? String,
            let options = input["options"] as? [String] else { return nil }
      self.id = id
      self.title = title
      self.options = options
    }
  }

  private let channel: FlutterMethodChannel
  private let facets: [Facet]
  private let scroll = NSScrollView()
  private var facetIndex = 0
  private var selection: [String: Set<String>] = [:]
  private var checkboxes: [NSButton] = []

  init(channel: FlutterMethodChannel, input: [String: Any]) {
    self.channel = channel
    facets = (input["facets"] as? [[String: Any]] ?? []).compactMap(Facet.init)
    super.init(frame: .zero)

    let tabs = NSSegmentedControl(
      labels: facets.map { $0.title }, trackingMode: .selectOne,
      target: self, action: #selector(changeFacet)
    )
    tabs.selectedSegment = 0
    tabs.segmentDistribution = .fillProportionally
    tabs.translatesAutoresizingMaskIntoConstraints = false

    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.translatesAutoresizingMaskIntoConstraints = false
    let closeLabel = input["closeLabel"] as? String ?? ""
    let close = NSButton(
      image: NSImage(systemSymbolName: "xmark", accessibilityDescription: nil) ?? NSImage(),
      target: self, action: #selector(closePanel)
    )
    close.isBordered = false
    close.setAccessibilityLabel(closeLabel)
    close.translatesAutoresizingMaskIntoConstraints = false

    addSubview(tabs)
    addSubview(close)
    addSubview(scroll)
    NSLayoutConstraint.activate([
      tabs.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      tabs.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      tabs.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
      close.centerYAnchor.constraint(equalTo: tabs.centerYAnchor),
      close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      close.widthAnchor.constraint(equalToConstant: 26),
      close.heightAnchor.constraint(equalToConstant: 26),
      scroll.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 9),
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
    ])

    update(input)
    showOptions()
    channel.setMethodCallHandler { [weak self] call, reply in
      guard call.method == "update", let input = call.arguments as? [String: Any] else {
        reply(FlutterMethodNotImplemented)
        return
      }
      self?.update(input)
      reply(nil)
    }
  }

  required init?(coder: NSCoder) { nil }

  deinit { channel.setMethodCallHandler(nil) }

  @objc private func closePanel() {
    channel.invokeMethod("close", arguments: nil)
  }

  @objc private func changeFacet(_ sender: NSSegmentedControl) {
    facetIndex = sender.selectedSegment
    showOptions()
  }

  private func showOptions() {
    guard facets.indices.contains(facetIndex) else { return }
    let facet = facets[facetIndex]
    checkboxes = facet.options.map { value in
      NSButton(checkboxWithTitle: value, target: self, action: #selector(toggleOption))
    }

    let stack = MeshFirmwareOptionsStack(views: checkboxes)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 7
    stack.edgeInsets = NSEdgeInsets(top: 3, left: 4, bottom: 3, right: 4)
    stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
    scroll.documentView = stack
    scroll.contentView.scroll(to: .zero)
    scroll.reflectScrolledClipView(scroll.contentView)
    syncCheckboxes()
  }

  private func update(_ input: [String: Any]) {
    selection = (input["selection"] as? [String: [String]] ?? [:]).mapValues(Set.init)
    let dark = input["dark"] as? Bool == true
    appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    syncCheckboxes()
  }

  private func syncCheckboxes() {
    guard facets.indices.contains(facetIndex) else { return }
    let selected = selection[facets[facetIndex].id] ?? []
    for option in checkboxes {
      option.state = selected.contains(option.title) ? .on : .off
    }
  }

  @objc private func toggleOption(_ sender: NSButton) {
    let facet = facets[facetIndex].id
    if sender.state == .on {
      selection[facet, default: []].insert(sender.title)
    } else {
      selection[facet]?.remove(sender.title)
    }
    channel.invokeMethod("toggle", arguments: ["facet": facet, "value": sender.title])
  }
}

private final class MeshFirmwareOptionsStack: NSStackView {
  override var isFlipped: Bool { true }
}
