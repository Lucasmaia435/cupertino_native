import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../channel/params.dart';
import '../channel/platform_view_modal_visibility.dart';
import '../style/sf_symbol.dart';
import '../style/button_style.dart';

const Duration _kCNButtonImplicitAnimationDuration = Duration(
  milliseconds: 340,
);
const Curve _kCNButtonImplicitAnimationCurve = Curves.easeInCubic;

/// A Cupertino-native push button.
///
/// Embeds a native UIButton/NSButton for authentic visuals and behavior on
/// iOS and macOS. Falls back to [CupertinoButton] on other platforms.
class CNButton extends StatefulWidget {
  /// Creates a text button variant of [CNButton].
  const CNButton({
    super.key,
    required this.label,
    this.onPressed,
    this.enabled = true,
    this.tint,
    this.backgroundColor,
    this.backgroundGradient,
    this.height = 32.0,
    this.shrinkWrap = false,
    this.style = CNButtonStyle.plain,
  }) : icon = null,
       flutterIcon = null,
       width = null,
       round = false;

  /// Creates a round, icon-only variant of [CNButton].
  const CNButton.icon({
    super.key,
    this.icon,
    this.flutterIcon,
    this.onPressed,
    this.enabled = true,
    this.tint,
    this.backgroundColor,
    this.backgroundGradient,
    double size = 44.0,
    this.style = CNButtonStyle.glass,
  }) : assert(
         icon == null || flutterIcon == null,
         'Use either icon (CNSymbol) or flutterIcon (Icon), not both.',
       ),
       assert(
         icon != null || flutterIcon != null,
         'Provide icon (CNSymbol) or flutterIcon (Icon).',
       ),
       label = null,
       round = true,
       width = size,
       height = size,
       shrinkWrap = false,
       super();

  /// Button text (null in icon mode).
  final String? label; // null in icon mode
  /// Button icon using SF Symbols.
  final CNSymbol? icon;

  /// Button icon using Flutter [Icon].
  ///
  /// This allows variable-font properties like fill/weight.
  final Icon? flutterIcon;

  /// Callback when pressed.
  final VoidCallback? onPressed;

  /// Whether the control is interactive and tappable.
  final bool enabled;

  /// Accent/tint color.
  final Color? tint;

  /// Optional background color for the native button body.
  final Color? backgroundColor;

  /// Optional linear gradient rendered behind the native button body.
  ///
  /// When both [backgroundColor] and [backgroundGradient] are provided,
  /// [backgroundGradient] takes precedence.
  final LinearGradient? backgroundGradient;

  /// Control height.
  final double height;

  /// Fixed width used in icon/round mode.
  final double? width; // fixed when round/icon mode
  /// If true, sizes the control to its intrinsic width.
  final bool shrinkWrap;

  /// Visual style to apply.
  final CNButtonStyle style;

  /// Whether the icon variant (round) is used.
  final bool round;

  /// Whether this instance is configured as the icon variant.
  bool get isIcon => icon != null || flutterIcon != null;

  @override
  State<CNButton> createState() => _CNButtonState();
}

class _CNButtonState extends State<CNButton>
    with CNPlatformViewModalVisibility<CNButton> {
  MethodChannel? _channel;
  bool? _lastIsDark;
  int? _lastTint;
  int? _lastBackground;
  String? _lastTitle;
  String? _lastIconName;
  int? _lastIconCodePoint;
  String? _lastIconFontFamily;
  String? _lastIconFontPackage;
  bool? _lastIconMatchTextDirection;
  double? _lastIconSize;
  int? _lastIconColor;
  double? _lastIconFill;
  double? _lastIconWeight;
  double? _lastIconGrade;
  double? _lastIconOpticalSize;
  double? _intrinsicWidth;
  CNButtonStyle? _lastStyle;
  String? _lastBackgroundGradientSignature;
  Offset? _downPosition;
  bool _pressed = false;

  bool get _isDark => CupertinoTheme.of(context).brightness == Brightness.dark;
  IconData? get _flutterIconData => widget.flutterIcon?.icon;
  double? get _effectiveIconSize =>
      widget.icon?.size ?? widget.flutterIcon?.size;
  int? get _effectiveIconColor => resolveColorToArgb(
    widget.icon?.color ?? widget.flutterIcon?.color,
    context,
  );
  double? get _effectiveIconFill => widget.flutterIcon?.fill;
  double? get _effectiveIconWeight => widget.flutterIcon?.weight;
  double? get _effectiveIconGrade => widget.flutterIcon?.grade;
  double? get _effectiveIconOpticalSize => widget.flutterIcon?.opticalSize;

  Color? get _effectiveTint =>
      widget.tint ?? CupertinoTheme.of(context).primaryColor;

  @override
  MethodChannel? get visibilityChannel => _channel;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CNButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPropsToNativeIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightnessIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundGradient = _encodeBackgroundGradient();

    if (!(defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS)) {
      return _buildFallbackButton();
    }

    trackPlatformViewModalVisibility();

    const viewType = 'CupertinoNativeButton';

    final creationParams = <String, dynamic>{
      if (widget.label != null) 'buttonTitle': widget.label,
      if (widget.icon != null) 'buttonIconName': widget.icon!.name,
      if (_effectiveIconSize != null) 'buttonIconSize': _effectiveIconSize,
      if (_effectiveIconColor != null) 'buttonIconColor': _effectiveIconColor,
      if (widget.icon?.mode != null)
        'buttonIconRenderingMode': widget.icon!.mode!.name,
      if (widget.icon?.paletteColors != null)
        'buttonIconPaletteColors': widget.icon!.paletteColors!
            .map((c) => resolveColorToArgb(c, context))
            .toList(),
      if (widget.icon?.gradient != null)
        'buttonIconGradientEnabled': widget.icon!.gradient,
      if (_flutterIconData != null)
        'buttonIconDataCodePoint': _flutterIconData!.codePoint,
      if (_flutterIconData != null)
        'buttonIconDataFontFamily': _flutterIconData!.fontFamily,
      if (_flutterIconData != null)
        'buttonIconDataFontPackage': _flutterIconData!.fontPackage,
      if (_flutterIconData != null)
        'buttonIconDataMatchTextDirection':
            _flutterIconData!.matchTextDirection,
      if (_effectiveIconFill != null) 'buttonIconDataFill': _effectiveIconFill,
      if (_effectiveIconWeight != null)
        'buttonIconDataWeight': _effectiveIconWeight,
      if (_effectiveIconGrade != null)
        'buttonIconDataGrade': _effectiveIconGrade,
      if (_effectiveIconOpticalSize != null)
        'buttonIconDataOpticalSize': _effectiveIconOpticalSize,
      if (widget.isIcon) 'round': true,
      'buttonStyle': widget.style.name,
      'enabled': (widget.enabled && widget.onPressed != null),
      'isDark': _isDark,
      'style': encodeStyle(context, tint: _effectiveTint)
        ..addAll({
          if (widget.backgroundColor != null)
            'backgroundColor': resolveColorToArgb(
              widget.backgroundColor,
              context,
            ),
          if (backgroundGradient != null)
            'backgroundGradient': backgroundGradient,
        }),
    };

    final platformView = defaultTargetPlatform == TargetPlatform.iOS
        ? UiKitView(
            viewType: viewType,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onCreated,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              // Forward taps to native; let Flutter keep drags for scrolling.
              Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
            },
          )
        : AppKitView(
            viewType: viewType,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onCreated,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
            },
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedWidth = constraints.hasBoundedWidth;
        final preferIntrinsic = widget.shrinkWrap || !hasBoundedWidth;
        double? width;
        if (widget.isIcon) {
          width = widget.width ?? widget.height;
        } else if (preferIntrinsic) {
          width = _intrinsicWidth ?? 80.0;
        }
        return Listener(
          onPointerDown: (e) {
            _downPosition = e.position;
            _setPressed(true);
          },
          onPointerMove: (e) {
            final start = _downPosition;
            if (start != null && _pressed) {
              final moved = (e.position - start).distance;
              if (moved > kTouchSlop) {
                _setPressed(false);
              }
            }
          },
          onPointerUp: (_) {
            _setPressed(false);
            _downPosition = null;
          },
          onPointerCancel: (_) {
            _setPressed(false);
            _downPosition = null;
          },
          child: AnimatedContainer(
            duration: _kCNButtonImplicitAnimationDuration,
            curve: _kCNButtonImplicitAnimationCurve,
            height: widget.height,
            width: width,
            child: platformView,
          ),
        );
      },
    );
  }

  void _onCreated(int id) {
    final ch = MethodChannel('CupertinoNativeButton_$id');
    _channel = ch;
    ch.setMethodCallHandler(_onMethodCall);
    syncPlatformViewModalVisibility();
    _lastTint = resolveColorToArgb(_effectiveTint, context);
    _lastBackground = resolveColorToArgb(widget.backgroundColor, context);
    _lastBackgroundGradientSignature = _backgroundGradientSignature(
      _encodeBackgroundGradient(),
    );
    _lastIsDark = _isDark;
    _lastTitle = widget.label;
    _lastIconName = widget.icon?.name;
    _lastIconCodePoint = _flutterIconData?.codePoint;
    _lastIconFontFamily = _flutterIconData?.fontFamily;
    _lastIconFontPackage = _flutterIconData?.fontPackage;
    _lastIconMatchTextDirection = _flutterIconData?.matchTextDirection;
    _lastIconSize = _effectiveIconSize;
    _lastIconColor = _effectiveIconColor;
    _lastIconFill = _effectiveIconFill;
    _lastIconWeight = _effectiveIconWeight;
    _lastIconGrade = _effectiveIconGrade;
    _lastIconOpticalSize = _effectiveIconOpticalSize;
    _lastStyle = widget.style;
    if (!widget.isIcon) {
      _requestIntrinsicSize();
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'pressed':
        if (widget.enabled && widget.onPressed != null) {
          widget.onPressed!();
        }
        break;
    }
    return null;
  }

  Future<void> _requestIntrinsicSize() async {
    final ch = _channel;
    if (ch == null) return;
    try {
      final size = await ch.invokeMethod<Map>('getIntrinsicSize');
      final w = (size?['width'] as num?)?.toDouble();
      if (w != null && mounted) {
        setState(() => _intrinsicWidth = w);
      }
    } catch (_) {}
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final tint = resolveColorToArgb(_effectiveTint, context);
    final background = resolveColorToArgb(widget.backgroundColor, context);
    final backgroundGradient = _encodeBackgroundGradient();
    final backgroundGradientSignature = _backgroundGradientSignature(
      backgroundGradient,
    );
    final preIconName = widget.icon?.name;
    final preIconCodePoint = _flutterIconData?.codePoint;
    final preIconFontFamily = _flutterIconData?.fontFamily;
    final preIconFontPackage = _flutterIconData?.fontPackage;
    final preIconMatchTextDirection = _flutterIconData?.matchTextDirection;
    final preIconSize = _effectiveIconSize;
    final preIconColor = _effectiveIconColor;
    final preIconFill = _effectiveIconFill;
    final preIconWeight = _effectiveIconWeight;
    final preIconGrade = _effectiveIconGrade;
    final preIconOpticalSize = _effectiveIconOpticalSize;

    final styleUpdates = <String, dynamic>{};
    if (_lastTint != tint && tint != null) {
      styleUpdates['tint'] = tint;
      _lastTint = tint;
    }
    if (_lastBackground != background) {
      styleUpdates['backgroundColor'] = background;
      _lastBackground = background;
    }
    if (_lastBackgroundGradientSignature != backgroundGradientSignature) {
      styleUpdates['backgroundGradient'] = backgroundGradient;
      _lastBackgroundGradientSignature = backgroundGradientSignature;
    }
    if (_lastStyle != widget.style) {
      styleUpdates['buttonStyle'] = widget.style.name;
      _lastStyle = widget.style;
    }
    if (styleUpdates.isNotEmpty) {
      await ch.invokeMethod('setStyle', styleUpdates);
    }
    // Enabled state
    await ch.invokeMethod('setEnabled', {
      'enabled': (widget.enabled && widget.onPressed != null),
    });
    if (_lastTitle != widget.label && widget.label != null) {
      await ch.invokeMethod('setButtonTitle', {'title': widget.label});
      _lastTitle = widget.label;
      _requestIntrinsicSize();
    }

    if (widget.isIcon) {
      final iconName = preIconName;
      final iconSize = preIconSize;
      final iconColor = preIconColor;
      final updates = <String, dynamic>{};
      if (iconName != null &&
          (_lastIconName != iconName || _lastIconCodePoint != null)) {
        updates['buttonIconName'] = iconName;
        _lastIconName = iconName;
        _lastIconCodePoint = null;
        _lastIconFontFamily = null;
        _lastIconFontPackage = null;
        _lastIconMatchTextDirection = null;
      }
      if (_lastIconSize != iconSize) {
        updates['buttonIconSize'] = iconSize;
        _lastIconSize = iconSize;
      }
      if (_lastIconColor != iconColor) {
        updates['buttonIconColor'] = iconColor;
        _lastIconColor = iconColor;
      }
      final iconDataChanged =
          _lastIconCodePoint != preIconCodePoint ||
          _lastIconFontFamily != preIconFontFamily ||
          _lastIconFontPackage != preIconFontPackage ||
          _lastIconMatchTextDirection != preIconMatchTextDirection ||
          _lastIconName != null;
      final iconDataStyleChanged =
          _lastIconFill != preIconFill ||
          _lastIconWeight != preIconWeight ||
          _lastIconGrade != preIconGrade ||
          _lastIconOpticalSize != preIconOpticalSize;
      if ((iconDataChanged || iconDataStyleChanged) &&
          preIconCodePoint != null) {
        updates['buttonIconDataCodePoint'] = preIconCodePoint;
        updates['buttonIconDataFontFamily'] = preIconFontFamily;
        updates['buttonIconDataFontPackage'] = preIconFontPackage;
        updates['buttonIconDataMatchTextDirection'] =
            preIconMatchTextDirection ?? false;
        updates['buttonIconDataFill'] = preIconFill;
        updates['buttonIconDataWeight'] = preIconWeight;
        updates['buttonIconDataGrade'] = preIconGrade;
        updates['buttonIconDataOpticalSize'] = preIconOpticalSize;
        _lastIconCodePoint = preIconCodePoint;
        _lastIconFontFamily = preIconFontFamily;
        _lastIconFontPackage = preIconFontPackage;
        _lastIconMatchTextDirection = preIconMatchTextDirection;
        _lastIconFill = preIconFill;
        _lastIconWeight = preIconWeight;
        _lastIconGrade = preIconGrade;
        _lastIconOpticalSize = preIconOpticalSize;
        _lastIconName = null;
      }
      if (widget.icon?.mode != null) {
        updates['buttonIconRenderingMode'] = widget.icon!.mode!.name;
      }
      if (widget.icon?.paletteColors != null) {
        updates['buttonIconPaletteColors'] = widget.icon!.paletteColors!
            .map((c) => resolveColorToArgb(c, context))
            .toList();
      }
      if (widget.icon?.gradient != null) {
        updates['buttonIconGradientEnabled'] = widget.icon!.gradient;
      }
      if (updates.isNotEmpty) {
        await ch.invokeMethod('setButtonIcon', updates);
      }
    }
  }

  Future<void> _syncBrightnessIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    // Capture context-derived values before any awaits
    final isDark = _isDark;
    final tint = resolveColorToArgb(_effectiveTint, context);
    final background = resolveColorToArgb(widget.backgroundColor, context);
    final backgroundGradient = _encodeBackgroundGradient();
    final backgroundGradientSignature = _backgroundGradientSignature(
      backgroundGradient,
    );
    if (_lastIsDark != isDark) {
      // Update _lastIsDark before the first await so that any concurrent call
      // from a second didChangeDependencies (possible during parent rebuilds)
      // sees the updated value and exits early — preventing a race where the
      // second call skips the icon re-send because the first already updated
      // _lastIconName, leaving the native side without an icon after its own
      // setBrightness reset.
      _lastIsDark = isDark;
      // Invalidate all icon tracking so _syncPropsToNativeIfNeeded re-sends
      // the full icon state after the native view resets on setBrightness.
      _lastIconCodePoint = null;
      _lastIconName = null;
      _lastIconFontFamily = null;
      _lastIconFontPackage = null;
      _lastIconMatchTextDirection = null;
      _lastIconSize = null;
      _lastIconColor = null;
      _lastIconFill = null;
      _lastIconWeight = null;
      _lastIconGrade = null;
      _lastIconOpticalSize = null;
      await ch.invokeMethod('setBrightness', {'isDark': isDark});
      // Re-sync icon explicitly: didUpdateWidget is not guaranteed to fire
      // after a system theme change (it only fires on parent widget rebuild),
      // so we cannot rely on it to trigger the re-send in release/profile mode.
      if (mounted) await _syncPropsToNativeIfNeeded();
    }
    // Also propagate theme-driven tint changes (e.g., accent color changes)
    final styleUpdates = <String, dynamic>{};
    if (_lastTint != tint && tint != null) {
      styleUpdates['tint'] = tint;
      _lastTint = tint;
    }
    if (_lastBackground != background) {
      styleUpdates['backgroundColor'] = background;
      _lastBackground = background;
    }
    if (_lastBackgroundGradientSignature != backgroundGradientSignature) {
      styleUpdates['backgroundGradient'] = backgroundGradient;
      _lastBackgroundGradientSignature = backgroundGradientSignature;
    }
    if (styleUpdates.isNotEmpty) {
      await ch.invokeMethod('setStyle', styleUpdates);
    }
  }

  Map<String, dynamic>? _encodeBackgroundGradient() {
    final gradient = widget.backgroundGradient;
    if (gradient == null) return null;

    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final begin = gradient.begin.resolve(textDirection);
    final end = gradient.end.resolve(textDirection);

    return <String, dynamic>{
      'colors': gradient.colors
          .map((color) => resolveColorToArgb(color, context)!)
          .toList(),
      if (gradient.stops != null) 'stops': gradient.stops,
      'begin': <String, double>{'x': begin.x, 'y': begin.y},
      'end': <String, double>{'x': end.x, 'y': end.y},
    };
  }

  String? _backgroundGradientSignature(Map<String, dynamic>? gradient) {
    if (gradient == null) return null;
    return jsonEncode(gradient);
  }

  Widget _buildFallbackButton() {
    final width = widget.isIcon && widget.round
        ? (widget.width ?? widget.height)
        : null;

    return AnimatedContainer(
      duration: _kCNButtonImplicitAnimationDuration,
      curve: _kCNButtonImplicitAnimationCurve,
      height: widget.height,
      width: width,
      decoration: BoxDecoration(
        color: widget.backgroundGradient == null
            ? widget.backgroundColor
            : null,
        gradient: widget.backgroundGradient,
        shape: widget.isIcon && widget.round
            ? BoxShape.circle
            : BoxShape.rectangle,
        borderRadius: widget.isIcon && widget.round
            ? null
            : BorderRadius.circular(widget.height / 2),
      ),
      child: CupertinoButton(
        color: const Color(0x00000000),
        padding: widget.isIcon
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onPressed: (widget.enabled && widget.onPressed != null)
            ? widget.onPressed
            : null,
        child: widget.isIcon
            ? (widget.flutterIcon != null
                  ? Icon(
                      widget.flutterIcon!.icon ?? CupertinoIcons.ellipsis,
                      size: _effectiveIconSize,
                      color: widget.flutterIcon!.color,
                      fill: widget.flutterIcon!.fill,
                      weight: widget.flutterIcon!.weight,
                      grade: widget.flutterIcon!.grade,
                      opticalSize: widget.flutterIcon!.opticalSize,
                      shadows: widget.flutterIcon!.shadows,
                    )
                  : Icon(CupertinoIcons.ellipsis, size: _effectiveIconSize))
            : Text(widget.label ?? ''),
      ),
    );
  }

  Future<void> _setPressed(bool pressed) async {
    final ch = _channel;
    if (ch == null) return;
    if (_pressed == pressed) return;
    _pressed = pressed;
    try {
      await ch.invokeMethod('setPressed', {'pressed': pressed});
    } catch (_) {}
  }
}
