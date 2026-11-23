// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/attachment_sheet_route.dart';
import 'package:meshgrame/ui/ios_control.dart';

void main() {
  for (final (size, highContrast, opacity) in [
    (const Size(390, 844), false, .25),
    (const Size(844, 390), false, .25),
    (const Size(1024, 768), false, .025),
    (const Size(1024, 768), true, .25),
  ]) {
    testWidgets('iOS draws one dismissible attachment scrim at $size, '
        'high contrast: $highContrast', (tester) async {
      final opened = await _open(tester, size, highContrast: highContrast);
      final scrim = find.byWidgetPredicate(
        (widget) => switch (widget) {
          IosControl() =>
            widget.kind == 'sheetDim' &&
                widget.properties['opacity'] == opacity,
          ColoredBox() =>
            widget.color == Colors.black.withValues(alpha: opacity),
          _ => false,
        },
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(scrim, findsOneWidget);
      final fade = find
          .ancestor(of: scrim, matching: find.byType(FadeTransition))
          .first;
      expect(
        tester.widget<FadeTransition>(fade).opacity.value,
        inExclusiveRange(0, 1),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);

      final context = tester.element(find.text('Attachment content'));
      final route = ModalRoute.of(context)!;
      expect(route.barrierColor, Colors.transparent);
      final barrier = find.byWidgetPredicate(
        (widget) => widget is ModalBarrier && widget.dismissible,
      );
      expect(tester.widget<ModalBarrier>(barrier).semanticsLabel, isNotEmpty);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(await opened(), isNull);
      expect(barrier, findsNothing);
      expect(scrim, findsNothing);
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
  }

  testWidgets('iOS lets the attachment position its own morph', (tester) async {
    final opened = await _open(
      tester,
      const Size(390, 844),
      morphFromSource: true,
    );
    final sheet = find.text('Attachment content');
    await tester.pump(const Duration(milliseconds: 100));
    final initialRect = tester.getRect(sheet);
    final route = ModalRoute.of(tester.element(sheet))!;
    expect(route.animation!.value, inExclusiveRange(0, 1));
    expect(route.transitionDuration, const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet), initialRect);
    await tester.tap(sheet);
    await tester.pumpAndSettle();
    expect(await opened(), 'sent');
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('Android keeps the original attachment route barrier', (
    tester,
  ) async {
    final opened = await _open(tester, const Size(390, 844));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Attachment content'));
    final route = ModalRoute.of(context)!;
    expect(route.barrierColor, Colors.black54);
    expect(find.byType(AnimatedModalBarrier), findsOneWidget);
    await tester.tap(find.text('Attachment content'));
    await tester.pumpAndSettle();
    expect(await opened(), 'sent');
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}

Future<Future<String?> Function()> _open(
  WidgetTester tester,
  Size size, {
  bool highContrast = false,
  bool morphFromSource = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  late Future<String?> result;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(highContrast: highContrast),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showMeshAttachmentSheet<String>(
                context,
                morphFromSource: morphFromSource,
                builder: (context) => SizedBox(
                  height: 200,
                  child: Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, 'sent'),
                      child: const Text('Attachment content'),
                    ),
                  ),
                ),
              );
            },
            child: const Text('Open attachment'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open attachment'));
  await tester.pump();
  return () => result;
}
