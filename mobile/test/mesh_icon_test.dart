// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/mesh_icon.dart';

void main() {
  testWidgets('resolves platform glyphs and preserves icon layout', (
    tester,
  ) async {
    const key = ValueKey('search');
    const size = 18.0;
    const color = Colors.red;
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      final apple = platform == TargetPlatform.iOS;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  const MeshIcon(
                    Icons.search_rounded,
                    key: key,
                    color: color,
                    size: size,
                    semanticLabel: 'Search',
                  ),
                  Icon(meshPlatformIcon(context, Icons.copy_rounded)),
                  const MeshIcon(Icons.access_alarm),
                  const MeshIcon(CupertinoIcons.person_crop_circle),
                  const MeshIcon(null),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final search = find.descendant(
        of: find.byKey(key),
        matching: find.byType(Icon),
      );
      final icon = tester.widget<Icon>(search);
      expect(icon.icon, apple ? CupertinoIcons.search : Icons.search_rounded);
      expect(icon.semanticLabel, 'Search');
      expect(icon.color, color);
      expect(tester.getSize(search), const Size.square(size));
      expect(
        find.byIcon(apple ? CupertinoIcons.doc_on_doc : Icons.copy_rounded),
        findsOneWidget,
      );
      expect(
        find.byIcon(
          apple ? CupertinoIcons.question_circle : Icons.access_alarm,
        ),
        findsOneWidget,
      );
      expect(find.byIcon(CupertinoIcons.person_crop_circle), findsOneWidget);
      expect(
        tester.widgetList<Icon>(find.byType(Icon)).where((i) => i.icon == null),
        hasLength(1),
      );
    }
  });
}
