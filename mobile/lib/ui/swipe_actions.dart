// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mesh_icon.dart';
import 'navigation.dart';

typedef SwipeAction = ({
  String label,
  IconData icon,
  Color color,
  VoidCallback onTap,
});

class SwipeActionsRow extends StatefulWidget {
  const SwipeActionsRow({
    super.key,
    required this.revealed,
    required this.onReveal,
    required this.actions,
    required this.surface,
    required this.background,
    this.closedSurface,
    required this.child,
  });

  final bool revealed;
  final ValueChanged<bool> onReveal;
  final List<SwipeAction> actions;
  final Color surface, background;
  final Color? closedSurface;
  final Widget child;

  @override
  State<SwipeActionsRow> createState() => _SwipeActionsRowState();
}

class _SwipeActionsRowState extends State<SwipeActionsRow>
    with SingleTickerProviderStateMixin {
  static const _diameter = 46.0, _spacing = 10.0, _edge = 8.0;
  double get _open => widget.actions.length * (_diameter + _spacing) + _edge;
  late final _slide = AnimationController.unbounded(
    vsync: this,
    value: widget.revealed ? _open : 0,
  );

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SwipeActionsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revealed != oldWidget.revealed ||
        widget.actions.length != oldWidget.actions.length) {
      _settle(widget.revealed);
    }
  }

  void _settle(bool opened) {
    _slide.animateTo(
      opened ? _open : 0,
      duration: meshMotion(context),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final maximum = math.max(
        _open,
        math.min(_open + 110, bounds.maxWidth * .66),
      );
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _slide.stop(),
        onHorizontalDragUpdate: (drag) {
          final delta = -drag.delta.dx;
          final friction = delta > 0 && _slide.value > _open ? .65 : 1;
          _slide.value = (_slide.value + delta * friction).clamp(0.0, maximum);
        },
        onHorizontalDragEnd: (drag) {
          final velocity = drag.primaryVelocity ?? 0;
          final opened = velocity.abs() > 210
              ? velocity < 0
              : _slide.value >= _open * .42;
          widget.onReveal(opened);
          _settle(opened);
        },
        onHorizontalDragCancel: () => _settle(widget.revealed),
        child: AnimatedBuilder(
          animation: _slide,
          child: widget.child,
          builder: (context, content) {
            final offset = _slide.value;
            final stretch = (offset - _open).clamp(0.0, maximum);
            final foreground = Transform.translate(
              offset: Offset(-offset, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(24 * (offset / 38).clamp(0.0, 1.0)),
                ),
                child: Material(
                  color: Color.lerp(
                    widget.closedSurface ?? widget.surface,
                    widget.surface,
                    (offset / 38).clamp(0.0, 1.0),
                  ),
                  child: widget.revealed
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            widget.onReveal(false);
                            _settle(false);
                          },
                          child: IgnorePointer(child: content),
                        )
                      : content,
                ),
              ),
            );
            return ColoredBox(
              color: widget.background,
              child: ClipRect(
                child: Stack(
                  children: [
                    for (var i = 0; i < widget.actions.length; i++)
                      if (offset > i * (_diameter + _spacing))
                        _button(
                          widget.actions[widget.actions.length - 1 - i],
                          i,
                          offset,
                          stretch,
                        ),
                    foreground,
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );

  Widget _button(SwipeAction action, int index, double offset, double stretch) {
    final start = index * (_diameter + _spacing);
    final visibility = ((offset - start) / (_diameter + _spacing)).clamp(
      0.0,
      1.0,
    );
    final size =
        _diameter * (.28 + .72 * Curves.easeOutCubic.transform(visibility));
    return Positioned(
      right: _edge + start + (index == 0 ? 0 : stretch),
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !widget.revealed,
        child: ExcludeSemantics(
          excluding: !widget.revealed,
          child: Center(
            child: Opacity(
              opacity: visibility,
              child: Material(
                color: action.color,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: size,
                  width: size + (index == 0 ? stretch : 0),
                  child: IconButton(
                    tooltip: action.label,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: action.onTap,
                    icon: MeshIcon(
                      action.icon,
                      color: Colors.white,
                      size: 22 * (.4 + .6 * visibility),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
