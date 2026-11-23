// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';

import '../mesh/controller.dart';
import '../mesh/nodes.dart';
import 'contact_picker.dart';
import 'ios_control.dart';
import 'location_search.dart';
import 'navigation.dart';
import 'position_picker.dart';
import 'style.dart';

export 'contact_picker.dart' show ShareableNode;

Future<String?> pickChatAttachment(
  BuildContext context, {
  required List<ShareableNode> contacts,
  MeshController? controller,
  NodePosition? initialPosition,
  List<AttachmentLocationNode> locationNodes = const [],
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  backgroundColor: Colors.transparent,
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null,
  builder: (context) => _AttachmentSheet(
    contacts: contacts,
    controller: controller,
    initialPosition: initialPosition,
    locationNodes: locationNodes,
  ),
);

enum _AttachmentTab { location, contact }

class _AttachmentSheet extends StatefulWidget {
  const _AttachmentSheet({
    required this.contacts,
    required this.controller,
    required this.locationNodes,
    this.initialPosition,
  });

  final List<ShareableNode> contacts;
  final MeshController? controller;
  final List<AttachmentLocationNode> locationNodes;
  final NodePosition? initialPosition;

  @override
  State<_AttachmentSheet> createState() => _AttachmentSheetState();
}

class _AttachmentSheetState extends State<_AttachmentSheet>
    with TickerProviderStateMixin {
  static const _gripHeight = 18.0;
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

  @override
  void dispose() {
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
                GlassActionButton(
                  primary: !useIosControls,
                  onTap: point == null
                      ? null
                      : () => _closeSheet(
                          'geo:${formatChatPosition(point, separator: ',')}',
                        ),
                  label: tr(context, 'Отправить геопозицию', 'Send location'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(String location, double travel) {
    final style = MeshStyle.of(context);
    return GestureDetector(
      key: const ValueKey('attachment-grip'),
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onVerticalDragStart: travel > 0
          ? (_) => _gripDrag = _startSheetDrag(travel)
          : null,
      onVerticalDragUpdate: (details) => _gripDrag?.update(details),
      onVerticalDragEnd: (details) {
        final drag = _gripDrag;
        _gripDrag = null;
        drag?.end(details);
      },
      onVerticalDragCancel: () {
        final drag = _gripDrag;
        _gripDrag = null;
        drag?.cancel();
      },
      child: Column(
        children: [
          SizedBox(
            height: _gripHeight,
            width: double.infinity,
            child: Center(
              child: Container(
                width: 35,
                height: 3,
                decoration: BoxDecoration(
                  color: style.secondary.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          if (_tab == _AttachmentTab.location)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  GlassButton(
                    icon: Icons.close_rounded,
                    label: tr(context, 'Закрыть', 'Close'),
                    onTap: _closeSheet,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  GlassButton(
                    icon: Icons.search_rounded,
                    label: tr(context, 'Искать геопозицию', 'Search locations'),
                    onTap: () => unawaited(_searchLocation()),
                  ),
                  const SizedBox(width: 6),
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
              ),
            ),
        ],
      ),
    );
  }

  Widget _layout(
    String location,
    double travel,
    double panelProgress,
    double attributionHeight,
  ) {
    final showingMap = _tab == _AttachmentTab.location;
    final navigationBottom = MeshTabBar.bottomOffset(context);
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
          Positioned.fill(
            bottom: bottomObstruction,
            child: Column(
              children: [
                _header(location, travel),
                Expanded(child: _location()),
              ],
            ),
          ),
          const PositionedDirectional(
            start: _attributionMargin,
            end: _attributionMargin,
            bottom: 0,
            child: Align(
              alignment: AlignmentDirectional.bottomEnd,
              child: MeshMapAttribution(),
            ),
          ),
        ] else ...[
          Positioned.fill(
            top: _gripHeight,
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
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _header(location, travel),
          ),
        ],
      ],
    );
    final switching = _tabs.shown != _tabs.selected;
    return Material(
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
                  child: SizedBox(height: available - topInset, child: child),
                ),
              );
            },
          ),
        );
      },
    );
  }
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
