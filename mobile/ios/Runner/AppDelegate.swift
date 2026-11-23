// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import AudioToolbox
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  let engine = FlutterEngine(name: "Meshgram", project: nil, allowHeadlessExecution: true)
  private let wifiPush = WifiPushNotifications()
  private let backSwipeSnapshot = BackSwipeSnapshot()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    engine.run()
    GeneratedPluginRegistrant.register(with: engine)
    registerPlatformControls()
    RadioMessageNotifications.register(with: engine.binaryMessenger)
    wifiPush.register(with: engine.binaryMessenger)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerPlatformControls() {
    if let registrar = engine.registrar(forPlugin: "MeshControls") {
      FlutterMethodChannel(name: "meshgrame/app_info", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          guard call.method == "buildInfo" else {
            result(FlutterMethodNotImplemented)
            return
          }
          let bundle = Bundle.main
          var info = [String: String]()
          info["version"] = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
          info["number"] = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
          if let url = bundle.url(forResource: "meshgrame-build-date", withExtension: "txt"),
             let date = try? String(contentsOf: url, encoding: .utf8) {
            info["date"] = date.trimmingCharacters(in: .whitespacesAndNewlines)
          }
          result(info)
        }
      registrar.register(MeshControlsFactory(registrar.messenger()), withId: "meshgrame/controls")
      registrar.register(MeshComposerFactory(registrar.messenger()), withId: "meshgrame/composer")
      backSwipeSnapshot.register(with: registrar)
    }
  }
}

private enum RadioMessageNotifications {
  private static let messageSound: SystemSoundID? = {
    guard let framework = Bundle.main.privateFrameworksURL?.appendingPathComponent("App.framework"),
          let bundle = Bundle(url: framework),
          let root = bundle.resourceURL else { return nil }
    let asset = FlutterDartProject.lookupKey(forAsset: "assets/sounds/message.wav")
    let sound = root.appendingPathComponent(asset)
    var id: SystemSoundID = 0
    return AudioServicesCreateSystemSoundID(sound as CFURL, &id) == kAudioServicesNoError ? id : nil
  }()

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "meshgrame/notifications", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "permission":
        permission(center, result)
      case "requestPermission":
        guard UIApplication.shared.applicationState == .active else {
          permission(center, result)
          return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
          permission(center, result)
        }
      case "openSettings":
        let address: String
        if #available(iOS 16.0, *) {
          address = UIApplication.openNotificationSettingsURLString
        } else {
          address = UIApplication.openSettingsURLString
        }
        if let url = URL(string: address) { UIApplication.shared.open(url) }
        result(nil)
      case "playInAppSound":
        if UIApplication.shared.applicationState == .active, let sound = messageSound {
          AudioServicesPlaySystemSound(sound)
        }
        result(nil)
      case "requestBadge":
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
          DispatchQueue.main.async { result(nil) }
        }
      case "badge":
        guard let count = call.arguments as? Int else { result(nil); return }
        if #available(iOS 16.0, *) {
          center.setBadgeCount(count)
        } else {
          UIApplication.shared.applicationIconBadgeNumber = count
        }
        result(nil)
      case "publish":
        guard UIApplication.shared.applicationState != .active,
              let data = call.arguments as? [String: Any],
              let chat = data["chat"] as? String, let title = data["title"] as? String,
              let body = data["body"] as? String else {
          result(nil)
          return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = chat
        content.sound = data["sound"] as? Bool == false ? nil : .default
        center.add(UNNotificationRequest(identifier: chat, content: content, trigger: nil)) { error in
          DispatchQueue.main.async {
            if let error {
              result(FlutterError(code: "notification", message: error.localizedDescription, details: nil))
            } else {
              result(nil)
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func permission(_ center: UNUserNotificationCenter, _ result: @escaping FlutterResult) {
    center.getNotificationSettings { settings in
      let value: String
      switch settings.authorizationStatus {
      case .notDetermined: value = "prompt"
      case .authorized, .provisional, .ephemeral: value = "enabled"
      default: value = "disabled"
      }
      DispatchQueue.main.async { result(value) }
    }
  }
}

private final class BackSwipeSnapshot {
  private var id: Int?
  private var overlay: UIView?
  private var snapshot: UIView?

  func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "meshgrame/back_swipe", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self,
            let arguments = call.arguments as? [String: Any],
            let id = arguments["id"] as? Int else {
        result(false)
        return
      }
      switch call.method {
      case "capture":
        result(self.capture(id, from: registrar.viewController?.viewIfLoaded))
      case "afterFrame":
        // Flutter's endOfFrame is on the Dart thread, before the new surface is composited.
        DisplayFrameDelay.wait {
          result(self.id == id)
        }
      case "move":
        guard self.id == id, let overlay = self.overlay,
              let offset = arguments["offset"] as? Double else {
          result(false)
          return
        }
        self.snapshot?.transform = CGAffineTransform(translationX: overlay.bounds.width * offset, y: 0)
        result(true)
      case "release":
        DisplayFrameDelay.wait {
          if self.id == id { self.remove() }
          result(true)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func capture(_ id: Int, from host: UIView?) -> Bool {
    guard let host, let window = host.window, !host.bounds.isEmpty else { return false }
    remove()
    let frame = host.convert(host.bounds, to: window)
    let format = UIGraphicsImageRendererFormat()
    format.scale = window.traitCollection.displayScale
    var captured = false
    // Rasterize the composed window while both Flutter and UIKit are visible.
    // A live snapshot view can lose its backing content on a physical device.
    let image = UIGraphicsImageRenderer(size: frame.size, format: format).image { context in
      context.cgContext.translateBy(x: -frame.minX, y: -frame.minY)
      captured = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    guard captured else { return false }

    let overlay = UIView(frame: frame)
    overlay.clipsToBounds = true
    overlay.isUserInteractionEnabled = false
    overlay.accessibilityElementsHidden = true
    let snapshot = UIImageView(image: image)
    snapshot.frame = overlay.bounds
    overlay.addSubview(snapshot)
    // The window overlay is above Flutter's platform-view overlay layers.
    window.addSubview(overlay)
    self.id = id
    self.overlay = overlay
    self.snapshot = snapshot
    return true
  }

  private func remove() {
    overlay?.removeFromSuperview()
    id = nil
    overlay = nil
    snapshot = nil
  }
}

private final class DisplayFrameDelay {
  private let completion: () -> Void
  private var remainingFrames = 2

  private init(_ completion: @escaping () -> Void) {
    self.completion = completion
  }

  static func wait(_ completion: @escaping () -> Void) {
    let delay = DisplayFrameDelay(completion)
    let link = CADisplayLink(target: delay, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
  }

  @objc private func tick(_ link: CADisplayLink) {
    remainingFrames -= 1
    guard remainingFrames == 0 else { return }
    link.invalidate()
    completion()
  }
}
