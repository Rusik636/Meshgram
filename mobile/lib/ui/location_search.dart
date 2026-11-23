// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';

import '../mesh/chat_position.dart';
import '../mesh/nodes.dart';
import 'mesh_icon.dart';
import 'mesh_map.dart';
import 'style.dart';

typedef AttachmentLocationNode = ({String name, NodePosition position});

Future<NodePosition?> openAttachmentLocationSearch(
  BuildContext context, {
  required List<AttachmentLocationNode> nodes,
}) => showDialog<NodePosition>(
  context: context,
  builder: (_) => _AttachmentLocationSearch(nodes: nodes),
);

class _AttachmentLocationSearch extends StatefulWidget {
  const _AttachmentLocationSearch({required this.nodes});

  final List<AttachmentLocationNode> nodes;

  @override
  State<_AttachmentLocationSearch> createState() =>
      _AttachmentLocationSearchState();
}

class _AttachmentLocationSearchState extends State<_AttachmentLocationSearch> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final coordinates = chatPosition(_query)?.point;
    final query = _query.toLowerCase();
    final visible = widget.nodes
        .where((node) => node.name.toLowerCase().contains(query))
        .toList();
    return Dialog(
      backgroundColor: style.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SizedBox(
        height: 400,
        width: 460,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      onChanged: (value) =>
                          setState(() => _query = value.trim()),
                      onSubmitted: (_) {
                        final point =
                            coordinates ??
                            (visible.length == 1
                                ? visible.first.position
                                : null);
                        if (point != null) Navigator.pop(context, point);
                      },
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: tr(
                          context,
                          'Узел или координаты',
                          'Node or coordinates',
                        ),
                        prefixIcon: const MeshIcon(Icons.search_rounded),
                        filled: true,
                        fillColor: style.field,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr(context, 'Закрыть поиск', 'Close search'),
                    onPressed: () => Navigator.pop(context),
                    icon: const MeshIcon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: coordinates == null && visible.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _query.isEmpty
                              ? tr(
                                  context,
                                  'Введите координаты',
                                  'Enter coordinates',
                                )
                              : tr(
                                  context,
                                  'Точка не найдена',
                                  'No matching locations',
                                ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: style.secondary),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      children: [
                        if (coordinates != null)
                          ListTile(
                            leading: MeshIcon(
                              Icons.place_rounded,
                              color: style.accent,
                            ),
                            title: Text(
                              tr(context, 'Координаты', 'Coordinates'),
                            ),
                            subtitle: Text(formatMapCoordinates(coordinates)),
                            onTap: () => Navigator.pop(context, coordinates),
                          ),
                        for (final node in visible)
                          ListTile(
                            leading: MeshAvatar(node.name, size: 36),
                            title: Text(
                              node.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(formatMapCoordinates(node.position)),
                            onTap: () => Navigator.pop(context, node.position),
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
