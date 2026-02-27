import FlutterMacOS
import Cocoa
import CoreText

class CupertinoTabBarNSView: NSView {
  private struct FlutterFontManifestEntry {
    let family: String
    let assets: [String]
  }

  private static var cachedFlutterAssetsURL: URL?
  private static var cachedFontManifest: [FlutterFontManifestEntry]?

  private let channel: FlutterMethodChannel
  private let control: NSSegmentedControl

  private var currentLabels: [String] = []
  private var currentSymbols: [String] = []
  private var currentIconCodePoints: [Int?] = []
  private var currentIconFontFamilies: [String?] = []
  private var currentIconFontPackages: [String?] = []
  private var currentIconMatchDirections: [Bool] = []
  private var currentSizes: [NSNumber] = []
  private var currentSelectedIndex: Int = 0
  private var currentTint: NSColor? = nil
  private var currentBackground: NSColor? = nil

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(
      name: "CupertinoNativeTabBar_\(viewId)",
      binaryMessenger: messenger
    )
    self.control = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: nil, action: nil)

    var isDark: Bool = false

    if let dict = args as? [String: Any] {
      currentLabels = (dict["labels"] as? [String]) ?? []
      currentSymbols = (dict["sfSymbols"] as? [String]) ?? []
      currentIconCodePoints = Self.parseOptionalIntArray(dict["iconDataCodePoints"])
      currentIconFontFamilies = Self.parseOptionalStringArray(dict["iconDataFontFamilies"])
      currentIconFontPackages = Self.parseOptionalStringArray(dict["iconDataFontPackages"])
      currentIconMatchDirections = Self.parseBoolArray(dict["iconDataMatchTextDirections"])
      currentSizes = (dict["sfSymbolSizes"] as? [NSNumber]) ?? []
      if let value = dict["selectedIndex"] as? NSNumber { currentSelectedIndex = value.intValue }
      if let value = dict["isDark"] as? NSNumber { isDark = value.boolValue }
      if let style = dict["style"] as? [String: Any] {
        if let value = style["tint"] as? NSNumber { currentTint = Self.colorFromARGB(value.intValue) }
        if let value = style["backgroundColor"] as? NSNumber { currentBackground = Self.colorFromARGB(value.intValue) }
      }
    }

    super.init(frame: .zero)

    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    if let background = currentBackground {
      layer?.backgroundColor = background.cgColor
    }

    configureSegments()
    control.target = self
    control.action = #selector(onChanged(_:))

    addSubview(control)
    control.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      control.leadingAnchor.constraint(equalTo: leadingAnchor),
      control.trailingAnchor.constraint(equalTo: trailingAnchor),
      control.topAnchor.constraint(equalTo: topAnchor),
      control.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "getIntrinsicSize":
        let size = self.control.intrinsicContentSize
        result(["width": Double(size.width), "height": Double(size.height)])
      case "setSelectedIndex":
        if let params = call.arguments as? [String: Any],
           let index = (params["index"] as? NSNumber)?.intValue {
          let count = self.control.segmentCount
          if count > 0 {
            self.currentSelectedIndex = max(0, min(index, count - 1))
            self.control.selectedSegment = self.currentSelectedIndex
          } else {
            self.currentSelectedIndex = -1
            self.control.selectedSegment = -1
          }
          self.applySegmentTint()
          result(nil)
        } else {
          result(FlutterError(code: "bad_args", message: "Missing index", details: nil))
        }
      case "setItems":
        if let params = call.arguments as? [String: Any] {
          self.currentLabels = (params["labels"] as? [String]) ?? []
          self.currentSymbols = (params["sfSymbols"] as? [String]) ?? []
          self.currentIconCodePoints = Self.parseOptionalIntArray(params["iconDataCodePoints"])
          self.currentIconFontFamilies = Self.parseOptionalStringArray(params["iconDataFontFamilies"])
          self.currentIconFontPackages = Self.parseOptionalStringArray(params["iconDataFontPackages"])
          self.currentIconMatchDirections = Self.parseBoolArray(params["iconDataMatchTextDirections"])
          self.currentSelectedIndex = (params["selectedIndex"] as? NSNumber)?.intValue ?? self.currentSelectedIndex
          self.configureSegments()
          result(nil)
        } else {
          result(FlutterError(code: "bad_args", message: "Missing items", details: nil))
        }
      case "setLayout":
        // macOS uses a single segmented control layout.
        result(nil)
      case "setStyle":
        if let params = call.arguments as? [String: Any] {
          if let value = params["tint"] as? NSNumber { self.currentTint = Self.colorFromARGB(value.intValue) }
          if let value = params["backgroundColor"] as? NSNumber {
            let color = Self.colorFromARGB(value.intValue)
            self.currentBackground = color
            self.wantsLayer = true
            self.layer?.backgroundColor = color.cgColor
          }
          self.applySegmentTint()
          result(nil)
        } else {
          result(FlutterError(code: "bad_args", message: "Missing style", details: nil))
        }
      case "setBrightness":
        if let params = call.arguments as? [String: Any],
           let isDark = (params["isDark"] as? NSNumber)?.boolValue {
          self.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
          result(nil)
        } else {
          result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  required init?(coder: NSCoder) {
    return nil
  }

  private func configureSegments() {
    let count = totalItemCount()
    control.segmentCount = count
    if count > 0 {
      control.selectedSegment = max(0, min(currentSelectedIndex, count - 1))
    } else {
      control.selectedSegment = -1
    }
    for index in 0..<count {
      if let image = baseImageForSegment(index) {
        control.setImage(image, forSegment: index)
        control.setLabel("", forSegment: index)
      } else if index < currentLabels.count {
        control.setImage(nil, forSegment: index)
        control.setLabel(currentLabels[index], forSegment: index)
      } else {
        control.setImage(nil, forSegment: index)
        control.setLabel("", forSegment: index)
      }
    }
    applySegmentTint()
  }

  private func applySegmentTint() {
    let count = control.segmentCount
    guard count > 0 else { return }
    let selected = control.selectedSegment
    for index in 0..<count {
      guard var image = baseImageForSegment(index) else { continue }
      if index == selected, let tint = currentTint {
        image = image.tinted(with: tint)
      }
      control.setImage(image, forSegment: index)
    }
  }

  private func baseImageForSegment(_ index: Int) -> NSImage? {
    if index < currentSymbols.count {
      let symbolName = currentSymbols[index]
      if !symbolName.isEmpty,
         #available(macOS 11.0, *),
         var image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
        if index < currentSizes.count, #available(macOS 12.0, *) {
          let size = CGFloat(truncating: currentSizes[index])
          let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
          image = image.withSymbolConfiguration(config) ?? image
        }
        return image
      }
    }

    guard index < currentIconCodePoints.count, let codePoint = currentIconCodePoints[index] else {
      return nil
    }
    let family = index < currentIconFontFamilies.count ? currentIconFontFamilies[index] : nil
    let package = index < currentIconFontPackages.count ? currentIconFontPackages[index] : nil
    let size = index < currentSizes.count ? CGFloat(truncating: currentSizes[index]) : 18
    return Self.iconImage(
      codePoint: codePoint,
      fontFamily: family,
      fontPackage: package,
      pointSize: size
    )
  }

  private func totalItemCount() -> Int {
    return max(max(currentLabels.count, currentSymbols.count), currentIconCodePoints.count)
  }

  @objc private func onChanged(_ sender: NSSegmentedControl) {
    currentSelectedIndex = sender.selectedSegment
    channel.invokeMethod("valueChanged", arguments: ["index": sender.selectedSegment])
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

  private static func parseOptionalIntArray(_ value: Any?) -> [Int?] {
    guard let raw = value as? [Any] else { return [] }
    return raw.map { element in
      if element is NSNull { return nil }
      if let number = element as? NSNumber { return number.intValue }
      return nil
    }
  }

  private static func parseOptionalStringArray(_ value: Any?) -> [String?] {
    guard let raw = value as? [Any] else { return [] }
    return raw.map { element in
      if element is NSNull { return nil }
      if let text = element as? String { return text }
      return nil
    }
  }

  private static func parseBoolArray(_ value: Any?) -> [Bool] {
    guard let raw = value as? [Any] else { return [] }
    return raw.map { element in
      if let number = element as? NSNumber { return number.boolValue }
      return false
    }
  }

  private static func colorFromARGB(_ argb: Int) -> NSColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
  }
}

private extension NSImage {
  func tinted(with color: NSColor) -> NSImage {
    let img = NSImage(size: size)
    img.lockFocus()
    let rect = NSRect(origin: .zero, size: size)
    color.set()
    rect.fill()
    draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
    img.unlockFocus()
    return img
  }
}
