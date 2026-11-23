// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/ios_control.dart';
import 'package:meshgrame/ui/search_field.dart';
import 'package:meshgrame/ui/style.dart';

void main() {
  testWidgets('iOS retains the native button and search when a sheet opens', (
    tester,
  ) async {
    final search = TextEditingController();
    final focus = FocusNode();
    final searchKey = GlobalKey<IosControlState>();
    addTearDown(search.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                GlassButton(
                  icon: Icons.sort_rounded,
                  label: 'Sort',
                  onTap: () {},
                ),
                SizedBox.square(
                  dimension: 48,
                  child: MeshSearchEditor(
                    placeholder: 'Search',
                    controller: search,
                    focusNode: focus,
                    iosKey: searchKey,
                    active: false,
                    onActivate: () {},
                    onChanged: (_) {},
                    onDismissKeyboard: () {},
                  ),
                ),
                TextButton(
                  onPressed: () => showMeshSheet<void>(
                    context: context,
                    builder: (context) => TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close sheet'),
                    ),
                  ),
                  child: const Text('Open sheet'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Finder native(String kind) => find.byWidgetPredicate(
      (widget) => widget is IosControl && widget.kind == kind,
    );
    final button = native('button');
    final editor = native('chatSearch');
    final buttonState = tester.state<IosControlState>(button);
    final searchState = tester.state<IosControlState>(editor);
    expect(
      tester.widget<IosControl>(button).properties['symbol'],
      'line.3.horizontal.decrease',
    );
    expect(tester.getSize(button), const Size.square(48));
    final platformButton = find.descendant(
      of: button,
      matching: find.byType(UiKitView),
    );
    expect(tester.getRect(platformButton), tester.getRect(button).inflate(8));

    void expectControls(bool covered) {
      expect(tester.state<IosControlState>(button), same(buttonState));
      expect(tester.state<IosControlState>(editor), same(searchState));
      expect(
        tester.widget<IosControl>(button).properties['coveredByModal'],
        covered,
      );
      expect(
        tester.widget<IosControl>(editor).properties['coveredByModal'],
        covered,
      );
      expect(tester.widget<IosControl>(button).capsule, isFalse);
      expect(tester.widget<IosControl>(editor).capsule, isTrue);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(RawImage), findsNothing);
    }

    expectControls(false);
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    expectControls(true);
    await tester.tap(find.text('Close sheet'));
    await tester.pumpAndSettle();
    expectControls(false);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
