// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/mesh_scroll_edge.dart';
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
    final top = find.byWidgetPredicate(
      (widget) => widget is MeshScrollEdge && widget.top,
    );
    final bottom = find.byWidgetPredicate(
      (widget) => widget is MeshScrollEdge && !widget.top,
    );
    final edge = find.descendant(of: top, matching: find.byType(DecoratedBox));
    LinearGradient gradient() =>
        (tester.widget<DecoratedBox>(edge).decoration as BoxDecoration)
                .gradient!
            as LinearGradient;
    await tester.pumpAndSettle();
    expect(top, findsNothing);
    final bottomBounds = tester.getRect(bottom);
    expect(bottomBounds.bottom, tester.getRect(list).bottom);

    await tester.drag(list, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Settings')), heading);
    expect(gradient().colors.first.a, 1);
    expect(gradient().colors.last.a, 0);
    expect(tester.getRect(bottom), bottomBounds);
    await tester.tapAt(tester.getTopLeft(list) + const Offset(42, 7));
    expect(tapped, isTrue);

    final scroll = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(bottom, findsNothing);
    expect(find.text('Row 29').hitTestable(), findsOneWidget);
  });
}
