import FlutterMacOS
import Cocoa
import CoreText
import SwiftUI

private struct ButtonBackgroundGradient {
  let colors: [NSColor]
  let locations: [CGFloat]?
  let startPoint: CGPoint
  let endPoint: CGPoint
}

private final class ButtonGradientBackgroundView: NSView {
  var isRound: Bool = false {
    didSet { needsLayout = true }
  }

  var gradient: ButtonBackgroundGradient? {
    didSet { updateGradient() }
  }

  private let gradientLayer = CAGradientLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.masksToBounds = true
    layer?.addSublayer(gradientLayer)
    isHidden = true
  }

  required init?(coder: NSCoder) { return nil }

  override func layout() {
    super.layout()
    gradientLayer.frame = bounds
    layer?.cornerRadius = min(bounds.width, bounds.height) / 2.0
  }

  private func updateGradient() {
    guard let gradient else {
      gradientLayer.colors = nil
      gradientLayer.locations = nil
      isHidden = true
      return
    }

    gradientLayer.colors = gradient.colors.map(\.cgColor)
    gradientLayer.locations = gradient.locations?.map {
      NSNumber(value: Double($0))
    }
    gradientLayer.startPoint = gradient.startPoint
    gradientLayer.endPoint = gradient.endPoint
    isHidden = false
  }
}

@available(macOS 26.0, *)
private struct GlassGradientChrome: View {
  let gradient: ButtonBackgroundGradient
  let isRound: Bool
  let isEnabled: Bool

  private var gradientStops: [Gradient.Stop] {
    if let locations = gradient.locations, locations.count == gradient.colors.count {
      return zip(gradient.colors, locations).map { color, location in
        Gradient.Stop(
          color: Color(nsColor: color),
          location: Double(location)
        )
      }
    }

    guard gradient.colors.count > 1 else {
      return gradient.colors.map { Gradient.Stop(color: Color(nsColor: $0), location: 0) }
    }

    let step = 1.0 / Double(gradient.colors.count - 1)
    return gradient.colors.enumerated().map { index, color in
      Gradient.Stop(
        color: Color(nsColor: color),
        location: Double(index) * step
      )
    }
  }

  private var linearGradient: LinearGradient {
    LinearGradient(
      gradient: Gradient(stops: gradientStops),
      startPoint: UnitPoint(x: gradient.startPoint.x, y: gradient.startPoint.y),
      endPoint: UnitPoint(x: gradient.endPoint.x, y: gradient.endPoint.y)
    )
  }

  var body: some View {
    Group {
      if isRound {
        let shape = Circle()
        ZStack {
          linearGradient.clipShape(shape)
          shape
            .fill(Color.clear)
            .glassEffect(.regular, in: shape)
            .opacity(isEnabled ? 1.0 : 0.9)
        }
      } else {
        let shape = Capsule()
        ZStack {
          linearGradient.clipShape(shape)
          shape
            .fill(Color.clear)
            .glassEffect(.regular, in: shape)
            .opacity(isEnabled ? 1.0 : 0.9)
        }
      }
    }
    .allowsHitTesting(false)
  }
}

class CupertinoButtonNSView: NSView {
  private struct FlutterFontManifestEntry {
    let family: String
    let assets: [String]
  }

  private static var cachedFlutterAssetsURL: URL?
  private static var cachedFontManifest: [FlutterFontManifestEntry]?

  private let channel: FlutterMethodChannel
  private let gradientBackgroundView: ButtonGradientBackgroundView
  private let button: NSButton
  private let gradientBackgroundInset: CGFloat = 3.0
  private let implicitAnimationDuration: TimeInterval = 0.2
  private var gradientLeadingConstraint: NSLayoutConstraint?
  private var gradientTrailingConstraint: NSLayoutConstraint?
  private var gradientTopConstraint: NSLayoutConstraint?
  private var gradientBottomConstraint: NSLayoutConstraint?
  private var glassHostingView: NSHostingView<AnyView>?
  private var glassLeadingConstraint: NSLayoutConstraint?
  private var glassTrailingConstraint: NSLayoutConstraint?
  private var glassTopConstraint: NSLayoutConstraint?
  private var glassBottomConstraint: NSLayoutConstraint?
  private var isEnabled: Bool = true
  private var currentButtonStyle: String = "automatic"
  private var currentTintColor: NSColor? = nil
  private var currentBackgroundColor: NSColor? = nil
  private var currentBackgroundGradient: ButtonBackgroundGradient? = nil
  private var isRoundButton: Bool = false

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CupertinoNativeButton_\(viewId)", binaryMessenger: messenger)
    self.gradientBackgroundView = ButtonGradientBackgroundView(frame: .zero)
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
    var backgroundGradient: ButtonBackgroundGradient? = nil
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
        backgroundGradient = Self.backgroundGradient(from: style["backgroundGradient"])
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
    button.wantsLayer = true
    currentTintColor = tint
    currentBackgroundColor = backgroundColor
    currentBackgroundGradient = backgroundGradient
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
                color: iconColor,
                fill: iconDataFill,
                weight: iconDataWeight,
                grade: iconDataGrade,
                opticalSize: iconDataOpticalSize
              ) {
      button.image = image
      button.imagePosition = .imageOnly
    }
    addSubview(gradientBackgroundView)
    addSubview(button)
    gradientBackgroundView.translatesAutoresizingMaskIntoConstraints = false
    button.translatesAutoresizingMaskIntoConstraints = false
    gradientLeadingConstraint = gradientBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor)
    gradientTrailingConstraint = gradientBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor)
    gradientTopConstraint = gradientBackgroundView.topAnchor.constraint(equalTo: topAnchor)
    gradientBottomConstraint = gradientBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor)
    NSLayoutConstraint.activate([
      gradientLeadingConstraint!,
      gradientTrailingConstraint!,
      gradientTopConstraint!,
      gradientBottomConstraint!,
      button.leadingAnchor.constraint(equalTo: leadingAnchor),
      button.trailingAnchor.constraint(equalTo: trailingAnchor),
      button.topAnchor.constraint(equalTo: topAnchor),
      button.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])

    isEnabled = enabled
    button.setButtonType(.momentaryPushIn)
    button.isEnabled = enabled
    applyButtonStyle()

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
          if args["backgroundGradient"] is NSNull {
            self.currentBackgroundGradient = nil
            shouldReapplyStyle = true
          } else if let gradient = Self.backgroundGradient(from: args["backgroundGradient"]) {
            self.currentBackgroundGradient = gradient
            shouldReapplyStyle = true
          }
          if let bs = args["buttonStyle"] as? String {
            self.currentButtonStyle = bs
            shouldReapplyStyle = true
          }
          if shouldReapplyStyle {
            self.performAnimatedUpdates {
              self.applyButtonStyle()
            }
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing style", details: nil)) }
      case "setButtonTitle":
        if let args = call.arguments as? [String: Any], let t = args["title"] as? String {
          self.performAnimatedUpdates {
            self.button.title = t
            self.button.image = nil
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing title", details: nil)) }
      case "setEnabled":
        if let args = call.arguments as? [String: Any], let e = args["enabled"] as? NSNumber {
          self.performAnimatedUpdates {
            self.isEnabled = e.boolValue
            self.button.isEnabled = self.isEnabled
            self.updateGradientBackground()
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing enabled", details: nil)) }
      case "setButtonIcon":
        if let args = call.arguments as? [String: Any] {
          self.performAnimatedUpdates {
            if let image = Self.buttonImage(from: args) {
              self.button.image = image
              self.button.title = ""
              self.button.imagePosition = .imageOnly
            }
            if let r = args["round"] as? NSNumber, r.boolValue {
              self.button.bezelStyle = .circular
            }
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing icon args", details: nil)) }
      case "setVisible":
        if let args = call.arguments as? [String: Any], let visible = (args["visible"] as? NSNumber)?.boolValue {
          self.isHidden = !visible
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing visible", details: nil)) }
      case "setBrightness":
        if let args = call.arguments as? [String: Any], let isDark = (args["isDark"] as? NSNumber)?.boolValue {
          // Changing NSView.appearance triggers AppKit layout/redraw that can
          // clear NSButton.image in release builds. Save and restore it.
          let savedImage = self.button.image
          self.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
          if self.button.image == nil, let img = savedImage {
            self.button.image = img
          }
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
    let iconColor = (args["buttonIconColor"] as? NSNumber).map {
      Self.colorFromARGB($0.intValue)
    }
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
      color: iconColor,
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
    color: NSColor?,
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
      .foregroundColor: color ?? NSColor.black,
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
    image.isTemplate = (color == nil)
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

  private static func backgroundGradient(from value: Any?) -> ButtonBackgroundGradient? {
    guard let dict = value as? [String: Any],
          let rawColors = dict["colors"] as? [NSNumber],
          !rawColors.isEmpty else {
      return nil
    }

    let colors = rawColors.map { Self.colorFromARGB($0.intValue) }
    let locations = (dict["stops"] as? [NSNumber])?.map {
      CGFloat($0.doubleValue)
    }

    return ButtonBackgroundGradient(
      colors: colors,
      locations: locations,
      startPoint: unitPoint(
        from: dict["begin"] as? [String: Any],
        fallbackRawX: -1,
        fallbackRawY: -1
      ),
      endPoint: unitPoint(
        from: dict["end"] as? [String: Any],
        fallbackRawX: 1,
        fallbackRawY: 1
      )
    )
  }

  private static func unitPoint(
    from dict: [String: Any]?,
    fallbackRawX: Double,
    fallbackRawY: Double
  ) -> CGPoint {
    let rawX = (dict?["x"] as? NSNumber)?.doubleValue ?? fallbackRawX
    let rawY = (dict?["y"] as? NSNumber)?.doubleValue ?? fallbackRawY
    let x = min(max((rawX + 1.0) / 2.0, 0.0), 1.0)
    let y = min(max((rawY + 1.0) / 2.0, 0.0), 1.0)
    return CGPoint(x: CGFloat(x), y: CGFloat(y))
  }

  private func installGlassBackgroundIfNeeded() {
    guard #available(macOS 26.0, *) else { return }
    guard glassHostingView == nil else { return }

    let host = NSHostingView(rootView: AnyView(EmptyView()))
    host.translatesAutoresizingMaskIntoConstraints = false
    host.wantsLayer = true
    glassHostingView = host
    addSubview(host, positioned: .below, relativeTo: button)
    glassLeadingConstraint = host.leadingAnchor.constraint(equalTo: leadingAnchor)
    glassTrailingConstraint = host.trailingAnchor.constraint(equalTo: trailingAnchor)
    glassTopConstraint = host.topAnchor.constraint(equalTo: topAnchor)
    glassBottomConstraint = host.bottomAnchor.constraint(equalTo: bottomAnchor)
    NSLayoutConstraint.activate([
      glassLeadingConstraint!,
      glassTrailingConstraint!,
      glassTopConstraint!,
      glassBottomConstraint!
    ])
  }

  private func updateGradientInsets() {
    let inset = (isRoundButton && currentBackgroundGradient != nil) ? gradientBackgroundInset : 0
    gradientLeadingConstraint?.constant = inset
    gradientTrailingConstraint?.constant = -inset
    gradientTopConstraint?.constant = inset
    gradientBottomConstraint?.constant = -inset
    glassLeadingConstraint?.constant = inset
    glassTrailingConstraint?.constant = -inset
    glassTopConstraint?.constant = inset
    glassBottomConstraint?.constant = -inset
  }

  private func addFadeTransition(to layer: CALayer?) {
    let transition = CATransition()
    transition.type = .fade
    transition.duration = implicitAnimationDuration
    transition.timingFunction = CAMediaTimingFunction(
      controlPoints: 0.55,
      0.055,
      0.675,
      0.19
    )
    layer?.add(transition, forKey: "cnButtonImplicitFade")
  }

  private func performAnimatedUpdates(_ updates: @escaping () -> Void) {
    guard window != nil else {
      updates()
      layoutSubtreeIfNeeded()
      return
    }

    layoutSubtreeIfNeeded()
    addFadeTransition(to: button.layer)
    addFadeTransition(to: gradientBackgroundView.layer)
    addFadeTransition(to: glassHostingView?.layer)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = implicitAnimationDuration
      context.timingFunction = CAMediaTimingFunction(
        controlPoints: 0.55,
        0.055,
        0.675,
        0.19
      )
      updates()
      self.layoutSubtreeIfNeeded()
    }
  }

  private func updateGradientBackground() {
    updateGradientInsets()
    let alpha: CGFloat = isEnabled ? 1.0 : 0.55
    let usesGlassChrome = currentBackgroundGradient != nil &&
      ["glass", "prominentGlass"].contains(currentButtonStyle)

    if usesGlassChrome, #available(macOS 26.0, *), let gradient = currentBackgroundGradient {
      installGlassBackgroundIfNeeded()
      glassHostingView?.rootView = AnyView(
        GlassGradientChrome(
          gradient: gradient,
          isRound: isRoundButton,
          isEnabled: isEnabled
        )
      )
      if window != nil {
        glassHostingView?.animator().alphaValue = alpha
      } else {
        glassHostingView?.alphaValue = alpha
      }
      glassHostingView?.isHidden = false
      gradientBackgroundView.gradient = nil
      return
    }

    glassHostingView?.isHidden = true
    gradientBackgroundView.isRound = isRoundButton
    gradientBackgroundView.gradient = currentBackgroundGradient
    if window != nil {
      gradientBackgroundView.animator().alphaValue = alpha
    } else {
      gradientBackgroundView.alphaValue = alpha
    }
  }

  private func applyButtonStyle() {
    updateGradientBackground()
    let hasGradientBackground = currentBackgroundGradient != nil

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

      if hasGradientBackground {
        button.bezelColor = .clear
      } else if let background = currentBackgroundColor {
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
