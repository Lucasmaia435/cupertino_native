import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../channel/params.dart';
import '../style/sf_symbol.dart';

/// Immutable data describing a single tab bar item.
class CNTabBarItem {
  /// Creates a tab bar item description.
  const CNTabBarItem({
    this.label,
    this.icon,
    this.iconData,
    this.iconDataSize,
  })  : assert(
          icon == null || iconData == null,
          'Use either icon (CNSymbol) or iconData (IconData), not both.',
        ),
        assert(
          icon == null || iconDataSize == null,
          'iconDataSize can only be used with iconData.',
        ),
        assert(
          iconData != null || iconDataSize == null,
          'iconDataSize requires iconData.',
        );

  /// Optional tab item label.
  final String? label;

  /// Optional SF Symbol for the item.
  final CNSymbol? icon;

  /// Optional Flutter [IconData] for the item.
  ///
  /// This allows using icon fonts such as `CupertinoIcons` and `Icons`.
  final IconData? iconData;

  /// Icon size used when [iconData] is provided.
  final double? iconDataSize;
}

/// A Cupertino-native tab bar. Uses native UITabBar/NSTabView style visuals.
class CNTabBar extends StatefulWidget {
  /// Creates a Cupertino-native tab bar.
  const CNTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.tint,
    this.backgroundColor,
    this.iconSize,
    this.height,
    this.split = false,
    this.rightCount = 1,
    this.shrinkCentered = true,
    this.splitSpacing = 8.0,
  });

  /// Items to display in the tab bar.
  final List<CNTabBarItem> items;

  /// The index of the currently selected item.
  final int currentIndex;

  /// Called when the user selects a new item.
  final ValueChanged<int> onTap;

  /// Accent/tint color.
  final Color? tint;

  /// Background color for the bar.
  final Color? backgroundColor;

  /// Default icon size when item icon does not specify one.
  final double? iconSize;

  /// Fixed height; if null uses intrinsic height reported by native view.
  final double? height;

  /// When true, splits items between left and right sections.
  final bool split;

  /// How many trailing items to pin right when [split] is true.
  final int rightCount; // how many trailing items to pin right when split
  /// When true, centers the split groups more tightly.
  final bool shrinkCentered;

  /// Gap between left/right halves when split.
  final double splitSpacing; // gap between left/right halves when split

  @override
  State<CNTabBar> createState() => _CNTabBarState();
}

class _CNTabBarState extends State<CNTabBar> {
  MethodChannel? _channel;
  int? _lastIndex;
  int? _lastTint;
  int? _lastBg;
  bool? _lastIsDark;
  double? _intrinsicHeight;
  double? _intrinsicWidth;
  List<String>? _lastLabels;
  List<String>? _lastSymbols;
  List<int?>? _lastIconCodePoints;
  List<String?>? _lastIconFontFamilies;
  List<String?>? _lastIconFontPackages;
  List<bool>? _lastIconMatchTextDirections;
  List<double?>? _lastSizes;
  bool? _lastSplit;
  int? _lastRightCount;
  double? _lastSplitSpacing;

  bool get _isDark => CupertinoTheme.of(context).brightness == Brightness.dark;
  Color? get _effectiveTint =>
      widget.tint ?? CupertinoTheme.of(context).primaryColor;
  double? _effectiveItemIconSize(CNTabBarItem item) =>
      item.icon?.size ?? item.iconDataSize ?? widget.iconSize;

  @override
  void didUpdateWidget(covariant CNTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPropsToNativeIfNeeded();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!(defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS)) {
      // Simple Flutter fallback using CupertinoTabBar for non-Apple platforms.
      return SizedBox(
        height: widget.height,
        child: CupertinoTabBar(
          items: [
            for (final item in widget.items)
              BottomNavigationBarItem(
                icon: Icon(
                  item.iconData ?? CupertinoIcons.circle,
                  size: _effectiveItemIconSize(item),
                ),
                label: item.label,
              ),
          ],
          currentIndex: widget.currentIndex,
          onTap: widget.onTap,
          backgroundColor: widget.backgroundColor,
          inactiveColor: CupertinoColors.inactiveGray,
          activeColor: widget.tint ?? CupertinoTheme.of(context).primaryColor,
        ),
      );
    }

    final labels = widget.items.map((e) => e.label ?? '').toList();
    final symbols = widget.items.map((e) => e.icon?.name ?? '').toList();
    final iconCodePoints =
        widget.items.map((e) => e.iconData?.codePoint).toList();
    final iconFontFamilies =
        widget.items.map((e) => e.iconData?.fontFamily).toList();
    final iconFontPackages =
        widget.items.map((e) => e.iconData?.fontPackage).toList();
    final iconMatchTextDirections = widget.items
        .map((e) => e.iconData?.matchTextDirection ?? false)
        .toList();
    final sizes = widget.items.map((e) => _effectiveItemIconSize(e)).toList();
    final colors = widget.items
        .map((e) => resolveColorToArgb(e.icon?.color, context))
        .toList();

    final creationParams = <String, dynamic>{
      'labels': labels,
      'sfSymbols': symbols,
      'iconDataCodePoints': iconCodePoints,
      'iconDataFontFamilies': iconFontFamilies,
      'iconDataFontPackages': iconFontPackages,
      'iconDataMatchTextDirections': iconMatchTextDirections,
      'sfSymbolSizes': sizes,
      'sfSymbolColors': colors,
      'selectedIndex': widget.currentIndex,
      'isDark': _isDark,
      'split': widget.split,
      'rightCount': widget.rightCount,
      'splitSpacing': widget.splitSpacing,
      'style': encodeStyle(context, tint: _effectiveTint)
        ..addAll({
          if (widget.backgroundColor != null)
            'backgroundColor': resolveColorToArgb(
              widget.backgroundColor,
              context,
            ),
        }),
    };

    final viewType = 'CupertinoNativeTabBar';
    final platformView = defaultTargetPlatform == TargetPlatform.iOS
        ? UiKitView(
            viewType: viewType,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onCreated,
          )
        : AppKitView(
            viewType: viewType,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onCreated,
          );

    final h = widget.height ?? _intrinsicHeight ?? 50.0;
    if (!widget.split && widget.shrinkCentered) {
      final w = _intrinsicWidth;
      return SizedBox(height: h, width: w, child: platformView);
    }
    return SizedBox(height: h, child: platformView);
  }

  void _onCreated(int id) {
    final ch = MethodChannel('CupertinoNativeTabBar_$id');
    _channel = ch;
    ch.setMethodCallHandler(_onMethodCall);
    _lastIndex = widget.currentIndex;
    _lastTint = resolveColorToArgb(_effectiveTint, context);
    _lastBg = resolveColorToArgb(widget.backgroundColor, context);
    _lastIsDark = _isDark;
    _requestIntrinsicSize();
    _cacheItems();
    _lastSplit = widget.split;
    _lastRightCount = widget.rightCount;
    _lastSplitSpacing = widget.splitSpacing;
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'valueChanged') {
      final args = call.arguments as Map?;
      final idx = (args?['index'] as num?)?.toInt();
      if (idx != null && idx != _lastIndex) {
        widget.onTap(idx);
        _lastIndex = idx;
      }
    }
    return null;
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    // Capture theme-dependent values before awaiting
    final idx = widget.currentIndex;
    final tint = resolveColorToArgb(_effectiveTint, context);
    final bg = resolveColorToArgb(widget.backgroundColor, context);
    if (_lastIndex != idx) {
      await ch.invokeMethod('setSelectedIndex', {'index': idx});
      _lastIndex = idx;
    }

    final style = <String, dynamic>{};
    if (_lastTint != tint && tint != null) {
      style['tint'] = tint;
      _lastTint = tint;
    }
    if (_lastBg != bg && bg != null) {
      style['backgroundColor'] = bg;
      _lastBg = bg;
    }
    if (style.isNotEmpty) {
      await ch.invokeMethod('setStyle', style);
    }

    // Items update (for hot reload or dynamic changes)
    final labels = widget.items.map((e) => e.label ?? '').toList();
    final symbols = widget.items.map((e) => e.icon?.name ?? '').toList();
    final iconCodePoints =
        widget.items.map((e) => e.iconData?.codePoint).toList();
    final iconFontFamilies =
        widget.items.map((e) => e.iconData?.fontFamily).toList();
    final iconFontPackages =
        widget.items.map((e) => e.iconData?.fontPackage).toList();
    final iconMatchTextDirections = widget.items
        .map((e) => e.iconData?.matchTextDirection ?? false)
        .toList();
    final sizes = widget.items.map((e) => _effectiveItemIconSize(e)).toList();
    if (_listSignature(_lastLabels) != _listSignature(labels) ||
        _listSignature(_lastSymbols) != _listSignature(symbols) ||
        _listSignature(_lastIconCodePoints) != _listSignature(iconCodePoints) ||
        _listSignature(_lastIconFontFamilies) !=
            _listSignature(iconFontFamilies) ||
        _listSignature(_lastIconFontPackages) !=
            _listSignature(iconFontPackages) ||
        _listSignature(_lastIconMatchTextDirections) !=
            _listSignature(iconMatchTextDirections) ||
        _listSignature(_lastSizes) != _listSignature(sizes)) {
      await ch.invokeMethod('setItems', {
        'labels': labels,
        'sfSymbols': symbols,
        'iconDataCodePoints': iconCodePoints,
        'iconDataFontFamilies': iconFontFamilies,
        'iconDataFontPackages': iconFontPackages,
        'iconDataMatchTextDirections': iconMatchTextDirections,
        'sfSymbolSizes': sizes,
        'selectedIndex': widget.currentIndex,
      });
      _lastLabels = labels;
      _lastSymbols = symbols;
      _lastIconCodePoints = iconCodePoints;
      _lastIconFontFamilies = iconFontFamilies;
      _lastIconFontPackages = iconFontPackages;
      _lastIconMatchTextDirections = iconMatchTextDirections;
      _lastSizes = sizes;
      // Re-measure width in case content changed
      _requestIntrinsicSize();
    }

    // Layout updates (split / insets)
    if (_lastSplit != widget.split ||
        _lastRightCount != widget.rightCount ||
        _lastSplitSpacing != widget.splitSpacing) {
      await ch.invokeMethod('setLayout', {
        'split': widget.split,
        'rightCount': widget.rightCount,
        'splitSpacing': widget.splitSpacing,
        'selectedIndex': widget.currentIndex,
      });
      _lastSplit = widget.split;
      _lastRightCount = widget.rightCount;
      _lastSplitSpacing = widget.splitSpacing;
      _requestIntrinsicSize();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightnessIfNeeded();
    _syncPropsToNativeIfNeeded();
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

  void _cacheItems() {
    _lastLabels = widget.items.map((e) => e.label ?? '').toList();
    _lastSymbols = widget.items.map((e) => e.icon?.name ?? '').toList();
    _lastIconCodePoints =
        widget.items.map((e) => e.iconData?.codePoint).toList();
    _lastIconFontFamilies =
        widget.items.map((e) => e.iconData?.fontFamily).toList();
    _lastIconFontPackages =
        widget.items.map((e) => e.iconData?.fontPackage).toList();
    _lastIconMatchTextDirections = widget.items
        .map((e) => e.iconData?.matchTextDirection ?? false)
        .toList();
    _lastSizes = widget.items.map((e) => _effectiveItemIconSize(e)).toList();
  }

  String _listSignature(List<dynamic>? values) {
    if (values == null) return '';
    return values.map((value) => value?.toString() ?? 'null').join('|');
  }

  Future<void> _requestIntrinsicSize() async {
    if (widget.height != null) return;
    final ch = _channel;
    if (ch == null) return;
    try {
      final size = await ch.invokeMethod<Map>('getIntrinsicSize');
      final h = (size?['height'] as num?)?.toDouble();
      final w = (size?['width'] as num?)?.toDouble();
      if (!mounted) return;
      setState(() {
        if (h != null && h > 0) _intrinsicHeight = h;
        if (w != null && w > 0) _intrinsicWidth = w;
      });
    } catch (_) {}
  }
}
