// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {
  @MainActor
  func testComposerUsesInteractiveGlassAndKeepsTheSameEditor() throws {
    let draft = "Первая строка\nВторая 👋"
    let input = appearance(dark: true).merging([
      "text": draft, "placeholder": "Сообщение", "visualOutset": 8,
    ]) { _, value in value }
    let composer = MeshComposer(frame: CGRect(x: 0, y: 0, width: 256, height: 62),
      id: 0, input: input, messenger: TestMessenger())
    let root = composer.view()
    root.layoutIfNeeded()
    let field = try XCTUnwrap(root.subviews.first)
    let glass = try XCTUnwrap(field.subviews.first as? UIVisualEffectView)
    let interactive = glass.isUserInteractionEnabled
    let editor = try XCTUnwrap((interactive ? glass.contentView : field).subviews.last as? UITextView)
    let placeholder = try XCTUnwrap(editor.subviews.compactMap { $0 as? UILabel }.first {
      $0.text == "Сообщение"
    })
    let press = try XCTUnwrap(field.gestureRecognizers?.first as? UILongPressGestureRecognizer)
    XCTAssertFalse(root.clipsToBounds)
    XCTAssertEqual(field.frame, root.bounds.insetBy(dx: 8, dy: 8))
    XCTAssertFalse(press.cancelsTouchesInView)
    XCTAssertFalse(press.delaysTouchesBegan)
    XCTAssertTrue(composer.gestureRecognizer(press,
      shouldRecognizeSimultaneouslyWith: editor.panGestureRecognizer))
    XCTAssertEqual(editor.accessibilityLabel, placeholder.text)
    XCTAssertFalse(placeholder.isAccessibilityElement)
    XCTAssertTrue(placeholder.isHidden)

    let selection = NSRange(location: 2, length: 4)
    editor.selectedRange = selection
    for covered in [true, false] {
      composer.updateAppearance(input.merging(["coveredByModal": covered]) { _, value in value })
      root.frame.size.height = covered ? 84 : 66
      root.layoutIfNeeded()
      XCTAssertTrue((interactive ? glass.contentView : field).subviews.last === editor)
      XCTAssertEqual(editor.bounds.height, field.bounds.height)
      XCTAssertEqual(editor.text, draft)
      XCTAssertEqual(editor.selectedRange, selection)
      XCTAssertTrue(editor.transform.isIdentity)
      XCTAssertEqual(root.accessibilityElementsHidden, covered)
      XCTAssertEqual(press.isEnabled, !interactive && !covered && !UIAccessibility.isReduceMotionEnabled)
      if #available(iOS 26.0, *), !UIAccessibility.isReduceTransparencyEnabled {
        let material = try XCTUnwrap(glass.effect as? UIGlassEffect)
        XCTAssertNil(material.tintColor)
        XCTAssertEqual(material.isInteractive, !UIAccessibility.isReduceMotionEnabled)
      }
    }

    composer.updateAppearance(input.merging(["highContrast": true]) { _, value in value })
    let opaque = try XCTUnwrap(field.subviews.first as? UIVisualEffectView)
    XCTAssertNil(opaque.effect)
    XCTAssertEqual(opaque.backgroundColor, meshColor(input["surface"], .clear))
    XCTAssertTrue(field.subviews.last === editor)
    XCTAssertEqual(editor.text, draft)
    XCTAssertEqual(editor.selectedRange, selection)
    editor.text = ""
    composer.textViewDidChange(editor)
    XCTAssertFalse(placeholder.isHidden)
  }

  @MainActor
  func testReplyControlsShareTheNativeComposerSurface() throws {
    let draft = "Первая строка\nВторая 👋"
    let messenger = TestMessenger()
    let composer = MeshComposer(frame: CGRect(x: 0, y: 0, width: 256, height: 128),
      id: 1, input: appearance(dark: false).merging([
        "text": draft, "start": 1, "end": 5, "visualOutset": 8,
        "reply": [
          "author": "Мира", "text": "На месте", "openLabel": "Исходное сообщение",
          "cancelLabel": "Отменить ответ",
        ],
      ]) { _, value in value }, messenger: messenger)
    let root = composer.view()
    root.layoutIfNeeded()
    let field = try XCTUnwrap(root.subviews.first)
    let glass = try XCTUnwrap(field.subviews.first as? UIVisualEffectView)
    let contents = glass.isUserInteractionEnabled ? glass.contentView : field
    let editor = try XCTUnwrap(contents.subviews.last as? UITextView)
    let quote = try XCTUnwrap(contents.subviews.dropLast().last)
    XCTAssertFalse(quote.isHidden)
    XCTAssertGreaterThan(quote.bounds.height, 0)
    XCTAssertEqual(quote.frame.maxY, editor.frame.minY)
    XCTAssertEqual(editor.frame.maxY, field.bounds.maxY)
    XCTAssertEqual(editor.text, draft)
    XCTAssertEqual(editor.selectedRange, NSRange(location: 1, length: 4))
    let controls = try XCTUnwrap(quote.subviews.first).subviews.compactMap { $0 as? UIControl }
    XCTAssertEqual(controls.count, 2)
    controls.forEach { $0.sendActions(for: .touchUpInside) }
    XCTAssertEqual(Array(messenger.methods.suffix(2)), ["openReply", "cancelReply"])
  }

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
      ("profile action", ["symbol": "bubble.left", "label": "Чат", "stacked": true, "verticalVisualOutset": 24]),
    ]

    for dark in [false, true] {
      for (name, properties) in controls {
        let input = appearance(dark: dark).merging(properties) { _, value in value }
          .merging(["visualOutset": 8]) { _, value in value }
        let profileAction = name == "profile action"
        let messenger = TestMessenger()
        let control = MeshControlSurface(
          frame: CGRect(x: 0, y: 0, width: 176, height: profileAction ? 120 : 64),
          channel: channel(messenger),
          input: input
        )
        let root = control.view()
        root.layoutIfNeeded()
        let button = try XCTUnwrap(root.subviews.compactMap { $0 as? UIButton }.first)
        XCTAssertFalse(root.clipsToBounds)
        if profileAction {
          XCTAssertEqual(button.frame, CGRect(x: 8, y: 24, width: 160, height: 72))
          XCTAssertNil(root.hitTest(CGPoint(x: 88, y: 23), with: nil))
          XCTAssertTrue(root.hitTest(CGPoint(x: 88, y: 25), with: nil) === button)
        } else {
          XCTAssertEqual(button.bounds.height, name == "attach" ? 40 : name == "location action" ? 48 : 44)
        }
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
  func testNativeSearchKeepsEditableTextAboveUntintedGlassWhileCovered() throws {
    for dark in [false, true] {
      let input = appearance(dark: dark).merging([
        "placeholder": "Search", "initialText": "Node", "autofocus": false,
        "expandsFromCorner": true, "active": true,
      ]) { _, value in value }
      let search = MeshSearchField(
        frame: CGRect(x: 0, y: 0, width: 200, height: 48),
        channel: channel(),
        input: input
      )
      let view = search.view()
      let backdrop = try XCTUnwrap(view.subviews.first as? UIVisualEffectView)
      let editor = try XCTUnwrap(view.subviews.last as? UITextField)
      let initialEffect = backdrop.effect
      let initialBackground = backdrop.backgroundColor
      let reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
      XCTAssertFalse(view.clipsToBounds)
      XCTAssertFalse(backdrop.isUserInteractionEnabled)
      XCTAssertTrue(view.isUserInteractionEnabled)
      XCTAssertFalse(view.accessibilityElementsHidden)

      for covered in [true, false] {
        let state = "dark=\(dark), covered=\(covered)"
        search.update(input.merging(["coveredByModal": covered]) { _, value in value })
        XCTAssertTrue(search.view() === view, state)
        if reduceTransparency {
          XCTAssertNil(initialEffect, state)
          XCTAssertNil(backdrop.effect, state)
        } else if #available(iOS 26.0, *) {
          XCTAssertTrue(initialEffect is UIGlassEffect, state)
          let glass = try XCTUnwrap(backdrop.effect as? UIGlassEffect, state)
          XCTAssertNil(glass.tintColor, state)
        } else {
          XCTAssertTrue(backdrop.effect is UIBlurEffect, state)
        }
        XCTAssertEqual(backdrop.backgroundColor, initialBackground, state)
        XCTAssertTrue(view.subviews.last === editor, state)
        XCTAssertEqual(editor.text, "Node", state)
        XCTAssertEqual(view.isUserInteractionEnabled, !covered, state)
        XCTAssertEqual(view.accessibilityElementsHidden, covered, state)
      }
      search.update(input.merging(["highContrast": true]) { _, value in value })
      XCTAssertNil(backdrop.effect)
      XCTAssertEqual(backdrop.backgroundColor, meshColor(input["surface"], .clear))
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
