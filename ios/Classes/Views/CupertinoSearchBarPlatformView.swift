import Flutter
import UIKit

class CupertinoSearchBarPlatformView: NSObject, FlutterPlatformView, UISearchBarDelegate {
  private let channel: FlutterMethodChannel
  private let container: UIView
  private let searchBar: UISearchBar

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CupertinoNativeSearchBar_\(viewId)", binaryMessenger: messenger)
    self.container = UIView(frame: frame)
    self.searchBar = UISearchBar(frame: .zero)

    var text: String = ""
    var placeholder: String? = nil
    var enabled: Bool = true
    var showsCancelButton: Bool = false
    var isDark: Bool = false
    var tint: UIColor? = nil
    var bg: UIColor? = nil
    var fieldBg: UIColor? = nil

    if let dict = args as? [String: Any] {
      if let value = dict["text"] as? String { text = value }
      if let value = dict["placeholder"] as? String { placeholder = value }
      if let value = dict["enabled"] as? NSNumber { enabled = value.boolValue }
      if let value = dict["showsCancelButton"] as? NSNumber { showsCancelButton = value.boolValue }
      if let value = dict["isDark"] as? NSNumber { isDark = value.boolValue }
      if let style = dict["style"] as? [String: Any] {
        if let value = style["tint"] as? NSNumber { tint = Self.colorFromARGB(value.intValue) }
        if let value = style["backgroundColor"] as? NSNumber { bg = Self.colorFromARGB(value.intValue) }
        if let value = style["fieldBackgroundColor"] as? NSNumber { fieldBg = Self.colorFromARGB(value.intValue) }
      }
    }

    super.init()

    container.backgroundColor = .clear
    if #available(iOS 13.0, *) {
      container.overrideUserInterfaceStyle = isDark ? .dark : .light
    }

    searchBar.translatesAutoresizingMaskIntoConstraints = false
    searchBar.delegate = self
    searchBar.searchBarStyle = .minimal
    searchBar.text = text
    searchBar.placeholder = placeholder
    searchBar.showsCancelButton = showsCancelButton
    applyEnabled(enabled)
    if let color = tint { searchBar.tintColor = color }
    if let color = bg { searchBar.backgroundColor = color }
    if let color = fieldBg { searchBar.searchTextField.backgroundColor = color }

    container.addSubview(searchBar)
    NSLayoutConstraint.activate([
      searchBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      searchBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      searchBar.topAnchor.constraint(equalTo: container.topAnchor),
      searchBar.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "getIntrinsicSize":
        let width = max(self.container.bounds.width, 320)
        let size = self.searchBar.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        result(["width": Double(size.width), "height": Double(size.height)])
      case "setText":
        if let params = call.arguments as? [String: Any], let value = params["text"] as? String {
          self.searchBar.text = value
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing text", details: nil)) }
      case "setPlaceholder":
        if let params = call.arguments as? [String: Any] {
          if params["placeholder"] is NSNull {
            self.searchBar.placeholder = nil
          } else {
            self.searchBar.placeholder = params["placeholder"] as? String
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing placeholder", details: nil)) }
      case "setEnabled":
        if let params = call.arguments as? [String: Any], let value = (params["enabled"] as? NSNumber)?.boolValue {
          self.applyEnabled(value)
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing enabled", details: nil)) }
      case "setShowsCancelButton":
        if let params = call.arguments as? [String: Any], let value = (params["showsCancelButton"] as? NSNumber)?.boolValue {
          self.searchBar.setShowsCancelButton(value, animated: true)
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing showsCancelButton", details: nil)) }
      case "setStyle":
        if let params = call.arguments as? [String: Any] {
          if let value = params["tint"] as? NSNumber {
            self.searchBar.tintColor = Self.colorFromARGB(value.intValue)
          }
          if let value = params["backgroundColor"] as? NSNumber {
            self.searchBar.backgroundColor = Self.colorFromARGB(value.intValue)
          }
          if let value = params["fieldBackgroundColor"] as? NSNumber {
            self.searchBar.searchTextField.backgroundColor = Self.colorFromARGB(value.intValue)
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing style", details: nil)) }
      case "setBrightness":
        if let params = call.arguments as? [String: Any], let isDark = (params["isDark"] as? NSNumber)?.boolValue {
          if #available(iOS 13.0, *) {
            self.container.overrideUserInterfaceStyle = isDark ? .dark : .light
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil)) }
      case "focus":
        self.searchBar.becomeFirstResponder()
        result(nil)
      case "unfocus":
        self.searchBar.resignFirstResponder()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    return container
  }

  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    channel.invokeMethod("textChanged", arguments: ["text": searchText])
  }

  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    channel.invokeMethod("submitted", arguments: ["text": searchBar.text ?? ""])
    searchBar.resignFirstResponder()
  }

  func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
    searchBar.text = ""
    channel.invokeMethod("textChanged", arguments: ["text": ""])
    channel.invokeMethod("cancelled", arguments: nil)
    searchBar.resignFirstResponder()
  }

  private func applyEnabled(_ enabled: Bool) {
    searchBar.isUserInteractionEnabled = enabled
    searchBar.searchTextField.isEnabled = enabled
    searchBar.alpha = enabled ? 1.0 : 0.6
  }

  private static func colorFromARGB(_ argb: Int) -> UIColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
}
