import 'dart:async';

import 'package:flutter/material.dart' show BottomSheet;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps platform views hidden while their route is covered by another route.
mixin CNPlatformViewModalVisibility<T extends StatefulWidget> on State<T> {
  bool _desiredVisible = true;
  bool? _lastSentVisible;
  bool _syncScheduled = false;
  bool _monitorScheduled = false;
  MethodChannel? _lastChannel;
  ModalRoute<dynamic>? _route;

  /// The method channel currently attached to the platform view instance.
  @protected
  MethodChannel? get visibilityChannel;

  /// Whether the platform view should currently be visible for this route.
  @protected
  bool get isPlatformViewVisible => _desiredVisible;

  bool _updateDesiredVisibility() {
    final route = _route;
    final isCurrent = route?.isCurrent ?? true;
    final handlesLocalHistory = route?.willHandlePopInternally ?? false;
    final isInsideBottomSheet =
        context.findAncestorWidgetOfExactType<BottomSheet>() != null;
    final nextVisible =
        isCurrent && (!handlesLocalHistory || isInsideBottomSheet);
    final changed = _desiredVisible != nextVisible;
    _desiredVisible = nextVisible;
    return changed;
  }

  bool get _shouldMonitorRouteState =>
      (_route?.canPop ?? false) || !_desiredVisible;

  void _ensurePlatformViewVisibilityMonitor() {
    if (_monitorScheduled || !_shouldMonitorRouteState) return;
    _monitorScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _monitorScheduled = false;
      if (!mounted) return;

      if (_updateDesiredVisibility()) {
        setState(() {});
        _schedulePlatformViewVisibilitySync();
      }

      if (_shouldMonitorRouteState) {
        _ensurePlatformViewVisibilityMonitor();
      }
    });
  }

  /// Recomputes the desired visibility from the current modal route state.
  @protected
  void trackPlatformViewModalVisibility() {
    _route = ModalRoute.of(context);
    _updateDesiredVisibility();
    _ensurePlatformViewVisibilityMonitor();
    _schedulePlatformViewVisibilitySync();
  }

  /// Forces a sync after a platform view channel has been attached.
  @protected
  void syncPlatformViewModalVisibility() {
    _ensurePlatformViewVisibilityMonitor();
    _schedulePlatformViewVisibilitySync();
  }

  void _schedulePlatformViewVisibilitySync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;

      final channel = visibilityChannel;
      if (!identical(channel, _lastChannel)) {
        _lastChannel = channel;
        _lastSentVisible = null;
      }
      if (channel == null || _lastSentVisible == _desiredVisible) {
        return;
      }

      final visible = _desiredVisible;
      _lastSentVisible = visible;
      unawaited(
        channel
            .invokeMethod<void>('setVisible', {'visible': visible})
            .catchError((_) {
              if (_lastSentVisible == visible) {
                _lastSentVisible = null;
              }
            }),
      );
    });
  }
}
