// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

bool meshDesktop(BuildContext context) =>
    meshDesktopPlatform(Theme.of(context).platform);

bool meshDesktopPlatform(TargetPlatform platform) => switch (platform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

ButtonStyle? meshDesktopButtonStyle(
  BuildContext context, [
  ButtonStyle? style,
]) {
  if (!meshDesktop(context)) return style;
  return desktopButtonFeedback(Theme.of(context).focusColor, style);
}

ButtonStyle desktopButtonFeedback(Color focusColor, [ButtonStyle? style]) =>
    (style ?? const ButtonStyle()).copyWith(
      splashFactory: NoSplash.splashFactory,
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (!states.contains(WidgetState.focused) ||
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed)) {
          return Colors.transparent;
        }
        return style?.overlayColor?.resolve({WidgetState.focused}) ??
            focusColor;
      }),
    );

class DesktopSpring extends StatelessWidget {
  const DesktopSpring({
    super.key,
    required this.child,
    this.enabled = true,
    this.buildScaled,
  });

  final Widget child;
  final bool enabled;
  final Widget Function(BuildContext, double, Widget)? buildScaled;

  @override
  Widget build(BuildContext context) => meshDesktop(context)
      ? _SpringTarget(
          enabled: enabled && !MediaQuery.disableAnimationsOf(context),
          buildScaled: buildScaled,
          child: child,
        )
      : buildScaled?.call(context, 1, child) ?? child;
}

class _SpringTarget extends StatefulWidget {
  const _SpringTarget({
    required this.enabled,
    required this.buildScaled,
    required this.child,
  });

  final bool enabled;
  final Widget Function(BuildContext, double, Widget)? buildScaled;
  final Widget child;

  @override
  State<_SpringTarget> createState() => _SpringTargetState();
}

class _SpringTargetState extends State<_SpringTarget>
    with SingleTickerProviderStateMixin {
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 360,
    ratio: .52,
  );

  late final _scale = AnimationController.unbounded(vsync: this, value: 1);
  bool _hovered = false;

  void _animate({double impulse = 0}) {
    if (!widget.enabled) return;
    _scale.animateWith(
      SpringSimulation(
        _spring,
        _scale.value,
        _hovered ? 1.04 : 1,
        _scale.velocity + impulse,
        snapToEnd: true,
      ),
    );
  }

  void _hover(bool value) {
    if (value == _hovered) return;
    _hovered = value;
    _animate();
  }

  @override
  void didUpdateWidget(_SpringTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled == oldWidget.enabled) return;
    if (widget.enabled) {
      if (_hovered) _animate();
    } else {
      _scale.value = 1;
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (event) => _hover(event.kind == PointerDeviceKind.mouse),
    onExit: (_) => _hover(false),
    child: Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kPrimaryMouseButton) {
          _animate(impulse: 1.8);
        }
      },
      child: AnimatedBuilder(
        animation: _scale,
        child: widget.child,
        builder: (context, child) =>
            widget.buildScaled?.call(context, _scale.value, child!) ??
            Transform.scale(
              scale: _scale.value,
              transformHitTests: false,
              child: child,
            ),
      ),
    ),
  );
}
