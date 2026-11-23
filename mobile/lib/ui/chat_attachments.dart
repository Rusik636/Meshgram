// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
  Uint8List? backdrop,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  backgroundColor: Colors.transparent,
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null,
  builder: (context) => MessageMenuBackdrop(
    image: backdrop,
    child: _AttachmentSheet(
      contacts: contacts,
      controller: controller,
      initialPosition: initialPosition,
      locationNodes: locationNodes,
    ),
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

class _AttachmentSheetState extends State<_AttachmentSheet> {
  final _map = MapController();
  final _contactSearch = TextEditingController();
  late final _point = ValueNotifier(widget.initialPosition);
  _AttachmentTab _tab = _AttachmentTab.location;
  bool _expanded = false;
  bool _locating = false;
  bool _dragging = false;
  double? _zoom;
  int _selectionRevision = 0;
  double _drag = 0;
  String? _positionError;

  @override
  void dispose() {
    _map.dispose();
    _contactSearch.dispose();
    _point.dispose();
    super.dispose();
  }

  void _select(int index) {
    final tab = _AttachmentTab.values[index];
    if (tab == _tab) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _tab = tab;
      _selectionRevision++;
    });
  }

  void _setExpanded(bool expanded) {
    setState(() => _expanded = expanded);
  }

  void _resetDrag() {
    setState(() {
      _dragging = false;
      _drag = 0;
    });
  }

  void _onGripEnd(DragEndDetails details) {
    final intent = _drag + (details.primaryVelocity ?? 0) * .10;
    _resetDrag();
    if (intent < -32 && !_expanded) {
      _setExpanded(true);
    } else if (intent > 32) {
      if (_expanded) {
        FocusScope.of(context).unfocus();
        _setExpanded(false);
      } else {
        Navigator.pop(context);
      }
    }
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

  Widget _sheetSurface(Widget child) {
    if (_tab != _AttachmentTab.location) {
      return MessageMenuSurface(radius: 26, child: child);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(_expanded ? 0 : 26),
      child: Stack(fit: StackFit.expand, children: [_locationMap(), child]),
    );
  }

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
                      : () => Navigator.pop(
                          context,
                          'geo:${formatChatPosition(point, separator: ',')}',
                        ),
                  label: tr(context, 'Отправить геопозицию', 'Send location'),
                ),
                const SizedBox(height: 5),
                const Center(child: MeshMapAttribution()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final location = tr(context, 'Геопозиция', 'Location');
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final motion = _dragging || keyboard > 0
        ? Duration.zero
        : meshMotion(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = (constraints.maxHeight - keyboard).clamp(
          0.0,
          constraints.maxHeight,
        );
        final minHeight = available < 232 ? available : 232.0;
        final fraction = _expanded || keyboard > 0 ? 1.0 : .72;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: AnimatedContainer(
            duration: motion,
            curve: Curves.easeOutCubic,
            height: (available * fraction - _drag).clamp(minHeight, available),
            child: _sheetSurface(
              SafeArea(
                top: false,
                // The compact native bar occupies the bottom inset itself.
                bottom: _expanded || !useIosControls,
                child: Column(
                  children: [
                    GestureDetector(
                      key: const ValueKey('attachment-grip'),
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (_) =>
                          setState(() => _dragging = true),
                      onVerticalDragUpdate: (details) =>
                          setState(() => _drag += details.delta.dy),
                      onVerticalDragEnd: _onGripEnd,
                      onVerticalDragCancel: _resetDrag,
                      child: SizedBox(
                        height: 18,
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
                    ),
                    if (_tab == _AttachmentTab.location) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Row(
                          children: [
                            GlassButton(
                              icon: Icons.close_rounded,
                              label: tr(context, 'Закрыть', 'Close'),
                              onTap: () => Navigator.pop(context),
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
                              label: tr(
                                context,
                                'Искать геопозицию',
                                'Search locations',
                              ),
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
                              onTap: () {
                                FocusScope.of(context).unfocus();
                                _setExpanded(!_expanded);
                              },
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: _location()),
                    ] else
                      Expanded(
                        child: AttachmentContacts(
                          contacts: widget.contacts,
                          controller: widget.controller,
                          search: _contactSearch,
                          expanded: _expanded,
                          onClose: () => Navigator.pop(context),
                          onToggleExpand: () => _setExpanded(!_expanded),
                          onSelect: (link) => Navigator.pop(context, link),
                        ),
                      ),
                    if (!_expanded)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          6,
                          16,
                          useIosControls ? 0 : 8,
                        ),
                        child: MeshTabBar(
                          labels: [location, tr(context, 'Контакт', 'Contact')],
                          icons: const [
                            Icons.place_outlined,
                            Icons.person_outline_rounded,
                          ],
                          symbols: const [
                            'location.fill',
                            'person.crop.circle',
                          ],
                          index: _tab.index,
                          onSelect: _select,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String formatChatPosition(NodePosition point, {String separator = ', '}) =>
    '${point.latitude.toStringAsFixed(6)}$separator${point.longitude.toStringAsFixed(6)}';
