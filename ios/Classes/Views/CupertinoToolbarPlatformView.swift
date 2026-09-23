import Flutter
import UIKit

/// Container that hosts the navigation bar and an optional readability
/// gradient behind it, and forwards trait (light/dark) changes.
private class ToolbarContainerView: UIView {
  var gradientLayer: CAGradientLayer?
  var onTraitChange: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    gradientLayer?.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height + 30)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
      onTraitChange?()
    }
  }
}

class CupertinoToolbarPlatformView: NSObject, FlutterPlatformView {
  private let channel: FlutterMethodChannel
  private let containerView: ToolbarContainerView
  private let navigationBar: UINavigationBar
  private let navigationItem: UINavigationItem

  private var isDark: Bool = false
  private var perActionTintTags: Set<Int> = []

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CupertinoNativeToolbar_\(viewId)", binaryMessenger: messenger)
    self.containerView = ToolbarContainerView(frame: frame)
    self.navigationBar = UINavigationBar()
    self.navigationItem = UINavigationItem()

    let dict = args as? [String: Any]
    self.isDark = (dict?["isDark"] as? NSNumber)?.boolValue ?? false

    super.init()

    if #available(iOS 13.0, *) {
      containerView.overrideUserInterfaceStyle = isDark ? .dark : .light
    }

    let showsGradient = (dict?["showsGradient"] as? NSNumber)?.boolValue ?? true
    if showsGradient {
      setupGradient()
    }
    setupNavigationBar()

    if let dict = dict {
      configureItems(dict)
      if let style = dict["style"] as? [String: Any], let n = style["tint"] as? NSNumber {
        applyGlobalTint(Self.colorFromARGB(n.intValue))
      }
    }

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }
  }

  func view() -> UIView {
    return containerView
  }

  private func setupGradient() {
    containerView.clipsToBounds = false
    let gradientLayer = CAGradientLayer()
    gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
    gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
    containerView.layer.insertSublayer(gradientLayer, at: 0)
    containerView.gradientLayer = gradientLayer
    containerView.onTraitChange = { [weak self] in self?.updateGradientColors() }
    updateGradientColors()
  }

  private func updateGradientColors() {
    let isDarkMode = containerView.traitCollection.userInterfaceStyle == .dark
    let base = isDarkMode ? UIColor.black : UIColor.white
    containerView.gradientLayer?.colors = [
      base.withAlphaComponent(0.85).cgColor,
      base.withAlphaComponent(0.6).cgColor,
      base.withAlphaComponent(0.2).cgColor,
      base.withAlphaComponent(0.0).cgColor,
    ]
    containerView.gradientLayer?.locations = [0.0, 0.4, 0.7, 1.0]
  }

  private func setupNavigationBar() {
    containerView.backgroundColor = .clear
    navigationBar.translatesAutoresizingMaskIntoConstraints = false
    navigationBar.items = [navigationItem]

    if #available(iOS 13.0, *) {
      let appearance = UINavigationBarAppearance()
      appearance.configureWithTransparentBackground()
      appearance.backgroundColor = .clear
      appearance.shadowColor = .clear
      navigationBar.standardAppearance = appearance
      navigationBar.scrollEdgeAppearance = appearance
      if #available(iOS 15.0, *) {
        navigationBar.compactAppearance = appearance
      }
    }

    containerView.addSubview(navigationBar)
    NSLayoutConstraint.activate([
      navigationBar.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor),
      navigationBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      navigationBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      navigationBar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
    ])
  }

  private func configureItems(_ params: [String: Any]) {
    if let title = params["title"] as? String {
      navigationItem.title = title
    }

    var rightGroup: [UIBarButtonItem] = []
    var leftGroup: [UIBarButtonItem] = []

    if let actions = params["actions"] as? [[String: Any]] {
      let hasFlexible = actions.contains { ($0["spacerAfter"] as? NSNumber)?.intValue == 2 }
      var foundFlexible = false
      let total = actions.count

      for (index, action) in actions.enumerated() {
        var button: UIBarButtonItem?

        if let icon = action["icon"] as? String {
          button = UIBarButtonItem(image: UIImage(systemName: icon), style: .plain, target: self, action: #selector(actionTapped(_:)))
        } else if let title = action["title"] as? String {
          button = UIBarButtonItem(title: title, style: .plain, target: self, action: #selector(actionTapped(_:)))
        }

        guard let btn = button else { continue }
        btn.tag = index
        if let label = action["label"] as? String {
          btn.accessibilityLabel = label
        }
        if (action["prominent"] as? NSNumber)?.boolValue == true {
          if #available(iOS 26.0, *) {
            btn.style = .prominent
          }
        }
        if let n = action["tint"] as? NSNumber {
          btn.tintColor = Self.colorFromARGB(n.intValue)
          perActionTintTags.insert(index)
        }

        if !hasFlexible {
          rightGroup.append(btn)
        } else if !foundFlexible {
          leftGroup.append(btn)
        } else {
          rightGroup.append(btn)
        }

        if let spacerAfter = action["spacerAfter"] as? NSNumber {
          switch spacerAfter.intValue {
          case 1:
            if #available(iOS 16.0, *) {
              if !hasFlexible || foundFlexible {
                rightGroup.append(.fixedSpace(12))
              } else {
                leftGroup.append(.fixedSpace(12))
              }
            }
          case 2:
            foundFlexible = true
          default:
            break
          }
        }
        _ = total
      }
    }

    navigationItem.leftBarButtonItems = leftGroup.isEmpty ? nil : leftGroup
    navigationItem.rightBarButtonItems = rightGroup.isEmpty ? nil : rightGroup.reversed()
  }

  private func applyGlobalTint(_ color: UIColor?) {
    containerView.tintColor = color
    navigationBar.tintColor = color
    for item in (navigationItem.leftBarButtonItems ?? []) + (navigationItem.rightBarButtonItems ?? []) {
      if !perActionTintTags.contains(item.tag) {
        item.tintColor = color
      }
    }
  }

  @objc private func actionTapped(_ sender: UIBarButtonItem) {
    channel.invokeMethod("actionTapped", arguments: ["index": sender.tag])
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setTitle":
      if let args = call.arguments as? [String: Any], let title = args["title"] as? String {
        navigationItem.title = title
      }
      result(nil)
    case "setActions":
      perActionTintTags.removeAll()
      configureItems((call.arguments as? [String: Any]) ?? [:])
      if let globalTint = navigationBar.tintColor {
        applyGlobalTint(globalTint)
      }
      result(nil)
    case "setStyle":
      if let args = call.arguments as? [String: Any] {
        if let n = args["tint"] as? NSNumber {
          applyGlobalTint(Self.colorFromARGB(n.intValue))
        } else if args["tint"] is NSNull {
          applyGlobalTint(nil)
        }
      }
      result(nil)
    case "setBrightness":
      if let args = call.arguments as? [String: Any], let dark = args["isDark"] as? NSNumber {
        isDark = dark.boolValue
        if #available(iOS 13.0, *) {
          containerView.overrideUserInterfaceStyle = isDark ? .dark : .light
        }
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func colorFromARGB(_ argb: Int) -> UIColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
}
