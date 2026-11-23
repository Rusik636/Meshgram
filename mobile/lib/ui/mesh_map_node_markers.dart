// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

part of 'mesh_map.dart';

const _nodeMarkerDiameter = 52.0;
const _clusterRadius = 66.0;
const _clusterHeadroom = .35;
const _clusterMemberDiameter = 26.0;
const _clusterMaxDiameter = 84.0;

class _NodeMarkerGroup {
  const _NodeMarkerGroup(
    this.members,
    this.center,
    this.color, [
    this.mergeDistance = 0,
  ]);

  final List<MeshMapPin> members;
  final Offset center;
  final Color color;
  final double mergeDistance;

  bool get isSingle => members.length == 1;
}

typedef _NearbyPair = ({int first, int second, double distanceSquared});

int _worldCopy(double x, double center, double world) =>
    world == 0 ? 0 : ((center - x) / world).round();

List<_NodeMarkerGroup> _clusterNodes(
  List<MeshMapPin> pins,
  List<Offset> points,
) {
  // RURUS combines the closest pair of screen-space bubbles at each step.
  // Their midpoint and color are mixed evenly, regardless of group size.
  final active = <int, _NodeMarkerGroup>{};
  final cells = <(int, int), Set<int>>{};
  final nearby = SplayTreeSet<_NearbyPair>((a, b) {
    final distance = a.distanceSquared.compareTo(b.distanceSquared);
    if (distance != 0) return distance;
    final first = a.first.compareTo(b.first);
    return first == 0 ? a.second.compareTo(b.second) : first;
  });
  var nextId = 0;

  (int, int) cell(Offset point) => (
    (point.dx / _clusterRadius).floor(),
    (point.dy / _clusterRadius).floor(),
  );

  void add(_NodeMarkerGroup group) {
    final id = nextId++;
    final (x, y) = cell(group.center);
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final neighbor in cells[(x + dx, y + dy)] ?? const <int>{}) {
          final distance =
              (active[neighbor]!.center - group.center).distanceSquared;
          if (distance <= _clusterRadius * _clusterRadius) {
            nearby.add((
              first: neighbor,
              second: id,
              distanceSquared: distance,
            ));
          }
        }
      }
    }
    active[id] = group;
    (cells[(x, y)] ??= {}).add(id);
  }

  for (final (index, pin) in pins.indexed) {
    add(
      _NodeMarkerGroup(
        [pin],
        points[index],
        MeshAvatar.colorsFor(pin._avatarName!).$2,
      ),
    );
  }

  while (nearby.isNotEmpty) {
    final pair = nearby.first;
    nearby.remove(pair);
    final first = active[pair.first];
    final second = active[pair.second];
    if (first == null || second == null) continue;
    active
      ..remove(pair.first)
      ..remove(pair.second);
    cells[cell(first.center)]!.remove(pair.first);
    cells[cell(second.center)]!.remove(pair.second);
    add(
      _NodeMarkerGroup(
        [...first.members, ...second.members],
        (first.center + second.center) / 2,
        Color.lerp(first.color, second.color, .5)!,
        math.sqrt(pair.distanceSquared),
      ),
    );
  }
  return active.values.toList();
}

class _NodeMarkerLayer extends StatefulWidget {
  const _NodeMarkerLayer({required this.pins});

  final List<MeshMapPin> pins;

  @override
  State<_NodeMarkerLayer> createState() => _NodeMarkerLayerState();
}

class _NodeMarkerLayerState extends State<_NodeMarkerLayer> {
  List<MeshMapPin>? _projectedPins;
  double? _projectedZoom;
  var _projected = const <Offset>[];
  var _worldCopies = const <int>[];
  var _groups = const <_NodeMarkerGroup>[];

  List<_NodeMarkerGroup> _groupsFor(
    MapCamera camera,
    double centerX,
    double world,
  ) {
    final pins = widget.pins;
    final shouldProject =
        !identical(pins, _projectedPins) || camera.zoom != _projectedZoom;
    if (shouldProject) {
      _projectedPins = pins;
      _projectedZoom = camera.zoom;
      _projected = [
        for (final pin in pins)
          camera.projectAtZoom(meshMapPoint(pin.position)),
      ];
    }
    final copies = [
      for (final point in _projected) _worldCopy(point.dx, centerX, world),
    ];
    // A pan only moves the markers. Regroup when zoom or a wrapped world
    // changes, or when the caller provides a new set of nodes.
    if (shouldProject || !listEquals(copies, _worldCopies)) {
      _worldCopies = copies;
      _groups = _clusterNodes(pins, [
        for (final (index, point) in _projected.indexed)
          point.translate(world * copies[index], 0),
      ]);
    }
    return _groups;
  }

  Future<void> _openGroup(
    BuildContext context,
    MapCamera camera,
    _NodeMarkerGroup group,
  ) async {
    final maxZoom = camera.maxZoom ?? 19;
    if (group.mergeDistance > 0) {
      final steps =
          math.log(_clusterRadius / group.mergeDistance) / math.ln2 +
          _clusterHeadroom;
      if (camera.zoom + steps <= maxZoom &&
          MapController.of(
            context,
          ).move(camera.unprojectAtZoom(group.center), camera.zoom + steps)) {
        return;
      }
    }

    // Overlapping nodes at the closest zoom can still be opened individually.
    final style = MeshStyle.of(context);
    final members = group.members.toList()
      ..sort(
        (a, b) => a._avatarName!.toLowerCase().compareTo(
          b._avatarName!.toLowerCase(),
        ),
      );
    final selection = await showModalBottomSheet<MeshMapPin>(
      context: context,
      useSafeArea: true,
      backgroundColor: style.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: members.length,
          itemBuilder: (context, index) {
            final pin = members[index];
            final name = pin._avatarName!;
            return ListTile(
              leading: MeshAvatar(name, size: 38, online: pin._online),
              title: Text(name),
              subtitle: Text(pin._nodeId!),
              trailing: const Icon(Icons.chevron_right_rounded),
              enabled: pin.onTap != null,
              onTap: pin.onTap == null
                  ? null
                  : () => Navigator.pop(context, pin),
            );
          },
        ),
      ),
    );
    if (context.mounted) selection?.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final style = MeshStyle.of(context);
    final motion = meshMotion(context);
    final labelHeight = MediaQuery.textScalerOf(context).scale(12) * 1.3 + 9;
    final world = camera.getWorldWidthAtZoom();
    final centerX = camera.pixelOrigin.dx + camera.size.width / 2;
    final groups = _groupsFor(camera, centerX, world);
    Offset localPoint(LatLng point) {
      final projected = camera.projectAtZoom(point);
      return projected.translate(
            world * _worldCopy(projected.dx, centerX, world),
            0,
          ) -
          camera.pixelOrigin;
    }

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final group in groups)
            for (final pin in group.members)
              TweenAnimationBuilder<LatLng>(
                key: ValueKey(pin._nodeId),
                tween: _MarkerPositionTween(
                  meshMapPoint(pin.position),
                  group.isSingle
                      ? meshMapPoint(pin.position)
                      : camera.unprojectAtZoom(group.center),
                ),
                duration: motion,
                curve: const Cubic(.55, .06, .28, 1),
                builder: (context, position, child) {
                  final point = localPoint(position);
                  return Positioned(
                    left: point.dx - 81,
                    top:
                        point.dy -
                        _nodeMarkerDiameter / 2 -
                        (pin.label == null ? 0 : labelHeight),
                    width: 162,
                    height:
                        _nodeMarkerDiameter +
                        (pin.label == null ? 0 : labelHeight),
                    child: child!,
                  );
                },
                child: IgnorePointer(
                  ignoring: !group.isSingle,
                  child: ExcludeSemantics(
                    excluding: !group.isSingle,
                    child: AnimatedOpacity(
                      duration: motion,
                      opacity: group.isSingle ? 1 : 0,
                      child: _NodeAvatarMarker(pin: pin),
                    ),
                  ),
                ),
              ),
          for (final group in groups)
            if (!group.isSingle)
              _NodeGroupMarker(
                key: ValueKey(
                  group.members.map((pin) => pin._nodeId).join(' '),
                ),
                center: group.center - camera.pixelOrigin,
                group: group,
                borderColor: style.surface,
                onTap: () => unawaited(_openGroup(context, camera, group)),
              ),
        ],
      ),
    );
  }
}

class _MarkerPositionTween extends Tween<LatLng> {
  _MarkerPositionTween(LatLng begin, LatLng end)
    : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) {
    final start = begin!;
    final target = end!;
    final longitude = (target.longitude - start.longitude + 180) % 360 - 180;
    return LatLng(
      ui.lerpDouble(start.latitude, target.latitude, t)!,
      (start.longitude + longitude * t + 180) % 360 - 180,
    );
  }
}

class _NodeAvatarMarker extends StatelessWidget {
  const _NodeAvatarMarker({required this.pin});

  final MeshMapPin pin;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final name = pin._avatarName!;
    return GestureDetector(
      onTap: pin.onTap,
      excludeFromSemantics: true,
      child: Semantics(
        label: name,
        button: pin.onTap != null,
        excludeSemantics: true,
        onTap: pin.onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (pin.label case final label?)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: style.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: style.text,
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            SizedBox.square(
              dimension: _nodeMarkerDiameter,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: style.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2.5),
                    child: MeshAvatar(name, size: 44, online: pin._online),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeGroupMarker extends StatelessWidget {
  const _NodeGroupMarker({
    super.key,
    required this.center,
    required this.group,
    required this.borderColor,
    required this.onTap,
  });

  final Offset center;
  final _NodeMarkerGroup group;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = group.members.length;
    final diameter = math.min(
      _clusterMaxDiameter,
      math.sqrt(
        _nodeMarkerDiameter * _nodeMarkerDiameter +
            (count - 1) * _clusterMemberDiameter * _clusterMemberDiameter,
      ),
    );
    final duration = meshMotion(context);
    return Positioned(
      left: center.dx - diameter / 2,
      top: center.dy - diameter / 2,
      width: diameter,
      height: diameter,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: duration == Duration.zero ? 1 : .76, end: 1),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Semantics(
          label: tr(context, 'Группа узлов, $count', 'Node group, $count'),
          button: true,
          excludeSemantics: true,
          onTap: onTap,
          child: GestureDetector(
            onTap: onTap,
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: group.color,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 2.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    MaterialLocalizations.of(context).formatDecimal(count),
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
