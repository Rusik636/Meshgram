// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/controller.dart';
import 'package:meshgrame/mesh/network.dart';
import 'package:meshgrame/mesh/store.dart';
import 'package:meshgrame/radio/meshtastic.dart';
import 'package:meshgrame/ui/message_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MeshController controllerFor(MeshStore store) => MeshController(
    store: store,
    transport: _UnusedTransport(),
    adapters: const [MeshtasticAdapter()],
    preview: true,
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'records successful reactions in order across chats and restarts',
    () async {
      final store = MeshStore(await SharedPreferences.getInstance());
      final controller = controllerFor(store);
      addTearDown(controller.dispose);
      final channel = controller.cache!.peers['ch:0']!;
      final direct = controller.cache!.peers['node:a']!;
      final channelMessage = controller.messages(channel.id).last;
      final directMessage = controller.messages(direct.id).last;

      expect(controller.recentReactionEmojis, isEmpty);
      expect(await controller.react(channel, directMessage, '🫡'), isFalse);
      expect(controller.recentReactionEmojis, isEmpty);
      expect(await controller.react(channel, channelMessage, '👍🏾'), isTrue);
      expect(await controller.react(channel, channelMessage, '❤️'), isTrue);
      expect(await controller.react(direct, directMessage, '🔥'), isTrue);
      expect(await controller.react(direct, directMessage, '❤'), isTrue);
      expect(controller.recentReactionEmojis, ['❤', '🔥', '👍🏾']);

      expect(await controller.react(channel, channelMessage, '👋🏻'), isTrue);
      expect(controller.recentReactionEmojis, ['👋🏻', '❤', '🔥']);
      final reopened = controllerFor(store);
      addTearDown(reopened.dispose);
      expect(reopened.recentReactionEmojis, ['👋🏻', '❤', '🔥']);
    },
  );

  test('upgrades recover only local reaction history across radios', () async {
    final store = MeshStore(await SharedPreferences.getInstance());
    final earlier = ChatCache()
      ..reactions.addAll([
        MeshReaction(
          'ch:0',
          'msg',
          'local',
          '❤️',
          own: true,
          time: DateTime(2025, 1, 2),
        ),
        MeshReaction('ch:0', 'msg2', 'remote', '⚡', time: DateTime(2025, 1, 4)),
      ]);
    await store.save('meshcore/demo-core', earlier);
    final controller = controllerFor(store);
    addTearDown(controller.dispose);
    controller.cache!.reactions.add(
      MeshReaction(
        'ch:0',
        'msg3',
        'local',
        '🫱🏻‍🫲🏼',
        own: true,
        time: DateTime(2025, 1, 3),
      ),
    );
    expect(controller.recentReactionEmojis, ['🫱🏻‍🫲🏼', '❤️']);
  });

  testWidgets('the quick strip starts with recents then fills from defaults', (
    tester,
  ) async {
    const start = 'Open';
    var recent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showMessageMenu(
                  context: context,
                  anchor: const Rect.fromLTWH(50, 250, 170, 50),
                  canReact: true,
                  canReply: true,
                  recentReactions: recent,
                  outgoing: false,
                  bubble: const SizedBox(width: 170, height: 50),
                  reactions: const [],
                  onOpenProfile: (_) {},
                  details: const SizedBox(),
                ),
              ),
              child: const Text(start),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(start));
    await tester.pumpAndSettle();
    final thumbs = find.byTooltip('React 👍');
    expect(
      tester.getCenter(thumbs).dx,
      lessThan(tester.getCenter(find.byTooltip('React ❤️')).dx),
    );
    await tester.tap(thumbs);
    await tester.pumpAndSettle();

    recent = ['👍🏾', '❤', '🫱🏻‍🫲🏼'];
    await tester.tap(find.text(start));
    await tester.pumpAndSettle();
    final tone = find.byTooltip('React 👍🏾');
    final heart = find.byTooltip('React ❤');
    final handshake = find.byTooltip('React 🫱🏻‍🫲🏼');
    expect(find.byTooltip('React ❤️'), findsNothing);
    final positions = [
      tone,
      heart,
      handshake,
      thumbs,
    ].map((item) => tester.getCenter(item).dx);
    expect(positions, orderedEquals(positions.toList()..sort()));
  });
}

class _UnusedTransport implements RadioTransport {
  @override
  Future<RadioLink> connect(Radio radio, String service) =>
      throw UnimplementedError();

  @override
  Future<void> scan(
    Map<String, String> services,
    void Function(List<DiscoveredRadio>) update,
  ) async {}

  @override
  Future<void> stopScan() async {}
}
