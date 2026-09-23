import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../channel/params.dart';
import '../channel/platform_view_modal_visibility.dart';
import '../style/sf_symbol.dart';

/// Spacing inserted after a [CNToolbarAction] in a [CNToolbar].
enum CNToolbarActionSpacer {
  /// No spacer.
  none,

  /// A small fixed space, grouping items within the same section.
  fixed,

  /// A flexible space that separates item groups (e.g. left vs. right).
  flexible,
}

/// Describes a single action button shown in a [CNToolbar].
class CNToolbarAction {
  /// Creates a toolbar action. Provide [icon], [flutterIcon] or [text].
  const CNToolbarAction({
    this.icon,
    this.flutterIcon,
    this.text,
    this.label,
    required this.onPressed,
    this.tint,
    this.prominent = false,
    this.spacerAfter = CNToolbarActionSpacer.none,
  }) : assert(
         icon != null || flutterIcon != null || text != null,
         'Provide icon, flutterIcon or text.',
       ),
       assert(
         icon == null || flutterIcon == null,
         'Use either icon (CNSymbol) or flutterIcon (Icon), not both.',
       );

  /// SF Symbol shown as the action's glyph.
  final CNSymbol? icon;

  /// A Flutter [Icon] shown as the action's glyph instead of an SF Symbol —
  /// for a Material icon, or a custom icon font, that has no SF Symbol
  /// equivalent. Rendered natively from the icon's codepoint and font, the
  /// same way [flutterIcon] works on `CNTabBarItem`.
  final Icon? flutterIcon;

  /// Text shown when neither [icon] nor [flutterIcon] is set.
  final String? text;

  /// Accessibility label and the name shown if this action overflows into a
  /// menu. Falls back to [text] when omitted.
  final String? label;

  /// Called when the action is tapped.
  final VoidCallback onPressed;

  /// Per-action tint color, overriding the toolbar's [CNToolbar.tint].
  final Color? tint;

  /// Whether to draw this action with a prominent (tinted glass) background.
  final bool prominent;

  /// Spacer drawn immediately after this action.
  final CNToolbarActionSpacer spacerAfter;

  /// The name to show or speak for this action: [label], else [text].
  String? get effectiveLabel => label ?? text;

  Map<String, dynamic> _toNativeMap(BuildContext context) => {
    if (icon != null) 'icon': icon!.name,
    if (flutterIcon?.icon case final iconData?) ...{
      'iconCodePoint': iconData.codePoint,
      if (iconData.fontFamily != null) 'iconFontFamily': iconData.fontFamily,
      if (iconData.fontPackage != null) 'iconFontPackage': iconData.fontPackage,
      if (flutterIcon!.size != null) 'iconSize': flutterIcon!.size,
      if (flutterIcon!.fill != null) 'iconFill': flutterIcon!.fill,
      if (flutterIcon!.weight != null) 'iconWeight': flutterIcon!.weight,
      if (flutterIcon!.grade != null) 'iconGrade': flutterIcon!.grade,
      if (flutterIcon!.opticalSize != null) 'iconOpticalSize': flutterIcon!.opticalSize,
    },
    if (text != null) 'title': text,
    if (effectiveLabel != null) 'label': effectiveLabel,
    'spacerAfter': spacerAfter.index,
    if (prominent) 'prominent': true,
    if (tint != null) 'tint': resolveColorToArgb(tint, context),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CNToolbarAction &&
        other.icon?.name == icon?.name &&
        other.flutterIcon?.icon == flutterIcon?.icon &&
        other.flutterIcon?.fill == flutterIcon?.fill &&
        other.flutterIcon?.weight == flutterIcon?.weight &&
        other.flutterIcon?.grade == flutterIcon?.grade &&
        other.flutterIcon?.opticalSize == flutterIcon?.opticalSize &&
        other.text == text &&
        other.label == label &&
        other.tint == tint &&
        other.prominent == prominent &&
        other.spacerAfter == spacerAfter;
  }

  @override
  int get hashCode =>
      Object.hash(icon?.name, flutterIcon?.icon, text, label, tint, prominent, spacerAfter);
}

/// A Cupertino-native top toolbar. Uses a native UINavigationBar (iOS) or a
/// translucent NSVisualEffectView bar (macOS) with Liquid Glass action
/// buttons, matching iOS 26's fixed toolbar look.
class CNToolbar extends StatefulWidget {
  /// Creates a Cupertino-native toolbar.
  const CNToolbar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.tint,
    this.height = 44.0,
    this.showsBackgroundGradient = true,
  });

  /// Title text shown centered in the bar. Ignored when [titleWidget] is set.
  final String? title;

  /// Custom widget overlaid at the title position, replacing [title].
  final Widget? titleWidget;

  /// Widget overlaid at the leading edge (e.g. a back button).
  final Widget? leading;

  /// Trailing action buttons.
  final List<CNToolbarAction>? actions;

  /// Tint applied to action glyphs.
  final Color? tint;

  /// Height of the bar's content area, excluding the top safe area inset.
  final double height;

  /// Whether the native view draws a readability gradient behind the bar as
  /// content scrolls underneath it.
  final bool showsBackgroundGradient;

  @override
  State<CNToolbar> createState() => _CNToolbarState();
}

class _CNToolbarState extends State<CNToolbar>
    with CNPlatformViewModalVisibility<CNToolbar> {
  MethodChannel? _channel;
  bool? _lastIsDark;
  int? _lastTint;
  String? _lastTitle;
  List<CNToolbarAction>? _lastActions;

  bool get _isDark => CupertinoTheme.of(context).brightness == Brightness.dark;

  @override
  MethodChannel? get visibilityChannel => _channel;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CNToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPropsToNativeIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightnessIfNeeded();
    _syncPropsToNativeIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    if (!(defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS)) {
      return _buildFallback(context);
    }

    trackPlatformViewModalVisibility();

    final creationParams = <String, dynamic>{
      if (widget.title != null && widget.titleWidget == null)
        'title': widget.title,
      if (widget.actions != null && widget.actions!.isNotEmpty)
        'actions': widget.actions!.map((a) => a._toNativeMap(context)).toList(),
      'isDark': _isDark,
      if (!widget.showsBackgroundGradient) 'showsGradient': false,
      'style': encodeStyle(context, tint: widget.tint),
    };

    const viewType = 'CupertinoNativeToolbar';
    final platformView = defaultTargetPlatform == TargetPlatform.iOS
        ? UiKitView(
            viewType: viewType,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onCreated,
            hitTestBehavior: PlatformViewHitTestBehavior.translucent,
          )
        : AppKitView(
            viewType: viewType,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onCreated,
            hitTestBehavior: PlatformViewHitTestBehavior.translucent,
          );

    return SizedBox(
      height: widget.height + topInset,
      child: Stack(
        children: [
          Positioned.fill(child: platformView),
          if (widget.leading != null)
            Positioned(
              left: 16,
              top: topInset,
              bottom: 0,
              child: Align(alignment: Alignment.center, child: widget.leading),
            ),
          if (widget.titleWidget != null)
            Positioned(
              left: 0,
              right: 0,
              top: topInset,
              bottom: 0,
              child: Center(child: widget.titleWidget),
            ),
        ],
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    return CupertinoNavigationBar(
      middle: widget.titleWidget ??
          (widget.title != null ? Text(widget.title!) : null),
      leading: widget.leading,
      trailing: widget.actions != null && widget.actions!.isNotEmpty
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final action in widget.actions!)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: action.onPressed,
                    child: action.icon != null
                        ? Icon(CupertinoIcons.circle, size: action.icon!.size)
                        : Text(action.text ?? ''),
                  ),
              ],
            )
          : null,
    );
  }

  void _onCreated(int id) {
    final ch = MethodChannel('CupertinoNativeToolbar_$id');
    _channel = ch;
    ch.setMethodCallHandler(_onMethodCall);
    syncPlatformViewModalVisibility();
    _lastIsDark = _isDark;
    _lastTint = resolveColorToArgb(widget.tint, context);
    _lastTitle = widget.title;
    _lastActions = widget.actions == null ? null : List.of(widget.actions!);
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'actionTapped') {
      final args = call.arguments as Map?;
      final index = (args?['index'] as num?)?.toInt();
      final actions = widget.actions;
      if (index != null && actions != null && index >= 0 && index < actions.length) {
        actions[index].onPressed();
      }
    }
    return null;
  }

  Future<void> _syncBrightnessIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final isDark = _isDark;
    if (_lastIsDark != isDark) {
      await ch.invokeMethod('setBrightness', {'isDark': isDark});
      _lastIsDark = isDark;
    }
  }

  bool _actionsEqual(List<CNToolbarAction>? a, List<CNToolbarAction>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;

    // Capture everything that reads `context` up front: nothing below may
    // touch it again once the first `await` below has run.
    final title = widget.title;
    final actionsPayload = widget.actions != null && widget.actions!.isNotEmpty
        ? widget.actions!.map((a) => a._toNativeMap(context)).toList()
        : null;
    final tint = resolveColorToArgb(widget.tint, context);

    if (widget.title != _lastTitle && widget.titleWidget == null && title != null) {
      await ch.invokeMethod('setTitle', {'title': title});
      _lastTitle = widget.title;
    }

    if (!_actionsEqual(_lastActions, widget.actions)) {
      await ch.invokeMethod('setActions', {
        if (actionsPayload != null) 'actions': actionsPayload,
      });
      _lastActions = widget.actions == null ? null : List.of(widget.actions!);
    }

    if (_lastTint != tint) {
      await ch.invokeMethod('setStyle', {'tint': tint});
      _lastTint = tint;
    }
  }
}
