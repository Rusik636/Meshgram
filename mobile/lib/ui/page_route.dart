import 'dart:async';

import 'package:flutter/cupertino.dart'
    show CupertinoPageRoute, CupertinoPageTransition;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

PageRoute<T> meshPageRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => Theme.of(context).platform == TargetPlatform.iOS
    ? _MeshCupertinoRoute<T>(builder: builder)
    : MaterialPageRoute<T>(builder: builder, allowSnapshotting: false);

class _MeshCupertinoRoute<T> extends CupertinoPageRoute<T> {
  _MeshCupertinoRoute({required super.builder})
    : super(allowSnapshotting: false);

  static const _channel = MethodChannel('meshgrame/back_swipe');
  static int _nextSnapshotId = 0;
  final _snapshot = ValueNotifier<_SnapshotPhase>(_SnapshotPhase.idle);
  int? _snapshotId;
  bool _snapshotReady = false;

  @override
  void install() {
    super.install();
    navigator!.userGestureInProgressNotifier.addListener(_gestureChanged);
    animation!
      ..addListener(_moveSnapshot)
      ..addStatusListener(_keepPreviousPageHidden);
  }

  void _keepPreviousPageHidden(AnimationStatus _) {
    if (_snapshot.value == _SnapshotPhase.capturing) {
      overlayEntries.first.opaque = true;
    }
  }

  void _gestureChanged() {
    if (popGestureInProgress) {
      if (isCurrent && _snapshotId == null) unawaited(_captureSnapshot());
    } else if (_snapshotId case final id?) {
      unawaited(_restorePage(id));
    }
  }

  Future<bool> _send(String method, int id, {double? offset}) async {
    try {
      return await _channel.invokeMethod<bool>(method, {
            'id': id,
            'offset': ?offset,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _captureSnapshot() async {
    final id = _snapshotId = ++_nextSnapshotId;
    // Hold the live page still until UIKit has captured the composed frame.
    _snapshot.value = _SnapshotPhase.capturing;
    final captured = await _send('capture', id);
    if (_snapshotId != id) return;
    if (!captured) {
      _snapshotId = null;
      _snapshot.value = _SnapshotPhase.idle;
      overlayEntries.first.opaque = animation!.isCompleted && opaque;
      return;
    }

    // Paint just the previous page underneath the snapshot. This also removes
    // the outgoing platform-view layers from Flutter's compositor.
    _snapshot.value = _SnapshotPhase.visible;
    overlayEntries.first.opaque = false;
    await SchedulerBinding.instance.endOfFrame;
    if (_snapshotId != id) return;
    final ready = await _send('afterFrame', id);
    if (_snapshotId != id) return;
    if (!ready) {
      await _restorePage(id);
      return;
    }
    _snapshotReady = true;
    _moveSnapshot();
  }

  void _moveSnapshot() {
    if (!_snapshotReady) return;
    final direction = Directionality.of(navigator!.context);
    final offset = 1 - animation!.value;
    unawaited(
      _send(
        'move',
        _snapshotId!,
        offset: direction == TextDirection.ltr ? offset : -offset,
      ),
    );
  }

  Future<void> _restorePage(int id) async {
    _snapshotId = null;
    _snapshotReady = false;
    _snapshot.value = _SnapshotPhase.idle;
    if (isCurrent && animation!.isCompleted) {
      overlayEntries.first.opaque = opaque;
    }
    // On cancel, keep the snapshot on top until the live controls are back.
    await SchedulerBinding.instance.endOfFrame;
    await _send('release', id);
  }

  @override
  void dispose() {
    navigator?.userGestureInProgressNotifier.removeListener(_gestureChanged);
    animation!
      ..removeListener(_moveSnapshot)
      ..removeStatusListener(_keepPreviousPageHidden);
    if (_snapshotId case final id?) {
      _snapshotId = null;
      _snapshotReady = false;
      unawaited(_send('release', id));
    }
    _snapshot.dispose();
    super.dispose();
  }

  // Tap navigation swaps the two screens in one frame, keeping UIKit views
  // from both pages out of the same animated compositor stack.
  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  bool didPop(T? result) {
    if (popGestureInProgress) {
      controller!.reverseDuration = super.transitionDuration;
    }
    return super.didPop(result);
  }

  // Keep the underlying page stationary during an interactive pop.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => null;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final cupertino = super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      ValueListenableBuilder(
        valueListenable: _snapshot,
        child: child,
        builder: (_, phase, page) =>
            Offstage(offstage: phase == _SnapshotPhase.visible, child: page),
      ),
    );
    if (cupertino is! CupertinoPageTransition) return cupertino;
    return ClipRect(
      child: ValueListenableBuilder(
        valueListenable: _snapshot,
        // Keep the stock edge recognizer mounted even while the page is hidden.
        child: cupertino.child,
        builder: (_, phase, gestureDetector) => SlideTransition(
          position: phase == _SnapshotPhase.idle
              ? animation.drive(
                  Tween(begin: const Offset(1, 0), end: Offset.zero),
                )
              : const AlwaysStoppedAnimation(Offset.zero),
          textDirection: Directionality.of(context),
          child: gestureDetector,
        ),
      ),
    );
  }
}

enum _SnapshotPhase { idle, capturing, visible }
