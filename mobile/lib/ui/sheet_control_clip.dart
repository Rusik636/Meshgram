// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Marks the painted extent of an opaque sheet without adding a native view.
class MeshOpaqueSheetRegion extends SingleChildRenderObjectWidget {
  const MeshOpaqueSheetRegion({
    super.key,
    required this.presentingRoute,
    this.motion,
    this.topExtent = 0,
    required super.child,
  });

  final ModalRoute<dynamic>? presentingRoute;
  final Listenable? motion;
  final double topExtent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _SheetRegion()
        ..update(ModalRoute.of(context), presentingRoute, motion, topExtent);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _SheetRegion).update(
      ModalRoute.of(context),
      presentingRoute,
      motion,
      topExtent,
    );
  }
}

/// Keeps a native view mounted while withholding its part behind a sheet.
class MeshSheetControlClip extends SingleChildRenderObjectWidget {
  const MeshSheetControlClip({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ControlClip()..route = ModalRoute.of(context);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _ControlClip)
      ..route = ModalRoute.of(context)
      ..markNeedsPaint();
  }
}

final _sheetRegions = <_SheetRegion>{};
final _controlClips = <_ControlClip>{};

void _updateControls() {
  for (final control in _controlClips) {
    control.markNeedsPaint();
  }
}

class _SheetRegion extends RenderProxyBox {
  ModalRoute<dynamic>? route;
  ModalRoute<dynamic>? presentingRoute;
  Animation<double>? _transition;
  Listenable? _motion;
  double _topExtent = 0;

  Rect get bounds =>
      Rect.fromLTWH(0, -_topExtent, size.width, size.height + _topExtent);

  bool isAbove(ModalRoute<dynamic> controlRoute) {
    if (route == null || route == controlRoute || route == presentingRoute) {
      return false;
    }
    var presenter = presentingRoute;
    while (presenter != null) {
      if (presenter == controlRoute) return true;
      ModalRoute<dynamic>? next;
      for (final sheet in _sheetRegions) {
        if (sheet.route == presenter && sheet.presentingRoute != presenter) {
          next = sheet.presentingRoute;
          break;
        }
      }
      presenter = next;
    }
    return false;
  }

  void update(
    ModalRoute<dynamic>? owner,
    ModalRoute<dynamic>? presenter,
    Listenable? motion,
    double topExtent,
  ) {
    if (owner == route &&
        presenter == presentingRoute &&
        motion == _motion &&
        topExtent == _topExtent) {
      return;
    }
    if (attached) _unlisten();
    route = owner;
    presentingRoute = presenter;
    _transition = owner?.animation;
    _motion = motion;
    _topExtent = topExtent;
    if (attached) {
      _listen();
      _updateControls();
    }
  }

  void _listen() {
    _transition?.addListener(_updateControls);
    _motion?.addListener(_updateControls);
  }

  void _unlisten() {
    _transition?.removeListener(_updateControls);
    _motion?.removeListener(_updateControls);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _sheetRegions.add(this);
    _listen();
    _updateControls();
  }

  @override
  void detach() {
    _unlisten();
    _sheetRegions.remove(this);
    super.detach();
    _updateControls();
  }

  @override
  void performLayout() {
    super.performLayout();
    _updateControls();
  }
}

class _ControlClip extends RenderProxyBox {
  ModalRoute<dynamic>? route;
  final _clipLayer = LayerHandle<ContainerLayer>();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controlClips.add(this);
  }

  @override
  void detach() {
    _controlClips.remove(this);
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    super.dispose();
  }

  List<Rect> _visibleRects() {
    var visible = [Offset.zero & size];
    final owner = route;
    if (owner == null) return visible;
    for (final sheet in _sheetRegions) {
      if (!sheet.hasSize || !sheet.isAbove(owner)) continue;
      // Layout and animation transforms are current by the time controls paint.
      final covered = MatrixUtils.transformRect(
        sheet.getTransformTo(this),
        sheet.bounds,
      );
      if (!covered.isFinite || covered.isEmpty) continue;
      if (visible.any(covered.overlaps)) {
        visible = [for (final rect in visible) ..._subtract(rect, covered)];
        if (visible.isEmpty) break;
      }
    }
    return visible;
  }

  Iterable<Rect> _subtract(Rect rect, Rect covered) sync* {
    final overlap = rect.intersect(covered);
    if (overlap.isEmpty) {
      yield rect;
      return;
    }
    if (rect.top < overlap.top) {
      yield Rect.fromLTRB(rect.left, rect.top, rect.right, overlap.top);
    }
    if (overlap.bottom < rect.bottom) {
      yield Rect.fromLTRB(rect.left, overlap.bottom, rect.right, rect.bottom);
    }
    if (rect.left < overlap.left) {
      yield Rect.fromLTRB(rect.left, overlap.top, overlap.left, overlap.bottom);
    }
    if (overlap.right < rect.right) {
      yield Rect.fromLTRB(
        overlap.right,
        overlap.top,
        rect.right,
        overlap.bottom,
      );
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      _visibleRects().any((rect) => rect.contains(position)) &&
      super.hitTest(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    final visible = _visibleRects();
    if (visible.isEmpty) {
      _clipLayer.layer = null;
      return;
    }
    final oldLayer = _clipLayer.layer;
    if (visible.length == 1) {
      if (visible.single == (Offset.zero & size)) {
        _clipLayer.layer = null;
        super.paint(context, offset);
      } else {
        _clipLayer.layer = context.pushClipRect(
          needsCompositing,
          offset,
          visible.single,
          super.paint,
          oldLayer: oldLayer is ClipRectLayer ? oldLayer : null,
        );
      }
    } else {
      final path = Path();
      for (final rect in visible) {
        path.addRect(rect);
      }
      _clipLayer.layer = context.pushClipPath(
        needsCompositing,
        offset,
        Offset.zero & size,
        path,
        super.paint,
        clipBehavior: Clip.hardEdge,
        oldLayer: oldLayer is ClipPathLayer ? oldLayer : null,
      );
    }
  }
}
