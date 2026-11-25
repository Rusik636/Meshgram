// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/desktop_interaction.dart';
import 'package:meshgrame/ui/style.dart';

void main() {
  for (final reduceMotion in [false, true]) {
    testWidgets('Desktop spring respects reduced motion $reduceMotion', (
      tester,
    ) async {
      var clicks = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Scaffold(
              body: Center(
                child: GlassButton(
                  label: 'Action',
                  icon: Icons.attach_file_rounded,
                  onTap: () => clicks++,
                ),
              ),
            ),
          ),
        ),
      );
      final button = find.byType(GlassButton);
      final transform = find.descendant(
        of: find.byType(DesktopSpring),
        matching: find.byType(Transform),
      );
      double scale() =>
          tester.widget<Transform>(transform).transform.storage[0];
      final center = tester.getCenter(button);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: center + const Offset(100, 0));
      await mouse.moveTo(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      final peak = scale();
      await tester.pumpAndSettle();
      final hovered = scale();
      expect(hovered, closeTo(reduceMotion ? 1 : 1.04, .001));
      expect(peak, reduceMotion ? hovered : greaterThan(hovered));
      expect(tester.getCenter(button), center);

      await mouse.down(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 55));
      expect(scale(), reduceMotion ? hovered : greaterThan(hovered + .02));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(clicks, 1);
      expect(scale(), closeTo(hovered, .001));

      await mouse.moveTo(center + const Offset(100, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(scale(), reduceMotion ? 1 : lessThan(1));
      await tester.pumpAndSettle();
      expect(scale(), closeTo(1, .001));
      final style = tester.widget<IconButton>(find.byType(IconButton)).style!;
      expect(
        style.overlayColor!.resolve({WidgetState.hovered, WidgetState.focused}),
        Colors.transparent,
      );
      expect(
        style.overlayColor!.resolve({WidgetState.focused}),
        isNot(Colors.transparent),
      );
      await mouse.removePointer();
    });
  }
}
