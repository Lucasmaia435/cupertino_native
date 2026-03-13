import FlutterMacOS
import Cocoa
import CoreText
import SwiftUI

@available(macOS 26.0, *)
private struct MacGlassInputBackground: View {
  let cornerRadius: CGFloat
  let isEnabled: Bool

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    shape
      .fill(Color.clear)
      .glassEffect(.regular, in: shape)
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
  private let fieldClickGestureRecognizer: NSClickGestureRecognizer
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
  private var searchButtonHeightConstraint: NSLayoutConstraint!
  private var searchButtonCenterYConstraint: NSLayoutConstraint!
  private var scrollViewTopConstraint: NSLayoutConstraint!
  private var trailingButtonsFirstLineCenterYConstraint: NSLayoutConstraint!
  private var trailingButtonsCenterYConstraint: NSLayoutConstraint!
  private var trailingButtonsTrailingConstraint: NSLayoutConstraint!
  private var trailingButtonsBottomConstraint: NSLayoutConstraint!
  private var clearButtonWidthConstraint: NSLayoutConstraint!
  private var clearButtonHeightConstraint: NSLayoutConstraint!
  private var trailingButtonWidthConstraints: [NSLayoutConstraint] = []
  private var trailingButtonHeightConstraints: [NSLayoutConstraint] = []
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
  private var customFieldOverlayColor: NSColor? = nil
  private var customFieldBorderColor: NSColor? = nil
  private var customSendButtonBackgroundColor: NSColor? = nil
  private var customSendButtonForegroundColor: NSColor? = nil
  private var customPlaceholderColor: NSColor? = nil
  private var customLeadingAccessoryColor: NSColor? = nil
  private var customClearButtonColor: NSColor? = nil
  private var customCancelButtonColor: NSColor? = nil
  private var controlEnabled = true
  private var focusEnabled = true
  private var showsLeadingAccessory = false
  private var leadingAccessoryTriggersSubmit = false
  private var clearButtonVisibilityRule = "whileNotEmpty"
  private var sendButtonVisibilityRule = "never"
  private var trailingActionsVisibilityRule = "whileEmpty"
  private var trailingAccessoryOrder: [String] = ["clear", "actions", "send"]
  private var showsCancelButton = false
  private var cancelButtonText = "Cancel"
  private var requestedMinHeight: CGFloat = 44
  private var requestedMaxHeight: CGFloat = 240
  private var maxVisibleLines = 1
  private var lastReportedHeight: CGFloat = 0
  private var isDarkAppearance = false
  private var isApplyingProgrammaticText = false
  private var isApplyingProgrammaticSelection = false
  private var hasInteractedWithField = false
  private var leadingAccessoryIcon: TrailingAction?
  private var clearButtonIcon: TrailingAction?
  private var sendButtonIcon: TrailingAction?
  private var disabledOpacity: CGFloat = 0.6

  private var compactHorizontalPadding: CGFloat = 16
  private var compactVerticalPadding: CGFloat = 8
  private var textOpticalVerticalOffset: CGFloat = 1.5
  private var fieldCornerRadius: CGFloat = 28
  private var accessoryButtonSize: CGFloat = 32
  private var sendButtonOuterInset: CGFloat = 8
  private let defaultSendButtonIconSize: CGFloat = 16
  private var sendButtonDiameterBoost: CGFloat = 8
  private var trailingSpacing: CGFloat = 6
  private var leadingReservedWidth: CGFloat = 0
  private var trailingReservedWidth: CGFloat = 0

  private var effectiveFieldBackgroundColor: NSColor? {
    customFieldBackgroundColor ?? customBackgroundColor
  }

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    let clearButton = NSButton(title: "", target: nil, action: nil)
    let firstTrailingButton = NSButton(title: "", target: nil, action: nil)
    let secondTrailingButton = NSButton(title: "", target: nil, action: nil)
    let sendButton = NSButton(title: "", target: nil, action: nil)
    let searchButton = NSButton(title: "", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let fieldClickGestureRecognizer = NSClickGestureRecognizer(target: nil, action: nil)
    self.channel = FlutterMethodChannel(name: "CupertinoNativeSearchBar_\(viewId)", binaryMessenger: messenger)
    self.fieldClipView = NSView(frame: .zero)
    self.fieldClickGestureRecognizer = fieldClickGestureRecognizer
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
    var showsLeadingAccessory: Bool = false
    var leadingAccessoryTriggersSubmit: Bool = false
    var clearButtonVisibilityRule = "whileNotEmpty"
    var sendButtonVisibilityRule = "never"
    var trailingActionsVisibilityRule = "whileEmpty"
    var trailingAccessoryOrder = ["clear", "actions", "send"]
    var cancelButtonText = "Cancel"
    var minHeight: CGFloat = 44
    var maxHeight: CGFloat = 240
    var maxVisibleLines: Int = 1
    var focusEnabled: Bool = true
    var isDark: Bool = false
    var tint: NSColor? = nil
    var bg: NSColor? = nil
    var fieldBg: NSColor? = nil
    var fieldOverlayColor: NSColor? = nil
    var fieldBorderColor: NSColor? = nil
    var sendButtonBg: NSColor? = nil
    var sendButtonFg: NSColor? = nil
    var placeholderColor: NSColor? = nil
    var leadingAccessoryColor: NSColor? = nil
    var clearButtonColor: NSColor? = nil
    var cancelButtonColor: NSColor? = nil
    var disabledOpacity: CGFloat = 0.6
    var borderRadius: CGFloat = 28
    var accessoryButtonSize: CGFloat = 32
    var fieldHorizontalPadding: CGFloat = 16
    var fieldVerticalPadding: CGFloat = 8
    var textOpticalVerticalOffset: CGFloat = 1.5
    var sendButtonOuterInset: CGFloat = 8
    var sendButtonDiameterBoost: CGFloat = 8
    var trailingSpacing: CGFloat = 6
    var leadingReservedWidth: CGFloat = 0
    var trailingReservedWidth: CGFloat = 0
    var leadingIcon: TrailingAction? = nil
    var clearIcon: TrailingAction? = nil
    var sendIcon: TrailingAction? = nil
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
      if let behavior = dict["behavior"] as? [String: Any] {
        if let value = (behavior["showsLeadingAccessory"] as? NSNumber)?.boolValue {
          showsLeadingAccessory = value
        }
        if let value = (behavior["leadingAccessoryTriggersSubmit"] as? NSNumber)?.boolValue {
          leadingAccessoryTriggersSubmit = value
        }
        if let value = (behavior["showsCancelButton"] as? NSNumber)?.boolValue {
          showsCancelButton = value
        }
        if let value = behavior["clearButtonVisibility"] as? String {
          clearButtonVisibilityRule = value
        }
        if let value = behavior["sendButtonVisibility"] as? String {
          sendButtonVisibilityRule = value
        }
        if let value = behavior["trailingActionsVisibility"] as? String {
          trailingActionsVisibilityRule = value
        }
        if let value = behavior["trailingAccessoryOrder"] as? [String], !value.isEmpty {
          trailingAccessoryOrder = value
        }
        if let value = behavior["maxVisibleLines"] as? NSNumber {
          maxVisibleLines = value.intValue
        }
      }
      if let layout = dict["layout"] as? [String: Any] {
        if let value = layout["height"] as? NSNumber { minHeight = CGFloat(truncating: value) }
        if let value = layout["maxHeight"] as? NSNumber { maxHeight = CGFloat(truncating: value) }
        if let value = layout["borderRadius"] as? NSNumber { borderRadius = CGFloat(truncating: value) }
        if let value = layout["accessoryButtonSize"] as? NSNumber { accessoryButtonSize = CGFloat(truncating: value) }
        if let value = layout["fieldHorizontalPadding"] as? NSNumber { fieldHorizontalPadding = CGFloat(truncating: value) }
        if let value = layout["fieldVerticalPadding"] as? NSNumber { fieldVerticalPadding = CGFloat(truncating: value) }
        if let value = layout["textOpticalVerticalOffset"] as? NSNumber { textOpticalVerticalOffset = CGFloat(truncating: value) }
        if let value = layout["sendButtonOuterInset"] as? NSNumber { sendButtonOuterInset = CGFloat(truncating: value) }
        if let value = layout["sendButtonSizeBoost"] as? NSNumber { sendButtonDiameterBoost = CGFloat(truncating: value) }
        if let value = layout["trailingSpacing"] as? NSNumber { trailingSpacing = CGFloat(truncating: value) }
        if let value = layout["leadingReservedWidth"] as? NSNumber { leadingReservedWidth = CGFloat(truncating: value) }
        if let value = layout["trailingReservedWidth"] as? NSNumber { trailingReservedWidth = CGFloat(truncating: value) }
      }
      if let strings = dict["strings"] as? [String: Any] {
        if let value = strings["cancelButtonText"] as? String {
          cancelButtonText = value
        }
      }
      if let style = dict["style"] as? [String: Any] {
        if let value = style["tint"] as? NSNumber { tint = Self.colorFromARGB(value.intValue) }
        if let value = style["backgroundColor"] as? NSNumber { bg = Self.colorFromARGB(value.intValue) }
        if let value = style["fieldBackgroundColor"] as? NSNumber { fieldBg = Self.colorFromARGB(value.intValue) }
        if let value = style["fieldOverlayColor"] as? NSNumber { fieldOverlayColor = Self.colorFromARGB(value.intValue) }
        if let value = style["fieldBorderColor"] as? NSNumber { fieldBorderColor = Self.colorFromARGB(value.intValue) }
        if let value = style["sendButtonBackgroundColor"] as? NSNumber {
          sendButtonBg = Self.colorFromARGB(value.intValue)
        }
        if let value = style["sendButtonForegroundColor"] as? NSNumber {
          sendButtonFg = Self.colorFromARGB(value.intValue)
        }
        if let value = style["placeholderColor"] as? NSNumber {
          placeholderColor = Self.colorFromARGB(value.intValue)
        }
        if let value = style["leadingAccessoryColor"] as? NSNumber {
          leadingAccessoryColor = Self.colorFromARGB(value.intValue)
        }
        if let value = style["clearButtonColor"] as? NSNumber {
          clearButtonColor = Self.colorFromARGB(value.intValue)
        }
        if let value = style["cancelButtonColor"] as? NSNumber {
          cancelButtonColor = Self.colorFromARGB(value.intValue)
        }
        if let value = style["disabledOpacity"] as? NSNumber {
          disabledOpacity = CGFloat(truncating: value)
        }
      }
      if let icons = dict["icons"] as? [String: Any] {
        leadingIcon = Self.parseAccessoryIcon(icons["leading"])
        clearIcon = Self.parseAccessoryIcon(icons["clear"])
        sendIcon = Self.parseAccessoryIcon(icons["send"])
      }
      trailingActions = Self.parseTrailingActions(dict["traillingActions"])
      if dict["behavior"] == nil {
        showsLeadingAccessory = isSearchMode
        leadingAccessoryTriggersSubmit = isSearchMode
        clearButtonVisibilityRule = isSearchMode ? "whileNotEmpty" : "never"
        sendButtonVisibilityRule = isSearchMode ? "never" : "whileNotEmpty"
        trailingActionsVisibilityRule = isSearchMode
          ? "whileEmptyBeforeInteractionOrFocused"
          : "whileEmpty"
        trailingAccessoryOrder = isSearchMode ? ["clear", "actions"] : ["send", "actions"]
      }
    }
    currentTint = tint

    super.init(frame: .zero)

    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    isDarkAppearance = isDark
    customBackgroundColor = bg
    customFieldBackgroundColor = fieldBg
    customFieldOverlayColor = fieldOverlayColor
    customFieldBorderColor = fieldBorderColor
    customSendButtonBackgroundColor = sendButtonBg
    customSendButtonForegroundColor = sendButtonFg
    customPlaceholderColor = placeholderColor
    customLeadingAccessoryColor = leadingAccessoryColor
    customClearButtonColor = clearButtonColor
    customCancelButtonColor = cancelButtonColor
    controlEnabled = enabled
    self.focusEnabled = focusEnabled
    self.showsLeadingAccessory = showsLeadingAccessory
    self.leadingAccessoryTriggersSubmit = leadingAccessoryTriggersSubmit
    self.clearButtonVisibilityRule = clearButtonVisibilityRule
    self.sendButtonVisibilityRule = sendButtonVisibilityRule
    self.trailingActionsVisibilityRule = trailingActionsVisibilityRule
    self.trailingAccessoryOrder = trailingAccessoryOrder
    self.showsCancelButton = showsCancelButton
    self.cancelButtonText = cancelButtonText
    requestedMinHeight = max(28, min(minHeight, maxHeight))
    requestedMaxHeight = max(requestedMinHeight, maxHeight)
    self.maxVisibleLines = max(1, maxVisibleLines)
    self.leadingAccessoryIcon = leadingIcon
    self.clearButtonIcon = clearIcon
    self.sendButtonIcon = sendIcon
    self.disabledOpacity = max(0, min(disabledOpacity, 1))
    self.fieldCornerRadius = borderRadius
    self.accessoryButtonSize = accessoryButtonSize
    self.compactHorizontalPadding = fieldHorizontalPadding
    self.compactVerticalPadding = fieldVerticalPadding
    self.textOpticalVerticalOffset = textOpticalVerticalOffset
    self.sendButtonOuterInset = sendButtonOuterInset
    self.sendButtonDiameterBoost = sendButtonDiameterBoost
    self.trailingSpacing = trailingSpacing
    self.leadingReservedWidth = max(0, leadingReservedWidth)
    self.trailingReservedWidth = max(0, trailingReservedWidth)

    fieldClipView.translatesAutoresizingMaskIntoConstraints = false
    fieldClipView.wantsLayer = true
    fieldClipView.layer?.cornerRadius = fieldCornerRadius
    fieldClipView.layer?.masksToBounds = true

    fieldBackgroundView.translatesAutoresizingMaskIntoConstraints = false
    fieldBackgroundView.blendingMode = .withinWindow
    fieldBackgroundView.state = .active

    fieldTintOverlayView.translatesAutoresizingMaskIntoConstraints = false
    fieldTintOverlayView.wantsLayer = true

    fieldClickGestureRecognizer.target = self
    fieldClickGestureRecognizer.action = #selector(onFieldClicked(_:))

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
    trailingButtonsStack.spacing = trailingSpacing

    let clearButtonSizeConstraints = configureAccessoryButton(clearButton, size: accessoryButtonSize)
    clearButtonWidthConstraint = clearButtonSizeConstraints.width
    clearButtonHeightConstraint = clearButtonSizeConstraints.height
    clearButton.target = self
    clearButton.action = #selector(onClearPressed)

    for (index, trailingButton) in trailingButtons.enumerated() {
      let sizeConstraints = configureAccessoryButton(trailingButton, size: accessoryButtonSize)
      trailingButtonWidthConstraints.append(sizeConstraints.width)
      trailingButtonHeightConstraints.append(sizeConstraints.height)
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
         NSImage.SymbolConfiguration(pointSize: defaultSendButtonIconSize, weight: .medium)
       ) {
      sendButton.image = configuredImage
    }

    let searchButtonSizeConstraints = configureAccessoryButton(searchButton, size: accessoryButtonSize)
    leadingSearchWidthConstraint = searchButtonSizeConstraints.width
    searchButtonHeightConstraint = searchButtonSizeConstraints.height
    searchButton.target = self
    searchButton.action = #selector(onSearchPressed)

    cancelButton.translatesAutoresizingMaskIntoConstraints = false
    cancelButton.isBordered = false
    cancelButton.target = self
    cancelButton.action = #selector(onCancelPressed)
    cancelButton.focusRingType = .none
    cancelButton.font = NSFont.systemFont(ofSize: 14)
    cancelButton.setButtonType(.momentaryPushIn)
    cancelButton.title = cancelButtonText

    addSubview(fieldClipView)
    addSubview(cancelButton)
    fieldClipView.addGestureRecognizer(fieldClickGestureRecognizer)
    fieldClipView.addSubview(fieldBackgroundView)
    installGlassBackgroundIfNeeded()
    fieldClipView.addSubview(fieldTintOverlayView)
    fieldClipView.addSubview(searchButton)
    fieldClipView.addSubview(scrollView)
    fieldClipView.addSubview(placeholderLabel)
    fieldClipView.addSubview(trailingButtonsStack)

    let firstLineCenterOffset = currentFirstLineCenterOffset()
    searchButtonCenterYConstraint = searchButton.centerYAnchor.constraint(equalTo: fieldClipView.centerYAnchor)
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
    scrollViewTopConstraint = scrollView.topAnchor.constraint(
      equalTo: fieldClipView.topAnchor,
      constant: textOpticalVerticalOffset
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
	      searchButtonCenterYConstraint,
	      searchButtonHeightConstraint,
	      leadingSearchWidthConstraint,

      trailingButtonsTrailingConstraint,
      trailingButtonsFirstLineCenterYConstraint,
      trailingButtonsBottomConstraint,

      scrollView.leadingAnchor.constraint(equalTo: searchButton.trailingAnchor, constant: 4),
      scrollView.trailingAnchor.constraint(equalTo: trailingButtonsStack.leadingAnchor, constant: -8),
      scrollViewTopConstraint,
      scrollView.bottomAnchor.constraint(equalTo: fieldClipView.bottomAnchor),

      placeholderLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingButtonsStack.leadingAnchor, constant: -8),
      placeholderTopConstraint,
      placeholderLabel.bottomAnchor.constraint(lessThanOrEqualTo: fieldClipView.bottomAnchor),
    ])

	    applyTrailingActions(trailingActions)
	    applyAccessoryIcons()
	    applyBehaviorConfiguration([
	      "showsLeadingAccessory": self.showsLeadingAccessory,
	      "leadingAccessoryTriggersSubmit": self.leadingAccessoryTriggersSubmit,
	      "showsCancelButton": self.showsCancelButton,
	      "clearButtonVisibility": self.clearButtonVisibilityRule,
	      "sendButtonVisibility": self.sendButtonVisibilityRule,
	      "trailingActionsVisibility": self.trailingActionsVisibilityRule,
	      "trailingAccessoryOrder": self.trailingAccessoryOrder,
	      "maxVisibleLines": self.maxVisibleLines
	    ])
	    applyFocusEnabled(focusEnabled)
	    applyEnabled(enabled)
	    applyPlaceholder(placeholder)
	    applyStringsConfiguration(["cancelButtonText": cancelButtonText])
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
      case "setSelection":
        if let params = call.arguments as? [String: Any],
           let baseOffset = (params["baseOffset"] as? NSNumber)?.intValue,
           let extentOffset = (params["extentOffset"] as? NSNumber)?.intValue {
          self.applySelection(baseOffset: baseOffset, extentOffset: extentOffset)
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing selection", details: nil)) }
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
	      case "setBehavior":
	        if let params = call.arguments as? [String: Any], let behavior = params["behavior"] as? [String: Any] {
	          self.applyBehaviorConfiguration(behavior)
	          result(nil)
	        } else { result(FlutterError(code: "bad_args", message: "Missing behavior", details: nil)) }
	      case "setShowsCancelButton":
	        if let params = call.arguments as? [String: Any], let value = (params["showsCancelButton"] as? NSNumber)?.boolValue {
	          self.applyShowsCancelButton(value)
	          result(nil)
	        } else { result(FlutterError(code: "bad_args", message: "Missing showsCancelButton", details: nil)) }
	      case "setLayout":
	        if let params = call.arguments as? [String: Any], let layout = params["layout"] as? [String: Any] {
	          self.applyLayoutConfiguration(layout)
	          result(nil)
	        } else { result(FlutterError(code: "bad_args", message: "Missing layout", details: nil)) }
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
	      case "setStrings":
	        if let params = call.arguments as? [String: Any], let strings = params["strings"] as? [String: Any] {
	          self.applyStringsConfiguration(strings)
	          result(nil)
	        } else { result(FlutterError(code: "bad_args", message: "Missing strings", details: nil)) }
	      case "setIcons":
	        if let params = call.arguments as? [String: Any], let icons = params["icons"] as? [String: Any] {
	          self.applyIconsConfiguration(icons)
	          result(nil)
	        } else { result(FlutterError(code: "bad_args", message: "Missing icons", details: nil)) }
	      case "setStyle":
	        if let params = call.arguments as? [String: Any] {
	          if let value = params["tint"] as? NSNumber {
	            self.currentTint = Self.colorFromARGB(value.intValue)
	          } else if params.keys.contains("tint") {
	            self.currentTint = nil
	          }
	          if let value = params["backgroundColor"] as? NSNumber {
	            self.customBackgroundColor = Self.colorFromARGB(value.intValue)
	          } else if params.keys.contains("backgroundColor") {
	            self.customBackgroundColor = nil
	          }
	          if let value = params["fieldBackgroundColor"] as? NSNumber {
	            self.customFieldBackgroundColor = Self.colorFromARGB(value.intValue)
	          } else if params.keys.contains("fieldBackgroundColor") {
	            self.customFieldBackgroundColor = nil
	          }
	          if let value = params["fieldOverlayColor"] as? NSNumber {
	            self.customFieldOverlayColor = Self.colorFromARGB(value.intValue)
	          } else if params.keys.contains("fieldOverlayColor") {
	            self.customFieldOverlayColor = nil
	          }
	          if let value = params["fieldBorderColor"] as? NSNumber {
	            self.customFieldBorderColor = Self.colorFromARGB(value.intValue)
	          } else if params.keys.contains("fieldBorderColor") {
	            self.customFieldBorderColor = nil
	          }
	          if let value = params["sendButtonBackgroundColor"] as? NSNumber {
	            self.customSendButtonBackgroundColor = Self.colorFromARGB(value.intValue)
	          } else if params.keys.contains("sendButtonBackgroundColor") {
	            self.customSendButtonBackgroundColor = nil
	          }
	          if let value = params["sendButtonForegroundColor"] as? NSNumber {
	            self.customSendButtonForegroundColor = Self.colorFromARGB(value.intValue)
	          } else if params.keys.contains("sendButtonForegroundColor") {
	            self.customSendButtonForegroundColor = nil
	          }
	          if let value = params["placeholderColor"] as? NSNumber {
	            self.customPlaceholderColor = Self.colorFromARGB(value.intValue)
	          } else if params.keys.contains("placeholderColor") {
	            self.customPlaceholderColor = nil
	          }
	          if let value = params["leadingAccessoryColor"] as? NSNumber {
	            self.customLeadingAccessoryColor = Self.colorFromARGB(value.intValue)
	          } else if params.keys.contains("leadingAccessoryColor") {
	            self.customLeadingAccessoryColor = nil
	          }
	          if let value = params["clearButtonColor"] as? NSNumber {
	            self.customClearButtonColor = Self.colorFromARGB(value.intValue)
	          } else if params.keys.contains("clearButtonColor") {
	            self.customClearButtonColor = nil
	          }
	          if let value = params["cancelButtonColor"] as? NSNumber {
	            self.customCancelButtonColor = Self.colorFromARGB(value.intValue)
	          } else if params.keys.contains("cancelButtonColor") {
	            self.customCancelButtonColor = nil
	          }
	          if let value = params["disabledOpacity"] as? NSNumber {
	            self.disabledOpacity = max(0, min(CGFloat(truncating: value), 1))
	          }
	          self.applyVisualStyle()
	          self.refreshAccessoryButtons()
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
    guard !isApplyingProgrammaticText else { return }
    refreshAccessoryButtons()
    let height = refreshHeightAndNotifyIfNeeded()
    channel.invokeMethod(
      "textChanged",
      arguments: textChangedArguments(text: textView.string, height: height)
    )
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    guard !isApplyingProgrammaticText && !isApplyingProgrammaticSelection else {
      return
    }
    channel.invokeMethod("selectionChanged", arguments: currentSelectionArguments())
  }

  func textDidBeginEditing(_ notification: Notification) {
    guard controlEnabled && focusEnabled else {
      window?.makeFirstResponder(nil)
      return
    }
    hasInteractedWithField = true
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
    channel.invokeMethod(
      "textChanged",
      arguments: textChangedArguments(text: "", height: height)
    )
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

  private static func parseAccessoryIcon(_ raw: Any?) -> TrailingAction? {
    guard let dict = raw as? [String: Any],
          let codePoint = (dict["iconDataCodePoint"] as? NSNumber)?.intValue else {
      return nil
    }
    return TrailingAction(
      iconDataCodePoint: codePoint,
      iconDataFontFamily: dict["iconDataFontFamily"] as? String,
      iconDataFontPackage: dict["iconDataFontPackage"] as? String,
      iconDataMatchTextDirection:
        (dict["iconDataMatchTextDirection"] as? NSNumber)?.boolValue ?? false,
      iconDataColor: Self.parseOptionalColor(dict["iconDataColor"]),
      iconDataSize: Self.parseOptionalCGFloat(dict["iconDataSize"]) ?? 16,
      iconDataFill: Self.parseOptionalCGFloat(dict["iconDataFill"]),
      iconDataWeight: Self.parseOptionalCGFloat(dict["iconDataWeight"]),
      iconDataGrade: Self.parseOptionalCGFloat(dict["iconDataGrade"]),
      iconDataOpticalSize: Self.parseOptionalCGFloat(dict["iconDataOpticalSize"])
    )
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

  @objc private func onFieldClicked(_ recognizer: NSClickGestureRecognizer) {
    guard recognizer.state == .ended, controlEnabled, focusEnabled else {
      return
    }
    if window?.firstResponder === textView {
      return
    }

    let location = recognizer.location(in: fieldClipView)
    if shouldIgnoreFieldClick(on: fieldClipView.hitTest(location)) {
      return
    }

    window?.makeFirstResponder(textView)
  }

  @objc private func onSearchPressed() {
    guard controlEnabled && showsLeadingAccessory && leadingAccessoryTriggersSubmit else { return }
    channel.invokeMethod("submitted", arguments: ["text": textView.string])
  }

  @objc private func onSendPressed() {
    guard controlEnabled, !textView.string.isEmpty else { return }
    channel.invokeMethod("submitted", arguments: ["text": textView.string])
  }

  @objc private func onCancelPressed() {
    guard controlEnabled else { return }
    applyText("")
    let height = refreshHeightAndNotifyIfNeeded(force: true)
    channel.invokeMethod(
      "textChanged",
      arguments: textChangedArguments(text: "", height: height)
    )
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
    isApplyingProgrammaticText = true
    defer { isApplyingProgrammaticText = false }
    textView.string = text
    updatePlaceholderVisibility()
    refreshAccessoryButtons()
    refreshHeightAndNotifyIfNeeded(force: true)
  }

  private func applySelection(baseOffset: Int, extentOffset: Int) {
    let range = clampedSelectionRange(baseOffset: baseOffset, extentOffset: extentOffset)
    guard textView.selectedRange() != range else { return }
    isApplyingProgrammaticSelection = true
    defer { isApplyingProgrammaticSelection = false }
    textView.setSelectedRange(range)
  }

  private func clampedSelectionRange(baseOffset: Int, extentOffset: Int) -> NSRange {
    let textLength = textView.string.utf16.count
    let clampedBase = max(0, min(baseOffset, textLength))
    let clampedExtent = max(0, min(extentOffset, textLength))
    let location = min(clampedBase, clampedExtent)
    let length = abs(clampedExtent - clampedBase)
    return NSRange(location: location, length: length)
  }

  private func currentSelectionArguments() -> [String: Any] {
    let selectedRange = textView.selectedRange()
    let baseOffset = selectedRange.location == NSNotFound ? 0 : selectedRange.location
    return [
      "baseOffset": baseOffset,
      "extentOffset": baseOffset + selectedRange.length
    ]
  }

  private func textChangedArguments(text: String, height: CGFloat) -> [String: Any] {
    var arguments = currentSelectionArguments()
    arguments["text"] = text
    arguments["height"] = Double(height)
    return arguments
  }

  private func shouldIgnoreFieldClick(on hitView: NSView?) -> Bool {
    var current = hitView
    while let view = current {
      if view is NSControl {
        return true
      }
      current = view.superview
    }
    return false
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
    fieldClipView.alphaValue = enabled ? 1.0 : disabledOpacity
    cancelButton.alphaValue = enabled ? 1.0 : disabledOpacity
    for (index, trailingButton) in trailingButtons.enumerated() {
      trailingButton.isEnabled = enabled && trailingButtonsEnabled[index]
      trailingButton.alphaValue = trailingButton.isEnabled ? 1.0 : disabledOpacity
    }
    clearButton.isEnabled = enabled
    cancelButton.isEnabled = enabled
    applyVisualStyle()
    refreshAccessoryButtons()
  }

  private func applyBehaviorConfiguration(_ params: [String: Any]) {
    let previousTrailingRule = trailingActionsVisibilityRule
    if let value = (params["showsLeadingAccessory"] as? NSNumber)?.boolValue {
      showsLeadingAccessory = value
    }
    if let value = (params["leadingAccessoryTriggersSubmit"] as? NSNumber)?.boolValue {
      leadingAccessoryTriggersSubmit = value
    }
    if let value = (params["showsCancelButton"] as? NSNumber)?.boolValue {
      showsCancelButton = value
    }
    if let value = params["clearButtonVisibility"] as? String {
      clearButtonVisibilityRule = value
    }
    if let value = params["sendButtonVisibility"] as? String {
      sendButtonVisibilityRule = value
    }
    if let value = params["trailingActionsVisibility"] as? String {
      trailingActionsVisibilityRule = value
    }
    if let value = params["trailingAccessoryOrder"] as? [String], !value.isEmpty {
      trailingAccessoryOrder = value
    }
    if let value = params["maxVisibleLines"] as? NSNumber {
      maxVisibleLines = max(1, value.intValue)
    }
    if trailingActionsVisibilityRule == "whileEmptyBeforeInteractionOrFocused" &&
        previousTrailingRule != trailingActionsVisibilityRule {
      hasInteractedWithField = false
    }
    leadingSearchWidthConstraint.constant = currentLeadingAccessoryWidth()
    applyShowsCancelButton(showsCancelButton)
    updateTrailingAccessoryAlignment()
    refreshAccessoryButtons()
    refreshHeightAndNotifyIfNeeded(force: true)
    needsLayout = true
  }

  private func applyMode(_ isSearch: Bool) {
    applyBehaviorConfiguration([
      "showsLeadingAccessory": isSearch,
      "leadingAccessoryTriggersSubmit": isSearch,
      "clearButtonVisibility": isSearch ? "whileNotEmpty" : "never",
      "sendButtonVisibility": isSearch ? "never" : "whileNotEmpty",
      "trailingActionsVisibility": isSearch ? "whileEmptyBeforeInteractionOrFocused" : "whileEmpty",
      "trailingAccessoryOrder": isSearch ? ["clear", "actions"] : ["send", "actions"],
      "maxVisibleLines": isSearch ? 1 : maxVisibleLines
    ])
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
    cancelButton.title = cancelButtonText
    needsLayout = true
  }

  private func applyLayoutConfiguration(_ params: [String: Any]) {
    var minHeight = requestedMinHeight
    var maxHeight = requestedMaxHeight
    if let value = params["height"] as? NSNumber {
      minHeight = CGFloat(truncating: value)
    } else if let value = params["minHeight"] as? NSNumber {
      minHeight = CGFloat(truncating: value)
    }
    if let value = params["maxHeight"] as? NSNumber {
      maxHeight = CGFloat(truncating: value)
    }
    if let value = params["borderRadius"] as? NSNumber {
      fieldCornerRadius = CGFloat(truncating: value)
    }
    if let value = params["accessoryButtonSize"] as? NSNumber {
      accessoryButtonSize = CGFloat(truncating: value)
    }
    if let value = params["fieldHorizontalPadding"] as? NSNumber {
      compactHorizontalPadding = CGFloat(truncating: value)
    }
    if let value = params["fieldVerticalPadding"] as? NSNumber {
      compactVerticalPadding = CGFloat(truncating: value)
    }
    if let value = params["textOpticalVerticalOffset"] as? NSNumber {
      textOpticalVerticalOffset = CGFloat(truncating: value)
    }
    if let value = params["sendButtonOuterInset"] as? NSNumber {
      sendButtonOuterInset = CGFloat(truncating: value)
    }
    if let value = params["sendButtonSizeBoost"] as? NSNumber {
      sendButtonDiameterBoost = CGFloat(truncating: value)
    }
    if let value = params["trailingSpacing"] as? NSNumber {
      trailingSpacing = CGFloat(truncating: value)
    }
    if let value = params["leadingReservedWidth"] as? NSNumber {
      leadingReservedWidth = max(0, CGFloat(truncating: value))
    }
    if let value = params["trailingReservedWidth"] as? NSNumber {
      trailingReservedWidth = max(0, CGFloat(truncating: value))
    }
    requestedMaxHeight = max(maxHeight, minHeight)
    requestedMinHeight = max(28, min(minHeight, requestedMaxHeight))
    updateAccessoryButtonConstraints()
    trailingButtonsStack.spacing = trailingSpacing
    applyTextInsets()
    applyAccessoryIcons()
    applyVisualStyle()
    refreshAccessoryButtons()
    refreshHeightAndNotifyIfNeeded(force: true)
  }

  private func applyMinHeight(
    _ minHeight: CGFloat,
    maxHeight: CGFloat?,
    maxVisibleLines: Int?
  ) {
    var params: [String: Any] = ["minHeight": minHeight]
    if let maxHeight { params["maxHeight"] = maxHeight }
    applyLayoutConfiguration(params)
    if let maxVisibleLines {
      self.maxVisibleLines = max(1, maxVisibleLines)
    }
    refreshHeightAndNotifyIfNeeded(force: true)
  }

  private func applyStringsConfiguration(_ params: [String: Any]) {
    if let value = params["cancelButtonText"] as? String {
      cancelButtonText = value
    }
    cancelButton.title = cancelButtonText
    applyVisualStyle()
  }

  private func applyIconsConfiguration(_ params: [String: Any]) {
    if params.keys.contains("leading") {
      leadingAccessoryIcon = Self.parseAccessoryIcon(params["leading"])
    }
    if params.keys.contains("clear") {
      clearButtonIcon = Self.parseAccessoryIcon(params["clear"])
    }
    if params.keys.contains("send") {
      sendButtonIcon = Self.parseAccessoryIcon(params["send"])
    }
    applyAccessoryIcons()
    applyVisualStyle()
    refreshAccessoryButtons()
  }

  private func applyVisualStyle() {
    let fieldBaseColor = effectiveFieldBackgroundColor

    appearance = NSAppearance(named: isDarkAppearance ? .darkAqua : .aqua)
    layer?.backgroundColor = NSColor.clear.cgColor
    fieldClipView.layer?.cornerRadius = fieldCornerRadius
    fieldClipView.layer?.backgroundColor = (fieldBaseColor ?? .clear).cgColor
    fieldClipView.alphaValue = controlEnabled ? 1.0 : disabledOpacity
    cancelButton.alphaValue = controlEnabled ? 1.0 : disabledOpacity
    fieldClipView.layer?.borderWidth = 1
    fieldClipView.layer?.borderColor = (customFieldBorderColor ?? NSColor.white.withAlphaComponent(
      isDarkAppearance ? 0.16 : 0.34
    )).cgColor

    if #available(macOS 26.0, *) {
      if fieldBaseColor != nil {
        fieldBackgroundView.isHidden = true
        glassHostingView?.isHidden = true
        fieldTintOverlayView.layer?.backgroundColor = (customFieldOverlayColor ?? .clear).cgColor
      } else {
        updateGlassBackground()
        fieldBackgroundView.isHidden = true
        glassHostingView?.isHidden = false
        fieldTintOverlayView.layer?.backgroundColor = (customFieldOverlayColor ?? .clear).cgColor
      }
    } else if fieldBaseColor != nil {
      fieldBackgroundView.isHidden = true
      glassHostingView?.isHidden = true
      fieldTintOverlayView.layer?.backgroundColor = (customFieldOverlayColor ?? .clear).cgColor
    } else {
      glassHostingView?.isHidden = true
      fieldBackgroundView.isHidden = false
      fieldBackgroundView.material = isDarkAppearance ? .menu : .hudWindow
      fieldTintOverlayView.layer?.backgroundColor = (customFieldOverlayColor ?? .clear).cgColor
    }

    textView.textColor = .labelColor
    textView.insertionPointColor = currentTint ?? .controlAccentColor
    placeholderLabel.textColor = customPlaceholderColor ?? themedPlaceholderColor()
    if #available(macOS 10.14, *) {
      let cancelColor = customCancelButtonColor ?? currentTint ?? .controlAccentColor
      clearButton.contentTintColor =
        clearButtonIcon?.iconDataColor ?? customClearButtonColor ?? customPlaceholderColor ?? themedPlaceholderColor()
      clearButton.layer?.backgroundColor = NSColor.clear.cgColor
      clearButton.layer?.cornerRadius = 0
      cancelButton.contentTintColor = cancelColor
      cancelButton.attributedTitle = NSAttributedString(
        string: cancelButtonText,
        attributes: [
          .foregroundColor: cancelColor,
          .font: cancelButton.font ?? NSFont.systemFont(ofSize: 14)
        ]
      )
      searchButton.contentTintColor =
        leadingAccessoryIcon?.iconDataColor ?? customLeadingAccessoryColor ?? customPlaceholderColor ?? themedPlaceholderColor()
      searchButton.layer?.backgroundColor = NSColor.clear.cgColor
      searchButton.layer?.cornerRadius = 0
      sendButton.contentTintColor =
        sendButtonIcon?.iconDataColor ?? customSendButtonForegroundColor ?? .white
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

  private func themedPlaceholderColor() -> NSColor {
    return NSColor.labelColor.withAlphaComponent(isDarkAppearance ? 0.44 : 0.34)
  }

  private func updateTrailingAccessoryAlignment(
    hasText: Bool? = nil,
    currentFieldHeight: CGFloat? = nil
  ) {
    let resolvedHasText = hasText ?? !textView.string.isEmpty
    let showsSendButton = resolvedTrailingAccessorySlot(
      hasText: resolvedHasText,
      hasFocus: window?.firstResponder === textView
    ) == "send"
    let resolvedFieldHeight = max(
      requestedMinHeight,
      currentFieldHeight ?? (lastReportedHeight > 0 ? lastReportedHeight : requestedMinHeight)
    )
    let centersSendButton = showsSendButton && resolvedFieldHeight <= requestedMinHeight + 0.5
    let alignsToFieldCenter = showsLeadingAccessory || !resolvedHasText || centersSendButton
    trailingButtonsFirstLineCenterYConstraint.isActive = false
    trailingButtonsCenterYConstraint.isActive = alignsToFieldCenter
    trailingButtonsBottomConstraint.isActive = showsSendButton && !centersSendButton
    trailingButtonsTrailingConstraint.constant = showsSendButton
      ? -sendButtonOuterInset
      : -(compactHorizontalPadding - 2 + trailingReservedWidth)
    trailingButtonsBottomConstraint.constant = -sendButtonOuterInset
  }

  private func currentLeadingAccessoryWidth() -> CGFloat {
    if showsLeadingAccessory {
      return max(accessoryButtonSize, leadingReservedWidth)
    }
    return leadingReservedWidth
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
    let hasFocus = window?.firstResponder === textView
    let activeSlot = resolvedTrailingAccessorySlot(hasText: hasText, hasFocus: hasFocus)

    updateTrailingAccessoryAlignment(hasText: hasText)

    clearButton.isHidden = activeSlot != "clear"
    clearButton.isEnabled = controlEnabled && activeSlot == "clear"
    clearButton.alphaValue = clearButton.isEnabled ? 1.0 : disabledOpacity
    searchButton.isHidden = !showsLeadingAccessory
    searchButton.isEnabled = controlEnabled && showsLeadingAccessory && leadingAccessoryTriggersSubmit
    searchButton.alphaValue = controlEnabled && showsLeadingAccessory ? 1.0 : disabledOpacity
    sendButton.isHidden = activeSlot != "send"
    sendButton.isEnabled = controlEnabled && activeSlot == "send" && hasText
    sendButton.alphaValue = sendButton.isEnabled ? 1.0 : disabledOpacity
    for (index, trailingButton) in trailingButtons.enumerated() {
      let canShow = activeSlot == "actions" && trailingButtonsEnabled[index]
      trailingButton.isHidden = !canShow
      trailingButton.isEnabled = controlEnabled && canShow
      trailingButton.alphaValue = trailingButton.isEnabled ? 1.0 : disabledOpacity
    }
    updatePlaceholderVisibility()
  }

  @discardableResult
  private func refreshHeightAndNotifyIfNeeded(force: Bool = false) -> CGFloat {
    layoutSubtreeIfNeeded()
    fieldClipView.layoutSubtreeIfNeeded()

    let fallbackWidth = fieldClipView.bounds.width
      - compactHorizontalPadding
      - currentLeadingAccessoryWidth()
      - trailingReservedWidth
      - compactHorizontalPadding
    let measuredWidth = max(scrollView.contentSize.width, scrollView.bounds.width)
    let availableWidth = max(measuredWidth > 0 ? measuredWidth : fallbackWidth, 40)
    if let textContainer = textView.textContainer {
      let font = textView.font ?? NSFont.systemFont(ofSize: 16)
      textContainer.containerSize = NSSize(
        width: availableWidth,
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
        width: availableWidth,
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
        isEnabled: controlEnabled
      )
    )
    glassHostingView?.isHidden = false
  }

  private func updateAccessoryButtonConstraints() {
    clearButtonWidthConstraint?.constant = accessoryButtonSize
    clearButtonHeightConstraint?.constant = accessoryButtonSize
    leadingSearchWidthConstraint?.constant = currentLeadingAccessoryWidth()
    searchButtonHeightConstraint?.constant = accessoryButtonSize
    for constraint in trailingButtonWidthConstraints {
      constraint.constant = accessoryButtonSize
    }
    for constraint in trailingButtonHeightConstraints {
      constraint.constant = accessoryButtonSize
    }
  }

  private func resolveVisibilityRule(
    _ rule: String,
    hasText: Bool,
    hasFocus: Bool
  ) -> Bool {
    switch rule {
    case "never":
      return false
    case "always":
      return true
    case "whileEmpty":
      return !hasText
    case "whileNotEmpty":
      return hasText
    case "whileFocused":
      return hasFocus
    case "whileUnfocused":
      return !hasFocus
    case "whileEmptyAndFocused":
      return !hasText && hasFocus
    case "whileEmptyBeforeInteractionOrFocused":
      return !hasText && (!hasInteractedWithField || hasFocus)
    default:
      return false
    }
  }

  private func resolvedTrailingAccessorySlot(
    hasText: Bool,
    hasFocus: Bool
  ) -> String? {
    for slot in trailingAccessoryOrder {
      switch slot {
      case "clear":
        if resolveVisibilityRule(clearButtonVisibilityRule, hasText: hasText, hasFocus: hasFocus) {
          return slot
        }
      case "actions":
        if !currentTrailingActions.isEmpty &&
            resolveVisibilityRule(trailingActionsVisibilityRule, hasText: hasText, hasFocus: hasFocus) {
          return slot
        }
      case "send":
        if resolveVisibilityRule(sendButtonVisibilityRule, hasText: hasText, hasFocus: hasFocus) {
          return slot
        }
      default:
        continue
      }
    }
    return nil
  }

  private func applyAccessoryIcon(
    to button: NSButton,
    action: TrailingAction?,
    defaultSystemName: String,
    fallback: NSImage.Name,
    defaultPointSize: CGFloat,
    defaultWeight: NSFont.Weight = .regular
  ) {
    if let action,
       let image = Self.iconImage(
        codePoint: action.iconDataCodePoint,
        fontFamily: action.iconDataFontFamily,
        fontPackage: action.iconDataFontPackage,
        pointSize: actionIconPointSize(action),
        fill: action.iconDataFill,
        weight: action.iconDataWeight,
        grade: action.iconDataGrade,
        opticalSize: action.iconDataOpticalSize
       ) {
      button.image = image
      return
    }

    button.image = Self.systemSymbolImage(named: defaultSystemName, fallback: fallback)
    if #available(macOS 11.0, *),
       let image = button.image?.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: defaultPointSize, weight: defaultWeight)
       ) {
      button.image = image
    }
  }

  private func applyAccessoryIcons() {
    applyAccessoryIcon(
      to: clearButton,
      action: clearButtonIcon,
      defaultSystemName: "xmark.circle.fill",
      fallback: NSImage.stopProgressTemplateName,
      defaultPointSize: 18
    )
    applyAccessoryIcon(
      to: searchButton,
      action: leadingAccessoryIcon,
      defaultSystemName: "magnifyingglass",
      fallback: NSImage.touchBarSearchTemplateName,
      defaultPointSize: 18
    )
    applyAccessoryIcon(
      to: sendButton,
      action: sendButtonIcon,
      defaultSystemName: "arrow.up",
      fallback: NSImage.touchBarGoUpTemplateName,
      defaultPointSize: defaultSendButtonIconSize,
      defaultWeight: .medium
    )
    sendButton.imageScaling = .scaleProportionallyDown
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
    return min(accessoryButtonSize - 4, max(8, action.iconDataSize))
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
