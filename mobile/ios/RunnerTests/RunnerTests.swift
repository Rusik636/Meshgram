// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {
  @MainActor
  func testNativeButtonsKeepTheirConfigurationWhileCovered() throws {
    let controls: [(name: String, properties: [String: Any])] = [
      ("back", ["symbol": "chevron.left", "label": "Back"]),
      ("attach", ["symbol": "paperclip", "label": "Attachments"]),
      ("send", ["symbol": "arrow.up", "label": "Send", "primary": true]),
      ("chat title", ["kind": "chatTitle", "label": "Public", "subtitle": "Канал"]),
      ("chat avatar", ["kind": "chatAvatar", "label": "Chat profile", "initials": "R"]),
      ("map title", ["kind": "chatTitle", "label": "Геопозиция", "readOnly": true]),
      ("location action", ["label": "Геопозиция"]),
    ]

    for dark in [false, true] {
      for (name, properties) in controls {
        let input = appearance(dark: dark).merging(properties) { _, value in value }
          .merging(["visualOutset": 8]) { _, value in value }
        let messenger = TestMessenger()
        let control = MeshControlSurface(
          frame: CGRect(x: 0, y: 0, width: 176, height: 64),
          channel: channel(messenger),
          input: input
        )
        let root = control.view()
        root.layoutIfNeeded()
        let button = try XCTUnwrap(root.subviews.compactMap { $0 as? UIButton }.first)
        XCTAssertFalse(root.clipsToBounds)
        XCTAssertEqual(button.bounds.height, name == "attach" ? 40 : name == "location action" ? 48 : 44)
        button.layoutIfNeeded()
        let initial = try XCTUnwrap(button.configuration)
        if let title = initial.attributedTitle.map({ String($0.characters) }) ?? initial.title {
          let titleLabel = try XCTUnwrap(button.titleLabel, name)
          XCTAssertEqual(titleLabel.text, title, name)
          XCTAssertGreaterThan(titleLabel.bounds.width, 0, name)
        }
        if name == "send" {
          let image = try XCTUnwrap(button.imageView, name)
          XCTAssertGreaterThan(image.bounds.width, 0, name)
          XCTAssertEqual(initial.baseForegroundColor, meshColor(input["onAccent"], .white), name)
        }
        let readOnly = input["readOnly"] as? Bool == true
        XCTAssertEqual(root.isUserInteractionEnabled, !readOnly, name)
        XCTAssertFalse(root.accessibilityElementsHidden, name)
        if !readOnly {
          let edge = CGPoint(x: 9, y: root.bounds.midY)
          XCTAssertNil(root.hitTest(CGPoint(x: 7, y: edge.y), with: nil))
          XCTAssertTrue(root.hitTest(edge, with: nil) === button)
          XCTAssertTrue(button.point(inside: button.convert(edge, from: root), with: nil))
          button.isHighlighted = true
          XCTAssertEqual(button.alpha, 1, name)
          button.isHighlighted = false
          button.sendActions(for: .touchUpInside)
          XCTAssertEqual(messenger.methods, ["select"], name)
        } else {
          XCTAssertNil(root.hitTest(CGPoint(x: root.bounds.midX, y: root.bounds.midY), with: nil), name)
        }

        for covered in [true, false] {
          let state = "\(name), dark=\(dark), covered=\(covered)"
          control.update(input.merging(["coveredByModal": covered]) { _, value in value })
          XCTAssertTrue(control.view() === root, state)
          XCTAssertTrue(root.subviews.contains { $0 === button }, state)
          XCTAssertEqual(button.configuration, initial, state)
          XCTAssertEqual(root.isUserInteractionEnabled, !covered && !readOnly, state)
          XCTAssertEqual(root.accessibilityElementsHidden, covered, state)
        }
      }
    }
  }

  @MainActor
  func testNativeSearchKeepsItsEffectWhileCovered() throws {
    for dark in [false, true] {
      let input = appearance(dark: dark).merging([
        "placeholder": "Search", "autofocus": false, "cornerSearch": true, "active": true,
      ]) { _, value in value }
      let search = MeshSearchField(
        frame: CGRect(x: 0, y: 0, width: 200, height: 48),
        channel: channel(),
        input: input
      )
      let view = try XCTUnwrap(search.view() as? UIVisualEffectView)
      let initialEffect = view.effect
      let initialBackground = view.backgroundColor
      let reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
      XCTAssertTrue(view.isUserInteractionEnabled)
      XCTAssertFalse(view.accessibilityElementsHidden)

      for covered in [true, false] {
        let state = "dark=\(dark), covered=\(covered)"
        search.update(input.merging(["coveredByModal": covered]) { _, value in value })
        XCTAssertTrue(search.view() === view, state)
        if reduceTransparency {
          XCTAssertNil(initialEffect, state)
          XCTAssertNil(view.effect, state)
        } else if #available(iOS 26.0, *) {
          let initialGlass = try XCTUnwrap(initialEffect as? UIGlassEffect, state)
          let glass = try XCTUnwrap(view.effect as? UIGlassEffect, state)
          XCTAssertEqual(glass.tintColor, initialGlass.tintColor, state)
          XCTAssertEqual(glass.isInteractive, initialGlass.isInteractive, state)
        } else {
          XCTAssertTrue(initialEffect is UIBlurEffect, state)
          XCTAssertTrue(view.effect is UIBlurEffect, state)
        }
        XCTAssertEqual(view.backgroundColor, initialBackground, state)
        XCTAssertEqual(view.isUserInteractionEnabled, !covered, state)
        XCTAssertEqual(view.accessibilityElementsHidden, covered, state)
      }
    }
  }

  private func appearance(dark: Bool) -> [String: Any] {
    [
      "dark": dark,
      "enabled": true,
      "surface": UInt32(dark ? 0xff343c4d : 0xffeef1f8),
      "foreground": UInt32(dark ? 0xfff0f3fa : 0xff202a3c),
      "onAccent": UInt32(dark ? 0xff10254b : 0xffffffff),
    ]
  }

  private func channel(_ messenger: TestMessenger = TestMessenger()) -> FlutterMethodChannel {
    FlutterMethodChannel(name: "meshgrame/tests/glass", binaryMessenger: messenger)
  }
}

private final class TestMessenger: NSObject, FlutterBinaryMessenger {
  private(set) var methods: [String] = []

  func send(onChannel channel: String, message: Data?) {
    record(message)
  }

  private func record(_ message: Data?) {
    guard let message else { return }
    methods.append(FlutterStandardMethodCodec.sharedInstance().decodeMethodCall(message).method)
  }

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    record(message)
    callback?(nil)
  }

  func setMessageHandlerOnChannel(
    _ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    0
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
