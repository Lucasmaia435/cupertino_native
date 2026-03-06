import FlutterMacOS
import Cocoa
import CoreText

class CupertinoSearchBarNSView: NSView, NSSearchFieldDelegate {
  private struct FlutterFontManifestEntry {
    let family: String
    let assets: [String]
  }

  private struct TrailingAction {
    let iconDataCodePoint: Int
    let iconDataFontFamily: String?
    let iconDataFontPackage: String?
    let iconDataMatchTextDirection: Bool
    let iconDataColor: NSColor?
    let iconDataSize: CGFloat
    let iconDataFill: CGFloat?
    let iconDataWeight: CGFloat?
    let iconDataGrade: CGFloat?
    let iconDataOpticalSize: CGFloat?
  }

  private static var cachedFlutterAssetsURL: URL?
  private static var cachedFontManifest: [FlutterFontManifestEntry]?

  private let channel: FlutterMethodChannel
  private let searchField: NSSearchField
  private let trailingButtons: [NSButton]
  private let trailingButtonsStack: NSStackView
  private var searchFieldTrailingConstraint: NSLayoutConstraint!
  private var trailingButtonWidthConstraints: [NSLayoutConstraint] = []
  private var trailingButtonHeightConstraints: [NSLayoutConstraint] = []
  private var trailingButtonsEnabled: [Bool] = [false, false]
  private var currentTrailingActions: [TrailingAction] = []
  private var currentTint: NSColor? = nil
  private var requestedHeight: CGFloat = 56

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    let firstTrailingButton = NSButton(title: "", target: nil, action: nil)
    let secondTrailingButton = NSButton(title: "", target: nil, action: nil)
    self.channel = FlutterMethodChannel(name: "CupertinoNativeSearchBar_\(viewId)", binaryMessenger: messenger)
    self.searchField = NSSearchField(frame: .zero)
    self.trailingButtons = [firstTrailingButton, secondTrailingButton]
    self.trailingButtonsStack = NSStackView(views: [firstTrailingButton, secondTrailingButton])

    var text: String = ""
    var placeholder: String? = nil
    var enabled: Bool = true
    var height: CGFloat = 56
    var isDark: Bool = false
    var tint: NSColor? = nil
    var bg: NSColor? = nil
    var fieldBg: NSColor? = nil
    var trailingActions: [TrailingAction] = []

    if let dict = args as? [String: Any] {
      if let value = dict["text"] as? String { text = value }
      if let value = dict["placeholder"] as? String { placeholder = value }
      if let value = dict["enabled"] as? NSNumber { enabled = value.boolValue }
      if let value = dict["height"] as? NSNumber { height = CGFloat(truncating: value) }
      if let value = dict["isDark"] as? NSNumber { isDark = value.boolValue }
      if let style = dict["style"] as? [String: Any] {
        if let value = style["tint"] as? NSNumber { tint = Self.colorFromARGB(value.intValue) }
        if let value = style["backgroundColor"] as? NSNumber { bg = Self.colorFromARGB(value.intValue) }
        if let value = style["fieldBackgroundColor"] as? NSNumber { fieldBg = Self.colorFromARGB(value.intValue) }
      }
      trailingActions = Self.parseTrailingActions(dict["traillingActions"])
    }
    currentTint = tint

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
    requestedHeight = max(24, min(height, 240))

    for (index, trailingButton) in trailingButtons.enumerated() {
      trailingButton.translatesAutoresizingMaskIntoConstraints = false
      trailingButton.bezelStyle = .shadowlessSquare
      trailingButton.isBordered = false
      trailingButton.imagePosition = .imageOnly
      trailingButton.setButtonType(.momentaryChange)
      trailingButton.target = self
      trailingButton.action = #selector(onTrailingPressed(_:))
      trailingButton.tag = index
      trailingButton.isHidden = true
      trailingButton.isEnabled = false
    }

    trailingButtonsStack.translatesAutoresizingMaskIntoConstraints = false
    trailingButtonsStack.orientation = .horizontal
    trailingButtonsStack.alignment = .centerY
    trailingButtonsStack.spacing = 0

    if let color = tint, #available(macOS 10.14, *) {
      for trailingButton in trailingButtons {
        trailingButton.contentTintColor = color
      }
    }
    if let color = fieldBg {
      searchField.drawsBackground = true
      searchField.backgroundColor = color
    }
    if let color = bg {
      layer?.backgroundColor = color.cgColor
    }
    applyHeight(height)

    addSubview(searchField)
    addSubview(trailingButtonsStack)
    searchFieldTrailingConstraint = searchField.trailingAnchor.constraint(equalTo: trailingAnchor)
    trailingButtonWidthConstraints = trailingButtons.map {
      $0.widthAnchor.constraint(equalToConstant: 18)
    }
    trailingButtonHeightConstraints = trailingButtons.map {
      $0.heightAnchor.constraint(equalToConstant: 18)
    }
    NSLayoutConstraint.activate([
      searchField.leadingAnchor.constraint(equalTo: leadingAnchor),
      searchFieldTrailingConstraint,
      searchField.topAnchor.constraint(equalTo: topAnchor),
      searchField.bottomAnchor.constraint(equalTo: bottomAnchor),
      trailingButtonsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      trailingButtonsStack.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
      trailingButtonWidthConstraints[0],
      trailingButtonHeightConstraints[0],
      trailingButtonWidthConstraints[1],
      trailingButtonHeightConstraints[1]
    ])

    applyTrailingActions(trailingActions)
    applyEnabled(enabled)
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.applyTrailingActions(self.currentTrailingActions)
    }

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "getIntrinsicSize":
        let size = self.searchField.intrinsicContentSize
        result(["width": Double(size.width), "height": Double(self.requestedHeight)])
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
      case "setHeight":
        if let params = call.arguments as? [String: Any], let value = params["height"] as? NSNumber {
          self.applyHeight(CGFloat(truncating: value))
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing height", details: nil)) }
      case "setTrailingActions":
        if let params = call.arguments as? [String: Any] {
          self.applyTrailingActions(Self.parseTrailingActions(params["traillingActions"]))
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing trailing actions args", details: nil)) }
      case "setStyle":
        if let params = call.arguments as? [String: Any] {
          if let value = params["tint"] as? NSNumber, #available(macOS 10.14, *) {
            self.currentTint = Self.colorFromARGB(value.intValue)
            self.applyTrailingActions(self.currentTrailingActions)
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
      case "setVisible":
        if let params = call.arguments as? [String: Any], let visible = (params["visible"] as? NSNumber)?.boolValue {
          self.isHidden = !visible
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing visible", details: nil)) }
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

  func controlTextDidBeginEditing(_ obj: Notification) {
    channel.invokeMethod("tapped", arguments: nil)
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

  @objc private func onSubmit(_ sender: NSSearchField) {
    channel.invokeMethod("submitted", arguments: ["text": sender.stringValue])
  }

  @objc private func onTrailingPressed(_ sender: NSButton) {
    let index = sender.tag
    guard index >= 0,
          index < trailingButtonsEnabled.count,
          trailingButtonsEnabled[index],
          searchField.isEnabled else {
      return
    }
    channel.invokeMethod("trailingActionPressed", arguments: ["index": index])
  }

  private func applyEnabled(_ enabled: Bool) {
    searchField.isEnabled = enabled
    searchField.alphaValue = enabled ? 1.0 : 0.6
    for (index, trailingButton) in trailingButtons.enumerated() {
      trailingButton.isEnabled = enabled && trailingButtonsEnabled[index]
      trailingButton.alphaValue = trailingButton.isEnabled ? 1.0 : 0.6
    }
  }

  private func applyHeight(_ height: CGFloat) {
    requestedHeight = max(24, min(height, 240))
    let fontSize = max(12, min(24, requestedHeight * 0.42))
    let fieldFont = NSFont.systemFont(ofSize: fontSize)
    searchField.font = fieldFont
    if let cell = searchField.cell as? NSSearchFieldCell {
      cell.font = fieldFont
      cell.controlSize = requestedHeight < 30 ? .small : .regular
    }
    searchField.invalidateIntrinsicContentSize()
    needsLayout = true
    layoutSubtreeIfNeeded()
  }

  private func applyTrailingActions(_ actions: [TrailingAction]) {
    currentTrailingActions = Array(actions.prefix(2))
    for index in 0..<trailingButtons.count {
      guard index < currentTrailingActions.count,
            let image = Self.iconImage(
              codePoint: currentTrailingActions[index].iconDataCodePoint,
              fontFamily: currentTrailingActions[index].iconDataFontFamily,
              fontPackage: currentTrailingActions[index].iconDataFontPackage,
              pointSize: actionIconPointSize(currentTrailingActions[index]),
              fill: currentTrailingActions[index].iconDataFill,
              weight: currentTrailingActions[index].iconDataWeight,
              grade: currentTrailingActions[index].iconDataGrade,
              opticalSize: currentTrailingActions[index].iconDataOpticalSize
            ) else {
        trailingButtons[index].image = nil
        trailingButtons[index].isHidden = true
        trailingButtonsEnabled[index] = false
        trailingButtonWidthConstraints[index].constant = 0
        trailingButtonHeightConstraints[index].constant = 0
        continue
      }
      let _ = currentTrailingActions[index].iconDataMatchTextDirection
      trailingButtons[index].image = image
      trailingButtons[index].isHidden = false
      trailingButtonsEnabled[index] = true
      let side = actionButtonSide(currentTrailingActions[index])
      trailingButtonWidthConstraints[index].constant = side
      trailingButtonHeightConstraints[index].constant = side
      if #available(macOS 10.14, *) {
        trailingButtons[index].contentTintColor =
          currentTrailingActions[index].iconDataColor ?? currentTint
      }
    }

    let visibleSizes = trailingButtons.enumerated().compactMap { index, button -> CGFloat? in
      guard !button.isHidden else { return nil }
      return trailingButtonWidthConstraints[index].constant
    }
    if visibleSizes.isEmpty {
      searchFieldTrailingConstraint.constant = 0
    } else {
      let iconWidth = visibleSizes.reduce(CGFloat(0), +)
      let spacing =
        CGFloat(max(0, visibleSizes.count - 1)) * trailingButtonsStack.spacing
      searchFieldTrailingConstraint.constant = -(iconWidth + spacing + 10)
    }
    applyEnabled(searchField.isEnabled)
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

  private static func parseOptionalColor(_ value: Any?) -> NSColor? {
    if value is NSNull { return nil }
    if let number = value as? NSNumber { return colorFromARGB(number.intValue) }
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
