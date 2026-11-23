// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/controller.dart';
import 'package:meshgrame/mesh/store.dart';
import 'package:meshgrame/radio/ble_transport.dart';
import 'package:meshgrame/radio/meshtastic.dart';
import 'package:meshgrame/ui/chat.dart';
import 'package:meshgrame/ui/message_input.dart';
import 'package:meshgrame/ui/style.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('iOS keeps replies and link previews with the same editor', (
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
    await tester.pumpWidget(
      MaterialApp(
        home: MeshChatPage(controller: mesh, peer: peer),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.byType(MessageInput);
    final editor = find.descendant(of: input, matching: find.byType(UiKitView));
    final original = tester.element(editor);
    final bottom = tester.getRect(input).bottom;
    expect(
      find.ancestor(of: editor, matching: find.byType(GlassSurface)),
      findsNothing,
    );

    const draft = 'https://example.org/route';
    final composer = tester.widget<MessageInput>(input);
    mesh.setReplyDraft(peer.id, mesh.messages(peer.id).first);
    composer.controller.text = draft;
    composer.onChanged(draft);
    await tester.pump();

    final reply = find.byTooltip('Cancel reply');
    final link = find.byTooltip('Remove preview');
    expect(tester.getRect(reply).bottom, lessThan(tester.getRect(link).top));
    expect(tester.getRect(link).bottom, lessThan(tester.getRect(input).top));
    expect(tester.getRect(input).bottom, bottom);
    expect(tester.element(editor), same(original));

    await tester.tap(reply);
    await tester.pump();
    expect(reply, findsNothing);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(link, findsNothing);
    expect(tester.element(editor), same(original));
    expect(mesh.draft(peer.id), draft);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    mesh.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  for (final reduceMotion in [false, true]) {
    testWidgets(
      'iOS keeps the editor and draft as height changes, reduced motion $reduceMotion',
      (tester) async {
        final controller = TextEditingController(text: 'Draft');
        addTearDown(controller.dispose);
        final changes = <String>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        int? viewId;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
          call,
        ) async {
          if (call case MethodCall(
            method: 'create',
            arguments: {'id': final int id, 'viewType': 'meshgrame/composer'},
          )) {
            viewId = id;
          }
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(
            SystemChannels.platform_views,
            null,
          );
        });
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduceMotion),
              child: Scaffold(
                body: MessageInput(
                  controller: controller,
                  onChanged: changes.add,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(viewId, isNotNull);
        final editor = find.byType(UiKitView);
        final original = tester.element(editor);
        expect(tester.getSize(editor).height, 46);

        Future<void> receive(String type, Object value) =>
            messenger.handlePlatformMessage(
              'meshgrame/composer/$viewId',
              const StandardMethodCodec().encodeMethodCall(
                MethodCall(type, value),
              ),
              (_) {},
            );

        const multiline = 'Draft\nNext line';
        await receive('text', multiline);
        await receive('height', 88.0);
        await tester.pump();
        expect(tester.getSize(editor).height, reduceMotion ? 88 : 46);
        if (!reduceMotion) {
          await tester.pump(const Duration(milliseconds: 60));
          expect(tester.getSize(editor).height, inExclusiveRange(46.0, 88.0));
        }
        await tester.pumpAndSettle();
        expect(tester.getSize(editor).height, 88);
        expect(tester.element(editor), same(original));
        expect(controller.text, multiline);
        expect(changes, [multiline]);

        await receive('height', 46.0);
        await tester.pumpAndSettle();
        expect(tester.getSize(editor).height, 46);
        expect(tester.element(editor), same(original));
        expect(controller.text, multiline);
      },
      variant: const TargetPlatformVariant({TargetPlatform.iOS}),
    );
  }
}
