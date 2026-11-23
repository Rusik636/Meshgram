// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_name.dart';
import '../mesh/nodes.dart';
import 'page_route.dart';
import 'style.dart';

const _tiles = String.fromEnvironment(
  'MESHGRAME_MAP_TILES',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

LatLng meshMapPoint(NodePosition position) => LatLng(
  position.latitude.clamp(-85.05112878, 85.05112878),
  position.longitude,
);

NodePosition meshMapCoordinates(LatLng point) => (
  latitude: point.latitude.clamp(-85.05112878, 85.05112878),
  longitude: (point.longitude + 180) % 360 - 180,
);

String formatMapCoordinates(NodePosition point, {int digits = 5}) =>
    '${point.latitude.toStringAsFixed(digits)}, ${point.longitude.toStringAsFixed(digits)}';

class MeshMapPin {
  const MeshMapPin({required this.position, this.label, this.onTap});

  final NodePosition position;
  final String? label;
  final VoidCallback? onTap;
}

class MeshMap extends StatefulWidget {
  const MeshMap({
    super.key,
    this.center,
    this.zoom,
    this.controller,
    this.interactive = true,
    this.pins = const [],
    this.onCenterChanged,
    this.onMapTap,
    this.showCrosshair = false,
    this.loadTiles = true,
    this.fitPins = false,
    this.showAttribution = true,
  });

  final NodePosition? center;
  final double? zoom;
  final MapController? controller;
  final bool interactive, showCrosshair, loadTiles, fitPins, showAttribution;
  final List<MeshMapPin> pins;
  final ValueChanged<NodePosition>? onCenterChanged, onMapTap;

  @override
  State<MeshMap> createState() => _MeshMapState();
}

class _MeshMapState extends State<MeshMap> {
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

  TileProvider _provider() => widget.loadTiles
      ? NetworkTileProvider(
          headers: {'User-Agent': '$appName (dev.meshgrame.client)'},
          silenceExceptions: true,
          attemptDecodeOfHttpErrorResponses: false,
        )
      : _CachedTileProvider();

  late TileProvider _tileProvider = _provider();

  @override
  void didUpdateWidget(MeshMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadTiles != widget.loadTiles) _tileProvider = _provider();
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final markerLabelHeight =
        MediaQuery.textScalerOf(context).scale(12) * 1.3 + 8;
    var gestures = InteractiveFlag.all & ~InteractiveFlag.rotate;
    if (reduceMotion) {
      gestures &=
          ~(InteractiveFlag.flingAnimation | InteractiveFlag.doubleTapZoom);
    }
    final background = style.dark
        ? const Color(0xff101623)
        : const Color(0xffedf0eb);
    final points = widget.fitPins
        ? widget.pins.map((pin) => meshMapPoint(pin.position)).toSet().toList()
        : const <LatLng>[];
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: widget.controller,
          options: MapOptions(
            initialCenter: widget.center == null
                ? points.firstOrNull ?? const LatLng(25, 25)
                : meshMapPoint(widget.center!),
            initialZoom:
                widget.zoom ??
                (widget.center != null || points.length == 1 ? 15 : 3),
            initialCameraFit: points.length < 2
                ? null
                : CameraFit.coordinates(
                    coordinates: points,
                    maxZoom: 16,
                    padding: const EdgeInsets.fromLTRB(40, 76, 40, 100),
                  ),
            minZoom: 2,
            maxZoom: 19,
            backgroundColor: background,
            interactionOptions: InteractionOptions(
              flags: widget.interactive ? gestures : InteractiveFlag.none,
            ),
            onPositionChanged: (camera, _) =>
                widget.onCenterChanged?.call(meshMapCoordinates(camera.center)),
            onTap: widget.onMapTap == null
                ? null
                : (_, point) => widget.onMapTap!(meshMapCoordinates(point)),
          ),
          children: [
            _MapGrid(color: style.secondary.withValues(alpha: .17)),
            ColorFiltered(
              colorFilter: style.dark
                  ? _darkTiles
                  : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
              child: TileLayer(
                key: ValueKey(widget.loadTiles),
                urlTemplate: _tiles,
                tileProvider: _tileProvider,
                userAgentPackageName: 'dev.meshgrame.client',
                panBuffer: 0,
                tileDisplay: reduceMotion
                    ? const TileDisplay.instantaneous()
                    : const TileDisplay.fadeIn(),
              ),
            ),
            MarkerLayer(
              markers: [
                for (final pin in widget.pins)
                  Marker(
                    point: meshMapPoint(pin.position),
                    width: pin.label == null ? 40 : 162,
                    height: pin.label == null ? 39 : 39 + markerLabelHeight,
                    alignment: Alignment.topCenter,
                    child: _MapMarker(label: pin.label, onTap: pin.onTap),
                  ),
              ],
            ),
          ],
        ),
        if (widget.showCrosshair)
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -19),
                child: const _MapMarker(),
              ),
            ),
          ),
        if (widget.showAttribution)
          const Align(
            alignment: Alignment.bottomCenter,
            child: MeshMapAttribution(),
          ),
      ],
    );
  }
}

class _MapGrid extends StatelessWidget {
  const _MapGrid({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final origin = MapCamera.of(context).pixelOrigin;
    return IgnorePointer(
      child: CustomPaint(
        painter: _MapGridPainter(origin, color),
        size: Size.infinite,
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  const _MapGridPainter(this.origin, this.color);

  final Offset origin;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 32.0;
    final brush = Paint()..color = color;
    for (double x = -origin.dx % step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), brush);
    }
    for (double y = -origin.dy % step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), brush);
    }
  }

  @override
  bool shouldRepaint(_MapGridPainter oldDelegate) =>
      origin != oldDelegate.origin || color != oldDelegate.color;
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({this.label, this.onTap});

  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (label case final name?)
            DecoratedBox(
              decoration: BoxDecoration(
                color: style.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: style.separator),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: style.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          Icon(
            Icons.place_rounded,
            size: 38,
            color: style.accent,
            shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
          ),
        ],
      ),
    );
  }
}

class MeshMapAttribution extends StatelessWidget {
  const MeshMapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return Material(
      color: style.dark ? const Color(0xd43a3a3a) : const Color(0xd4e2e2e2),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(
          launchUrl(Uri.https('www.openstreetmap.org', '/copyright')),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Text(
            '© OpenStreetMap contributors',
            textAlign: TextAlign.center,
            style: TextStyle(color: style.text, fontSize: 10),
          ),
        ),
      ),
    );
  }
}

class MeshLocationPreview extends StatefulWidget {
  const MeshLocationPreview({
    super.key,
    required this.position,
    this.title,
    this.onTap,
    this.loadTiles = true,
  });

  final NodePosition position;
  final String? title;
  final VoidCallback? onTap;
  final bool loadTiles;

  @override
  State<MeshLocationPreview> createState() => _MeshLocationPreviewState();
}

class _MeshLocationPreviewState extends State<MeshLocationPreview> {
  int _refresh = 0;

  Future<void> _openMap() async {
    await openMeshLocation(context, widget.position, title: widget.title);
    if (mounted && !widget.loadTiles) setState(() => _refresh++);
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final label = widget.title ?? tr(context, 'Геопозиция', 'Location');
    return Material(
      color: style.field,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap ?? () => unawaited(_openMap()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 112,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: MeshMap(
                      key: ValueKey((widget.position, _refresh)),
                      center: widget.position,
                      zoom: 15,
                      interactive: false,
                      showCrosshair: true,
                      loadTiles: widget.loadTiles,
                      showAttribution: false,
                    ),
                  ),
                  const Align(
                    alignment: Alignment.bottomRight,
                    child: MeshMapAttribution(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.near_me_outlined, color: style.accent, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: style.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          formatMapCoordinates(widget.position),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: style.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: style.secondary,
                    size: 16,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openMeshLocation(
  BuildContext context,
  NodePosition position, {
  String? title,
  MeshMapPin? pin,
}) => Navigator.of(context).push<void>(
  meshPageRoute(
    context,
    builder: (context) =>
        _LocationMapPage(position: position, title: title, pin: pin),
  ),
);

class _LocationMapPage extends StatelessWidget {
  const _LocationMapPage({required this.position, this.title, this.pin});

  final NodePosition position;
  final String? title;
  final MeshMapPin? pin;

  Future<void> _copy(BuildContext context, String coordinates) async {
    await Clipboard.setData(ClipboardData(text: coordinates));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, 'Скопировано', 'Copied'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final safe = MediaQuery.paddingOf(context);
    final coordinates = formatMapCoordinates(position, digits: 6);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          MeshMap(
            center: position,
            zoom: 15,
            pins: [pin ?? MeshMapPin(position: position)],
            showAttribution: false,
          ),
          Positioned(
            top: safe.top,
            left: safe.left,
            right: safe.right,
            child: PageHeading(
              title ?? tr(context, 'Геопозиция', 'Location'),
              titleBackground: style.pill,
              leading: GlassButton(
                icon: Icons.arrow_back_ios_new_rounded,
                label: tr(context, 'Назад', 'Back'),
                onTap: () => Navigator.pop(context),
              ),
            ),
          ),
          Positioned(
            left: safe.left + 12,
            right: safe.right + 12,
            bottom: safe.bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassSurface(
                  radius: 20,
                  child: Tooltip(
                    message: tr(
                      context,
                      'Скопировать координаты',
                      'Copy coordinates',
                    ),
                    child: InkWell(
                      onTap: () => unawaited(_copy(context, coordinates)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: SizedBox(
                          height: 44,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.copy_rounded,
                                size: 17,
                                color: style.accent,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  coordinates,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: style.text),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Align(
                  alignment: AlignmentDirectional.bottomEnd,
                  child: MeshMapAttribution(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Chat previews may reuse tiles already viewed on a map without making a request.
class _CachedTileProvider extends TileProvider {
  @override
  ImageProvider<_CachedTileImage> getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) => _CachedTileImage(getTileUrl(coordinates, options));
}

@immutable
class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  const _CachedTileImage(this.url);

  final String url;

  static final _transparentPixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==',
  );

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(scale: 1, codec: _load(decode));

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final cache = BuiltInMapCachingProvider.getOrCreateInstance();
      final tile = await cache.getTile(url);
      if (tile != null) {
        return await decode(await ui.ImmutableBuffer.fromUint8List(tile.bytes));
      }
    } on Exception {
      // A missing or corrupt cache entry is represented by the coordinate grid.
    }
    // A later visit can pick up tiles that have been loaded since this miss.
    scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
    return decode(await ui.ImmutableBuffer.fromUint8List(_transparentPixel));
  }

  @override
  bool operator ==(Object other) =>
      other is _CachedTileImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
