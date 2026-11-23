// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/contact_attachment.dart';
import 'package:meshgrame/mesh/controller.dart';
import 'package:meshgrame/mesh/network.dart';
import 'package:meshgrame/mesh/nodes.dart';
import 'package:meshgrame/mesh/store.dart';
import 'package:meshgrame/radio/meshtastic.dart';
import 'package:meshgrame/ui/chat.dart';
import 'package:meshgrame/ui/mesh_map.dart';
import 'package:meshgrame/ui/message_links.dart';
import 'package:meshgrame/ui/style.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('sends a contact as a separate message and keeps the draft', (
    tester,
  ) async {
    final (controller, chat) = await _openChat(tester);
    const contact = (
      id: 'node:12345',
      name: 'Lake radio',
      writable: true,
      channel: false,
    );
    controller.cache!
      ..peers[contact.id] = contact
      ..identities[contact.id] = (
        publicKey: '12' * 32,
        type: null,
        shortName: 'LR',
      );
    const draft = 'Meet at the bridge';
    await tester.enterText(find.byType(TextField), draft);
    await _openAttachment(tester, 'Contact');
    await tester.tap(find.byTooltip('Sort by'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    expect(controller.nodeSort, NodeSort.name);
    await tester.tap(find.text(contact.name));
    await tester.pumpAndSettle();

    final sent = controller.messages(chat.id).where((item) => item.outgoing);
    final attachment = sent.single;
    expect(attachment.isAttachment, isTrue);
    expect(controller.contactAttachment(attachment.text)?.id, contact.id);
    expect(controller.draft(chat.id), draft);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      draft,
    );
    expect(find.text(contact.name), findsOneWidget);
    expect(find.text(attachment.text), findsNothing);
    expect(_contactAvatar(attachment.id, contact.name), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('imports a received contact and opens its conversation', (
    tester,
  ) async {
    const contact = (id: 'node:5151', name: 'Bridge relay');
    final (controller, chat) = await _openChat(
      tester,
      prepare: (controller, peer) {
        final link = compactContactLink((
          network: 'meshtastic',
          id: contact.id,
          name: contact.name,
          publicKey: 'ae' * 32,
          type: null,
          shortName: null,
        ), 200)!;
        controller.cache!.messages.add(
          MeshMessage(
            id: 'shared-contact',
            chat: peer.id,
            author: 'Radio A',
            text: link,
            time: DateTime.now(),
            delivery: Delivery.received,
          ),
        );
      },
    );
    expect(controller.cache!.peers[contact.id], isNull);
    expect(find.text(contact.name), findsOneWidget);
    final avatar = _contactAvatar('shared-contact', contact.name);
    expect(avatar, findsOneWidget);
    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();
    expect(controller.cache!.peers[contact.id]?.name, contact.name);
    expect(find.text('Add contact'), findsNothing);
    expect(avatar, findsOneWidget);
    expect(controller.messages(chat.id).last.id, 'shared-contact');

    await tester.tap(find.widgetWithText(TextButton, 'Message'));
    await tester.pumpAndSettle();
    final conversation = tester.widget<MeshChatPage>(find.byType(MeshChatPage));
    expect(conversation.peer.id, contact.id);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('sends a point and opens its message preview on a map', (
    tester,
  ) async {
    final (controller, chat) = await _openChat(tester);
    final point = controller.cache!.localPosition!;
    await tester.enterText(find.byType(TextField), 'Keep this pending');
    await _openAttachment(tester, 'Location');
    await tester.tap(find.text('Send location'));
    await tester.pumpAndSettle();

    final sent = controller.messages(chat.id).where((item) => item.outgoing);
    expect(sent.single.text, 'geo:55.750000,49.140000');
    expect(controller.draft(chat.id), 'Keep this pending');
    final preview = find.byType(MeshLocationPreview);
    expect(preview, findsOneWidget);
    expect(tester.widget<MeshLocationPreview>(preview).position, point);
    await tester.tap(
      find.descendant(of: preview, matching: find.text('Location')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Coordinates'), findsOneWidget);
    final map = tester.widget<MeshMap>(find.byType(MeshMap));
    expect(map.interactive, isTrue);
    expect(map.pins.single.position, point);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('keeps URLs clickable when their previews are dismissed', (
    tester,
  ) async {
    final (controller, chat) = await _openChat(tester);
    const urlChannel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = tester.binding.defaultBinaryMessenger;
    final opened = <String>[];
    messenger.setMockMethodCallHandler(urlChannel, (method) async {
      if (method.method != 'launch') return false;
      opened.add((method.arguments as Map)['url'] as String);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(urlChannel, null));

    const text = 'Check https://example.org/route';
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
    final preview = find.byType(MessageLinkPreview);
    expect(tester.widget<MessageLinkPreview>(preview).compact, isTrue);

    await tester.tap(find.byTooltip('Remove preview'));
    await tester.pumpAndSettle();
    expect(preview, findsNothing);
    expect(controller.draft(chat.id), text);
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    final sent = controller.messages(chat.id).last;
    expect(sent.text, text);
    expect(sent.suppressLinkPreview, isTrue);
    expect(preview, findsNothing);
    final restored = ChatCache.fromJson(controller.cache!.toJson());
    expect(restored.messages.last.suppressLinkPreview, isTrue);

    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(MessageLinkifiedText),
        matching: find.byType(RichText),
      ),
    );
    final urls = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 6, extentOffset: text.length),
    );
    await tester.tapAt(paragraph.localToGlobal(urls.first.toRect().center));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(opened, ['https://example.org/route']);

    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
    expect(tester.widget<MessageLinkPreview>(preview).compact, isTrue);
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(controller.messages(chat.id).last.suppressLinkPreview, isFalse);
    expect(tester.widget<MessageLinkPreview>(preview).compact, isFalse);
    await tester.tap(
      find.descendant(of: preview, matching: find.text('example.org')),
    );
    await tester.pumpAndSettle();
    expect(opened, ['https://example.org/route', 'https://example.org/route']);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

Finder _contactAvatar(String messageId, String contactName) => find.descendant(
  of: find.byKey(ValueKey(messageId)),
  matching: find.byWidgetPredicate(
    (widget) => widget is MeshAvatar && widget.name == contactName,
  ),
);

Future<void> _openAttachment(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip('Attachments'));
  await tester.pumpAndSettle();
  if (item != 'Location') {
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }
}

Future<(MeshController, Peer)> _openChat(
  WidgetTester tester, {
  void Function(MeshController, Peer)? prepare,
}) async {
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
  final chat = controller.cache!.peers['ch:0']!;
  prepare?.call(controller, chat);
  await tester.pumpWidget(
    MaterialApp(
      home: MeshChatPage(controller: controller, peer: chat),
    ),
  );
  await tester.pumpAndSettle();
  return (controller, chat);
}

class _UnusedTransport implements RadioTransport {
  @override
  Future<RadioLink> connect(Radio radio, String service) =>
      throw UnimplementedError();

  @override
  Future<void> scan(
    Map<String, String> services,
    void Function(List<DiscoveredRadio>) update,
  ) => throw UnimplementedError();

  @override
  Future<void> stopScan() async {}
}
