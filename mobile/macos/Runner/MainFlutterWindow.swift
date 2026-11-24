import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.minSize = NSSize(width: 480, height: 400)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    let registrar = flutterViewController.registrar(forPlugin: "MeshGlass")
    registrar.register(MeshGlassFactory(), withId: "meshgrame/glass")
    FlutterMethodChannel(name: "meshgrame/macos_glass", binaryMessenger: registrar.messenger)
      .setMethodCallHandler { call, reply in
        guard call.method == "isSupported" else {
          reply(FlutterMethodNotImplemented)
          return
        }
        if #available(macOS 26.0, *) {
          reply(true)
        } else {
          reply(false)
        }
      }

    super.awakeFromNib()
  }
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
