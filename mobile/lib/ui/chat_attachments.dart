// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';

import '../mesh/network.dart';
import '../mesh/nodes.dart';
import 'position_picker.dart';
import 'style.dart';

typedef ShareableNode = ({Peer peer, String? link});

Future<String?> pickChatAttachment(
  BuildContext context, {
  required List<ShareableNode> contacts,
  NodePosition? initialPosition,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  backgroundColor: Colors.transparent,
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null,
  builder: (context) =>
      _AttachmentSheet(contacts: contacts, initialPosition: initialPosition),
);

enum _AttachmentTab { location, contact }

class _AttachmentSheet extends StatefulWidget {
  const _AttachmentSheet({required this.contacts, this.initialPosition});

  final List<ShareableNode> contacts;
  final NodePosition? initialPosition;

  @override
  State<_AttachmentSheet> createState() => _AttachmentSheetState();
}

class _AttachmentSheetState extends State<_AttachmentSheet> {
  final _map = MapController();
  final _contactSearch = TextEditingController();
  late final _point = ValueNotifier(widget.initialPosition);
  _AttachmentTab? _tab;
  bool _expanded = false;
  bool _locating = false;
  double? _zoom;
  int _selectionRevision = 0;
  double _drag = 0;
  String _query = '';
  String? _positionError;

  @override
  void dispose() {
    _map.dispose();
    _contactSearch.dispose();
    _point.dispose();
    super.dispose();
  }

  void _select(_AttachmentTab tab) => setState(() {
    _tab = tab;
  });

  void _back() {
    FocusScope.of(context).unfocus();
    setState(() {
      _expanded = false;
      _tab = null;
      _selectionRevision++;
    });
  }

  void _onGripEnd(DragEndDetails details) {
    final intent = _drag + (details.primaryVelocity ?? 0) * .10;
    if (intent < -32 && _tab != null) {
      setState(() => _expanded = true);
    } else if (intent > 32) {
      if (_expanded) {
        FocusScope.of(context).unfocus();
        setState(() => _expanded = false);
      } else {
        Navigator.pop(context);
      }
    }
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
      _setPoint(point);
      _map.move(meshMapPoint(point), 15);
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

  Widget _action(_AttachmentTab tab, IconData icon, String label) {
    final style = MeshStyle.of(context);
    return Material(
      color: style.accent.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _select(tab),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
          child: Column(
            children: [
              Icon(icon, color: style.accent),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contacts() {
    final style = MeshStyle.of(context);
    final visible = widget.contacts
        .where(
          (contact) =>
              contact.peer.name.toLowerCase().contains(_query) ||
              contact.peer.id.toLowerCase().contains(_query),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _contactSearch,
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            decoration: InputDecoration(
              isDense: true,
              hintText: tr(context, 'Поиск узлов', 'Search nodes'),
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: style.field,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      widget.contacts.isEmpty
                          ? tr(context, 'Список узлов пуст', 'No nodes yet')
                          : tr(context, 'Узлы не найдены', 'No matching nodes'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: style.secondary),
                    ),
                  ),
                )
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: visible.length,
                  itemBuilder: (_, index) {
                    final contact = visible[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: style.accent.withValues(alpha: .16),
                        foregroundColor: style.accent,
                        child: const Icon(Icons.person_outline_rounded),
                      ),
                      title: Text(
                        contact.peer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      enabled: contact.link != null,
                      subtitle: Text(
                        contact.link == null
                            ? tr(
                                context,
                                'Ссылка недоступна',
                                'Contact link unavailable',
                              )
                            : contact.peer.id,
                      ),
                      trailing: const Icon(
                        Icons.arrow_upward_rounded,
                        size: 18,
                      ),
                      onTap: contact.link == null
                          ? null
                          : () => Navigator.pop(context, contact.link),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _location() {
    final style = MeshStyle.of(context);
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              MeshMap(
                controller: _map,
                center: _point.value,
                zoom: _zoom,
                onCenterChanged: (point) {
                  _zoom = _map.camera.zoom;
                  _setPoint(point);
                },
                onMapTap: (point) {
                  _setPoint(point);
                  _map.move(meshMapPoint(point), _map.camera.zoom);
                },
                showCrosshair: true,
              ),
              PositionedDirectional(
                end: 12,
                top: 12,
                child: FloatingActionButton.small(
                  heroTag: null,
                  tooltip: tr(context, 'Моя геопозиция', 'My location'),
                  onPressed: _locating ? null : () => unawaited(_locate()),
                  child: _locating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: ValueListenableBuilder(
            valueListenable: _point,
            builder: (context, point, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _positionError ??
                      (point == null
                          ? tr(
                              context,
                              'Передвиньте карту, чтобы выбрать точку',
                              'Move the map to pick a point',
                            )
                          : formatChatPosition(point)),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: style.secondary, fontSize: 13),
                ),
                const SizedBox(height: 7),
                FilledButton.icon(
                  onPressed: point == null
                      ? null
                      : () => Navigator.pop(
                          context,
                          'geo:${formatChatPosition(point, separator: ',')}',
                        ),
                  icon: const Icon(Icons.place_outlined),
                  label: Text(
                    tr(context, 'Отправить геопозицию', 'Send location'),
                  ),
                ),
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
    final contact = tr(context, 'Контакт', 'Contact');
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final title = switch (_tab) {
      _AttachmentTab.location => location,
      _AttachmentTab.contact => tr(context, 'Узлы', 'Nodes'),
      null => tr(context, 'Вложения', 'Attachments'),
    };
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = (constraints.maxHeight - insets).clamp(
          0.0,
          constraints.maxHeight,
        );
        final fraction = _expanded || insets > 0
            ? .98
            : _tab == null
            ? .34
            : .69;
        return AnimatedPadding(
          duration: motion,
          padding: EdgeInsets.only(bottom: insets),
          child: AnimatedContainer(
            duration: motion,
            curve: Curves.easeOutCubic,
            height: (available * fraction).clamp(
              available < 212 ? available : 212.0,
              available,
            ),
            child: Material(
              color: style.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (_) => _drag = 0,
                      onVerticalDragUpdate: (details) =>
                          _drag += details.delta.dy,
                      onVerticalDragEnd: _onGripEnd,
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: _tab == null
                                ? tr(context, 'Закрыть', 'Close')
                                : tr(context, 'Назад', 'Back'),
                            onPressed: _tab == null
                                ? () => Navigator.pop(context)
                                : _back,
                            icon: Icon(
                              _tab == null
                                  ? Icons.close_rounded
                                  : Icons.arrow_back_rounded,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_tab != null)
                            IconButton(
                              tooltip: _expanded
                                  ? tr(context, 'Свернуть', 'Collapse')
                                  : tr(context, 'На весь экран', 'Expand'),
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                setState(() => _expanded = !_expanded);
                              },
                              icon: Icon(
                                _expanded
                                    ? Icons.close_fullscreen_rounded
                                    : Icons.open_in_full_rounded,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: switch (_tab) {
                        _AttachmentTab.location => _location(),
                        _AttachmentTab.contact => _contacts(),
                        null => ListView(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _action(
                                    _AttachmentTab.location,
                                    Icons.place_outlined,
                                    location,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _action(
                                    _AttachmentTab.contact,
                                    Icons.person_outline_rounded,
                                    contact,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      },
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
