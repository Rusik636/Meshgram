// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/chat_attachments.dart';
import 'package:meshgrame/ui/contact_picker.dart';
import 'package:meshgrame/ui/navigation.dart';
import 'package:meshgrame/ui/node_list.dart';
import 'package:meshgrame/ui/search_field.dart';

const _size = Size(390, 844);
const _contactCount = 18;

void main() {
  testWidgets(
    'shows contacts under fixed tabs and keeps the last row tappable',
    (tester) async {
      String? selected;
      await _openContacts(tester, (value) => selected = value);

      final scroll = find.byType(CustomScrollView);
      final tabs = find.byType(MeshTabBar);
      final tabRect = tester.getRect(tabs);
      final listRect = tester.getRect(scroll);
      expect(listRect.bottom, _size.height);
      expect(listRect.bottom, greaterThan(tabRect.bottom));
      expect(listRect.top, lessThan(tabRect.top));

      final position = tester
          .widget<CustomScrollView>(scroll)
          .controller!
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getRect(tabs), tabRect);

      final last = find.text('Node ${_contactCount - 1}');
      final lastRow = find.ancestor(
        of: last,
        matching: find.byType(MeshNodeRow),
      );
      expect(lastRow.hitTestable(), findsOneWidget);
      expect(tester.getBottomLeft(lastRow).dy, lessThanOrEqualTo(tabRect.top));
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(selected, 'meshgram://contact/${_contactCount - 1}');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps the collapsed search header free of a solid band', (
    tester,
  ) async {
    await _openContacts(tester, (_) {});

    expect(find.byTooltip('Search nodes'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -175));
    await tester.pumpAndSettle();

    final search = find.byTooltip('Search nodes');
    expect(find.byType(MeshSearchLauncher), findsNothing);
    expect(search.hitTestable(), findsOneWidget);
    expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
    final picker = find.byType(AttachmentContacts);
    final bounds = tester.getRect(picker);
    final surfaces = find.descendant(
      of: picker,
      matching: find.byWidgetPredicate(_hasOpaqueSurface),
    );
    for (final surface in surfaces.evaluate()) {
      final render = surface.renderObject;
      if (render is! RenderBox || !render.hasSize) continue;
      final rect = render.localToGlobal(Offset.zero) & render.size;
      expect(
        rect.width >= bounds.width * .9 &&
            rect.height >= 24 &&
            rect.top < tester.getBottomLeft(search).dy,
        isFalse,
        reason: 'The collapsed header must blend into the contact list.',
      );
    }
    final softEdges = find.byKey(
      const ValueKey('attachment-contact-scroll-edges'),
    );
    expect(softEdges, findsOneWidget);

    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(MeshSearchEditor),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
    expect(softEdges, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

bool _hasOpaqueSurface(Widget widget) {
  if (widget is ColoredBox) return widget.color.a >= .95;
  if (widget is! DecoratedBox || widget.decoration is! BoxDecoration) {
    return false;
  }
  final decoration = widget.decoration as BoxDecoration;
  if ((decoration.color?.a ?? 0) >= .95) return true;
  final colors = decoration.gradient?.colors ?? const [];
  for (var index = 1; index < colors.length; index++) {
    if (colors[index].a >= .95 && colors[index] == colors[index - 1]) {
      return true;
    }
  }
  return false;
}

Future<void> _openContacts(
  WidgetTester tester,
  ValueChanged<String?> onSelected,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _size;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = tester.view.padding;
  addTearDown(tester.view.reset);

  final contacts = <ShareableNode>[
    for (var index = 0; index < _contactCount; index++)
      (
        peer: (
          id: 'node:$index',
          name: 'Node $index',
          channel: false,
          writable: true,
        ),
        link: 'meshgram://contact/$index',
      ),
  ];
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        platform: TargetPlatform.iOS,
        brightness: Brightness.dark,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async => onSelected(
              await pickChatAttachment(context, contacts: contacts),
            ),
            child: const Text('Open picker'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open picker'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Contact'));
  await tester.pumpAndSettle();
}
