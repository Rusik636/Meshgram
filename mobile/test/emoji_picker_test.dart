// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/emoji_picker.dart';

void main() {
  testWidgets('search groups skin tones and a hold opens the variants', (
    tester,
  ) async {
    await tester.runAsync(() => EmojiCatalog.load(rootBundle));
    final selections = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: EmojiPicker(
                gridHeight: 180,
                onSelect: selections.add,
                onCollapse: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final search = find.byType(TextField);
    await tester.enterText(search, 'thumbs up');
    await tester.pumpAndSettle();
    expect(find.text('👍'), findsOneWidget);
    expect(find.text('👍🏾'), findsNothing);

    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();
    expect(selections, ['👍']);

    await tester.longPress(find.text('👍'));
    await tester.pumpAndSettle();
    expect(find.text('👍🏾'), findsOneWidget);
    expect(selections, ['👍']);
    await tester.tap(find.text('👍🏾'));
    await tester.pumpAndSettle();
    expect(selections, ['👍', '👍🏾']);
    expect(find.text('👍🏾'), findsNothing);

    await tester.enterText(search, 'handshake: light skin tone');
    await tester.pumpAndSettle();
    expect(find.text('🤝'), findsOneWidget);
    expect(find.text('🫱🏻‍🫲🏼'), findsNothing);
    await tester.longPress(find.text('🤝'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🫱🏻‍🫲🏼'));
    await tester.pumpAndSettle();
    expect(selections.last, '🫱🏻‍🫲🏼');
    expect(tester.takeException(), isNull);
  });
}
