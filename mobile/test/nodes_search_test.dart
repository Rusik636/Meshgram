// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/controller.dart';
import 'package:meshgrame/mesh/store.dart';
import 'package:meshgrame/radio/ble_transport.dart';
import 'package:meshgrame/radio/meshtastic.dart';
import 'package:meshgrame/ui/node_list.dart';
import 'package:meshgrame/ui/nodes.dart';
import 'package:meshgrame/ui/search_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('opens node search from either position and restores the list', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = tester.view.padding;
    tester.view.systemGestureInsets = const FakeViewPadding(bottom: 52);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: BleTransport(),
      adapters: const [MeshtasticAdapter()],
      preview: true,
    );
    for (var index = 0; index < 20; index++) {
      final id = 'node:${0xabcdef00 + index}';
      controller.cache!.peers[id] = (
        id: id,
        name: 'Trail radio $index',
        channel: false,
        writable: true,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: MeshNodesPage(
          controller: controller,
          openChat: (_) async {},
          openProfile: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final heading = find.byKey(const ValueKey('nodes-heading'));
    final field = find.byKey(const ValueKey('nodes-search-field'));
    final editor = find.descendant(
      of: find.byType(MeshSearchEditor),
      matching: find.byType(TextField),
    );
    final headingRect = tester.getRect(heading);
    final expanded = tester.getRect(field);
    expect(expanded.width, 358);
    expect(expanded.top, greaterThan(headingRect.bottom));

    await tester.tapAt(expanded.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getRect(field).top, greaterThan(expanded.top));
    expect(tester.getRect(heading), headingRect);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.getRect(field).bottom, closeTo(536, .5));

    await tester.enterText(editor, 'МИРА');
    await tester.pumpAndSettle();
    expect(find.text('Мира Соколова'), findsOneWidget);
    expect(find.byType(MeshNodeRow), findsOneWidget);
    await tester.enterText(editor, '!ABCDEF07');
    await tester.pumpAndSettle();
    expect(find.text('Trail radio 7'), findsOneWidget);
    expect(find.byType(MeshNodeRow), findsOneWidget);

    await tester.tap(find.byTooltip('Close search'));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(tester.getRect(field), expanded);

    final list = find.byType(CustomScrollView);
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    final browseOffset = tester
        .widget<CustomScrollView>(list)
        .controller!
        .offset;
    final compact = tester.getRect(field);
    expect(compact.size, const Size.square(48));
    expect(compact.center.dy, headingRect.center.dy);
    final sort = find.byTooltip('Sort by');
    expect(compact.left, greaterThan(tester.getRect(sort).right));

    await tester.tap(find.byTooltip('Search nodes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getRect(field).width, greaterThan(compact.width));
    expect(tester.getRect(field).top, greaterThan(compact.top));
    await tester.pumpAndSettle();
    expect(tester.getRect(field).bottom, closeTo(784, .5));
    expect(tester.getRect(heading), headingRect);
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(tester.getRect(field), compact);
    expect(
      tester.widget<CustomScrollView>(list).controller!.offset,
      browseOffset,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
