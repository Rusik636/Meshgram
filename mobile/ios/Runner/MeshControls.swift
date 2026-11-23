// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import Flutter
import UIKit

let meshChatSymbol = "bubble.left"

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
    let channel = FlutterMethodChannel(name: "meshgrame/controls/\(id)", binaryMessenger: messenger)
    if input["kind"] as? String == "messageGlass" {
      return MeshMessageGlass(frame: frame, input: input)
    }
    if input["kind"] as? String == "modalGlass" {
      return MeshModalGlass(frame: frame, input: input)
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

  init(frame: CGRect, input: [String: Any]) {
    let effect: UIVisualEffect
    if #available(iOS 26.0, *) {
      effect = UIGlassEffect(style: .regular)
    } else {
      effect = UIBlurEffect(style: .systemMaterial)
    }
    surface = UIVisualEffectView(effect: effect)
    super.init()
    surface.frame = frame
    surface.overrideUserInterfaceStyle = input["dark"] as? Bool == true ? .dark : .light
    surface.layer.cornerRadius = CGFloat(input["radius"] as? Double ?? 22)
    surface.layer.cornerCurve = .continuous
    surface.clipsToBounds = true
    surface.isUserInteractionEnabled = false
    surface.accessibilityElementsHidden = true
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
    pointSize = input["kind"] as? String == "symbolIcon" ? 19 : 35
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

private final class MeshControlSurface: NSObject, FlutterPlatformView {
  private let root: UIView
  private let channel: FlutterMethodChannel
  private let kind: String
  private let button = UIButton(type: .system)
  private var input: [String: Any] = [:]
  private var observer: NSObjectProtocol?

  init(frame: CGRect, channel: FlutterMethodChannel, input: [String: Any]) {
    root = UIView(frame: frame)
    self.channel = channel
    kind = input["kind"] as? String ?? "button"
    super.init()

    root.addSubview(button)
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      button.topAnchor.constraint(equalTo: root.topAnchor),
      button.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    button.addAction(UIAction { [weak self] _ in
      self?.channel.invokeMethod("select", arguments: 0)
    }, for: .touchUpInside)

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

  private func update(_ values: [String: Any]) {
    guard !(input as NSDictionary).isEqual(to: values) else { return }
    input = values
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
    let reduceTransparency = UIAccessibility.isReduceTransparencyEnabled

    let primary = input["primary"] as? Bool == true
    let enabled = input["enabled"] as? Bool == true
    let title = input["label"] as? String ?? ""
    button.isEnabled = enabled
    button.accessibilityLabel = title
    button.tintColor = accent
    var configuration: UIButton.Configuration
    if #available(iOS 26.0, *), !reduceTransparency {
      configuration = primary ? .prominentGlass() : .glass()
      if primary { configuration.baseBackgroundColor = accent }
    } else {
      configuration = .filled()
      configuration.baseBackgroundColor = primary ? accent : surface
    }
    configuration.baseForegroundColor = primary ? meshColor(input["onAccent"], .white) : foreground
    configuration.cornerStyle = .capsule
    if kind == "chatTitle" {
      if input["readOnly"] as? Bool == true {
        root.isUserInteractionEnabled = false
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
