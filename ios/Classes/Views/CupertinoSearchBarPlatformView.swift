import Flutter
import UIKit
import CoreText

class CupertinoSearchBarPlatformView: NSObject, FlutterPlatformView, UISearchBarDelegate {
  private struct FlutterFontManifestEntry {
    let family: String
    let assets: [String]
  }

  private static var cachedFlutterAssetsURL: URL?
  private static var cachedFontManifest: [FlutterFontManifestEntry]?

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
    var trailingIconDataCodePoint: Int? = nil
    var trailingIconDataFontFamily: String? = nil
    var trailingIconDataFontPackage: String? = nil
    var trailingIconDataMatchTextDirection: Bool = false
    var trailingIconEnabled: Bool = false

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
      if let value = dict["trailingIconDataCodePoint"] as? NSNumber { trailingIconDataCodePoint = value.intValue }
      if let value = dict["trailingIconDataFontFamily"] as? String { trailingIconDataFontFamily = value }
      if let value = dict["trailingIconDataFontPackage"] as? String { trailingIconDataFontPackage = value }
      if let value = dict["trailingIconDataMatchTextDirection"] as? NSNumber {
        trailingIconDataMatchTextDirection = value.boolValue
      }
      if let value = dict["trailingIconEnabled"] as? NSNumber { trailingIconEnabled = value.boolValue }
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
    applyTrailingButton(
      iconDataCodePoint: trailingIconDataCodePoint,
      iconDataFontFamily: trailingIconDataFontFamily,
      iconDataFontPackage: trailingIconDataFontPackage,
      iconDataMatchTextDirection: trailingIconDataMatchTextDirection,
      enabled: trailingIconEnabled
    )

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
      case "setTrailingButton":
        if let params = call.arguments as? [String: Any] {
          var iconDataCodePoint: Int? = nil
          var iconDataFontFamily: String? = nil
          var iconDataFontPackage: String? = nil
          var iconDataMatchTextDirection: Bool = false
          var iconEnabled: Bool = false

          if params["trailingIconDataCodePoint"] is NSNull {
            iconDataCodePoint = nil
          } else {
            iconDataCodePoint = (params["trailingIconDataCodePoint"] as? NSNumber)?.intValue
          }
          if params["trailingIconDataFontFamily"] is NSNull {
            iconDataFontFamily = nil
          } else {
            iconDataFontFamily = params["trailingIconDataFontFamily"] as? String
          }
          if params["trailingIconDataFontPackage"] is NSNull {
            iconDataFontPackage = nil
          } else {
            iconDataFontPackage = params["trailingIconDataFontPackage"] as? String
          }
          if let value = params["trailingIconDataMatchTextDirection"] as? NSNumber {
            iconDataMatchTextDirection = value.boolValue
          }
          if let value = params["trailingIconEnabled"] as? NSNumber {
            iconEnabled = value.boolValue
          }

          self.applyTrailingButton(
            iconDataCodePoint: iconDataCodePoint,
            iconDataFontFamily: iconDataFontFamily,
            iconDataFontPackage: iconDataFontPackage,
            iconDataMatchTextDirection: iconDataMatchTextDirection,
            enabled: iconEnabled
          )
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing trailing button args", details: nil)) }
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

  func searchBarBookmarkButtonClicked(_ searchBar: UISearchBar) {
    channel.invokeMethod("trailingPressed", arguments: nil)
  }

  private func applyEnabled(_ enabled: Bool) {
    searchBar.isUserInteractionEnabled = enabled
    searchBar.searchTextField.isEnabled = enabled
    searchBar.alpha = enabled ? 1.0 : 0.6
  }

  private func applyTrailingButton(
    iconDataCodePoint: Int?,
    iconDataFontFamily: String?,
    iconDataFontPackage: String?,
    iconDataMatchTextDirection: Bool,
    enabled: Bool
  ) {
    guard let codePoint = iconDataCodePoint,
          var image = Self.iconImage(
            codePoint: codePoint,
            fontFamily: iconDataFontFamily,
            fontPackage: iconDataFontPackage,
            pointSize: 16
          ) else {
      searchBar.showsBookmarkButton = false
      searchBar.setImage(nil, for: .bookmark, state: .normal)
      searchBar.setImage(nil, for: .bookmark, state: .highlighted)
      return
    }

    if iconDataMatchTextDirection {
      image = image.imageFlippedForRightToLeftLayoutDirection()
    }
    searchBar.setImage(image, for: .bookmark, state: .normal)
    searchBar.setImage(image, for: .bookmark, state: .highlighted)
    searchBar.showsBookmarkButton = enabled
  }

  private static func iconImage(
    codePoint: Int,
    fontFamily: String?,
    fontPackage: String?,
    pointSize: CGFloat
  ) -> UIImage? {
    guard let scalar = UnicodeScalar(codePoint) else { return nil }
    let glyph = String(scalar) as NSString
    let resolvedFont = loadIconFont(
      family: fontFamily,
      package: fontPackage,
      pointSize: pointSize
    ) ?? UIFont.systemFont(ofSize: pointSize)
    let canvasSize = CGSize(width: pointSize * 1.8, height: pointSize * 1.8)
    let renderer = UIGraphicsImageRenderer(size: canvasSize)
    let image = renderer.image { _ in
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      let attrs: [NSAttributedString.Key: Any] = [
        .font: resolvedFont,
        .foregroundColor: UIColor.white,
        .paragraphStyle: paragraph
      ]
      let glyphSize = glyph.size(withAttributes: attrs)
      let rect = CGRect(
        x: (canvasSize.width - glyphSize.width) / 2.0,
        y: (canvasSize.height - glyphSize.height) / 2.0,
        width: glyphSize.width,
        height: glyphSize.height
      )
      glyph.draw(in: rect, withAttributes: attrs)
    }
    return image.withRenderingMode(.alwaysTemplate)
  }

  private static func loadIconFont(
    family: String?,
    package: String?,
    pointSize: CGFloat
  ) -> UIFont? {
    guard let family else { return nil }
    ensureFlutterFontRegistered(family: family, package: package)

    let directCandidates = directFontNameCandidates(
      family: family,
      package: package
    )
    for candidate in directCandidates {
      if let font = UIFont(name: candidate, size: pointSize) {
        return font
      }
    }

    let wanted = normalizedFontToken(family)
    for familyName in UIFont.familyNames {
      let familyToken = normalizedFontToken(familyName)
      if familyToken == wanted || familyToken.contains(wanted) || wanted.contains(familyToken) {
        if let font = UIFont(name: familyName, size: pointSize) {
          return font
        }
      }
      for fontName in UIFont.fontNames(forFamilyName: familyName) {
        let fontToken = normalizedFontToken(fontName)
        if fontToken == wanted || fontToken.contains(wanted) || wanted.contains(fontToken) {
          if let font = UIFont(name: fontName, size: pointSize) {
            return font
          }
        }
      }
    }
    return nil
  }

  private static func directFontNameCandidates(family: String, package: String?) -> [String] {
    var candidates: [String] = []
    if let package {
      candidates.append("packages/\(package)/\(family)")
      candidates.append("\(package)/\(family)")
    }
    candidates.append(family)
    candidates.append("\(family)-Regular")
    candidates.append(family.replacingOccurrences(of: "_", with: " "))
    candidates.append(family.replacingOccurrences(of: "_", with: "") + "-Regular")
    if family == "MaterialIcons" {
      candidates.append("Material Icons")
      candidates.append("MaterialIcons-Regular")
    }
    if family == "CupertinoIcons" {
      candidates.append("Cupertino Icons")
    }
    return Array(Set(candidates))
  }

  private static func normalizedFontToken(_ text: String) -> String {
    let allowed = CharacterSet.alphanumerics
    return text.lowercased().unicodeScalars
      .filter { allowed.contains($0) }
      .map(String.init)
      .joined()
  }

  private static func ensureFlutterFontRegistered(family: String, package: String?) {
    let manifest = loadFontManifest()
    guard !manifest.isEmpty else { return }
    let candidates = [
      family,
      package != nil ? "packages/\(package!)/\(family)" : nil
    ].compactMap { $0 }

    for candidate in candidates {
      let entries = manifest.filter { $0.family == candidate }
      for entry in entries {
        registerFontAssets(entry.assets)
      }
    }
  }

  private static func registerFontAssets(_ assets: [String]) {
    guard let assetsRoot = flutterAssetsURL() else { return }
    for asset in assets {
      let fileURL = assetsRoot.appendingPathComponent(asset)
      guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
      CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, nil)
    }
  }

  private static func loadFontManifest() -> [FlutterFontManifestEntry] {
    if let cachedFontManifest {
      return cachedFontManifest
    }
    guard let assetsRoot = flutterAssetsURL() else {
      cachedFontManifest = []
      return []
    }
    let manifestURL = assetsRoot.appendingPathComponent("FontManifest.json")
    guard let data = try? Data(contentsOf: manifestURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      cachedFontManifest = []
      return []
    }

    let parsed = json.compactMap { item -> FlutterFontManifestEntry? in
      guard let family = item["family"] as? String else { return nil }
      let fonts = (item["fonts"] as? [[String: Any]]) ?? []
      let assets = fonts.compactMap { $0["asset"] as? String }
      return FlutterFontManifestEntry(family: family, assets: assets)
    }
    cachedFontManifest = parsed
    return parsed
  }

  private static func flutterAssetsURL() -> URL? {
    if let cachedFlutterAssetsURL {
      return cachedFlutterAssetsURL
    }
    let candidates: [URL?] = [
      Bundle.main.resourceURL?.appendingPathComponent("flutter_assets"),
      Bundle.main.privateFrameworksURL?
        .appendingPathComponent("App.framework")
        .appendingPathComponent("flutter_assets"),
      URL(fileURLWithPath: Bundle.main.bundlePath)
        .appendingPathComponent("Frameworks")
        .appendingPathComponent("App.framework")
        .appendingPathComponent("flutter_assets")
    ]
    for candidate in candidates.compactMap({ $0 }) {
      var isDir: ObjCBool = false
      if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
        cachedFlutterAssetsURL = candidate
        return candidate
      }
    }
    return nil
  }

  private static func colorFromARGB(_ argb: Int) -> UIColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
}
