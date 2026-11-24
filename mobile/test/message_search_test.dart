// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/controller.dart';
import 'package:meshgrame/mesh/network.dart';
import 'package:meshgrame/mesh/store.dart';
import 'package:meshgrame/radio/ble_transport.dart';
import 'package:meshgrame/radio/meshtastic.dart';
import 'package:meshgrame/ui/chat.dart';
import 'package:meshgrame/ui/message_search.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('message filter results and date jump open the exact entries', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final mesh = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: BleTransport(),
      adapters: const [MeshtasticAdapter()],
      preview: true,
    );
    final peer = mesh.cache!.peers['ch:0']!;
    final time = DateTime(2026, 11, 24, 11, 20);
    const link = 'http://example.org/summit';
    mesh.cache!.messages
      ..clear()
      ..addAll([
        MeshMessage(
          id: 'link',
          chat: peer.id,
          author: 'Mira',
          text: link,
          time: time.subtract(const Duration(days: 1)),
          delivery: Delivery.received,
        ),
        MeshMessage(
          id: 'location',
          chat: peer.id,
          author: 'Lena',
          text: 'geo:55.75,49.14',
          time: time,
          delivery: Delivery.received,
        ),
      ]);
    final history = mesh.messages(peer.id);
    final day = DateUtils.dateOnly(history.first.time);
    final compound = MessageSearchFilters(
      author: 'name:Mira',
      period: DateTimeRange(start: day, end: day),
      content: {MessageContentFilter.link, MessageContentFilter.contact},
    );
    expect(compound.accepts(mesh, history.first, 'summit'), isTrue);
    expect(compound.accepts(mesh, history.last, ''), isFalse);
    expect(
      const MessageSearchFilters(content: {MessageContentFilter.location})
          .accepts(mesh, history.last, ''),
      isTrue,
    );
    final contactCode = const MeshtasticAdapter().contactCode(
      (id: 'node:5151', name: 'Bridge', channel: false, writable: true),
      (publicKey: 'ae' * 32, type: null, shortName: 'BR'),
    );
    final contact = MeshMessage(
      id: 'contact',
      chat: peer.id,
      author: 'Mira',
      text: contactCode.toString(),
      time: day,
      delivery: Delivery.received,
    );
    expect(compound.accepts(mesh, contact, ''), isTrue);
    Widget page(int key) => MaterialApp(
      home: MeshChatPage(
        key: ValueKey(key),
        controller: mesh,
        peer: peer,
        initialSearch: true,
      ),
    );
    await tester.pumpWidget(page(0));
    await tester.pumpAndSettle();
    expect(find.byType(MessageSearchResultTile), findsNWidgets(2));
    await tester.tap(find.byTooltip('Message filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Links'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageSearchResultTile), findsOneWidget);
    expect(find.text('Mira'), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);
    await tester.tap(find.text(link));
    await tester.pumpAndSettle();
    expect(find.byType(MessageSearchResultTile), findsNothing);
    expect(find.byKey(const ValueKey('link')).hitTestable(), findsOneWidget);

    await tester.pumpWidget(page(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Go to date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageSearchResultTile), findsNothing);
    expect(
      find.byKey(const ValueKey('location')).hitTestable(),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    mesh.dispose();
  });
}
