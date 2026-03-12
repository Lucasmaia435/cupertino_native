import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../channel/params.dart';

/// Layout configuration for [CNTextField].
class CNTextFieldLayout {
  /// Creates a layout configuration.
  const CNTextFieldLayout({
    this.height = 44.0,
    this.maxHeight = 240.0,
    this.maxVisibleLines = 1,
    this.borderRadius = 28.0,
    this.fieldHorizontalPadding = 16.0,
    this.fieldVerticalPadding = 8.0,
    this.textOpticalVerticalOffset = 1.5,
    this.accessoryGap = 8.0,
  });

  /// Minimum visual height of the field.
  final double height;

  /// Maximum visual height of the field before the text view scrolls.
  final double maxHeight;

  /// Maximum number of visible lines before the field starts scrolling.
  final int maxVisibleLines;

  /// Border radius applied to the field chrome.
  final double borderRadius;

  /// Horizontal padding inside the field.
  final double fieldHorizontalPadding;

  /// Vertical padding inside the field.
  final double fieldVerticalPadding;

  /// Small optical offset used to align text and accessories.
  final double textOpticalVerticalOffset;

  /// Gap reserved between the text and custom accessories.
  final double accessoryGap;
}

/// Visual styling for [CNTextField].
class CNTextFieldStyle {
  /// Creates a style configuration.
  const CNTextFieldStyle({
    this.tint,
    this.backgroundColor,
    this.fieldBackgroundColor,
    this.fieldOverlayColor,
    this.fieldBorderColor,
    this.placeholderColor,
    this.disabledOpacity = 0.6,
  });

  /// Accent/tint color.
  final Color? tint;

  /// Primary background color for the control.
  ///
  /// When [fieldBackgroundColor] is omitted, this color is also used as the
  /// field surface so the component tracks other native controls like
  /// [CNTabBar].
  final Color? backgroundColor;

  /// Optional explicit background color for the field surface.
  ///
  /// When provided, this overrides [backgroundColor] for the inner field
  /// chrome.
  final Color? fieldBackgroundColor;

  /// Optional overlay color applied on top of the field surface.
  final Color? fieldOverlayColor;

  /// Optional explicit border color.
  final Color? fieldBorderColor;

  /// Optional placeholder color.
  final Color? placeholderColor;

  /// Opacity used when the field is disabled.
  final double disabledOpacity;
}

/// A Cupertino-native text field rendered by the host platform.
///
/// Accessories are provided as regular Flutter widgets via [leading] and
/// [trailing]. Visibility and behavior are intentionally controlled by the
/// client widget tree, not by the component itself.
class CNTextField extends StatefulWidget {
  /// Creates a native text field with Flutter-driven accessories.
  const CNTextField({
    super.key,
    this.text = '',
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.placeholder,
    this.enabled = true,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.leading,
    this.trailing = const [],
    this.layout = const CNTextFieldLayout(),
    this.style = const CNTextFieldStyle(),
    this.textInputAction = TextInputAction.done,
    this.keyboardType = TextInputType.text,
  });

  /// Current text displayed by the field.
  final String text;

  /// Called when the text changes due to user interaction.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits through the text input system.
  final ValueChanged<String>? onSubmitted;

  /// Called when the field is tapped.
  final VoidCallback? onTap;

  /// Optional placeholder string.
  final String? placeholder;

  /// Whether the control is interactive.
  final bool enabled;

  /// Optional text controller. When provided, [text] is ignored.
  final TextEditingController? controller;

  /// Optional focus node for matching [CupertinoTextField] focus behavior.
  final FocusNode? focusNode;

  /// Whether the field should request focus when inserted into the tree.
  final bool autofocus;

  /// Optional leading accessory rendered inside the field chrome.
  final Widget? leading;

  /// Optional trailing accessories rendered inside the field chrome.
  final List<Widget> trailing;

  /// Layout configuration for the field.
  final CNTextFieldLayout layout;

  /// Visual styling configuration for the field.
  final CNTextFieldStyle style;

  /// Fallback text input action used on non-native platforms.
  final TextInputAction textInputAction;

  /// Fallback keyboard type used on non-native platforms.
  final TextInputType keyboardType;

  @override
  State<CNTextField> createState() => _CNTextFieldState();
}

class _CNTextFieldState extends State<CNTextField> {
  MethodChannel? _channel;
  late final TextEditingController _fallbackController;
  late final FocusNode _fallbackFocusNode;

  TextEditingController? _observedController;
  FocusNode? _observedFocusNode;

  bool _isApplyingNativeTextChange = false;
  bool _isApplyingNativeFocusChange = false;
  double? _reportedNativeHeight;
  double? _pendingNativeHeight;
  bool _hasScheduledNativeHeightCommit = false;
  double _leadingWidth = 0;
  double _leadingHeight = 0;
  double _trailingWidth = 0;
  double _trailingHeight = 0;
  double? _reportedFallbackFieldHeight;

  String? _lastText;
  String? _lastPlaceholder;
  bool? _lastEnabled;
  bool? _lastIsDark;
  bool? _lastFocusEnabled;
  String? _lastBehaviorSignature;
  String? _lastLayoutSignature;
  String? _lastStyleSignature;

  TextEditingController get _textController =>
      widget.controller ?? _fallbackController;

  FocusNode get _focusNode => widget.focusNode ?? _fallbackFocusNode;

  CNTextFieldLayout get _layout => widget.layout;

  CNTextFieldStyle get _style => widget.style;

  bool get _isDark => CupertinoTheme.of(context).brightness == Brightness.dark;

  bool get _isNativePlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  bool get _canInteractWithTextInput =>
      widget.enabled && _focusNode.canRequestFocus;

  Color get _effectiveTint =>
      _style.tint ?? CupertinoTheme.of(context).primaryColor;

  Color? get _effectiveFieldBackgroundColor =>
      _style.fieldBackgroundColor ?? _style.backgroundColor;

  double get _configuredMaxHeight =>
      math.max(_layout.height, _layout.maxHeight);

  double get _minimumHeight {
    final min = defaultTargetPlatform == TargetPlatform.macOS ? 28.0 : 36.0;
    return _layout.height.clamp(min, _configuredMaxHeight).toDouble();
  }

  double get _effectiveNativeHeight => (_reportedNativeHeight ?? _minimumHeight)
      .clamp(_minimumHeight, _configuredMaxHeight)
      .toDouble();

  int get _effectiveMaxVisibleLines => math.max(1, _layout.maxVisibleLines);

  bool get _hasLeadingAccessory => widget.leading != null;

  bool get _hasTrailingAccessories => widget.trailing.isNotEmpty;

  double get _leadingReservedWidth =>
      _hasLeadingAccessory ? _leadingWidth + _layout.accessoryGap : 0.0;

  double get _trailingReservedWidth =>
      _hasTrailingAccessories ? _trailingWidth + _layout.accessoryGap : 0.0;

  double _resolvedLineHeight(BuildContext context) {
    final themeTextStyle = CupertinoTheme.of(context).textTheme.textStyle;
    final defaultFontSize = defaultTargetPlatform == TargetPlatform.macOS
        ? 16.0
        : 17.0;
    final fontSize = themeTextStyle.fontSize ?? defaultFontSize;
    return fontSize * (themeTextStyle.height ?? 1.25);
  }

  double _resolvedTextVerticalPadding(BuildContext context) {
    final lineHeight = _resolvedLineHeight(context);
    return math.max(
      _layout.fieldVerticalPadding,
      (_minimumHeight - lineHeight) / 2,
    );
  }

  double _resolvedTextBottomPadding(BuildContext context) {
    final effectiveTextVerticalPadding = _resolvedTextVerticalPadding(context);
    return math.max(
      0.0,
      effectiveTextVerticalPadding - _layout.textOpticalVerticalOffset,
    );
  }

  double _accessoryLastLineTop(
    BuildContext context,
    double fieldHeight, {
    required double accessoryHeight,
  }) {
    const accessoryOpticalLift = 2.0;
    final bottomPadding = _resolvedTextBottomPadding(context);
    final lastLineBottom = fieldHeight - bottomPadding;
    final resolvedAccessoryHeight = accessoryHeight > 0
        ? accessoryHeight
        : _resolvedLineHeight(context);
    return math.max(
      0.0,
      lastLineBottom - resolvedAccessoryHeight - accessoryOpticalLift,
    );
  }

  double _leadingLastLineTop(BuildContext context, double fieldHeight) {
    return _accessoryLastLineTop(
      context,
      fieldHeight,
      accessoryHeight: _leadingHeight,
    );
  }

  double _trailingLastLineTop(BuildContext context, double fieldHeight) {
    return _accessoryLastLineTop(
      context,
      fieldHeight,
      accessoryHeight: _trailingHeight,
    );
  }

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
    final resolved = height
        .clamp(_minimumHeight, _configuredMaxHeight)
        .toDouble();
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

  String _jsonSignature(Map<String, dynamic> value) => jsonEncode(value);

  Color? _resolveDynamicColor(Color? color) {
    if (color == null) return null;
    return CupertinoDynamicColor.resolve(color, context);
  }

  Color _resolvedPlaceholderColor(BuildContext context) {
    final explicit = _resolveDynamicColor(_style.placeholderColor);
    if (explicit != null) return explicit;
    final base = CupertinoDynamicColor.resolve(
      CupertinoTheme.of(context).textTheme.textStyle.color ??
          CupertinoColors.label,
      context,
    );
    return base.withValues(alpha: _isDark ? 0.44 : 0.34);
  }

  Map<String, dynamic> _encodeBehavior() {
    return <String, dynamic>{
      'showsLeadingAccessory': false,
      'leadingAccessoryTriggersSubmit': false,
      'showsCancelButton': false,
      'clearButtonVisibility': 'never',
      'sendButtonVisibility': 'never',
      'trailingActionsVisibility': 'never',
      'trailingAccessoryOrder': const <String>[],
      'maxVisibleLines': _effectiveMaxVisibleLines,
    };
  }

  Map<String, dynamic> _encodeLayout() {
    return <String, dynamic>{
      'height': _layout.height,
      'maxHeight': _layout.maxHeight,
      'borderRadius': _layout.borderRadius,
      'fieldHorizontalPadding': _layout.fieldHorizontalPadding,
      'fieldVerticalPadding': _layout.fieldVerticalPadding,
      'textOpticalVerticalOffset': _layout.textOpticalVerticalOffset,
      'leadingReservedWidth': _leadingReservedWidth,
      'trailingReservedWidth': _trailingReservedWidth,
    };
  }

  Map<String, dynamic> _encodeStyle() {
    return encodeStyle(context, tint: _effectiveTint)..addAll(<String, dynamic>{
      'backgroundColor': resolveColorToArgb(_style.backgroundColor, context),
      'fieldBackgroundColor': resolveColorToArgb(
        _style.fieldBackgroundColor,
        context,
      ),
      'fieldOverlayColor': resolveColorToArgb(
        _style.fieldOverlayColor,
        context,
      ),
      'fieldBorderColor': resolveColorToArgb(_style.fieldBorderColor, context),
      'placeholderColor': resolveColorToArgb(_style.placeholderColor, context),
      'disabledOpacity': _style.disabledOpacity,
    });
  }

  void _cacheCurrentProps() {
    _lastText = _textController.text;
    _lastPlaceholder = widget.placeholder;
    _lastEnabled = widget.enabled;
    _lastIsDark = _isDark;
    _lastFocusEnabled = _canInteractWithTextInput;
    _lastBehaviorSignature = _jsonSignature(_encodeBehavior());
    _lastLayoutSignature = _jsonSignature(_encodeLayout());
    _lastStyleSignature = _jsonSignature(_encodeStyle());
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final channel = _channel;
    if (channel == null) return;

    final text = _textController.text;
    final placeholder = widget.placeholder;
    final enabled = widget.enabled;
    final focusEnabled = _canInteractWithTextInput;
    final behaviorSignature = _jsonSignature(_encodeBehavior());
    final layoutSignature = _jsonSignature(_encodeLayout());
    final styleSignature = _jsonSignature(_encodeStyle());

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

    if (_lastBehaviorSignature != behaviorSignature) {
      await channel.invokeMethod('setBehavior', {
        'behavior': _encodeBehavior(),
      });
      _lastBehaviorSignature = behaviorSignature;
    }

    if (_lastLayoutSignature != layoutSignature) {
      await channel.invokeMethod('setLayout', {'layout': _encodeLayout()});
      _lastLayoutSignature = layoutSignature;
      if ((_reportedNativeHeight ?? 0) < _minimumHeight && mounted) {
        setState(() {
          _reportedNativeHeight = _minimumHeight;
        });
      }
    }

    if (_lastStyleSignature != styleSignature) {
      await channel.invokeMethod('setStyle', _encodeStyle());
      _lastStyleSignature = styleSignature;
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
  }

  Future<void> _syncBrightnessIfNeeded() async {
    final channel = _channel;
    if (channel == null) return;

    final isDark = _isDark;
    if (_lastIsDark != isDark) {
      await channel.invokeMethod('setBrightness', {'isDark': isDark});
      _lastIsDark = isDark;
    }
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('CupertinoNativeSearchBar_$id');
    _channel = channel;
    channel.setMethodCallHandler(_onMethodCall);
    _cacheCurrentProps();
    _lastBehaviorSignature = null;
    _lastLayoutSignature = null;
    _lastStyleSignature = null;
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
      case 'tapped':
        widget.onTap?.call();
        break;
      case 'focusChanged':
        final focused = args?['focused'] == true;
        _applyNativeFocus(focused);
        break;
    }
    return null;
  }

  void _updateLeadingSize(Size size) {
    final width = size.width;
    final height = size.height;
    final widthChanged = (_leadingWidth - width).abs() >= 0.5;
    final heightChanged = (_leadingHeight - height).abs() >= 0.5;
    if (!widthChanged && !heightChanged) return;
    setState(() {
      _leadingWidth = width;
      _leadingHeight = height;
    });
    if (widthChanged) {
      _syncPropsToNativeIfNeeded();
    }
  }

  void _updateTrailingSize(Size size) {
    final width = size.width;
    final height = size.height;
    if ((_trailingWidth - width).abs() < 0.5 &&
        (_trailingHeight - height).abs() < 0.5) {
      return;
    }
    setState(() {
      _trailingWidth = width;
      _trailingHeight = height;
    });
    _syncPropsToNativeIfNeeded();
  }

  void _updateFallbackFieldSize(Size size) {
    final height = size.height;
    final currentHeight = _reportedFallbackFieldHeight ?? 0;
    if ((currentHeight - height).abs() < 0.5) return;
    setState(() {
      _reportedFallbackFieldHeight = height;
    });
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
      'focusEnabled': _canInteractWithTextInput,
      'isDark': _isDark,
      'behavior': _encodeBehavior(),
      'layout': _encodeLayout(),
      'style': _encodeStyle(),
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
        child: SizedBox(
          height: _effectiveNativeHeight,
          child: _buildFieldOverlay(context, child: platformView),
        ),
      ),
    );
  }

  Widget _buildFieldOverlay(BuildContext context, {required Widget child}) {
    final leading = widget.leading;
    final trailing = widget.trailing;
    final leadingInset = math.max(0.0, _layout.fieldHorizontalPadding - 4);
    final trailingInset = math.max(0.0, _layout.fieldHorizontalPadding - 2);

    return ClipRRect(
      borderRadius: BorderRadius.circular(_layout.borderRadius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fieldHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : _effectiveNativeHeight;
          final leadingTop = _leadingLastLineTop(context, fieldHeight);
          final trailingTop = _trailingLastLineTop(context, fieldHeight);

          return Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (leading != null)
                PositionedDirectional(
                  start: leadingInset,
                  top: leadingTop,
                  child: _SizeObserver(
                    onSize: _updateLeadingSize,
                    child: leading,
                  ),
                ),
              if (trailing.isNotEmpty)
                PositionedDirectional(
                  end: trailingInset,
                  top: trailingTop,
                  child: _SizeObserver(
                    onSize: _updateTrailingSize,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: trailing,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final effectiveTint = _effectiveTint;
    final canInteractWithTextInput =
        widget.enabled && _focusNode.canRequestFocus;

    if (!canInteractWithTextInput && _focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.unfocus();
        }
      });
    }

    final resolvedFieldBackground =
        _resolveDynamicColor(
          _effectiveFieldBackgroundColor ??
              _style.fieldOverlayColor ??
              CupertinoColors.systemGrey5,
        ) ??
        CupertinoDynamicColor.resolve(CupertinoColors.systemGrey5, context);
    final resolvedFieldOverlayColor = _resolveDynamicColor(
      _style.fieldOverlayColor,
    );
    final resolvedFieldBorderColor = _resolveDynamicColor(
      _style.fieldBorderColor,
    );
    final resolvedPlaceholderColor = _resolvedPlaceholderColor(context);
    final resolvedDisabledOpacity = _style.disabledOpacity.clamp(0.0, 1.0);

    final textStyle = theme.textTheme.textStyle.copyWith(
      fontSize: 17,
      height: 1.25,
    );
    final strutStyle = StrutStyle(
      fontSize: textStyle.fontSize,
      height: textStyle.height,
      forceStrutHeight: true,
    );
    final lineHeight = _resolvedLineHeight(context);
    final effectiveTextVerticalPadding = _resolvedTextVerticalPadding(context);
    final effectiveTextTopPadding =
        effectiveTextVerticalPadding + _layout.textOpticalVerticalOffset;
    final effectiveTextBottomPadding = _resolvedTextBottomPadding(context);
    final minFieldHeight = math
        .max(
          36.0,
          math.max(
            _layout.height,
            _fieldHeightForLines(lineHeight, 1, effectiveTextVerticalPadding),
          ),
        )
        .toDouble();
    final maxFieldHeight = math
        .max(
          minFieldHeight,
          _fieldHeightForLines(
            lineHeight,
            _effectiveMaxVisibleLines,
            effectiveTextVerticalPadding,
          ),
        )
        .toDouble();

    Widget content = AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: minFieldHeight,
          maxHeight: maxFieldHeight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_layout.borderRadius),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fieldHeight =
                  (_reportedFallbackFieldHeight ?? minFieldHeight)
                      .clamp(minFieldHeight, maxFieldHeight)
                      .toDouble();
              final leadingTop = _leadingLastLineTop(context, fieldHeight);
              final trailingTop = _trailingLastLineTop(context, fieldHeight);

              return _SizeObserver(
                onSize: _updateFallbackFieldSize,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: resolvedFieldBackground,
                        borderRadius: BorderRadius.circular(
                          _layout.borderRadius,
                        ),
                        border: resolvedFieldBorderColor == null
                            ? null
                            : Border.all(color: resolvedFieldBorderColor),
                      ),
                    ),
                    if (resolvedFieldOverlayColor != null)
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: resolvedFieldOverlayColor,
                            borderRadius: BorderRadius.circular(
                              _layout.borderRadius,
                            ),
                          ),
                        ),
                      ),
                    CupertinoTheme(
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
                          enableInteractiveSelection: canInteractWithTextInput,
                          padding: EdgeInsetsDirectional.only(
                            start:
                                _layout.fieldHorizontalPadding +
                                _leadingReservedWidth,
                            end:
                                _layout.fieldHorizontalPadding +
                                _trailingReservedWidth,
                            top: effectiveTextTopPadding,
                            bottom: effectiveTextBottomPadding,
                          ),
                          minLines: 1,
                          maxLines: _effectiveMaxVisibleLines == 1 ? 1 : null,
                          keyboardType: widget.keyboardType,
                          textInputAction: widget.textInputAction,
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
                    if (_hasLeadingAccessory)
                      PositionedDirectional(
                        start: math.max(
                          0.0,
                          _layout.fieldHorizontalPadding - 4,
                        ),
                        top: leadingTop,
                        child: _SizeObserver(
                          onSize: _updateLeadingSize,
                          child: widget.leading!,
                        ),
                      ),
                    if (_hasTrailingAccessories)
                      PositionedDirectional(
                        end: math.max(0.0, _layout.fieldHorizontalPadding - 2),
                        top: trailingTop,
                        child: _SizeObserver(
                          onSize: _updateTrailingSize,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: widget.trailing,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: widget.enabled ? 1 : resolvedDisabledOpacity,
      child: content,
    );
  }

  double _fieldHeightForLines(
    double lineHeight,
    int lines,
    double verticalPadding,
  ) {
    return lineHeight * lines + (verticalPadding * 2);
  }
}

class _SizeObserver extends SingleChildRenderObjectWidget {
  const _SizeObserver({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSizeObserver(onSize);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSizeObserver renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeObserver extends RenderProxyBox {
  _RenderSizeObserver(this.onSize);

  ValueChanged<Size> onSize;
  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _lastSize) return;
    _lastSize = size;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      onSize(size);
    });
  }
}
