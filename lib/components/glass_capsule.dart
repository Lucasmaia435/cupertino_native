import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../channel/params.dart';
import '../channel/platform_view_modal_visibility.dart';
import '../style/sf_symbol.dart';

/// One entry in a [CNGlassCapsuleItem.menu]: the overflow control's native
/// pull-down menu.
class CNGlassCapsuleMenuEntry {
  /// Creates a menu entry.
  const CNGlassCapsuleMenuEntry({required this.id, required this.title, this.icon});

  /// Reported back through [CNGlassCapsule.onMenuTap].
  final int id;

  /// Text shown for this entry.
  final String title;

  /// Optional SF Symbol shown before the title.
  final CNSymbol? icon;
}

/// One control inside a [CNGlassCapsule].
class CNGlassCapsuleItem {
  /// Creates a glass capsule item. Provide one of [icon], [flutterIcon],
  /// [image] or [title].
  const CNGlassCapsuleItem({
    this.icon,
    this.selectedIcon,
    this.flutterIcon,
    this.image,
    this.title,
    this.label,
    this.tint,
    this.badgeCount,
    this.menu,
  }) : assert(
         (icon == null ? 0 : 1) + (flutterIcon == null ? 0 : 1) + (image == null ? 0 : 1) <= 1,
         'Use one of icon (CNSymbol), flutterIcon (Icon) or image (ImageProvider).',
       );

  /// SF Symbol shown as this item's glyph.
  final CNSymbol? icon;

  /// SF Symbol shown instead of [icon] while this item is selected. Falls
  /// back to [icon] when null.
  final CNSymbol? selectedIcon;

  /// A Flutter [Icon] shown as this item's glyph instead of an SF Symbol —
  /// for a Material icon, or a custom icon font, that has no SF Symbol
  /// equivalent. Rendered natively from the icon's codepoint and font, the
  /// same way [flutterIcon] works on `CNTabBarItem`, so it inherits the
  /// capsule's selection tint like an SF Symbol would.
  final Icon? flutterIcon;

  /// A picture (asset, file, or network image) shown as a round avatar
  /// instead of an SF Symbol.
  final ImageProvider? image;

  /// Text shown when neither [icon] nor [image] is set.
  final String? title;

  /// Accessibility label and, for the overflow control's own entries, the
  /// name of an item that moved into it. Falls back to [title].
  final String? label;

  /// Per-item tint, overriding the capsule's [CNGlassCapsule.tint].
  final Color? tint;

  /// Badge count shown at this item's corner. Values over 99 show as "99+".
  final int? badgeCount;

  /// When set, tapping the item opens a native pull-down menu of these
  /// entries instead of reporting a tap: the overflow control of a trailing
  /// bar of items that did not fit elsewhere.
  final List<CNGlassCapsuleMenuEntry>? menu;

  /// The name to show or speak for this item: [label], else [title].
  String? get effectiveLabel => label ?? title;

  String? _extractAsset() {
    final image = this.image;
    if (image is AssetImage) return image.assetName;
    return null;
  }

  String? _extractFile() {
    final image = this.image;
    if (image is FileImage) return image.file.path;
    return null;
  }

  String? _extractNetwork() {
    final image = this.image;
    if (image is NetworkImage) return image.url;
    return null;
  }

  Map<String, dynamic> _toNativeMap(BuildContext context) => <String, dynamic>{
    if (icon != null) 'symbol': icon!.name,
    if (selectedIcon != null) 'selectedSymbol': selectedIcon!.name,
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
    if (_extractAsset() case final asset?) 'asset': asset,
    if (_extractFile() case final file?) 'file': file,
    if (_extractNetwork() case final network?) 'network': network,
    if (title != null) 'title': title,
    if (effectiveLabel != null) 'label': effectiveLabel,
    if (tint != null) 'tint': resolveColorToArgb(tint, context),
    if (badgeCount != null && badgeCount! > 0) 'badge': badgeCount,
    if (menu != null)
      'menu': [
        for (final entry in menu!)
          {
            'id': entry.id,
            'title': entry.title,
            if (entry.icon != null) 'symbol': entry.icon!.name,
          },
      ],
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CNGlassCapsuleItem &&
        other.icon?.name == icon?.name &&
        other.selectedIcon?.name == selectedIcon?.name &&
        other.flutterIcon?.icon == flutterIcon?.icon &&
        other.flutterIcon?.fill == flutterIcon?.fill &&
        other.flutterIcon?.weight == flutterIcon?.weight &&
        other.flutterIcon?.grade == flutterIcon?.grade &&
        other.flutterIcon?.opticalSize == flutterIcon?.opticalSize &&
        other.image == image &&
        other.title == title &&
        other.label == label &&
        other.tint == tint &&
        other.badgeCount == badgeCount &&
        listEquals(
          other.menu?.map((e) => e.id).toList(),
          menu?.map((e) => e.id).toList(),
        );
  }

  @override
  int get hashCode => Object.hash(
    icon?.name,
    selectedIcon?.name,
    flutterIcon?.icon,
    image,
    title,
    label,
    tint,
    badgeCount,
  );
}

/// A vertical Liquid Glass capsule holding a column of icon buttons: the
/// shape iOS 26 gives each group of toolbar items, and the tab bar, in the
/// trailing bar on a folding iPhone. With [selectedIndex] set it behaves as
/// a tab bar and highlights that item with a sliding selection pill.
class CNGlassCapsule extends StatefulWidget {
  /// Creates a Cupertino-native glass capsule.
  const CNGlassCapsule({
    super.key,
    required this.items,
    required this.onTap,
    this.onMenuTap,
    this.selectedIndex,
    this.inset = 0,
    this.tint,
  });

  /// Items shown top to bottom.
  final List<CNGlassCapsuleItem> items;

  /// Called with the tapped item's index.
  final ValueChanged<int> onTap;

  /// Called with the [CNGlassCapsuleMenuEntry.id] chosen from an item's menu.
  final ValueChanged<int>? onMenuTap;

  /// Index of the selected item. When set, this capsule behaves as a tab bar
  /// with a selection highlight; when null, it is a plain group of buttons.
  final int? selectedIndex;

  /// Space kept free above the first and below the last item.
  final double inset;

  /// Tint of the selected tab, or of every item when there is no selection.
  final Color? tint;

  /// Width of every item, matching the diameter iOS 26 uses on its own bar.
  static const double width = 48;

  /// Height of a capsule of [count] toolbar items.
  static double actionsHeight(int count) => 48.0 + (count - 1) * 52.0;

  /// Height of a tab capsule of [count] tabs, and the matching [inset].
  static double tabsHeight(int count) => tabsInset * 2 + count * 50.0;

  /// The [inset] a tab capsule of [tabsHeight] uses.
  static const double tabsInset = 6;

  @override
  State<CNGlassCapsule> createState() => _CNGlassCapsuleState();
}

class _CNGlassCapsuleState extends State<CNGlassCapsule>
    with CNPlatformViewModalVisibility<CNGlassCapsule> {
  MethodChannel? _channel;
  String? _lastParamsSignature;

  bool get _isDark => CupertinoTheme.of(context).brightness == Brightness.dark;

  @override
  MethodChannel? get visibilityChannel => _channel;

  Map<String, dynamic> _params(BuildContext context) => <String, dynamic>{
    'items': widget.items.map((i) => i._toNativeMap(context)).toList(),
    if (widget.selectedIndex != null) 'selectedIndex': widget.selectedIndex,
    'inset': widget.inset,
    'isDark': _isDark,
    if (widget.tint != null) 'tint': resolveColorToArgb(widget.tint, context),
  };

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CNGlassCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncIfNeeded();
  }

  Future<void> _syncIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final params = _params(context);
    final signature = params.toString();
    if (_lastParamsSignature == signature) return;
    _lastParamsSignature = signature;
    await ch.invokeMethod('update', params);
  }

  @override
  Widget build(BuildContext context) {
    if (!(defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS)) {
      return _buildFallback(context);
    }

    trackPlatformViewModalVisibility();

    final params = _params(context);
    _lastParamsSignature ??= params.toString();

    const viewType = 'CupertinoNativeGlassCapsule';
    return defaultTargetPlatform == TargetPlatform.iOS
        ? UiKitView(
            viewType: viewType,
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onCreated,
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          )
        : AppKitView(
            viewType: viewType,
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onCreated,
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
  }

  Widget _buildFallback(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final tint = widget.tint ?? CupertinoTheme.of(context).primaryColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.systemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(CNGlassCapsule.width / 2),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: widget.inset),
        child: Column(
          children: [
            for (var i = 0; i < widget.items.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onTap(i),
                  child: Center(
                    child: IconTheme.merge(
                      data: IconThemeData(
                        color: i == widget.selectedIndex ? tint : label,
                      ),
                      child: widget.items[i].icon != null
                          ? Icon(CupertinoIcons.circle, color: label, size: 20)
                          : Text(
                              widget.items[i].title ??
                                  widget.items[i].icon?.name ??
                                  widget.items[i].label ??
                                  '',
                              style: TextStyle(fontSize: 10, color: label),
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onCreated(int id) {
    final ch = MethodChannel('CupertinoNativeGlassCapsule_$id');
    _channel = ch;
    ch.setMethodCallHandler(_onMethodCall);
    syncPlatformViewModalVisibility();
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onItemTapped':
        final args = call.arguments as Map?;
        final index = (args?['index'] as num?)?.toInt();
        if (index != null && index >= 0 && index < widget.items.length) {
          widget.onTap(index);
        }
        break;
      case 'onMenuItemTapped':
        final args = call.arguments as Map?;
        final id = (args?['id'] as num?)?.toInt();
        if (id != null) widget.onMenuTap?.call(id);
        break;
    }
    return null;
  }
}
