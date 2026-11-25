// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'sheet_control_clip.dart';

bool get useIosControls =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.iOS &&
    !const bool.fromEnvironment('FLUTTER_TEST');

const meshIosGlassOutset = 8.0;

/// Keeps UIKit controls out of a scene's opacity transition.
class IosControlVisibility extends InheritedWidget {
  const IosControlVisibility({
    super.key,
    required this.visible,
    required super.child,
  });

  final bool visible;

  static bool visibleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<IosControlVisibility>()
          ?.visible ??
      true;

  @override
  bool updateShouldNotify(IosControlVisibility oldWidget) =>
      visible != oldWidget.visible;
}

class MeshIosGlassFrame extends StatelessWidget {
  const MeshIosGlassFrame({
    super.key,
    required this.child,
    this.verticalOutset = meshIosGlassOutset,
  });

  final Widget child;
  final double verticalOutset;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Give UIKit room to draw interactive glass beyond its resting frame.
      final width = constraints.maxWidth + meshIosGlassOutset * 2;
      final height = constraints.maxHeight + verticalOutset * 2;
      return OverflowBox(
        minWidth: width,
        maxWidth: width,
        minHeight: height,
        maxHeight: height,
        child: child,
      );
    },
  );
}

class IosControl extends StatefulWidget {
  const IosControl({
    super.key,
    required this.kind,
    required this.properties,
    this.onSelect,
    this.onLongPress,
    this.onTextChanged,
    this.horizontalDrag = false,
    this.eagerGestures = false,
    this.tapOnly = false,
  });

  final String kind;
  final Map<String, Object> properties;
  final ValueChanged<int>? onSelect;
  final VoidCallback? onLongPress;
  final ValueChanged<String>? onTextChanged;
  final bool horizontalDrag;
  final bool eagerGestures;
  final bool tapOnly;

  @override
  IosControlState createState() => IosControlState();
}

class IosControlState extends State<IosControl> {
  MethodChannel? _channel;

  bool get _hasGlassOutset => switch (widget.kind) {
    'button' || 'chatTitle' || 'chatAvatar' => true,
    _ => false,
  };

  void dismissKeyboard() => unawaited(_send('dismissKeyboard', true));

  Future<void> _send(String method, Object value) async {
    try {
      await _channel?.invokeMethod<void>(method, value);
    } on MissingPluginException {
      // A pending update may outlive a control during a route transition.
    }
  }

  @override
  void didUpdateWidget(IosControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(widget.properties, oldWidget.properties)) {
      unawaited(_send('update', widget.properties));
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasGlassOutset = _hasGlassOutset;
    // The taller glass buttons in profiles stretch further on a vertical drag.
    final verticalOutset =
        widget.kind == 'button' && widget.properties['stacked'] == true
        ? 24.0
        : meshIosGlassOutset;
    final view = UiKitView(
      viewType: 'meshgrame/controls',
      gestureBlockingPolicy: widget.eagerGestures || widget.tapOnly
          ? UiKitViewGestureBlockingPolicy.doNotBlockGesture
          : UiKitViewGestureBlockingPolicy.fallbackToPluginDefault,
      creationParams: {
        'kind': widget.kind,
        ...widget.properties,
        if (widget.tapOnly) 'tapOnly': true,
        if (hasGlassOutset) 'visualOutset': meshIosGlassOutset,
        if (verticalOutset != meshIosGlassOutset)
          'verticalVisualOutset': verticalOutset,
      },
      creationParamsCodec: const StandardMessageCodec(),
      gestureRecognizers: {
        if (widget.horizontalDrag)
          Factory<OneSequenceGestureRecognizer>(
            HorizontalDragGestureRecognizer.new,
          )
        else if (widget.tapOnly)
          Factory<OneSequenceGestureRecognizer>(TapGestureRecognizer.new)
        else if (widget.eagerGestures || widget.onTextChanged != null)
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
      onPlatformViewCreated: (id) {
        final channel = _channel = MethodChannel('meshgrame/controls/$id');
        channel.setMethodCallHandler((call) async {
          if (!mounted) return;
          switch ((call.method, call.arguments)) {
            case ('select', final int index):
              widget.onSelect?.call(index);
            case ('longPress', _):
              widget.onLongPress?.call();
            case ('text', final String text):
              widget.onTextChanged?.call(text);
          }
        });
        unawaited(_send('update', widget.properties));
      },
    );
    final clippedView = Visibility(
      visible: IosControlVisibility.visibleOf(context),
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: MeshSheetControlClip(child: view),
    );
    return hasGlassOutset
        ? MeshIosGlassFrame(verticalOutset: verticalOutset, child: clippedView)
        : clippedView;
  }
}
