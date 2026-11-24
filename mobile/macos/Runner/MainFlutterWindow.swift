import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  fileprivate weak var windowControlsAnchor: NSView?
  private var titlebarControls: [(button: NSButton, origin: NSPoint)] = []

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    styleMask.insert(.fullSizeContentView)
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    titlebarSeparatorStyle = .none
    isMovableByWindowBackground = true
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.minSize = NSSize(width: 480, height: 400)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    let registrar = flutterViewController.registrar(forPlugin: "MeshGlass")
    registrar.register(MeshGlassFactory(), withId: "meshgrame/glass")
    registrar.register(MeshWindowControlsFactory(), withId: "meshgrame/window_controls")
    FlutterMethodChannel(name: "meshgrame/macos_glass", binaryMessenger: registrar.messenger)
      .setMethodCallHandler { call, reply in
        guard call.method == "configuration" else {
          reply(FlutterMethodNotImplemented)
          return
        }
        let glass: Bool
        if #available(macOS 26.0, *) {
          glass = !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        } else {
          glass = false
        }
        reply([
          "glass": glass,
          "regularFontSize": NSFont.systemFontSize(for: .regular),
          "smallFontSize": NSFont.smallSystemFontSize
        ])
      }

    super.awakeFromNib()
  }

  override func update() {
    super.update()
    positionWindowControls()
  }

  fileprivate func positionWindowControls() {
    guard let anchor = windowControlsAnchor, anchor.window === self,
          !anchor.bounds.isEmpty, !styleMask.contains(.fullScreen) else {
      for (button, origin) in titlebarControls { button.setFrameOrigin(origin) }
      titlebarControls.removeAll()
      return
    }

    if titlebarControls.isEmpty {
      let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
      titlebarControls = kinds.compactMap { kind in
        standardWindowButton(kind).map { (button: $0, origin: $0.frame.origin) }
      }
    }
    guard let (first, firstOrigin) = titlebarControls.first,
          let parent = first.superview,
          titlebarControls.allSatisfy({ $0.button.superview === parent }) else { return }

    let slot = parent.convert(anchor.convert(anchor.bounds, to: nil), from: nil)
    let firstFrame = NSRect(origin: firstOrigin, size: first.frame.size)
    let group = titlebarControls.reduce(firstFrame) { rect, control in
      rect.union(NSRect(origin: control.origin, size: control.button.frame.size))
    }
    for (button, origin) in titlebarControls {
      let y = slot.midY - button.frame.height / 2
      let target = NSPoint(
        x: slot.midX - group.width / 2 + origin.x - group.minX,
        y: max(parent.bounds.minY, min(y, parent.bounds.maxY - button.frame.height))
      )
      if button.frame.origin != target { button.setFrameOrigin(target) }
    }
  }
}

private final class MeshWindowControlsFactory: NSObject, FlutterPlatformViewFactory {
  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    MeshWindowControlsView()
  }
}

private final class MeshWindowControlsView: NSView {
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if let window = window as? MainFlutterWindow,
       window !== newWindow, window.windowControlsAnchor === self {
      window.windowControlsAnchor = nil
      window.positionWindowControls()
    }
    super.viewWillMove(toWindow: newWindow)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let window = window as? MainFlutterWindow else { return }
    window.windowControlsAnchor = self
    window.positionWindowControls()
  }

  override func layout() {
    super.layout()
    (window as? MainFlutterWindow)?.positionWindowControls()
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class MeshGlassFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    guard #available(macOS 26.0, *) else { return NSView() }
    let options = args as? [String: Any]
    let glass = MeshGlassView()
    let radius = options?["radius"] as? NSNumber
    glass.cornerRadius = CGFloat(radius?.doubleValue ?? 22)
    if let dark = options?["dark"] as? Bool {
      glass.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
    if let tint = options?["tint"] as? NSNumber {
      let value = tint.uint32Value
      glass.tintColor = NSColor(
        srgbRed: CGFloat((value >> 16) & 255) / 255,
        green: CGFloat((value >> 8) & 255) / 255,
        blue: CGFloat(value & 255) / 255,
        alpha: CGFloat(value >> 24) / 255
      )
    }
    return glass
  }
}

@available(macOS 26.0, *)
private final class MeshGlassView: NSGlassEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
