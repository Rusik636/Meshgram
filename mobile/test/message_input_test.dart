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
import 'package:meshgrame/ui/message_link_metadata.dart';
import 'package:meshgrame/ui/message_links.dart';
import 'package:meshgrame/ui/style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'find_control.dart';

void main() {
  testWidgets(
    'Desktop composer aligns with its buttons and sends on Enter',
    (tester) async {
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
      final field = find.descendant(
        of: input,
        matching: find.byType(TextField),
      );
      final draft = tester.widget<TextField>(field).controller!;
      final attachment = findControl('Attachments');
      expect(tester.getRect(input).height, tester.getRect(attachment).height);
      expect(tester.getRect(input).top, tester.getRect(attachment).top);

      await tester.enterText(field, 'First Next');
      draft.selection = const TextSelection(baseOffset: 5, extentOffset: 6);
      final previousCount = mesh.messages(peer.id).length;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(draft.text, 'First\nNext');
      expect(draft.selection, const TextSelection.collapsed(offset: 6));
      expect(tester.getSize(input).height, greaterThan(meshGlassButtonExtent));
      expect(tester.getRect(input).bottom, tester.getRect(attachment).bottom);
      expect(mesh.draft(peer.id), draft.text);
      expect(mesh.messages(peer.id), hasLength(previousCount));

      draft.value = draft.value.copyWith(
        composing: const TextRange(start: 6, end: 10),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(mesh.messages(peer.id), hasLength(previousCount));
      draft.clearComposing();

      final enter =
          Theme.of(tester.element(field)).platform == TargetPlatform.macOS
          ? LogicalKeyboardKey.numpadEnter
          : LogicalKeyboardKey.enter;
      await tester.sendKeyDownEvent(enter);
      await tester.sendKeyRepeatEvent(enter);
      await tester.sendKeyUpEvent(enter);
      await tester.pumpAndSettle();
      expect(mesh.messages(peer.id), hasLength(previousCount + 1));
      expect(mesh.messages(peer.id).last.text, 'First\nNext');
      expect(draft.text, isEmpty);
      expect(tester.getRect(input).height, tester.getRect(attachment).height);
      await tester.pumpWidget(const SizedBox());
      mesh.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets('iOS keeps replies and link previews with the same editor', (
    tester,
  ) async {
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
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    });
    SharedPreferences.setMockInitialValues({});
    final mesh = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: BleTransport(),
      adapters: const [MeshtasticAdapter()],
      preview: true,
    );
    final peer = mesh.cache!.peers['ch:0']!;
    const draft = 'https://example.org/ios-route';
    await _cacheLink(tester, draft);
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

    final composer = tester.widget<MessageInput>(input);
    final message = mesh.messages(peer.id).first;
    mesh.setReplyDraft(peer.id, message);
    composer.controller.text = draft;
    composer.onChanged(draft);
    await tester.pumpAndSettle();

    expect(tester.widget<MessageInput>(input).accessory?.title, 'Route');
    expect(tester.widget<MessageInput>(input).accessory?.link, isTrue);
    expect(findControl('Cancel reply'), findsNothing);
    expect(findControl('Remove preview'), findsNothing);
    expect(tester.getRect(input).bottom, bottom);
    expect(tester.element(editor), same(original));

    expect(viewId, isNotNull);
    Future<void> dismissAccessory() => messenger.handlePlatformMessage(
      'meshgrame/composer/$viewId',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('dismissAccessory'),
      ),
      (_) {},
    );
    await dismissAccessory();
    await tester.pumpAndSettle();
    expect(mesh.replyDraft(peer.id)?.id, message.id);
    expect(tester.widget<MessageInput>(input).accessory?.text, message.text);
    expect(tester.widget<MessageInput>(input).accessory?.link, isFalse);
    expect(tester.element(editor), same(original));
    await dismissAccessory();
    await tester.pumpAndSettle();
    expect(mesh.replyDraft(peer.id), isNull);
    expect(tester.widget<MessageInput>(input).accessory, isNull);
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
        final composer = find.byType(MessageInput);
        expect(tester.getSize(composer).height, 46);
        expect(tester.getRect(editor), tester.getRect(composer).inflate(8));

        Future<void> receive(String type, Object value) =>
            messenger.handlePlatformMessage(
              'meshgrame/composer/$viewId',
              const StandardMethodCodec().encodeMethodCall(
                MethodCall(type, value),
              ),
              (_) {},
            );

        const multiline = 'Draft\nNext line';
        await receive('editing', {'text': multiline, 'start': 1, 'end': 4});
        await receive('height', 88.0);
        await tester.pump();
        expect(tester.getSize(composer).height, reduceMotion ? 88 : 46);
        if (!reduceMotion) {
          await tester.pump(const Duration(milliseconds: 60));
          expect(tester.getSize(composer).height, inExclusiveRange(46.0, 88.0));
        }
        await tester.pumpAndSettle();
        expect(tester.getSize(composer).height, 88);
        expect(tester.element(editor), same(original));
        expect(controller.text, multiline);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 4),
        );
        expect(changes, [multiline]);

        await receive('editing', {'text': multiline, 'start': 5, 'end': 5});
        expect(controller.selection, const TextSelection.collapsed(offset: 5));
        expect(changes, [multiline]);

        await receive('height', 46.0);
        await tester.pumpAndSettle();
        expect(tester.getSize(composer).height, 46);
        expect(tester.element(editor), same(original));
        expect(controller.text, multiline);
      },
      variant: const TargetPlatformVariant({TargetPlatform.iOS}),
    );
  }

  testWidgets('Android opens reply with the keyboard and keeps the selection', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    SharedPreferences.setMockInitialValues({});
    final mesh = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: BleTransport(),
      adapters: const [MeshtasticAdapter()],
      preview: true,
    );
    final peer = mesh.cache!.peers['node:a']!;
    const link = 'https://example.org/android-route';
    await _cacheLink(tester, link);
    await tester.pumpWidget(
      MaterialApp(
        home: MeshChatPage(controller: mesh, peer: peer),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.byType(MessageInput);
    final field = find.descendant(of: input, matching: find.byType(TextField));
    final original = tester.element(field);
    final originalHeight = tester.getSize(input).height;
    final messages = mesh.messages(peer.id);
    final first = messages.last;
    await tester.drag(find.text(first.text), const Offset(-88, 0));
    await tester.pump();
    expect(mesh.replyDraft(peer.id)?.id, first.id);
    expect(findControl('Cancel reply'), findsNothing);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    final reply = findControl('Cancel reply');
    expect(reply.hitTestable(), findsOneWidget);
    expect(
      find
          .ancestor(of: reply, matching: find.byType(GlassSurface))
          .evaluate()
          .first,
      same(
        find
            .ancestor(of: field, matching: find.byType(GlassSurface))
            .evaluate()
            .first,
      ),
    );
    expect(tester.getRect(input).bottom, lessThanOrEqualTo(584));
    const draft = 'First line\n$link';
    await tester.enterText(field, draft);
    await tester.pumpAndSettle();
    expect(tester.getSize(input).height, greaterThan(originalHeight));
    expect(reply, findsNothing);
    final preview = findControl('Remove preview');
    expect(preview.hitTestable(), findsOneWidget);
    expect(
      find
          .ancestor(of: preview, matching: find.byType(GlassSurface))
          .evaluate()
          .first,
      same(
        find
            .ancestor(of: field, matching: find.byType(GlassSurface))
            .evaluate()
            .first,
      ),
    );
    final editor = tester.widget<TextField>(field).controller!;
    const selection = TextSelection(baseOffset: 1, extentOffset: 5);
    editor.selection = selection;
    final next = messages[messages.length - 2];
    await tester.longPress(find.text(next.text).hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(mesh.replyDraft(peer.id)?.id, next.id);
    expect(editor.selection, selection);
    expect(editor.text, draft);

    await tester.tap(reply);
    await tester.pumpAndSettle();
    expect(mesh.replyDraft(peer.id), isNull);
    expect(editor.selection, selection);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(preview.hitTestable(), findsOneWidget);
    expect(tester.element(field), same(original));

    await tester.drag(
      find.text(first.text).hitTestable(),
      const Offset(-88, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(findControl('Send'));
    await tester.pumpAndSettle();
    expect(mesh.messages(peer.id).last.replyTo, mesh.referenceFor(first));
    expect(mesh.messages(peer.id).last.text, draft);
    expect(mesh.replyDraft(peer.id), isNull);
    expect(editor.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
    mesh.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}

Future<void> _cacheLink(WidgetTester tester, String url) async {
  final uri = Uri.parse(url);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MessageLinkPreview(
          uri: uri,
          loadMetadata: (_) async =>
              MessageLinkMetadata(siteName: 'Example', title: 'Route'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
