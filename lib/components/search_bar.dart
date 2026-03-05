import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../channel/params.dart';

/// Trailing action rendered by the native search bar.
class CNSearchBarAction {
  /// Creates a trailing action.
  const CNSearchBarAction({
    required this.icon,
    required this.onPressed,
  });

  /// Icon rendered natively.
  final Icon icon;

  /// Called when the action is pressed.
  final VoidCallback onPressed;
}

/// A Cupertino-native search bar rendered by the host platform.
///
/// On iOS/macOS this embeds `UISearchBar`/`NSSearchField` through platform
/// views. On unsupported platforms it falls back to
/// [CupertinoSearchTextField].
class CNSearchBar extends StatefulWidget {
  /// Creates a Cupertino-native search bar.
  const CNSearchBar({
    super.key,
    this.text = '',
    this.onChanged,
    this.onSubmitted,
    this.onCancelled,
    this.onTap,
    this.placeholder,
    this.enabled = true,
    this.showsCancelButton = false,
    this.traillingActions = const [],
    this.controller,
    this.height = 56.0,
    this.tint,
    this.backgroundColor,
    this.fieldBackgroundColor,
  }) : assert(
          traillingActions.length <= 2,
          'CNSearchBar supports at most two traillingActions.',
        );

  /// Current text displayed by the search field.
  final String text;

  /// Called when the text changes due to user interaction.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits the search action.
  final ValueChanged<String>? onSubmitted;

  /// Called when the native cancel action is triggered.
  final VoidCallback? onCancelled;

  /// Called when the native field is tapped or receives focus.
  final VoidCallback? onTap;

  /// Optional placeholder string.
  final String? placeholder;

  /// Whether the control is interactive.
  final bool enabled;

  /// Whether to display the cancel button (mainly relevant on iOS).
  final bool showsCancelButton;

  /// Optional trailing actions rendered by the native search field.
  ///
  /// Supports up to two actions.
  final List<CNSearchBarAction> traillingActions;

  /// Optional text controller. When provided, [text] is ignored.
  final TextEditingController? controller;

  /// Visual height of the embedded platform view.
  final double height;

  /// Accent/tint color.
  final Color? tint;

  /// Optional background color for the whole control container.
  final Color? backgroundColor;

  /// Optional background color for the text field area.
  final Color? fieldBackgroundColor;

  @override
  State<CNSearchBar> createState() => _CNSearchBarState();
}

class _CNSearchBarState extends State<CNSearchBar> {
  MethodChannel? _channel;
  late final TextEditingController _fallbackController;
  TextEditingController? _observedController;
  bool _isApplyingNativeTextChange = false;

  String? _lastText;
  String? _lastPlaceholder;
  bool? _lastEnabled;
  bool? _lastShowsCancelButton;
  bool? _lastIsDark;
  int? _lastTint;
  int? _lastBackground;
  int? _lastFieldBackground;
  double? _lastHeight;
  String? _lastTraillingActionsSignature;

  TextEditingController get _textController =>
      widget.controller ?? _fallbackController;

  bool get _isDark => CupertinoTheme.of(context).brightness == Brightness.dark;

  Color? get _effectiveTint =>
      widget.tint ?? CupertinoTheme.of(context).primaryColor;

  double get _effectiveHeight {
    final min = defaultTargetPlatform == TargetPlatform.macOS ? 24.0 : 32.0;
    return widget.height.clamp(min, 240.0);
  }

  @override
  void initState() {
    super.initState();
    _fallbackController = TextEditingController(text: widget.text);
    _observeController(_textController);
  }

  @override
  void didUpdateWidget(covariant CNSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _unobserveController(oldWidget.controller ?? _fallbackController);
      _observeController(_textController);
    }
    _syncFallbackControllerIfNeeded();
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
    _fallbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!(defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS)) {
      return SizedBox(
        height: _effectiveHeight,
        child: CupertinoSearchTextField(
          controller: _textController,
          enabled: widget.enabled,
          placeholder: widget.placeholder,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          onSuffixTap: widget.onCancelled,
          onTap: widget.onTap,
        ),
      );
    }

    const viewType = 'CupertinoNativeSearchBar';
    final creationParams = <String, dynamic>{
      'text': _textController.text,
      'placeholder': widget.placeholder,
      'enabled': widget.enabled,
      'showsCancelButton': widget.showsCancelButton,
      'height': _effectiveHeight,
      'traillingActions': _encodeTraillingActions(widget.traillingActions),
      'isDark': _isDark,
      'style': encodeStyle(context, tint: _effectiveTint)
        ..addAll({
          if (widget.backgroundColor != null)
            'backgroundColor':
                resolveColorToArgb(widget.backgroundColor, context),
          if (widget.fieldBackgroundColor != null)
            'fieldBackgroundColor': resolveColorToArgb(
              widget.fieldBackgroundColor,
              context,
            ),
        }),
    };

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return SizedBox(
        height: _effectiveHeight,
        child: UiKitView(
          viewType: viewType,
          creationParamsCodec: const StandardMessageCodec(),
          creationParams: creationParams,
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
      );
    }

    return SizedBox(
      height: _effectiveHeight,
      child: AppKitView(
        viewType: viewType,
        creationParamsCodec: const StandardMessageCodec(),
        creationParams: creationParams,
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('CupertinoNativeSearchBar_$id');
    _channel = channel;
    channel.setMethodCallHandler(_onMethodCall);
    _cacheCurrentProps();
    // Force one trailing actions sync after attach; some native paths can
    // ignore creation params during first layout pass.
    _lastTraillingActionsSignature = null;
    _syncBrightnessIfNeeded();
    _syncPropsToNativeIfNeeded();
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
      case 'trailingActionPressed':
        final index = (args?['index'] as num?)?.toInt();
        if (index != null &&
            index >= 0 &&
            index < widget.traillingActions.length) {
          widget.traillingActions[index].onPressed();
        }
        break;
    }
    return null;
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

  void _onTextControllerChanged() {
    if (_isApplyingNativeTextChange) return;
    _syncTextToNativeIfNeeded();
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

  Future<void> _syncTextToNativeIfNeeded() async {
    final channel = _channel;
    if (channel == null) return;

    final text = _textController.text;
    if (_lastText == text) return;
    await channel.invokeMethod('setText', {'text': text});
    _lastText = text;
  }

  void _cacheCurrentProps() {
    _lastText = _textController.text;
    _lastPlaceholder = widget.placeholder;
    _lastEnabled = widget.enabled;
    _lastShowsCancelButton = widget.showsCancelButton;
    _lastIsDark = _isDark;
    _lastTint = resolveColorToArgb(_effectiveTint, context);
    _lastBackground = resolveColorToArgb(widget.backgroundColor, context);
    _lastFieldBackground =
        resolveColorToArgb(widget.fieldBackgroundColor, context);
    _lastHeight = _effectiveHeight;
    _lastTraillingActionsSignature =
        _traillingActionsSignature(widget.traillingActions);
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final channel = _channel;
    if (channel == null) return;

    final text = _textController.text;
    final placeholder = widget.placeholder;
    final enabled = widget.enabled;
    final showsCancelButton = widget.showsCancelButton;
    final height = _effectiveHeight;
    final tint = resolveColorToArgb(_effectiveTint, context);
    final bg = resolveColorToArgb(widget.backgroundColor, context);
    final fieldBg = resolveColorToArgb(widget.fieldBackgroundColor, context);
    final traillingActions = widget.traillingActions;
    final traillingActionsSignature =
        _traillingActionsSignature(traillingActions);

    if (_lastText != text) {
      await channel.invokeMethod('setText', {'text': text});
      _lastText = text;
    }

    if (_lastPlaceholder != placeholder) {
      await channel
          .invokeMethod('setPlaceholder', {'placeholder': placeholder});
      _lastPlaceholder = placeholder;
    }

    if (_lastEnabled != enabled) {
      await channel.invokeMethod('setEnabled', {'enabled': enabled});
      _lastEnabled = enabled;
    }

    if (_lastShowsCancelButton != showsCancelButton) {
      await channel.invokeMethod('setShowsCancelButton', {
        'showsCancelButton': showsCancelButton,
      });
      _lastShowsCancelButton = showsCancelButton;
    }

    if (_lastHeight != height) {
      await channel.invokeMethod('setHeight', {'height': height});
      _lastHeight = height;
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
    if (style.isNotEmpty) {
      await channel.invokeMethod('setStyle', style);
    }
  }

  List<Map<String, dynamic>> _encodeTraillingActions(
    List<CNSearchBarAction> actions,
  ) {
    return actions.take(2).map((action) {
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
    }).toList(growable: false);
  }

  String _traillingActionsSignature(List<CNSearchBarAction> actions) {
    return actions.take(2).map((action) {
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
    }).join('||');
  }

  Future<void> _syncBrightnessIfNeeded() async {
    final channel = _channel;
    if (channel == null) return;

    final isDark = _isDark;
    final tint = resolveColorToArgb(_effectiveTint, context);
    final bg = resolveColorToArgb(widget.backgroundColor, context);
    final fieldBg = resolveColorToArgb(widget.fieldBackgroundColor, context);

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
    if (style.isNotEmpty) {
      await channel.invokeMethod('setStyle', style);
    }
  }
}
