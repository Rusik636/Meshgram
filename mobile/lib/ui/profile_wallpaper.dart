// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import 'chat_workspace.dart';
import 'style.dart';

class ProfilePalette {
  ProfilePalette(String identity)
    : seed = sha256.convert(utf8.encode(identity.toLowerCase())).bytes;

  final List<int> seed;

  Color tone(double shift, double lightness) => HSLColor.fromAHSL(
    1,
    (seed[0] / 256 * 360 + shift) % 360,
    .64,
    lightness,
  ).toColor();

  Color base(MeshStyle style) => tone(0, style.dark ? .24 : .82);
  Color accent(MeshStyle style) =>
      tone(25 + seed[1] / 8, style.dark ? .69 : .43);
}

/// Draw the contours over the full height of the expanded profile header.
class ProfileWallpaper extends StatefulWidget {
  const ProfileWallpaper({
    super.key,
    required this.identity,
    required this.coverage,
  });

  final String identity;
  final double coverage;

  @override
  State<ProfileWallpaper> createState() => _ProfileWallpaperState();
}

class _ProfileWallpaperState extends State<ProfileWallpaper>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  late var _palette = ProfilePalette(widget.identity);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate =
        !MediaQuery.disableAnimationsOf(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (animate && !_motion.isAnimating) {
      _motion.repeat();
    } else if (!animate) {
      _motion.stop();
    }
  }

  @override
  void didUpdateWidget(ProfileWallpaper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.identity != oldWidget.identity) {
      _palette = ProfilePalette(widget.identity);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(double.infinity, widget.coverage),
        painter: _RouteContours(
          _motion,
          _palette.seed,
          _palette.base(style),
          _palette.accent(style),
          ChatWorkspacePane.desktopSplit(context) ? style.canvas : null,
        ),
      ),
    );
  }
}

class _RouteContours extends CustomPainter {
  _RouteContours(this.motion, this.seed, this.base, this.accent, this.edgeColor)
    : super(repaint: motion);

  final Animation<double> motion;
  final List<int> seed;
  final Color base, accent;
  final Color? edgeColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    const top = Alignment.topCenter, bottom = Alignment.bottomCenter;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: top,
          end: bottom,
          colors: [base.withValues(alpha: .72), base.withValues(alpha: 0)],
        ).createShader(rect),
    );
    final key = seed;
    final turn = 2 * math.pi;
    final phase = key[2] / 256 * turn;
    final cycle = motion.value * turn;
    final amplitude = 8 + key[3] / 24;
    final brush = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05
      ..shader = LinearGradient(
        begin: top,
        end: bottom,
        colors: [accent.withValues(alpha: .36), accent.withValues(alpha: 0)],
        stops: const [0, .95],
      ).createShader(rect);
    canvas.save();
    canvas.clipRect(rect);
    for (var line = -2; line * 15 < size.height + 24; line++) {
      final path = Path();
      for (var sample = 0; sample <= 48; sample++) {
        final fraction = sample / 48;
        final x = size.width * fraction;
        final a = fraction * turn + phase + line * .36;
        final y =
            line * 15.0 +
            24 +
            amplitude * math.sin(a + cycle) +
            7 * math.cos(a * 2 - cycle + key[4] / 25);
        if (sample == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, brush);
    }
    canvas.restore();
    if (edgeColor case final color?) {
      paintChatWorkspaceEdge(canvas, size, color);
    }
  }

  @override
  bool shouldRepaint(_RouteContours oldDelegate) =>
      seed != oldDelegate.seed ||
      base != oldDelegate.base ||
      accent != oldDelegate.accent ||
      edgeColor != oldDelegate.edgeColor;
}
