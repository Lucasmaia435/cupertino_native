import Flutter
import UIKit
import CoreText

private final class LayoutAwareSearchBar: UISearchBar {
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

class CupertinoSearchBarPlatformView: NSObject, FlutterPlatformView, UISearchBarDelegate {
  private struct FlutterFontManifestEntry {
    let family: String
    let assets: [String]
  }

  private struct TrailingAction {
    let iconDataCodePoint: Int
    let iconDataFontFamily: String?
    let iconDataFontPackage: String?
    let iconDataMatchTextDirection: Bool
    let iconDataColor: UIColor?
    let iconDataSize: CGFloat
    let iconDataFill: CGFloat?
    let iconDataWeight: CGFloat?
    let iconDataGrade: CGFloat?
    let iconDataOpticalSize: CGFloat?
  }

  private static var cachedFlutterAssetsURL: URL?
  private static var cachedFontManifest: [FlutterFontManifestEntry]?

  private let channel: FlutterMethodChannel
  private let container: UIView
  private let searchBar: LayoutAwareSearchBar
  private let trailingButtons: [UIButton]
  private var trailingButtonsEnabled: [Bool] = [false, false]
  private var currentTrailingActions: [TrailingAction] = []
  private var isInstallingTrailingButtons = false

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    let firstTrailingButton = UIButton(type: .system)
    let secondTrailingButton = UIButton(type: .system)
    self.channel = FlutterMethodChannel(name: "CupertinoNativeSearchBar_\(viewId)", binaryMessenger: messenger)
    self.container = UIView(frame: frame)
    self.searchBar = LayoutAwareSearchBar(frame: .zero)
    self.trailingButtons = [firstTrailingButton, secondTrailingButton]

    var text: String = ""
    var placeholder: String? = nil
    var enabled: Bool = true
    var showsCancelButton: Bool = false
    var isDark: Bool = false
    var tint: UIColor? = nil
    var bg: UIColor? = nil
    var fieldBg: UIColor? = nil
    var trailingActions: [TrailingAction] = []

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
      trailingActions = Self.parseTrailingActions(dict["traillingActions"])
    }

    super.init()

    container.backgroundColor = .clear
    if #available(iOS 13.0, *) {
      container.overrideUserInterfaceStyle = isDark ? .dark : .light
    }

    searchBar.translatesAutoresizingMaskIntoConstraints = false
    searchBar.onLayout = { [weak self] in
      guard let self else { return }
      self.installTrailingButtonsInTextField()
    }
    searchBar.delegate = self
    searchBar.searchBarStyle = .minimal
    searchBar.text = text
    searchBar.placeholder = placeholder
    searchBar.showsCancelButton = showsCancelButton
    for (index, button) in trailingButtons.enumerated() {
      button.tag = index
      button.tintColor = tint ?? searchBar.tintColor
      button.adjustsImageWhenHighlighted = true
      button.imageView?.contentMode = .scaleAspectFit
      button.isHidden = true
      button.addTarget(self, action: #selector(onTrailingPressed(_:)), for: .touchUpInside)
    }
    applyEnabled(enabled)
    if let color = tint { searchBar.tintColor = color }
    if let color = bg { searchBar.backgroundColor = color }
    if let color = fieldBg { searchBar.searchTextField.backgroundColor = color }
    applyTrailingActions(trailingActions)

    container.addSubview(searchBar)
    NSLayoutConstraint.activate([
      searchBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      searchBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      searchBar.topAnchor.constraint(equalTo: container.topAnchor),
      searchBar.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.applyTrailingActions(self.currentTrailingActions)
    }

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
      case "setTrailingActions":
        if let params = call.arguments as? [String: Any] {
          self.applyTrailingActions(Self.parseTrailingActions(params["traillingActions"]))
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing trailing actions args", details: nil)) }
      case "setStyle":
        if let params = call.arguments as? [String: Any] {
          if let value = params["tint"] as? NSNumber {
            self.searchBar.tintColor = Self.colorFromARGB(value.intValue)
            self.applyTrailingActions(self.currentTrailingActions)
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

  @objc private func onTrailingPressed(_ sender: UIButton) {
    let index = sender.tag
    guard index >= 0,
          index < trailingButtonsEnabled.count,
          trailingButtonsEnabled[index],
          searchBar.searchTextField.isEnabled else {
      return
    }
    channel.invokeMethod("trailingActionPressed", arguments: ["index": index])
  }

  private static func parseTrailingActions(_ raw: Any?) -> [TrailingAction] {
    guard let items = raw as? [Any] else { return [] }
    var actions: [TrailingAction] = []
    for item in items.prefix(2) {
      guard let dict = item as? [String: Any],
            let codePoint = (dict["iconDataCodePoint"] as? NSNumber)?.intValue else {
        continue
      }
      let fontFamily = dict["iconDataFontFamily"] as? String
      let fontPackage = dict["iconDataFontPackage"] as? String
      let matchTextDirection =
        (dict["iconDataMatchTextDirection"] as? NSNumber)?.boolValue ?? false
      let iconColor = Self.parseOptionalColor(dict["iconDataColor"])
      let size = Self.parseOptionalCGFloat(dict["iconDataSize"]) ?? 16
      actions.append(
        TrailingAction(
          iconDataCodePoint: codePoint,
          iconDataFontFamily: fontFamily,
          iconDataFontPackage: fontPackage,
          iconDataMatchTextDirection: matchTextDirection,
          iconDataColor: iconColor,
          iconDataSize: size,
          iconDataFill: Self.parseOptionalCGFloat(dict["iconDataFill"]),
          iconDataWeight: Self.parseOptionalCGFloat(dict["iconDataWeight"]),
          iconDataGrade: Self.parseOptionalCGFloat(dict["iconDataGrade"]),
          iconDataOpticalSize: Self.parseOptionalCGFloat(dict["iconDataOpticalSize"])
        )
      )
    }
    return actions
  }

  private func applyEnabled(_ enabled: Bool) {
    searchBar.isUserInteractionEnabled = enabled
    searchBar.searchTextField.isEnabled = enabled
    searchBar.alpha = enabled ? 1.0 : 0.6
    for (index, button) in trailingButtons.enumerated() {
      button.isEnabled = enabled && trailingButtonsEnabled[index]
      button.alpha = button.isEnabled ? 1.0 : 0.6
    }
  }

  private func applyTrailingActions(_ actions: [TrailingAction]) {
    currentTrailingActions = Array(actions.prefix(2))
    for index in 0..<trailingButtons.count {
      guard index < currentTrailingActions.count,
            var image = Self.iconImage(
              codePoint: currentTrailingActions[index].iconDataCodePoint,
              fontFamily: currentTrailingActions[index].iconDataFontFamily,
              fontPackage: currentTrailingActions[index].iconDataFontPackage,
              pointSize: actionIconPointSize(currentTrailingActions[index]),
              fill: currentTrailingActions[index].iconDataFill,
              weight: currentTrailingActions[index].iconDataWeight,
              grade: currentTrailingActions[index].iconDataGrade,
              opticalSize: currentTrailingActions[index].iconDataOpticalSize
            ) else {
        trailingButtons[index].setImage(nil, for: .normal)
        trailingButtons[index].isHidden = true
        trailingButtonsEnabled[index] = false
        continue
      }

      if currentTrailingActions[index].iconDataMatchTextDirection {
        image = image.imageFlippedForRightToLeftLayoutDirection()
      }
      trailingButtons[index].setImage(image, for: .normal)
      trailingButtons[index].isHidden = false
      trailingButtonsEnabled[index] = true
      trailingButtons[index].tintColor =
        currentTrailingActions[index].iconDataColor ?? searchBar.tintColor
    }
    installTrailingButtonsInTextField()
    applyEnabled(searchBar.searchTextField.isEnabled)
  }

  private func installTrailingButtonsInTextField() {
    if isInstallingTrailingButtons { return }
    isInstallingTrailingButtons = true
    defer { isInstallingTrailingButtons = false }

    let visibleEntries = trailingButtons.enumerated().compactMap { index, button
      -> (button: UIButton, side: CGFloat)? in
      guard !button.isHidden, index < currentTrailingActions.count else {
        return nil
      }
      return (button, actionButtonSide(currentTrailingActions[index]))
    }
    guard !visibleEntries.isEmpty else {
      searchBar.searchTextField.rightView = nil
      searchBar.searchTextField.rightViewMode = .never
      return
    }

    let spacing: CGFloat = 0
    let totalWidth = visibleEntries
      .map { $0.side }
      .reduce(CGFloat(0), +)
    let width = totalWidth + (spacing * CGFloat(max(0, visibleEntries.count - 1)))
    let containerHeight = visibleEntries
      .map { $0.side }
      .reduce(CGFloat(0), max)
    let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: containerHeight))
    var x: CGFloat = 0
    for entry in visibleEntries {
      let button = entry.button
      let side = entry.side
      button.removeFromSuperview()
      button.frame = CGRect(
        x: x,
        y: (containerHeight - side) / 2.0,
        width: side,
        height: side
      )
      container.addSubview(button)
      x += side + spacing
    }
    searchBar.searchTextField.rightView = container
    searchBar.searchTextField.rightViewMode = .always
  }

  private func actionButtonSide(_ action: TrailingAction) -> CGFloat {
    let requestedSide = clampedActionIconSize(action) + 2
    return max(18, min(requestedSide, 130))
  }

  private func actionIconPointSize(_ action: TrailingAction) -> CGFloat {
    return clampedActionIconSize(action)
  }

  private func clampedActionIconSize(_ action: TrailingAction) -> CGFloat {
    return min(128, max(12, action.iconDataSize))
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
    let assets = fontAssetsForFamily(family: family, package: package)
    guard !assets.isEmpty else { return }
    registerFontAssets(assets)
  }

  private static func fontAssetsForFamily(family: String, package: String?) -> [String] {
    let manifest = loadFontManifest()
    guard !manifest.isEmpty else { return [] }

    let exactCandidates = manifestFontNameCandidates(
      family: family,
      package: package
    )
    var exactAssets: [String] = []
    for entry in manifest {
      if exactCandidates.contains(entry.family) {
        exactAssets.append(contentsOf: entry.assets)
      }
    }
    if !exactAssets.isEmpty {
      return Array(Set(exactAssets))
    }

    let normalizedCandidates = Set(
      manifestFontNameCandidates(family: family, package: package)
        .map { normalizedFontToken($0) }
    )

    var scopedFallbackAssets: [String] = []
    for entry in manifest {
      // If package is provided, avoid app-level fonts with same family.
      if let package {
        let packagePrefix = "packages/\(package)/"
        if !entry.family.hasPrefix(packagePrefix) { continue }
      } else if entry.family.hasPrefix("packages/") {
        // If package is not provided, prefer app-level font families.
        continue
      }

      if normalizedCandidates.contains(normalizedFontToken(entry.family)) {
        scopedFallbackAssets.append(contentsOf: entry.assets)
      }
    }
    if !scopedFallbackAssets.isEmpty {
      return Array(Set(scopedFallbackAssets))
    }

    // Last resort for compatibility: any normalized match.
    var fallbackAssets: [String] = []
    for entry in manifest {
      if normalizedCandidates.contains(normalizedFontToken(entry.family)) {
        fallbackAssets.append(contentsOf: entry.assets)
      }
    }
    return Array(Set(fallbackAssets))
  }

  private static func manifestFontNameCandidates(
    family: String,
    package: String?
  ) -> [String] {
    var candidates: [String] = [family]
    if let package {
      candidates.append("packages/\(package)/\(family)")
    }

    if family.hasPrefix("packages/"),
       let lastComponent = family.split(separator: "/").last,
       !lastComponent.isEmpty {
      candidates.append(String(lastComponent))
    }

    let withSpaces = family.replacingOccurrences(of: "_", with: " ")
    let withoutSpaces = family.replacingOccurrences(of: " ", with: "")
    let withoutUnderscores = family.replacingOccurrences(of: "_", with: "")
    candidates.append(withSpaces)
    candidates.append(withoutSpaces)
    candidates.append(withoutUnderscores)

    if let package {
      candidates.append("packages/\(package)/\(withSpaces)")
      candidates.append("packages/\(package)/\(withoutSpaces)")
      candidates.append("packages/\(package)/\(withoutUnderscores)")
    }
    return Array(Set(candidates))
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

  private static func parseOptionalCGFloat(_ value: Any?) -> CGFloat? {
    if value is NSNull { return nil }
    if let number = value as? NSNumber { return CGFloat(truncating: number) }
    return nil
  }

  private static func parseOptionalColor(_ value: Any?) -> UIColor? {
    if value is NSNull { return nil }
    if let number = value as? NSNumber { return colorFromARGB(number.intValue) }
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
