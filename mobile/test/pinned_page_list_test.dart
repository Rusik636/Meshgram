// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/style.dart';

void main() {
  testWidgets('feathers the scrolled list without covering its controls', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinnedPageList(
            padding: EdgeInsets.zero,
            header: const PageHeading('Settings'),
            children: List.generate(
              30,
              (index) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => tapped = true,
                child: SizedBox(height: 52, child: Text('Row $index')),
              ),
            ),
          ),
        ),
      ),
    );

    final heading = tester.getRect(find.text('Settings'));
    final list = find.byType(ListView);
    final edge = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).gradient is LinearGradient,
    );
    LinearGradient gradient() =>
        (tester.widget<DecoratedBox>(edge).decoration as BoxDecoration)
                .gradient!
            as LinearGradient;
    expect(gradient().colors.first.a, 0);

    await tester.drag(list, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Settings')), heading);
    expect(gradient().colors.first.a, 1);
    expect(gradient().colors.last.a, 0);
    await tester.tapAt(tester.getTopLeft(list) + const Offset(42, 7));
    expect(tapped, isTrue);
  });
}
