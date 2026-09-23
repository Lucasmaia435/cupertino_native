import CoreText
import UIKit

/// Renders a Flutter `IconData` glyph (codepoint + font family/package, with
/// optional variable-font axes) as a `UIImage`, so a native platform view can
/// show an arbitrary Flutter/Material icon the same way it shows an SF
/// Symbol. Extracted from `CupertinoTabBarPlatformView` — the tab bar, the
/// glass capsule and the toolbar all need the same glyph-to-image pipeline
/// for their respective `flutterIcon` support, and keeping one copy of the
/// font-manifest/registration logic avoids the three drifting apart.
enum CNFlutterIconImageRenderer {
  private struct FlutterFontManifestEntry {
    let family: String
    let assets: [String]
  }

  private static var cachedFlutterAssetsURL: URL?
  private static var cachedFontManifest: [FlutterFontManifestEntry]?

  static func image(
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

    let candidates = manifestFontNameCandidates(family: family, package: package)
    let candidateSet = Set(candidates)
    let normalizedCandidates = Set(candidates.map { normalizedFontToken($0) })

    var assets: [String] = []
    for entry in manifest {
      if candidateSet.contains(entry.family) ||
          normalizedCandidates.contains(normalizedFontToken(entry.family)) {
        assets.append(contentsOf: entry.assets)
      }
    }
    return Array(Set(assets))
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
}
