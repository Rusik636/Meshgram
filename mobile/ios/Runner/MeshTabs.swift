// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import Flutter
import UIKit
import UIKit.UIGestureRecognizerSubclass

// The Flutter platform view contains a system tab controller with transparent
// pages. Flutter owns the actual content and responds to UIKit selection.
final class MeshTabs: NSObject, FlutterPlatformView, UITabBarControllerDelegate {
  // Reserve the floating bar's full width for text tabs without drawing icons.
  private static let textTabImage = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 1))
    .image { _ in }

  private let root: TabControllerContainer
  private let tabs = UITabBarController()
  private let channel: FlutterMethodChannel
  private let textOnly: Bool
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
    textOnly = input["textOnly"] as? Bool == true
    super.init()

    root.backgroundColor = .clear
    root.clipsToBounds = !textOnly
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
    root.addSubview(tabs.view)
    if textOnly {
      layoutTextTabs()
    } else {
      tabs.view.frame = root.bounds
      tabs.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    tabs.didMove(toParent: parent)
  }

  private func layoutTextTabs() {
    guard tabs.view.superview === root, root.bounds.width > 0 else { return }
    let scale = textTabScale
    let systemHeight: CGFloat
    if #available(iOS 26.0, *) { systemHeight = 102 } else { systemHeight = 49 }
    // Preserve the system glass proportions while fitting the floating bar inline.
    // Compensate for its 20 pt system inset on either side.
    let width = max(0, root.bounds.width - 32) / scale + 40
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
    tabs.tabBar.tintColor = meshColor(values["accent"], .systemBlue)
    if textOnly && sizeChanged {
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
    channel.invokeMethod("select", arguments: viewController.tabBarItem.tag)
  }
}

// Both the tab bar and the segmented control use UIKit's interactive glass.
// Segments can be sized independently to fit the folder labels.
final class MeshFolderTabs: NSObject, FlutterPlatformView {
  // Match the resting UIKit tab bar selection on the light chat canvas.
  private static let lightSelection = UIColor(
    red: 227.0 / 255, green: 228.0 / 255, blue: 231.0 / 255, alpha: 1
  )

  private let root: TabControllerContainer
  private let control = MeshFolderSegmentedControl()
  private let boundary = TabTapBoundary(target: nil, action: nil)
  private let channel: FlutterMethodChannel
  private var labels: [String] = []
  private var appearance: [String: Any] = [:]

  init(_ frame: CGRect, _ channel: FlutterMethodChannel, _ input: [String: Any]) {
    root = TabControllerContainer(frame: frame)
    self.channel = channel
    super.init()
    root.addGestureRecognizer(boundary)
    boundary.cancelsTouchesInView = true
    root.addSubview(control)
    control.addTarget(self, action: #selector(selectSegment), for: .valueChanged)
    root.layoutContent = { [weak self] in
      guard let self else { return }
      self.control.frame = self.root.bounds
      self.control.layoutIfNeeded()
      self.boundary.gateGestures(in: self.control)
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

  private func update(_ input: [String: Any]) {
    let newLabels = input["labels"] as? [String] ?? []
    if labels != newLabels {
      labels = newLabels
      control.removeAllSegments()
      for (index, label) in labels.enumerated() {
        control.insertSegment(withTitle: label, at: index, animated: false)
      }
      root.setNeedsLayout()
    }
    let widths = input["widths"] as? [NSNumber] ?? []
    for (index, width) in widths.prefix(labels.count).enumerated()
      where control.widthForSegment(at: index) != CGFloat(width.doubleValue) {
      control.setWidth(CGFloat(width.doubleValue), forSegmentAt: index)
    }
    let attributes = input.filter { ["titleSize", "dark", "rtl", "text", "accent"].contains($0.key) }
    if !(appearance as NSDictionary).isEqual(to: attributes) {
      appearance = attributes
      let size = CGFloat((input["titleSize"] as? NSNumber)?.doubleValue ?? 15)
      let dark = input["dark"] as? Bool == true
      control.overrideUserInterfaceStyle = dark ? .dark : .light
      control.semanticContentAttribute = input["rtl"] as? Bool == true ? .forceRightToLeft : .forceLeftToRight
      control.selectedSegmentTintColor = dark ? UIColor(white: 0.075, alpha: 1) : Self.lightSelection
      let font = UIFont.systemFont(ofSize: size, weight: .semibold)
      control.setTitleTextAttributes([
        .font: font,
        .foregroundColor: meshColor(input["text"], .label),
      ], for: .normal)
      control.setTitleTextAttributes([
        .font: font,
        .foregroundColor: meshColor(input["accent"], .label),
      ], for: .selected)
    }
    if let index = input["index"] as? Int, labels.indices.contains(index),
       control.selectedSegmentIndex != index {
      control.selectedSegmentIndex = index
    }
  }

  @objc private func selectSegment() {
    guard boundary.state != .recognized else { return }
    channel.invokeMethod("select", arguments: control.selectedSegmentIndex)
  }
}

private final class MeshFolderSegmentedControl: UISegmentedControl {
  override func layoutSubviews() {
    super.layoutSubviews()
    if #available(iOS 26.0, *) {
      // The direct image views are the system track. A custom background image
      // would also replace the system's interactive selection effect.
      for case let track as UIImageView in subviews {
        track.isHidden = true
      }
    }
  }
}

private final class TabTapBoundary: UIGestureRecognizer {
  private var origin: CGPoint?
  private var startedAt: TimeInterval = 0
  private let gatedGestures = NSHashTable<UIGestureRecognizer>.weakObjects()

  func gateGestures(in view: UIView) {
    for gesture in view.gestureRecognizers ?? [] where !gatedGestures.contains(gesture) {
      gesture.require(toFail: self)
      gatedGestures.add(gesture)
    }
    for subview in view.subviews { gateGestures(in: subview) }
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    origin = touches.first?.location(in: view)
    startedAt = event.timestamp
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    guard let origin, let point = touches.first?.location(in: view) else { return }
    if abs(point.x - origin.x) > 7 || abs(point.y - origin.y) > 7 {
      state = .recognized
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    guard state == .possible else { return }
    if event.timestamp - startedAt > 0.5 {
      state = .recognized
    } else {
      state = .failed
    }
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    state = .cancelled
  }

  override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
    false
  }

  override func reset() {
    super.reset()
    origin = nil
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
