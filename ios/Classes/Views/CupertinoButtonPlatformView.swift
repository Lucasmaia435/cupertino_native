import Flutter
import UIKit
import CoreText

private struct ButtonBackgroundGradient {
  let colors: [UIColor]
  let locations: [NSNumber]?
  let startPoint: CGPoint
  let endPoint: CGPoint
}

private final class ButtonGradientBackgroundView: UIView {
  override class var layerClass: AnyClass { CAGradientLayer.self }

  var isRound: Bool = false {
    didSet { setNeedsLayout() }
  }

  var gradient: ButtonBackgroundGradient? {
    didSet { updateGradient() }
  }

  private var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    clipsToBounds = true
    layer.masksToBounds = true
    if #available(iOS 13.0, *) {
      layer.cornerCurve = .continuous
    }
    isHidden = true
  }

  required init?(coder: NSCoder) { return nil }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = min(bounds.width, bounds.height) / 2.0
  }

  private func updateGradient() {
    guard let gradient else {
      gradientLayer.colors = nil
      gradientLayer.locations = nil
      isHidden = true
      return
    }

    gradientLayer.colors = gradient.colors.map(\.cgColor)
    gradientLayer.locations = gradient.locations
    gradientLayer.startPoint = gradient.startPoint
    gradientLayer.endPoint = gradient.endPoint
    isHidden = false
  }
}

class CupertinoButtonPlatformView: NSObject, FlutterPlatformView {
  private struct FlutterFontManifestEntry {
    let family: String
    let assets: [String]
  }

  private static var cachedFlutterAssetsURL: URL?
  private static var cachedFontManifest: [FlutterFontManifestEntry]?

  private let channel: FlutterMethodChannel
  private let container: UIView
  private let gradientBackgroundView: ButtonGradientBackgroundView
  private let button: UIButton
  private let gradientBackgroundInset: CGFloat = 3.0
  private let implicitAnimationDuration: TimeInterval = 0.2
  private let implicitAnimationControlPoint1 = CGPoint(x: 0.55, y: 0.055)
  private let implicitAnimationControlPoint2 = CGPoint(x: 0.675, y: 0.19)
  private var gradientLeadingConstraint: NSLayoutConstraint?
  private var gradientTrailingConstraint: NSLayoutConstraint?
  private var gradientTopConstraint: NSLayoutConstraint?
  private var gradientBottomConstraint: NSLayoutConstraint?
  private var isEnabled: Bool = true
  private var currentButtonStyle: String = "automatic"
  private var currentBackgroundColor: UIColor? = nil
  private var currentBackgroundGradient: ButtonBackgroundGradient? = nil
  private var isRoundButton: Bool = false

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CupertinoNativeButton_\(viewId)", binaryMessenger: messenger)
    self.container = UIView(frame: frame)
    self.gradientBackgroundView = ButtonGradientBackgroundView(frame: frame)
    self.button = UIButton(type: .system)

    var title: String? = nil
    var iconName: String? = nil
    var iconSize: CGFloat? = nil
    var iconColor: UIColor? = nil
    var makeRound: Bool = false
    var isDark: Bool = false
    var tint: UIColor? = nil
    var backgroundColor: UIColor? = nil
    var backgroundGradient: ButtonBackgroundGradient? = nil
    var buttonStyle: String = "automatic"
    var enabled: Bool = true
    var iconMode: String? = nil
    var iconPalette: [NSNumber] = []
    var iconDataCodePoint: Int? = nil
    var iconDataFontFamily: String? = nil
    var iconDataFontPackage: String? = nil
    var iconDataMatchDirection: Bool = false
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
      if let v = dict["isDark"] as? NSNumber { isDark = v.boolValue }
      if let style = dict["style"] as? [String: Any] {
        if let n = style["tint"] as? NSNumber { tint = Self.colorFromARGB(n.intValue) }
        if let n = style["backgroundColor"] as? NSNumber {
          backgroundColor = Self.colorFromARGB(n.intValue)
        }
        backgroundGradient = Self.backgroundGradient(from: style["backgroundGradient"])
      }
      if let bs = dict["buttonStyle"] as? String { buttonStyle = bs }
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
      if let match = dict["buttonIconDataMatchTextDirection"] as? NSNumber {
        iconDataMatchDirection = match.boolValue
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

    super.init()

    container.backgroundColor = .clear
    if #available(iOS 13.0, *) { container.overrideUserInterfaceStyle = isDark ? .dark : .light }

    gradientBackgroundView.translatesAutoresizingMaskIntoConstraints = false
    button.translatesAutoresizingMaskIntoConstraints = false
    if let t = tint { button.tintColor = t }
    else if #available(iOS 13.0, *) { button.tintColor = .label }

    container.addSubview(gradientBackgroundView)
    container.addSubview(button)
    gradientLeadingConstraint = gradientBackgroundView.leadingAnchor.constraint(equalTo: container.leadingAnchor)
    gradientTrailingConstraint = gradientBackgroundView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
    gradientTopConstraint = gradientBackgroundView.topAnchor.constraint(equalTo: container.topAnchor)
    gradientBottomConstraint = gradientBackgroundView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    NSLayoutConstraint.activate([
      gradientLeadingConstraint!,
      gradientTrailingConstraint!,
      gradientTopConstraint!,
      gradientBottomConstraint!,
      button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      button.topAnchor.constraint(equalTo: container.topAnchor),
      button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    currentButtonStyle = buttonStyle
    currentBackgroundColor = backgroundColor
    currentBackgroundGradient = backgroundGradient
    isRoundButton = makeRound
    isEnabled = enabled
    button.isEnabled = enabled
    applyButtonStyle(buttonStyle: buttonStyle, round: makeRound)

    var finalImage: UIImage? = nil
    if let name = iconName, var image = UIImage(systemName: name) {
      if let sz = iconSize { image = image.applyingSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: sz)) ?? image }
      if let mode = iconMode {
        switch mode {
        case "hierarchical":
          if #available(iOS 15.0, *), let col = iconColor {
            let cfg = UIImage.SymbolConfiguration(hierarchicalColor: col)
            image = image.applyingSymbolConfiguration(cfg) ?? image
          }
        case "palette":
          if #available(iOS 15.0, *), !iconPalette.isEmpty {
            let cols = iconPalette.map { Self.colorFromARGB($0.intValue) }
            let cfg = UIImage.SymbolConfiguration(paletteColors: cols)
            image = image.applyingSymbolConfiguration(cfg) ?? image
          }
        case "multicolor":
          if #available(iOS 15.0, *) {
            let cfg = UIImage.SymbolConfiguration.preferringMulticolor()
            image = image.applyingSymbolConfiguration(cfg) ?? image
          }
        case "monochrome":
          if let col = iconColor, #available(iOS 13.0, *) {
            image = image.withTintColor(col, renderingMode: .alwaysOriginal)
          }
        default:
          break
        }
      } else if let col = iconColor, #available(iOS 13.0, *) {
        image = image.withTintColor(col, renderingMode: .alwaysOriginal)
      }
      finalImage = image
    } else if let codePoint = iconDataCodePoint {
      let pointSize = iconSize ?? 20
      if var image = Self.iconImage(
        codePoint: codePoint,
        fontFamily: iconDataFontFamily,
        fontPackage: iconDataFontPackage,
        pointSize: pointSize,
        color: iconColor,
        fill: iconDataFill,
        weight: iconDataWeight,
        grade: iconDataGrade,
        opticalSize: iconDataOpticalSize
      ) {
        if iconDataMatchDirection {
          image = image.imageFlippedForRightToLeftLayoutDirection()
        }
        finalImage = image
      }
    }
    setButtonContent(title: title, image: finalImage, iconOnly: (title == nil))

    // Default system highlight/pressed behavior
    button.addTarget(self, action: #selector(onPressed(_:)), for: .touchUpInside)
    button.adjustsImageWhenHighlighted = true

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "getIntrinsicSize":
        let size = self.button.intrinsicContentSize
        result(["width": Double(size.width), "height": Double(size.height)])
      case "setStyle":
        if let args = call.arguments as? [String: Any] {
          var shouldReapplyStyle = false
          if let n = args["tint"] as? NSNumber {
            self.button.tintColor = Self.colorFromARGB(n.intValue)
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
              self.applyButtonStyle(
                buttonStyle: self.currentButtonStyle,
                round: self.isRoundButton
              )
            }
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing style", details: nil)) }
      case "setEnabled":
        if let args = call.arguments as? [String: Any], let e = args["enabled"] as? NSNumber {
          self.performAnimatedUpdates {
            self.isEnabled = e.boolValue
            self.button.isEnabled = self.isEnabled
            self.updateGradientBackground(round: self.isRoundButton)
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing enabled", details: nil)) }
      case "setPressed":
        if let args = call.arguments as? [String: Any], let p = args["pressed"] as? NSNumber {
          self.button.isHighlighted = p.boolValue
          self.updateGradientBackground(round: self.isRoundButton, isPressed: p.boolValue)
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing pressed", details: nil)) }
      case "setButtonTitle":
        if let args = call.arguments as? [String: Any], let t = args["title"] as? String {
          self.performAnimatedUpdates {
            self.setButtonContent(title: t, image: nil, iconOnly: false)
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing title", details: nil)) }
      case "setButtonIcon":
        if let args = call.arguments as? [String: Any] {
          let image = Self.buttonImage(from: args)
          self.performAnimatedUpdates {
            self.setButtonContent(title: nil, image: image, iconOnly: true)
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing icon args", details: nil)) }
      case "setVisible":
        if let args = call.arguments as? [String: Any], let visible = (args["visible"] as? NSNumber)?.boolValue {
          self.container.isHidden = !visible
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing visible", details: nil)) }
      case "setBrightness":
        if let args = call.arguments as? [String: Any], let isDark = (args["isDark"] as? NSNumber)?.boolValue {
          if #available(iOS 13.0, *) { self.container.overrideUserInterfaceStyle = isDark ? .dark : .light }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil)) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { container }

  @objc private func onPressed(_ sender: UIButton) {
    guard isEnabled else { return }
    channel.invokeMethod("pressed", arguments: nil)
  }

  private static func buttonImage(from args: [String: Any]) -> UIImage? {
    let pointSize = (args["buttonIconSize"] as? NSNumber).map { CGFloat(truncating: $0) }

    if let name = args["buttonIconName"] as? String, var image = UIImage(systemName: name) {
      if let size = pointSize {
        image = image.applyingSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: size)) ?? image
      }
      if let mode = args["buttonIconRenderingMode"] as? String {
        switch mode {
        case "hierarchical":
          if #available(iOS 15.0, *), let c = args["buttonIconColor"] as? NSNumber {
            let cfg = UIImage.SymbolConfiguration(hierarchicalColor: Self.colorFromARGB(c.intValue))
            image = image.applyingSymbolConfiguration(cfg) ?? image
          }
        case "palette":
          if #available(iOS 15.0, *), let pal = args["buttonIconPaletteColors"] as? [NSNumber] {
            let cols = pal.map { Self.colorFromARGB($0.intValue) }
            let cfg = UIImage.SymbolConfiguration(paletteColors: cols)
            image = image.applyingSymbolConfiguration(cfg) ?? image
          }
        case "multicolor":
          if #available(iOS 15.0, *) {
            let cfg = UIImage.SymbolConfiguration.preferringMulticolor()
            image = image.applyingSymbolConfiguration(cfg) ?? image
          }
        case "monochrome":
          if let c = args["buttonIconColor"] as? NSNumber, #available(iOS 13.0, *) {
            image = image.withTintColor(Self.colorFromARGB(c.intValue), renderingMode: .alwaysOriginal)
          }
        default:
          break
        }
      } else if let c = args["buttonIconColor"] as? NSNumber, #available(iOS 13.0, *) {
        image = image.withTintColor(Self.colorFromARGB(c.intValue), renderingMode: .alwaysOriginal)
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
    let size = pointSize ?? 20
    guard var image = iconImage(
      codePoint: codePoint,
      fontFamily: fontFamily,
      fontPackage: fontPackage,
      pointSize: size,
      color: iconColor,
      fill: fill,
      weight: weight,
      grade: grade,
      opticalSize: opticalSize
    ) else {
      return nil
    }
    if let match = (args["buttonIconDataMatchTextDirection"] as? NSNumber)?.boolValue, match {
      image = image.imageFlippedForRightToLeftLayoutDirection()
    }
    return image
  }

  private static func iconImage(
    codePoint: Int,
    fontFamily: String?,
    fontPackage: String?,
    pointSize: CGFloat,
    color: UIColor?,
    fill: CGFloat?,
    weight: CGFloat?,
    grade: CGFloat?,
    opticalSize: CGFloat?
  ) -> UIImage? {
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
    ) ?? UIFont.systemFont(ofSize: pointSize)
    let canvasSize = CGSize(width: pointSize * 1.8, height: pointSize * 1.8)
    let renderer = UIGraphicsImageRenderer(size: canvasSize)
    let image = renderer.image { _ in
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      let attrs: [NSAttributedString.Key: Any] = [
        .font: resolvedFont,
        .foregroundColor: color ?? UIColor.white,
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
    return image.withRenderingMode(color == nil ? .alwaysTemplate : .alwaysOriginal)
  }

  private static func loadIconFont(
    family: String?,
    package: String?,
    pointSize: CGFloat,
    fill: CGFloat?,
    weight: CGFloat?,
    grade: CGFloat?,
    opticalSize: CGFloat?
  ) -> UIFont? {
    guard let family else { return nil }
    ensureFlutterFontRegistered(family: family, package: package)

    let directCandidates = directFontNameCandidates(
      family: family,
      package: package
    )
    for candidate in directCandidates {
      if let font = UIFont(name: candidate, size: pointSize) {
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
    for familyName in UIFont.familyNames {
      let familyToken = normalizedFontToken(familyName)
      if familyToken == wanted || familyToken.contains(wanted) || wanted.contains(familyToken) {
        if let font = UIFont(name: familyName, size: pointSize) {
          return applyFontVariations(
            to: font,
            fill: fill,
            weight: weight,
            grade: grade,
            opticalSize: opticalSize
          )
        }
      }
      for fontName in UIFont.fontNames(forFamilyName: familyName) {
        let fontToken = normalizedFontToken(fontName)
        if fontToken == wanted || fontToken.contains(wanted) || wanted.contains(fontToken) {
          if let font = UIFont(name: fontName, size: pointSize) {
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
    return nil
  }

  private static func applyFontVariations(
    to font: UIFont,
    fill: CGFloat?,
    weight: CGFloat?,
    grade: CGFloat?,
    opticalSize: CGFloat?
  ) -> UIFont {
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
    let variationAttr = UIFontDescriptor.AttributeName(
      rawValue: kCTFontVariationAttribute as String
    )
    let descriptor = font.fontDescriptor.addingAttributes([
      variationAttr: variations
    ])
    return UIFont(descriptor: descriptor, size: font.pointSize)
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

  private static func materializedBackgroundColor(_ color: UIColor) -> UIColor {
    color.withAlphaComponent(min(color.cgColor.alpha * 0.45, 0.32))
  }

  private static func backgroundGradient(from value: Any?) -> ButtonBackgroundGradient? {
    guard let dict = value as? [String: Any],
          let rawColors = dict["colors"] as? [NSNumber],
          !rawColors.isEmpty else {
      return nil
    }

    let colors = rawColors.map { Self.colorFromARGB($0.intValue) }
    let locations = (dict["stops"] as? [NSNumber])?.map {
      NSNumber(value: $0.doubleValue)
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

  private func updateGradientBackground(round: Bool, isPressed: Bool = false) {
    let inset = (round && currentBackgroundGradient != nil) ? gradientBackgroundInset : 0
    gradientLeadingConstraint?.constant = inset
    gradientTrailingConstraint?.constant = -inset
    gradientTopConstraint?.constant = inset
    gradientBottomConstraint?.constant = -inset
    gradientBackgroundView.isRound = round
    gradientBackgroundView.gradient = currentBackgroundGradient
    guard currentBackgroundGradient != nil else { return }

    if !isEnabled {
      gradientBackgroundView.alpha = 0.55
    } else {
      gradientBackgroundView.alpha = isPressed ? 0.88 : 1.0
    }
  }

  private func addFadeTransition(to layer: CALayer?) {
    let transition = CATransition()
    transition.type = .fade
    transition.duration = implicitAnimationDuration
    transition.timingFunction = CAMediaTimingFunction(
      controlPoints: Float(implicitAnimationControlPoint1.x),
      Float(implicitAnimationControlPoint1.y),
      Float(implicitAnimationControlPoint2.x),
      Float(implicitAnimationControlPoint2.y)
    )
    layer?.add(transition, forKey: "cnButtonImplicitFade")
  }

  private func performAnimatedUpdates(_ updates: @escaping () -> Void) {
    guard container.window != nil else {
      updates()
      container.layoutIfNeeded()
      return
    }

    container.layoutIfNeeded()
    addFadeTransition(to: button.layer)
    addFadeTransition(to: gradientBackgroundView.layer)
    let timing = UICubicTimingParameters(
      controlPoint1: implicitAnimationControlPoint1,
      controlPoint2: implicitAnimationControlPoint2
    )
    let animator = UIViewPropertyAnimator(
      duration: implicitAnimationDuration,
      timingParameters: timing
    )
    animator.addAnimations {
      updates()
      self.container.layoutIfNeeded()
    }
    animator.startAnimation()
  }

  private func applyButtonStyle(buttonStyle: String, round: Bool) {
    updateGradientBackground(round: round, isPressed: button.isHighlighted)

    if #available(iOS 15.0, *) {
      // Preserve current content while swapping configurations
      let currentTitle = button.configuration?.title
      let currentImage = button.configuration?.image
      let currentSymbolCfg = button.configuration?.preferredSymbolConfigurationForImage
      let hasCustomBackground = currentBackgroundColor != nil
      let hasGradientBackground = currentBackgroundGradient != nil
      var config: UIButton.Configuration
      switch buttonStyle {
      case "plain": config = .plain()
      case "gray": config = .gray()
      case "tinted": config = .tinted()
      case "bordered": config = .bordered()
      case "borderedProminent": config = .borderedProminent()
      case "filled": config = .filled()
      case "glass":
        if #available(iOS 26.0, *) {
          config = .glass()
        } else {
          config = .tinted()
        }
      case "prominentGlass":
        if #available(iOS 26.0, *) {
          config = .prominentGlass()
        } else {
          config = .tinted()
        }
      default:
        config = .plain()
      }
      config.cornerStyle = (round || hasGradientBackground) ? .capsule : .dynamic
      // Apply theme tint to configuration in a platform-standard way
      if let tint = button.tintColor {
        if hasGradientBackground {
          config.baseForegroundColor = tint
        } else {
          switch buttonStyle {
          case "filled", "borderedProminent", "prominentGlass":
            if hasCustomBackground {
              config.baseForegroundColor = tint
            } else {
              // Treat prominentGlass like filled: color the background and let system pick readable foreground
              config.baseBackgroundColor = tint
            }
          case "tinted", "bordered", "gray", "plain", "glass":
            // Foreground-only tint
            config.baseForegroundColor = tint
          default:
            break
          }
        }
      }
      if hasGradientBackground {
        if buttonStyle != "glass" && buttonStyle != "prominentGlass" {
          config.baseBackgroundColor = nil
          config.background.backgroundColor = .clear
          config.background.visualEffect = nil
        }
      } else if let backgroundColor = currentBackgroundColor {
        let materialBackground = Self.materializedBackgroundColor(backgroundColor)
        config.background.backgroundColor = materialBackground
        if buttonStyle == "glass" || buttonStyle == "prominentGlass" {
          config.baseBackgroundColor = materialBackground
        } else {
          // Avoid baseBackgroundColor here because it turns the material back into a solid fill.
          config.baseBackgroundColor = nil
          // Match the softer native bar/chrome treatment instead of a fully solid fill.
          config.background.visualEffect = UIBlurEffect(style: .systemChromeMaterial)
        }
      }
      // Restore content after style swap
      config.title = currentTitle
      config.image = currentImage
      config.preferredSymbolConfigurationForImage = currentSymbolCfg
      button.configuration = config
    } else {
      button.layer.cornerRadius = round ? 999 : 8
      button.clipsToBounds = true
      if currentBackgroundGradient != nil {
        button.backgroundColor = .clear
      } else if let backgroundColor = currentBackgroundColor {
        button.backgroundColor = Self.materializedBackgroundColor(backgroundColor)
      } else {
        button.backgroundColor = .clear
      }
      button.layer.borderWidth = 0
    }
  }

  private func setButtonContent(title: String?, image: UIImage?, iconOnly: Bool) {
    if #available(iOS 15.0, *) {
      var cfg = button.configuration ?? .plain()
      cfg.title = title
      cfg.image = image
      button.configuration = cfg
    } else {
      button.setTitle(title, for: .normal)
      button.setImage(image, for: .normal)
      if iconOnly {
        button.contentEdgeInsets = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
      }
    }
  }
}
