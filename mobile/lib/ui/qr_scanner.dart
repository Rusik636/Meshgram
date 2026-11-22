import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'style.dart';

class MeshQrScannerPage extends StatefulWidget {
  const MeshQrScannerPage({super.key, required this.title});

  final String title;

  @override
  State<MeshQrScannerPage> createState() => _MeshQrScannerState();
}

class _MeshQrScannerState extends State<MeshQrScannerPage> {
  final _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _returning = false;

  void _use(String raw) {
    if (_returning || raw.trim().isEmpty) return;
    _returning = true;
    Navigator.of(context).pop(raw.trim());
  }

  Future<void> _manual() async {
    if (_scanner.value.isRunning) await _scanner.stop();
    if (!mounted) return;
    var text = '';
    final link = await showMeshDialog<String>(
      context: context,
      builder: (context) => MeshDialog(
        title: Text(widget.title),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (value) => text = value,
          decoration: InputDecoration(
            hintText: tr(context, 'Вставьте ссылку', 'Paste a link'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(text),
            child: Text(tr(context, 'Добавить', 'Add')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (link?.trim().isNotEmpty == true) {
      _use(link!);
    } else {
      try {
        await _scanner.start();
      } on MobileScannerException {
        // The on-screen camera error still offers manual invitation entry.
      }
    }
  }

  @override
  void dispose() {
    unawaited(_scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          PageHeading(
            widget.title,
            leading: GlassButton(
              icon: Icons.arrow_back_ios_new_rounded,
              label: tr(context, 'Назад', 'Back'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    final side = math.min(size.shortestSide * .72, 284.0);
                    final window = Rect.fromCenter(
                      center: size.center(Offset.zero),
                      width: side,
                      height: side,
                    );
                    return MobileScanner(
                      controller: _scanner,
                      scanWindow: window,
                      overlayBuilder: (context, _) => IgnorePointer(
                        child: Semantics(
                          label: tr(
                            context,
                            'Поместите QR-код в рамку.',
                            'Place the QR code inside the frame.',
                          ),
                          child: CustomPaint(size: size, painter: _ScannerMask(window)),
                        ),
                      ),
                      onDetect: (capture) {
                        final value = capture.barcodes
                            .where(
                              (barcode) => barcode.rawValue?.isNotEmpty == true,
                            )
                            .firstOrNull
                            ?.rawValue;
                        if (value != null) _use(value);
                      },
                      errorBuilder: (context, error) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            tr(
                              context,
                              'Камера недоступна. Можно вставить ссылку.',
                              'The camera is unavailable. You can paste a link.',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: GlassActionButton(
              label: tr(context, 'Вставить ссылку', 'Paste a link'),
              onTap: () => unawaited(_manual()),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ScannerMask extends CustomPainter {
  const _ScannerMask(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(window.shortestSide / 16, 12.0);
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(window, Radius.circular(radius)));
    canvas.drawPath(mask, Paint()..color = const Color(0x9c080d17));

    final corners = Path();
    final length = math.min(window.shortestSide * .18, 34.0);
    for (final (corner, dx, dy) in [
      (window.topLeft, 1, 1),
      (window.topRight, -1, 1),
      (window.bottomRight, -1, -1),
      (window.bottomLeft, 1, -1),
    ]) {
      corners
        ..moveTo(corner.dx, corner.dy + dy * length)
        ..lineTo(corner.dx, corner.dy + dy * radius)
        ..quadraticBezierTo(
          corner.dx,
          corner.dy,
          corner.dx + dx * radius,
          corner.dy,
        )
        ..lineTo(corner.dx + dx * length, corner.dy);
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6
      ..color = const Color(0xb3000000);
    canvas.drawPath(corners, stroke);
    canvas.drawPath(
      corners,
      stroke
        ..strokeWidth = 3
        ..color = const Color(0xfff0f7ff),
    );
  }

  @override
  bool shouldRepaint(_ScannerMask oldDelegate) => oldDelegate.window != window;
}
