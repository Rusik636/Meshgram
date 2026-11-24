// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import Flutter
import UIKit

// The Flutter platform view contains a system tab controller with transparent
// pages. Flutter owns the actual content and responds to UIKit selection.
final class MeshTabs: NSObject, FlutterPlatformView, UITabBarControllerDelegate {
  // Reserve the floating bar's full width for text tabs without drawing icons.
  private static let textTabImage = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 1))
    .image { _ in }

  private let root: TabControllerContainer
  private let tabs = UITabBarController()
  private let indicatorViewport = UIView()
  private let channel: FlutterMethodChannel
  private let textOnly: Bool
  private let indicatorOnly: Bool
  private var input: [String: Any] = [:]
  private var labels: [String] = []
  private var symbols: [String] = []

  private var textTabScale: CGFloat {
    if #available(iOS 26.0, *) { return 0.73 }
    return 1
  }

  init(_ frame: CGRect, _ channel: FlutterMethodChannel, _ input: [String: Any]) {
    root = TabControllerContainer(frame: frame)
    self.channel = channel
    indicatorOnly = input["indicatorOnly"] as? Bool == true
    textOnly = indicatorOnly || input["textOnly"] as? Bool == true
    super.init()

    root.backgroundColor = .clear
    root.clipsToBounds = !textOnly
    root.isUserInteractionEnabled = !indicatorOnly
    root.accessibilityElementsHidden = indicatorOnly
    tabs.delegate = self
    tabs.loadViewIfNeeded()
    tabs.view.backgroundColor = .clear
    tabs.view.isOpaque = false
    if #available(iOS 17.0, *) {
      tabs.traitOverrides.horizontalSizeClass = .compact
    }
    root.windowDidChange = { [weak self] in self?.mount() }
    if textOnly {
      root.layoutContent = { [weak self] in self?.layoutTextTabs() }
      tabs.tabBar.itemPositioning = .fill
    }
    if indicatorOnly {
      // Use UIKit's selection over the caller's glass background.
      indicatorViewport.frame = root.bounds
      indicatorViewport.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      indicatorViewport.clipsToBounds = true
      root.addSubview(indicatorViewport)
      let appearance = UITabBarAppearance()
      appearance.configureWithTransparentBackground()
      appearance.stackedItemPositioning = .fill
      tabs.tabBar.standardAppearance = appearance
      tabs.tabBar.scrollEdgeAppearance = appearance
    }
    update(input)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let values = call.arguments as? [String: Any] else {
        return result(FlutterMethodNotImplemented)
      }
      self?.update(values)
      result(nil)
    }
  }

  deinit { channel.setMethodCallHandler(nil) }

  func view() -> UIView { root }

  private func mount() {
    guard root.window != nil else {
      if tabs.parent != nil {
        tabs.willMove(toParent: nil)
        tabs.view.removeFromSuperview()
        tabs.removeFromParent()
      }
      return
    }
    var responder: UIResponder? = root.next
    while let current = responder, !(current is UIViewController) {
      responder = current.next
    }
    guard let parent = responder as? UIViewController, tabs.parent !== parent else { return }
    parent.addChild(tabs)
    (indicatorOnly ? indicatorViewport : root).addSubview(tabs.view)
    if textOnly {
      layoutTextTabs()
    } else {
      tabs.view.frame = root.bounds
      tabs.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    tabs.didMove(toParent: parent)
  }

  private func layoutTextTabs() {
    guard tabs.view.superview != nil, root.bounds.width > 0 else { return }
    let scale = textTabScale
    let systemHeight: CGFloat
    if #available(iOS 26.0, *) { systemHeight = 102 } else { systemHeight = 49 }
    // Preserve the system glass proportions while fitting the floating bar inline.
    // Compensate for its 20 pt system inset on either side.
    let widthAdjustment: CGFloat = indicatorOnly ? 18 : -32
    let width = max(0, root.bounds.width + widthAdjustment) / scale + 40
    if indicatorOnly {
      // Clip the surrounding bar chrome to reveal only UIKit’s selected fill.
      indicatorViewport.layer.cornerCurve = .continuous
      indicatorViewport.layer.cornerRadius = root.bounds.height / 2
    }
    tabs.view.bounds = CGRect(x: 0, y: 0, width: width, height: systemHeight)
    tabs.view.center = CGPoint(x: root.bounds.midX, y: root.bounds.midY)
    tabs.view.transform = CGAffineTransform(scaleX: scale, y: scale)
  }

  private func updateTextTabAppearance(_ titleSize: CGFloat) {
    let appearance = tabs.tabBar.standardAppearance.copy()
    appearance.stackedItemPositioning = .fill
    let inverseScale = 1 / textTabScale
    let matrix = CGAffineTransform(scaleX: inverseScale, y: inverseScale)
    let regular = UIFont.systemFont(ofSize: titleSize).fontDescriptor.withMatrix(matrix)
    let selected = UIFont.systemFont(ofSize: titleSize, weight: .semibold).fontDescriptor.withMatrix(matrix)
    let normalFont = UIFont(descriptor: regular, size: titleSize)
    let selectedFont = UIFont(descriptor: selected, size: titleSize)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let titleOffset = UIOffset(horizontal: 0, vertical: textTabScale < 1 ? -10 : -16)
    for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
      for (state, font) in [(layout.normal, normalFont), (layout.selected, selectedFont),
                            (layout.disabled, normalFont), (layout.focused, normalFont)] {
        state.titleTextAttributes = [.font: font, .paragraphStyle: paragraph]
        state.titlePositionAdjustment = titleOffset
      }
    }
    tabs.tabBar.standardAppearance = appearance
    tabs.tabBar.scrollEdgeAppearance = appearance
  }

  private func tabImage(_ name: String) -> UIImage? {
    let configuration = UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)
    guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return nil }
    // Rasterize within a fixed canvas so the tab bar keeps both symbol variants compact.
    let canvas = CGSize(width: 22, height: 22)
    let scale = min(canvas.width / symbol.size.width, 18.5 / symbol.size.height)
    let size = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
    let origin = CGPoint(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2)
    return UIGraphicsImageRenderer(size: canvas).image { _ in
      symbol.withTintColor(.black, renderingMode: .alwaysOriginal)
        .draw(in: CGRect(origin: origin, size: size))
    }.withRenderingMode(.alwaysTemplate)
  }

  private func update(_ values: [String: Any]) {
    guard !(input as NSDictionary).isEqual(to: values) else { return }
    let sizeChanged = (values["titleSize"] as? NSNumber) != (input["titleSize"] as? NSNumber)
    input = values
    tabs.overrideUserInterfaceStyle = values["dark"] as? Bool == true ? .dark : .light
    if indicatorOnly {
      root.overrideUserInterfaceStyle = tabs.overrideUserInterfaceStyle
      indicatorViewport.backgroundColor = tabs.overrideUserInterfaceStyle == .dark
        ? UIColor(white: 0.078, alpha: 1) : UIColor(white: 0.9, alpha: 1)
      if #available(iOS 26.0, *) {
        indicatorViewport.isHidden = values["lensActive"] as? Bool == true &&
          !UIAccessibility.isReduceMotionEnabled && !UIAccessibility.isReduceTransparencyEnabled
      }
    }
    tabs.tabBar.tintColor = meshColor(values["accent"], .systemBlue)
    if textOnly && !indicatorOnly && sizeChanged {
      updateTextTabAppearance((values["titleSize"] as? NSNumber)?.doubleValue ?? 15)
    }
    let current = values["labels"] as? [String] ?? []
    let currentSymbols = values["symbols"] as? [String] ?? []
    if labels != current || symbols != currentSymbols {
      labels = current
      symbols = currentSymbols
      tabs.viewControllers = labels.enumerated().map { index, label in
        let page = UIViewController()
        page.view.backgroundColor = .clear
        page.view.isUserInteractionEnabled = false
        let name = symbols.indices.contains(index) ? symbols[index] : "circle"
        let image = textOnly ? Self.textTabImage : tabImage(name)
        let selected = textOnly ? Self.textTabImage : tabImage(name + ".fill") ?? image
        page.tabBarItem = UITabBarItem(title: label, image: image, selectedImage: selected)
        page.tabBarItem.tag = index
        return page
      }
    }
    let unreadCounts = values["unreadCounts"] as? [Int] ?? []
    if let controllers = tabs.viewControllers, !textOnly {
      for (index, page) in controllers.enumerated() {
        let count = unreadCounts.indices.contains(index) ? unreadCounts[index] : 0
        let overflow = index == 0 ? "99+" : "+99"
        page.tabBarItem.badgeValue = count <= 0 ? nil : count > 99 ? overflow : String(count)
      }
    }
    if let index = values["index"] as? Int {
      select(index)
    }
  }

  private func select(_ index: Int) {
    guard labels.indices.contains(index), tabs.selectedIndex != index else { return }
    tabs.selectedIndex = index
  }

  func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
    guard !indicatorOnly else { return }
    channel.invokeMethod("select", arguments: viewController.tabBarItem.tag)
  }
}

// This glass is composited above the folder labels so they can refract at its edge.
final class MeshTabLens: NSObject, FlutterPlatformView {
  private let root: TabControllerContainer
  private let channel: FlutterMethodChannel
  private var tap: Int
  private var lens: UIVisualEffectView?

  init(_ frame: CGRect, _ channel: FlutterMethodChannel, _ input: [String: Any]) {
    root = TabControllerContainer(frame: frame)
    self.channel = channel
    tap = input["tap"] as? Int ?? 0
    super.init()
    root.isUserInteractionEnabled = false
    root.accessibilityElementsHidden = true
    root.layoutContent = { [weak self] in self?.layoutLens() }
    update(input)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let values = call.arguments as? [String: Any] else {
        return result(FlutterMethodNotImplemented)
      }
      self?.update(values)
      result(nil)
    }
  }

  deinit { channel.setMethodCallHandler(nil) }

  func view() -> UIView { root }

  private func layoutLens() {
    guard let lens else { return }
    lens.bounds = CGRect(origin: .zero, size: root.bounds.insetBy(dx: 2, dy: 1).size)
    lens.center = CGPoint(x: root.bounds.midX, y: root.bounds.midY)
    lens.layer.cornerRadius = lens.bounds.height / 2
  }

  private func update(_ values: [String: Any]) {
    root.overrideUserInterfaceStyle = values["dark"] as? Bool == true ? .dark : .light
    let nextTap = values["tap"] as? Int ?? 0
    let tapped = nextTap != tap
    tap = nextTap
    guard #available(iOS 26.0, *), tapped, values["reduceMotion"] as? Bool != true,
      !UIAccessibility.isReduceMotionEnabled, !UIAccessibility.isReduceTransparencyEnabled else { return }
    self.lens?.removeFromSuperview()
    let lens = UIVisualEffectView(effect: nil)
    lens.layer.cornerCurve = .continuous
    let material = UIGlassEffect(style: .clear)
    let dark = root.overrideUserInterfaceStyle == .dark
    material.tintColor = UIColor(white: dark ? 0.06 : 0.95, alpha: 0.16)
    self.lens = lens
    layoutLens()
    root.addSubview(lens)
    UIView.animate(withDuration: 0.18, delay: 0, usingSpringWithDamping: 0.74,
      initialSpringVelocity: 0.45, options: [.allowUserInteraction]) {
      lens.effect = material
      lens.transform = CGAffineTransform(scaleX: 1.16, y: 1.22)
    } completion: { [weak self] _ in
      guard self?.lens === lens else { return }
      UIView.animate(withDuration: 0.23, delay: 0, usingSpringWithDamping: 0.78,
        initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        lens.effect = nil
        lens.transform = .identity
      } completion: { [weak self] _ in
        lens.removeFromSuperview()
        if self?.lens === lens { self?.lens = nil }
      }
    }
  }
}

private final class TabControllerContainer: UIView {
  var windowDidChange: (() -> Void)?
  var layoutContent: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    layoutContent?()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    windowDidChange?()
  }
}
