import FlutterMacOS
import Cocoa
import CoreText

class CupertinoButtonNSView: NSView {
  private struct FlutterFontManifestEntry {
    let family: String
    let assets: [String]
  }

  private static var cachedFlutterAssetsURL: URL?
  private static var cachedFontManifest: [FlutterFontManifestEntry]?

  private let channel: FlutterMethodChannel
  private let button: NSButton
  private var isEnabled: Bool = true
  private var currentButtonStyle: String = "automatic"
  private var currentTintColor: NSColor? = nil
  private var currentBackgroundColor: NSColor? = nil
  private var isRoundButton: Bool = false

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CupertinoNativeButton_\(viewId)", binaryMessenger: messenger)
    self.button = NSButton(title: "", target: nil, action: nil)
    super.init(frame: .zero)

    var title: String? = nil
    var iconName: String? = nil
    var iconSize: CGFloat? = nil
    var iconColor: NSColor? = nil
    var makeRound: Bool = false
    var buttonStyle: String = "automatic"
    var isDark: Bool = false
    var tint: NSColor? = nil
    var backgroundColor: NSColor? = nil
    var enabled: Bool = true
    var iconMode: String? = nil
    var iconPalette: [NSNumber] = []
    var iconDataCodePoint: Int? = nil
    var iconDataFontFamily: String? = nil
    var iconDataFontPackage: String? = nil
    var iconDataFill: CGFloat? = nil
    var iconDataWeight: CGFloat? = nil
    var iconDataGrade: CGFloat? = nil
    var iconDataOpticalSize: CGFloat? = nil

    if let dict = args as? [String: Any] {
      if let t = dict["buttonTitle"] as? String { title = t }
      if let s = dict["buttonIconName"] as? String { iconName = s }
      if let s = dict["buttonIconSize"] as? NSNumber { iconSize = CGFloat(truncating: s) }
      if let c = dict["buttonIconColor"] as? NSNumber { iconColor = Self.colorFromARGB(c.intValue) }
      if let r = dict["round"] as? NSNumber { makeRound = r.boolValue }
      if let bs = dict["buttonStyle"] as? String { buttonStyle = bs }
      if let v = dict["isDark"] as? NSNumber { isDark = v.boolValue }
      if let style = dict["style"] as? [String: Any] {
        if let n = style["tint"] as? NSNumber { tint = Self.colorFromARGB(n.intValue) }
        if let n = style["backgroundColor"] as? NSNumber {
          backgroundColor = Self.colorFromARGB(n.intValue)
        }
      }
      if let e = dict["enabled"] as? NSNumber { enabled = e.boolValue }
      if let m = dict["buttonIconRenderingMode"] as? String { iconMode = m }
      if let pal = dict["buttonIconPaletteColors"] as? [NSNumber] { iconPalette = pal }
      if let cp = dict["buttonIconDataCodePoint"] as? NSNumber {
        iconDataCodePoint = cp.intValue
      }
      if let family = dict["buttonIconDataFontFamily"] as? String {
        iconDataFontFamily = family
      }
      if let package = dict["buttonIconDataFontPackage"] as? String {
        iconDataFontPackage = package
      }
      if let value = dict["buttonIconDataFill"] as? NSNumber {
        iconDataFill = CGFloat(truncating: value)
      }
      if let value = dict["buttonIconDataWeight"] as? NSNumber {
        iconDataWeight = CGFloat(truncating: value)
      }
      if let value = dict["buttonIconDataGrade"] as? NSNumber {
        iconDataGrade = CGFloat(truncating: value)
      }
      if let value = dict["buttonIconDataOpticalSize"] as? NSNumber {
        iconDataOpticalSize = CGFloat(truncating: value)
      }
    }

    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    currentTintColor = tint
    currentBackgroundColor = backgroundColor
    currentButtonStyle = buttonStyle
    isRoundButton = makeRound

    if let t = title { button.title = t }
    if let name = iconName, var image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
      if #available(macOS 12.0, *), let sz = iconSize {
        let cfg = NSImage.SymbolConfiguration(pointSize: sz, weight: .regular)
        image = image.withSymbolConfiguration(cfg) ?? image
      }
      if let mode = iconMode {
        switch mode {
        case "hierarchical":
          if #available(macOS 12.0, *), let c = iconColor {
            let cfg = NSImage.SymbolConfiguration(hierarchicalColor: c)
            image = image.withSymbolConfiguration(cfg) ?? image
          }
        case "palette":
          if #available(macOS 12.0, *), !iconPalette.isEmpty {
            let cols = iconPalette.map { Self.colorFromARGB($0.intValue) }
            let cfg = NSImage.SymbolConfiguration(paletteColors: cols)
            image = image.withSymbolConfiguration(cfg) ?? image
          }
        case "multicolor":
          if #available(macOS 12.0, *) {
            let cfg = NSImage.SymbolConfiguration.preferringMulticolor()
            image = image.withSymbolConfiguration(cfg) ?? image
          }
        case "monochrome":
          if let c = iconColor { image = image.tinted(with: c) }
        default:
          break
        }
      } else if let c = iconColor { image = image.tinted(with: c) }
      button.image = image
      button.imagePosition = .imageOnly
    } else if let codePoint = iconDataCodePoint,
              let image = Self.iconImage(
                codePoint: codePoint,
                fontFamily: iconDataFontFamily,
                fontPackage: iconDataFontPackage,
                pointSize: iconSize ?? 18,
                fill: iconDataFill,
                weight: iconDataWeight,
                grade: iconDataGrade,
                opticalSize: iconDataOpticalSize
              ) {
      button.image = image
      button.imagePosition = .imageOnly
    }
    applyButtonStyle()
    button.setButtonType(.momentaryPushIn)
    button.isEnabled = enabled
    isEnabled = enabled

    addSubview(button)
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: leadingAnchor),
      button.trailingAnchor.constraint(equalTo: trailingAnchor),
      button.topAnchor.constraint(equalTo: topAnchor),
      button.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])

    button.target = self
    button.action = #selector(onPressed(_:))

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "getIntrinsicSize":
        let s = self.button.intrinsicContentSize
        result(["width": Double(s.width), "height": Double(s.height)])
      case "setStyle":
        if let args = call.arguments as? [String: Any] {
          var shouldReapplyStyle = false
          if let n = args["tint"] as? NSNumber {
            self.currentTintColor = Self.colorFromARGB(n.intValue)
            shouldReapplyStyle = true
          }
          if args["backgroundColor"] is NSNull {
            self.currentBackgroundColor = nil
            shouldReapplyStyle = true
          } else if let n = args["backgroundColor"] as? NSNumber {
            self.currentBackgroundColor = Self.colorFromARGB(n.intValue)
            shouldReapplyStyle = true
          }
          if let bs = args["buttonStyle"] as? String {
            self.currentButtonStyle = bs
            shouldReapplyStyle = true
          }
          if shouldReapplyStyle {
            self.applyButtonStyle()
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing style", details: nil)) }
      case "setButtonTitle":
        if let args = call.arguments as? [String: Any], let t = args["title"] as? String {
          self.button.title = t
          self.button.image = nil
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing title", details: nil)) }
      case "setEnabled":
        if let args = call.arguments as? [String: Any], let e = args["enabled"] as? NSNumber {
          self.isEnabled = e.boolValue
          self.button.isEnabled = self.isEnabled
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing enabled", details: nil)) }
      case "setButtonIcon":
        if let args = call.arguments as? [String: Any] {
          if let image = Self.buttonImage(from: args) {
            self.button.image = image
            self.button.title = ""
            self.button.imagePosition = .imageOnly
          }
          if let r = args["round"] as? NSNumber, r.boolValue { self.button.bezelStyle = .circular }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing icon args", details: nil)) }
      case "setVisible":
        if let args = call.arguments as? [String: Any], let visible = (args["visible"] as? NSNumber)?.boolValue {
          self.isHidden = !visible
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing visible", details: nil)) }
      case "setBrightness":
        if let args = call.arguments as? [String: Any], let isDark = (args["isDark"] as? NSNumber)?.boolValue {
          self.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil)) }
      case "setPressed":
        if let args = call.arguments as? [String: Any], let p = args["pressed"] as? NSNumber {
          self.alphaValue = p.boolValue ? 0.7 : 1.0
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing pressed", details: nil)) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  required init?(coder: NSCoder) { return nil }

  @objc private func onPressed(_ sender: NSButton) {
    guard isEnabled else { return }
    channel.invokeMethod("pressed", arguments: nil)
  }

  private static func buttonImage(from args: [String: Any]) -> NSImage? {
    let pointSize = (args["buttonIconSize"] as? NSNumber).map { CGFloat(truncating: $0) }

    if let name = args["buttonIconName"] as? String,
       var image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
      if #available(macOS 12.0, *), let size = pointSize {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        image = image.withSymbolConfiguration(cfg) ?? image
      }
      if let mode = args["buttonIconRenderingMode"] as? String {
        switch mode {
        case "hierarchical":
          if #available(macOS 12.0, *), let c = args["buttonIconColor"] as? NSNumber {
            let cfg = NSImage.SymbolConfiguration(hierarchicalColor: Self.colorFromARGB(c.intValue))
            image = image.withSymbolConfiguration(cfg) ?? image
          }
        case "palette":
          if #available(macOS 12.0, *), let pal = args["buttonIconPaletteColors"] as? [NSNumber] {
            let cols = pal.map { Self.colorFromARGB($0.intValue) }
            let cfg = NSImage.SymbolConfiguration(paletteColors: cols)
            image = image.withSymbolConfiguration(cfg) ?? image
          }
        case "multicolor":
          if #available(macOS 12.0, *) {
            let cfg = NSImage.SymbolConfiguration.preferringMulticolor()
            image = image.withSymbolConfiguration(cfg) ?? image
          }
        case "monochrome":
          if let c = args["buttonIconColor"] as? NSNumber {
            image = image.tinted(with: Self.colorFromARGB(c.intValue))
          }
        default:
          break
        }
      } else if let c = args["buttonIconColor"] as? NSNumber {
        image = image.tinted(with: Self.colorFromARGB(c.intValue))
      }
      return image
    }

    guard let codePoint = (args["buttonIconDataCodePoint"] as? NSNumber)?.intValue else {
      return nil
    }
    let fontFamily = args["buttonIconDataFontFamily"] as? String
    let fontPackage = args["buttonIconDataFontPackage"] as? String
    let fill = (args["buttonIconDataFill"] as? NSNumber).map { CGFloat(truncating: $0) }
    let weight = (args["buttonIconDataWeight"] as? NSNumber).map { CGFloat(truncating: $0) }
    let grade = (args["buttonIconDataGrade"] as? NSNumber).map { CGFloat(truncating: $0) }
    let opticalSize = (args["buttonIconDataOpticalSize"] as? NSNumber).map { CGFloat(truncating: $0) }
    let size = pointSize ?? 18
    return iconImage(
      codePoint: codePoint,
      fontFamily: fontFamily,
      fontPackage: fontPackage,
      pointSize: size,
      fill: fill,
      weight: weight,
      grade: grade,
      opticalSize: opticalSize
    )
  }

  private static func iconImage(
    codePoint: Int,
    fontFamily: String?,
    fontPackage: String?,
    pointSize: CGFloat,
    fill: CGFloat?,
    weight: CGFloat?,
    grade: CGFloat?,
    opticalSize: CGFloat?
  ) -> NSImage? {
    guard let scalar = UnicodeScalar(codePoint) else { return nil }
    let glyph = String(scalar) as NSString
    let resolvedFont = loadIconFont(
      family: fontFamily,
      package: fontPackage,
      pointSize: pointSize,
      fill: fill,
      weight: weight,
      grade: grade,
      opticalSize: opticalSize
    ) ?? NSFont.systemFont(ofSize: pointSize)
    let canvasSize = NSSize(width: pointSize * 1.8, height: pointSize * 1.8)
    let image = NSImage(size: canvasSize)
    image.lockFocus()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
      .font: resolvedFont,
      .foregroundColor: NSColor.labelColor,
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
    return image
  }

  private static func loadIconFont(
    family: String?,
    package: String?,
    pointSize: CGFloat,
    fill: CGFloat?,
    weight: CGFloat?,
    grade: CGFloat?,
    opticalSize: CGFloat?
  ) -> NSFont? {
    guard let family else { return nil }
    ensureFlutterFontRegistered(family: family, package: package)

    let directCandidates = directFontNameCandidates(
      family: family,
      package: package
    )
    for candidate in directCandidates {
      if let font = NSFont(name: candidate, size: pointSize) {
        return applyFontVariations(
          to: font,
          fill: fill,
          weight: weight,
          grade: grade,
          opticalSize: opticalSize
        )
      }
    }

    let wanted = normalizedFontToken(family)
    for familyName in NSFontManager.shared.availableFontFamilies {
      let familyToken = normalizedFontToken(familyName)
      if familyToken == wanted || familyToken.contains(wanted) || wanted.contains(familyToken) {
        if let font = NSFont(name: familyName, size: pointSize) {
          return applyFontVariations(
            to: font,
            fill: fill,
            weight: weight,
            grade: grade,
            opticalSize: opticalSize
          )
        }
      }
      if let members = NSFontManager.shared.availableMembers(ofFontFamily: familyName) {
        for member in members {
          if member.count > 0, let fontName = member[0] as? String {
            let fontToken = normalizedFontToken(fontName)
            if fontToken == wanted || fontToken.contains(wanted) || wanted.contains(fontToken) {
              if let font = NSFont(name: fontName, size: pointSize) {
                return applyFontVariations(
                  to: font,
                  fill: fill,
                  weight: weight,
                  grade: grade,
                  opticalSize: opticalSize
                )
              }
            }
          }
        }
      }
    }
    return nil
  }

  private static func applyFontVariations(
    to font: NSFont,
    fill: CGFloat?,
    weight: CGFloat?,
    grade: CGFloat?,
    opticalSize: CGFloat?
  ) -> NSFont {
    guard fill != nil || weight != nil || grade != nil || opticalSize != nil else {
      return font
    }
    guard let axes = CTFontCopyVariationAxes(font as CTFont) as? [[CFString: Any]] else {
      return font
    }
    var variations: [NSNumber: NSNumber] = [:]
    for axis in axes {
      guard let axisId = axis[kCTFontVariationAxisIdentifierKey] as? NSNumber,
            let axisName = (axis[kCTFontVariationAxisNameKey] as? String)?.lowercased() else {
        continue
      }
      let minValue = (axis[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.doubleValue
      let maxValue = (axis[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.doubleValue
      func setVariation(_ value: CGFloat?) {
        guard let value else { return }
        var clamped = Double(value)
        if let minValue { clamped = max(clamped, minValue) }
        if let maxValue { clamped = min(clamped, maxValue) }
        variations[axisId] = NSNumber(value: clamped)
      }

      if axisName.contains("fill") {
        setVariation(fill)
      } else if axisName.contains("weight") {
        setVariation(weight)
      } else if axisName.contains("grade") {
        setVariation(grade)
      } else if axisName.contains("optical") || axisName.contains("opsz") {
        setVariation(opticalSize)
      }
    }
    guard !variations.isEmpty else { return font }
    let variationAttr = NSFontDescriptor.AttributeName(
      rawValue: kCTFontVariationAttribute as String
    )
    let descriptor = font.fontDescriptor.addingAttributes([
      variationAttr: variations
    ])
    return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
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

  private func applyButtonStyle() {
    switch currentButtonStyle {
    case "plain":
      button.bezelStyle = .texturedRounded
      button.isBordered = false
    case "gray": button.bezelStyle = .texturedRounded
    case "tinted": button.bezelStyle = .texturedRounded
    case "bordered": button.bezelStyle = .rounded
    case "borderedProminent": button.bezelStyle = .rounded
    case "filled": button.bezelStyle = .rounded
    case "glass": button.bezelStyle = .texturedRounded
    case "prominentGlass": button.bezelStyle = .texturedRounded
    default: button.bezelStyle = .rounded
    }
    if currentButtonStyle != "plain" {
      button.isBordered = true
    }
    if isRoundButton {
      button.bezelStyle = .circular
    }

    if #available(macOS 10.14, *) {
      if let tint = currentTintColor {
        if ["filled", "borderedProminent", "prominentGlass"].contains(currentButtonStyle) {
          button.contentTintColor = .white
        } else {
          button.contentTintColor = tint
        }
      }

      if let background = currentBackgroundColor {
        button.bezelColor = background
        if currentButtonStyle == "plain" {
          button.isBordered = true
          button.bezelStyle = isRoundButton ? .circular : .rounded
        }
      } else if ["filled", "borderedProminent", "prominentGlass"].contains(currentButtonStyle),
                let tint = currentTintColor {
        button.bezelColor = tint
      } else {
        button.bezelColor = nil
      }
    }
  }
}

private extension NSImage {
  func tinted(with color: NSColor) -> NSImage {
    guard isTemplate else { return self }
    let image = self.copy() as! NSImage
    image.lockFocus()
    color.set()
    let imageRect = NSRect(origin: .zero, size: image.size)
    imageRect.fill(using: .sourceAtop)
    image.unlockFocus()
    image.isTemplate = false
    return image
  }
}
