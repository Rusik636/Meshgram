// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:ui' show FragmentProgram, FragmentShader, ImageFilter;

import 'package:flutter/material.dart';

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
