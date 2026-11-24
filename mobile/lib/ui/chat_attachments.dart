// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';

import '../mesh/controller.dart';
import '../mesh/nodes.dart';
import 'attachment_sheet_route.dart';
import 'contact_picker.dart';
import 'ios_control.dart';
import 'location_search.dart';
import 'mesh_page_title.dart';
import 'navigation.dart';
import 'position_picker.dart';
import 'sheet_control_clip.dart';
import 'style.dart';

export 'contact_picker.dart' show ShareableNode;

typedef AttachmentPaperclip = ({
  Rect start,
  Size viewport,
  Rect? Function() currentRect,
  ValueChanged<bool> setHidden,
});

Future<String?> pickChatAttachment(
  BuildContext context, {
  required List<ShareableNode> contacts,
  MeshController? controller,
  NodePosition? initialPosition,
  List<AttachmentLocationNode> locationNodes = const [],
  AttachmentPaperclip? paperclip,
}) {
  final presentingRoute = useIosControls ? ModalRoute.of(context) : null;
  return showMeshAttachmentSheet<String>(
    context,
    morphFromSource: paperclip != null,
    builder: (context) => _AttachmentSheet(
      presentingRoute: presentingRoute,
      contacts: contacts,
      controller: controller,
      initialPosition: initialPosition,
      locationNodes: locationNodes,
      paperclip: paperclip,
    ),
  );
}

enum _AttachmentTab { location, contact }

class _AttachmentSheet extends StatefulWidget {
  const _AttachmentSheet({
    required this.presentingRoute,
    required this.contacts,
    required this.controller,
    required this.locationNodes,
    this.initialPosition,
    this.paperclip,
  });

  final ModalRoute<dynamic>? presentingRoute;
  final AttachmentPaperclip? paperclip;
  final List<ShareableNode> contacts;
  final MeshController? controller;
  final List<AttachmentLocationNode> locationNodes;
  final NodePosition? initialPosition;

  @override
  State<_AttachmentSheet> createState() => _AttachmentSheetState();
}

class _AttachmentSheetState extends State<_AttachmentSheet>
    with TickerProviderStateMixin {
  static const _contactHeaderDragHeight = 30.0;
  static const _attributionMargin = 8.0;
  static const _spring = SpringDescription(
    mass: 5,
    stiffness: 900,
    damping: 124,
  );

  final _map = MapController();
  final _contactSearch = TextEditingController();
  late final _point = ValueNotifier(widget.initialPosition);
  late final _tabs = MeshNavigationFade(this);
  // One compact inset is 1.0. Values above it move the sheet off the bottom.
  late final _inset = AnimationController.unbounded(vsync: this, value: 1);
  _AttachmentTab get _tab => _AttachmentTab.values[_tabs.shown];
  bool _expanded = false;
  bool? _expandedBeforeContactSearch;
  bool _locating = false;
  bool _closing = false;
  double? _zoom;
  int _selectionRevision = 0;
  String? _positionError;
  Drag? _gripDrag;
  Animation<double>? _paperclipAnimation;
  bool _paperclipOpened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.paperclip == null || _paperclipAnimation != null) return;
    _paperclipAnimation = ModalRoute.of(context)?.animation;
    _paperclipAnimation?.addStatusListener(_paperclipStatusChanged);
  }

  void _paperclipStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) _paperclipOpened = true;
    widget.paperclip?.setHidden(
      !MediaQuery.disableAnimationsOf(context) &&
          (status == AnimationStatus.forward ||
              status == AnimationStatus.reverse),
    );
  }

  @override
  void dispose() {
    if (_paperclipAnimation case final animation?) {
      animation.removeStatusListener(_paperclipStatusChanged);
      if (!animation.isDismissed) {
        final restoreSource = widget.paperclip!.setHidden;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => restoreSource(false),
        );
      }
    }
    _tabs.opacity.dispose();
    _inset.dispose();
    _map.dispose();
    _contactSearch.dispose();
    _point.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _tabs.selected || _expandedBeforeContactSearch != null) return;
    FocusScope.of(context).unfocus();
    _selectionRevision++;
    unawaited(
      _tabs.select(
        index,
        animate: meshMotion(context) != Duration.zero,
        rebuild: () => setState(() {}),
      ),
    );
  }

  void _changeContactSearch(bool searching) {
    if (searching) {
      _expandedBeforeContactSearch ??= _expanded;
      _snapTo(true, dismissKeyboard: false);
    } else {
      final previous = _expandedBeforeContactSearch;
      _expandedBeforeContactSearch = null;
      if (previous != null) _snapTo(previous, dismissKeyboard: false);
    }
  }

  void _snapTo(
    bool expanded, {
    double velocity = 0,
    bool dismissKeyboard = true,
  }) {
    final changed = _expanded != expanded;
    if (changed) {
      if (dismissKeyboard) FocusScope.of(context).unfocus();
      setState(() => _expanded = expanded);
    }
    final target = expanded ? 0.0 : 1.0;
    if (MediaQuery.disableAnimationsOf(context) || _inset.value == target) {
      _inset.value = target;
    } else if (changed) {
      unawaited(
        _inset.animateWith(
          SpringSimulation(
            _spring,
            _inset.value,
            target,
            velocity.abs() * (target - _inset.value).sign,
            snapToEnd: true,
          ),
        ),
      );
    } else {
      unawaited(
        _inset.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        ),
      );
    }
  }

  Drag? _startSheetDrag(double travel) {
    if (_closing || _expandedBeforeContactSearch != null || travel <= 0) {
      return null;
    }
    _inset.stop();
    return _AttachmentDrag(
      onUpdate: (delta) => _inset.value = (_inset.value + delta / travel).clamp(
        0.0,
        1.0 + MediaQuery.sizeOf(context).height / travel,
      ),
      onEnd: (velocity) => _endSheetDrag(travel, velocity),
      onCancel: () => _snapTo(_expanded),
    );
  }

  void _endSheetDrag(double travel, double velocity) {
    final inset = _inset.value;
    final overshoot = (inset - 1) * travel;
    if (overshoot > 60 ||
        (overshoot > 0 && velocity > 300) ||
        (_expanded && velocity > 1800)) {
      _closeSheet();
      return;
    }
    final expanded = _expanded
        ? velocity <= 300 && inset <= .5
        : velocity < -300 || inset < .5;
    _snapTo(expanded, velocity: velocity / travel);
  }

  void _closeSheet([String? result]) {
    if (_closing) return;
    _closing = true;
    Navigator.pop(context, result);
  }

  Future<void> _searchLocation() async {
    // A pending GPS fix cannot overwrite a point picked from search.
    _selectionRevision++;
    final point = await openAttachmentLocationSearch(
      context,
      nodes: widget.locationNodes,
    );
    if (!mounted || _tab != _AttachmentTab.location || point == null) return;
    _moveTo(point, 15);
  }

  void _moveTo(NodePosition point, double zoom) {
    _map.move(meshMapPoint(point), zoom);
    _zoom = zoom;
    _setPoint(point);
  }

  Future<void> _locate() async {
    if (_locating) return;
    final selection = _selectionRevision;
    bool stillSelecting() =>
        mounted &&
        _tab == _AttachmentTab.location &&
        selection == _selectionRevision;
    setState(() {
      _locating = true;
      _positionError = null;
    });
    String? error;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted || !stillSelecting()) return;
        error = tr(
          context,
          'Включите геолокацию на телефоне.',
          'Turn on location services.',
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (!stillSelecting()) return;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted || !stillSelecting()) return;
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        error = tr(
          context,
          'Разрешите доступ к геопозиции в настройках телефона.',
          'Allow location access in your phone settings.',
        );
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 12),
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!stillSelecting()) return;
      final point = (
        latitude: position.latitude,
        longitude: position.longitude,
      );
      _moveTo(point, 15);
    } catch (_) {
      if (mounted && stillSelecting()) {
        error = tr(
          context,
          'Телефон не смог определить геопозицию. Выберите точку на карте.',
          'Could not get your location. Pick a point on the map.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _locating = false;
          _positionError = stillSelecting() ? error : null;
        });
      }
    }
  }

  void _setPoint(NodePosition point) {
    _selectionRevision++;
    _point.value = point;
    if (_positionError != null) setState(() => _positionError = null);
  }

  Widget _locationMap() => MeshMap(
    controller: _map,
    center: _point.value,
    zoom: _zoom,
    onCenterChanged: (point) {
      _zoom = _map.camera.zoom;
      _setPoint(point);
    },
    onMapTap: (point) => _moveTo(point, _map.camera.zoom),
    showCrosshair: true,
    showAttribution: false,
  );

  Widget _location() {
    final style = MeshStyle.of(context);
    final locate = _locating
        ? const SizedBox.square(
            dimension: 48,
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        : GlassButton(
            icon: Icons.my_location_rounded,
            label: tr(context, 'Моя геопозиция', 'My location'),
            onTap: () => unawaited(_locate()),
          );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        PositionedDirectional(end: 12, top: 4, child: locate),
        PositionedDirectional(
          start: 16,
          end: 16,
          bottom: 4,
          child: ValueListenableBuilder(
            valueListenable: _point,
            builder: (context, point, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: GlassSurface(
                    radius: 16,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text(
                        _positionError ??
                            (point == null
                                ? tr(
                                    context,
                                    'Передвиньте карту, чтобы выбрать точку',
                                    'Move the map to pick a point',
                                  )
                                : formatChatPosition(point)),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: style.text, fontSize: 13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Center(
                  child: GlassActionButton(
                    primary: !useIosControls,
                    fitContent: true,
                    onTap: point == null
                        ? null
                        : () => _closeSheet(
                            'geo:${formatChatPosition(point, separator: ',')}',
                          ),
                    label: tr(context, 'Отправить', 'Send'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _locationHeading(String location) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        const buttonSize = 48.0;
        const actionGap = 6.0;
        const trailingWidth = 2 * buttonSize + actionGap;
        const idealTitleWidth = 150.0;
        // Balance the two trailing buttons while giving the title more
        // room on narrow phones.
        final leadingGap = useIosControls
            ? (constraints.maxWidth -
                      buttonSize -
                      trailingWidth -
                      idealTitleWidth)
                  .clamp(12.0, trailingWidth - buttonSize)
            : 12.0;
        return Row(
          children: [
            GlassButton(
              icon: Icons.close_rounded,
              label: tr(context, 'Закрыть', 'Close'),
              onTap: _closeSheet,
            ),
            SizedBox(width: leadingGap),
            Expanded(
              child: MeshPageTitle(
                location,
                fallback: Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            GlassButton(
              icon: Icons.search_rounded,
              label: tr(context, 'Искать геопозицию', 'Search locations'),
              onTap: () => unawaited(_searchLocation()),
            ),
            const SizedBox(width: actionGap),
            GlassButton(
              icon: _expanded
                  ? Icons.close_fullscreen_rounded
                  : Icons.open_in_full_rounded,
              label: _expanded
                  ? tr(context, 'Свернуть', 'Collapse')
                  : tr(context, 'На весь экран', 'Expand'),
              onTap: () => _snapTo(!_expanded),
            ),
          ],
        );
      },
    ),
  );

  Widget _dragHeader(
    double travel,
    Widget child, {
    Key? key,
    bool translucent = false,
  }) {
    final canDrag = travel > 0 && _expandedBeforeContactSearch == null;
    return GestureDetector(
      key: key,
      // Keep the Contacts header buttons tappable through the drag area.
      behavior: translucent
          ? HitTestBehavior.translucent
          : HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onVerticalDragStart: canDrag
          ? (_) => _gripDrag = _startSheetDrag(travel)
          : null,
      onVerticalDragUpdate: canDrag
          ? (details) => _gripDrag?.update(details)
          : null,
      onVerticalDragEnd: canDrag
          ? (details) {
              final drag = _gripDrag;
              _gripDrag = null;
              drag?.end(details);
            }
          : null,
      onVerticalDragCancel: canDrag
          ? () {
              final drag = _gripDrag;
              _gripDrag = null;
              drag?.cancel();
            }
          : null,
      child: child,
    );
  }

  Widget _layout(
    String location,
    double travel,
    double panelProgress,
    double attributionHeight,
  ) {
    final showingMap = _tab == _AttachmentTab.location;
    final navigationBottom = MeshTabBar.bottomOffset(context) + 6;
    final panelExtent = MeshTabBar.heightOf(context) + navigationBottom + 6;
    final footer = math.max(
      MediaQuery.paddingOf(context).bottom,
      showingMap ? attributionHeight : 0.0,
    );
    final bottomObstruction = math.max(footer, panelExtent * panelProgress);
    final pane = Stack(
      key: ValueKey(_tab),
      children: [
        if (showingMap) ...[
          Positioned.fill(child: _locationMap()),
          const PositionedDirectional(
            start: _attributionMargin,
            end: _attributionMargin,
            bottom: 0,
            child: Align(
              alignment: AlignmentDirectional.bottomEnd,
              child: MeshMapAttribution(),
            ),
          ),
          Positioned.fill(
            bottom: bottomObstruction,
            child: Column(
              children: [
                _dragHeader(travel, _locationHeading(location)),
                Expanded(child: _location()),
              ],
            ),
          ),
        ] else ...[
          Positioned.fill(
            child: AttachmentContacts(
              contacts: widget.contacts,
              controller: widget.controller,
              search: _contactSearch,
              expanded: _expanded,
              bottomObstruction: bottomObstruction,
              onClose: _closeSheet,
              onSearchChanged: _changeContactSearch,
              onSelect: _closeSheet,
              beginSheetDrag: () => _startSheetDrag(travel),
            ),
          ),
          if (Theme.of(context).platform == TargetPlatform.iOS)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _contactHeaderDragHeight,
              child: _dragHeader(
                travel,
                const SizedBox.expand(),
                translucent: true,
              ),
            ),
        ],
      ],
    );
    final switching = _tabs.shown != _tabs.selected;
    final panel = Material(
      key: const ValueKey('attachment-sheet-panel'),
      color: MeshStyle.of(context).surface,
      borderRadius: BorderRadius.circular(_expanded && showingMap ? 0 : 26),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              key: const ValueKey('attachment-tab-pane'),
              opacity: _tabs.opacity,
              child: IgnorePointer(
                ignoring: switching,
                child: ExcludeSemantics(excluding: switching, child: pane),
              ),
            ),
          ),
          if (panelProgress > 0)
            PositionedDirectional(
              start: 16,
              end: 16,
              bottom: navigationBottom - panelExtent * (1 - panelProgress),
              child: IgnorePointer(
                ignoring: _expanded,
                child: ExcludeSemantics(
                  excluding: _expanded,
                  child: MeshTabBar(
                    labels: [location, tr(context, 'Контакт', 'Contact')],
                    icons: const [
                      Icons.place_outlined,
                      Icons.person_outline_rounded,
                    ],
                    symbols: const ['location.fill', 'person.crop.circle'],
                    index: _tabs.selected,
                    onSelect: _select,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final separateRegion =
        useIosControls &&
        (widget.paperclip == null || _paperclipAnimation == null);
    return Column(
      children: [
        _dragHeader(
          travel,
          const MeshSheetGrip(),
          key: const ValueKey('attachment-grip'),
        ),
        Expanded(
          child: separateRegion
              ? MeshOpaqueSheetRegion(
                  presentingRoute: widget.presentingRoute,
                  motion: _inset,
                  child: panel,
                )
              : panel,
        ),
      ],
    );
  }

  Widget _withPaperclipTransition(Widget panel, Size size, double bottom) {
    final paperclip = widget.paperclip;
    final animation = _paperclipAnimation;
    if (paperclip == null || animation == null) return panel;
    return _AttachmentPaperclipMorph(
      presentingRoute: widget.presentingRoute,
      detent: _inset,
      animation: animation,
      paperclip: paperclip,
      sheetWasOpened: () => _paperclipOpened,
      size: size,
      bottom: bottom,
      cornerRadius: _expanded && _tab == _AttachmentTab.location ? 0 : 26,
      child: panel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = tr(context, 'Геопозиция', 'Location');
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final attributionHeight = MeshMapAttribution.heightFor(
          context,
          constraints.maxWidth - _attributionMargin * 2,
        );
        final available = (constraints.maxHeight - keyboard).clamp(
          0.0,
          constraints.maxHeight,
        );
        final minHeight = available.clamp(0.0, 232.0);
        final fraction = constraints.maxWidth <= 320 ? .15 : .2488;
        final travel = (available * fraction).floorToDouble().clamp(
          0.0,
          available - minHeight,
        );
        final dragTravel = keyboard > 0 ? 0.0 : travel;
        return TweenAnimationBuilder<double>(
          tween: Tween(end: _expanded || keyboard > 0 ? 0.0 : 1.0),
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          builder: (context, panelProgress, _) => AnimatedBuilder(
            animation: _inset,
            child: _layout(
              location,
              dragTravel,
              panelProgress,
              attributionHeight,
            ),
            builder: (context, child) {
              final topInset = _inset.value.clamp(0.0, 1.0) * travel;
              final overshoot = (_inset.value - 1).clamp(0.0, double.infinity);
              return Padding(
                padding: EdgeInsets.only(bottom: keyboard),
                child: Transform.translate(
                  offset: Offset(0, overshoot * travel),
                  child: SizedBox(
                    height: available - topInset,
                    child: _withPaperclipTransition(
                      child!,
                      Size(constraints.maxWidth, available - topInset),
                      keyboard - overshoot * travel,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _AttachmentPaperclipMorph extends StatelessWidget {
  const _AttachmentPaperclipMorph({
    required this.presentingRoute,
    required this.detent,
    required this.animation,
    required this.paperclip,
    required this.sheetWasOpened,
    required this.size,
    required this.bottom,
    required this.cornerRadius,
    required this.child,
  });

  final ModalRoute<dynamic>? presentingRoute;
  final Listenable detent;
  final Animation<double> animation;
  final AttachmentPaperclip paperclip;
  final bool Function() sheetWasOpened;
  final Size size;
  final double bottom;
  final double cornerRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safe = MediaQueryData.fromView(View.of(context)).padding;
    final origin = Offset(
      safe.left + (media.size.width - safe.horizontal - size.width) / 2,
      media.size.height - bottom - size.height,
    );
    final style = MeshStyle.of(context);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, panel) {
        final inFlight = !media.disableAnimations && !animation.isCompleted;
        final progress = inFlight ? animation.value : 1.0;
        final useCurrentSource =
            media.size != paperclip.viewport ||
            (animation.status == AnimationStatus.reverse && sheetWasOpened());
        final source = useCurrentSource
            ? paperclip.currentRect() ?? paperclip.start
            : paperclip.start;
        final bounds = Rect.lerp(
          source.shift(-origin),
          Rect.fromLTWH(
            0,
            MeshSheetGrip.height,
            size.width,
            math.max(0, size.height - MeshSheetGrip.height),
          ),
          Curves.easeInOutCubic.transform(progress),
        )!;
        final sourceRadius = source.shortestSide / 2;
        final radius =
            sourceRadius +
            (cornerRadius - sourceRadius) *
                Curves.easeInOut.transform(progress);
        final outline = RRect.fromRectAndRadius(
          bounds,
          Radius.circular(radius),
        );
        final glyphOpacity = 1 - const Interval(.08, .40).transform(progress);
        final panelOpacity = const Interval(
          .48,
          .94,
          curve: Curves.easeOut,
        ).transform(progress);
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            if (useIosControls)
              Positioned.fromRect(
                rect: bounds,
                child: MeshOpaqueSheetRegion(
                  presentingRoute: presentingRoute,
                  motion: detent,
                  child: const SizedBox.expand(),
                ),
              ),
            if (inFlight)
              Positioned.fromRect(
                rect: bounds,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: ClipRRect(
                      key: const ValueKey('attachment-paperclip-flight'),
                      borderRadius: BorderRadius.circular(radius),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: style.surface),
                          if (glyphOpacity > 0)
                            Center(
                              child: Opacity(
                                key: const ValueKey(
                                  'attachment-paperclip-glyph',
                                ),
                                opacity: glyphOpacity,
                                child: SizedBox.square(
                                  dimension: 22,
                                  child: useIosControls
                                      ? IosControl(
                                          kind: 'symbolIcon',
                                          properties: {
                                            'symbol': 'paperclip',
                                            'pointSize': 18.0,
                                            'accent': style.text.toARGB32(),
                                          },
                                        )
                                      : Icon(
                                          CupertinoIcons.paperclip,
                                          size: 18,
                                          color: style.text,
                                        ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            IgnorePointer(
              ignoring: inFlight,
              child: ExcludeSemantics(
                excluding: inFlight,
                child: Opacity(
                  opacity: panelOpacity,
                  child: ClipRRect(
                    clipper: inFlight ? _AttachmentMorphClip(outline) : null,
                    clipBehavior: inFlight ? Clip.antiAlias : Clip.none,
                    child: panel,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AttachmentMorphClip extends CustomClipper<RRect> {
  const _AttachmentMorphClip(this.outline);

  final RRect outline;

  @override
  RRect getClip(Size size) => outline;

  @override
  bool shouldReclip(_AttachmentMorphClip oldClipper) =>
      outline != oldClipper.outline;
}

class _AttachmentDrag extends Drag {
  _AttachmentDrag({
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final void Function(double) onUpdate, onEnd;
  final VoidCallback onCancel;

  @override
  void update(DragUpdateDetails details) => onUpdate(details.delta.dy);

  @override
  void end(DragEndDetails details) =>
      onEnd(details.primaryVelocity ?? details.velocity.pixelsPerSecond.dy);

  @override
  void cancel() => onCancel();
}

String formatChatPosition(NodePosition point, {String separator = ', '}) =>
    '${point.latitude.toStringAsFixed(6)}$separator${point.longitude.toStringAsFixed(6)}';
