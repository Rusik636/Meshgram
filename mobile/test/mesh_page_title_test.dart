// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/ios_control.dart';
import 'package:meshgrame/ui/mesh_page_title.dart';

void main() {
  testWidgets('centers a passive native chat title on the iOS map', (
    tester,
  ) async {
    const title = 'A long map title that cannot fit between the controls';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 240, child: MeshMapPageHeading(title)),
          ),
        ),
      ),
    );
    final native = find.byWidgetPredicate(
      (widget) => widget is IosControl && widget.kind == 'chatTitle',
    );
    final control = tester.widget<IosControl>(native);
    expect(control.properties['label'], title);
    expect(control.properties['readOnly'], isTrue);
    expect(control.properties['enabled'], isTrue);
    expect(control.onSelect, isNull);
    expect(tester.getSize(native), const Size(96, 48));
    expect(
      tester.getCenter(native).dx,
      tester.getCenter(find.byType(MeshMapPageHeading)).dx,
    );
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('uses the provided fallback outside the native control', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MeshPageTitle('Location', fallback: Text('Existing heading')),
        ),
      ),
    );
    expect(find.text('Existing heading'), findsOneWidget);
    expect(find.byType(IosControl), findsNothing);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}
