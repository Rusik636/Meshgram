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
      ("chat title", ["kind": "chatTitle", "label": "River", "subtitle": "Channel"]),
      ("chat avatar", ["kind": "chatAvatar", "label": "Chat profile", "initials": "R"]),
      ("map title", ["kind": "chatTitle", "label": "Node map", "readOnly": true]),
    ]

    for dark in [false, true] {
      for (name, properties) in controls {
        let input = appearance(dark: dark).merging(properties) { _, value in value }
        let control = MeshControlSurface(
          frame: CGRect(x: 0, y: 0, width: 160, height: 48),
          channel: channel(),
          input: input
        )
        let root = control.view()
        root.layoutIfNeeded()
        let panel = try XCTUnwrap(root.subviews.compactMap { $0 as? UIVisualEffectView }.first)
        let button = try XCTUnwrap(panel.contentView.subviews.compactMap { $0 as? UIButton }.first)
        XCTAssertEqual(panel.bounds.height, name == "attach" ? 40 : 44)
        let initial = try XCTUnwrap(button.configuration)
        let readOnly = input["readOnly"] as? Bool == true
        XCTAssertEqual(root.isUserInteractionEnabled, !readOnly, name)
        XCTAssertFalse(root.accessibilityElementsHidden, name)
        if !readOnly {
          let edge = CGPoint(x: 1, y: root.bounds.midY)
          XCTAssertTrue(root.hitTest(edge, with: nil) === button)
          XCTAssertTrue(button.point(inside: button.convert(edge, from: root), with: nil))
          button.isHighlighted = true
          XCTAssertEqual(button.alpha, 0.6, accuracy: 0.001)
          XCTAssertEqual(panel.alpha, 1)
          button.isHighlighted = false
        }

        for covered in [true, false] {
          let state = "\(name), dark=\(dark), covered=\(covered)"
          control.update(input.merging(["coveredByModal": covered]) { _, value in value })
          XCTAssertTrue(control.view() === root, state)
          XCTAssertTrue(panel.contentView.subviews.contains { $0 === button }, state)
          XCTAssertEqual(button.configuration, initial, state)
          if #available(iOS 26.0, *), !UIAccessibility.isReduceTransparencyEnabled {
            let glass = try XCTUnwrap(panel.effect as? UIGlassEffect, state)
            let expectedTint = name == "send" ? UIColor.systemBlue : meshPanelTint(dark: dark)
            XCTAssertEqual(glass.tintColor, expectedTint, state)
            XCTAssertEqual(glass.isInteractive, !readOnly && name != "chat title", state)
          }
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
    ]
  }

  private func channel() -> FlutterMethodChannel {
    FlutterMethodChannel(name: "meshgrame/tests/glass", binaryMessenger: TestMessenger())
  }
}

private final class TestMessenger: NSObject, FlutterBinaryMessenger {
  func send(onChannel channel: String, message: Data?) {}

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
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
