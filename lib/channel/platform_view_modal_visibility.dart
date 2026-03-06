import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps platform views hidden while their route is covered by another route.
mixin CNPlatformViewModalVisibility<T extends StatefulWidget> on State<T> {
  bool _desiredVisible = true;
  bool? _lastSentVisible;
  bool _syncScheduled = false;
  MethodChannel? _lastChannel;

  /// The method channel currently attached to the platform view instance.
  @protected
  MethodChannel? get visibilityChannel;

  /// Recomputes the desired visibility from the current modal route state.
  @protected
  void trackPlatformViewModalVisibility() {
    _desiredVisible = ModalRoute.isCurrentOf(context) ?? true;
    _schedulePlatformViewVisibilitySync();
  }

  /// Forces a sync after a platform view channel has been attached.
  @protected
  void syncPlatformViewModalVisibility() {
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
