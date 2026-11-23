// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/chat_attachments.dart';
import 'package:meshgrame/ui/mesh_map.dart';

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

    await tester.enterText(find.byType(TextField), 'сокол');
    await tester.pumpAndSettle();
    expect(find.text('Илья Ветров'), findsNothing);

    await tester.tap(find.text('Мира Соколова'));
    await tester.pumpAndSettle();
    expect(result, _contacts.first.link);
    expect(find.text('Nodes'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'expands and collapses the map without losing the selected point',
    (tester) async {
      String? result;
      await _openPicker(tester, (value) => result = value);
      await tester.tap(find.text('Location'));
      await tester.pumpAndSettle();

      final map = find.byType(MeshMap);
      final compact = tester.getSize(map).height;
      final action = find.text('Send location');
      expect(action, findsOneWidget);

      await tester.tap(find.byTooltip('Expand'));
      await tester.pumpAndSettle();
      expect(tester.getSize(map).height, greaterThan(compact));
      await tester.tap(find.byTooltip('Collapse'));
      await tester.pumpAndSettle();
      expect(tester.getSize(map).height, closeTo(compact, .01));

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(result, 'geo:55.725000,52.401000');
      expect(map, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _openPicker(
  WidgetTester tester,
  ValueChanged<String?> onResult,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async => onResult(
              await pickChatAttachment(
                context,
                contacts: _contacts,
                initialPosition: (latitude: 55.725, longitude: 52.401),
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
