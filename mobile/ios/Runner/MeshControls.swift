// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import Flutter
import UIKit

let meshChatSymbol = "bubble.left"
// Tint for the attachment transition and navigation controls on older iOS versions.
func meshPanelTint(dark: Bool) -> UIColor {
  UIColor(white: 1, alpha: dark ? 0.025 : 0.10)
}

final class MeshControlsFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(_ messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier id: Int64, arguments args: Any?) -> FlutterPlatformView {
    let input = args as? [String: Any] ?? [:]
    let kind = input["kind"] as? String
    if kind == "sheetDim" || kind == "messagePreview" {
      let surface = MeshPassiveSurface(frame: frame)
      let color = meshColor(input["color"], .black)
      surface.backgroundColor = kind == "sheetDim"
        ? color.withAlphaComponent(CGFloat(input["opacity"] as? Double ?? 0.25))
        : .clear
      return surface
    }
    let channel = FlutterMethodChannel(name: "meshgrame/controls/\(id)", binaryMessenger: messenger)
    if kind == "chatPreviewBackdrop" {
      return MeshChatPreviewBackdrop(frame: frame, channel: channel, input: input)
    }
    if input["kind"] as? String == "messageGlass" {
      return MeshMessageGlass(frame: frame, input: input)
    }
    if input["kind"] as? String == "modalGlass" {
      return MeshModalGlass(frame: frame, channel: channel, input: input)
    }
    if input["kind"] as? String == "tabs" {
      return MeshTabs(frame, channel, input)
    }
    if input["kind"] as? String == "chatSearch" {
      return MeshSearchField(frame: frame, channel: channel, input: input)
    }
    if let kind = input["kind"] as? String, kind == "chatIcon" || kind == "symbolIcon" {
      return MeshSymbolIcon(frame: frame, channel: channel, input: input)
    }
    return MeshControlSurface(frame: frame, channel: channel, input: input)
  }
}

private final class MeshPassiveSurface: UIView, FlutterPlatformView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    accessibilityElementsHidden = true
  }

  required init?(coder: NSCoder) { nil }
  func view() -> UIView { self }
}

// The chat list mixes Flutter content and UIKit controls. A single UIKit
// effect samples both without clipping the blur to each platform view.
private final class MeshChatPreviewBackdrop: NSObject, FlutterPlatformView {
  private let surface: UIView
  private let blur = UIVisualEffectView()
  private let dim = UIView()
  private let channel: FlutterMethodChannel
  private var animator: UIViewPropertyAnimator?
  private var darkStyle = false

  init(frame: CGRect, channel: FlutterMethodChannel, input: [String: Any]) {
    surface = UIView(frame: frame)
    self.channel = channel
    super.init()
    surface.isUserInteractionEnabled = false
    surface.accessibilityElementsHidden = true
    for layer in [blur, dim] {
      layer.frame = surface.bounds
      layer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      surface.addSubview(layer)
    }
    update(input)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let input = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.update(input)
      result(nil)
    }
  }

  deinit {
    animator?.stopAnimation(true)
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { surface }

  private func update(_ input: [String: Any]) {
    let progress = CGFloat(input["progress"] as? Double ?? 0)
    let dark = input["dark"] as? Bool == true
    let reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
    if input["blur"] as? Bool == true && !reduceTransparency {
      if animator == nil || dark != darkStyle {
        animator?.stopAnimation(true)
        blur.effect = nil
        darkStyle = dark
        let effect = UIBlurEffect(style: dark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)
        let newAnimator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak blur] in
          blur?.effect = effect
        }
        newAnimator.pausesOnCompletion = true
        newAnimator.startAnimation()
        newAnimator.pauseAnimation()
        animator = newAnimator
      }
      animator?.fractionComplete = progress
    } else {
      animator?.stopAnimation(true)
      animator = nil
      blur.effect = nil
    }
    let color = meshColor(input["color"], .black)
    let opacity = reduceTransparency ? max(0.85, color.cgColor.alpha) : color.cgColor.alpha
    dim.backgroundColor = color.withAlphaComponent(opacity * progress)
  }
}

// UIKit may sample Flutter's overlay when a live backdrop sits beneath its
// labels. Give message panels an opaque backing made only from the blurred
// chat. Refraction stays native while the foreground stays sharp.
private final class MeshMessageGlass: UIView, FlutterPlatformView {
  private let background = UIImageView()
  private let dim = UIView()
  private let glass: UIVisualEffectView

  init(frame: CGRect, input: [String: Any]) {
    if #available(iOS 26.0, *) {
      glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    } else {
      glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    }
    super.init(frame: frame)
    let dark = input["dark"] as? Bool == true
    overrideUserInterfaceStyle = dark ? .dark : .light
    backgroundColor = dark ? .black : .white
    if let bytes = input["backdrop"] as? FlutterStandardTypedData {
      background.image = UIImage(data: bytes.data)
    }
    background.contentMode = .scaleToFill
    dim.backgroundColor = meshColor(input["dim"], .clear)
    layer.cornerRadius = CGFloat(input["radius"] as? Double ?? 22)
    layer.cornerCurve = .continuous
    clipsToBounds = true
    isUserInteractionEnabled = false
    accessibilityElementsHidden = true
    addSubview(background)
    addSubview(dim)
    glass.layer.cornerRadius = layer.cornerRadius
    glass.layer.cornerCurve = .continuous
    glass.clipsToBounds = true
    addSubview(glass)
  }

  required init?(coder: NSCoder) { nil }
  func view() -> UIView { self }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if let window {
      background.frame = convert(window.bounds, from: window)
    }
    dim.frame = bounds
    glass.frame = bounds
  }
}

private final class MeshModalGlass: NSObject, FlutterPlatformView {
  private let surface: UIVisualEffectView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, channel: FlutterMethodChannel, input: [String: Any]) {
    let effect: UIVisualEffect
    if #available(iOS 26.0, *) {
      let glass = UIGlassEffect(style: .regular)
      if input["panel"] as? Bool == true {
        glass.tintColor = meshPanelTint(dark: input["dark"] as? Bool == true)
      }
      effect = glass
    } else {
      effect = UIBlurEffect(style: .systemMaterial)
    }
    surface = UIVisualEffectView(effect: effect)
    self.channel = channel
    super.init()
    surface.frame = frame
    surface.overrideUserInterfaceStyle = input["dark"] as? Bool == true ? .dark : .light
    updateRadius(input)
    surface.clipsToBounds = true
    surface.isUserInteractionEnabled = false
    surface.accessibilityElementsHidden = true
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let values = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.updateRadius(values)
      result(nil)
    }
  }

  deinit { channel.setMethodCallHandler(nil) }

  private func updateRadius(_ values: [String: Any]) {
    let radius = values["radius"] as? Double ?? 22
    if #available(iOS 26.0, *) {
      surface.cornerConfiguration = .uniformCorners(radius: .fixed(radius))
    } else {
      surface.layer.cornerRadius = CGFloat(radius)
      surface.layer.cornerCurve = .continuous
    }
  }

  func view() -> UIView { surface }
}

func meshColor(_ input: Any?, _ fallback: UIColor) -> UIColor {
  guard let value = (input as? NSNumber)?.uint32Value else { return fallback }
  return UIColor(red: CGFloat(value >> 16 & 255) / 255,
                 green: CGFloat(value >> 8 & 255) / 255,
                 blue: CGFloat(value & 255) / 255,
                 alpha: CGFloat(value >> 24 & 255) / 255)
}

private final class MeshSymbolIcon: NSObject, FlutterPlatformView {
  private let image: UIImageView
  private let channel: FlutterMethodChannel
  private let pointSize: CGFloat

  init(frame: CGRect, channel: FlutterMethodChannel, input: [String: Any]) {
    image = UIImageView(frame: frame)
    self.channel = channel
    let defaultSize: CGFloat = input["kind"] as? String == "symbolIcon" ? 19 : 35
    pointSize = (input["pointSize"] as? NSNumber).map { CGFloat(truncating: $0) } ?? defaultSize
    super.init()
    image.contentMode = .scaleAspectFit
    image.isAccessibilityElement = false
    image.isUserInteractionEnabled = false
    update(input)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let values = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.update(values)
      result(nil)
    }
  }

  func view() -> UIView { image }

  private func update(_ input: [String: Any]) {
    let symbol = input["symbol"] as? String ?? meshChatSymbol + ".fill"
    let selected = input["selected"] as? Bool == true
    let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    let normal = UIImage(systemName: symbol, withConfiguration: configuration)
    image.image = selected
      ? UIImage(systemName: symbol + ".fill", withConfiguration: configuration) ?? normal
      : normal
    image.tintColor = meshColor(input["accent"], .systemBlue)
  }

  deinit { channel.setMethodCallHandler(nil) }
}

private final class MeshButtonContent: UIButton {
  var hitInset: CGFloat = 0

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    bounds.insetBy(dx: -hitInset, dy: -hitInset).contains(point)
  }
}

private final class MeshButtonHost: UIView {
  let button = MeshButtonContent(type: .system)
  var visualOutset: CGFloat = 0
  var verticalVisualOutset: CGFloat = 0
  var buttonInset: CGFloat = 0
  var stacked = false
  private let legacyGlass: UIVisualEffectView?

  override init(frame: CGRect) {
    if #available(iOS 26.0, *) {
      legacyGlass = nil
    } else {
      legacyGlass = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    }
    super.init(frame: frame)
    if let legacyGlass {
      addSubview(legacyGlass)
      legacyGlass.layer.cornerCurve = .continuous
      legacyGlass.clipsToBounds = true
      legacyGlass.isUserInteractionEnabled = false
    }
    addSubview(button)
  }

  required init?(coder: NSCoder) { nil }

  func updateLegacyGlass(tint: UIColor, reduced: Bool) {
    guard let legacyGlass else { return }
    legacyGlass.isHidden = reduced
    legacyGlass.contentView.backgroundColor = tint
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    button.hitInset = buttonInset
    button.frame = bounds.insetBy(
      dx: visualOutset + buttonInset, dy: verticalVisualOutset + buttonInset
    )
    legacyGlass?.frame = button.frame
    legacyGlass?.layer.cornerRadius = stacked ? 19 : button.bounds.height / 2
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hitBounds = bounds.insetBy(dx: visualOutset, dy: verticalVisualOutset)
    guard isUserInteractionEnabled, !isHidden, button.isEnabled, hitBounds.contains(point) else { return nil }
    return button
  }
}

final class MeshControlSurface: NSObject, FlutterPlatformView {
  private let root: MeshButtonHost
  private let channel: FlutterMethodChannel
  private let kind: String
  private var button: UIButton { root.button }
  private var input: [String: Any] = [:]
  private var observer: NSObjectProtocol?
  private lazy var longPress = UILongPressGestureRecognizer(
    target: self, action: #selector(controlHeld(_:))
  )

  init(frame: CGRect, channel: FlutterMethodChannel, input: [String: Any]) {
    root = MeshButtonHost(frame: frame)
    self.channel = channel
    kind = input["kind"] as? String ?? "button"
    super.init()

    root.visualOutset = (input["visualOutset"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
    root.verticalVisualOutset = (input["verticalVisualOutset"] as? NSNumber)
      .map { CGFloat($0.doubleValue) } ?? root.visualOutset
    button.addAction(UIAction { [weak self] _ in
      guard let self, self.input["enabled"] as? Bool == true else { return }
      self.channel.invokeMethod("select", arguments: 0)
    }, for: .touchUpInside)
    if kind == "chatTitle" || kind == "button" {
      button.addGestureRecognizer(longPress)
    }

    observer = NotificationCenter.default.addObserver(
      forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.refreshAppearance() }
    update(input)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let values = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.update(values)
      result(nil)
    }
  }

  deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { root }

  @objc private func controlHeld(_ gesture: UILongPressGestureRecognizer) {
    if gesture.state == .began { _ = handleLongPress() }
  }

  private func handleLongPress() -> Bool {
    guard root.isUserInteractionEnabled, button.isEnabled,
      input["longPressLabel"] is String else { return false }
    channel.invokeMethod("longPress", arguments: nil)
    return true
  }

  func update(_ values: [String: Any]) {
    var appearance = values
    let covered = appearance.removeValue(forKey: "coveredByModal") as? Bool == true
    root.isUserInteractionEnabled = !covered && values["readOnly"] as? Bool != true
    root.accessibilityElementsHidden = covered
    guard !(input as NSDictionary).isEqual(to: appearance) else { return }
    input = appearance
    refreshAppearance()
  }

  private func chatAvatar() -> UIImage {
    let size = CGSize(width: 35, height: 35)
    return UIGraphicsImageRenderer(size: size).image { image in
      let context = image.cgContext
      let frame = CGRect(origin: .zero, size: size)
      context.saveGState()
      context.addEllipse(in: frame)
      context.clip()
      let top = meshColor(input["avatarTop"], .systemBlue)
      let bottom = meshColor(input["avatarBottom"], .systemIndigo)
      if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: [top.cgColor, bottom.cgColor] as CFArray,
                                   locations: [0, 1]) {
        context.drawLinearGradient(gradient, start: .zero,
                                   end: CGPoint(x: size.width, y: size.height), options: [])
      }
      let text = (input["initials"] as? String ?? "M") as NSString
      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
        .foregroundColor: UIColor.white,
      ]
      let textSize = text.size(withAttributes: attributes)
      text.draw(at: CGPoint(x: (size.width - textSize.width) / 2,
                            y: (size.height - textSize.height) / 2), withAttributes: attributes)
      context.restoreGState()
      if input["online"] as? Bool == true {
        let dot = CGRect(x: size.width - 11, y: size.height - 11, width: 10, height: 10)
        meshColor(input["onlineBorder"], .systemBackground).setFill()
        UIBezierPath(ovalIn: dot).fill()
        meshColor(input["onlineColor"], .systemGreen).setFill()
        UIBezierPath(ovalIn: dot.insetBy(dx: 1.5, dy: 1.5)).fill()
      }
    }.withRenderingMode(.alwaysOriginal)
  }

  private func refreshAppearance() {
    root.overrideUserInterfaceStyle = input["dark"] as? Bool == true ? .dark : .light
    let accent = meshColor(input["accent"], .systemBlue)
    let foreground = meshColor(input["foreground"], .label)
    let surface = meshColor(input["surface"], .secondarySystemBackground)
    let readOnly = input["readOnly"] as? Bool == true

    let primary = input["primary"] as? Bool == true
    let enabled = input["enabled"] as? Bool == true
    let title = input["label"] as? String ?? ""
    let longPressLabel = input["longPressLabel"] as? String
    longPress.isEnabled = longPressLabel != nil
    button.isEnabled = enabled || longPressLabel != nil
    button.accessibilityLabel = title
    button.accessibilityCustomActions = longPressLabel.map { label in
      [UIAccessibilityCustomAction(name: label) { [weak self] _ in
        self?.handleLongPress() ?? false
      }]
    }
    let dark = root.overrideUserInterfaceStyle == .dark
    let symbol = input["symbol"] as? String
    let stacked = input["stacked"] as? Bool == true
    // Keep the larger Flutter hit target around the 44 pt navigation glass and 40 pt paperclip.
    root.buttonInset = symbol == "paperclip" ? 4 : (!stacked && (symbol != nil || kind != "button") ? 2 : 0)
    root.stacked = stacked
    root.setNeedsLayout()

    let reduced = UIAccessibility.isReduceTransparencyEnabled
    var configuration: UIButton.Configuration
    if #available(iOS 26.0, *), !reduced {
      configuration = primary ? .prominentGlass() : .glass()
      if primary {
        configuration.baseBackgroundColor = accent
      }
    } else if reduced {
      configuration = .filled()
      configuration.baseBackgroundColor = primary ? accent : surface
    } else {
      configuration = .plain()
      configuration.background = .clear()
    }
    root.updateLegacyGlass(tint: primary ? accent : meshPanelTint(dark: dark), reduced: reduced)
    let labelColor = primary ? meshColor(input["onAccent"], .white) : foreground
    button.tintColor = labelColor
    configuration.baseForegroundColor = labelColor
    configuration.cornerStyle = .capsule
    if kind == "chatTitle" {
      if readOnly {
        button.accessibilityTraits = [.header, .staticText]
      }
      var heading = AttributedString(title)
      let headingSize = (input["titleFontSize"] as? NSNumber)?.doubleValue ?? 16
      heading.font = UIFont.systemFont(ofSize: headingSize, weight: .semibold)
      heading.foregroundColor = foreground
      configuration.attributedTitle = heading
      if let value = input["subtitle"] as? String {
        var subtitle = AttributedString(value)
        let subtitleSize = (input["subtitleFontSize"] as? NSNumber)?.doubleValue ?? 11
        subtitle.font = UIFont.systemFont(ofSize: subtitleSize)
        subtitle.foregroundColor = meshColor(input["secondary"], .secondaryLabel)
        configuration.attributedSubtitle = subtitle
      }
      configuration.titleAlignment = .center
      configuration.titleLineBreakMode = .byTruncatingTail
      configuration.subtitleLineBreakMode = .byTruncatingTail
      configuration.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 13, bottom: 3, trailing: 13)
    } else if kind == "chatAvatar" {
      configuration.image = chatAvatar()
      configuration.contentInsets = .zero
      button.accessibilityValue = input["onlineLabel"] as? String
    } else if let symbol = input["symbol"] as? String {
      configuration.image = UIImage(systemName: symbol)
      configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
      if primary && enabled {
        configuration.imageColorTransformer = UIConfigurationColorTransformer { _ in labelColor }
      }
      if input["stacked"] as? Bool == true {
        configuration.imagePlacement = .top
        configuration.imagePadding = 4
        configuration.titleAlignment = .center
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 19
        var label = AttributedString(title)
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        configuration.attributedTitle = label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 3, bottom: 4, trailing: 3)
      } else {
        configuration.contentInsets = .zero
      }
    } else {
      var titleText = AttributedString(title)
      titleText.font = .preferredFont(forTextStyle: .headline)
      configuration.attributedTitle = titleText
      configuration.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12)
    }
    button.configuration = configuration
  }
}
