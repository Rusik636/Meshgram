// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/chat_attachments.dart';
import 'package:meshgrame/ui/mesh_map.dart';
import 'package:meshgrame/ui/navigation.dart';

const _position = (latitude: 55.75, longitude: 49.14);
const _size = Size(390, 844);

void main() {
  testWidgets('the location viewer draws through the system insets', (
    tester,
  ) async {
    await _open(tester, (context) => openMeshLocation(context, _position));

    expect(tester.getRect(find.byType(MeshMap)), Offset.zero & _size);
    expect(find.byTooltip('Copy coordinates'), findsOneWidget);
    expect(find.byType(MeshMapAttribution), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the location sheet draws behind the header, action and tabs', (
    tester,
  ) async {
    await _open(
      tester,
      (context) => pickChatAttachment(
        context,
        contacts: const [],
        initialPosition: _position,
      ),
    );

    final map = find.byType(MeshMap);
    final action = find.text('Send location');
    expect(tester.getRect(map).contains(tester.getCenter(action)), isTrue);
    expect(
      tester.getRect(map).contains(tester.getCenter(find.byType(MeshTabBar))),
      isTrue,
    );

    await tester.tap(find.byTooltip('Expand'));
    await tester.pumpAndSettle();
    final expanded = tester.getRect(map);
    expect(expanded.bottom, _size.height);
    expect(
      expanded.contains(tester.getCenter(find.byTooltip('Collapse'))),
      isTrue,
    );
    expect(expanded.contains(tester.getCenter(action)), isTrue);
    expect(find.byType(MeshTabBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _open(
  WidgetTester tester,
  Future<Object?> Function(BuildContext) open,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _size;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = tester.view.padding;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('Open map'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open map'));
  await tester.pumpAndSettle();
}
