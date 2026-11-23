// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/sheet_control_clip.dart';

void main() {
  testWidgets('clips the covered part without replacing a control', (
    tester,
  ) async {
    final firstTop = ValueNotifier(144.0);
    final secondTop = ValueNotifier(50.0);
    addTearDown(firstTop.dispose);
    addTearDown(secondTop.dispose);
    const under = ValueKey('under');
    const inner = ValueKey('inner');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Stack(
              children: [
                const Positioned(
                  top: 60,
                  left: 20,
                  width: 80,
                  height: 60,
                  child: MeshSheetControlClip(key: under, child: _InkProbe()),
                ),
                TextButton(
                  onPressed: () => _openSheet(
                    context,
                    firstTop,
                    (context) => Stack(
                      children: [
                        const Positioned(
                          top: 12,
                          left: 20,
                          width: 80,
                          height: 60,
                          child: MeshSheetControlClip(
                            key: inner,
                            child: _InkProbe(),
                          ),
                        ),
                        Positioned(
                          left: 140,
                          child: TextButton(
                            onPressed: () => _openSheet(
                              context,
                              secondTop,
                              (context) => TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close nested sheet'),
                              ),
                            ),
                            child: const Text('Open nested sheet'),
                          ),
                        ),
                      ],
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

    RenderBox box(Key key) => tester.renderObject(find.byKey(key));
    bool hits(RenderBox control, double y) =>
        control.hitTest(BoxHitTestResult(), position: Offset(12, y));
    final oldControl = box(under);
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    final innerControl = box(inner);
    expect(hits(oldControl, 54), isTrue);
    expect(hits(innerControl, 54), isTrue);

    firstTop.value = 90;
    await tester.pump();
    expect(hits(oldControl, 25), isTrue);
    expect(hits(oldControl, 35), isFalse);
    expect(
      tester.layers.whereType<ClipRectLayer>().map(
        (layer) => layer.clipRect?.size,
      ),
      contains(const Size(80, 30)),
    );
    expect(hits(innerControl, 54), isTrue);

    firstTop.value = 60;
    await tester.pump();
    expect(hits(oldControl, 0), isFalse);
    expect(identical(box(under), oldControl), isTrue);

    firstTop.value = 144;
    await tester.pump();
    await tester.tap(find.text('Open nested sheet'));
    await tester.pumpAndSettle();
    expect(hits(oldControl, 0), isFalse);
    expect(hits(innerControl, 0), isFalse);
    await tester.tap(find.text('Close nested sheet'));
    await tester.pumpAndSettle();
    expect(hits(oldControl, 54), isTrue);
    expect(hits(innerControl, 54), isTrue);
    expect(identical(box(inner), innerControl), isTrue);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openSheet(
  BuildContext context,
  ValueNotifier<double> top,
  WidgetBuilder content,
) {
  final presentingRoute = ModalRoute.of(context);
  return showGeneralDialog<void>(
    context: context,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.topLeft,
      child: ValueListenableBuilder<double>(
        valueListenable: top,
        child: MeshOpaqueSheetRegion(
          presentingRoute: presentingRoute,
          motion: top,
          child: Material(
            child: SizedBox(width: 400, height: 300, child: content(context)),
          ),
        ),
        builder: (context, y, child) =>
            Transform.translate(offset: Offset(0, y), child: child),
      ),
    ),
  );
}

class _InkProbe extends LeafRenderObjectWidget {
  const _InkProbe();

  @override
  RenderBox createRenderObject(BuildContext context) => _InkProbeRender();
}

class _InkProbeRender extends RenderBox {
  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void performLayout() => size = constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.drawRect(offset & size, Paint()..color = Colors.red);
  }
}
