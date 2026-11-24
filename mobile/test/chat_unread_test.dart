// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/controller.dart';
import 'package:meshgrame/mesh/network.dart';
import 'package:meshgrame/mesh/store.dart';
import 'package:meshgrame/radio/meshtastic.dart';
import 'package:meshgrame/ui/channel_avatars.dart';
import 'package:meshgrame/ui/chat.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chat = (
  id: 'node:42',
  name: 'Mountain relay',
  writable: true,
  channel: false,
);

MeshMessage _item(int index, {bool outgoing = false, String? chat}) =>
    MeshMessage(
      id: 'packet:$index',
      chat: chat ?? _chat.id,
      author: outgoing ? 'You' : _chat.name,
      text: 'Packet $index: reporting from the mountain summit.',
      time: DateTime(2026, 11, 22, 12, index),
      delivery: outgoing ? Delivery.acknowledged : Delivery.received,
    );

void _receive(ChatCache cache, MeshMessage message, {required bool unread}) {
  if (unread) cache.addUnread(message);
  cache.messages.add(message);
}

void main() {
  test(
    'migrates unread counts over incoming history and persists exact IDs',
    () {
      final source = ChatCache()
        ..messages.addAll([_item(1), _item(2), _item(3, outgoing: true)])
        ..unread[_chat.id] = 2;
      final restored = ChatCache.fromJson(source.toJson());
      expect(restored.unreadIds(_chat.id), {'packet:1', 'packet:2'});
      final laterArrival = _item(0);
      _receive(restored, laterArrival, unread: true);
      expect(restored.markReadThrough(_chat.id, laterArrival.id), isTrue);
      expect(restored.unread[_chat.id], 2);
      final reopened = ChatCache.fromJson(restored.toJson());
      expect(reopened.unreadIds(_chat.id), {'packet:1', 'packet:2'});
    },
  );

  test(
    'pruning drops orphaned unread counts and preserves recent messages',
    () {
      final cache = ChatCache();
      _receive(cache, _item(1, chat: 'node:forgotten'), unread: true);
      _receive(cache, _item(2), unread: true);
      _receive(cache, _item(3), unread: true);
      cache.trimHistory(1);
      expect(cache.unread, {_chat.id: 1});
      expect(cache.unreadIds(_chat.id), {'packet:3'});
    },
  );

  test('manual unread survives reload without increasing message totals', () {
    final cache = ChatCache()..markedUnread.add(_chat.id);
    final restored = ChatCache.fromJson(cache.toJson());
    expect(restored.markedUnread, {_chat.id});
    expect(restored.unread, isEmpty);
    restored.markRead(_chat.id);
    expect(restored.markedUnread, isEmpty);
  });

  testWidgets(
    'opens on first unread and advances only through visible history',
    (tester) async {
      final controller = await _mount(tester, firstUnread: 30);
      final scroll = tester
          .widget<ChatMessageList>(find.byType(ChatMessageList))
          .controller!;
      final latest = find.byTooltip('Go to latest message');

      final unread = find.byKey(const ValueKey('unread-divider'));
      final label = find.text('Unread messages');
      final lines = find.descendant(of: unread, matching: find.byType(Divider));
      expect(label, findsOneWidget);
      expect(lines, findsNWidgets(2));
      expect(
        tester.getSize(lines.first).width,
        tester.getSize(lines.last).width,
      );
      expect(tester.getCenter(label).dx, tester.getCenter(unread).dx);
      expect(
        find.byKey(const ValueKey('packet:30')).hitTestable(),
        findsOneWidget,
      );
      expect(scroll.offset, greaterThan(200));
      expect(controller.cache!.unread[_chat.id], inInclusiveRange(1, 29));
      expect(latest.hitTestable(), findsOneWidget);

      await tester.tap(latest);
      await tester.pumpAndSettle();

      expect(scroll.offset, closeTo(0, .1));
      expect(controller.cache!.unread[_chat.id], isNull);
      expect(latest, findsNothing);
      expect(
        find.byKey(const ValueKey('packet:59')).hitTestable(),
        findsOneWidget,
      );
      await _unmount(tester, controller);
    },
  );

  testWidgets(
    'new packets preserve older scroll position and increase the jump badge',
    (tester) async {
      final controller = await _mount(tester);
      final scroll = tester
          .widget<ChatMessageList>(find.byType(ChatMessageList))
          .controller!;
      scroll.jumpTo(610);
      await tester.pumpAndSettle();
      final anchor = find.byKey(const ValueKey('packet:48'));
      expect(anchor.hitTestable(), findsOneWidget);
      final y = tester.getTopLeft(anchor).dy;

      _receive(controller.cache!, _item(60), unread: true);
      controller.refreshNodePresence();
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(anchor).dy, closeTo(y, 1.0));
      expect(controller.cache!.unread[_chat.id], 1);
      expect(find.bySemanticsLabel('Unread: 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Go to latest message'));
      await tester.pumpAndSettle();
      expect(controller.cache!.unread[_chat.id], isNull);

      _receive(controller.cache!, _item(61), unread: true);
      controller.refreshNodePresence();
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(0, .1));
      expect(controller.cache!.unread[_chat.id], isNull);
      await _unmount(tester, controller);
    },
  );

  testWidgets('keeps arrivals unread behind a route and while backgrounded', (
    tester,
  ) async {
    final controller = await _mount(tester);
    final context = tester.element(find.byType(MeshChatPage));
    final dialog = showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('Overlay')),
    );
    await tester.pumpAndSettle();
    _receive(controller.cache!, _item(60), unread: true);
    controller.refreshNodePresence();
    await tester.pumpAndSettle();
    expect(controller.cache!.unread[_chat.id], 1);
    expect(controller.viewingLatest(controller.active!, _chat.id), isFalse);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    await dialog;
    expect(controller.cache!.unread[_chat.id], isNull);
    expect(controller.viewingLatest(controller.active!, _chat.id), isTrue);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    _receive(controller.cache!, _item(61), unread: true);
    controller.refreshNodePresence();
    await tester.pump();
    expect(controller.cache!.unread[_chat.id], 1);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(controller.cache!.unread[_chat.id], isNull);
    await _unmount(tester, controller);
  });
}

Future<MeshController> _mount(
  WidgetTester tester, {
  int firstUnread = 60,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues({});
  final controller = MeshController(
    store: MeshStore(await SharedPreferences.getInstance()),
    transport: _UnusedTransport(),
    adapters: const [MeshtasticAdapter()],
    preview: true,
  );
  final cache = controller.cache!;
  cache.peers[_chat.id] = _chat;
  for (var i = 0; i < 60; i++) {
    _receive(cache, _item(i), unread: i >= firstUnread);
  }
  await tester.pumpWidget(
    MaterialApp(
      home: MeshChatPage(controller: controller, peer: _chat),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _unmount(WidgetTester tester, MeshController controller) async {
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
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
