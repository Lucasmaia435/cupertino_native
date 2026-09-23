import FlutterMacOS
import Cocoa

class CupertinoToolbarNSView: NSView {
  private let channel: FlutterMethodChannel
  private let effectView: NSVisualEffectView
  private let titleLabel: NSTextField
  private let actionsStack: NSStackView

  private var currentActions: [[String: Any]] = []
  private var currentTint: NSColor?

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CupertinoNativeToolbar_\(viewId)", binaryMessenger: messenger)
    self.effectView = NSVisualEffectView()
    self.titleLabel = NSTextField(labelWithString: "")
    self.actionsStack = NSStackView()

    var isDark = false
    let dict = args as? [String: Any]
    if let value = dict?["isDark"] as? NSNumber { isDark = value.boolValue }

    super.init(frame: .zero)

    appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

    effectView.material = .headerView
    effectView.blendingMode = .withinWindow
    effectView.state = .active
    effectView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(effectView)

    titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    titleLabel.alignment = .center
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(titleLabel)

    actionsStack.orientation = .horizontal
    actionsStack.spacing = 8
    actionsStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(actionsStack)

    NSLayoutConstraint.activate([
      effectView.topAnchor.constraint(equalTo: topAnchor),
      effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
      effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

      titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

      actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      actionsStack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    if let dict = dict {
      configureItems(dict)
      if let style = dict["style"] as? [String: Any], let n = style["tint"] as? NSNumber {
        currentTint = Self.colorFromARGB(n.intValue)
        applyTint()
      }
    }

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }
  }

  required init?(coder: NSCoder) { return nil }

  private func configureItems(_ params: [String: Any]) {
    if let title = params["title"] as? String {
      titleLabel.stringValue = title
    }

    actionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let actions = (params["actions"] as? [[String: Any]]) ?? []
    currentActions = actions

    for (index, action) in actions.enumerated() {
      let button = NSButton(title: "", target: self, action: #selector(actionTapped(_:)))
      button.tag = index
      button.isBordered = false
      button.bezelStyle = .regularSquare

      if let icon = action["icon"] as? String, #available(macOS 11.0, *) {
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: action["label"] as? String)
        button.imagePosition = .imageOnly
      } else if let title = action["title"] as? String {
        button.title = title
      }

      if let label = action["label"] as? String {
        button.setAccessibilityLabel(label)
      }
      if let n = action["tint"] as? NSNumber {
        button.contentTintColor = Self.colorFromARGB(n.intValue)
      } else if let tint = currentTint {
        button.contentTintColor = tint
      }

      actionsStack.addArrangedSubview(button)
    }
  }

  private func applyTint() {
    for (index, view) in actionsStack.arrangedSubviews.enumerated() {
      guard let button = view as? NSButton else { continue }
      let hasOwnTint = (currentActions[safe: index]?["tint"] as? NSNumber) != nil
      if !hasOwnTint {
        button.contentTintColor = currentTint
      }
    }
  }

  @objc private func actionTapped(_ sender: NSButton) {
    channel.invokeMethod("actionTapped", arguments: ["index": sender.tag])
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setTitle":
      if let args = call.arguments as? [String: Any], let title = args["title"] as? String {
        titleLabel.stringValue = title
      }
      result(nil)
    case "setActions":
      configureItems((call.arguments as? [String: Any]) ?? [:])
      applyTint()
      result(nil)
    case "setStyle":
      if let args = call.arguments as? [String: Any] {
        if let n = args["tint"] as? NSNumber {
          currentTint = Self.colorFromARGB(n.intValue)
        } else if args["tint"] is NSNull {
          currentTint = nil
        }
        applyTint()
      }
      result(nil)
    case "setBrightness":
      if let args = call.arguments as? [String: Any], let dark = args["isDark"] as? NSNumber {
        appearance = NSAppearance(named: dark.boolValue ? .darkAqua : .aqua)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func colorFromARGB(_ argb: Int) -> NSColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return NSColor(red: r, green: g, blue: b, alpha: a)
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
