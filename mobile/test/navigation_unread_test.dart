// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/controller.dart';
import 'package:meshgrame/mesh/network.dart';
import 'package:meshgrame/mesh/store.dart';
import 'package:meshgrame/radio/meshcore.dart';
import 'package:meshgrame/radio/meshtastic.dart';
import 'package:meshgrame/ui/ios_control.dart';
import 'package:meshgrame/ui/navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings badge has its own unread number and +99 cap', (
    tester,
  ) async {
    Future<void> display(int otherUnread) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: MeshNavigation(
            index: 0,
            unread: 8,
            settingsUnread: otherUnread,
            onSelect: (_) {},
          ),
        ),
      ),
    );

    await display(0);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('0'), findsNothing);

    await display(99);
    expect(find.text('99'), findsOneWidget);
    expect(find.text('+99'), findsNothing);

    await display(100);
    expect(find.text('+99'), findsOneWidget);
    final badge = find.ancestor(
      of: find.byIcon(Icons.settings_outlined),
      matching: find.byType(Badge),
    );
    expect(
      find.descendant(of: badge, matching: find.text('+99')),
      findsOneWidget,
    );
    expect(find.text('8'), findsOneWidget);
  });

  testWidgets('home and attachments share the native iOS tab bar', (
    tester,
  ) async {
    const attachmentTabs = ValueKey('attachment tabs');
    final selected = <int>[];
    final attachmentSelections = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeshTabBar(
            key: attachmentTabs,
            labels: const ['Location', 'Contact'],
            icons: const [Icons.place_outlined, Icons.person_outline_rounded],
            symbols: const ['location.fill', 'person.crop.circle'],
            index: 0,
            onSelect: attachmentSelections.add,
          ),
          bottomNavigationBar: MeshNavigation(
            index: 0,
            unread: 8,
            settingsUnread: 100,
            onSelect: selected.add,
          ),
        ),
      ),
    );
    final nativeTabs = find.byWidgetPredicate(
      (widget) => widget is IosControl && widget.kind == 'tabs',
    );
    final home = find.descendant(
      of: find.byType(MeshNavigation),
      matching: nativeTabs,
    );
    final attachments = find.descendant(
      of: find.byKey(attachmentTabs),
      matching: nativeTabs,
    );
    final tabs = tester.widget<IosControl>(home);
    expect(tabs.properties['labels'], ['Chats', 'Settings']);
    expect(tabs.properties['unreadCounts'], [8, 100]);
    tabs.onSelect?.call(1);
    expect(selected, [1]);
    final picker = tester.widget<IosControl>(attachments);
    expect(picker.properties['labels'], ['Location', 'Contact']);
    expect(picker.properties['symbols'], [
      'location.fill',
      'person.crop.circle',
    ]);
    expect(tester.getSize(attachments), tester.getSize(home));
    picker.onSelect?.call(1);
    expect(attachmentSelections, [1]);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  test(
    'other-radio total follows the selected profile and includes saved radios',
    () async {
      SharedPreferences.setMockInitialValues({});
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _NoRadioTransport(),
        adapters: const [MeshtasticAdapter(), MeshCoreAdapter()],
        preview: true,
      );
      addTearDown(controller.dispose);
      final first = controller.radios.first;
      final second = controller.radios.last;
      const third = (
        network: 'meshtastic',
        device: 'demo-extra',
        name: 'Relay',
      );
      controller.radios = [...controller.radios, third];
      controller.notificationCache(second).unread['ch:0'] = 20;
      controller.notificationCache(third).unread['ch:0'] = 12;
      expect(controller.active, first);
      expect(controller.unreadOnOtherRadios, 35);

      await controller.connect(second);
      expect(controller.active, second);
      expect(controller.unreadOnOtherRadios, 18);
    },
  );
}

class _NoRadioTransport implements RadioTransport {
  @override
  Future<RadioLink> connect(Radio radio, String service) =>
      throw StateError('Unexpected real connection');

  @override
  Future<void> scan(
    Map<String, String> services,
    void Function(List<DiscoveredRadio>) update,
  ) async {}

  @override
  Future<void> stopScan() async {}
}
