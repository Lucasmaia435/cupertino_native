import Flutter
import UIKit
import CoreText

class CupertinoTabBarPlatformView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private struct FlutterFontManifestEntry {
    let family: String
    let assets: [String]
  }

  private static var cachedFlutterAssetsURL: URL?
  private static var cachedFontManifest: [FlutterFontManifestEntry]?

  private let channel: FlutterMethodChannel
  private let container: UIView
  private var tabBar: UITabBar?
  private var tabBarLeft: UITabBar?
  private var tabBarRight: UITabBar?

  private var isSplit: Bool = false
  private var rightCountVal: Int = 1
  private var leftInsetVal: CGFloat = 0
  private var rightInsetVal: CGFloat = 0
  private var splitSpacingVal: CGFloat = 8

  private var currentLabels: [String] = []
  private var currentSymbols: [String] = []
  private var currentIconCodePoints: [Int?] = []
  private var currentIconFontFamilies: [String?] = []
  private var currentIconFontPackages: [String?] = []
  private var currentIconMatchDirections: [Bool] = []
  private var currentIconFills: [CGFloat?] = []
  private var currentIconWeights: [CGFloat?] = []
  private var currentIconGrades: [CGFloat?] = []
  private var currentIconOpticalSizes: [CGFloat?] = []
  private var currentSizes: [CGFloat?] = []
  private var currentTintColor: UIColor? = nil
  private var currentBackgroundColor: UIColor? = nil

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(
      name: "CupertinoNativeTabBar_\(viewId)",
      binaryMessenger: messenger
    )
    self.container = UIView(frame: frame)

    var selectedIndex: Int = 0
    var isDark: Bool = false

    if let dict = args as? [String: Any] {
      currentLabels = (dict["labels"] as? [String]) ?? []
      currentSymbols = (dict["sfSymbols"] as? [String]) ?? []
      currentIconCodePoints = Self.parseOptionalIntArray(dict["iconDataCodePoints"])
      currentIconFontFamilies = Self.parseOptionalStringArray(dict["iconDataFontFamilies"])
      currentIconFontPackages = Self.parseOptionalStringArray(dict["iconDataFontPackages"])
      currentIconMatchDirections = Self.parseBoolArray(dict["iconDataMatchTextDirections"])
      currentIconFills = Self.parseOptionalDoubleArray(dict["iconDataFills"])
      currentIconWeights = Self.parseOptionalDoubleArray(dict["iconDataWeights"])
      currentIconGrades = Self.parseOptionalDoubleArray(dict["iconDataGrades"])
      currentIconOpticalSizes = Self.parseOptionalDoubleArray(dict["iconDataOpticalSizes"])
      currentSizes = Self.parseOptionalDoubleArray(dict["sfSymbolSizes"])
      if let value = dict["selectedIndex"] as? NSNumber { selectedIndex = value.intValue }
      if let value = dict["isDark"] as? NSNumber { isDark = value.boolValue }
      if let style = dict["style"] as? [String: Any] {
        if let value = style["tint"] as? NSNumber {
          currentTintColor = Self.colorFromARGB(value.intValue)
        }
        if let value = style["backgroundColor"] as? NSNumber {
          currentBackgroundColor = Self.colorFromARGB(value.intValue)
        }
      }
      if let value = dict["split"] as? NSNumber { isSplit = value.boolValue }
      if let value = dict["rightCount"] as? NSNumber { rightCountVal = value.intValue }
      if let value = dict["splitSpacing"] as? NSNumber {
        splitSpacingVal = CGFloat(truncating: value)
      }
    }

    super.init()

    container.backgroundColor = .clear
    if #available(iOS 13.0, *) {
      container.overrideUserInterfaceStyle = isDark ? .dark : .light
    }

    rebuildBars(selectedIndex: selectedIndex)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "getIntrinsicSize":
        if let bar = self.tabBar ?? self.tabBarLeft ?? self.tabBarRight {
          let size = bar.sizeThatFits(
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
          )
          result(["width": Double(size.width), "height": Double(size.height)])
        } else {
          result(["width": Double(self.container.bounds.width), "height": 50.0])
        }
      case "setItems":
        if let params = call.arguments as? [String: Any] {
          self.currentLabels = (params["labels"] as? [String]) ?? []
          self.currentSymbols = (params["sfSymbols"] as? [String]) ?? []
          self.currentIconCodePoints = Self.parseOptionalIntArray(params["iconDataCodePoints"])
          self.currentIconFontFamilies = Self.parseOptionalStringArray(params["iconDataFontFamilies"])
          self.currentIconFontPackages = Self.parseOptionalStringArray(params["iconDataFontPackages"])
          self.currentIconMatchDirections = Self.parseBoolArray(params["iconDataMatchTextDirections"])
          self.currentIconFills = Self.parseOptionalDoubleArray(params["iconDataFills"])
          self.currentIconWeights = Self.parseOptionalDoubleArray(params["iconDataWeights"])
          self.currentIconGrades = Self.parseOptionalDoubleArray(params["iconDataGrades"])
          self.currentIconOpticalSizes = Self.parseOptionalDoubleArray(params["iconDataOpticalSizes"])
          self.currentSizes = Self.parseOptionalDoubleArray(params["sfSymbolSizes"])
          let selectedIndex = (params["selectedIndex"] as? NSNumber)?.intValue ?? 0
          self.rebuildBars(selectedIndex: selectedIndex)
          result(nil)
        } else {
          result(FlutterError(code: "bad_args", message: "Missing items", details: nil))
        }
      case "setItemIconStyle":
        if let params = call.arguments as? [String: Any],
           let index = (params["index"] as? NSNumber)?.intValue {
          self.updateItemIconStyle(at: index, params: params)
          result(nil)
        } else {
          result(FlutterError(code: "bad_args", message: "Missing icon style args", details: nil))
        }
      case "setLayout":
        if let params = call.arguments as? [String: Any] {
          self.isSplit = (params["split"] as? NSNumber)?.boolValue ?? false
          self.rightCountVal = (params["rightCount"] as? NSNumber)?.intValue ?? 1
          if let value = params["splitSpacing"] as? NSNumber {
            self.splitSpacingVal = CGFloat(truncating: value)
          }
          let selectedIndex = (params["selectedIndex"] as? NSNumber)?.intValue ?? 0
          self.rebuildBars(selectedIndex: selectedIndex)
          result(nil)
        } else {
          result(FlutterError(code: "bad_args", message: "Missing layout", details: nil))
        }
      case "setSelectedIndex":
        if let params = call.arguments as? [String: Any],
           let index = (params["index"] as? NSNumber)?.intValue {
          self.applySelection(selectedIndex: index)
          result(nil)
        } else {
          result(FlutterError(code: "bad_args", message: "Missing index", details: nil))
        }
      case "setStyle":
        if let params = call.arguments as? [String: Any] {
          if let value = params["tint"] as? NSNumber {
            self.currentTintColor = Self.colorFromARGB(value.intValue)
          }
          if let value = params["backgroundColor"] as? NSNumber {
            self.currentBackgroundColor = Self.colorFromARGB(value.intValue)
          }
          if let bar = self.tabBar { self.applyStyle(to: bar) }
          if let left = self.tabBarLeft { self.applyStyle(to: left) }
          if let right = self.tabBarRight { self.applyStyle(to: right) }
          result(nil)
        } else {
          result(FlutterError(code: "bad_args", message: "Missing style", details: nil))
        }
      case "setBrightness":
        if let params = call.arguments as? [String: Any],
           let isDark = (params["isDark"] as? NSNumber)?.boolValue {
          if #available(iOS 13.0, *) {
            self.container.overrideUserInterfaceStyle = isDark ? .dark : .light
          }
          result(nil)
        } else {
          result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    return container
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    if let single = self.tabBar, single === tabBar, let items = single.items,
       let idx = items.firstIndex(of: item) {
      channel.invokeMethod("valueChanged", arguments: ["index": idx])
      return
    }
    if let left = tabBarLeft, left === tabBar, let items = left.items,
       let idx = items.firstIndex(of: item) {
      tabBarRight?.selectedItem = nil
      channel.invokeMethod("valueChanged", arguments: ["index": idx])
      return
    }
    if let right = tabBarRight, right === tabBar, let items = right.items,
       let idx = items.firstIndex(of: item), let left = tabBarLeft,
       let leftItems = left.items {
      tabBarLeft?.selectedItem = nil
      channel.invokeMethod("valueChanged", arguments: ["index": leftItems.count + idx])
      return
    }
  }

  private func rebuildBars(selectedIndex: Int) {
    tabBar?.removeFromSuperview()
    tabBarLeft?.removeFromSuperview()
    tabBarRight?.removeFromSuperview()
    tabBar = nil
    tabBarLeft = nil
    tabBarRight = nil

    let count = totalItemCount()
    if isSplit && count > rightCountVal {
      let leftEnd = count - rightCountVal
      let left = UITabBar(frame: .zero)
      let right = UITabBar(frame: .zero)
      tabBarLeft = left
      tabBarRight = right
      left.translatesAutoresizingMaskIntoConstraints = false
      right.translatesAutoresizingMaskIntoConstraints = false
      left.delegate = self
      right.delegate = self
      applyStyle(to: left)
      applyStyle(to: right)
      left.items = buildItems(0..<leftEnd)
      right.items = buildItems(leftEnd..<count)
      applySelection(selectedIndex: selectedIndex)
      container.addSubview(left)
      container.addSubview(right)

      let spacing: CGFloat = splitSpacingVal
      let leftWidth = left.sizeThatFits(.zero).width + leftInsetVal * 2
      let rightWidth = right.sizeThatFits(.zero).width + rightInsetVal * 2
      let total = leftWidth + rightWidth + spacing
      if total > container.bounds.width, count > 0 {
        let rightFraction = CGFloat(rightCountVal) / CGFloat(count)
        NSLayoutConstraint.activate([
          right.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -rightInsetVal),
          right.topAnchor.constraint(equalTo: container.topAnchor),
          right.bottomAnchor.constraint(equalTo: container.bottomAnchor),
          right.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: rightFraction),
          left.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leftInsetVal),
          left.trailingAnchor.constraint(equalTo: right.leadingAnchor, constant: -spacing),
          left.topAnchor.constraint(equalTo: container.topAnchor),
          left.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
      } else {
        NSLayoutConstraint.activate([
          right.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -rightInsetVal),
          right.topAnchor.constraint(equalTo: container.topAnchor),
          right.bottomAnchor.constraint(equalTo: container.bottomAnchor),
          right.widthAnchor.constraint(equalToConstant: rightWidth),
          left.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leftInsetVal),
          left.topAnchor.constraint(equalTo: container.topAnchor),
          left.bottomAnchor.constraint(equalTo: container.bottomAnchor),
          left.widthAnchor.constraint(equalToConstant: leftWidth),
          left.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -spacing)
        ])
      }
      return
    }

    let bar = UITabBar(frame: .zero)
    tabBar = bar
    bar.delegate = self
    bar.translatesAutoresizingMaskIntoConstraints = false
    applyStyle(to: bar)
    bar.items = buildItems(0..<count)
    applySelection(selectedIndex: selectedIndex)
    container.addSubview(bar)
    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      bar.topAnchor.constraint(equalTo: container.topAnchor),
      bar.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])
  }

  private func applyStyle(to tabBar: UITabBar) {
    if let color = currentBackgroundColor { tabBar.barTintColor = color }
    if #available(iOS 10.0, *), let color = currentTintColor { tabBar.tintColor = color }
    if #available(iOS 13.0, *) {
      let appearance = UITabBarAppearance()
      appearance.configureWithDefaultBackground()
      tabBar.standardAppearance = appearance
      if #available(iOS 15.0, *) {
        tabBar.scrollEdgeAppearance = appearance
      }
    }
  }

  private func applySelection(selectedIndex: Int) {
    if let bar = tabBar, let items = bar.items, selectedIndex >= 0, selectedIndex < items.count {
      bar.selectedItem = items[selectedIndex]
      return
    }
    if let left = tabBarLeft, let leftItems = left.items {
      if selectedIndex >= 0, selectedIndex < leftItems.count {
        left.selectedItem = leftItems[selectedIndex]
        tabBarRight?.selectedItem = nil
        return
      }
      if let right = tabBarRight, let rightItems = right.items {
        let rightIndex = selectedIndex - leftItems.count
        if rightIndex >= 0, rightIndex < rightItems.count {
          right.selectedItem = rightItems[rightIndex]
          tabBarLeft?.selectedItem = nil
        }
      }
    }
  }

  private func updateItemIconStyle(at index: Int, params: [String: Any]) {
    guard index >= 0 else { return }
    ensureStyleCapacity(index: index)

    if params.keys.contains("sfSymbolSize") {
      currentSizes[index] = Self.parseOptionalCGFloat(params["sfSymbolSize"])
    }
    if params.keys.contains("iconDataFill") {
      currentIconFills[index] = Self.parseOptionalCGFloat(params["iconDataFill"])
    }
    if params.keys.contains("iconDataWeight") {
      currentIconWeights[index] = Self.parseOptionalCGFloat(params["iconDataWeight"])
    }
    if params.keys.contains("iconDataGrade") {
      currentIconGrades[index] = Self.parseOptionalCGFloat(params["iconDataGrade"])
    }
    if params.keys.contains("iconDataOpticalSize") {
      currentIconOpticalSizes[index] = Self.parseOptionalCGFloat(params["iconDataOpticalSize"])
    }

    let image = imageForItem(index)
    if let bar = tabBar, let items = bar.items, index < items.count {
      items[index].image = image
      items[index].selectedImage = image
      return
    }
    if let left = tabBarLeft, let leftItems = left.items {
      if index < leftItems.count {
        leftItems[index].image = image
        leftItems[index].selectedImage = image
        return
      }
      if let right = tabBarRight, let rightItems = right.items {
        let rightIndex = index - leftItems.count
        if rightIndex >= 0, rightIndex < rightItems.count {
          rightItems[rightIndex].image = image
          rightItems[rightIndex].selectedImage = image
        }
      }
    }
  }

  private func ensureStyleCapacity(index: Int) {
    let targetCount = index + 1
    func expand<T>(_ array: inout [T?]) {
      if array.count < targetCount {
        array.append(contentsOf: Array(repeating: nil, count: targetCount - array.count))
      }
    }
    expand(&currentSizes)
    expand(&currentIconFills)
    expand(&currentIconWeights)
    expand(&currentIconGrades)
    expand(&currentIconOpticalSizes)
  }

  private func buildItems(_ range: Range<Int>) -> [UITabBarItem] {
    var items: [UITabBarItem] = []
    let normalAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 10, weight: .regular)
    ]
    let selectedAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
    ]
    for index in range {
      let title = index < currentLabels.count ? currentLabels[index] : nil
      let image = imageForItem(index)
      let item = UITabBarItem(title: title, image: image, selectedImage: image)
      item.setTitleTextAttributes(normalAttrs, for: .normal)
      item.setTitleTextAttributes(selectedAttrs, for: .selected)
      items.append(item)
    }
    return items
  }

  private func imageForItem(_ index: Int) -> UIImage? {
    if index < currentSymbols.count {
      let symbolName = currentSymbols[index]
      if !symbolName.isEmpty, var image = UIImage(systemName: symbolName) {
        if index < currentSizes.count, let size = currentSizes[index] {
          image = image.applyingSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: size)
          ) ?? image
        }
        return image
      }
    }

    guard index < currentIconCodePoints.count,
          let codePoint = currentIconCodePoints[index] else {
      return nil
    }

    let family = index < currentIconFontFamilies.count ? currentIconFontFamilies[index] : nil
    let package = index < currentIconFontPackages.count ? currentIconFontPackages[index] : nil
    let fill = index < currentIconFills.count ? currentIconFills[index] : nil
    let weight = index < currentIconWeights.count ? currentIconWeights[index] : nil
    let grade = index < currentIconGrades.count ? currentIconGrades[index] : nil
    let opticalSize = index < currentIconOpticalSizes.count
      ? currentIconOpticalSizes[index]
      : nil
    let pointSize: CGFloat = index < currentSizes.count
      ? (currentSizes[index] ?? 20)
      : 20
    guard var image = Self.iconImage(
      codePoint: codePoint,
      fontFamily: family,
      fontPackage: package,
      pointSize: pointSize,
      fill: fill,
      weight: weight,
      grade: grade,
      opticalSize: opticalSize
    ) else {
      return nil
    }
    if index < currentIconMatchDirections.count, currentIconMatchDirections[index] {
      image = image.imageFlippedForRightToLeftLayoutDirection()
    }
    return image
  }

  private func totalItemCount() -> Int {
    return max(max(currentLabels.count, currentSymbols.count), currentIconCodePoints.count)
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

  private static func parseOptionalCGFloat(_ value: Any?) -> CGFloat? {
    if value is NSNull { return nil }
    if let number = value as? NSNumber { return CGFloat(truncating: number) }
    return nil
  }

  private static func parseOptionalDoubleArray(_ value: Any?) -> [CGFloat?] {
    guard let raw = value as? [Any] else { return [] }
    return raw.map { element in
      if element is NSNull { return nil }
      if let number = element as? NSNumber {
        return CGFloat(truncating: number)
      }
      return nil
    }
  }

  private static func colorFromARGB(_ argb: Int) -> UIColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
}
