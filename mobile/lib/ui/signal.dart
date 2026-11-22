import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.level, this.wifi = false});

  final int level;
  final bool wifi;

  static const glyphWidth = 24.0;

  static int bluetooth(int? rssi) => switch (rssi) {
    null => 0,
    >= -55 => 4,
    >= -67 => 3,
    >= -79 => 2,
    _ => 1,
  };

  static int snr(double value) => switch (value) {
    >= 5 => 4,
    >= 0 => 3,
    >= -10 => 2,
    _ => 1,
  };

  static int lora(int value) => switch (value) {
    >= -80 => 4,
    >= -100 => 3,
    >= -112 => 2,
    _ => 1,
  };

  static int latency(Duration value, {bool ios = false}) {
    final (excellent, good, fair) = ios ? (150, 200, 250) : (40, 70, 100);
    final ms = value.inMilliseconds;
    if (ms <= excellent) return 4;
    if (ms <= good) return 3;
    if (ms <= fair) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    const idle = Color(MeshGrameV2Light.signalIdle);
    final active = switch (level) {
      4 => const Color(MeshGrameV2Light.signalStrong),
      3 => const Color(MeshGrameV2Light.signalGood),
      2 => const Color(MeshGrameV2Light.signalFair),
      1 => const Color(MeshGrameV2Light.signalWeak),
      _ => idle,
    };
    if (wifi) {
      return CustomPaint(
        size: const Size(glyphWidth, 17),
        painter: _WifiArcs(level, active, idle),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 2,
      children: [
        for (var bar = 1; bar <= 4; bar++)
          Container(
            width: (glyphWidth - 6) / 4,
            height: (3 + bar * 2).toDouble(),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1),
              color: bar <= level ? active : idle,
            ),
          ),
      ],
    );
  }
}

class _WifiArcs extends CustomPainter {
  const _WifiArcs(this.level, this.active, this.idle);

  final int level;
  final Color active, idle;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 1.6, dotRadius = 1.25, sweep = .6 * math.pi;
    final outerRadius = (size.width - stroke) / (2 * math.sin(sweep / 2));
    final gap = (outerRadius - dotRadius - 2.5 * stroke) / 3;
    final center = Offset(size.width / 2, size.height - dotRadius);
    final paint = Paint()..color = level > 0 ? active : idle;
    canvas.drawCircle(center, dotRadius, paint);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final radius = dotRadius + gap + stroke / 2 + i * (stroke + gap);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -(math.pi + sweep) / 2,
        sweep,
        false,
        paint..color = level > i + 1 ? active : idle,
      );
    }
  }

  @override
  bool shouldRepaint(_WifiArcs oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.active != active ||
      oldDelegate.idle != idle;
}
