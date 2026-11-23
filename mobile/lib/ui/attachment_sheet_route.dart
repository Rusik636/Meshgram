// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:ui' show SemanticsHitTestBehavior;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ios_control.dart';

Future<T?> showMeshAttachmentSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool morphFromSource = false,
}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: reduceMotion ? AnimationStyle.noAnimation : null,
      builder: builder,
    );
  }

  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push(
    _IosAttachmentSheetRoute<T>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      sheetAnimationStyle: reduceMotion
          ? AnimationStyle.noAnimation
          : morphFromSource
          ? const AnimationStyle(
              duration: Duration(milliseconds: 400),
              reverseDuration: Duration(milliseconds: 350),
            )
          : null,
      morphFromSource: morphFromSource,
    ),
  );
}

class _IosAttachmentSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _IosAttachmentSheetRoute({
    required super.builder,
    required super.capturedThemes,
    required super.barrierLabel,
    required super.barrierOnTapHint,
    required this.morphFromSource,
    super.sheetAnimationStyle,
  }) : super(
         isScrollControlled: true,
         useSafeArea: true,
         enableDrag: false,
         backgroundColor: Colors.transparent,
         modalBarrierColor: Colors.transparent,
       );

  final bool morphFromSource;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    if (!morphFromSource) {
      return super.buildPage(context, animation, secondaryAnimation);
    }
    final sheet = SafeArea(
      bottom: false,
      child: DisplayFeatureSubScreen(
        anchorPoint: anchorPoint,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Semantics(
            hitTestBehavior: SemanticsHitTestBehavior.opaque,
            child: Material(
              type: MaterialType.transparency,
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    );
    return capturedThemes?.wrap(sheet) ?? sheet;
  }

  @override
  Widget buildModalBarrier() => Stack(
    fit: StackFit.expand,
    children: [
      if (!offstage)
        IgnorePointer(
          child: ExcludeSemantics(
            child: FadeTransition(
              opacity: animation!.drive(CurveTween(curve: barrierCurve)),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final regular =
                      constraints.biggest.shortestSide >= 600 &&
                      !MediaQuery.highContrastOf(context);
                  final opacity = regular ? .025 : .25;
                  // Draw the scrim in the same compositor as the controls
                  // underneath the sheet. Flutter still owns dismissal.
                  return useIosControls
                      ? IosControl(
                          key: ValueKey(opacity),
                          kind: 'sheetDim',
                          properties: {'opacity': opacity},
                        )
                      : ColoredBox(
                          color: Colors.black.withValues(alpha: opacity),
                        );
                },
              ),
            ),
          ),
        ),
      super.buildModalBarrier(),
    ],
  );
}
