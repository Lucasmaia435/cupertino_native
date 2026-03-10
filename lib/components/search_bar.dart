import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../channel/params.dart';

/// Trailing action rendered by the text field.
class CNTextFieldAction {
  /// Creates a trailing action.
  const CNTextFieldAction({required this.icon, required this.onPressed});

  /// Icon rendered by the trailing button.
  final Icon icon;

  /// Called when the action is pressed.
  final VoidCallback onPressed;
}

/// Deprecated compatibility alias for [CNTextFieldAction].
@Deprecated('Use CNTextFieldAction instead.')
class CNSearchBarAction extends CNTextFieldAction {
  /// Creates a trailing action.
  const CNSearchBarAction({required super.icon, required super.onPressed});
}

/// A Cupertino-native text field rendered by the host platform.
///
/// On iOS/macOS this embeds a native multiline text field through platform
/// views. On unsupported platforms it falls back to a Flutter-composed
/// Cupertino text field.
class CNTextField extends StatefulWidget {
  /// Creates a search text field.
  const CNTextField.search({
    super.key,
    this.text = '',
    this.onChanged,
    this.onSubmitted,
    this.onCancelled,
    this.onTap,
    this.placeholder,
    this.enabled = true,
    this.showsCancelButton = false,
    this.actions = const [],
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.height = 44.0,
    this.tint,
    this.backgroundColor,
    this.fieldBackgroundColor,
  }) : sendButtonBackgroundColor = null,
       _isSearch = true,
       assert(actions.length <= 2, 'CNTextField supports at most two actions.');

  /// Creates a chat/composer text field.
  const CNTextField.chat({
    super.key,
    this.text = '',
    this.onChanged,
    this.onSubmitted,
    this.onCancelled,
    this.onTap,
    this.placeholder,
    this.enabled = true,
    this.actions = const [],
    this.sendButtonBackgroundColor,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.height = 44.0,
    this.tint,
    this.backgroundColor,
    this.fieldBackgroundColor,
  }) : showsCancelButton = false,
       _isSearch = false,
       assert(actions.length <= 2, 'CNTextField supports at most two actions.');

  /// Current text displayed by the field.
  final String text;

  /// Called when the text changes due to user interaction.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits through the platform text input system.
  final ValueChanged<String>? onSubmitted;

  /// Called when the cancel action is triggered.
  final VoidCallback? onCancelled;

  /// Called when the field is tapped.
  final VoidCallback? onTap;

  /// Optional placeholder string.
  final String? placeholder;

  /// Whether the control is interactive.
  final bool enabled;

  /// Whether to display the cancel button.
  final bool showsCancelButton;

  /// Optional trailing actions rendered inside the field.
  ///
  /// Supports up to two actions.
  final List<CNTextFieldAction> actions;

  /// Optional text controller. When provided, [text] is ignored.
  final TextEditingController? controller;

  /// Optional focus node for matching [CupertinoTextField] focus behavior.
  final FocusNode? focusNode;

  /// Whether the field should request focus when inserted into the tree.
  final bool autofocus;

  /// Minimum visual height of the field.
  final double height;

  /// Background color for the chat send button.
  final Color? sendButtonBackgroundColor;

  /// Accent/tint color.
  final Color? tint;

  /// Optional background color for the whole control container.
  final Color? backgroundColor;

  /// Optional background color for the text field area.
  final Color? fieldBackgroundColor;

  final bool _isSearch;

  @override
  State<CNTextField> createState() => _CNTextFieldState();
}

class _CNTextFieldState extends State<CNTextField> {
  static const int _kAbsoluteMaxVisibleLines = 10;
  static const double _kBorderRadius = 28.0;
  static const double _kAccessorySize = 32.0;
  static const double _kFieldHorizontalPadding = 16.0;
  static const double _kFieldVerticalPadding = 8.0;
  static const double _kTextOpticalVerticalOffset = 1.5;
  static const double _kNativeMaxHeight = 240.0;
  static const double _kSendButtonOuterInset = 8.0;
  static const double _kSendButtonSizeBoost = 8.0;

  MethodChannel? _channel;
  late final TextEditingController _fallbackController;
  late final FocusNode _fallbackFocusNode;

  TextEditingController? _observedController;
  FocusNode? _observedFocusNode;

  bool _isApplyingNativeTextChange = false;
  bool _isApplyingNativeFocusChange = false;
  bool _hasSearchInteractionOccurred = false;
  double? _reportedNativeHeight;
  double? _pendingNativeHeight;
  bool _hasScheduledNativeHeightCommit = false;

  String? _lastText;
  String? _lastPlaceholder;
  bool? _lastEnabled;
  bool? _lastIsSearch;
  bool? _lastShowsCancelButton;
  bool? _lastIsDark;
  bool? _lastFocusEnabled;
  int? _lastTint;
  int? _lastBackground;
  int? _lastFieldBackground;
  int? _lastSendButtonBackground;
  double? _lastMinimumHeight;
  String? _lastTraillingActionsSignature;

  TextEditingController get _textController =>
      widget.controller ?? _fallbackController;

  FocusNode get _focusNode => widget.focusNode ?? _fallbackFocusNode;

  bool get _isDark => CupertinoTheme.of(context).brightness == Brightness.dark;

  Color? get _effectiveTint =>
      widget.tint ?? CupertinoTheme.of(context).primaryColor;

  bool get _isNativePlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  bool get _canInteractWithTextInput =>
      widget.enabled && _focusNode.canRequestFocus;

  double get _minimumHeight {
    final min = defaultTargetPlatform == TargetPlatform.macOS ? 28.0 : 36.0;
    return widget.height.clamp(min, _kNativeMaxHeight).toDouble();
  }

  double get _effectiveNativeHeight => (_reportedNativeHeight ?? _minimumHeight)
      .clamp(_minimumHeight, _kNativeMaxHeight)
      .toDouble();

  bool get _isSearchMode => widget._isSearch;

  bool get _showsClearButton =>
      _isSearchMode && widget.enabled && _textController.text.isNotEmpty;

  bool get _showsSendButton =>
      !_isSearchMode && widget.enabled && _textController.text.isNotEmpty;

  bool get _showsActions {
    if (widget.actions.isEmpty) return false;
    if (_isSearchMode) {
      return _textController.text.isEmpty &&
          (!_hasSearchInteractionOccurred || _focusNode.hasFocus);
    }
    return _textController.text.isEmpty;
  }

  int get _effectiveMaxLines => _isSearchMode ? 1 : _kAbsoluteMaxVisibleLines;

  Color? get _effectiveSendButtonBackgroundColor =>
      widget.sendButtonBackgroundColor ?? _effectiveTint;

  @override
  void initState() {
    super.initState();
    _fallbackController = TextEditingController(text: widget.text);
    _fallbackFocusNode = FocusNode();
    _observeController(_textController);
    _observeFocusNode(_focusNode);
  }

  @override
  void didUpdateWidget(covariant CNTextField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget._isSearch && widget._isSearch) {
      _hasSearchInteractionOccurred = false;
    }

    if (oldWidget.controller != widget.controller) {
      _unobserveController(oldWidget.controller ?? _fallbackController);
      _observeController(_textController);
    }

    if (oldWidget.focusNode != widget.focusNode) {
      _unobserveFocusNode(oldWidget.focusNode ?? _fallbackFocusNode);
      _observeFocusNode(_focusNode);
    }

    _syncFallbackControllerIfNeeded();

    if (!_canInteractWithTextInput && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }

    _syncPropsToNativeIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightnessIfNeeded();
    _syncPropsToNativeIfNeeded();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _unobserveController(_textController);
    _unobserveFocusNode(_focusNode);
    _fallbackController.dispose();
    _fallbackFocusNode.dispose();
    super.dispose();
  }

  void _observeController(TextEditingController controller) {
    _observedController = controller;
    controller.addListener(_onTextControllerChanged);
  }

  void _unobserveController(TextEditingController controller) {
    controller.removeListener(_onTextControllerChanged);
    if (_observedController == controller) {
      _observedController = null;
    }
  }

  void _observeFocusNode(FocusNode focusNode) {
    _observedFocusNode = focusNode;
    focusNode.addListener(_onFocusNodeChanged);
  }

  void _unobserveFocusNode(FocusNode focusNode) {
    focusNode.removeListener(_onFocusNodeChanged);
    if (_observedFocusNode == focusNode) {
      _observedFocusNode = null;
    }
  }

  void _onTextControllerChanged() {
    if (_isApplyingNativeTextChange) return;
    if (_isNativePlatform) {
      _syncTextToNativeIfNeeded();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _onFocusNodeChanged() {
    if (_isSearchMode && _focusNode.hasFocus) {
      _hasSearchInteractionOccurred = true;
    }
    if (_isNativePlatform && !_isApplyingNativeFocusChange) {
      _syncFocusToNativeIfNeeded();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _syncFallbackControllerIfNeeded() {
    if (widget.controller != null || _fallbackController.text == widget.text) {
      return;
    }
    _fallbackController.value = TextEditingValue(
      text: widget.text,
      selection: TextSelection.collapsed(offset: widget.text.length),
      composing: TextRange.empty,
    );
  }

  void _applyNativeText(String text) {
    if (_textController.text == text) return;
    _isApplyingNativeTextChange = true;
    _textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
    _isApplyingNativeTextChange = false;
  }

  void _applyNativeFocus(bool focused) {
    _isApplyingNativeFocusChange = true;
    try {
      if (focused) {
        if (_canInteractWithTextInput) {
          if (!_focusNode.hasFocus) {
            _focusNode.requestFocus();
          }
        } else {
          _syncFocusToNativeIfNeeded(forceUnfocus: true);
        }
      } else if (_focusNode.hasFocus) {
        _focusNode.unfocus();
      }
    } finally {
      _isApplyingNativeFocusChange = false;
    }
  }

  void _applyNativeHeight(double height) {
    final resolved = height.clamp(_minimumHeight, _kNativeMaxHeight).toDouble();
    if (!mounted) return;

    final currentReportedHeight = _reportedNativeHeight ?? _minimumHeight;
    final pendingHeight = _pendingNativeHeight;

    if (pendingHeight != null && (pendingHeight - resolved).abs() < 0.5) {
      return;
    }
    if (pendingHeight == null &&
        (currentReportedHeight - resolved).abs() < 0.5) {
      return;
    }

    if (resolved < currentReportedHeight) {
      _pendingNativeHeight = resolved;
      _scheduleNativeHeightCommit();
      return;
    }

    _pendingNativeHeight = null;
    _hasScheduledNativeHeightCommit = false;
    setState(() {
      _reportedNativeHeight = resolved;
    });
  }

  void _scheduleNativeHeightCommit() {
    if (_hasScheduledNativeHeightCommit) return;

    _hasScheduledNativeHeightCommit = true;
    SchedulerBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hasScheduledNativeHeightCommit = false;
      final pendingHeight = _pendingNativeHeight;
      _pendingNativeHeight = null;
      if (!mounted || pendingHeight == null) return;

      final currentReportedHeight = _reportedNativeHeight ?? _minimumHeight;
      if ((currentReportedHeight - pendingHeight).abs() < 0.5) return;

      setState(() {
        _reportedNativeHeight = pendingHeight;
      });
    });
  }

  Future<void> _syncTextToNativeIfNeeded() async {
    final channel = _channel;
    if (channel == null) return;

    final text = _textController.text;
    if (_lastText == text) return;

    await channel.invokeMethod('setText', {'text': text});
    _lastText = text;
  }

  Future<void> _syncFocusToNativeIfNeeded({bool forceUnfocus = false}) async {
    final channel = _channel;
    if (channel == null) return;

    if (forceUnfocus || !_focusNode.hasFocus || !_canInteractWithTextInput) {
      await channel.invokeMethod('unfocus');
      return;
    }

    await channel.invokeMethod('focus');
  }

  void _cacheCurrentProps() {
    _lastText = _textController.text;
    _lastPlaceholder = widget.placeholder;
    _lastEnabled = widget.enabled;
    _lastIsSearch = _isSearchMode;
    _lastShowsCancelButton = widget.showsCancelButton;
    _lastIsDark = _isDark;
    _lastFocusEnabled = _canInteractWithTextInput;
    _lastTint = resolveColorToArgb(_effectiveTint, context);
    _lastBackground = resolveColorToArgb(widget.backgroundColor, context);
    _lastFieldBackground = resolveColorToArgb(
      widget.fieldBackgroundColor,
      context,
    );
    _lastSendButtonBackground = resolveColorToArgb(
      _effectiveSendButtonBackgroundColor,
      context,
    );
    _lastMinimumHeight = _minimumHeight;
    _lastTraillingActionsSignature = _traillingActionsSignature(widget.actions);
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final channel = _channel;
    if (channel == null) return;

    final text = _textController.text;
    final placeholder = widget.placeholder;
    final enabled = widget.enabled;
    final isSearch = _isSearchMode;
    final showsCancelButton = widget.showsCancelButton;
    final minimumHeight = _minimumHeight;
    final focusEnabled = _canInteractWithTextInput;
    final tint = resolveColorToArgb(_effectiveTint, context);
    final bg = resolveColorToArgb(widget.backgroundColor, context);
    final fieldBg = resolveColorToArgb(widget.fieldBackgroundColor, context);
    final sendButtonBackground = resolveColorToArgb(
      _effectiveSendButtonBackgroundColor,
      context,
    );
    final traillingActions = widget.actions;
    final traillingActionsSignature = _traillingActionsSignature(
      traillingActions,
    );

    if (_lastText != text) {
      await channel.invokeMethod('setText', {'text': text});
      _lastText = text;
    }

    if (_lastPlaceholder != placeholder) {
      await channel.invokeMethod('setPlaceholder', {
        'placeholder': placeholder,
      });
      _lastPlaceholder = placeholder;
    }

    if (_lastEnabled != enabled) {
      await channel.invokeMethod('setEnabled', {'enabled': enabled});
      _lastEnabled = enabled;
    }

    if (_lastIsSearch != isSearch) {
      await channel.invokeMethod('setMode', {'isSearch': isSearch});
      _lastIsSearch = isSearch;
    }

    if (_lastShowsCancelButton != showsCancelButton) {
      await channel.invokeMethod('setShowsCancelButton', {
        'showsCancelButton': showsCancelButton,
      });
      _lastShowsCancelButton = showsCancelButton;
    }

    if (_lastMinimumHeight != minimumHeight) {
      await channel.invokeMethod('setMinHeight', {
        'minHeight': minimumHeight,
        'maxHeight': _kNativeMaxHeight,
        'maxVisibleLines': _effectiveMaxLines,
      });
      _lastMinimumHeight = minimumHeight;
      if ((_reportedNativeHeight ?? 0) < minimumHeight && mounted) {
        setState(() {
          _reportedNativeHeight = minimumHeight;
        });
      }
    }

    if (_lastFocusEnabled != focusEnabled) {
      await channel.invokeMethod('setFocusEnabled', {
        'focusEnabled': focusEnabled,
      });
      _lastFocusEnabled = focusEnabled;
      if (!focusEnabled) {
        await channel.invokeMethod('unfocus');
      }
    }

    if (_lastTraillingActionsSignature != traillingActionsSignature) {
      await channel.invokeMethod('setTrailingActions', {
        'traillingActions': _encodeTraillingActions(traillingActions),
      });
      _lastTraillingActionsSignature = traillingActionsSignature;
    }

    final style = <String, dynamic>{};
    if (_lastTint != tint && tint != null) {
      style['tint'] = tint;
      _lastTint = tint;
    }
    if (_lastBackground != bg && bg != null) {
      style['backgroundColor'] = bg;
      _lastBackground = bg;
    }
    if (_lastFieldBackground != fieldBg && fieldBg != null) {
      style['fieldBackgroundColor'] = fieldBg;
      _lastFieldBackground = fieldBg;
    }
    if (_lastSendButtonBackground != sendButtonBackground) {
      style['sendButtonBackgroundColor'] = sendButtonBackground;
      _lastSendButtonBackground = sendButtonBackground;
    }
    if (style.isNotEmpty) {
      await channel.invokeMethod('setStyle', style);
    }
  }

  Future<void> _syncBrightnessIfNeeded() async {
    final channel = _channel;
    if (channel == null) return;

    final isDark = _isDark;
    final tint = resolveColorToArgb(_effectiveTint, context);
    final bg = resolveColorToArgb(widget.backgroundColor, context);
    final fieldBg = resolveColorToArgb(widget.fieldBackgroundColor, context);
    final sendButtonBackground = resolveColorToArgb(
      _effectiveSendButtonBackgroundColor,
      context,
    );

    if (_lastIsDark != isDark) {
      await channel.invokeMethod('setBrightness', {'isDark': isDark});
      _lastIsDark = isDark;
    }

    final style = <String, dynamic>{};
    if (_lastTint != tint && tint != null) {
      style['tint'] = tint;
      _lastTint = tint;
    }
    if (_lastBackground != bg && bg != null) {
      style['backgroundColor'] = bg;
      _lastBackground = bg;
    }
    if (_lastFieldBackground != fieldBg && fieldBg != null) {
      style['fieldBackgroundColor'] = fieldBg;
      _lastFieldBackground = fieldBg;
    }
    if (_lastSendButtonBackground != sendButtonBackground) {
      style['sendButtonBackgroundColor'] = sendButtonBackground;
      _lastSendButtonBackground = sendButtonBackground;
    }
    if (style.isNotEmpty) {
      await channel.invokeMethod('setStyle', style);
    }
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('CupertinoNativeSearchBar_$id');
    _channel = channel;
    channel.setMethodCallHandler(_onMethodCall);
    _cacheCurrentProps();
    _lastTraillingActionsSignature = null;
    _syncBrightnessIfNeeded();
    _syncPropsToNativeIfNeeded();
    if (_focusNode.hasFocus && _canInteractWithTextInput) {
      _syncFocusToNativeIfNeeded();
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    final args = call.arguments as Map?;
    switch (call.method) {
      case 'textChanged':
        final text = args?['text'] as String?;
        if (text != null) {
          _applyNativeText(text);
          widget.onChanged?.call(text);
          _lastText = text;
        }
        final height = (args?['height'] as num?)?.toDouble();
        if (height != null) {
          _applyNativeHeight(height);
        }
        break;
      case 'heightChanged':
        final height = (args?['height'] as num?)?.toDouble();
        if (height != null) {
          _applyNativeHeight(height);
        }
        break;
      case 'submitted':
        final text = (args?['text'] as String?) ?? _textController.text;
        widget.onSubmitted?.call(text);
        break;
      case 'cancelled':
        widget.onCancelled?.call();
        break;
      case 'tapped':
        widget.onTap?.call();
        break;
      case 'focusChanged':
        final focused = args?['focused'] == true;
        _applyNativeFocus(focused);
        break;
      case 'trailingActionPressed':
        final index = (args?['index'] as num?)?.toInt();
        if (index != null && index >= 0 && index < widget.actions.length) {
          widget.actions[index].onPressed();
        }
        break;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isNativePlatform) {
      return _buildFallback(context);
    }

    if (!_canInteractWithTextInput && _focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.unfocus();
        }
      });
    }

    final creationParams = <String, dynamic>{
      'text': _textController.text,
      'placeholder': widget.placeholder,
      'enabled': widget.enabled,
      'isSearch': _isSearchMode,
      'showsCancelButton': widget.showsCancelButton,
      'minHeight': _minimumHeight,
      'maxHeight': _kNativeMaxHeight,
      'maxVisibleLines': _effectiveMaxLines,
      'focusEnabled': _canInteractWithTextInput,
      'traillingActions': _encodeTraillingActions(widget.actions),
      'isDark': _isDark,
      'style': encodeStyle(context, tint: _effectiveTint)
        ..addAll({
          if (widget.backgroundColor != null)
            'backgroundColor': resolveColorToArgb(
              widget.backgroundColor,
              context,
            ),
          if (widget.fieldBackgroundColor != null)
            'fieldBackgroundColor': resolveColorToArgb(
              widget.fieldBackgroundColor,
              context,
            ),
          if (_effectiveSendButtonBackgroundColor != null)
            'sendButtonBackgroundColor': resolveColorToArgb(
              _effectiveSendButtonBackgroundColor,
              context,
            ),
        }),
    };

    final platformView = defaultTargetPlatform == TargetPlatform.iOS
        ? UiKitView(
            viewType: 'CupertinoNativeSearchBar',
            creationParamsCodec: const StandardMessageCodec(),
            creationParams: creationParams,
            onPlatformViewCreated: _onPlatformViewCreated,
          )
        : AppKitView(
            viewType: 'CupertinoNativeSearchBar',
            creationParamsCodec: const StandardMessageCodec(),
            creationParams: creationParams,
            onPlatformViewCreated: _onPlatformViewCreated,
          );

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      includeSemantics: false,
      onFocusChange: (_) => _syncFocusToNativeIfNeeded(),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: SizedBox(height: _effectiveNativeHeight, child: platformView),
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final effectiveTint = widget.tint ?? theme.primaryColor;
    final canInteractWithTextInput =
        widget.enabled && _focusNode.canRequestFocus;

    if (!canInteractWithTextInput && _focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.unfocus();
        }
      });
    }

    final resolvedFieldBackground = CupertinoDynamicColor.resolve(
      widget.fieldBackgroundColor ?? CupertinoColors.systemGrey5,
      context,
    );
    final resolvedPlaceholderColor = CupertinoDynamicColor.resolve(
      CupertinoColors.placeholderText,
      context,
    );
    final resolvedSecondaryLabel = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final resolvedSendButtonBackground = CupertinoDynamicColor.resolve(
      _effectiveSendButtonBackgroundColor ?? effectiveTint,
      context,
    );

    final textStyle = theme.textTheme.textStyle.copyWith(
      fontSize: 17,
      height: 1.25,
    );
    final strutStyle = StrutStyle(
      fontSize: textStyle.fontSize,
      height: textStyle.height,
      forceStrutHeight: true,
    );
    final lineHeight = (textStyle.fontSize ?? 17) * (textStyle.height ?? 1.0);
    final minimumResolvedHeight = math.max(36.0, widget.height);
    final effectiveTextVerticalPadding = math.max(
      _kFieldVerticalPadding,
      (minimumResolvedHeight - lineHeight) / 2,
    );
    final effectiveTextTopPadding =
        effectiveTextVerticalPadding + _kTextOpticalVerticalOffset;
    final effectiveTextBottomPadding = math.max(
      0.0,
      effectiveTextVerticalPadding - _kTextOpticalVerticalOffset,
    );
    final minFieldHeight = math
        .max(
          36.0,
          math.max(
            widget.height,
            _fieldHeightForLines(lineHeight, 1, effectiveTextVerticalPadding),
          ),
        )
        .toDouble();
    final maxFieldHeight = math
        .max(
          minFieldHeight,
          _fieldHeightForLines(
            lineHeight,
            _effectiveMaxLines,
            effectiveTextVerticalPadding,
          ),
        )
        .toDouble();

    final actionWidgets = widget.actions
        .take(2)
        .map((action) {
          final resolvedActionIconSize = _resolvedActionIconSize(
            action.icon.size,
          );
          return _AccessoryButton(
            onPressed: widget.enabled ? action.onPressed : null,
            child: SizedBox.square(
              dimension: resolvedActionIconSize,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: action.icon.color ?? effectiveTint,
                    size: resolvedActionIconSize,
                  ),
                  child: action.icon,
                ),
              ),
            ),
          );
        })
        .toList(growable: false);

    final textInputAction = _isSearchMode
        ? TextInputAction.search
        : TextInputAction.newline;
    final keyboardType = _isSearchMode
        ? TextInputType.text
        : TextInputType.multiline;

    final textField = LayoutBuilder(
      builder: (context, constraints) {
        final sendButtonDiameter = math.max(
          0.0,
          minFieldHeight - (_kSendButtonOuterInset * 2) + _kSendButtonSizeBoost,
        );

        Widget? trailingAccessory;
        if (_isSearchMode) {
          if (_showsClearButton) {
            trailingAccessory = _AccessoryButton(
              onPressed: _clearText,
              foregroundColor: resolvedSecondaryLabel,
              child: Icon(
                CupertinoIcons.clear_thick_circled,
                size: 18,
                color: resolvedSecondaryLabel,
              ),
            );
          } else if (_showsActions) {
            trailingAccessory = Row(
              mainAxisSize: MainAxisSize.min,
              children: actionWidgets,
            );
          }
        } else if (_showsSendButton) {
          trailingAccessory = _SendButton(
            diameter: sendButtonDiameter,
            backgroundColor: resolvedSendButtonBackground,
            onPressed: widget.enabled ? _handleSubmitPressed : null,
          );
        } else if (_showsActions) {
          trailingAccessory = Row(
            mainAxisSize: MainAxisSize.min,
            children: actionWidgets,
          );
        }

        final showsCenteredSendButton =
            _showsSendButton &&
            _textFitsOnSingleLine(
              maxWidth: constraints.maxWidth,
              minFieldHeight: minFieldHeight,
              textStyle: textStyle,
              strutStyle: strutStyle,
            );
        final showsBottomAlignedSendButton =
            _showsSendButton && !showsCenteredSendButton;
        final fieldCrossAxisAlignment = showsBottomAlignedSendButton
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.center;
        final accessoryBottomPadding = showsBottomAlignedSendButton
            ? _kSendButtonOuterInset
            : 0.0;
        final accessoryEndPadding = _showsSendButton
            ? _kSendButtonOuterInset
            : _kFieldHorizontalPadding - 2;

        return AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: minFieldHeight,
              maxHeight: maxFieldHeight,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kBorderRadius),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: resolvedFieldBackground,
                  borderRadius: BorderRadius.circular(_kBorderRadius),
                ),
                child: Row(
                  crossAxisAlignment: fieldCrossAxisAlignment,
                  children: [
                    if (_isSearchMode)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: _kFieldHorizontalPadding - 4,
                          end: 4,
                        ),
                        child: _AccessoryButton(
                          onPressed: widget.enabled
                              ? _handleSubmitPressed
                              : null,
                          foregroundColor: resolvedSecondaryLabel,
                          child: const Icon(CupertinoIcons.search, size: 18),
                        ),
                      ),
                    Expanded(
                      child: CupertinoTheme(
                        data: theme.copyWith(primaryColor: effectiveTint),
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(
                            context,
                          ).copyWith(scrollbars: false),
                          child: CupertinoTextField.borderless(
                            controller: _textController,
                            focusNode: _focusNode,
                            autofocus: widget.autofocus,
                            enabled: widget.enabled,
                            enableInteractiveSelection:
                                canInteractWithTextInput,
                            padding: EdgeInsetsDirectional.only(
                              start: _isSearchMode
                                  ? 0
                                  : _kFieldHorizontalPadding,
                              end: 4,
                              top: effectiveTextTopPadding,
                              bottom: effectiveTextBottomPadding,
                            ),
                            minLines: 1,
                            maxLines: _isSearchMode ? 1 : null,
                            keyboardType: keyboardType,
                            textInputAction: textInputAction,
                            style: textStyle,
                            strutStyle: strutStyle,
                            placeholder: widget.placeholder,
                            placeholderStyle: textStyle.copyWith(
                              color: resolvedPlaceholderColor,
                            ),
                            cursorColor: effectiveTint,
                            onTap: widget.onTap,
                            onChanged: widget.onChanged,
                            onSubmitted: widget.onSubmitted,
                            contextMenuBuilder: (context, editableTextState) {
                              if (!canInteractWithTextInput) {
                                return const SizedBox.shrink();
                              }
                              if (defaultTargetPlatform == TargetPlatform.iOS &&
                                  SystemContextMenu.isSupported(context)) {
                                return SystemContextMenu.editableText(
                                  editableTextState: editableTextState,
                                );
                              }
                              return CupertinoAdaptiveTextSelectionToolbar.editableText(
                                editableTextState: editableTextState,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    if (trailingAccessory != null)
                      Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: 4,
                          end: accessoryEndPadding,
                          bottom: accessoryBottomPadding,
                        ),
                        child: trailingAccessory,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    Widget content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: textField),
        if (_isSearchMode && widget.showsCancelButton) ...[
          const SizedBox(width: 8),
          CupertinoTheme(
            data: theme.copyWith(primaryColor: effectiveTint),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              minimumSize: const Size(28, 28),
              onPressed: widget.enabled ? _handleCancelPressed : null,
              child: const Text('Cancel'),
            ),
          ),
        ],
      ],
    );

    if (widget.backgroundColor != null) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
            widget.backgroundColor!,
            context,
          ),
          borderRadius: BorderRadius.circular(_kBorderRadius),
        ),
        child: Padding(padding: const EdgeInsets.all(4), child: content),
      );
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: widget.enabled ? 1 : 0.6,
      child: content,
    );
  }

  void _clearText() {
    if (_textController.text.isEmpty) return;
    _textController.clear();
    widget.onChanged?.call('');
  }

  void _handleCancelPressed() {
    _clearText();
    _focusNode.unfocus();
    widget.onCancelled?.call();
  }

  void _handleSubmitPressed() {
    widget.onSubmitted?.call(_textController.text);
  }

  double _fieldHeightForLines(
    double lineHeight,
    int lines,
    double verticalPadding,
  ) {
    return lineHeight * lines + (verticalPadding * 2);
  }

  double _resolvedActionIconSize(double? requestedSize) {
    final baseSize = requestedSize ?? 16.0;
    return baseSize.clamp(8.0, _kAccessorySize - 4.0).toDouble();
  }

  bool _textFitsOnSingleLine({
    required double maxWidth,
    required double minFieldHeight,
    required TextStyle textStyle,
    required StrutStyle strutStyle,
  }) {
    if (_isSearchMode || !_showsSendButton) {
      return false;
    }

    final text = _textController.text;
    if (text.isEmpty || text.contains('\n')) {
      return !text.contains('\n');
    }

    if (!maxWidth.isFinite || maxWidth <= 0) {
      return true;
    }

    final trailingWidth =
        math.max(
          0.0,
          minFieldHeight - (_kSendButtonOuterInset * 2) + _kSendButtonSizeBoost,
        ) +
        12.0;
    final textStartPadding = _kFieldHorizontalPadding;
    final textEndPadding = 4.0;
    final availableTextWidth =
        maxWidth - textStartPadding - textEndPadding - trailingWidth;
    if (availableTextWidth <= 0) {
      return false;
    }

    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      strutStyle: strutStyle,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 2,
    )..layout(maxWidth: availableTextWidth);

    return !painter.didExceedMaxLines;
  }

  List<Map<String, dynamic>> _encodeTraillingActions(
    List<CNTextFieldAction> actions,
  ) {
    return actions
        .take(2)
        .map((action) {
          final icon = action.icon;
          final iconData = icon.icon;
          return <String, dynamic>{
            'iconDataCodePoint': iconData?.codePoint,
            'iconDataFontFamily': iconData?.fontFamily,
            'iconDataFontPackage': iconData?.fontPackage,
            'iconDataMatchTextDirection': iconData?.matchTextDirection ?? false,
            'iconDataColor': resolveColorToArgb(icon.color, context),
            'iconDataSize': icon.size,
            'iconDataFill': icon.fill,
            'iconDataWeight': icon.weight,
            'iconDataGrade': icon.grade,
            'iconDataOpticalSize': icon.opticalSize,
          };
        })
        .toList(growable: false);
  }

  String _traillingActionsSignature(List<CNTextFieldAction> actions) {
    return actions
        .take(2)
        .map((action) {
          final icon = action.icon;
          final iconData = icon.icon;
          return [
            iconData?.codePoint,
            iconData?.fontFamily,
            iconData?.fontPackage,
            iconData?.matchTextDirection,
            resolveColorToArgb(icon.color, context),
            icon.size,
            icon.fill,
            icon.weight,
            icon.grade,
            icon.opticalSize,
          ].map((value) => value?.toString() ?? 'null').join('|');
        })
        .join('||');
  }
}

class _AccessoryButton extends StatelessWidget {
  const _AccessoryButton({
    required this.onPressed,
    required this.child,
    this.foregroundColor,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final buttonChild = SizedBox.square(
      dimension: _CNTextFieldState._kAccessorySize,
      child: IconTheme.merge(
        data: IconThemeData(color: foregroundColor),
        child: Center(child: child),
      ),
    );

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size.square(_CNTextFieldState._kAccessorySize),
      onPressed: onPressed,
      child: buttonChild,
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.diameter,
    required this.backgroundColor,
    required this.onPressed,
  });

  static const double _kIconSize = 16.0;

  final double diameter;
  final Color backgroundColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final resolvedDiameter = math.max(0.0, diameter);
    return SizedBox.square(
      dimension: resolvedDiameter,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              CupertinoIcons.arrow_up,
              color: CupertinoColors.white,
              size: _kIconSize,
            ),
          ),
        ),
      ),
    );
  }
}

/// Deprecated compatibility wrapper for [CNTextField].
@Deprecated('Use CNTextField.search or CNTextField.chat instead.')
class CNSearchBar extends StatelessWidget {
  /// Creates a deprecated compatibility wrapper.
  const CNSearchBar({
    super.key,
    this.text = '',
    this.onChanged,
    this.onSubmitted,
    this.onCancelled,
    this.onTap,
    this.placeholder,
    this.enabled = true,
    this.showsSearchIcon = true,
    this.showsCancelButton = false,
    this.traillingActions = const [],
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.height = 44.0,
    this.maxLines = 1,
    this.tint,
    this.backgroundColor,
    this.fieldBackgroundColor,
    this.sendButtonBackgroundColor,
  });

  /// Initial text value.
  final String text;

  /// Called when the text changes due to user interaction.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits the current value.
  final ValueChanged<String>? onSubmitted;

  /// Called when the cancel action is triggered.
  final VoidCallback? onCancelled;

  /// Called when the field is tapped.
  final VoidCallback? onTap;

  /// Placeholder text.
  final String? placeholder;

  /// Whether the control is interactive.
  final bool enabled;

  /// Whether the deprecated wrapper should build in search mode.
  final bool showsSearchIcon;

  /// Whether to show the cancel button.
  final bool showsCancelButton;

  /// Trailing actions for the field.
  final List<CNSearchBarAction> traillingActions;

  /// External controller for the text value.
  final TextEditingController? controller;

  /// External focus node for the field.
  final FocusNode? focusNode;

  /// Whether the field should request focus automatically.
  final bool autofocus;

  /// Minimum visual height of the field.
  final double height;

  /// Deprecated max lines input kept for compatibility.
  final int maxLines;

  /// Accent color.
  final Color? tint;

  /// Optional container background color.
  final Color? backgroundColor;

  /// Optional field background color.
  final Color? fieldBackgroundColor;

  /// Optional send button background color for chat mode.
  final Color? sendButtonBackgroundColor;

  @override
  Widget build(BuildContext context) {
    if (showsSearchIcon) {
      return CNTextField.search(
        key: key,
        text: text,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onCancelled: onCancelled,
        onTap: onTap,
        placeholder: placeholder,
        enabled: enabled,
        showsCancelButton: showsCancelButton,
        actions: traillingActions,
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        height: height,
        tint: tint,
        backgroundColor: backgroundColor,
        fieldBackgroundColor: fieldBackgroundColor,
      );
    }

    return CNTextField.chat(
      key: key,
      text: text,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onCancelled: onCancelled,
      onTap: onTap,
      placeholder: placeholder,
      enabled: enabled,
      actions: traillingActions,
      sendButtonBackgroundColor: sendButtonBackgroundColor,
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      height: height,
      tint: tint,
      backgroundColor: backgroundColor,
      fieldBackgroundColor: fieldBackgroundColor,
    );
  }
}
