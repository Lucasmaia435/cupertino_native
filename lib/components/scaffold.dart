import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:foldable/foldable.dart';

import '../style/button_style.dart';
import '../style/sf_symbol.dart';
import 'button.dart';
import 'glass_capsule.dart';
import 'tab_bar.dart';
import 'toolbar.dart';

/// Controls when a [CupertinoNativeScaffold]'s tab bar shrinks in response to
/// scrolling, matching iOS 26's `UITabBarController.tabBarMinimizeBehavior`.
enum CNTabBarMinimizeBehavior {
  /// Minimize on scroll down, expand on scroll up (the system default).
  automatic,

  /// Minimize only when scrolling down.
  onScrollDown,

  /// Minimize only when scrolling up.
  onScrollUp,

  /// Never minimize.
  never,
}

// MARK: - iPhone Duo layout

/// The edge of the window the system reserves for vertical controls on a
/// folding iPhone.
enum _CNDuoBarSide { left, right }

/// Layout decisions for a folding iPhone showing its trailing-strip pose:
/// the toolbar and tab bar move into a vertical bar on the edge the system
/// actually reserves, rather than a device- or size-class check. Ported from
/// the layout rules `foldable` documents for `ReservedRegion`/view padding.
abstract final class _CNDuoLayout {
  static const double barWidthFallback = 60.0;
  static const double bezelInset = 12.0;
  static const double statusClusterFallbackHeight = 170.0;
  static const double edgeMargin = 24.0;
  static const double regionGap = 11.0;

  /// Height of the title-only band shown at the top of the page in this pose.
  static const double titleBandHeight = 70.0;

  static _CNDuoBarSide? barSide(EdgeInsets viewPadding) {
    if (viewPadding.top != 0) return null;
    if (viewPadding.right > 0 && viewPadding.left == 0) {
      return _CNDuoBarSide.right;
    }
    if (viewPadding.left > 0 && viewPadding.right == 0) {
      return _CNDuoBarSide.left;
    }
    return null;
  }

  static bool isVerticalBarPose(EdgeInsets viewPadding) =>
      barSide(viewPadding) != null;

  static double stripWidth(EdgeInsets padding) {
    final inset = barSide(padding) == _CNDuoBarSide.left
        ? padding.left
        : padding.right;
    return inset > 0 ? inset : barWidthFallback;
  }

  static double bandWidth(EdgeInsets padding) => stripWidth(padding) + bezelInset;

  /// Free space to keep above and below the controls so they clear the
  /// camera/status cluster wherever the current rotation puts it.
  static ({double top, double bottom}) barInsets({
    required Size size,
    required EdgeInsets padding,
    required List<ReservedRegion> regions,
  }) {
    final strip = stripWidth(padding);
    final onLeft = barSide(padding) == _CNDuoBarSide.left;
    final stripStart = onLeft ? 0.0 : size.width - strip;
    final stripEnd = onLeft ? strip : size.width;

    final inStrip = regions.where(
      (r) =>
          r.kind == ReservedRegionKind.occlusion &&
          r.isActive &&
          r.bounds.right > stripStart &&
          r.bounds.left < stripEnd &&
          r.bounds.right <= size.width + 1 &&
          r.bounds.bottom <= size.height + 1,
    );

    double? top;
    double? bottom;
    for (final region in inStrip) {
      if (region.bounds.center.dy < size.height / 2) {
        if (top == null || region.bounds.bottom > top) top = region.bounds.bottom;
      } else {
        final room = size.height - region.bounds.top + regionGap;
        if (bottom == null || room > bottom) bottom = room;
      }
    }

    final unknown = inStrip.isEmpty;
    return (
      top: top ?? (unknown ? statusClusterFallbackHeight : edgeMargin),
      bottom: bottom ?? edgeMargin,
    );
  }
}

/// What sits behind the title in the duo pose: content scrolling underneath
/// is blurred and faded out towards the top, like the system's scroll-edge
/// effect, so the leading-aligned title never reads on top of a list row.
class _CNDuoTitleBackdrop extends StatelessWidget {
  const _CNDuoTitleBackdrop();

  @override
  Widget build(BuildContext context) {
    final base = CupertinoColors.systemBackground.resolveFrom(context);
    return IgnorePointer(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        maxHeight: _CNDuoLayout.titleBandHeight + 24,
        minHeight: _CNDuoLayout.titleBandHeight + 24,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.62, 1.0],
            colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          ).createShader(rect),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: ColoredBox(color: base.withValues(alpha: 0.82)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The page title as the duo pose shows it: at the leading edge rather than
/// centered, since the navigation controls live in the trailing bar.
class _CNDuoToolbarTitle extends StatelessWidget {
  const _CNDuoToolbarTitle({this.title, this.titleWidget});

  final String? title;
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final strip = _CNDuoLayout.stripWidth(viewPadding);
    final onLeft = _CNDuoLayout.barSide(viewPadding) == _CNDuoBarSide.left;
    return Padding(
      padding: EdgeInsets.only(
        left: 20 + (onLeft ? strip : 0),
        right: onLeft ? 20 : strip + 8,
        top: 26,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: titleWidget ??
            Text(
              title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
      ),
    );
  }
}

/// Space between the groups of controls in the duo vertical bar, as iOS 26
/// lays out its own trailing bar.
const double _kDuoBarGroupSpacing = 12.0;

/// The trailing (or leading, on one landscape rotation) vertical bar shown on
/// a folding iPhone: primary navigation (back), then the toolbar items, each
/// group in its own glass capsule; at the bottom, the tab bar as a capsule of
/// icons. Ported from `adaptive_platform_ui`'s `DuoVerticalBar`: every element
/// is a [CNGlassCapsule] — the same native Liquid Glass control iOS 26 itself
/// uses for a folding iPhone's trailing bar — not a hand-rotated horizontal
/// control.
class _CNDuoVerticalBar extends StatelessWidget {
  const _CNDuoVerticalBar({
    this.leading,
    this.onBack,
    this.actions = const <CNToolbarAction>[],
    this.tabs,
    this.currentTabIndex,
    this.onTabChange,
    this.tint,
    this.regions = const <ReservedRegion>[],
  });

  final Widget? leading;
  final VoidCallback? onBack;
  final List<CNToolbarAction> actions;
  final List<CNTabBarItem>? tabs;
  final int? currentTabIndex;
  final ValueChanged<int>? onTabChange;
  final Color? tint;
  final List<ReservedRegion> regions;

  /// [actions] split into the groups that each get a capsule: a new group
  /// starts after every spacer, fixed or flexible alike.
  static List<List<CNToolbarAction>> _groupsOf(List<CNToolbarAction> actions) {
    final groups = <List<CNToolbarAction>>[];
    var current = <CNToolbarAction>[];
    for (final action in actions) {
      current.add(action);
      if (action.spacerAfter != CNToolbarActionSpacer.none) {
        groups.add(current);
        current = <CNToolbarAction>[];
      }
    }
    if (current.isNotEmpty) groups.add(current);
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final insets = _CNDuoLayout.barInsets(
      size: MediaQuery.sizeOf(context),
      padding: padding,
      regions: regions,
    );
    final tabItems = tabs ?? const <CNTabBarItem>[];
    final tabsHeight = tabItems.isEmpty
        ? 0.0
        : CNGlassCapsule.tabsHeight(tabItems.length) + _kDuoBarGroupSpacing;

    return Padding(
      padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.maxHeight - tabsHeight;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ..._controls(room),
              const Spacer(),
              if (tabItems.isNotEmpty)
                SizedBox(
                  width: CNGlassCapsule.width,
                  height: CNGlassCapsule.tabsHeight(tabItems.length),
                  child: CNGlassCapsule(
                    items: [
                      for (final item in tabItems)
                        CNGlassCapsuleItem(
                          icon: item.icon,
                          label: item.label,
                          badgeCount: item.showBadge
                              ? int.tryParse(item.badgeLabel ?? '') ?? 1
                              : null,
                        ),
                    ],
                    selectedIndex: currentTabIndex ?? 0,
                    inset: CNGlassCapsule.tabsInset,
                    tint: tint,
                    onTap: (index) => onTabChange?.call(index),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// The controls that fit into [room], top to bottom. Toolbar items give way
  /// before the tab bar does, which keeps the primary destinations reachable:
  /// the items that do not fit move, from the bottom up, into one overflow
  /// menu, as the system does. A group can be split, so its first items stay
  /// visible while the rest moves into the menu.
  List<Widget> _controls(double room) {
    final groups = _groupsOf(actions);
    final total = actions.length;
    var used = leading == null && onBack == null ? 0.0 : CNGlassCapsule.width;
    final overflowCost = _kDuoBarGroupSpacing + CNGlassCapsule.actionsHeight(1);

    final shown = <List<CNToolbarAction>>[];
    var count = 0;
    outer:
    for (final group in groups) {
      var capsule = <CNToolbarAction>[];
      for (final action in group) {
        final cost = capsule.isEmpty
            ? (used > 0 ? _kDuoBarGroupSpacing : 0.0) + CNGlassCapsule.width
            : CNGlassCapsule.actionsHeight(capsule.length + 1) -
                  CNGlassCapsule.actionsHeight(capsule.length);
        final isLast = count == total - 1;
        if (used + cost + (isLast ? 0 : overflowCost) > room) {
          if (capsule.isNotEmpty) shown.add(capsule);
          break outer;
        }
        used += cost;
        capsule.add(action);
        count++;
      }
      shown.add(capsule);
      capsule = <CNToolbarAction>[];
    }

    final overflow = actions.skip(count).toList();

    final children = <Widget>[];
    void add(Widget child) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: _kDuoBarGroupSpacing));
      }
      children.add(child);
    }

    if (leading != null) {
      add(leading!);
    } else if (onBack != null) {
      add(_CNDuoBarBackButton(onPressed: onBack!));
    }
    for (final group in shown) {
      if (group.isNotEmpty) add(_CNDuoActionCapsule(actions: group, tint: tint));
    }
    if (overflow.isNotEmpty) add(_CNDuoOverflowCapsule(actions: overflow));
    return children;
  }
}

/// One group of toolbar items in one glass capsule.
class _CNDuoActionCapsule extends StatelessWidget {
  const _CNDuoActionCapsule({required this.actions, this.tint});

  final List<CNToolbarAction> actions;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: CNGlassCapsule.width,
      height: CNGlassCapsule.actionsHeight(actions.length),
      child: CNGlassCapsule(
        items: [
          for (final action in actions)
            CNGlassCapsuleItem(
              icon: action.icon,
              title: action.icon == null ? action.text : null,
              label: action.effectiveLabel,
              tint: action.tint,
            ),
        ],
        tint: tint,
        onTap: (index) => actions[index].onPressed(),
      ),
    );
  }
}

/// The items that did not fit, behind a native pull-down menu.
class _CNDuoOverflowCapsule extends StatelessWidget {
  const _CNDuoOverflowCapsule({required this.actions});

  final List<CNToolbarAction> actions;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: CNGlassCapsule.width,
      height: CNGlassCapsule.actionsHeight(1),
      child: CNGlassCapsule(
        items: [
          CNGlassCapsuleItem(
            icon: const CNSymbol('ellipsis'),
            label: 'More',
            menu: [
              for (var i = 0; i < actions.length; i++)
                CNGlassCapsuleMenuEntry(
                  id: i,
                  title: actions[i].effectiveLabel ?? '',
                  icon: actions[i].icon,
                ),
            ],
          ),
        ],
        onTap: (_) {},
        onMenuTap: (id) {
          if (id >= 0 && id < actions.length) actions[id].onPressed();
        },
      ),
    );
  }
}

/// The back button of the trailing bar: one round glass control.
class _CNDuoBarBackButton extends StatelessWidget {
  const _CNDuoBarBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: CNGlassCapsule.width,
      height: CNGlassCapsule.width,
      child: CNGlassCapsule(
        items: const [
          CNGlassCapsuleItem(icon: CNSymbol('chevron.left'), label: 'Back'),
        ],
        onTap: (_) => onPressed(),
      ),
    );
  }
}

// MARK: - Scaffold

/// A Cupertino-native scaffold matching iOS 26's fixed Liquid Glass toolbar
/// and `UITabBar`, including the trailing-strip layout iOS uses on a folding
/// iPhone. Composes [CNToolbar] and [CNTabBar] the way `CupertinoPageScaffold`
/// composes `CupertinoNavigationBar`.
class CupertinoNativeScaffold extends StatefulWidget {
  /// Creates a Cupertino-native scaffold.
  ///
  /// [children] holds one page per tab (or a single page when [tabs] is
  /// null); the visible page follows [currentTabIndex].
  const CupertinoNativeScaffold({
    super.key,
    required this.children,
    this.tabs,
    this.currentTabIndex,
    this.onTabChange,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.tintColor,
    this.tabBarBackgroundColor,
    this.minimizeBehavior = CNTabBarMinimizeBehavior.automatic,
    this.useHeroBackButton = true,
    this.tabBarHidden = false,
    this.resizeToAvoidBottomInset,
    this.enableDuoLayout = true,
  }) : assert(children.length > 0, 'Provide at least one page in children.'),
       assert(
         tabs == null || (currentTabIndex != null && onTabChange != null),
         'currentTabIndex and onTabChange are required when tabs is set.',
       ),
       assert(
         tabs == null || tabs.length == children.length,
         'children must have exactly one entry per tab.',
       );

  /// One page per tab, or a single page when [tabs] is null.
  final List<Widget> children;

  /// Tab bar items. Omit for a scaffold with no tab bar.
  final List<CNTabBarItem>? tabs;

  /// Index of the visible page/tab.
  final int? currentTabIndex;

  /// Called when a tab is selected.
  final ValueChanged<int>? onTabChange;

  /// Toolbar title text. Ignored when [titleWidget] is set.
  final String? title;

  /// Custom widget overlaid at the toolbar's title position.
  final Widget? titleWidget;

  /// Custom leading widget. When null, a back button is shown automatically
  /// if the route can pop and there is no tab bar.
  final Widget? leading;

  /// Toolbar trailing actions.
  final List<CNToolbarAction>? actions;

  /// Tint applied to the toolbar and tab bar.
  final Color? tintColor;

  /// Background color for the tab bar.
  final Color? tabBarBackgroundColor;

  /// Controls when the tab bar shrinks in response to scrolling.
  final CNTabBarMinimizeBehavior minimizeBehavior;

  /// Whether the automatic back button uses a shared [Hero] so it does not
  /// pop in and out across a push/pop transition.
  final bool useHeroBackButton;

  /// Hides the tab bar, e.g. while a modal is presented above it.
  final bool tabBarHidden;

  /// Passed through to the underlying [CupertinoPageScaffold]. Defaults to
  /// `false` when a tab bar is shown, since the tab bar would otherwise float
  /// above the keyboard instead of being covered by it.
  final bool? resizeToAvoidBottomInset;

  /// Whether to react to a folding iPhone's vertical-bar pose. Disable to
  /// always use the standard top toolbar/bottom tab bar layout.
  final bool enableDuoLayout;

  @override
  State<CupertinoNativeScaffold> createState() => _CupertinoNativeScaffoldState();
}

class _CupertinoNativeScaffoldState extends State<CupertinoNativeScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tabBarController;
  late final Animation<double> _tabBarAnimation;
  bool _isMinimized = false;

  FoldableData? _fold;
  StreamSubscription<FoldableData>? _foldSub;

  @override
  void initState() {
    super.initState();
    _tabBarController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _tabBarAnimation = CurvedAnimation(
      parent: _tabBarController,
      curve: Curves.easeInOut,
    );
    if (widget.enableDuoLayout) _listenToFold();
  }

  void _listenToFold() {
    Foldable.snapshot.then(_onFoldChanged).catchError((Object _) {});
    _foldSub = Foldable.changes.listen(_onFoldChanged, onError: (Object _) {});
  }

  void _onFoldChanged(FoldableData data) {
    if (!mounted) return;
    setState(() => _fold = data);
  }

  @override
  void dispose() {
    _foldSub?.cancel();
    _tabBarController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (widget.minimizeBehavior == CNTabBarMinimizeBehavior.never) return false;
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      final downMinimizes =
          widget.minimizeBehavior == CNTabBarMinimizeBehavior.onScrollDown ||
              widget.minimizeBehavior == CNTabBarMinimizeBehavior.automatic;
      final upMinimizes = widget.minimizeBehavior == CNTabBarMinimizeBehavior.onScrollUp;
      if (downMinimizes) {
        if (delta > 0 && !_isMinimized) {
          _minimizeTabBar();
        } else if (delta < 0 && _isMinimized) {
          _expandTabBar();
        }
      } else if (upMinimizes) {
        if (delta < 0 && !_isMinimized) {
          _minimizeTabBar();
        } else if (delta > 0 && _isMinimized) {
          _expandTabBar();
        }
      }
    }
    return false;
  }

  void _minimizeTabBar() {
    if (!_isMinimized) {
      _isMinimized = true;
      _tabBarController.forward();
    }
  }

  void _expandTabBar() {
    if (_isMinimized) {
      _isMinimized = false;
      _tabBarController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabBarHidden ? null : widget.tabs;
    final hasTabs = tabs != null && tabs.isNotEmpty;

    final canPop = Navigator.of(context).canPop();
    Widget? heroLeading;
    if (widget.leading == null && !hasTabs && canPop) {
      final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
      final backButton = SizedBox(
        height: 38,
        width: 38,
        child: CNButton.icon(
          icon: const CNSymbol('chevron.left', size: 20),
          style: CNButtonStyle.glass,
          onPressed: isCurrent ? () => Navigator.of(context).pop() : null,
        ),
      );
      heroLeading = widget.useHeroBackButton
          ? Hero(
              tag: 'cupertino_native_scaffold_back_button',
              flightShuttleBuilder: (_, __, ___, ____, toHeroContext) => toHeroContext.widget,
              child: backButton,
            )
          : backButton;
    }

    final hasToolbarContent = widget.title != null ||
        widget.titleWidget != null ||
        widget.leading != null ||
        heroLeading != null ||
        (widget.actions != null && widget.actions!.isNotEmpty);

    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    final isPopping = ModalRoute.of(context)?.animation?.status == AnimationStatus.reverse;
    final showNativeView = isCurrentRoute || isPopping;

    Widget bodyContent = widget.children.length == 1
        ? widget.children.first
        : IndexedStack(
            index: widget.currentTabIndex ?? 0,
            sizing: StackFit.expand,
            children: widget.children,
          );

    final mq = MediaQuery.of(context);
    final duoVerticalPose =
        widget.enableDuoLayout && _CNDuoLayout.isVerticalBarPose(mq.viewPadding);
    final hasTitle = widget.title != null || widget.titleWidget != null;
    final hasControls = widget.leading != null ||
        heroLeading != null ||
        (widget.actions != null && widget.actions!.isNotEmpty);
    final showTopToolbar = duoVerticalPose ? hasTitle : hasToolbarContent;
    final showDuoSideBar = duoVerticalPose && (hasControls || hasTabs);

    final barOnLeft = _CNDuoLayout.barSide(mq.viewPadding) == _CNDuoBarSide.left;
    final trailingInset = !duoVerticalPose
        ? 0.0
        : barOnLeft
            ? mq.padding.left
            : mq.padding.right;

    const toolbarContentHeight = 44.0;
    if (showTopToolbar || trailingInset > 0) {
      final topInset =
          !showTopToolbar ? 0.0 : (duoVerticalPose ? _CNDuoLayout.titleBandHeight : toolbarContentHeight);
      bodyContent = Padding(
        padding: EdgeInsets.only(
          left: barOnLeft ? trailingInset : 0,
          right: barOnLeft ? 0 : trailingInset,
        ),
        child: MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(
              top: mq.padding.top + topInset,
              left: mq.padding.left - (barOnLeft ? trailingInset : 0),
              right: mq.padding.right - (barOnLeft ? 0 : trailingInset),
            ),
            viewPadding: mq.viewPadding.copyWith(top: mq.viewPadding.top + topInset),
          ),
          child: bodyContent,
        ),
      );
    }

    final stackContent = Stack(
      children: [
        bodyContent,
        if (showTopToolbar)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: duoVerticalPose ? _CNDuoLayout.titleBandHeight : null,
            child: duoVerticalPose
                ? Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: [
                      const _CNDuoTitleBackdrop(),
                      _CNDuoToolbarTitle(title: widget.title, titleWidget: widget.titleWidget),
                    ],
                  )
                : CNToolbar(
                    title: widget.title,
                    titleWidget: widget.titleWidget,
                    leading: widget.leading ?? heroLeading,
                    actions: widget.actions,
                    tint: widget.tintColor,
                  ),
          ),
        if (showDuoSideBar)
          Positioned(
            top: 0,
            bottom: 0,
            left: barOnLeft ? 0 : null,
            right: barOnLeft ? null : 0,
            width: _CNDuoLayout.bandWidth(mq.viewPadding),
            child: _CNDuoVerticalBar(
              leading: widget.leading,
              onBack: heroLeading == null ? null : () => Navigator.of(context).maybePop(),
              actions: widget.actions ?? const <CNToolbarAction>[],
              tabs: tabs,
              currentTabIndex: widget.currentTabIndex,
              onTabChange: widget.onTabChange,
              tint: widget.tintColor,
              regions: _fold?.regions ?? const <ReservedRegion>[],
            ),
          ),
        if (!duoVerticalPose && hasTabs)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: _tabBarAnimation,
              builder: (context, child) {
                final progress = _tabBarAnimation.value;
                final scale = 1.0 - (progress * 0.3);
                final opacity = 1.0 - (progress * 0.5);
                return Transform.scale(
                  scale: scale,
                  alignment: Alignment.bottomCenter,
                  child: Opacity(opacity: opacity, child: child),
                );
              },
              child: !showNativeView
                  ? const SizedBox.shrink()
                  : CNTabBar(
                      items: tabs,
                      currentIndex: widget.currentTabIndex ?? 0,
                      onTap: widget.onTabChange ?? (_) {},
                      tint: widget.tintColor,
                      backgroundColor: widget.tabBarBackgroundColor,
                    ),
            ),
          ),
      ],
    );

    return CupertinoPageScaffold(
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset ?? !hasTabs,
      child: hasTabs
          ? NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: stackContent,
            )
          : stackContent,
    );
  }
}
