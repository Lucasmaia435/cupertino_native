import FlutterMacOS
import Cocoa

/// A vertical Liquid Glass capsule holding a column of icon buttons, mirroring
/// the iOS platform view of the same name. macOS has no folding-device use
/// case for this today, but the widget stays available for consistency.
class CupertinoGlassCapsuleNSView: NSView {
  private let channel: FlutterMethodChannel
  private let effectView = NSVisualEffectView()
  private let selectionView = NSView()
  private let stack = NSStackView()

  private var items: [[String: Any]] = []
  private var buttons: [NSButton] = []
  private var badges: [Int: NSTextField] = [:]
  private var selectedIndex: Int?
  private var tint: NSColor?
  private var inset: CGFloat = 0
  private var stackTop: NSLayoutConstraint?
  private var stackBottom: NSLayoutConstraint?

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "CupertinoNativeGlassCapsule_\(viewId)", binaryMessenger: messenger)
    super.init(frame: .zero)

    wantsLayer = true
    effectView.material = .popover
    effectView.blendingMode = .withinWindow
    effectView.state = .active
    effectView.wantsLayer = true
    effectView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(effectView)

    selectionView.wantsLayer = true
    selectionView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
    selectionView.isHidden = true
    effectView.addSubview(selectionView)

    stack.orientation = .vertical
    stack.distribution = .fillEqually
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    effectView.addSubview(stack)

    let top = stack.topAnchor.constraint(equalTo: effectView.topAnchor)
    let bottom = stack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
    stackTop = top
    stackBottom = bottom
    NSLayoutConstraint.activate([
      effectView.topAnchor.constraint(equalTo: topAnchor),
      effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
      effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
      top,
      bottom,
    ])

    if let params = args as? [String: Any] {
      apply(params)
    }

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "update":
        if let params = call.arguments as? [String: Any] {
          self.apply(params)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  required init?(coder: NSCoder) { return nil }

  override func layout() {
    super.layout()
    layoutChrome()
  }

  private func apply(_ params: [String: Any]) {
    if let dark = params["isDark"] as? Bool {
      appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
    if let n = params["tint"] as? NSNumber {
      tint = Self.colorFromARGB(n.intValue)
    } else if params.keys.contains("items") {
      tint = nil
    }
    if let value = params["inset"] as? NSNumber {
      inset = CGFloat(truncating: value)
      stackTop?.constant = inset
      stackBottom?.constant = -inset
    }

    selectedIndex = (params["selectedIndex"] as? NSNumber)?.intValue

    if let newItems = params["items"] as? [[String: Any]] {
      items = newItems
      rebuildButtons()
    }
    refreshAppearance()
    needsLayout = true
  }

  private func rebuildButtons() {
    buttons.forEach { $0.removeFromSuperview() }
    buttons = []
    badges.values.forEach { $0.removeFromSuperview() }
    badges = [:]

    for (index, item) in items.enumerated() {
      let button = NSButton(title: "", target: self, action: #selector(tapped(_:)))
      button.tag = index
      button.isBordered = false
      button.bezelStyle = .regularSquare
      if let label = item["label"] as? String {
        button.setAccessibilityLabel(label)
      }
      stack.addArrangedSubview(button)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.heightAnchor.constraint(equalTo: stack.heightAnchor, multiplier: 1.0 / CGFloat(max(items.count, 1))).isActive = true
      buttons.append(button)

      if let count = (item["badge"] as? NSNumber)?.intValue, count > 0 {
        let badge = NSTextField(labelWithString: count > 99 ? "99+" : "\(count)")
        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.systemRed.cgColor
        badge.layer?.cornerRadius = 8
        badge.drawsBackground = false
        addSubview(badge)
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
          badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
          badge.heightAnchor.constraint(equalToConstant: 16),
          badge.centerXAnchor.constraint(equalTo: button.centerXAnchor, constant: 10),
          badge.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: 10),
        ])
        badges[index] = badge
      }
    }
  }

  private func refreshAppearance() {
    for (index, button) in buttons.enumerated() {
      let item = items[index]
      let selected = index == selectedIndex
      let itemTint = (item["tint"] as? NSNumber).map { Self.colorFromARGB($0.intValue) }
      let color = selectedIndex != nil
        ? (selected ? (itemTint ?? tint ?? .controlAccentColor) : .labelColor)
        : (itemTint ?? tint ?? .labelColor)

      let symbol = (selected ? item["selectedSymbol"] as? String : nil) ?? item["symbol"] as? String
      if let symbol = symbol, #available(macOS 11.0, *) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: item["label"] as? String)
        button.imagePosition = .imageOnly
        button.contentTintColor = color
      } else if let title = item["title"] as? String {
        button.title = title
        button.contentTintColor = color
      }
    }
  }

  private func layoutChrome() {
    let width = bounds.width
    guard width > 0 else { return }
    effectView.layer?.cornerRadius = width / 2
    selectionView.layer?.cornerRadius = (width - 6) / 2

    guard let selected = selectedIndex, selected < buttons.count else {
      selectionView.isHidden = true
      return
    }
    let button = buttons[selected]
    selectionView.frame = NSRect(
      x: 3, y: button.frame.origin.y, width: width - 6, height: button.frame.height
    )
    selectionView.isHidden = false
  }

  @objc private func tapped(_ sender: NSButton) {
    let item = items[sender.tag]
    if let entries = item["menu"] as? [[String: Any]] {
      let menu = NSMenu()
      for entry in entries {
        let id = (entry["id"] as? NSNumber)?.intValue ?? -1
        let menuItem = NSMenuItem(
          title: entry["title"] as? String ?? "",
          action: #selector(menuItemTapped(_:)),
          keyEquivalent: ""
        )
        menuItem.target = self
        menuItem.tag = id
        menu.addItem(menuItem)
      }
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
      return
    }
    channel.invokeMethod("onItemTapped", arguments: ["index": sender.tag])
  }

  @objc private func menuItemTapped(_ sender: NSMenuItem) {
    channel.invokeMethod("onMenuItemTapped", arguments: ["id": sender.tag])
  }

  private static func colorFromARGB(_ argb: Int) -> NSColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return NSColor(red: r, green: g, blue: b, alpha: a)
  }
}
