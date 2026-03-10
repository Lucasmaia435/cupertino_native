import FlutterMacOS
import Cocoa
import CoreText
import SwiftUI

@available(macOS 26.0, *)
private struct MacGlassInputBackground: View {
  let cornerRadius: CGFloat
  let accentColor: NSColor
  let isDark: Bool
  let isEnabled: Bool

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    shape
      .fill(Color.clear)
      .glassEffect(.regular, in: shape)
      .overlay(
        shape.stroke(
          Color.white.opacity(isDark ? 0.18 : 0.34),
          lineWidth: 1
        )
      )
      .overlay {
        shape.fill(
          LinearGradient(
            colors: [
              Color.white.opacity(isDark ? 0.14 : 0.22),
              Color.white.opacity(isDark ? 0.04 : 0.08),
              Color.clear,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      }
      .overlay {
        shape.fill(Color(nsColor: accentColor).opacity(isDark ? 0.04 : 0.06))
      }
      .opacity(isEnabled ? 1.0 : 0.9)
      .allowsHitTesting(false)
  }
}

private final class NonFlashingScrollView: NSScrollView {
  override func flashScrollers() {}
}

class CupertinoSearchBarNSView: NSView, NSTextViewDelegate {
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
  private let fieldClipView: NSView
  private let fieldBackgroundView: NSVisualEffectView
  private let fieldTintOverlayView: NSView
  private let scrollView: NSScrollView
  private let textView: NSTextView
  private let placeholderLabel: NSTextField
  private let clearButton: NSButton
  private let trailingButtons: [NSButton]
  private let trailingButtonsStack: NSStackView
  private let sendButton: NSButton
  private let searchButton: NSButton
  private let cancelButton: NSButton
  private var glassHostingView: NSHostingView<AnyView>?
  private var leadingSearchWidthConstraint: NSLayoutConstraint!
  private var searchButtonFirstLineCenterYConstraint: NSLayoutConstraint!
  private var trailingButtonsFirstLineCenterYConstraint: NSLayoutConstraint!
  private var trailingButtonsCenterYConstraint: NSLayoutConstraint!
  private var trailingButtonsTrailingConstraint: NSLayoutConstraint!
  private var trailingButtonsBottomConstraint: NSLayoutConstraint!
  private var sendButtonWidthConstraint: NSLayoutConstraint!
  private var sendButtonHeightConstraint: NSLayoutConstraint!
  private var placeholderTopConstraint: NSLayoutConstraint!
  private var fieldTrailingConstraintToContainer: NSLayoutConstraint!
  private var fieldTrailingConstraintToCancel: NSLayoutConstraint!
  private var trailingButtonsEnabled: [Bool] = [false, false]
  private var currentTrailingActions: [TrailingAction] = []
  private var currentTint: NSColor? = nil
  private var customBackgroundColor: NSColor? = nil
  private var customFieldBackgroundColor: NSColor? = nil
  private var customSendButtonBackgroundColor: NSColor? = nil
  private var controlEnabled = true
  private var focusEnabled = true
  private var isSearchMode = true
  private var showsCancelButton = false
  private var requestedMinHeight: CGFloat = 44
  private var requestedMaxHeight: CGFloat = 240
  private var maxVisibleLines = 1
  private var lastReportedHeight: CGFloat = 0
  private var isDarkAppearance = false

  private let compactHorizontalPadding: CGFloat = 16
  private let compactVerticalPadding: CGFloat = 8
  private let fieldCornerRadius: CGFloat = 28
  private let accessoryButtonSize: CGFloat = 32
  private let sendButtonOuterInset: CGFloat = 8
  private let sendButtonIconSize: CGFloat = 16
  private let sendButtonDiameterBoost: CGFloat = 8
  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    let clearButton = NSButton(title: "", target: nil, action: nil)
    let firstTrailingButton = NSButton(title: "", target: nil, action: nil)
    let secondTrailingButton = NSButton(title: "", target: nil, action: nil)
    let sendButton = NSButton(title: "", target: nil, action: nil)
    let searchButton = NSButton(title: "", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    self.channel = FlutterMethodChannel(name: "CupertinoNativeSearchBar_\(viewId)", binaryMessenger: messenger)
    self.fieldClipView = NSView(frame: .zero)
    self.fieldBackgroundView = NSVisualEffectView(frame: .zero)
    self.fieldTintOverlayView = NSView(frame: .zero)
    self.scrollView = NonFlashingScrollView(frame: .zero)
    self.textView = NSTextView(frame: .zero)
    self.placeholderLabel = NSTextField(labelWithString: "")
    self.clearButton = clearButton
    self.trailingButtons = [firstTrailingButton, secondTrailingButton]
    self.trailingButtonsStack = NSStackView(views: [clearButton, firstTrailingButton, secondTrailingButton, sendButton])
    self.sendButton = sendButton
    self.searchButton = searchButton
    self.cancelButton = cancelButton

    var text: String = ""
    var placeholder: String? = nil
    var enabled: Bool = true
    var isSearchMode: Bool = true
    var showsCancelButton: Bool = false
    var minHeight: CGFloat = 44
    var maxHeight: CGFloat = 240
    var maxVisibleLines: Int = 1
    var focusEnabled: Bool = true
    var isDark: Bool = false
    var tint: NSColor? = nil
    var bg: NSColor? = nil
    var fieldBg: NSColor? = nil
    var sendButtonBg: NSColor? = nil
    var trailingActions: [TrailingAction] = []

    if let dict = args as? [String: Any] {
      if let value = dict["text"] as? String { text = value }
      if let value = dict["placeholder"] as? String { placeholder = value }
      if let value = dict["enabled"] as? NSNumber { enabled = value.boolValue }
      if let value = dict["isSearch"] as? NSNumber { isSearchMode = value.boolValue }
      if let value = dict["showsCancelButton"] as? NSNumber { showsCancelButton = value.boolValue }
      if let value = dict["minHeight"] as? NSNumber { minHeight = CGFloat(truncating: value) }
      if let value = dict["maxHeight"] as? NSNumber { maxHeight = CGFloat(truncating: value) }
      if let value = dict["maxVisibleLines"] as? NSNumber { maxVisibleLines = value.intValue }
      if let value = dict["focusEnabled"] as? NSNumber { focusEnabled = value.boolValue }
      if let value = dict["isDark"] as? NSNumber { isDark = value.boolValue }
      if let style = dict["style"] as? [String: Any] {
        if let value = style["tint"] as? NSNumber { tint = Self.colorFromARGB(value.intValue) }
        if let value = style["backgroundColor"] as? NSNumber { bg = Self.colorFromARGB(value.intValue) }
        if let value = style["fieldBackgroundColor"] as? NSNumber { fieldBg = Self.colorFromARGB(value.intValue) }
        if let value = style["sendButtonBackgroundColor"] as? NSNumber {
          sendButtonBg = Self.colorFromARGB(value.intValue)
        }
      }
      trailingActions = Self.parseTrailingActions(dict["traillingActions"])
    }
    currentTint = tint

    super.init(frame: .zero)

    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    isDarkAppearance = isDark
    customBackgroundColor = bg
    customFieldBackgroundColor = fieldBg
    customSendButtonBackgroundColor = sendButtonBg
    controlEnabled = enabled
    self.focusEnabled = focusEnabled
    self.isSearchMode = isSearchMode
    self.showsCancelButton = showsCancelButton
    requestedMinHeight = max(28, min(minHeight, maxHeight))
    requestedMaxHeight = max(requestedMinHeight, min(maxHeight, 240))
    self.maxVisibleLines = max(1, maxVisibleLines)

    fieldClipView.translatesAutoresizingMaskIntoConstraints = false
    fieldClipView.wantsLayer = true
    fieldClipView.layer?.cornerRadius = fieldCornerRadius
    fieldClipView.layer?.masksToBounds = true

    fieldBackgroundView.translatesAutoresizingMaskIntoConstraints = false
    fieldBackgroundView.blendingMode = .withinWindow
    fieldBackgroundView.state = .active

    fieldTintOverlayView.translatesAutoresizingMaskIntoConstraints = false
    fieldTintOverlayView.wantsLayer = true

    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = false
    scrollView.scrollerStyle = .legacy

    textView.delegate = self
    textView.translatesAutoresizingMaskIntoConstraints = false
    textView.drawsBackground = false
    textView.isRichText = false
    textView.importsGraphics = false
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: 0,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.string = text
    textView.font = NSFont.systemFont(ofSize: 16)
    applyTextInsets()
    scrollView.documentView = textView

    placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
    placeholderLabel.stringValue = placeholder ?? ""
    placeholderLabel.lineBreakMode = .byTruncatingTail

    trailingButtonsStack.translatesAutoresizingMaskIntoConstraints = false
    trailingButtonsStack.orientation = .horizontal
    trailingButtonsStack.alignment = .centerY
    trailingButtonsStack.spacing = 6

    configureAccessoryButton(clearButton, size: accessoryButtonSize)
    clearButton.target = self
    clearButton.action = #selector(onClearPressed)
    clearButton.image = Self.systemSymbolImage(
      named: "xmark.circle.fill",
      fallback: NSImage.stopProgressTemplateName
    )

    for (index, trailingButton) in trailingButtons.enumerated() {
      configureAccessoryButton(trailingButton, size: accessoryButtonSize)
      trailingButton.target = self
      trailingButton.action = #selector(onTrailingPressed(_:))
      trailingButton.tag = index
      trailingButton.isHidden = true
      trailingButton.isEnabled = false
    }

    let sendButtonSizeConstraints = configureAccessoryButton(
      sendButton,
      size: sendButtonDiameter(for: requestedMinHeight)
    )
    sendButtonWidthConstraint = sendButtonSizeConstraints.width
    sendButtonHeightConstraint = sendButtonSizeConstraints.height
    sendButton.target = self
    sendButton.action = #selector(onSendPressed)
    sendButton.image = Self.systemSymbolImage(
      named: "arrow.up",
      fallback: NSImage.touchBarGoUpTemplateName
    )
    sendButton.imageScaling = .scaleProportionallyDown
    if #available(macOS 11.0, *),
       let configuredImage = sendButton.image?.withSymbolConfiguration(
         NSImage.SymbolConfiguration(pointSize: sendButtonIconSize, weight: .medium)
       ) {
      sendButton.image = configuredImage
    }

    configureAccessoryButton(searchButton, size: accessoryButtonSize)
    searchButton.target = self
    searchButton.action = #selector(onSearchPressed)
    searchButton.image = Self.systemSymbolImage(
      named: "magnifyingglass",
      fallback: NSImage.touchBarSearchTemplateName
    )

    cancelButton.translatesAutoresizingMaskIntoConstraints = false
    cancelButton.isBordered = false
    cancelButton.target = self
    cancelButton.action = #selector(onCancelPressed)
    cancelButton.focusRingType = .none
    cancelButton.font = NSFont.systemFont(ofSize: 14)
    cancelButton.setButtonType(.momentaryPushIn)

    addSubview(fieldClipView)
    addSubview(cancelButton)
    fieldClipView.addSubview(fieldBackgroundView)
    installGlassBackgroundIfNeeded()
    fieldClipView.addSubview(fieldTintOverlayView)
    fieldClipView.addSubview(searchButton)
    fieldClipView.addSubview(scrollView)
    fieldClipView.addSubview(placeholderLabel)
    fieldClipView.addSubview(trailingButtonsStack)

    leadingSearchWidthConstraint = searchButton.widthAnchor.constraint(equalToConstant: accessoryButtonSize)
    let firstLineCenterOffset = currentFirstLineCenterOffset()
    searchButtonFirstLineCenterYConstraint = searchButton.centerYAnchor.constraint(
      equalTo: scrollView.topAnchor,
      constant: firstLineCenterOffset
    )
    trailingButtonsFirstLineCenterYConstraint = trailingButtonsStack.centerYAnchor.constraint(
      equalTo: scrollView.topAnchor,
      constant: firstLineCenterOffset
    )
    trailingButtonsCenterYConstraint = trailingButtonsStack.centerYAnchor.constraint(
      equalTo: fieldClipView.centerYAnchor
    )
    trailingButtonsTrailingConstraint = trailingButtonsStack.trailingAnchor.constraint(
      equalTo: fieldClipView.trailingAnchor,
      constant: -(compactHorizontalPadding - 2)
    )
    trailingButtonsBottomConstraint = trailingButtonsStack.bottomAnchor.constraint(
      equalTo: fieldClipView.bottomAnchor,
      constant: -(compactVerticalPadding - 2)
    )
    placeholderTopConstraint = placeholderLabel.centerYAnchor.constraint(
      equalTo: scrollView.topAnchor,
      constant: firstLineCenterOffset
    )
    fieldTrailingConstraintToContainer = fieldClipView.trailingAnchor.constraint(equalTo: trailingAnchor)
    fieldTrailingConstraintToCancel = fieldClipView.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8)

    NSLayoutConstraint.activate([
      fieldClipView.leadingAnchor.constraint(equalTo: leadingAnchor),
      fieldClipView.topAnchor.constraint(equalTo: topAnchor),
      fieldClipView.bottomAnchor.constraint(equalTo: bottomAnchor),
      fieldTrailingConstraintToContainer,

      cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor),
      cancelButton.centerYAnchor.constraint(equalTo: fieldClipView.centerYAnchor),
      cancelButton.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
      cancelButton.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

      fieldBackgroundView.leadingAnchor.constraint(equalTo: fieldClipView.leadingAnchor),
      fieldBackgroundView.trailingAnchor.constraint(equalTo: fieldClipView.trailingAnchor),
      fieldBackgroundView.topAnchor.constraint(equalTo: fieldClipView.topAnchor),
      fieldBackgroundView.bottomAnchor.constraint(equalTo: fieldClipView.bottomAnchor),

      fieldTintOverlayView.leadingAnchor.constraint(equalTo: fieldClipView.leadingAnchor),
      fieldTintOverlayView.trailingAnchor.constraint(equalTo: fieldClipView.trailingAnchor),
      fieldTintOverlayView.topAnchor.constraint(equalTo: fieldClipView.topAnchor),
      fieldTintOverlayView.bottomAnchor.constraint(equalTo: fieldClipView.bottomAnchor),

      searchButton.leadingAnchor.constraint(equalTo: fieldClipView.leadingAnchor, constant: compactHorizontalPadding - 4),
      searchButtonFirstLineCenterYConstraint,
      searchButton.heightAnchor.constraint(equalToConstant: accessoryButtonSize),
      leadingSearchWidthConstraint,

      trailingButtonsTrailingConstraint,
      trailingButtonsFirstLineCenterYConstraint,
      trailingButtonsBottomConstraint,

      scrollView.leadingAnchor.constraint(equalTo: searchButton.trailingAnchor, constant: 4),
      scrollView.trailingAnchor.constraint(equalTo: trailingButtonsStack.leadingAnchor, constant: -8),
      scrollView.topAnchor.constraint(equalTo: fieldClipView.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: fieldClipView.bottomAnchor),

      placeholderLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingButtonsStack.leadingAnchor, constant: -8),
      placeholderTopConstraint,
      placeholderLabel.bottomAnchor.constraint(lessThanOrEqualTo: fieldClipView.bottomAnchor),
    ])

    applyTrailingActions(trailingActions)
    applyMode(isSearchMode)
    applyShowsCancelButton(showsCancelButton)
    applyFocusEnabled(focusEnabled)
    applyEnabled(enabled)
    applyPlaceholder(placeholder)
    applyVisualStyle()
    refreshAccessoryButtons()
    refreshHeightAndNotifyIfNeeded(force: true)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "getIntrinsicSize":
        result([
          "width": Double(max(self.bounds.width, 0)),
          "height": Double(self.lastReportedHeight == 0 ? self.requestedMinHeight : self.lastReportedHeight)
        ])
      case "setText":
        if let params = call.arguments as? [String: Any], let value = params["text"] as? String {
          self.applyText(value)
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing text", details: nil)) }
      case "setPlaceholder":
        if let params = call.arguments as? [String: Any] {
          self.applyPlaceholder(params["placeholder"] as? String)
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing placeholder", details: nil)) }
      case "setEnabled":
        if let params = call.arguments as? [String: Any], let value = (params["enabled"] as? NSNumber)?.boolValue {
          self.applyEnabled(value)
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing enabled", details: nil)) }
      case "setMode":
        if let params = call.arguments as? [String: Any], let value = (params["isSearch"] as? NSNumber)?.boolValue {
          self.applyMode(value)
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing isSearch", details: nil)) }
      case "setShowsCancelButton":
        if let params = call.arguments as? [String: Any], let value = (params["showsCancelButton"] as? NSNumber)?.boolValue {
          self.applyShowsCancelButton(value)
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing showsCancelButton", details: nil)) }
      case "setMinHeight":
        if let params = call.arguments as? [String: Any],
           let value = params["minHeight"] as? NSNumber {
          let maxHeight = (params["maxHeight"] as? NSNumber).map { CGFloat(truncating: $0) }
          let maxVisibleLines = (params["maxVisibleLines"] as? NSNumber)?.intValue
          self.applyMinHeight(
            CGFloat(truncating: value),
            maxHeight: maxHeight,
            maxVisibleLines: maxVisibleLines
          )
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing minHeight", details: nil)) }
      case "setFocusEnabled":
        if let params = call.arguments as? [String: Any],
           let value = (params["focusEnabled"] as? NSNumber)?.boolValue {
          self.applyFocusEnabled(value)
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing focusEnabled", details: nil)) }
      case "setTrailingActions":
        if let params = call.arguments as? [String: Any] {
          self.applyTrailingActions(Self.parseTrailingActions(params["traillingActions"]))
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing trailing actions args", details: nil)) }
      case "setStyle":
        if let params = call.arguments as? [String: Any] {
          if let value = params["tint"] as? NSNumber {
            self.currentTint = Self.colorFromARGB(value.intValue)
          }
          if let value = params["backgroundColor"] as? NSNumber {
            self.customBackgroundColor = Self.colorFromARGB(value.intValue)
          }
          if let value = params["fieldBackgroundColor"] as? NSNumber {
            self.customFieldBackgroundColor = Self.colorFromARGB(value.intValue)
          }
          if let value = params["sendButtonBackgroundColor"] as? NSNumber {
            self.customSendButtonBackgroundColor = Self.colorFromARGB(value.intValue)
          } else if params.keys.contains("sendButtonBackgroundColor") {
            self.customSendButtonBackgroundColor = nil
          }
          self.applyVisualStyle()
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing style", details: nil)) }
      case "setVisible":
        if let params = call.arguments as? [String: Any], let visible = (params["visible"] as? NSNumber)?.boolValue {
          self.isHidden = !visible
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing visible", details: nil)) }
      case "setBrightness":
        if let params = call.arguments as? [String: Any], let isDark = (params["isDark"] as? NSNumber)?.boolValue {
          self.isDarkAppearance = isDark
          self.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
          self.applyVisualStyle()
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil)) }
      case "focus":
        if self.controlEnabled && self.focusEnabled {
          self.window?.makeFirstResponder(self.textView)
        }
        result(nil)
      case "unfocus":
        self.window?.makeFirstResponder(nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func layout() {
    super.layout()
    refreshHeightAndNotifyIfNeeded()
  }

  func textDidChange(_ notification: Notification) {
    refreshAccessoryButtons()
    let height = refreshHeightAndNotifyIfNeeded()
    channel.invokeMethod("textChanged", arguments: [
      "text": textView.string,
      "height": Double(height)
    ])
  }

  func textDidBeginEditing(_ notification: Notification) {
    guard controlEnabled && focusEnabled else {
      window?.makeFirstResponder(nil)
      return
    }
    refreshAccessoryButtons()
    channel.invokeMethod("tapped", arguments: nil)
    channel.invokeMethod("focusChanged", arguments: ["focused": true])
  }

  func textDidEndEditing(_ notification: Notification) {
    refreshAccessoryButtons()
    channel.invokeMethod("focusChanged", arguments: ["focused": false])
  }

  @objc private func onClearPressed() {
    guard controlEnabled else { return }
    applyText("")
    let height = refreshHeightAndNotifyIfNeeded(force: true)
    channel.invokeMethod("textChanged", arguments: [
      "text": "",
      "height": Double(height)
    ])
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

  @objc private func onTrailingPressed(_ sender: NSButton) {
    let index = sender.tag
    guard index >= 0,
          index < trailingButtonsEnabled.count,
          trailingButtonsEnabled[index],
          controlEnabled else {
      return
    }
    channel.invokeMethod("trailingActionPressed", arguments: ["index": index])
  }

  @objc private func onSearchPressed() {
    guard controlEnabled && isSearchMode else { return }
    channel.invokeMethod("submitted", arguments: ["text": textView.string])
  }

  @objc private func onSendPressed() {
    guard controlEnabled, !isSearchMode, !textView.string.isEmpty else { return }
    channel.invokeMethod("submitted", arguments: ["text": textView.string])
  }

  @objc private func onCancelPressed() {
    guard controlEnabled else { return }
    applyText("")
    let height = refreshHeightAndNotifyIfNeeded(force: true)
    channel.invokeMethod("textChanged", arguments: [
      "text": "",
      "height": Double(height)
    ])
    channel.invokeMethod("cancelled", arguments: nil)
    window?.makeFirstResponder(nil)
  }

  @discardableResult
  private func configureAccessoryButton(_ button: NSButton, size: CGFloat) -> (width: NSLayoutConstraint, height: NSLayoutConstraint) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isBordered = false
    button.bezelStyle = .shadowlessSquare
    button.imagePosition = .imageOnly
    button.setButtonType(.momentaryChange)
    button.focusRingType = .none
    button.wantsLayer = true
    let widthConstraint = button.widthAnchor.constraint(equalToConstant: size)
    let heightConstraint = button.heightAnchor.constraint(equalToConstant: size)
    NSLayoutConstraint.activate([
      widthConstraint,
      heightConstraint
    ])
    return (widthConstraint, heightConstraint)
  }

  private func applyText(_ text: String) {
    guard textView.string != text else { return }
    textView.string = text
    updatePlaceholderVisibility()
    refreshAccessoryButtons()
    refreshHeightAndNotifyIfNeeded(force: true)
  }

  private func applyPlaceholder(_ placeholder: String?) {
    placeholderLabel.stringValue = placeholder ?? ""
    updatePlaceholderVisibility()
  }

  private func applyEnabled(_ enabled: Bool) {
    controlEnabled = enabled
    if !enabled, window?.firstResponder === textView {
      window?.makeFirstResponder(nil)
    }
    textView.isEditable = enabled && focusEnabled
    textView.isSelectable = enabled && focusEnabled
    fieldClipView.alphaValue = enabled ? 1.0 : 0.6
    cancelButton.alphaValue = enabled ? 1.0 : 0.6
    for (index, trailingButton) in trailingButtons.enumerated() {
      trailingButton.isEnabled = enabled && trailingButtonsEnabled[index]
      trailingButton.alphaValue = trailingButton.isEnabled ? 1.0 : 0.6
    }
    clearButton.isEnabled = enabled
    cancelButton.isEnabled = enabled
    applyVisualStyle()
    refreshAccessoryButtons()
  }

  private func applyMode(_ isSearch: Bool) {
    isSearchMode = isSearch
    leadingSearchWidthConstraint.constant = isSearch ? accessoryButtonSize : 0
    searchButtonFirstLineCenterYConstraint.isActive = isSearch
    updateTrailingAccessoryAlignment()
    refreshAccessoryButtons()
    needsLayout = true
  }

  private func applyFocusEnabled(_ enabled: Bool) {
    focusEnabled = enabled
    if !enabled, window?.firstResponder === textView {
      window?.makeFirstResponder(nil)
    }
    textView.isEditable = controlEnabled && enabled
    textView.isSelectable = controlEnabled && enabled
  }

  private func applyShowsCancelButton(_ shows: Bool) {
    showsCancelButton = shows
    cancelButton.isHidden = !shows
    fieldTrailingConstraintToContainer.isActive = !shows
    fieldTrailingConstraintToCancel.isActive = shows
    needsLayout = true
  }

  private func applyMinHeight(
    _ minHeight: CGFloat,
    maxHeight: CGFloat?,
    maxVisibleLines: Int?
  ) {
    requestedMinHeight = max(28, min(minHeight, requestedMaxHeight))
    if let maxHeight {
      requestedMaxHeight = max(requestedMinHeight, min(maxHeight, 240))
    }
    if let maxVisibleLines {
      self.maxVisibleLines = max(1, maxVisibleLines)
    }
    applyTextInsets()
    refreshHeightAndNotifyIfNeeded(force: true)
  }

  private func applyVisualStyle() {
    appearance = NSAppearance(named: isDarkAppearance ? .darkAqua : .aqua)
    layer?.backgroundColor = (customBackgroundColor ?? .clear).cgColor
    fieldClipView.layer?.cornerRadius = fieldCornerRadius
    fieldClipView.layer?.borderWidth = 1
    fieldClipView.layer?.borderColor = NSColor.white.withAlphaComponent(
      isDarkAppearance ? 0.16 : 0.34
    ).cgColor

    if #available(macOS 26.0, *) {
      updateGlassBackground()
      fieldBackgroundView.isHidden = true
      glassHostingView?.isHidden = false
      if let customFieldBackgroundColor {
        fieldTintOverlayView.layer?.backgroundColor = customFieldBackgroundColor.withAlphaComponent(
          isDarkAppearance ? 0.18 : 0.22
        ).cgColor
      } else {
        fieldTintOverlayView.layer?.backgroundColor =
          NSColor.white.withAlphaComponent(isDarkAppearance ? 0.04 : 0.08).cgColor
      }
    } else if let customFieldBackgroundColor {
      fieldBackgroundView.isHidden = true
      glassHostingView?.isHidden = true
      fieldTintOverlayView.layer?.backgroundColor = customFieldBackgroundColor.cgColor
    } else {
      glassHostingView?.isHidden = true
      fieldBackgroundView.isHidden = false
      fieldBackgroundView.material = isDarkAppearance ? .menu : .hudWindow
      fieldTintOverlayView.layer?.backgroundColor =
        NSColor.windowBackgroundColor.withAlphaComponent(isDarkAppearance ? 0.14 : 0.20).cgColor
    }

    textView.textColor = .labelColor
    textView.insertionPointColor = currentTint ?? .controlAccentColor
    placeholderLabel.textColor = .placeholderTextColor
    if #available(macOS 10.14, *) {
      clearButton.contentTintColor = .secondaryLabelColor
      clearButton.layer?.backgroundColor = NSColor.clear.cgColor
      clearButton.layer?.cornerRadius = 0
      cancelButton.contentTintColor = currentTint ?? .controlAccentColor
      searchButton.contentTintColor = .secondaryLabelColor
      searchButton.layer?.backgroundColor = NSColor.clear.cgColor
      searchButton.layer?.cornerRadius = 0
      sendButton.contentTintColor = .white
      sendButton.layer?.backgroundColor =
        (customSendButtonBackgroundColor ?? currentTint ?? .controlAccentColor).cgColor
      sendButton.layer?.cornerRadius = sendButtonDiameter(for: requestedMinHeight) / 2
      for index in trailingButtons.indices {
        trailingButtons[index].contentTintColor =
          index < currentTrailingActions.count
            ? (currentTrailingActions[index].iconDataColor ?? currentTint ?? .controlAccentColor)
            : (currentTint ?? .controlAccentColor)
        trailingButtons[index].layer?.backgroundColor = NSColor.clear.cgColor
        trailingButtons[index].layer?.cornerRadius = 0
      }
    }
  }

  private func updatePlaceholderVisibility() {
    placeholderLabel.isHidden = !textView.string.isEmpty
  }

  private func updateTrailingAccessoryAlignment(
    hasText: Bool? = nil,
    currentFieldHeight: CGFloat? = nil
  ) {
    let resolvedHasText = hasText ?? !textView.string.isEmpty
    let showsSendButton = !isSearchMode && resolvedHasText
    let resolvedFieldHeight = max(
      requestedMinHeight,
      currentFieldHeight ?? (lastReportedHeight > 0 ? lastReportedHeight : requestedMinHeight)
    )
    let centersSendButton = showsSendButton && resolvedFieldHeight <= requestedMinHeight + 0.5
    let alignsToTextCenter = isSearchMode || !resolvedHasText
    trailingButtonsFirstLineCenterYConstraint.isActive = alignsToTextCenter
    trailingButtonsCenterYConstraint.isActive = centersSendButton
    trailingButtonsBottomConstraint.isActive = showsSendButton && !centersSendButton
    trailingButtonsTrailingConstraint.constant = showsSendButton ? -sendButtonOuterInset : -(compactHorizontalPadding - 2)
    trailingButtonsBottomConstraint.constant = -sendButtonOuterInset
  }

  private func sendButtonDiameter(for fieldHeight: CGFloat) -> CGFloat {
    return max(0, fieldHeight - (sendButtonOuterInset * 2) + sendButtonDiameterBoost)
  }

  private func updateSendButtonSize(for fieldHeight: CGFloat) {
    let diameter = sendButtonDiameter(for: fieldHeight)
    sendButtonWidthConstraint.constant = diameter
    sendButtonHeightConstraint.constant = diameter
    sendButton.layer?.cornerRadius = diameter / 2
  }

  private func applyTextInsets() {
    let lineHeight = ceil(
      textView.layoutManager?.defaultLineHeight(
        for: textView.font ?? NSFont.systemFont(ofSize: 16)
      ) ?? NSFont.systemFont(ofSize: 16).boundingRectForFont.height
    )
    let centeredInset = (requestedMinHeight - lineHeight) / 2.0
    let verticalInset = max(compactVerticalPadding - 2, centeredInset)
    textView.textContainerInset = NSSize(width: 0, height: verticalInset)
    let firstLineCenterOffset = verticalInset + (lineHeight / 2.0)
    searchButtonFirstLineCenterYConstraint?.constant = firstLineCenterOffset
    trailingButtonsFirstLineCenterYConstraint?.constant = firstLineCenterOffset
    placeholderTopConstraint?.constant = firstLineCenterOffset
  }

  private func currentFirstLineCenterOffset() -> CGFloat {
    let lineHeight = ceil(
      textView.layoutManager?.defaultLineHeight(
        for: textView.font ?? NSFont.systemFont(ofSize: 16)
      ) ?? NSFont.systemFont(ofSize: 16).boundingRectForFont.height
    )
    return textView.textContainerInset.height + (lineHeight / 2.0)
  }

  private func refreshAccessoryButtons() {
    let hasText = !textView.string.isEmpty
    let showsActionButtons = isSearchMode
      ? (!hasText && window?.firstResponder === textView)
      : !hasText

    updateTrailingAccessoryAlignment(hasText: hasText)

    clearButton.isHidden = !isSearchMode || !hasText
    clearButton.isEnabled = controlEnabled && isSearchMode && hasText
    clearButton.alphaValue = clearButton.isEnabled ? 1.0 : 0.6
    searchButton.isHidden = !isSearchMode
    searchButton.isEnabled = controlEnabled && isSearchMode
    searchButton.alphaValue = searchButton.isEnabled ? 1.0 : 0.6
    sendButton.isHidden = isSearchMode || !hasText
    sendButton.isEnabled = controlEnabled && !isSearchMode && hasText
    sendButton.alphaValue = sendButton.isEnabled ? 1.0 : 0.6
    for (index, trailingButton) in trailingButtons.enumerated() {
      let canShow = showsActionButtons && trailingButtonsEnabled[index]
      trailingButton.isHidden = !canShow
      trailingButton.isEnabled = controlEnabled && canShow
      trailingButton.alphaValue = trailingButton.isEnabled ? 1.0 : 0.6
    }
    updatePlaceholderVisibility()
  }

  @discardableResult
  private func refreshHeightAndNotifyIfNeeded(force: Bool = false) -> CGFloat {
    let availableWidth = max(
      scrollView.contentSize.width,
      fieldClipView.bounds.width
        - compactHorizontalPadding
        - trailingButtonsStack.bounds.width
        - compactHorizontalPadding
    )
    if let textContainer = textView.textContainer {
      let font = textView.font ?? NSFont.systemFont(ofSize: 16)
      textContainer.containerSize = NSSize(
        width: max(availableWidth, 40),
        height: CGFloat.greatestFiniteMagnitude
      )
      textView.layoutManager?.ensureLayout(for: textContainer)
      let usedRect = textView.layoutManager?.usedRect(for: textContainer) ?? .zero
      let descenderCompensation = ceil(abs(font.descender)) + 1
      let contentHeight = ceil(
        usedRect.height
          + (textView.textContainerInset.height * 2)
          + descenderCompensation
      )
      let lineHeight = ceil(
        textView.layoutManager?.defaultLineHeight(
          for: font
        ) ?? font.boundingRectForFont.height
      )
      let maxVisibleHeight = ceil(
        lineHeight * CGFloat(maxVisibleLines)
          + (textView.textContainerInset.height * 2)
          + descenderCompensation
      )
      let desiredHeight = min(
        requestedMaxHeight,
        max(requestedMinHeight, min(contentHeight, maxVisibleHeight))
      )
      updateSendButtonSize(for: requestedMinHeight)
      updateTrailingAccessoryAlignment(
        hasText: !textView.string.isEmpty,
        currentFieldHeight: desiredHeight
      )
      scrollView.hasVerticalScroller = false
      textView.frame.size = NSSize(
        width: max(availableWidth, 40),
        height: max(contentHeight, scrollView.contentSize.height)
      )

      if force || abs(lastReportedHeight - desiredHeight) > 0.5 {
        lastReportedHeight = desiredHeight
        channel.invokeMethod("heightChanged", arguments: ["height": Double(desiredHeight)])
      }
      return desiredHeight
    }

    if force || abs(lastReportedHeight - requestedMinHeight) > 0.5 {
      lastReportedHeight = requestedMinHeight
      channel.invokeMethod("heightChanged", arguments: ["height": Double(requestedMinHeight)])
    }
    return requestedMinHeight
  }

  private static func systemSymbolImage(named symbolName: String, fallback: NSImage.Name) -> NSImage? {
    if #available(macOS 11.0, *) {
      return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }
    return NSImage(named: fallback)
  }

  private func installGlassBackgroundIfNeeded() {
    guard #available(macOS 26.0, *) else { return }
    guard glassHostingView == nil else { return }

    let host = NSHostingView(
      rootView: AnyView(
        MacGlassInputBackground(
          cornerRadius: fieldCornerRadius,
          accentColor: currentTint ?? .controlAccentColor,
          isDark: isDarkAppearance,
          isEnabled: controlEnabled
        )
      )
    )
    host.translatesAutoresizingMaskIntoConstraints = false
    glassHostingView = host
    fieldClipView.addSubview(host)
    NSLayoutConstraint.activate([
      host.leadingAnchor.constraint(equalTo: fieldClipView.leadingAnchor),
      host.trailingAnchor.constraint(equalTo: fieldClipView.trailingAnchor),
      host.topAnchor.constraint(equalTo: fieldClipView.topAnchor),
      host.bottomAnchor.constraint(equalTo: fieldClipView.bottomAnchor),
    ])
  }

  private func updateGlassBackground() {
    guard #available(macOS 26.0, *) else { return }
    installGlassBackgroundIfNeeded()
    glassHostingView?.rootView = AnyView(
      MacGlassInputBackground(
        cornerRadius: fieldCornerRadius,
        accentColor: currentTint ?? .controlAccentColor,
        isDark: isDarkAppearance,
        isEnabled: controlEnabled
      )
    )
    glassHostingView?.isHidden = false
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
        continue
      }
      let _ = currentTrailingActions[index].iconDataMatchTextDirection
      trailingButtons[index].image = image
      trailingButtons[index].isHidden = false
      trailingButtonsEnabled[index] = true
      if #available(macOS 10.14, *) {
        trailingButtons[index].contentTintColor =
          currentTrailingActions[index].iconDataColor ?? currentTint ?? .controlAccentColor
      }
    }
    refreshAccessoryButtons()
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
