// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import Flutter
import UIKit

final class MeshComposerFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(_ messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier id: Int64, arguments args: Any?) -> FlutterPlatformView {
    MeshComposer(frame: frame, id: id, input: args as? [String: Any] ?? [:], messenger: messenger)
  }
}

private class MeshInputGlass: UIVisualEffectView {
  override func layoutSubviews() {
    super.layoutSubviews()
    if #available(iOS 26.0, *) {
      cornerConfiguration = .capsule()
    } else {
      layer.cornerRadius = bounds.height / 2
    }
  }

  func applyMaterial(surface: UIColor) {
    backgroundColor = .clear
    if UIAccessibility.isReduceTransparencyEnabled {
      effect = nil
      backgroundColor = surface
    } else if #available(iOS 26.0, *) {
      let material = UIGlassEffect(style: .regular)
      material.tintColor = surface.withAlphaComponent(0.22)
      effect = material
    } else {
      effect = UIBlurEffect(style: .systemThickMaterial)
    }
    let light = overrideUserInterfaceStyle == .light
    layer.borderWidth = light ? 1 : 0
    layer.borderColor = light ? meshLightGlassOutline.cgColor : nil
  }
}

private final class ComposerTextView: UITextView {
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

private final class MeshComposer: NSObject, FlutterPlatformView, UITextViewDelegate {
  private let container = UIView()
  private let textView: ComposerTextView
  private let placeholder = UILabel()
  private let channel: FlutterMethodChannel
  private var reportedHeight: CGFloat = 0

  init(frame: CGRect, id: Int64, input: [String: Any], messenger: FlutterBinaryMessenger) {
    textView = ComposerTextView(frame: frame)
    channel = FlutterMethodChannel(name: "meshgrame/composer/\(id)", binaryMessenger: messenger)
    super.init()
    container.frame = frame
    container.backgroundColor = .clear
    container.addSubview(textView)
    textView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      textView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      textView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      textView.topAnchor.constraint(equalTo: container.topAnchor),
      textView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    textView.delegate = self
    textView.backgroundColor = .clear
    textView.textContainerInset = UIEdgeInsets(top: 12, left: 22, bottom: 12, right: 22)
    textView.textContainer.lineFragmentPadding = 0
    textView.autocapitalizationType = .sentences
    textView.adjustsFontForContentSizeCategory = true
    textView.font = .preferredFont(forTextStyle: .body)
    textView.text = input["text"] as? String ?? ""

    placeholder.translatesAutoresizingMaskIntoConstraints = false
    placeholder.font = textView.font
    placeholder.adjustsFontForContentSizeCategory = true
    placeholder.isAccessibilityElement = false
    placeholder.isUserInteractionEnabled = false
    textView.addSubview(placeholder)
    NSLayoutConstraint.activate([
      placeholder.leadingAnchor.constraint(equalTo: textView.frameLayoutGuide.leadingAnchor, constant: 22),
      placeholder.topAnchor.constraint(equalTo: textView.frameLayoutGuide.topAnchor, constant: 12),
      placeholder.trailingAnchor.constraint(lessThanOrEqualTo: textView.frameLayoutGuide.trailingAnchor, constant: -22),
    ])
    textView.onLayout = { [weak self] in self?.updateHeight() }
    updateAppearance(input)
    updatePlaceholder()

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "appearance":
        if let appearance = call.arguments as? [String: Any] { self.updateAppearance(appearance) }
      case "dismissKeyboard":
        self.textView.resignFirstResponder()
      case "focus":
        self.textView.becomeFirstResponder()
      case "replaceText":
        if let value = call.arguments as? String, value != self.textView.text {
          self.textView.text = value
          self.updatePlaceholder()
          self.updateHeight()
        }
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { container }

  func textViewDidChange(_ textView: UITextView) {
    updatePlaceholder()
    updateHeight()
    channel.invokeMethod("text", arguments: textView.text ?? "")
  }

  private func updatePlaceholder() {
    placeholder.isHidden = !textView.text.isEmpty
  }

  private func updateHeight() {
    guard textView.bounds.width > 36 else { return }
    let lineHeight = textView.font?.lineHeight ?? 22
    let maximum = min(160, ceil(lineHeight * 4 + 24))
    let measured = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height
    let desired = min(maximum, max(46, ceil(measured)))
    if textView.isScrollEnabled != (measured > maximum) { textView.isScrollEnabled = measured > maximum }
    guard desired != reportedHeight else { return }
    reportedHeight = desired
    channel.invokeMethod("height", arguments: Double(desired))
  }

  private func updateAppearance(_ input: [String: Any]) {
    let covered = input["coveredByModal"] as? Bool == true
    container.isUserInteractionEnabled = !covered
    container.accessibilityElementsHidden = covered
    if covered && textView.isFirstResponder { textView.resignFirstResponder() }
    let dark = input["dark"] as? Bool ?? false
    container.overrideUserInterfaceStyle = dark ? .dark : .light
    textView.keyboardAppearance = dark ? .dark : .light
    textView.textColor = color(input["foreground"], .label)
    textView.tintColor = color(input["accent"], .systemBlue)
    placeholder.textColor = color(input["secondary"], .placeholderText)
    placeholder.text = input["placeholder"] as? String
    textView.accessibilityLabel = placeholder.text
  }

  private func color(_ input: Any?, _ fallback: UIColor) -> UIColor {
    guard let n = (input as? NSNumber)?.uint32Value else { return fallback }
    return UIColor(red: CGFloat(n >> 16 & 255) / 255, green: CGFloat(n >> 8 & 255) / 255,
                   blue: CGFloat(n & 255) / 255, alpha: CGFloat(n >> 24 & 255) / 255)
  }
}

private final class SearchGlass: MeshInputGlass {
  var onAttach: (() -> Void)?
  var onLayout: (() -> Void)?

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil { onAttach?() }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

final class MeshSearchField: NSObject, FlutterPlatformView, UITextFieldDelegate {
  private let glass = SearchGlass(effect: nil)
  private let field = UITextField()
  private let icon = UIImageView(image: UIImage(systemName: "magnifyingglass",
    withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)))
  private let cornerButton = UIButton(type: .system)
  private let channel: FlutterMethodChannel
  private let cornerSearch: Bool
  private var surface: UIColor = .secondarySystemBackground
  private var pendingFocus = true
  private var cornerActive = false

  init(frame: CGRect, channel: FlutterMethodChannel, input: [String: Any]) {
    self.channel = channel
    cornerSearch = input["cornerSearch"] as? Bool == true
    super.init()
    pendingFocus = !cornerSearch && (input["autofocus"] as? Bool ?? true)
    field.text = input["initialText"] as? String
    glass.frame = frame
    glass.clipsToBounds = true
    glass.layer.cornerCurve = .continuous
    glass.onAttach = { [weak self] in self?.focusWhenReady() }

    icon.frame = CGRect(x: 0, y: 0, width: 28, height: 22)
    icon.contentMode = .left
    icon.isAccessibilityElement = false
    field.leftView = icon
    field.leftViewMode = .always
    field.clearButtonMode = .always
    field.autocapitalizationType = .none
    field.returnKeyType = .search
    field.delegate = self
    field.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
    field.translatesAutoresizingMaskIntoConstraints = false
    glass.contentView.addSubview(field)
    NSLayoutConstraint.activate([
      field.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 14),
      field.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -12),
      field.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
      field.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
    ])
    if cornerSearch {
      cornerButton.setImage(UIImage(systemName: "magnifyingglass",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)),
        for: .normal)
      cornerButton.addTarget(self, action: #selector(activateSearch), for: .touchUpInside)
      cornerButton.translatesAutoresizingMaskIntoConstraints = false
      glass.contentView.addSubview(cornerButton)
      NSLayoutConstraint.activate([
        cornerButton.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
        cornerButton.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
        cornerButton.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
        cornerButton.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
      ])
      glass.onLayout = { [weak self] in self?.layoutCornerSearch() }
    }
    NotificationCenter.default.addObserver(self, selector: #selector(updateGlass),
      name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
    update(input)
    channel.setMethodCallHandler { [weak self] call, result in
      switch (call.method, call.arguments) {
      case ("update", let input as [String: Any]): self?.update(input)
      case ("dismissKeyboard", _): self?.dismissKeyboard()
      default: return result(FlutterMethodNotImplemented)
      }
      result(nil)
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { glass }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    dismissKeyboard()
    return false
  }

  func textFieldShouldClear(_ textField: UITextField) -> Bool {
    textField.text = ""
    textDidChange()
    return false
  }

  private func dismissKeyboard() {
    pendingFocus = false
    field.resignFirstResponder()
  }

  private func focusWhenReady() {
    guard pendingFocus,
      glass.window != nil,
      !cornerSearch || glass.bounds.width >= 120 else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.pendingFocus, self.glass.window != nil else { return }
      self.pendingFocus = false
      self.field.becomeFirstResponder()
    }
  }

  private func layoutCornerSearch() {
    let progress = min(1, max(0, (glass.bounds.width - 48) / 72))
    field.alpha = progress
    cornerButton.alpha = 1 - progress
    focusWhenReady()
  }

  @objc private func activateSearch() {
    channel.invokeMethod("select", arguments: 0)
  }

  @objc private func textDidChange() {
    channel.invokeMethod("text", arguments: field.text ?? "")
  }

  @objc private func updateGlass() {
    glass.applyMaterial(surface: surface)
  }

  func update(_ input: [String: Any]) {
    let dark = input["dark"] as? Bool == true
    let interfaceStyle: UIUserInterfaceStyle = dark ? .dark : .light
    let themeChanged = glass.overrideUserInterfaceStyle != interfaceStyle
    let covered = input["coveredByModal"] as? Bool == true
    glass.isUserInteractionEnabled = !covered
    glass.accessibilityElementsHidden = covered
    if covered { dismissKeyboard() }
    glass.overrideUserInterfaceStyle = interfaceStyle
    field.keyboardAppearance = dark ? .dark : .light
    let titleSize = (input["titleSize"] as? NSNumber)?.doubleValue ?? 17
    field.font = .systemFont(ofSize: titleSize)
    field.textColor = meshColor(input["foreground"], .label)
    field.tintColor = meshColor(input["accent"], .systemBlue)
    let secondary = meshColor(input["secondary"], .secondaryLabel)
    icon.tintColor = secondary
    let placeholder = input["placeholder"] as? String ?? ""
    field.accessibilityLabel = placeholder
    field.attributedPlaceholder = NSAttributedString(string: placeholder,
      attributes: [.foregroundColor: secondary])
    if cornerSearch {
      let active = input["active"] as? Bool == true
      if active != cornerActive {
        cornerActive = active
        if active {
          pendingFocus = input["autofocus"] as? Bool ?? true
        } else {
          dismissKeyboard()
          field.text = ""
        }
      }
      cornerButton.accessibilityLabel = placeholder
      cornerButton.tintColor = field.textColor
      cornerButton.isUserInteractionEnabled = !active
      cornerButton.isAccessibilityElement = !active
      field.isUserInteractionEnabled = active
      field.isAccessibilityElement = active
      layoutCornerSearch()
    }
    let nextSurface = meshColor(input["surface"], .secondarySystemBackground)
    if nextSurface != surface || themeChanged {
      surface = nextSurface
      updateGlass()
    }
  }
}
