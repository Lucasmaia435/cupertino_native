import FlutterMacOS
import Cocoa

class CupertinoSearchBarNSView: NSView, NSSearchFieldDelegate {
  private let channel: FlutterMethodChannel
  private let searchField: NSSearchField

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CupertinoNativeSearchBar_\(viewId)", binaryMessenger: messenger)
    self.searchField = NSSearchField(frame: .zero)

    var text: String = ""
    var placeholder: String? = nil
    var enabled: Bool = true
    var isDark: Bool = false
    var tint: NSColor? = nil
    var bg: NSColor? = nil
    var fieldBg: NSColor? = nil

    if let dict = args as? [String: Any] {
      if let value = dict["text"] as? String { text = value }
      if let value = dict["placeholder"] as? String { placeholder = value }
      if let value = dict["enabled"] as? NSNumber { enabled = value.boolValue }
      if let value = dict["isDark"] as? NSNumber { isDark = value.boolValue }
      if let style = dict["style"] as? [String: Any] {
        if let value = style["tint"] as? NSNumber { tint = Self.colorFromARGB(value.intValue) }
        if let value = style["backgroundColor"] as? NSNumber { bg = Self.colorFromARGB(value.intValue) }
        if let value = style["fieldBackgroundColor"] as? NSNumber { fieldBg = Self.colorFromARGB(value.intValue) }
      }
    }

    super.init(frame: .zero)

    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

    searchField.translatesAutoresizingMaskIntoConstraints = false
    searchField.delegate = self
    searchField.target = self
    searchField.action = #selector(onSubmit(_:))
    searchField.sendsSearchStringImmediately = true
    searchField.stringValue = text
    searchField.placeholderString = placeholder
    searchField.isEnabled = enabled
    if let color = tint, #available(macOS 10.14, *) {
      searchField.contentTintColor = color
    }
    if let color = fieldBg {
      searchField.drawsBackground = true
      searchField.backgroundColor = color
    }
    if let color = bg {
      layer?.backgroundColor = color.cgColor
    }

    addSubview(searchField)
    NSLayoutConstraint.activate([
      searchField.leadingAnchor.constraint(equalTo: leadingAnchor),
      searchField.trailingAnchor.constraint(equalTo: trailingAnchor),
      searchField.topAnchor.constraint(equalTo: topAnchor),
      searchField.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "getIntrinsicSize":
        let size = self.searchField.intrinsicContentSize
        result(["width": Double(size.width), "height": Double(size.height)])
      case "setText":
        if let params = call.arguments as? [String: Any], let value = params["text"] as? String {
          self.searchField.stringValue = value
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing text", details: nil)) }
      case "setPlaceholder":
        if let params = call.arguments as? [String: Any] {
          if params["placeholder"] is NSNull {
            self.searchField.placeholderString = nil
          } else {
            self.searchField.placeholderString = params["placeholder"] as? String
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing placeholder", details: nil)) }
      case "setEnabled":
        if let params = call.arguments as? [String: Any], let value = (params["enabled"] as? NSNumber)?.boolValue {
          self.searchField.isEnabled = value
          self.searchField.alphaValue = value ? 1.0 : 0.6
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing enabled", details: nil)) }
      case "setShowsCancelButton":
        // NSSearchField controls cancel affordance automatically based on text.
        result(nil)
      case "setStyle":
        if let params = call.arguments as? [String: Any] {
          if let value = params["tint"] as? NSNumber, #available(macOS 10.14, *) {
            self.searchField.contentTintColor = Self.colorFromARGB(value.intValue)
          }
          if let value = params["backgroundColor"] as? NSNumber {
            self.layer?.backgroundColor = Self.colorFromARGB(value.intValue).cgColor
          }
          if let value = params["fieldBackgroundColor"] as? NSNumber {
            self.searchField.drawsBackground = true
            self.searchField.backgroundColor = Self.colorFromARGB(value.intValue)
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing style", details: nil)) }
      case "setBrightness":
        if let params = call.arguments as? [String: Any], let isDark = (params["isDark"] as? NSNumber)?.boolValue {
          self.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil)) }
      case "focus":
        self.window?.makeFirstResponder(self.searchField)
        result(nil)
      case "unfocus":
        self.window?.makeFirstResponder(self)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  required init?(coder: NSCoder) {
    return nil
  }

  func controlTextDidChange(_ obj: Notification) {
    channel.invokeMethod("textChanged", arguments: ["text": searchField.stringValue])
  }

  @objc private func onSubmit(_ sender: NSSearchField) {
    channel.invokeMethod("submitted", arguments: ["text": sender.stringValue])
  }

  private static func colorFromARGB(_ argb: Int) -> NSColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
  }
}
