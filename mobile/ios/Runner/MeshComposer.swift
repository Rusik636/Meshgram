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
  var maximumRadius: Double?

  override func layoutSubviews() {
    super.layoutSubviews()
    if #available(iOS 26.0, *) {
      cornerConfiguration = .capsule(maximumRadius: maximumRadius)
    } else {
      layer.cornerRadius = min(maximumRadius.map { CGFloat($0) } ?? .greatestFiniteMagnitude, bounds.height / 2)
    }
  }

  func applyMaterial(surface: UIColor, opaque: Bool) {
    backgroundColor = .clear
    if opaque || UIAccessibility.isReduceTransparencyEnabled {
      effect = nil
      backgroundColor = surface
    } else if #available(iOS 26.0, *) {
      effect = UIGlassEffect(style: .regular)
    } else {
      effect = UIBlurEffect(style: .systemThickMaterial)
    }
  }
}

private final class ComposerTextView: UITextView {
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

private final class ComposerSurface: UIView {
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

private final class ComposerAccessory: UIView {
  let open = UIControl()
  let cancel = UIButton(type: .system)
  private let author = UILabel()
  private let excerpt = UILabel()
  private let accentLine = UIView()
  private let thumbnail = UIImageView()
  private let content = UIView()
  private var contentHeight: NSLayoutConstraint?
  private var thumbnailWidth: NSLayoutConstraint?

  var preferredHeight: CGFloat {
    guard !isHidden else { return 0 }
    return max(44, ceil(author.font.lineHeight + excerpt.font.lineHeight + 12))
  }

  init() {
    super.init(frame: .zero)
    isHidden = true
    clipsToBounds = true
    excerpt.font = .preferredFont(forTextStyle: .caption1)
    for label in [author, excerpt] {
      label.adjustsFontForContentSizeCategory = true
      label.lineBreakMode = .byTruncatingTail
    }
    author.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
      for: .systemFont(ofSize: 12, weight: .semibold))
    accentLine.layer.cornerRadius = 1
    accentLine.isUserInteractionEnabled = false
    thumbnail.contentMode = .scaleAspectFill
    thumbnail.clipsToBounds = true
    thumbnail.layer.cornerRadius = 6
    open.isAccessibilityElement = true
    open.accessibilityTraits = .button
    cancel.setImage(UIImage(systemName: "xmark",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)), for: .normal)
    let labels = UIStackView(arrangedSubviews: [author, excerpt])
    labels.axis = .vertical
    labels.isUserInteractionEnabled = false
    for (view, parent) in [(content, self), (open, content), (cancel, content),
      (accentLine, open), (labels, open), (thumbnail, open)] {
      view.translatesAutoresizingMaskIntoConstraints = false
      parent.addSubview(view)
    }
    let height = content.heightAnchor.constraint(equalToConstant: 44)
    contentHeight = height
    let thumbnailWidth = thumbnail.widthAnchor.constraint(equalToConstant: 0)
    self.thumbnailWidth = thumbnailWidth
    NSLayoutConstraint.activate([
      height,
      thumbnailWidth,
      content.leadingAnchor.constraint(equalTo: leadingAnchor),
      content.trailingAnchor.constraint(equalTo: trailingAnchor),
      content.bottomAnchor.constraint(equalTo: bottomAnchor),
      open.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      open.trailingAnchor.constraint(equalTo: cancel.leadingAnchor),
      open.topAnchor.constraint(equalTo: content.topAnchor),
      open.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      cancel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      cancel.widthAnchor.constraint(equalToConstant: 44),
      cancel.topAnchor.constraint(equalTo: content.topAnchor),
      cancel.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      accentLine.leadingAnchor.constraint(equalTo: open.leadingAnchor, constant: 22),
      accentLine.widthAnchor.constraint(equalToConstant: 2),
      accentLine.topAnchor.constraint(equalTo: labels.topAnchor),
      accentLine.bottomAnchor.constraint(equalTo: labels.bottomAnchor),
      labels.leadingAnchor.constraint(equalTo: accentLine.trailingAnchor, constant: 7),
      labels.trailingAnchor.constraint(equalTo: thumbnail.leadingAnchor, constant: -4),
      labels.centerYAnchor.constraint(equalTo: open.centerYAnchor),
      thumbnail.trailingAnchor.constraint(equalTo: open.trailingAnchor),
      thumbnail.centerYAnchor.constraint(equalTo: open.centerYAnchor),
      thumbnail.heightAnchor.constraint(equalTo: thumbnail.widthAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    let height = max(44, preferredHeight)
    if contentHeight?.constant != height { contentHeight?.constant = height }
    super.layoutSubviews()
  }

  func update(_ input: [String: Any]) {
    isHidden = input["title"] == nil
    author.text = input["title"] as? String
    excerpt.text = input["text"] as? String
    let image = (input["image"] as? FlutterStandardTypedData).flatMap { UIImage(data: $0.data) }
    thumbnail.image = image
    thumbnailWidth?.constant = image == nil ? 0 : 32
    open.accessibilityLabel = [author.text, excerpt.text].compactMap { $0 }.joined(separator: ", ")
    open.accessibilityHint = input["openLabel"] as? String
    cancel.accessibilityLabel = input["dismissLabel"] as? String
  }

  func applyColors(accent: UIColor, foreground: UIColor, secondary: UIColor) {
    accentLine.backgroundColor = accent
    author.textColor = accent
    excerpt.textColor = foreground
    cancel.tintColor = secondary
  }
}

final class MeshComposer: NSObject, FlutterPlatformView, UITextViewDelegate, UIGestureRecognizerDelegate {
  private let container = UIView()
  private let fieldContainer = ComposerSurface()
  private var glass = MeshInputGlass(effect: nil)
  private var nativeInteractive: Bool?
  private let textView: ComposerTextView
  private let accessory = ComposerAccessory()
  private let placeholder = UILabel()
  private let channel: FlutterMethodChannel
  private var reportedHeight: CGFloat = 0
  private var textHeight: CGFloat = 46
  private var reservesAccessorySpace = false
  private var surface: UIColor = .secondarySystemBackground
  private var highContrast = false
  private var press: UILongPressGestureRecognizer?
  private var applyingEditing = false
  private var pendingFocus = false

  init(frame: CGRect, id: Int64, input: [String: Any], messenger: FlutterBinaryMessenger) {
    textView = ComposerTextView(frame: frame)
    channel = FlutterMethodChannel(name: "meshgrame/composer/\(id)", binaryMessenger: messenger)
    super.init()
    container.frame = frame
    container.backgroundColor = .clear

    let outset = CGFloat((input["visualOutset"] as? NSNumber)?.doubleValue ?? 0)
    fieldContainer.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(fieldContainer)
    NSLayoutConstraint.activate([
      fieldContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: outset),
      fieldContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -outset),
      fieldContainer.topAnchor.constraint(equalTo: container.topAnchor, constant: outset),
      fieldContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -outset),
    ])
    textView.delegate = self
    textView.backgroundColor = .clear
    textView.textContainerInset = UIEdgeInsets(top: 12, left: 22, bottom: 12, right: 22)
    textView.textContainer.lineFragmentPadding = 0
    textView.autocapitalizationType = .sentences
    textView.adjustsFontForContentSizeCategory = true
    textView.font = .preferredFont(forTextStyle: .body)
    applyEditing(input)

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
    textView.onLayout = { [weak self] in
      self?.updateHeight()
      self?.focusWhenReady()
    }
    fieldContainer.onLayout = { [weak self] in self?.layoutEditor() }
    accessory.open.addTarget(self, action: #selector(openAccessory), for: .touchUpInside)
    accessory.cancel.addTarget(self, action: #selector(dismissAccessory), for: .touchUpInside)
    accessory.update(input["accessory"] as? [String: Any] ?? [:])
    reservesAccessorySpace = !accessory.isHidden

    let press = UILongPressGestureRecognizer(target: self, action: #selector(pressChanged))
    press.minimumPressDuration = 0
    press.cancelsTouchesInView = false
    press.delaysTouchesBegan = false
    press.delaysTouchesEnded = false
    press.delegate = self
    fieldContainer.addGestureRecognizer(press)
    self.press = press

    NotificationCenter.default.addObserver(self, selector: #selector(updateGlass),
      name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(updateGlass),
      name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    updateAppearance(input)
    updatePlaceholder()

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "appearance":
        if let appearance = call.arguments as? [String: Any] { self.updateAppearance(appearance) }
      case "dismissKeyboard":
        self.pendingFocus = false
        self.textView.resignFirstResponder()
      case "focus":
        self.pendingFocus = self.container.isUserInteractionEnabled
        self.focusWhenReady()
      case "textBounds":
        let textBounds = self.textView.bounds.inset(by: self.textView.textContainerInset)
          .insetBy(dx: self.textView.textContainer.lineFragmentPadding, dy: 0)
        let rect = self.textView.convert(textBounds, to: self.container)
        result([rect.minX, rect.minY, rect.width, rect.height])
        return
      case "editing":
        if let value = call.arguments as? [String: Any] {
          self.applyEditing(value)
          self.updatePlaceholder()
          // The initial height may have been measured before Flutter connected the channel.
          self.updateHeight(force: true)
        }
      case "accessory":
        self.accessory.update(call.arguments as? [String: Any] ?? [:])
        if !self.accessory.isHidden { self.reservesAccessorySpace = true }
        self.fieldContainer.setNeedsLayout()
        self.updateHeight()
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { container }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    gestureRecognizer === press
  }

  @objc private func pressChanged(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      setGlassPressed(true)
    case .ended, .cancelled, .failed:
      setGlassPressed(false)
    default:
      break
    }
  }

  private func setGlassPressed(_ pressed: Bool) {
    let transform = pressed ? CGAffineTransform(scaleX: 0.985, y: 0.94) : .identity
    let duration: TimeInterval = pressed ? 0.15 : 0.38
    UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.65,
      initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
      self.glass.transform = transform
    }
  }

  private func updatePressAvailability() {
    let enabled = nativeInteractive != true && container.isUserInteractionEnabled &&
      !UIAccessibility.isReduceMotionEnabled
    press?.isEnabled = enabled
    if !enabled && nativeInteractive == false {
      glass.layer.removeAllAnimations()
      glass.transform = .identity
    }
  }

  @objc private func openAccessory() {
    channel.invokeMethod("openAccessory", arguments: nil)
  }

  @objc private func dismissAccessory() {
    channel.invokeMethod("dismissAccessory", arguments: nil)
  }

  private func layoutEditor() {
    let bounds = fieldContainer.bounds
    if accessory.isHidden && bounds.height <= textHeight + 0.5 {
      reservesAccessorySpace = false
    }
    let editorHeight = reservesAccessorySpace ? min(bounds.height, textHeight) : bounds.height
    let editorTop = bounds.height - editorHeight
    accessory.frame = CGRect(x: 0, y: 0, width: bounds.width, height: editorTop)
    textView.frame = CGRect(x: 0, y: editorTop, width: bounds.width, height: editorHeight)
  }

  @objc private func updateGlass() {
    let opaque = highContrast || UIAccessibility.isReduceTransparencyEnabled
    var interactive = false
    if #available(iOS 26.0, *) {
      interactive = !opaque && !UIAccessibility.isReduceMotionEnabled
    }
    if nativeInteractive != interactive {
      nativeInteractive = interactive
      let effect: UIVisualEffect?
      if #available(iOS 26.0, *), interactive {
        let material = UIGlassEffect(style: .regular)
        material.isInteractive = true
        effect = material
      } else {
        effect = nil
      }
      // UIKit attaches its press interaction when the effect view is created.
      let replacement = MeshInputGlass(effect: effect)
      replacement.maximumRadius = 23
      replacement.frame = fieldContainer.bounds
      replacement.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      replacement.layer.cornerCurve = .continuous
      replacement.clipsToBounds = !interactive
      replacement.isUserInteractionEnabled = interactive
      replacement.accessibilityElementsHidden = !interactive
      fieldContainer.insertSubview(replacement, at: 0)
      let wasFocused = textView.isFirstResponder
      let selection = textView.selectedRange
      let parent = interactive ? replacement.contentView : fieldContainer
      parent.addSubview(accessory)
      parent.addSubview(textView)
      layoutEditor()
      glass.removeFromSuperview()
      glass = replacement
      if wasFocused && !textView.isFirstResponder { textView.becomeFirstResponder() }
      textView.selectedRange = selection
    }
    if !interactive { glass.applyMaterial(surface: surface, opaque: highContrast) }
    updatePressAvailability()
  }

  func textViewDidChange(_ textView: UITextView) {
    updatePlaceholder()
    updateHeight()
    reportEditing()
  }

  func textViewDidChangeSelection(_ textView: UITextView) {
    reportEditing()
  }

  private func reportEditing() {
    let range = textView.selectedRange
    guard !applyingEditing, range.location != NSNotFound else { return }
    channel.invokeMethod("editing", arguments: [
      "text": textView.text ?? "",
      "start": range.location,
      "end": NSMaxRange(range),
    ])
  }

  private func applyEditing(_ input: [String: Any]) {
    guard let text = input["text"] as? String else { return }
    applyingEditing = true
    defer { applyingEditing = false }
    let length = text.utf16.count
    let start = min(length, max(0, input["start"] as? Int ?? length))
    let end = min(length, max(start, input["end"] as? Int ?? start))
    if textView.text != text { textView.text = text }
    let range = NSRange(location: start, length: end - start)
    if textView.selectedRange != range { textView.selectedRange = range }
  }

  private func focusWhenReady() {
    guard pendingFocus, textView.window != nil else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.pendingFocus, self.textView.window != nil else { return }
      self.pendingFocus = false
      if !self.textView.isFirstResponder { self.textView.becomeFirstResponder() }
    }
  }

  private func updatePlaceholder() {
    placeholder.isHidden = !textView.text.isEmpty
  }

  private func updateHeight(force: Bool = false) {
    guard textView.bounds.width > 36 else { return }
    let lineHeight = textView.font?.lineHeight ?? 22
    let maximum = min(160, ceil(lineHeight * 4 + 24))
    let measured = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height
    let editorHeight = min(maximum, max(46, ceil(measured)))
    if textHeight != editorHeight {
      textHeight = editorHeight
      fieldContainer.setNeedsLayout()
    }
    let desired = editorHeight + accessory.preferredHeight
    if textView.isScrollEnabled != (measured > maximum) { textView.isScrollEnabled = measured > maximum }
    guard force || desired != reportedHeight else { return }
    reportedHeight = desired
    channel.invokeMethod("height", arguments: Double(desired))
  }

  func updateAppearance(_ input: [String: Any]) {
    let covered = input["coveredByModal"] as? Bool == true
    container.isUserInteractionEnabled = !covered
    container.accessibilityElementsHidden = covered
    if covered {
      pendingFocus = false
      if textView.isFirstResponder { textView.resignFirstResponder() }
    }
    let dark = input["dark"] as? Bool ?? false
    let style: UIUserInterfaceStyle = dark ? .dark : .light
    let nextSurface = meshColor(input["surface"], .secondarySystemBackground)
    let nextContrast = input["highContrast"] as? Bool == true
    if nativeInteractive == nil || style != container.overrideUserInterfaceStyle ||
      nextSurface != surface || nextContrast != highContrast {
      container.overrideUserInterfaceStyle = style
      surface = nextSurface
      highContrast = nextContrast
      updateGlass()
    }
    textView.keyboardAppearance = dark ? .dark : .light
    let foreground = meshColor(input["foreground"], .label)
    let accent = meshColor(input["accent"], .systemBlue)
    let secondary = meshColor(input["secondary"], .placeholderText)
    textView.textColor = foreground
    textView.tintColor = accent
    textView.alpha = input["hidesMovingText"] as? Bool == true ? 0 : 1
    placeholder.textColor = secondary
    accessory.applyColors(accent: accent, foreground: foreground, secondary: secondary)
    placeholder.text = input["placeholder"] as? String
    textView.accessibilityLabel = placeholder.text
    updatePressAvailability()
  }
}

private final class SearchContainer: UIView {
  var onLayout: (() -> Void)?

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil { onLayout?() }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

final class MeshSearchField: NSObject, FlutterPlatformView, UITextFieldDelegate {
  private let root: SearchContainer
  private let glass = MeshInputGlass(effect: nil)
  private let field = UITextField()
  private let icon = UIImageView(image: UIImage(systemName: "magnifyingglass",
    withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)))
  private let channel: FlutterMethodChannel
  private let expandsFromCorner: Bool
  private var surface: UIColor = .secondarySystemBackground
  private var highContrast = false
  private var pendingFocus = false
  private var active = false

  init(frame: CGRect, channel: FlutterMethodChannel, input: [String: Any]) {
    self.channel = channel
    root = SearchContainer(frame: frame)
    expandsFromCorner = input["expandsFromCorner"] as? Bool == true
    super.init()
    field.text = input["initialText"] as? String
    glass.frame = root.bounds
    glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    glass.clipsToBounds = true
    glass.layer.cornerCurve = .continuous
    glass.isUserInteractionEnabled = false
    glass.accessibilityElementsHidden = true
    root.addSubview(glass)
    root.onLayout = { [weak self] in self?.layoutEditor() }

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
    root.addSubview(field)
    NSLayoutConstraint.activate([
      field.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
      field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
      field.topAnchor.constraint(equalTo: root.topAnchor),
      field.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
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

  func view() -> UIView { root }

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
      root.window != nil,
      !expandsFromCorner || root.bounds.width >= 120 else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.pendingFocus, self.root.window != nil else { return }
      self.pendingFocus = false
      self.field.becomeFirstResponder()
    }
  }

  private func layoutEditor() {
    if expandsFromCorner {
      field.alpha = min(1, max(0, (root.bounds.width - 48) / 72))
    }
    focusWhenReady()
  }

  @objc private func textDidChange() {
    channel.invokeMethod("text", arguments: field.text ?? "")
  }

  @objc private func updateGlass() {
    glass.applyMaterial(surface: surface, opaque: highContrast)
  }

  func update(_ input: [String: Any]) {
    let dark = input["dark"] as? Bool == true
    let interfaceStyle: UIUserInterfaceStyle = dark ? .dark : .light
    let themeChanged = root.overrideUserInterfaceStyle != interfaceStyle
    let covered = input["coveredByModal"] as? Bool == true
    let nextActive = input["active"] as? Bool ?? true
    root.isUserInteractionEnabled = nextActive && !covered
    root.accessibilityElementsHidden = !root.isUserInteractionEnabled
    if nextActive != active {
      active = nextActive
      pendingFocus = active && (input["autofocus"] as? Bool ?? true)
      if !active {
        dismissKeyboard()
        field.text = ""
      }
    }
    if covered { dismissKeyboard() }
    root.overrideUserInterfaceStyle = interfaceStyle
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
    let nextSurface = meshColor(input["surface"], .secondarySystemBackground)
    let nextContrast = input["highContrast"] as? Bool == true
    if nextSurface != surface || nextContrast != highContrast || themeChanged {
      surface = nextSurface
      highContrast = nextContrast
      updateGlass()
    }
    layoutEditor()
  }
}
