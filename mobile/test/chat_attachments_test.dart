// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/chat_attachments.dart';
import 'package:meshgrame/ui/mesh_map.dart';
import 'package:meshgrame/ui/navigation.dart';
import 'package:meshgrame/ui/node_list.dart';
import 'package:meshgrame/ui/search_field.dart';
import 'package:meshgrame/ui/style.dart';

const _contacts = [
  (
    peer: (
      id: 'node:mira',
      name: 'Мира Соколова',
      channel: false,
      writable: true,
    ),
    link: 'meshgram://contact/mira',
  ),
  (
    peer: (
      id: 'node:ilya',
      name: 'Илья Ветров',
      channel: false,
      writable: true,
    ),
    link: 'meshgram://contact/ilya',
  ),
];

void main() {
  testWidgets('selects a mesh contact after filtering the node list', (
    tester,
  ) async {
    String? result;
    await _openPicker(tester, (value) => result = value);
    await tester.tap(find.text('Contact'));
    await tester.pumpAndSettle();
    expect(find.text('Мира Соколова'), findsOneWidget);
    expect(find.text('Илья Ветров'), findsOneWidget);
    expect(find.byType(MeshAvatar), findsNWidgets(2));

    await _startContactSearch(tester);
    await tester.enterText(_contactEditor, 'сокол');
    await tester.pumpAndSettle();
    expect(find.text('Илья Ветров'), findsNothing);

    await tester.tap(find.text('Мира Соколова'));
    await tester.pumpAndSettle();
    expect(result, _contacts.first.link);
    expect(find.byType(MeshTabBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sorts contacts with the Nodes picker and keeps the shared rows',
    (tester) async {
      await _openPicker(tester, (_) {});
      await tester.tap(find.text('Contact'));
      await tester.pumpAndSettle();

      Future<List<String>> sortedBy(String option) async {
        await tester.tap(find.byTooltip('Sort by'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(option));
        await tester.pumpAndSettle();
        return tester
            .widgetList<MeshNodeRow>(find.byType(MeshNodeRow))
            .map((row) => row.peer.name)
            .toList();
      }

      expect(await sortedBy('Name'), ['Илья Ветров', 'Мира Соколова']);
      expect(await sortedBy('Last heard'), ['Мира Соколова', 'Илья Ветров']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('morphs contact search from a compact button into the editor', (
    tester,
  ) async {
    await _openPicker(
      tester,
      (_) {},
      contacts: [
        for (var index = 0; index < 18; index++)
          (
            peer: (
              id: 'node:$index',
              name: 'Node $index',
              channel: false,
              writable: true,
            ),
            link: 'meshgram://contact/$index',
          ),
      ],
    );
    await tester.tap(find.text('Contact'));
    await tester.pumpAndSettle();

    expect(find.byType(MeshSearchLauncher), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(find.byType(MeshSearchLauncher), findsNothing);

    final collapsed = find.byTooltip('Search nodes');
    final collapsedWidth = tester.getSize(collapsed).width;
    await tester.tap(collapsed);
    await tester.pumpAndSettle();

    expect(tester.getSize(_contactEditor).width, greaterThan(collapsedWidth));
    expect(find.byTooltip('Close search'), findsOneWidget);
    expect(find.byType(MeshTabBar), findsOneWidget);
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Search nodes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'expands and collapses the map without losing the selected point',
    (tester) async {
      String? result;
      await _openPicker(tester, (value) => result = value);

      final map = find.byType(MeshMap);
      final compact = tester.getSize(map).height;
      final action = find.text('Send location');
      expect(action, findsOneWidget);
      expect(find.byType(MeshTabBar), findsOneWidget);

      final grip = find.byKey(const ValueKey('attachment-grip'));
      await tester.drag(grip, const Offset(0, -110));
      await tester.pumpAndSettle();
      expect(tester.getSize(map).height, greaterThan(compact));
      expect(find.byType(MeshTabBar), findsNothing);
      await tester.tap(find.byTooltip('Collapse'));
      await tester.pumpAndSettle();
      expect(tester.getSize(map).height, closeTo(compact, .01));
      expect(find.byType(MeshTabBar), findsOneWidget);

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(result, 'geo:55.725000,52.401000');
      expect(map, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keeps the compact tabs with the keyboard and restores the query',
    (tester) async {
      await _openPicker(tester, (_) {});
      await tester.tap(find.text('Contact'));
      await tester.pumpAndSettle();

      await _startContactSearch(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 440);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(_contactEditor, 'сокол');
      await tester.pumpAndSettle();
      expect(find.byType(MeshTabBar), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(_locationTab);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.text('55.725000, 52.401000'), findsOneWidget);
      await tester.tap(find.text('Contact'));
      await tester.pumpAndSettle();
      expect(find.text('сокол'), findsOneWidget);
      expect(find.text('Илья Ветров'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps the tab bar at one height when switching panes', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = tester.view.padding;
    addTearDown(tester.view.reset);
    await _openPicker(tester, (_) {}, platform: TargetPlatform.iOS);
    final bar = find.byType(MeshTabBar);
    final atRest = tester.getRect(bar);

    await tester.tap(find.text('Contact'));
    await tester.pumpAndSettle();
    expect(tester.getRect(bar), atRest);
    await _startContactSearch(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    tester.view.padding = const FakeViewPadding(top: 47);
    await tester.pumpAndSettle();
    final aboveKeyboard = tester.getRect(bar);
    expect(aboveKeyboard.bottom, lessThan(844 - 320));

    await tester.tap(_locationTab);
    await tester.pumpAndSettle();
    expect(tester.getRect(bar), aboveKeyboard);
    tester.view.resetViewInsets();
    tester.view.padding = tester.view.viewPadding;
    await tester.pumpAndSettle();
    expect(tester.getRect(bar), atRest);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tracks the finger and springs to the nearest detent', (
    tester,
  ) async {
    await _openPicker(tester, (_) {});
    final grip = find.byKey(const ValueKey('attachment-grip'));
    final top = tester.getTopLeft(grip).dy;
    final bar = tester.getRect(find.byType(MeshTabBar));
    final drag = await tester.startGesture(tester.getCenter(grip));
    await drag.moveBy(
      const Offset(0, -55),
      timeStamp: const Duration(milliseconds: 180),
    );
    await tester.pump();
    expect(tester.getTopLeft(grip).dy, closeTo(top - 55, .1));
    expect(tester.getRect(find.byType(MeshTabBar)), bar);
    await drag.up(timeStamp: const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(grip).dy, closeTo(top, .1));

    await tester.fling(grip, const Offset(0, -85), 650);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Collapse'), findsOneWidget);
    await tester.fling(grip, const Offset(0, 65), 600);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(grip).dy, closeTo(top, .1));
    expect(tester.getRect(find.byType(MeshTabBar)), bar);

    await tester.dragFrom(
      tester.getCenter(find.byType(MeshMap)),
      const Offset(0, 85),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(grip).dy, closeTo(top, .1));

    await tester.fling(grip, const Offset(0, 55), 650);
    await tester.pumpAndSettle();
    expect(grip, findsNothing);
  });

  testWidgets(
    'passes a downward drag at the top of iOS contacts to the sheet',
    (tester) async {
      await _openPicker(tester, (_) {}, platform: TargetPlatform.iOS);
      await tester.tap(find.text('Contact'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand'));
      await tester.pumpAndSettle();
      final list = find.byType(CustomScrollView);
      final scroll = tester.widget<CustomScrollView>(list).controller!;
      expect(scroll.offset, 0);
      await tester.fling(list, const Offset(0, 105), 700);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Expand'), findsOneWidget);
      expect(find.byType(MeshTabBar), findsOneWidget);
      expect(scroll.offset, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('searches known nodes or coordinates without sending them', (
    tester,
  ) async {
    String? result;
    await _openPicker(tester, (value) => result = value);
    final search = find.byTooltip('Search locations');

    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '56.25, 51.50');
    await tester.pumpAndSettle();
    expect(find.text('Coordinates'), findsOneWidget);
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(find.text('55.725000, 52.401000'), findsOneWidget);

    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'маяк');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Северный маяк'));
    await tester.pumpAndSettle();
    expect(find.text('56.300000, 51.750000'), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.text('Contact'));
    await tester.pumpAndSettle();
    await tester.tap(_locationTab);
    await tester.pumpAndSettle();
    expect(find.text('56.300000, 51.750000'), findsOneWidget);
    await tester.tap(find.text('Send location'));
    await tester.pumpAndSettle();
    expect(result, 'geo:56.300000,51.750000');
    expect(tester.takeException(), isNull);
  });
}

Finder get _locationTab => find.descendant(
  of: find.byType(MeshTabBar),
  matching: find.text('Location'),
);

Finder get _contactEditor => find.descendant(
  of: find.byType(MeshSearchEditor),
  matching: find.byType(TextField),
);

Future<void> _startContactSearch(WidgetTester tester) async {
  await tester.tap(find.byType(MeshSearchLauncher));
  await tester.pumpAndSettle();
}

Future<void> _openPicker(
  WidgetTester tester,
  ValueChanged<String?> onResult, {
  List<ShareableNode> contacts = _contacts,
  TargetPlatform? platform,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async => onResult(
              await pickChatAttachment(
                context,
                contacts: contacts,
                initialPosition: (latitude: 55.725, longitude: 52.401),
                locationNodes: const [
                  (
                    name: 'Северный маяк',
                    position: (latitude: 56.3, longitude: 51.75),
                  ),
                ],
              ),
            ),
            child: const Text('Open picker'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open picker'));
  await tester.pumpAndSettle();
}
