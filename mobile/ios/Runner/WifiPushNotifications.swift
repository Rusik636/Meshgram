// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import Flutter
import NetworkExtension
import UIKit

final class WifiPushNotifications {
  private var manager: NEAppPushManager?
  private var backgroundTask = UIBackgroundTaskIdentifier.invalid

  private var bundleID: String { Bundle.main.bundleIdentifier ?? "" }
  private var providerID: String { bundleID + ".LocalPush" }
  private var store: LocalPushStore? {
    guard let extensions = Bundle.main.builtInPlugInsURL,
          Bundle(url: extensions.appendingPathComponent("LocalPush.appex")) != nil else { return nil }
    return LocalPushStore(appBundleID: bundleID)
  }

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "meshgrame/wifi_push", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, let store = self.store else {
        result(call.method == "status" ? ["available": false] : nil)
        return
      }
      switch call.method {
      case "status":
        self.loadManager { error in
          if let error {
            result(self.flutterError(error))
          } else {
            result([
              "available": true,
              "ssid": self.manager?.isEnabled == true ? self.manager?.matchSSIDs.first ?? "" : "",
              "active": self.manager?.isActive == true,
            ])
          }
        }
      case "configure":
        guard let ssid = call.arguments as? String else {
          result(FlutterError(code: "wifi_push_ssid", message: nil, details: nil))
          return
        }
        self.configure(ssid, store: store, result: result)
      case "stage":
        guard UIApplication.shared.applicationState == .background,
              self.manager?.isEnabled == true,
              let values = call.arguments as? [[String: Any]] else {
          result(false)
          return
        }
        do {
          let json = try JSONSerialization.data(withJSONObject: values)
          let radios = try JSONDecoder().decode([LocalPushRadio].self, from: json)
          try store.setRadios(radios)
          result(true)
        } catch {
          result(self.flutterError(error))
        }
      case "finishHandoff":
        self.endBackgroundTask()
        result(nil)
      case "resume":
        do {
          try store.setRadios([])
          self.waitForLease(store, attempts: 80, result: result)
        } catch {
          result(self.flutterError(error))
        }
      case "acknowledge":
        store.acknowledge(call.arguments as? [String] ?? [])
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(applicationDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification, object: nil
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(endBackgroundTask),
      name: UIApplication.willEnterForegroundNotification, object: nil
    )
  }

  private func loadManager(_ done: @escaping (Error?) -> Void) {
    NEAppPushManager.loadAllFromPreferences { managers, error in
      DispatchQueue.main.async {
        if error == nil {
          self.manager = managers?.first { $0.providerBundleIdentifier == self.providerID }
        }
        done(error)
      }
    }
  }

  private func configure(_ ssid: String, store: LocalPushStore, result: @escaping FlutterResult) {
    guard ssid.utf8.count <= 32, !ssid.contains("\0") else {
      result(FlutterError(code: "wifi_push_ssid", message: nil, details: nil))
      return
    }
    loadManager { error in
      if let error {
        result(self.flutterError(error))
        return
      }
      let manager = self.manager ?? NEAppPushManager()
      if ssid.isEmpty {
        do {
          try store.setRadios([])
        } catch {
          result(self.flutterError(error))
          return
        }
        guard self.manager != nil else {
          result(true)
          return
        }
        manager.removeFromPreferences { error in
          DispatchQueue.main.async {
            if let error {
              result(self.flutterError(error))
            } else {
              self.manager = nil
              result(true)
            }
          }
        }
        return
      }
      manager.localizedDescription = "Meshgram"
      manager.providerBundleIdentifier = self.providerID
      manager.matchSSIDs = [ssid]
      manager.isEnabled = true
      manager.saveToPreferences { error in
        DispatchQueue.main.async {
          if let error {
            result(self.flutterError(error))
          } else {
            self.loadManager { error in
              if let error {
                result(self.flutterError(error))
              } else {
                result(true)
              }
            }
          }
        }
      }
    }
  }

  private func waitForLease(_ store: LocalPushStore, attempts: Int, result: @escaping FlutterResult) {
    if let lease = store.acquire() {
      let packets: [[String: Any]] = store.packets().map { name, packet in
        [
          "file": name, "radio": packet.radio, "receivedAt": packet.receivedAt,
          "frame": FlutterStandardTypedData(bytes: packet.frame),
        ]
      }
      close(lease)
      result(packets)
    } else if attempts > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.waitForLease(store, attempts: attempts - 1, result: result)
      }
    } else {
      result(FlutterError(code: "wifi_push_busy", message: nil, details: nil))
    }
  }

  @objc private func applicationDidEnterBackground() {
    guard manager?.isEnabled == true, backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Meshgram radio handoff") { [weak self] in
      self?.endBackgroundTask()
    }
  }

  @objc private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }

  private func flutterError(_ error: Error) -> FlutterError {
    FlutterError(code: "wifi_push", message: error.localizedDescription, details: nil)
  }
}
