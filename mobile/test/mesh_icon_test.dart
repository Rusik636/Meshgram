// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets(
    'preloads and reuses exact iOS symbols without embedding a platform view',
    (tester) async {
      const channel = MethodChannel('meshgrame/symbols');
      final messenger = tester.binding.defaultBinaryMessenger;
      final search = meshGlassButtonSymbol(Icons.search_rounded)!;
      var requests = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        requests++;
        expect(call.method, 'render');
        expect(call.arguments, containsAll([search, 'doc.on.doc', 'wifi']));
        return {
          search: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFUlEQVR4nGP8'
            '////fwYGBgYmEAHCAD34BABm6tHAAAAAAElFTkSuQmCC',
          ),
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.runAsync(() async {
        await prepareMeshIosSymbols();
        await prepareMeshIosSymbols();
      });
      expect(requests, 1);

      const explicit = ValueKey('explicit system glyph');
      const automatic = ValueKey('automatic system glyph');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MeshIcon(
                  Icons.search_rounded,
                  key: explicit,
                  size: 24,
                  systemSymbol: search,
                ),
                const MeshIcon(Icons.search_rounded, key: automatic, size: 18),
                const MeshIcon(Icons.sort_rounded),
              ],
            ),
          ),
        ),
      );
      Finder painted(Key key) => find.descendant(
        of: find.byKey(key),
        matching: find.byType(CustomPaint),
      );
      expect(tester.getSize(painted(explicit)), const Size.square(24));
      expect(tester.getSize(painted(automatic)), const Size.square(18));
      expect(find.byType(UiKitView), findsNothing);
      expect(find.byIcon(CupertinoIcons.search), findsNothing);
      expect(
        find.byIcon(CupertinoIcons.line_horizontal_3_decrease),
        findsOneWidget,
      );
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
