// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';

import '../mesh/nodes.dart';
import 'mesh_map.dart';
import 'page_route.dart';
import 'style.dart';

export 'mesh_map.dart';

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
  late final _center = ValueNotifier(
    widget.initial ?? (latitude: 25.0, longitude: 25.0),
  );

  @override
  void dispose() {
    _center.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final safe = MediaQuery.paddingOf(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          MeshMap(
            center: widget.initial,
            zoom: widget.initial == null ? 3 : 16,
            onCenterChanged: (point) => _center.value = point,
            showCrosshair: true,
            showAttribution: false,
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
            left: 16,
            right: 16,
            bottom: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: safe.left, right: safe.right),
                  child: Column(
                    children: [
                      GlassSurface(
                        radius: 16,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          child: ValueListenableBuilder(
                            valueListenable: _center,
                            builder: (context, position, _) => Text(
                              formatMapCoordinates(position, digits: 6),
                              style: TextStyle(color: style.text, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      GlassActionButton(
                        primary: true,
                        label: tr(context, 'Установить', 'Set'),
                        onTap: () => Navigator.pop(context, _center.value),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: safe.bottom + 8),
                const Center(child: MeshMapAttribution()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
