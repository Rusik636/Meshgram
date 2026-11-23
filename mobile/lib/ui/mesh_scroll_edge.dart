// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:ui' show FragmentProgram, FragmentShader, ImageFilter;

import 'package:flutter/material.dart';

/// Keeps the fade on the viewport while the scrollable content moves.
class MeshScrollViewport extends StatefulWidget {
  const MeshScrollViewport({
    super.key,
    required this.child,
    this.tint,
    this.edgeExtent = 18,
    this.fadeTop = true,
  }) : assert(edgeExtent > 0);

  final Widget child;
  final Color? tint;
  final double edgeExtent;
  final bool fadeTop;

  @override
  State<MeshScrollViewport> createState() => _MeshScrollViewportState();
}

class _MeshScrollViewportState extends State<MeshScrollViewport> {
  double _top = 0;
  double _bottom = 0;

  void _update(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != Axis.vertical) return;
    final extent = widget.edgeExtent;
    final top = (metrics.extentBefore / extent).clamp(0.0, 1.0);
    final bottom = (metrics.extentAfter / extent).clamp(0.0, 1.0);
    if (top == _top && bottom == _bottom) return;
    setState(() {
      _top = top;
      _bottom = bottom;
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    clipBehavior: Clip.none,
    children: [
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notice) {
          _update(notice.metrics, notice.depth);
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notice) {
            _update(notice.metrics, notice.depth);
            return false;
          },
          child: widget.child,
        ),
      ),
      if (widget.fadeTop && _top > 0)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: widget.edgeExtent,
          child: Opacity(
            opacity: _top,
            child: MeshScrollEdge(
              top: true,
              tint: widget.tint,
              opaqueEdge: true,
            ),
          ),
        ),
      if (_bottom > 0)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: widget.edgeExtent,
          child: Opacity(
            opacity: _bottom,
            child: MeshScrollEdge(
              top: false,
              tint: widget.tint,
              opaqueEdge: true,
            ),
          ),
        ),
    ],
  );
}

class MeshScrollEdge extends StatefulWidget {
  const MeshScrollEdge({
    super.key,
    required this.top,
    this.tint,
    this.opaqueEdge = false,
  });

  final bool top;
  final Color? tint;
  final bool opaqueEdge;

  @override
  State<MeshScrollEdge> createState() => _MeshScrollEdgeState();
}

class _MeshScrollEdgeState extends State<MeshScrollEdge> {
  static Future<FragmentProgram>? _program;
  FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (ImageFilter.isShaderFilterSupported) unawaited(_loadShader());
  }

  Future<void> _loadShader() async {
    try {
      final program = await (_program ??= FragmentProgram.fromAsset(
        'shaders/chat_edge.frag',
      ));
      if (!mounted) return;
      final shader = program.fragmentShader()..setFloat(2, widget.top ? 1 : 0);
      setState(() => _shader = shader);
    } catch (_) {
      // The gradient remains available if the runtime cannot load the shader.
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.tint;
    final top = widget.top;
    final shader = _shader;
    // Start at the surface color where the edge meets a clipped list viewport.
    final (opacity, stops) = widget.opaqueEdge
        ? (
            const [1.0, .98, .82, .5, .15, 0.0],
            const [0.0, .1, .3, .55, .8, 1.0],
          )
        : (const [.84, .55, .17, 0.0], const [0.0, .4, .73, 1.0]);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!MediaQuery.highContrastOf(context) &&
              (shader != null || tint == null))
            ClipRect(
              child: BackdropFilter(
                filter: shader == null
                    ? ImageFilter.blur(sigmaX: 2, sigmaY: 2)
                    : ImageFilter.shader(shader),
                child: const SizedBox.expand(),
              ),
            ),
          if (tint != null)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                  end: top ? Alignment.bottomCenter : Alignment.topCenter,
                  colors: [
                    for (final alpha in opacity) tint.withValues(alpha: alpha),
                  ],
                  stops: stops,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
