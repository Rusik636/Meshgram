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
    final list = find.byType(CustomScrollView);
    final fade = find.ancestor(of: list, matching: find.byType(ShaderMask));
    void expectSoftHeader() {
      expect(tester.getRect(list).top, 0);
      expect(tester.widget<ShaderMask>(fade).blendMode, BlendMode.dstIn);
    }

    final headingRect = tester.getRect(heading);
    final title = find.text('Nodes');
    final back = find.byTooltip('Back');
    final map = find.byTooltip('Node map');
    final sort = find.byTooltip('Sort by');
    final mapRect = tester.getRect(map);
    final sortRect = tester.getRect(sort);
    double titleBetween(Finder action) =>
        (tester.getRect(back).right + tester.getRect(action).left) / 2;
    double titleX() => tester.getCenter(title).dx;
    final expandedTitle = titleBetween(map);
    expect(titleX(), closeTo(expandedTitle, .01));
    expectSoftHeader();
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
    expectSoftHeader();

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

    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    final browseScroll = tester.widget<CustomScrollView>(list).controller!;
    final browseOffset = browseScroll.offset;
    final compact = tester.getRect(field);
    final compactTitle = titleBetween(field);
    expect(titleX(), closeTo(compactTitle, .01));
    expect(compact.size, const Size.square(48));
    expect(compact.center.dy, headingRect.center.dy);
    expect(compact.right, lessThan(mapRect.left));
    expect(mapRect.right, lessThan(sortRect.left));
    expect(tester.getRect(map), mapRect);
    expect(tester.getRect(sort), sortRect);
    expectSoftHeader();

    final collapseRange = meshSearchFieldHeight(tester.element(field)) + 8;
    browseScroll.jumpTo(collapseRange / 2);
    await tester.pump();
    expect(titleX(), closeTo((expandedTitle + compactTitle) / 2, .01));
    browseScroll.jumpTo(browseOffset);
    await tester.pump();

    await tester.tap(find.byTooltip('Search nodes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getRect(field).width, greaterThan(compact.width));
    expect(tester.getRect(field).top, greaterThan(compact.top));
    expect(titleX(), inExclusiveRange(compactTitle, expandedTitle));
    await tester.pumpAndSettle();
    expect(tester.getRect(field).bottom, closeTo(784, .5));
    expect(tester.getRect(heading), headingRect);
    expect(titleX(), closeTo(expandedTitle, .01));
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(tester.getRect(field), compact);
    expect(titleX(), closeTo(compactTitle, .01));
    expect(
      tester.widget<CustomScrollView>(list).controller!.offset,
      browseOffset,
    );
    await tester.tap(find.byTooltip('Search nodes'));
    await tester.pumpAndSettle();
    await tester.enterText(editor, '!ABCDEF07');
    tester.view.physicalSize = const Size(844, 390);
    tester.view.padding = const FakeViewPadding(
      left: 47,
      right: 34,
      bottom: 21,
    );
    tester.view.viewPadding = tester.view.padding;
    tester.view.viewInsets = const FakeViewPadding(bottom: 135);
    await tester.pumpAndSettle();
    expect(tester.getRect(field).bottom, closeTo(247, .5));
    expect(tester.getRect(field).left, 63);
    expect(find.text('Trail radio 7'), findsOneWidget);
    expectSoftHeader();

    await tester.tap(find.byTooltip('Close search'));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    final rotated = tester.getRect(field);
    expect(rotated.size, const Size.square(48));
    expect(rotated.right, lessThan(tester.getRect(map).left));
    expect(tester.getRect(map).right, lessThan(tester.getRect(sort).left));
    expect(titleX(), closeTo(titleBetween(field), .01));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
