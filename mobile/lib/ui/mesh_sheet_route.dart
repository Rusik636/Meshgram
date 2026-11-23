// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:ui' show SemanticsHitTestBehavior;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ios_control.dart';

/// Shows a standard Material bottom sheet with its scrim drawn in UIKit on iOS.
Future<T?> showMeshBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool enableDrag = true,
  bool? showDragHandle,
  Color? backgroundColor,
  AnimationStyle? sheetAnimationStyle,
  bool morphFromSource = false,
  bool useAttachmentDim = false,
}) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      backgroundColor: backgroundColor,
      sheetAnimationStyle: sheetAnimationStyle,
    );
  }

  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push(
    _IosMeshBottomSheetRoute<T>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      dimColor: useAttachmentDim
          ? null
          : Theme.of(context).bottomSheetTheme.modalBarrierColor ??
                Colors.black54,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      backgroundColor: backgroundColor,
      sheetAnimationStyle:
          sheetAnimationStyle ??
          (morphFromSource
              ? const AnimationStyle(
                  duration: Duration(milliseconds: 400),
                  reverseDuration: Duration(milliseconds: 350),
                )
              : null),
      morphFromSource: morphFromSource,
    ),
  );
}

class _IosMeshBottomSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _IosMeshBottomSheetRoute({
    required super.builder,
    required super.capturedThemes,
    required super.barrierLabel,
    required super.barrierOnTapHint,
    required this.morphFromSource,
    required this.dimColor,
    required super.isScrollControlled,
    super.useSafeArea,
    super.enableDrag,
    super.showDragHandle,
    super.backgroundColor,
    super.sheetAnimationStyle,
  }) : super(modalBarrierColor: Colors.transparent);

  final bool morphFromSource;
  final Color? dimColor;

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
                  final color =
                      dimColor ??
                      Colors.black.withValues(alpha: regular ? .025 : .25);
                  if (color.a == 0) return const SizedBox.expand();
                  // Draw the scrim in the same compositor as the controls
                  // underneath the sheet. Flutter still owns dismissal.
                  return useIosControls
                      ? IosControl(
                          key: ValueKey(color),
                          kind: 'sheetDim',
                          properties: {
                            'color': color.toARGB32(),
                            'opacity': color.a,
                          },
                        )
                      : ColoredBox(color: color);
                },
              ),
            ),
          ),
        ),
      super.buildModalBarrier(),
    ],
  );
}
