// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/controller.dart';
import 'package:meshgrame/mesh/store.dart';
import 'package:meshgrame/radio/ble_transport.dart';
import 'package:meshgrame/radio/meshtastic.dart';
import 'package:meshgrame/ui/chat.dart';
import 'package:meshgrame/ui/chat_attachments.dart';
import 'package:meshgrame/ui/home.dart';
import 'package:meshgrame/ui/ios_control.dart';
import 'package:meshgrame/ui/mesh_map.dart';
import 'package:meshgrame/ui/navigation.dart';
import 'package:meshgrame/ui/node_list.dart';
import 'package:meshgrame/ui/search_field.dart';
import 'package:meshgrame/ui/style.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  testWidgets('iOS morphs the paperclip and reverses an interrupted opening', (
    tester,
  ) async {
    final controller = await _openIosChat(tester);
    final chat = find.byType(MeshChatPage);
    final back = useIosControls
        ? _nativeControl('button', symbol: 'chevron.left')
        : find.byTooltip('Back');
    final title = useIosControls
        ? _nativeControl('chatTitle')
        : find.descendant(of: chat, matching: find.text('Тропа'));
    final avatar = useIosControls
        ? _nativeControl('chatAvatar')
        : find.descendant(of: chat, matching: find.byType(MeshAvatar));
    final controls = [
      for (final control in [back, title, avatar])
        find.descendant(of: chat, matching: control),
    ];
    final headerElements = controls.map(tester.element).toList();
    final headerRects = controls.map(tester.getRect).toList();

    void expectStableHeader() {
      for (var i = 0; i < controls.length; i++) {
        expect(tester.element(controls[i]), same(headerElements[i]));
        expect(tester.getRect(controls[i]), headerRects[i]);
      }
    }

    final button = _attachmentSource;
    final source = Rect.fromCenter(
      center: tester.getCenter(button),
      width: 40,
      height: 40,
    );
    final element = tester.element(button);
    await _tapAttachmentControl(tester, button);
    await tester.pump();

    expect(tester.getRect(_paperclipFlight), source);
    expect(_paperclipGlyph, findsOneWidget);
    expect(_sourceHidden(tester, button), isTrue);
    expectStableHeader();

    await tester.pump(const Duration(milliseconds: 110));
    final moving = tester.getRect(_paperclipFlight);
    expect(moving.width, greaterThan(source.width));
    expect(moving.top, lessThan(source.top));

    await tester.tapAt(const Offset(200, 90));
    await tester.pump();
    expect(tester.getRect(_paperclipFlight), moving);
    expect(_sourceHidden(tester, button), isTrue);
    await tester.pump(const Duration(milliseconds: 35));
    expect(tester.getRect(_paperclipFlight).width, lessThan(moving.width));
    await tester.pumpAndSettle();

    expect(_paperclipFlight, findsNothing);
    expect(_paperclipGlyph, findsNothing);
    expect(tester.element(button), same(element));
    expect(_sourceHidden(tester, button), isFalse);
    expectStableHeader();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('iOS restores the paperclip after closing an open sheet', (
    tester,
  ) async {
    final controller = await _openIosChat(tester);
    final button = _attachmentSource;
    final element = tester.element(button);
    await _tapAttachmentControl(tester, button);
    await tester.pumpAndSettle();
    expect(_paperclipFlight, findsNothing);
    expect(_paperclipGlyph, findsNothing);

    final map = find.byType(MeshMap);
    final openRect = tester.getRect(map);
    await _tapAttachmentControl(
      tester,
      useIosControls
          ? _nativeControl('button', symbol: 'xmark')
          : find.byTooltip('Close'),
    );
    await tester.pump();
    expect(tester.getRect(_paperclipFlight), openRect);
    await tester.pump(const Duration(milliseconds: 225));
    expect(tester.getRect(_paperclipFlight).width, lessThan(openRect.width));
    expect(_paperclipGlyph, findsOneWidget);
    expect(_sourceHidden(tester, button), isTrue);
    await tester.pumpAndSettle();

    expect(_paperclipFlight, findsNothing);
    expect(tester.element(button), same(element));
    expect(_sourceHidden(tester, button), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets(
    'iOS opens and closes attachments without a reduced-motion morph',
    (tester) async {
      final controller = await _openIosChat(tester, reduceMotion: true);
      final button = _attachmentSource;
      await _tapAttachmentControl(tester, button);
      await tester.pump();
      expect(find.byType(MeshMap), findsOneWidget);
      expect(_paperclipFlight, findsNothing);
      await _tapAttachmentControl(
        tester,
        useIosControls
            ? _nativeControl('button', symbol: 'xmark')
            : find.byTooltip('Close'),
      );
      await tester.pump();
      expect(_paperclipFlight, findsNothing);
      expect(_sourceHidden(tester, button), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets('selects a mesh contact after filtering the node list', (
    tester,
  ) async {
    String? result;
    await _openPicker(tester, (value) => result = value);
    await tester.tap(find.text('Contact'));
    await tester.pumpAndSettle();
    expect(find.text('Мира Соколова'), findsOneWidget);
    expect(find.text('Илья Ветров'), findsOneWidget);
    expect(find.byType(MeshAvatar), findsNWidgets(2));

    await _startContactSearch(tester);
    await tester.enterText(_contactEditor, 'сокол');
    await tester.pumpAndSettle();
    expect(find.text('Илья Ветров'), findsNothing);

    await tester.tap(find.text('Мира Соколова'));
    await tester.pumpAndSettle();
    expect(result, _contacts.first.link);
    expect(find.byType(MeshTabBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sorts contacts with the Nodes picker and keeps the shared rows',
    (tester) async {
      await _openPicker(tester, (_) {});
      await tester.tap(find.text('Contact'));
      await tester.pumpAndSettle();

      Future<List<String>> sortedBy(String option) async {
        await tester.tap(find.byTooltip('Sort by'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(option));
        await tester.pumpAndSettle();
        return tester
            .widgetList<MeshNodeRow>(find.byType(MeshNodeRow))
            .map((row) => row.peer.name)
            .toList();
      }

      expect(await sortedBy('Name'), ['Илья Ветров', 'Мира Соколова']);
      expect(await sortedBy('Last heard'), ['Мира Соколова', 'Илья Ветров']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'morphs the corner search button into the bottom field and back',
    (tester) async {
      await _openPicker(tester, (_) {});
      await tester.tap(find.text('Contact'));
      await tester.pumpAndSettle();

      final button = find.byTooltip('Search nodes');
      final control = find.byKey(
        const ValueKey('attachment-contact-search-control'),
      );
      final compact = tester.getRect(control);
      expect(compact.size, const Size.square(48));
      expect(find.byTooltip('Expand'), findsNothing);
      expect(find.byType(MeshSearchLauncher), findsNothing);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final opening = tester.getRect(control);
      expect(opening.width, greaterThan(compact.width));
      expect(opening.left, lessThan(compact.left));
      final cancel = find.byTooltip('Close search');
      final movingCancel = tester.getRect(cancel);

      await tester.pumpAndSettle();
      final expanded = tester.getRect(control);
      expect(expanded.width, greaterThan(opening.width));
      expect(expanded.bottom, closeTo(844 - 8, 1));
      expect(tester.getRect(cancel).left, lessThan(movingCancel.left));
      expect(_contactEditor, findsOneWidget);
      expect(find.text('Contacts'), findsOneWidget);
      expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
      expect(find.byType(MeshTabBar), findsNothing);
      await tester.tap(cancel);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final closing = tester.getRect(control);
      expect(closing.width, lessThan(expanded.width));
      expect(closing.width, greaterThan(compact.width));
      await tester.pumpAndSettle();
      expect(tester.getRect(control), compact);
      expect(button.hitTestable(), findsOneWidget);
      expect(find.byType(MeshTabBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expands and collapses the map without losing the selected point',
    (tester) async {
      String? result;
      await _openPicker(tester, (value) => result = value);

      final map = find.byType(MeshMap);
      final compact = tester.getSize(map).height;
      final action = find.text('Send location');
      expect(action, findsOneWidget);
      expect(find.byType(MeshTabBar), findsOneWidget);

      final grip = find.byKey(const ValueKey('attachment-grip'));
      await tester.drag(grip, const Offset(0, -110));
      await tester.pumpAndSettle();
      expect(tester.getSize(map).height, greaterThan(compact));
      expect(find.byType(MeshTabBar), findsNothing);
      await tester.tap(find.byTooltip('Collapse'));
      await tester.pumpAndSettle();
      expect(tester.getSize(map).height, closeTo(compact, .01));
      expect(find.byType(MeshTabBar), findsOneWidget);

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(result, 'geo:55.725000,52.401000');
      expect(map, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'anchors the contact search above the keyboard and restores the list',
    (tester) async {
      await _openPicker(tester, (_) {});
      await tester.tap(find.text('Contact'));
      await tester.pumpAndSettle();

      await _startContactSearch(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 440);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(_contactEditor, 'сокол');
      await tester.pumpAndSettle();
      expect(find.byType(MeshTabBar), findsNothing);
      expect(find.text('Илья Ветров'), findsNothing);
      expect(
        tester.getBottomLeft(_contactEditor).dy,
        closeTo(844 - 440 - 8, 1),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Close search'));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.text('Илья Ветров'), findsOneWidget);
      expect(find.text('Мира Соколова'), findsOneWidget);
      expect(find.byType(MeshTabBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('aligns both attachment tabs with the iPhone home tabs', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = tester.view.padding;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: BleTransport(),
      adapters: const [MeshtasticAdapter()],
      preview: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: MeshHome(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    final homeBar = find.byType(MeshNavigation);
    double homeTabCenter(String label) => tester
        .getCenter(find.descendant(of: homeBar, matching: find.text(label)))
        .dy;
    final homeChatTab = homeTabCenter('Chats');
    final homeSettingsTab = homeTabCenter('Settings');
    await tester.tap(find.text('Тропа'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Attachments'));
    await tester.pumpAndSettle();

    final bar = find.byType(MeshTabBar);
    final atRest = tester.getRect(bar);
    final contactTab = find.descendant(of: bar, matching: find.text('Contact'));
    void expectAligned() {
      expect(tester.getCenter(_locationTab).dy, closeTo(homeChatTab, .5));
      expect(tester.getCenter(contactTab).dy, closeTo(homeSettingsTab, .5));
    }

    expectAligned();
    await tester.tap(contactTab);
    await tester.pumpAndSettle();
    expect(tester.getRect(bar), atRest);
    expectAligned();
    await tester.tap(_locationTab);
    await tester.pumpAndSettle();
    expect(tester.getRect(bar), atRest);
    expectAligned();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('tracks the finger and springs to the nearest detent', (
    tester,
  ) async {
    await _openPicker(tester, (_) {});
    final grip = find.byKey(const ValueKey('attachment-grip'));
    final top = tester.getTopLeft(grip).dy;
    final bar = tester.getRect(find.byType(MeshTabBar));
    final drag = await tester.startGesture(tester.getCenter(grip));
    await drag.moveBy(
      const Offset(0, -55),
      timeStamp: const Duration(milliseconds: 180),
    );
    await tester.pump();
    expect(tester.getTopLeft(grip).dy, closeTo(top - 55, .1));
    expect(tester.getRect(find.byType(MeshTabBar)), bar);
    await drag.up(timeStamp: const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(grip).dy, closeTo(top, .1));

    await tester.fling(grip, const Offset(0, -85), 650);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Collapse'), findsOneWidget);
    await tester.fling(grip, const Offset(0, 65), 600);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(grip).dy, closeTo(top, .1));
    expect(tester.getRect(find.byType(MeshTabBar)), bar);

    await tester.dragFrom(
      tester.getCenter(find.byType(MeshMap)),
      const Offset(0, 85),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(grip).dy, closeTo(top, .1));

    await tester.fling(grip, const Offset(0, 55), 650);
    await tester.pumpAndSettle();
    expect(grip, findsNothing);
  });

  testWidgets('fades one attachment pane at a time under fixed tabs', (
    tester,
  ) async {
    await _openPicker(tester, (_) {}, platform: TargetPlatform.iOS);
    final map = find.byType(MeshMap);
    final tabs = find.byType(MeshTabBar);
    final tabRect = tester.getRect(tabs);
    final fade = find.byKey(const ValueKey('attachment-tab-pane'));
    final camera = tester.widget<MeshMap>(map).controller!;
    final point = camera.camera.center;
    expect(camera.move(point, 11), isTrue);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Contact'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<MeshTabBar>(tabs).index, 1);
    expect(tester.widget<FadeTransition>(fade).opacity.value, closeTo(.5, .02));
    expect(tester.getRect(tabs), tabRect);
    expect(map, findsOneWidget);
    expect(find.text('Мира Соколова'), findsNothing);

    await tester.pump(const Duration(milliseconds: 51));
    await tester.pump();
    expect(map, findsNothing);
    expect(find.text('Мира Соколова'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<FadeTransition>(fade).opacity.value, closeTo(.5, .02));
    expect(tester.getRect(tabs), tabRect);

    await tester.tap(_locationTab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('Contact'));
    await tester.pumpAndSettle();
    expect(map, findsNothing);
    expect(tester.widget<MeshTabBar>(tabs).index, 1);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);

    await tester.tap(_locationTab);
    await tester.pumpAndSettle();
    expect(tester.getRect(tabs), tabRect);
    expect(camera.camera.center, point);
    expect(camera.camera.zoom, 11);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches the attachment pane instantly with reduced motion', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _openPicker(tester, (_) {});
    await tester.tap(find.text('Contact'));
    await tester.pump();
    expect(find.byType(MeshMap), findsNothing);
    expect(find.text('Мира Соколова'), findsOneWidget);
  });

  testWidgets(
    'passes a downward drag at the top of iOS contacts to the sheet',
    (tester) async {
      await _openPicker(tester, (_) {}, platform: TargetPlatform.iOS);
      await tester.tap(find.text('Contact'));
      await tester.pumpAndSettle();
      final grip = find.byKey(const ValueKey('attachment-grip'));
      await tester.fling(grip, const Offset(0, -115), 650);
      await tester.pumpAndSettle();
      expect(find.byType(MeshTabBar), findsNothing);
      final expandedTop = tester.getTopLeft(grip).dy;
      await _startContactSearch(tester);
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(grip).dy, closeTo(expandedTop, .1));
      expect(find.byType(MeshTabBar), findsNothing);
      final list = find.byType(CustomScrollView);
      final scroll = tester.widget<CustomScrollView>(list).controller!;
      expect(scroll.offset, 0);
      await tester.fling(list, const Offset(0, 105), 700);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(grip).dy, greaterThan(expandedTop));
      expect(find.byType(MeshTabBar), findsOneWidget);
      expect(scroll.offset, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'iOS contact sheet uses the hidden grip and takes over at the list edge',
    (tester) async {
      await _openPicker(
        tester,
        (_) {},
        platform: TargetPlatform.iOS,
        contacts: [
          for (var index = 0; index < 30; index++)
            (
              peer: (
                id: 'node:$index',
                name: 'Contact $index',
                channel: false,
                writable: true,
              ),
              link: 'meshgram://contact/$index',
            ),
        ],
      );
      await tester.tap(find.text('Contact'));
      await tester.pumpAndSettle();
      final grip = find.byKey(const ValueKey('attachment-grip'));
      final compact = tester.getRect(grip);
      expect(compact.height, 48);
      await tester.flingFrom(
        compact.topCenter + const Offset(0, 36),
        const Offset(0, -104),
        600,
      );
      await tester.pumpAndSettle();
      final expandedTop = tester.getTopLeft(grip).dy;
      expect(expandedTop, lessThan(compact.top));

      final list = find.byType(CustomScrollView);
      final scroll = tester.widget<CustomScrollView>(list).controller!;
      scroll.jumpTo(90);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(list));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(tester.getTopLeft(grip).dy, closeTo(expandedTop, .1));
      final remaining = scroll.offset;
      expect(remaining, greaterThan(0));
      await gesture.moveBy(Offset(0, remaining + 40));
      await tester.pump();
      expect(scroll.offset, 0);
      expect(tester.getTopLeft(grip).dy, closeTo(expandedTop + 40, .1));
      await gesture.moveBy(const Offset(0, 80));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(grip).dy, closeTo(compact.top, .1));
    },
  );

  testWidgets('searches known nodes or coordinates without sending them', (
    tester,
  ) async {
    String? result;
    await _openPicker(tester, (value) => result = value);
    final search = find.byTooltip('Search locations');

    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '56.25, 51.50');
    await tester.pumpAndSettle();
    expect(find.text('Coordinates'), findsOneWidget);
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(find.text('55.725000, 52.401000'), findsOneWidget);

    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'маяк');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Северный маяк'));
    await tester.pumpAndSettle();
    expect(find.text('56.300000, 51.750000'), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.text('Contact'));
    await tester.pumpAndSettle();
    await tester.tap(_locationTab);
    await tester.pumpAndSettle();
    expect(find.text('56.300000, 51.750000'), findsOneWidget);
    await tester.tap(find.text('Send location'));
    await tester.pumpAndSettle();
    expect(result, 'geo:56.300000,51.750000');
    expect(tester.takeException(), isNull);
  });
}

Finder _nativeControl(String kind, {String? symbol}) => find.byWidgetPredicate(
  (widget) =>
      widget is IosControl &&
      widget.kind == kind &&
      (symbol == null || widget.properties['symbol'] == symbol),
);

bool _sourceHidden(WidgetTester tester, Finder button) => !tester
    .widget<Visibility>(
      find.ancestor(
        of: button,
        matching: find.byWidgetPredicate(
          (widget) => widget is Visibility && widget.maintainSize,
        ),
      ),
    )
    .visible;

Finder get _attachmentSource => useIosControls
    ? _nativeControl('button', symbol: 'paperclip')
    : find.byTooltip('Attachments');

Future<void> _tapAttachmentControl(WidgetTester tester, Finder control) async {
  if (tester.widget(control) case IosControl native) {
    native.onSelect!(0);
  } else {
    await tester.tap(control);
  }
}

Finder get _paperclipFlight =>
    find.byKey(const ValueKey('attachment-paperclip-flight'));

Finder get _paperclipGlyph =>
    find.byKey(const ValueKey('attachment-paperclip-glyph'));

Future<MeshController> _openIosChat(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = tester.view.padding;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final controller = MeshController(
    store: MeshStore(await SharedPreferences.getInstance()),
    transport: BleTransport(),
    adapters: const [MeshtasticAdapter()],
    preview: true,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: MeshHome(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Тропа'));
  await tester.pumpAndSettle();
  return controller;
}

Finder get _locationTab => find.descendant(
  of: find.byType(MeshTabBar),
  matching: find.text('Location'),
);

Finder get _contactEditor => find.descendant(
  of: find.byType(MeshSearchEditor),
  matching: find.byType(TextField),
);

Future<void> _startContactSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Search nodes'));
  await tester.pumpAndSettle();
}

Future<void> _openPicker(
  WidgetTester tester,
  ValueChanged<String?> onResult, {
  List<ShareableNode> contacts = _contacts,
  TargetPlatform? platform,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async => onResult(
              await pickChatAttachment(
                context,
                contacts: contacts,
                initialPosition: (latitude: 55.725, longitude: 52.401),
                locationNodes: const [
                  (
                    name: 'Северный маяк',
                    position: (latitude: 56.3, longitude: 51.75),
                  ),
                ],
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
