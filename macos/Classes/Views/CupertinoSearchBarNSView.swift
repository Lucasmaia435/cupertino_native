import FlutterMacOS
import Cocoa
import CoreText

class CupertinoSearchBarNSView: NSView, NSSearchFieldDelegate {
  private struct FlutterFontManifestEntry {
    let family: String
    let assets: [String]
  }

  private static var cachedFlutterAssetsURL: URL?
  private static var cachedFontManifest: [FlutterFontManifestEntry]?

  private let channel: FlutterMethodChannel
  private let searchField: NSSearchField
  private let trailingButton: NSButton
  private var searchFieldTrailingConstraint: NSLayoutConstraint!
  private var trailingButtonEnabled: Bool = false

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CupertinoNativeSearchBar_\(viewId)", binaryMessenger: messenger)
    self.searchField = NSSearchField(frame: .zero)
    self.trailingButton = NSButton(title: "", target: nil, action: nil)

    var text: String = ""
    var placeholder: String? = nil
    var enabled: Bool = true
    var isDark: Bool = false
    var tint: NSColor? = nil
    var bg: NSColor? = nil
    var fieldBg: NSColor? = nil
    var trailingIconDataCodePoint: Int? = nil
    var trailingIconDataFontFamily: String? = nil
    var trailingIconDataFontPackage: String? = nil
    var trailingIconDataMatchTextDirection: Bool = false
    var trailingIconEnabled: Bool = false

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
      if let value = dict["trailingIconDataCodePoint"] as? NSNumber { trailingIconDataCodePoint = value.intValue }
      if let value = dict["trailingIconDataFontFamily"] as? String { trailingIconDataFontFamily = value }
      if let value = dict["trailingIconDataFontPackage"] as? String { trailingIconDataFontPackage = value }
      if let value = dict["trailingIconDataMatchTextDirection"] as? NSNumber {
        trailingIconDataMatchTextDirection = value.boolValue
      }
      if let value = dict["trailingIconEnabled"] as? NSNumber { trailingIconEnabled = value.boolValue }
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

    trailingButton.translatesAutoresizingMaskIntoConstraints = false
    trailingButton.bezelStyle = .shadowlessSquare
    trailingButton.isBordered = false
    trailingButton.imagePosition = .imageOnly
    trailingButton.setButtonType(.momentaryChange)
    trailingButton.target = self
    trailingButton.action = #selector(onTrailingPressed(_:))
    trailingButton.isHidden = true
    trailingButton.isEnabled = false

    if let color = tint, #available(macOS 10.14, *) {
      searchField.contentTintColor = color
      trailingButton.contentTintColor = color
    }
    if let color = fieldBg {
      searchField.drawsBackground = true
      searchField.backgroundColor = color
    }
    if let color = bg {
      layer?.backgroundColor = color.cgColor
    }

    addSubview(searchField)
    addSubview(trailingButton)
    searchFieldTrailingConstraint = searchField.trailingAnchor.constraint(equalTo: trailingAnchor)
    NSLayoutConstraint.activate([
      searchField.leadingAnchor.constraint(equalTo: leadingAnchor),
      searchFieldTrailingConstraint,
      searchField.topAnchor.constraint(equalTo: topAnchor),
      searchField.bottomAnchor.constraint(equalTo: bottomAnchor),
      trailingButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      trailingButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
      trailingButton.widthAnchor.constraint(equalToConstant: 18),
      trailingButton.heightAnchor.constraint(equalToConstant: 18)
    ])

    applyTrailingButton(
      iconDataCodePoint: trailingIconDataCodePoint,
      iconDataFontFamily: trailingIconDataFontFamily,
      iconDataFontPackage: trailingIconDataFontPackage,
      iconDataMatchTextDirection: trailingIconDataMatchTextDirection,
      enabled: trailingIconEnabled
    )
    applyEnabled(enabled)

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
          self.applyEnabled(value)
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing enabled", details: nil)) }
      case "setShowsCancelButton":
        // NSSearchField controls cancel affordance automatically based on text.
        result(nil)
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
          if let value = params["tint"] as? NSNumber, #available(macOS 10.14, *) {
            self.searchField.contentTintColor = Self.colorFromARGB(value.intValue)
            self.trailingButton.contentTintColor = Self.colorFromARGB(value.intValue)
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

  @objc private func onTrailingPressed(_ sender: NSButton) {
    guard trailingButtonEnabled, searchField.isEnabled else { return }
    channel.invokeMethod("trailingPressed", arguments: nil)
  }

  private func applyEnabled(_ enabled: Bool) {
    searchField.isEnabled = enabled
    searchField.alphaValue = enabled ? 1.0 : 0.6
    trailingButton.isEnabled = enabled && trailingButtonEnabled
    trailingButton.alphaValue = trailingButton.isEnabled ? 1.0 : 0.6
  }

  private func applyTrailingButton(
    iconDataCodePoint: Int?,
    iconDataFontFamily: String?,
    iconDataFontPackage: String?,
    iconDataMatchTextDirection: Bool,
    enabled: Bool
  ) {
    guard let codePoint = iconDataCodePoint,
          let image = Self.iconImage(
            codePoint: codePoint,
            fontFamily: iconDataFontFamily,
            fontPackage: iconDataFontPackage,
            pointSize: 16
          ) else {
      trailingButton.image = nil
      trailingButton.isHidden = true
      trailingButtonEnabled = false
      searchFieldTrailingConstraint.constant = 0
      return
    }

    let _ = iconDataMatchTextDirection

    trailingButton.image = image
    trailingButton.isHidden = false
    trailingButtonEnabled = enabled
    searchFieldTrailingConstraint.constant = -28
    applyEnabled(searchField.isEnabled)
  }

  private static func iconImage(
    codePoint: Int,
    fontFamily: String?,
    fontPackage: String?,
    pointSize: CGFloat
  ) -> NSImage? {
    guard let scalar = UnicodeScalar(codePoint) else { return nil }
    let glyph = String(scalar) as NSString
    let resolvedFont = loadIconFont(
      family: fontFamily,
      package: fontPackage,
      pointSize: pointSize
    ) ?? NSFont.systemFont(ofSize: pointSize)
    let canvasSize = NSSize(width: pointSize * 1.8, height: pointSize * 1.8)
    let image = NSImage(size: canvasSize)
    image.lockFocus()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
      .font: resolvedFont,
      .foregroundColor: NSColor.black,
      .paragraphStyle: paragraph
    ]
    let glyphSize = glyph.size(withAttributes: attrs)
    let rect = NSRect(
      x: (canvasSize.width - glyphSize.width) / 2.0,
      y: (canvasSize.height - glyphSize.height) / 2.0,
      width: glyphSize.width,
      height: glyphSize.height
    )
    glyph.draw(in: rect, withAttributes: attrs)
    image.unlockFocus()
    image.isTemplate = true
    return image
  }

  private static func loadIconFont(
    family: String?,
    package: String?,
    pointSize: CGFloat
  ) -> NSFont? {
    guard let family else { return nil }
    ensureFlutterFontRegistered(family: family, package: package)

    let directCandidates = directFontNameCandidates(
      family: family,
      package: package
    )
    for candidate in directCandidates {
      if let font = NSFont(name: candidate, size: pointSize) {
        return font
      }
    }

    let wanted = normalizedFontToken(family)
    for familyName in NSFontManager.shared.availableFontFamilies {
      let familyToken = normalizedFontToken(familyName)
      if familyToken == wanted || familyToken.contains(wanted) || wanted.contains(familyToken) {
        if let font = NSFont(name: familyName, size: pointSize) {
          return font
        }
      }
      if let members = NSFontManager.shared.availableMembers(ofFontFamily: familyName) {
        for member in members {
          if member.count > 0, let fontName = member[0] as? String {
            let fontToken = normalizedFontToken(fontName)
            if fontToken == wanted || fontToken.contains(wanted) || wanted.contains(fontToken) {
              if let font = NSFont(name: fontName, size: pointSize) {
                return font
              }
            }
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

  private static func colorFromARGB(_ argb: Int) -> NSColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
  }
}
