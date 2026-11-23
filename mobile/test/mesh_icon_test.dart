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
    final compactSearchKey = GlobalKey<IosControlState>();
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
                SizedBox(
                  width: 200,
                  child: MeshSearchEditor(
                    placeholder: 'Search',
                    controller: search,
                    focusNode: focus,
                    iosKey: searchKey,
                    onChanged: (_) {},
                    onDismissKeyboard: () {},
                  ),
                ),
                MeshSearchEditor(
                  placeholder: 'Search nodes',
                  controller: search,
                  focusNode: focus,
                  iosKey: compactSearchKey,
                  active: false,
                  progress: 0,
                  onActivate: () {},
                  onChanged: (_) {},
                  onDismissKeyboard: () {},
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
    Finder nativeButton(String label) => find.byWidgetPredicate(
      (widget) =>
          widget is IosControl &&
          widget.kind == 'button' &&
          widget.properties['label'] == label,
    );
    final button = nativeButton('Sort');
    final searchButton = nativeButton('Search nodes');
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
    expect(
      tester.widget<IosControl>(searchButton).properties['symbol'],
      'magnifyingglass',
    );

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
      expect(
        find.descendant(of: editor, matching: find.byType(ClipRRect)),
        findsNothing,
      );
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

  testWidgets('iOS dialog buttons leave a gap between their glass surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMeshDialog<void>(
                context: context,
                builder: (context) => MeshDialog(
                  title: const Text('Short name'),
                  content: const TextField(),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              child: const Text('Open dialog'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();

    final actions = find.byType(GlassActionButton);
    expect(actions, findsNWidgets(2));
    final first = tester.getRect(actions.at(0));
    final second = tester.getRect(actions.at(1));
    expect(second.top - first.bottom, 12);
    expect(second.width, first.width);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
