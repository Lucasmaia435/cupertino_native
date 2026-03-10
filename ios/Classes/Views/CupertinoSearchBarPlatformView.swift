import Flutter
import SwiftUI
import UIKit
import CoreText

private final class LayoutAwareSearchContainerView: UIView {
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

@available(iOS 26.0, *)
private struct IOSGlassInputBackground: View {
  let cornerRadius: CGFloat
  let isDark: Bool
  let isEnabled: Bool

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    shape
      .fill(Color.clear)
      .glassEffect(.regular, in: shape)
      .overlay {
        shape.fill(Color.white.opacity(isDark ? 0.08 : 0.14))
      }
      .opacity(isEnabled ? 1.0 : 0.9)
      .allowsHitTesting(false)
  }
}

class CupertinoSearchBarPlatformView: NSObject, FlutterPlatformView, UITextViewDelegate {
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
  private let container: LayoutAwareSearchContainerView
  private let fieldClipView: UIView
  private let fieldBackgroundView: UIVisualEffectView
  private let fieldTintOverlayView: UIView
  private let textView: UITextView
  private let placeholderLabel: UILabel
  private let trailingStackView: UIStackView
  private let clearButton: UIButton
  private let trailingButtons: [UIButton]
  private let sendButton: UIButton
  private let searchButton: UIButton
  private let cancelButton: UIButton
  private var glassHostingController: UIHostingController<AnyView>?
  private var leadingSearchWidthConstraint: NSLayoutConstraint!
  private var searchButtonCenterYConstraint: NSLayoutConstraint!
  private var trailingStackFirstLineCenterYConstraint: NSLayoutConstraint!
  private var trailingStackCenterYConstraint: NSLayoutConstraint!
  private var trailingStackTrailingConstraint: NSLayoutConstraint!
  private var trailingStackBottomConstraint: NSLayoutConstraint!
  private var sendButtonWidthConstraint: NSLayoutConstraint!
  private var sendButtonHeightConstraint: NSLayoutConstraint!
  private var placeholderTopConstraint: NSLayoutConstraint!
  private var fieldTrailingConstraintToContainer: NSLayoutConstraint!
  private var fieldTrailingConstraintToCancel: NSLayoutConstraint!
  private var currentTrailingActions: [TrailingAction] = []
  private var trailingButtonsEnabled: [Bool] = [false, false]
  private var currentTint: UIColor?
  private var customBackgroundColor: UIColor?
  private var customFieldBackgroundColor: UIColor?
  private var customSendButtonBackgroundColor: UIColor?
  private var customPlaceholderColor: UIColor?
  private var controlEnabled = true
  private var focusEnabled = true
  private var isSearchMode = true
  private var showsCancelButton = false
  private var requestedMinHeight: CGFloat = 44
  private var requestedMaxHeight: CGFloat = 240
  private var maxVisibleLines = 1
  private var lastReportedHeight: CGFloat = 0
  private var isDarkAppearance = false
  private var isApplyingProgrammaticText = false
  private var hasInteractedWithSearchField = false

  private let compactHorizontalPadding: CGFloat = 16
  private let compactVerticalPadding: CGFloat = 8
  private let textOpticalVerticalOffset: CGFloat = 1.5
  private let fieldCornerRadius: CGFloat = 28
  private let accessoryButtonSize: CGFloat = 32
  private let sendButtonOuterInset: CGFloat = 8
  private let sendButtonContentInset: CGFloat = 4
  private let sendButtonIconSize: CGFloat = 16
  private let sendButtonDiameterBoost: CGFloat = 8
  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    let clearButton = UIButton(type: .system)
    let firstTrailingButton = UIButton(type: .system)
    let secondTrailingButton = UIButton(type: .system)
    let sendButton = UIButton(type: .system)
    let searchButton = UIButton(type: .system)
    let cancelButton = UIButton(type: .system)
    self.channel = FlutterMethodChannel(name: "CupertinoNativeSearchBar_\(viewId)", binaryMessenger: messenger)
    self.container = LayoutAwareSearchContainerView(frame: frame)
    self.fieldClipView = UIView(frame: .zero)
    self.fieldBackgroundView = UIVisualEffectView(effect: nil)
    self.fieldTintOverlayView = UIView(frame: .zero)
    self.textView = UITextView(frame: .zero)
    self.placeholderLabel = UILabel(frame: .zero)
    self.trailingStackView = UIStackView(arrangedSubviews: [clearButton, firstTrailingButton, secondTrailingButton, sendButton])
    self.clearButton = clearButton
    self.trailingButtons = [firstTrailingButton, secondTrailingButton]
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
    var tint: UIColor? = nil
    var bg: UIColor? = nil
    var fieldBg: UIColor? = nil
    var sendButtonBg: UIColor? = nil
    var placeholderColor: UIColor? = nil
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
        if let value = style["placeholderColor"] as? NSNumber {
          placeholderColor = Self.colorFromARGB(value.intValue)
        }
      }
      trailingActions = Self.parseTrailingActions(dict["traillingActions"])
    }

    super.init()

    container.backgroundColor = .clear
    if #available(iOS 13.0, *) {
      container.overrideUserInterfaceStyle = isDark ? .dark : .light
    }
    currentTint = tint
    customBackgroundColor = bg
    customFieldBackgroundColor = fieldBg
    customSendButtonBackgroundColor = sendButtonBg
    customPlaceholderColor = placeholderColor
    controlEnabled = enabled
    self.focusEnabled = focusEnabled
    self.isSearchMode = isSearchMode
    self.showsCancelButton = showsCancelButton
    requestedMinHeight = max(36, min(minHeight, maxHeight))
    requestedMaxHeight = max(requestedMinHeight, min(maxHeight, 240))
    self.maxVisibleLines = max(1, maxVisibleLines)

    container.onLayout = { [weak self] in
      self?.refreshHeightAndNotifyIfNeeded()
    }

    fieldClipView.translatesAutoresizingMaskIntoConstraints = false
    fieldClipView.clipsToBounds = true
    fieldClipView.layer.cornerRadius = fieldCornerRadius
    fieldClipView.layer.cornerCurve = .continuous

    fieldBackgroundView.translatesAutoresizingMaskIntoConstraints = false
    fieldBackgroundView.isUserInteractionEnabled = false

    fieldTintOverlayView.translatesAutoresizingMaskIntoConstraints = false
    fieldTintOverlayView.isUserInteractionEnabled = false

    textView.translatesAutoresizingMaskIntoConstraints = false
    textView.delegate = self
    textView.backgroundColor = .clear
    textView.text = text
    textView.font = UIFont.systemFont(ofSize: 17)
    textView.isScrollEnabled = false
    textView.showsVerticalScrollIndicator = false
    textView.showsHorizontalScrollIndicator = false
    textView.alwaysBounceVertical = false
    textView.keyboardDismissMode = .interactive
    textView.textContainer.lineFragmentPadding = 0
    applyTextInsets()

    placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
    placeholderLabel.text = placeholder
    placeholderLabel.font = textView.font
    placeholderLabel.numberOfLines = 1

    trailingStackView.translatesAutoresizingMaskIntoConstraints = false
    trailingStackView.axis = .horizontal
    trailingStackView.alignment = .center
    trailingStackView.distribution = .fill
    trailingStackView.spacing = 6

    configureAccessoryButton(clearButton, size: accessoryButtonSize)
    clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
    clearButton.addTarget(self, action: #selector(onClearPressed), for: .touchUpInside)

    for (index, button) in trailingButtons.enumerated() {
      configureAccessoryButton(button, size: accessoryButtonSize)
      button.tag = index
      button.addTarget(self, action: #selector(onTrailingPressed(_:)), for: .touchUpInside)
      button.isHidden = true
    }

    let sendButtonSizeConstraints = configureAccessoryButton(
      sendButton,
      size: sendButtonDiameter(for: requestedMinHeight)
    )
    sendButtonWidthConstraint = sendButtonSizeConstraints.width
    sendButtonHeightConstraint = sendButtonSizeConstraints.height
    sendButton.setImage(UIImage(systemName: "arrow.up"), for: .normal)
    sendButton.addTarget(self, action: #selector(onSendPressed), for: .touchUpInside)
    if #available(iOS 13.0, *) {
      sendButton.setPreferredSymbolConfiguration(
        UIImage.SymbolConfiguration(pointSize: sendButtonIconSize, weight: .medium),
        forImageIn: .normal
      )
    }
    if #available(iOS 15.0, *) {
      var config = sendButton.configuration ?? UIButton.Configuration.plain()
      config.contentInsets = NSDirectionalEdgeInsets(
        top: sendButtonContentInset,
        leading: sendButtonContentInset,
        bottom: sendButtonContentInset,
        trailing: sendButtonContentInset
      )
      sendButton.configuration = config
    } else {
      sendButton.contentEdgeInsets = UIEdgeInsets(
        top: sendButtonContentInset,
        left: sendButtonContentInset,
        bottom: sendButtonContentInset,
        right: sendButtonContentInset
      )
    }

    configureAccessoryButton(searchButton, size: accessoryButtonSize)
    searchButton.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
    searchButton.addTarget(self, action: #selector(onSearchPressed), for: .touchUpInside)

    cancelButton.translatesAutoresizingMaskIntoConstraints = false
    cancelButton.setTitle("Cancel", for: .normal)
    cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 17)
    cancelButton.addTarget(self, action: #selector(onCancelPressed), for: .touchUpInside)
    cancelButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    cancelButton.setContentHuggingPriority(.required, for: .horizontal)

    container.addSubview(fieldClipView)
    container.addSubview(cancelButton)
    fieldClipView.addSubview(fieldBackgroundView)
    installGlassBackgroundIfNeeded()
    fieldClipView.addSubview(fieldTintOverlayView)
    fieldClipView.addSubview(searchButton)
    fieldClipView.addSubview(textView)
    fieldClipView.addSubview(placeholderLabel)
    fieldClipView.addSubview(trailingStackView)

    leadingSearchWidthConstraint = searchButton.widthAnchor.constraint(equalToConstant: accessoryButtonSize)
    let firstLineCenterOffset = currentFirstLineCenterOffset()
    searchButtonCenterYConstraint = searchButton.centerYAnchor.constraint(equalTo: fieldClipView.centerYAnchor)
    trailingStackFirstLineCenterYConstraint = trailingStackView.centerYAnchor.constraint(
      equalTo: textView.topAnchor,
      constant: firstLineCenterOffset
    )
    trailingStackCenterYConstraint = trailingStackView.centerYAnchor.constraint(
      equalTo: fieldClipView.centerYAnchor
    )
    trailingStackTrailingConstraint = trailingStackView.trailingAnchor.constraint(
      equalTo: fieldClipView.trailingAnchor,
      constant: -(compactHorizontalPadding - 2)
    )
    trailingStackBottomConstraint = trailingStackView.bottomAnchor.constraint(
      equalTo: fieldClipView.bottomAnchor,
      constant: -(compactVerticalPadding - 2)
    )
    placeholderTopConstraint = placeholderLabel.centerYAnchor.constraint(
      equalTo: textView.topAnchor,
      constant: firstLineCenterOffset
    )
    fieldTrailingConstraintToContainer = fieldClipView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
    fieldTrailingConstraintToCancel = fieldClipView.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8)

    NSLayoutConstraint.activate([
      fieldClipView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      fieldClipView.topAnchor.constraint(equalTo: container.topAnchor),
      fieldClipView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      fieldTrailingConstraintToContainer,

      cancelButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      cancelButton.centerYAnchor.constraint(equalTo: fieldClipView.centerYAnchor),
      cancelButton.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
      cancelButton.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),

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
      searchButton.heightAnchor.constraint(equalToConstant: accessoryButtonSize),
      leadingSearchWidthConstraint,

      trailingStackTrailingConstraint,
      trailingStackFirstLineCenterYConstraint,
      trailingStackBottomConstraint,

      textView.leadingAnchor.constraint(equalTo: searchButton.trailingAnchor, constant: 4),
      textView.trailingAnchor.constraint(equalTo: trailingStackView.leadingAnchor, constant: -8),
      textView.topAnchor.constraint(equalTo: fieldClipView.topAnchor),
      textView.bottomAnchor.constraint(equalTo: fieldClipView.bottomAnchor),

      placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
      placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingStackView.leadingAnchor, constant: -8),
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
          "width": Double(max(self.container.bounds.width, 0)),
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
          if let value = params["placeholderColor"] as? NSNumber {
            self.customPlaceholderColor = Self.colorFromARGB(value.intValue)
          } else if params.keys.contains("placeholderColor") {
            self.customPlaceholderColor = nil
          }
          self.applyVisualStyle()
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing style", details: nil)) }
      case "setVisible":
        if let params = call.arguments as? [String: Any], let visible = (params["visible"] as? NSNumber)?.boolValue {
          self.container.isHidden = !visible
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing visible", details: nil)) }
      case "setBrightness":
        if let params = call.arguments as? [String: Any], let isDark = (params["isDark"] as? NSNumber)?.boolValue {
          self.isDarkAppearance = isDark
          self.applyVisualStyle()
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil)) }
      case "focus":
        if self.controlEnabled && self.focusEnabled {
          self.textView.becomeFirstResponder()
        }
        result(nil)
      case "unfocus":
        self.textView.resignFirstResponder()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    return container
  }

  func textViewDidChange(_ textView: UITextView) {
    refreshAccessoryButtons()
    let height = refreshHeightAndNotifyIfNeeded()
    channel.invokeMethod("textChanged", arguments: [
      "text": textView.text ?? "",
      "height": Double(height)
    ])
  }

  func textViewDidBeginEditing(_ textView: UITextView) {
    guard controlEnabled && focusEnabled else {
      textView.resignFirstResponder()
      return
    }
    hasInteractedWithSearchField = true
    refreshAccessoryButtons()
    channel.invokeMethod("tapped", arguments: nil)
    channel.invokeMethod("focusChanged", arguments: ["focused": true])
  }

  func textViewDidEndEditing(_ textView: UITextView) {
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

  @objc private func onCancelPressed() {
    guard controlEnabled else { return }
    applyText("")
    let height = refreshHeightAndNotifyIfNeeded(force: true)
    channel.invokeMethod("textChanged", arguments: [
      "text": "",
      "height": Double(height)
    ])
    channel.invokeMethod("cancelled", arguments: nil)
    textView.resignFirstResponder()
  }

  @objc private func onTrailingPressed(_ sender: UIButton) {
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
    channel.invokeMethod("submitted", arguments: ["text": textView.text ?? ""])
  }

  @objc private func onSendPressed() {
    guard controlEnabled, !isSearchMode, let text = textView.text, !text.isEmpty else {
      return
    }
    channel.invokeMethod("submitted", arguments: ["text": textView.text ?? ""])
  }

  @discardableResult
  private func configureAccessoryButton(_ button: UIButton, size: CGFloat) -> (width: NSLayoutConstraint, height: NSLayoutConstraint) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.adjustsImageWhenHighlighted = true
    button.imageView?.contentMode = .scaleAspectFit
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.clipsToBounds = true
    button.layer.cornerCurve = .continuous
    let widthConstraint = button.widthAnchor.constraint(equalToConstant: size)
    let heightConstraint = button.heightAnchor.constraint(equalToConstant: size)
    NSLayoutConstraint.activate([
      widthConstraint,
      heightConstraint
    ])
    if #available(iOS 15.0, *) {
      var config = UIButton.Configuration.plain()
      config.contentInsets = .zero
      button.configuration = config
    }
    return (widthConstraint, heightConstraint)
  }

  private func applyText(_ text: String) {
    guard textView.text != text else { return }
    isApplyingProgrammaticText = true
    textView.text = text
    isApplyingProgrammaticText = false
    updatePlaceholderVisibility()
    refreshAccessoryButtons()
    refreshHeightAndNotifyIfNeeded(force: true)
  }

  private func applyPlaceholder(_ placeholder: String?) {
    placeholderLabel.text = placeholder
    updatePlaceholderVisibility()
  }

  private func applyEnabled(_ enabled: Bool) {
    controlEnabled = enabled
    if !enabled && textView.isFirstResponder {
      textView.resignFirstResponder()
    }
    let editable = enabled && focusEnabled
    textView.isEditable = editable
    textView.isSelectable = editable
    textView.isUserInteractionEnabled = enabled
    fieldClipView.alpha = enabled ? 1.0 : 0.6
    cancelButton.alpha = enabled ? 1.0 : 0.6
    clearButton.isEnabled = enabled
    cancelButton.isEnabled = enabled
    applyVisualStyle()
    refreshAccessoryButtons()
  }

  private func applyFocusEnabled(_ enabled: Bool) {
    focusEnabled = enabled
    if !enabled && textView.isFirstResponder {
      textView.resignFirstResponder()
    }
    let editable = controlEnabled && enabled
    textView.isEditable = editable
    textView.isSelectable = editable
  }

  private func applyMode(_ isSearch: Bool) {
    let wasSearchMode = isSearchMode
    isSearchMode = isSearch
    if isSearch && !wasSearchMode {
      hasInteractedWithSearchField = false
    }
    leadingSearchWidthConstraint.constant = isSearch ? accessoryButtonSize : 0
    updateTrailingAccessoryAlignment()
    refreshAccessoryButtons()
    container.setNeedsLayout()
  }

  private func applyShowsCancelButton(_ shows: Bool) {
    showsCancelButton = shows
    cancelButton.isHidden = !shows
    fieldTrailingConstraintToContainer.isActive = !shows
    fieldTrailingConstraintToCancel.isActive = shows
    container.setNeedsLayout()
  }

  private func applyMinHeight(
    _ minHeight: CGFloat,
    maxHeight: CGFloat?,
    maxVisibleLines: Int?
  ) {
    requestedMinHeight = max(36, min(minHeight, self.requestedMaxHeight))
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
    if #available(iOS 13.0, *) {
      container.overrideUserInterfaceStyle = isDarkAppearance ? .dark : .light
    }

    container.backgroundColor = customBackgroundColor ?? .clear
    fieldClipView.layer.cornerRadius = fieldCornerRadius
    fieldClipView.layer.cornerCurve = .continuous
    fieldClipView.layer.borderWidth = 1
    fieldClipView.layer.borderColor = UIColor.white.withAlphaComponent(
      isDarkAppearance ? 0.16 : 0.34
    ).cgColor

    if #available(iOS 26.0, *) {
      updateGlassBackground()
      fieldBackgroundView.isHidden = true
      glassHostingController?.view.isHidden = false
      if let customFieldBackgroundColor {
        fieldTintOverlayView.backgroundColor = customFieldBackgroundColor.withAlphaComponent(
          isDarkAppearance ? 0.18 : 0.22
        )
      } else {
        fieldTintOverlayView.backgroundColor = .clear
      }
    } else if let customFieldBackgroundColor {
      fieldBackgroundView.isHidden = true
      glassHostingController?.view.isHidden = true
      fieldTintOverlayView.backgroundColor = customFieldBackgroundColor
    } else {
      glassHostingController?.view.isHidden = true
      fieldBackgroundView.isHidden = false
      fieldBackgroundView.effect = currentBlurEffect()
      fieldTintOverlayView.backgroundColor = .clear
    }

    textView.textColor = .label
    textView.tintColor = currentTint ?? container.tintColor
    placeholderLabel.textColor = customPlaceholderColor ?? themedPlaceholderColor()
    placeholderLabel.font = textView.font
    clearButton.tintColor = customPlaceholderColor ?? themedPlaceholderColor()
    clearButton.backgroundColor = .clear
    clearButton.layer.cornerRadius = 0
    cancelButton.tintColor = currentTint ?? container.tintColor
    cancelButton.setTitleColor(currentTint ?? container.tintColor, for: .normal)
    cancelButton.setTitleColor(
      (currentTint ?? container.tintColor).withAlphaComponent(0.6),
      for: .disabled
    )
    searchButton.tintColor = customPlaceholderColor ?? themedPlaceholderColor()
    searchButton.backgroundColor = .clear
    searchButton.layer.cornerRadius = 0
    sendButton.tintColor = .white
    sendButton.backgroundColor =
      customSendButtonBackgroundColor ?? currentTint ?? container.tintColor
    sendButton.layer.cornerRadius = sendButtonDiameter(for: requestedMinHeight) / 2

    for index in trailingButtons.indices {
      let color = index < currentTrailingActions.count
        ? (currentTrailingActions[index].iconDataColor ?? currentTint ?? container.tintColor)
        : (currentTint ?? container.tintColor)
      trailingButtons[index].tintColor = color
      trailingButtons[index].backgroundColor = .clear
      trailingButtons[index].layer.cornerRadius = 0
    }
  }

  private func currentBlurEffect() -> UIBlurEffect {
    if #available(iOS 13.0, *) {
      return UIBlurEffect(
        style: isDarkAppearance ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight
      )
    }
    return UIBlurEffect(style: .extraLight)
  }

  private func themedPlaceholderColor() -> UIColor {
    return UIColor.label.withAlphaComponent(isDarkAppearance ? 0.44 : 0.34)
  }

  private func applyTextInsets() {
    let lineHeight = ceil(textView.font?.lineHeight ?? UIFont.systemFont(ofSize: 17).lineHeight)
    let centeredInset = (requestedMinHeight - lineHeight) / 2.0
    let verticalInset = max(compactVerticalPadding - 1, centeredInset)
    let topInset = verticalInset + textOpticalVerticalOffset
    let bottomInset = max(0, verticalInset - textOpticalVerticalOffset)
    textView.textContainerInset = UIEdgeInsets(
      top: topInset,
      left: 0,
      bottom: bottomInset,
      right: 0
    )
    let firstLineCenterOffset = topInset + (lineHeight / 2.0)
    trailingStackFirstLineCenterYConstraint?.constant = firstLineCenterOffset
    placeholderTopConstraint?.constant = firstLineCenterOffset
  }

  private func currentFirstLineCenterOffset() -> CGFloat {
    let lineHeight = ceil(textView.font?.lineHeight ?? UIFont.systemFont(ofSize: 17).lineHeight)
    return textView.textContainerInset.top + (lineHeight / 2.0)
  }

  private func installGlassBackgroundIfNeeded() {
    guard #available(iOS 26.0, *) else { return }
    guard glassHostingController == nil else { return }

    let host = UIHostingController(
      rootView: AnyView(
        IOSGlassInputBackground(
          cornerRadius: fieldCornerRadius,
          isDark: isDarkAppearance,
          isEnabled: controlEnabled
        )
      )
    )
    host.view.translatesAutoresizingMaskIntoConstraints = false
    host.view.backgroundColor = .clear
    host.view.isUserInteractionEnabled = false
    glassHostingController = host
    fieldClipView.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: fieldClipView.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: fieldClipView.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: fieldClipView.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: fieldClipView.bottomAnchor),
    ])
  }

  private func updateGlassBackground() {
    guard #available(iOS 26.0, *) else { return }
    installGlassBackgroundIfNeeded()
    glassHostingController?.rootView = AnyView(
      IOSGlassInputBackground(
        cornerRadius: fieldCornerRadius,
        isDark: isDarkAppearance,
        isEnabled: controlEnabled
      )
    )
    glassHostingController?.view.isHidden = false
  }

  private func updatePlaceholderVisibility() {
    placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
  }

  private func updateTrailingAccessoryAlignment(
    hasText: Bool? = nil,
    currentFieldHeight: CGFloat? = nil
  ) {
    let resolvedHasText = hasText ?? !(textView.text ?? "").isEmpty
    let showsSendButton = !isSearchMode && resolvedHasText
    let resolvedFieldHeight = max(
      requestedMinHeight,
      currentFieldHeight ?? (lastReportedHeight > 0 ? lastReportedHeight : requestedMinHeight)
    )
    let centersSendButton = showsSendButton && resolvedFieldHeight <= requestedMinHeight + 0.5
    let alignsToFieldCenter = isSearchMode || !resolvedHasText || centersSendButton
    trailingStackFirstLineCenterYConstraint.isActive = false
    trailingStackCenterYConstraint.isActive = alignsToFieldCenter
    trailingStackBottomConstraint.isActive = showsSendButton && !centersSendButton
    trailingStackTrailingConstraint.constant = showsSendButton ? -sendButtonOuterInset : -(compactHorizontalPadding - 2)
    trailingStackBottomConstraint.constant = -sendButtonOuterInset
  }

  private func sendButtonDiameter(for fieldHeight: CGFloat) -> CGFloat {
    return max(0, fieldHeight - (sendButtonOuterInset * 2) + sendButtonDiameterBoost)
  }

  private func updateSendButtonSize(for fieldHeight: CGFloat) {
    let diameter = sendButtonDiameter(for: fieldHeight)
    sendButtonWidthConstraint.constant = diameter
    sendButtonHeightConstraint.constant = diameter
    sendButton.layer.cornerRadius = diameter / 2
  }

  private func refreshAccessoryButtons() {
    let hasText = !(textView.text ?? "").isEmpty
    let showsActionButtons = isSearchMode
      ? (!hasText && (!hasInteractedWithSearchField || textView.isFirstResponder))
      : !hasText

    updateTrailingAccessoryAlignment(hasText: hasText)

    clearButton.isHidden = !isSearchMode || !hasText
    clearButton.isEnabled = controlEnabled && isSearchMode && hasText
    clearButton.alpha = clearButton.isEnabled ? 1.0 : 0.6

    searchButton.isHidden = !isSearchMode
    searchButton.isEnabled = controlEnabled && isSearchMode
    searchButton.alpha = searchButton.isEnabled ? 1.0 : 0.6

    sendButton.isHidden = isSearchMode || !hasText
    sendButton.isEnabled = controlEnabled && !isSearchMode && hasText
    sendButton.alpha = sendButton.isEnabled ? 1.0 : 0.6

    for (index, button) in trailingButtons.enumerated() {
      let canShow = showsActionButtons && trailingButtonsEnabled[index]
      button.isHidden = !canShow
      button.isEnabled = controlEnabled && canShow
      button.alpha = button.isEnabled ? 1.0 : 0.6
    }

    updatePlaceholderVisibility()
  }

  @discardableResult
  private func refreshHeightAndNotifyIfNeeded(force: Bool = false) -> CGFloat {
    let availableWidth = max(
      textView.bounds.width,
      fieldClipView.bounds.width
        - compactHorizontalPadding
        - trailingStackView.bounds.width
        - compactHorizontalPadding
    )
    let font = textView.font ?? UIFont.systemFont(ofSize: 17)
    let fittingSize = textView.sizeThatFits(
      CGSize(width: max(availableWidth, 40), height: CGFloat.greatestFiniteMagnitude)
    )
    let descenderCompensation = ceil(abs(font.descender)) + 1
    let contentHeight = ceil(fittingSize.height + descenderCompensation)
    let lineHeight = ceil(font.lineHeight)
    let maxVisibleHeight = ceil(
      lineHeight * CGFloat(maxVisibleLines)
        + textView.textContainerInset.top
        + textView.textContainerInset.bottom
        + descenderCompensation
    )
    let desiredHeight = min(
      requestedMaxHeight,
      max(requestedMinHeight, min(contentHeight, maxVisibleHeight))
    )
    updateSendButtonSize(for: requestedMinHeight)
    updateTrailingAccessoryAlignment(
      hasText: !(textView.text ?? "").isEmpty,
      currentFieldHeight: desiredHeight
    )
    let shouldScroll = contentHeight > maxVisibleHeight + 0.5
    if textView.isScrollEnabled != shouldScroll {
      textView.isScrollEnabled = shouldScroll
    }

    if force || abs(lastReportedHeight - desiredHeight) > 0.5 {
      lastReportedHeight = desiredHeight
      channel.invokeMethod("heightChanged", arguments: ["height": Double(desiredHeight)])
    }
    return desiredHeight
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
        currentTrailingActions[index].iconDataColor ?? currentTint ?? container.tintColor
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
