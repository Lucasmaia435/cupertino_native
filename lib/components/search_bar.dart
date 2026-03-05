import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../channel/params.dart';

/// Controller for [CNSearchBar] to perform imperative native actions.
class CNSearchBarController {
  MethodChannel? _channel;

  void _attach(MethodChannel channel) {
    _channel = channel;
  }

  void _detach() {
    _channel = null;
  }

  /// Updates the native text value.
  Future<void> setText(String text) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod('setText', {'text': text});
  }

  /// Updates the native enabled state.
  Future<void> setEnabled(bool enabled) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod('setEnabled', {'enabled': enabled});
  }

  /// Updates the native placeholder text.
  Future<void> setPlaceholder(String? placeholder) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod('setPlaceholder', {'placeholder': placeholder});
  }

  /// Shows or hides the native cancel button (iOS).
  Future<void> setShowsCancelButton(bool showsCancelButton) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod('setShowsCancelButton', {
      'showsCancelButton': showsCancelButton,
    });
  }

  /// Requests focus for the native search field.
  Future<void> focus() async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod('focus');
  }

  /// Removes focus from the native search field.
  Future<void> unfocus() async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod('unfocus');
  }
}

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
    required this.text,
    required this.onChanged,
    this.onSubmitted,
    this.onCancelled,
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
  final ValueChanged<String> onChanged;

  /// Called when the user submits the search action.
  final ValueChanged<String>? onSubmitted;

  /// Called when the native cancel action is triggered.
  final VoidCallback? onCancelled;

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

  /// Optional controller for imperative interactions.
  final CNSearchBarController? controller;

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

  CNSearchBarController? _internalController;

  CNSearchBarController get _controller =>
      widget.controller ?? (_internalController ??= CNSearchBarController());

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
  }

  @override
  void didUpdateWidget(covariant CNSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _controller._detach();
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
          controller: _fallbackController,
          enabled: widget.enabled,
          placeholder: widget.placeholder,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          onSuffixTap: widget.onCancelled,
        ),
      );
    }

    const viewType = 'CupertinoNativeSearchBar';
    final creationParams = <String, dynamic>{
      'text': widget.text,
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
    _controller._attach(channel);
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
          widget.onChanged(text);
          _lastText = text;
        }
        break;
      case 'submitted':
        final text = (args?['text'] as String?) ?? widget.text;
        widget.onSubmitted?.call(text);
        break;
      case 'cancelled':
        widget.onCancelled?.call();
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
    if (_fallbackController.text == widget.text) return;
    _fallbackController.value = TextEditingValue(
      text: widget.text,
      selection: TextSelection.collapsed(offset: widget.text.length),
      composing: TextRange.empty,
    );
  }

  void _cacheCurrentProps() {
    _lastText = widget.text;
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

    final text = widget.text;
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
