// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/attachment_sheet_route.dart';
import 'package:meshgrame/ui/ios_control.dart';
import 'package:meshgrame/ui/mesh_sheet_route.dart';
import 'package:meshgrame/ui/style.dart';

void main() {
  for (final (size, highContrast, opacity) in [
    (const Size(390, 844), false, .25),
    (const Size(844, 390), false, .25),
    (const Size(1024, 768), false, .025),
    (const Size(1024, 768), true, .25),
  ]) {
    testWidgets('iOS draws one dismissible attachment scrim at $size, '
        'high contrast: $highContrast', (tester) async {
      final opened = await _open(tester, size, highContrast: highContrast);
      final scrim = find.byWidgetPredicate(
        (widget) => switch (widget) {
          IosControl() =>
            widget.kind == 'sheetDim' &&
                widget.properties['opacity'] == opacity,
          ColoredBox() =>
            widget.color == Colors.black.withValues(alpha: opacity),
          _ => false,
        },
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(scrim, findsOneWidget);
      final fade = find
          .ancestor(of: scrim, matching: find.byType(FadeTransition))
          .first;
      expect(
        tester.widget<FadeTransition>(fade).opacity.value,
        inExclusiveRange(0, 1),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);

      final context = tester.element(find.text('Attachment content'));
      final route = ModalRoute.of(context)!;
      expect(route.barrierColor, Colors.transparent);
      final barrier = find.byWidgetPredicate(
        (widget) => widget is ModalBarrier && widget.dismissible,
      );
      expect(tester.widget<ModalBarrier>(barrier).semanticsLabel, isNotEmpty);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(await opened(), isNull);
      expect(barrier, findsNothing);
      expect(scrim, findsNothing);
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
  }

  testWidgets('iOS lets the attachment position its own morph', (tester) async {
    final opened = await _open(
      tester,
      const Size(390, 844),
      morphFromSource: true,
    );
    final sheet = find.text('Attachment content');
    await tester.pump(const Duration(milliseconds: 100));
    final initialRect = tester.getRect(sheet);
    final route = ModalRoute.of(tester.element(sheet))!;
    expect(route.animation!.value, inExclusiveRange(0, 1));
    expect(route.transitionDuration, const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet), initialRect);
    await tester.tap(sheet);
    await tester.pumpAndSettle();
    expect(await opened(), 'sent');
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('Android keeps the original attachment route barrier', (
    tester,
  ) async {
    final opened = await _open(tester, const Size(390, 844));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Attachment content'));
    final route = ModalRoute.of(context)!;
    expect(route.barrierColor, Colors.black54);
    expect(find.byType(AnimatedModalBarrier), findsOneWidget);
    await tester.tap(find.text('Attachment content'));
    await tester.pumpAndSettle();
    expect(await opened(), 'sent');
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('ordinary and nested sheets preserve colors and gestures', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      tester.view.viewPadding = tester.view.padding;
      addTearDown(tester.view.reset);
      const dimColor = Color(0x660b4d8b);
      final ios = platform == TargetPlatform.iOS;
      final results = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            bottomSheetTheme: const BottomSheetThemeData(
              modalBarrierColor: dimColor,
            ),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => results.add(
                  await showMeshSheet<String>(
                    context: context,
                    builder: (context) => SheetBody(
                      title: 'Options',
                      children: [
                        TextButton(
                          onPressed: () async => results.add(
                            await showMeshBottomSheet<String>(
                              context: context,
                              useSafeArea: true,
                              showDragHandle: true,
                              backgroundColor: Colors.white,
                              builder: (context) => SizedBox(
                                height: 216,
                                child: Center(
                                  child: TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, 'node'),
                                    child: const Text('Select node'),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          child: const Text('Open cluster'),
                        ),
                      ],
                    ),
                  ),
                ),
                child: const Text('Open options'),
              ),
            ),
          ),
        ),
      );
      final scrims = ios
          ? find.byWidgetPredicate(
              (widget) => switch (widget) {
                IosControl() =>
                  widget.kind == 'sheetDim' &&
                      widget.properties['color'] == dimColor.toARGB32() &&
                      widget.properties['opacity'] == dimColor.a,
                ColoredBox() => widget.color == dimColor,
                _ => false,
              },
            )
          : find.byType(AnimatedModalBarrier);
      ModalBottomSheetRoute<String> routeFor(String text) =>
          ModalRoute.of(tester.element(find.text(text)))!
              as ModalBottomSheetRoute<String>;
      final expectedBarrier = ios ? Colors.transparent : dimColor;

      await tester.tap(find.text('Open options'));
      await tester.pumpAndSettle();
      final outer = routeFor('Options');
      expect(outer.barrierColor, expectedBarrier);
      expect(outer.enableDrag, isTrue);
      expect(outer.showDragHandle, isFalse);
      expect(outer.isScrollControlled, isTrue);
      expect(outer.useSafeArea, isFalse);
      expect(scrims, findsOneWidget);

      Future<void> openCluster() async {
        await tester.tap(find.text('Open cluster'));
        await tester.pumpAndSettle();
      }

      await openCluster();
      final inner = routeFor('Select node');
      expect(inner.barrierColor, expectedBarrier);
      expect(inner.enableDrag, isTrue);
      expect(inner.showDragHandle, isTrue);
      expect(inner.isScrollControlled, isFalse);
      expect(inner.useSafeArea, isTrue);
      expect(scrims, findsNWidgets(2));
      await tester.tap(find.text('Select node'));
      await tester.pumpAndSettle();
      expect(results, ['node']);
      expect(scrims, findsOneWidget);

      await openCluster();
      final bottom = find.ancestor(
        of: find.text('Select node'),
        matching: find.byType(BottomSheet),
      );
      final bounds = tester.getRect(bottom);
      await tester.flingFrom(
        Offset(bounds.center.dx, bounds.top + 24),
        const Offset(0, 120),
        1600,
      );
      await tester.pumpAndSettle();
      expect(find.text('Select node'), findsNothing);
      expect(results, ['node', null]);
      expect(scrims, findsOneWidget);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(results, ['node', null, null]);
      expect(scrims, findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({platform}));
  }
}

Future<Future<String?> Function()> _open(
  WidgetTester tester,
  Size size, {
  bool highContrast = false,
  bool morphFromSource = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  late Future<String?> result;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(highContrast: highContrast),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showMeshAttachmentSheet<String>(
                context,
                morphFromSource: morphFromSource,
                builder: (context) => SizedBox(
                  height: 200,
                  child: Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, 'sent'),
                      child: const Text('Attachment content'),
                    ),
                  ),
                ),
              );
            },
            child: const Text('Open attachment'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open attachment'));
  await tester.pump();
  return () => result;
}
