// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Gives an archive pull the part of a user drag that its row consumes.
class ChatArchiveScrollPhysics extends ClampingScrollPhysics {
  const ChatArchiveScrollPhysics(this.onDrag, {super.parent});

  final double Function(ScrollMetrics, double) onDrag;

  @override
  ChatArchiveScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      ChatArchiveScrollPhysics(onDrag, parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final remaining = onDrag(position, offset);
    return remaining == 0
        ? 0
        : super.applyPhysicsToUserOffset(position, remaining);
  }
}

/// Keeps chat rows in place when the transient archive disappears above them.
class ChatArchiveSliver extends SliverToBoxAdapter {
  const ChatArchiveSliver({
    super.key,
    required this.retraction,
    required super.child,
  });

  final ({int sequence, double extent}) retraction;

  @override
  RenderSliverToBoxAdapter createRenderObject(BuildContext context) =>
      _RenderChatArchive(retraction.sequence);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverToBoxAdapter renderObject,
  ) => (renderObject as _RenderChatArchive).retract(retraction);
}

class _RenderChatArchive extends RenderSliverToBoxAdapter {
  _RenderChatArchive(this._sequence);

  int _sequence;
  double _correction = 0;

  void retract(({int sequence, double extent}) retraction) {
    if (retraction.sequence == _sequence) return;
    _sequence = retraction.sequence;
    _correction = -retraction.extent;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    if (_correction == 0) {
      super.performLayout();
    } else {
      geometry = SliverGeometry(scrollOffsetCorrection: _correction);
      _correction = 0;
    }
  }
}
