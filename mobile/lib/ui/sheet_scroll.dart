// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class MeshSheetScrollController extends ScrollController {
  MeshSheetScrollController(
    this.beginSheetDrag, {
    this.transferRemainder = true,
  });

  final Drag? Function() beginSheetDrag;
  final bool transferRemainder;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SheetScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    beginSheetDrag: beginSheetDrag,
    transferRemainder: transferRemainder,
  );
}

class _SheetScrollPosition extends ScrollPositionWithSingleContext {
  _SheetScrollPosition({
    required super.physics,
    required super.context,
    required super.oldPosition,
    required this.beginSheetDrag,
    required this.transferRemainder,
  });

  final Drag? Function() beginSheetDrag;
  final bool transferRemainder;
  _SheetListDrag? _drag;

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    final scroll = super.drag(details, () {
      _drag = null;
      dragCancelCallback();
    });
    return _drag = _SheetListDrag(
      scroll,
      transferRemainder
          ? null
          : () => pixels <= minScrollExtent + 1 ? beginSheetDrag() : null,
    );
  }

  @override
  void applyUserOffset(double delta) {
    final drag = _drag;
    final details = drag?.details;
    if (!transferRemainder || drag == null || details == null) {
      super.applyUserOffset(delta);
      return;
    }
    if (drag.sheet == null) {
      final distanceToTop = math.max(0.0, pixels - minScrollExtent);
      if (delta <= distanceToTop) {
        super.applyUserOffset(delta);
        return;
      }
      // Use the part up to the boundary for the list, then give the rest of
      // this same drag update to the sheet.
      if (distanceToTop > 0) {
        super.applyUserOffset(distanceToTop);
        delta -= distanceToTop;
      }
      if (pixels <= minScrollExtent) drag.sheet = beginSheetDrag();
    }
    if (drag.sheet case final sheet?) {
      sheet.update(
        DragUpdateDetails(
          globalPosition: details.globalPosition,
          localPosition: details.localPosition,
          sourceTimeStamp: details.sourceTimeStamp,
          kind: details.kind,
          delta: Offset(0, delta),
          primaryDelta: delta,
        ),
      );
    } else {
      super.applyUserOffset(delta);
    }
  }
}

class _SheetListDrag extends Drag {
  _SheetListDrag(this._scroll, this._beginAtTop);

  final Drag _scroll;
  final Drag? Function()? _beginAtTop;
  Drag? sheet;
  DragUpdateDetails? details;

  @override
  void update(DragUpdateDetails details) {
    this.details = details;
    if (_beginAtTop != null) {
      if (details.delta.dy > 0) sheet ??= _beginAtTop();
      (sheet ?? _scroll).update(details);
    } else {
      _scroll.update(details);
    }
  }

  @override
  void end(DragEndDetails details) {
    if (sheet case final sheet?) {
      _scroll.cancel();
      sheet.end(details);
    } else {
      _scroll.end(details);
    }
  }

  @override
  void cancel() {
    _scroll.cancel();
    sheet?.cancel();
  }
}
