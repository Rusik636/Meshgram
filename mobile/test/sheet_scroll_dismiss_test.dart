// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/style.dart';

void main() {
  testWidgets('iOS passes the remaining list drag to the sheet at the top', (
    tester,
  ) async {
    await _open(tester, TargetPlatform.iOS);
    final list = find.byType(ListView);
    final position = tester.state<ScrollableState>(find.byType(Scrollable));
    final sheet = find.byType(BottomSheet);
    final top = tester.getTopLeft(sheet).dy;
    position.position.jumpTo(104);
    await tester.pump();

    final gesture = await tester.startGesture(tester.getCenter(list));
    await gesture.moveBy(const Offset(0, 24));
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    final distanceToTop = position.position.pixels;
    expect(distanceToTop, inExclusiveRange(0, 104));
    expect(tester.getTopLeft(sheet).dy, top);

    await gesture.moveBy(Offset(0, distanceToTop + 32));
    await tester.pump();
    expect(position.position.pixels, closeTo(0, .01));
    expect(tester.getTopLeft(sheet).dy, closeTo(top + 32, 1));

    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, top);
    await tester.fling(list, const Offset(0, 110), 1600);
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS can close the sheet from the widened grip area', (
    tester,
  ) async {
    await _open(tester, TargetPlatform.iOS);
    final sheet = find.byType(BottomSheet);
    final top = tester.getTopLeft(sheet).dy;
    final list = tester.getTopLeft(find.byType(ListView));
    expect(list.dy - top, 16);
    tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(120);
    await tester.pump();
    final gesture = await tester.startGesture(Offset(list.dx + 30, top + 35));
    await gesture.moveBy(const Offset(0, 24));
    await gesture.moveBy(const Offset(0, 232));
    await tester.pump();
    expect(tester.getTopLeft(sheet).dy, greaterThan(top + 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
  });

  testWidgets('Android keeps the grip and list gesture behavior', (
    tester,
  ) async {
    await _open(tester, TargetPlatform.android);
    final sheet = find.byType(BottomSheet);
    final list = find.byType(ListView);
    final top = tester.getTopLeft(sheet).dy;
    expect(tester.getTopLeft(list).dy - top, 16);
    await tester.fling(list, const Offset(0, 110), 1600);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, top);
  });
}

Future<void> _open(WidgetTester tester, TargetPlatform platform) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMeshSheet<void>(
              context: context,
              builder: (_) => SheetBody(
                title: 'Options',
                children: List.generate(
                  16,
                  (index) => ListTile(title: Text('Option $index')),
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
