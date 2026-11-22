import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_name.dart';
import '../mesh/nodes.dart';
import 'page_route.dart';
import 'style.dart';

Future<NodePosition?> pickNodePosition(
  BuildContext context,
  NodePosition? initial,
) => Navigator.of(context).push<NodePosition>(
  meshPageRoute(context, builder: (_) => _PositionPicker(initial: initial)),
);

class _PositionPicker extends StatefulWidget {
  const _PositionPicker({required this.initial});
  final NodePosition? initial;

  @override
  State<_PositionPicker> createState() => _PositionPickerState();
}

class _PositionPickerState extends State<_PositionPicker> {
  static const _darkTiles = ColorFilter.matrix([
    -.32,
    -.30,
    -.05,
    0,
    184,
    -.18,
    -.42,
    -.07,
    0,
    191,
    -.18,
    -.32,
    -.17,
    0,
    204,
    0,
    0,
    0,
    1,
    0,
  ]);

  late final _center = ValueNotifier(
    LatLng(
      widget.initial?.latitude.clamp(-85, 85).toDouble() ?? 25,
      widget.initial?.longitude ?? 25,
    ),
  );
  late final _initial = _center.value;
  final _tiles = NetworkTileProvider(
    headers: {'User-Agent': '$appName (dev.meshgrame.client)'},
  );

  @override
  void dispose() {
    _center.dispose();
    super.dispose();
  }

  NodePosition get _coordinates => (
    latitude: _center.value.latitude.clamp(-85, 85).toDouble(),
    longitude: (_center.value.longitude + 180) % 360 - 180,
  );

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final safe = MediaQuery.paddingOf(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _initial,
              initialZoom: widget.initial == null ? 3 : 16,
              minZoom: 2,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              backgroundColor: style.dark
                  ? const Color(0xff101623)
                  : const Color(0xffedf0eb),
              onPositionChanged: (camera, _) => _center.value = camera.center,
            ),
            children: [
              ColorFiltered(
                colorFilter: style.dark
                    ? _darkTiles
                    : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                child: TileLayer(
                  urlTemplate: const String.fromEnvironment(
                    'MESHGRAME_MAP_TILES',
                    defaultValue:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),
                  tileProvider: _tiles,
                  panBuffer: 0,
                ),
              ),
            ],
          ),
          IgnorePointer(
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: style.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                  Positioned(
                    bottom: 1,
                    child: Icon(
                      Icons.place_rounded,
                      size: 43,
                      color: style.accent,
                      shadows: const [
                        Shadow(blurRadius: 5, color: Colors.black45),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: safe.left + 16,
            top: safe.top + 7,
            child: GlassButton(
              icon: Icons.close_rounded,
              label: tr(context, 'Закрыть', 'Close'),
              onTap: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            left: safe.left + 16,
            right: safe.right + 16,
            bottom: safe.bottom,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: GlassSurface(
                    radius: 16,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      child: ValueListenableBuilder(
                        valueListenable: _center,
                        builder: (context, _, child) => Text(
                          '${_coordinates.latitude.toStringAsFixed(6)}, ${_coordinates.longitude.toStringAsFixed(6)}',
                          style: TextStyle(color: style.text, fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                GlassActionButton(
                  primary: true,
                  label: tr(context, 'Установить', 'Set'),
                  onTap: () => Navigator.pop(context, _coordinates),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Material(
                    color: style.dark
                        ? const Color(0xd43a3a3a)
                        : const Color(0xd4e2e2e2),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => unawaited(
                        launchUrl(
                          Uri.https('www.openstreetmap.org', '/copyright'),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: Text(
                          '© OpenStreetMap contributors',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: style.text, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
