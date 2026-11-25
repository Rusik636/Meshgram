// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'ios_control.dart';
import 'macos_glass.dart';
import 'navigation.dart';
import 'style.dart';

const meshSearchButtonSize = 48.0;

/// Lets momentum finish normally, then settles a partially collapsed header.
class MeshSearchScrollController extends ScrollController {
  double collapseRange = 0;
  double trailingSnapExtent = 0;
  bool reduceMotion = false;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _MeshSearchScrollPosition(
    physics: _MeshSearchSnapPhysics(this, parent: physics),
    context: context,
    oldPosition: oldPosition,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    debugLabel: debugLabel,
  );
}

class _MeshSearchScrollPosition extends ScrollPositionWithSingleContext {
  _MeshSearchScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    super.initialPixels,
    super.keepScrollOffset,
    super.debugLabel,
  });

  bool get endingGesture =>
      activity is DragScrollActivity || activity is BallisticScrollActivity;
}

class _MeshSearchSnapPhysics extends ScrollPhysics {
  const _MeshSearchSnapPhysics(this.controller, {super.parent});

  final MeshSearchScrollController controller;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final momentum = super.createBallisticSimulation(position, velocity);
    if (momentum != null) return momentum;
    if (position is! _MeshSearchScrollPosition || !position.endingGesture) {
      return null;
    }

    final current = position.pixels;
    final searchEnd = position.minScrollExtent + controller.collapseRange;
    final afterSearch = current > searchEnd;
    final start = afterSearch ? searchEnd : position.minScrollExtent;
    final end = afterSearch
        ? searchEnd + controller.trailingSnapExtent
        : searchEnd;
    if (end > position.maxScrollExtent || current <= start || current >= end) {
      return null;
    }

    final target = current < (start + end) / 2 ? start : end;
    if (controller.reduceMotion) return _MeshSearchInstantSnap(target);
    return ScrollSpringSimulation(
      spring,
      current,
      target,
      0,
      tolerance: toleranceFor(position),
    );
  }
}

class _MeshSearchInstantSnap extends Simulation {
  _MeshSearchInstantSnap(this.target);

  final double target;

  @override
  double x(double time) => target;

  @override
  double dx(double time) => 0;

  @override
  bool isDone(double time) => true;
}

double meshSearchFieldHeight(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(17) * 1.2 + 16).clamp(
      meshSearchButtonSize,
      double.infinity,
    );

double meshSearchProgress(Animation<double> animation) =>
    Curves.easeInOutCubic.transform(animation.value);

void animateMeshSearch(
  BuildContext context,
  AnimationController animation, {
  required bool open,
}) {
  final duration = meshMotion(context);
  if (duration == Duration.zero) {
    animation.value = open ? 1 : 0;
    return;
  }
  animation.duration = duration;
  if (open) {
    animation.forward();
  } else {
    animation.reverse();
  }
}

Rect meshSearchFieldRect({
  required double width,
  required double normalTop,
  required double compactTop,
  required double activeTop,
  required double fieldHeight,
  required double compactRight,
  required double progress,
  required double collapse,
}) {
  const side = 16.0;
  const activeRight = 72.0;
  final compactLeft = width - compactRight - meshSearchButtonSize;
  final left = lerpDouble(
    lerpDouble(side, compactLeft, collapse),
    side,
    progress,
  )!;
  final right = lerpDouble(
    lerpDouble(side, compactRight, collapse),
    activeRight,
    progress,
  )!;
  final top = lerpDouble(
    lerpDouble(normalTop, compactTop, collapse),
    activeTop,
    progress,
  )!;
  final height = lerpDouble(
    lerpDouble(fieldHeight, meshSearchButtonSize, collapse),
    fieldHeight,
    progress,
  )!;
  return Rect.fromLTWH(left, top, width - left - right, height);
}

class MeshSearchLauncher extends StatelessWidget {
  const MeshSearchLauncher({
    super.key,
    required this.placeholder,
    required this.onTap,
    required this.collapse,
  });

  final String placeholder;
  final double collapse;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final glass = MacGlass.enabled(context);
    final field = TextField(
      readOnly: true,
      canRequestFocus: false,
      onTap: onTap,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: TextStyle(
          color: style.secondary.withValues(alpha: 1 - collapse),
        ),
        hintMaxLines: 1,
        prefixIcon: Icon(
          Icons.search_rounded,
          color: style.secondary,
          size: 22,
        ),
        filled: !glass,
        fillColor: glass
            ? null
            : Color.lerp(style.searchField, style.pill, collapse),
        isDense: true,
        contentPadding: EdgeInsets.zero,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide.none,
        ),
      ),
    );
    return glass ? GlassSurface(radius: 100, child: field) : field;
  }
}

class MeshSearchEditor extends StatelessWidget {
  const MeshSearchEditor({
    super.key,
    required this.placeholder,
    required this.controller,
    required this.focusNode,
    required this.iosKey,
    required this.onChanged,
    required this.onDismissKeyboard,
    this.autofocus = true,
    this.initialText = '',
    this.onActivate,
    this.active = true,
    this.progress = 1,
  });

  final String placeholder, initialText;
  final TextEditingController controller;
  final FocusNode focusNode;
  final GlobalKey<IosControlState> iosKey;
  final ValueChanged<String> onChanged;
  final VoidCallback onDismissKeyboard;
  final bool autofocus;
  final VoidCallback? onActivate;
  final bool active;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    if (useIosControls) {
      if (onActivate != null && !active && progress == 0) {
        return GlassButton(
          icon: Icons.search_rounded,
          label: placeholder,
          onTap: onActivate,
        );
      }
      final covered = ModalRoute.isCurrentOf(context) == false;
      return SizedBox(
        height: meshSearchFieldHeight(context),
        child: IosControl(
          key: iosKey,
          kind: 'chatSearch',
          onTextChanged: onChanged,
          properties: {
            'placeholder': placeholder,
            'initialText': initialText,
            'autofocus': autofocus && !covered,
            'coveredByModal': covered,
            'titleSize': MediaQuery.textScalerOf(context).scale(17),
            'dark': style.dark,
            'foreground': style.text.toARGB32(),
            'secondary': style.secondary.toARGB32(),
            'accent': style.accent.toARGB32(),
            'surface': style.surface.toARGB32(),
            'highContrast': MediaQuery.highContrastOf(context),
            if (onActivate != null) ...{
              'expandsFromCorner': true,
              'active': active,
            },
          },
        ),
      );
    }
    Widget editor() => TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: (_) => onDismissKeyboard(),
      textInputAction: TextInputAction.search,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.zero,
        prefixIcon: const Icon(Icons.search_rounded),
        prefixIconConstraints: const BoxConstraints.tightFor(
          width: meshSearchButtonSize,
          height: meshSearchButtonSize,
        ),
        suffixIconConstraints: const BoxConstraints.tightFor(
          width: meshSearchButtonSize,
          height: meshSearchButtonSize,
        ),
        hint: Center(heightFactor: 1, child: Text(placeholder)),
        border: InputBorder.none,
        suffixIcon: controller.text.trim().isEmpty
            ? const SizedBox.shrink()
            : MeshIconButton(
                label: tr(context, 'Очистить запрос', 'Clear query'),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.cancel_outlined, size: 19),
              ),
      ),
    );
    if (onActivate == null) {
      return GlassSurface(
        radius: 100,
        color: MacGlass.enabled(context) ? null : style.searchField,
        child: editor(),
      );
    }
    return GlassSurface(
      radius: 100,
      color: MacGlass.enabled(context)
          ? null
          : Color.lerp(style.pill, style.searchField, progress),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 120) {
            return IgnorePointer(ignoring: !active, child: editor());
          }
          return Semantics(
            label: placeholder,
            child: IconButton(
              onPressed: active ? null : onActivate,
              icon: Icon(Icons.search_rounded, color: style.text, size: 20),
            ),
          );
        },
      ),
    );
  }
}
