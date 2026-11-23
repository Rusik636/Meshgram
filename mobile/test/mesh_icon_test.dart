// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/mesh_icon.dart';
import 'package:meshgrame/ui/style.dart';

void main() {
  testWidgets(
    'covered iOS glass buttons use preloaded glyphs at their native scale',
    (tester) async {
      const channel = MethodChannel('meshgrame/symbols');
      final messenger = tester.binding.defaultBinaryMessenger;
      final search = meshGlassButtonSymbol(Icons.search_rounded)!;
      var requests = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        requests++;
        expect(call.method, 'render');
        expect(call.arguments, containsAll([search, 'map', 'paperclip']));
        expect(call.arguments, isNot(contains('moon')));
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

      const buttonKey = ValueKey('covered search');
      const rowIconKey = ValueKey('settings tile');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                GlassButton(
                  key: buttonKey,
                  icon: Icons.search_rounded,
                  label: 'Search',
                  onTap: () {},
                  preferNative: false,
                ),
                MeshIosButtonGlyph(
                  Icons.sort_rounded,
                  symbol: meshGlassButtonSymbol(Icons.sort_rounded)!,
                ),
                const MeshRowIcon(
                  key: rowIconKey,
                  icon: Icons.dark_mode_outlined,
                  tint: Colors.blue,
                ),
              ],
            ),
          ),
        ),
      );
      final glyph = find.byType(RawImage);
      final button = find.byKey(buttonKey);
      expect(tester.getSize(glyph), const Size.square(31));
      expect(tester.getSize(button), const Size.square(48));
      expect(tester.getCenter(glyph), tester.getCenter(button));
      expect(find.byType(UiKitView), findsNothing);
      expect(find.byIcon(Icons.search_rounded), findsNothing);
      expect(
        find.byIcon(CupertinoIcons.line_horizontal_3_decrease),
        findsOneWidget,
      );
      final rowIcon = find.descendant(
        of: find.byKey(rowIconKey),
        matching: find.byIcon(Icons.dark_mode_outlined),
      );
      expect(tester.widget<Icon>(rowIcon).size, 17);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
