// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
    final shared = controller.contactAttachment(attachment.text);
    expect(shared?.id, contact.id);
    expect(shared?.shortName, 'LR');
    expect(controller.draft(chat.id), draft);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      draft,
    );
    expect(find.text(contact.name), findsOneWidget);
    expect(_contactCaption('LR'), findsOneWidget);
    expect(find.text('!00003039'), findsOneWidget);
    expect(find.text(contact.id), findsNothing);
    expect(find.text(attachment.text), findsNothing);
    expect(_contactAvatar(attachment.id, contact.name), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('opens a contact profile and centers Message', (tester) async {
    const contact = (id: 'node:5151', name: 'Bridge relay');
    final (controller, chat) = await _openChat(
      tester,
      prepare: (controller, peer) {
        final link = const MeshtasticAdapter()
            .contactCode(
              (
                id: contact.id,
                name: contact.name,
                writable: true,
                channel: false,
              ),
              (publicKey: 'ae' * 32, type: null, shortName: 'BR'),
            )!
            .toString();
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
    final write = find.widgetWithText(TextButton, 'Message');
    final card = find
        .ancestor(of: avatar, matching: find.byType(InkWell))
        .first;
    expect(tester.getCenter(write).dx, closeTo(tester.getCenter(card).dx, .01));
    final shortName = _contactCaption('BR');
    final address = find.text('!0000141f');
    final divider = find.descendant(of: card, matching: find.byType(Divider));
    expect(find.text(contact.id), findsNothing);
    expect(
      tester.getTopLeft(shortName).dy,
      greaterThan(tester.getTopLeft(find.text(contact.name)).dy),
    );
    expect(
      tester.getTopLeft(address).dy,
      greaterThan(tester.getTopLeft(shortName).dy),
    );
    expect(tester.getCenter(divider).dy, lessThan(tester.getTopLeft(write).dy));
    expect(find.text('Add contact'), findsNothing);

    await tester.tap(avatar);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final profile = tester.widget<MeshChatProfile>(
      find.byType(MeshChatProfile),
    );
    expect(profile.peer.id, contact.id);
    expect(controller.cache!.peers[contact.id]?.name, contact.name);
    expect(controller.cache!.identities[contact.id]?.publicKey, 'ae' * 32);
    expect(controller.cache!.identities[contact.id]?.shortName, 'BR');
    expect(controller.messages(chat.id).last.id, 'shared-contact');

    await tester.tap(
      find.descendant(
        of: find.byType(MeshChatProfile),
        matching: find.byTooltip('Back'),
      ),
    );
    await tester.pumpAndSettle();
    expect(avatar, findsOneWidget);
    await tester.tap(write);
    await tester.pumpAndSettle();
    expect(find.byType(MeshChatProfile), findsNothing);
    final conversation = tester.widget<MeshChatPage>(find.byType(MeshChatPage));
    expect(conversation.peer.id, contact.id);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('searches the current conversation from its shared profile', (
    tester,
  ) async {
    const peer = (
      id: 'node:5151',
      name: 'Bridge relay',
      writable: true,
      channel: false,
    );
    final identity = (publicKey: 'ae' * 32, type: null, shortName: 'BR');
    final (controller, _) = await _openChat(
      tester,
      directPeer: peer,
      prepare: (controller, _) {
        controller.cache!
          ..peers[peer.id] = peer
          ..identities[peer.id] = identity
          ..messages.add(
            MeshMessage(
              id: 'shared-current-contact',
              chat: peer.id,
              author: peer.name,
              text: const MeshtasticAdapter()
                  .contactCode(peer, identity)!
                  .toString(),
              time: DateTime.now(),
              delivery: Delivery.received,
            ),
          );
      },
    );
    await tester.tap(_contactAvatar('shared-current-contact', peer.name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
    await tester.tap(
      find.descendant(
        of: find.byType(MeshChatProfile),
        matching: find.text('Search'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump();

    expect(find.text('Search messages'), findsOneWidget);
    expect(find.byType(MeshChatProfile), findsNothing);
    expect(find.byType(MeshChatPage), findsOneWidget);

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
    expect(find.byTooltip('Copy coordinates'), findsOneWidget);
    expect(find.text('55.750000, 49.140000'), findsOneWidget);
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
    await tester.pump();
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
    await tester.pump(const Duration(seconds: 13));
    expect(controller.messages(chat.id).last.suppressLinkPreview, isFalse);
    expect(tester.widget<MessageLinkPreview>(preview).compact, isFalse);
    expect(find.text('Preview unavailable'), findsNothing);
    final latestUrl = tester.renderObject<RenderParagraph>(
      find.descendant(of: preview, matching: find.byType(RichText)).first,
    );
    final urlRect = latestUrl
        .getBoxesForSelection(
          TextSelection(baseOffset: 6, extentOffset: text.length),
        )
        .first
        .toRect();
    await tester.tapAt(latestUrl.localToGlobal(urlRect.center));
    await tester.pump(const Duration(milliseconds: 350));
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

Finder _contactCaption(String text) => find.byWidgetPredicate(
  (widget) => widget is Text && widget.data == text && widget.maxLines == 1,
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
  Peer? directPeer,
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
  final chat = directPeer ?? controller.cache!.peers['ch:0']!;
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
