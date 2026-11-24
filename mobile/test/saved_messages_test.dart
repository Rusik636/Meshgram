// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/controller.dart';
import 'package:meshgrame/mesh/network.dart';
import 'package:meshgrame/mesh/store.dart';
import 'package:meshgrame/radio/meshtastic.dart';
import 'package:meshgrame/ui/mesh_map.dart';
import 'package:meshgrame/ui/chat.dart';
import 'package:meshgrame/ui/radio_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'find_control.dart';

void main() {
  testWidgets('saved messages survive local history clearing without a radio', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = MeshStore(await SharedPreferences.getInstance());
    const radio = (device: 'test', name: 'Heltec', network: 'meshtastic');
    const peer = (id: 'ch:0', name: 'Test', channel: true, writable: true);
    final origin = ChatCache()..peers[peer.id] = peer;
    final time = DateTime(2026, 11, 24, 11, 20);
    final texts = [
      'Summit report https://example.org/route',
      'geo:55.75,49.14',
    ];
    for (final (index, text) in texts.indexed) {
      origin.messages.add(
        MeshMessage(
          id: 'message:$index',
          chat: peer.id,
          author: 'Mira',
          text: text,
          time: time,
          delivery: Delivery.received,
        ),
      );
    }
    await store.setRadios([radio]);
    await store.setActive(radioKey(radio));
    await store.save(radioKey(radio), origin);
    final transport = _OfflineTransport();
    MeshController createController() => MeshController(
      store: store,
      transport: transport,
      adapters: const [MeshtasticAdapter()],
    );

    final controller = createController();
    await Future.wait([
      for (final message in origin.messages)
        controller.toggleSavedMessage(peer, message),
    ]);
    await controller.setSavedLabels(controller.savedMessages.last, [
      'route',
      ' route ',
      '',
    ]);
    controller.clearChat(peer.id);
    expect(controller.messages(peer.id), isEmpty);
    controller.dispose();

    final restored = createController();
    expect(restored.connected, isFalse);
    expect(restored.savedMessages, hasLength(2));
    final saved = restored.savedMessages.last;
    expect(saved.labels, ['route']);
    expect(saved.author, 'Mira');
    expect(saved.chatName, 'Test');
    expect(saved.radioName, 'Heltec');
    expect(saved.message.time, time);
    expect(saved.message.text, texts.first);

    await tester.pumpWidget(
      MaterialApp(home: SavedMessagesPage(controller: restored)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mira'), findsNWidgets(2));
    expect(find.text('Test · Heltec'), findsNWidgets(2));
    expect(find.text('route'), findsOneWidget);
    expect(find.text(texts.first, findRichText: true), findsOneWidget);
    final position = tester.widget<MeshLocationPreview>(
      find.byType(MeshLocationPreview),
    );
    expect(position.position, (latitude: 55.75, longitude: 49.14));
    expect(position.loadTiles, isFalse);
    await tester.tap(find.text('Go to original').first);
    await tester.pumpAndSettle();
    expect(
      find.text('This message is no longer in local history'),
      findsOneWidget,
    );
    expect(transport.connections, 0);
    await tester.pumpWidget(const SizedBox());
    restored.dispose();
  });

  testWidgets('opening our own node saves notes locally in the same chat', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = MeshStore(await SharedPreferences.getInstance());
    const radio = (device: 'test', name: 'Heltec', network: 'meshtastic');
    const own = (
      id: 'node:42',
      name: 'My radio',
      channel: false,
      writable: false,
    );
    final cache = ChatCache()..radioNodeNumber = 42;
    await store.setRadios([radio]);
    await store.setActive(radioKey(radio));
    await store.save(radioKey(radio), cache);
    final transport = _OfflineTransport();
    final controller = MeshController(
      store: store,
      transport: transport,
      adapters: const [MeshtasticAdapter()],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMeshChat(context, controller, own),
            child: const Text('Open own node'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open own node'));
    await tester.pumpAndSettle();
    expect(find.byType(SavedMessagesPage), findsOneWidget);
    expect(find.byType(MeshChatPage), findsNothing);
    const note = 'Keep this for later';
    await tester.enterText(find.byType(EditableText), note);
    await tester.pumpAndSettle();
    await tester.tap(findControl('Save note'));
    await tester.pumpAndSettle();
    expect(find.text(note), findsOneWidget);
    expect(store.savedMessages.single.isNote, isTrue);
    expect(store.savedMessages.single.message.text, note);
    expect(store.savedChatDraft, isEmpty);
    expect(transport.connections, 0);
    await tester.tap(find.text('Heltec'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.widget<RadioSettingsPage>(find.byType(RadioSettingsPage)).radio,
      radio,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

class _OfflineTransport implements RadioTransport {
  int connections = 0;

  @override
  Future<RadioLink> connect(Radio radio, String service) {
    connections++;
    throw StateError('Saved messages require no radio connection');
  }

  @override
  Future<void> scan(
    Map<String, String> services,
    void Function(List<DiscoveredRadio>) update,
  ) async {}

  @override
  Future<void> stopScan() async {}
}
