// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';

import '../mesh/controller.dart';
import '../mesh/network.dart';
import '../mesh/nodes.dart';
import 'style.dart';

Future<NodeSort?> pickNodeSort(
  BuildContext context, {
  required List<NodeSort> sorts,
  required NodeSort selected,
  String? networkLabel,
}) => showMeshSheet<NodeSort>(
  context: context,
  builder: (context) {
    final style = MeshStyle.of(context);
    Widget option(NodeSort sort) => MeshRow(
      title: _sortLabel(context, sort),
      icon: _sortIcon(sort),
      tint: style.accent,
      selected: selected == sort,
      showChevron: false,
      onTap: () => Navigator.pop(context, sort),
    );
    return SheetBody(
      title: tr(context, 'Сортировка', 'Sort by'),
      children: [
        MeshGroup(children: sorts.take(2).map(option).toList()),
        if (networkLabel != null && sorts.length > 2) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 7),
            child: Text(
              networkLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: style.secondary,
              ),
            ),
          ),
          MeshGroup(children: sorts.skip(2).map(option).toList()),
        ],
      ],
    );
  },
);

Widget nodeRowSeparator(BuildContext context, int _) => Divider(
  height: 1,
  thickness: .5,
  indent: 80,
  color: MeshStyle.of(context).separator,
);

String? nodeSortSubtitle(
  BuildContext context,
  MeshController controller,
  Peer peer,
  NodeSort sort,
) {
  final observation = controller.nodeObservation(peer.id);
  switch (sort) {
    case NodeSort.distance:
      if (controller.nodeDistanceMeters(peer.id) case final meters?) {
        final format = MaterialLocalizations.of(context);
        if (meters < 1000) {
          return '${format.formatDecimal(meters.round())} ${tr(context, 'м', 'm')}';
        }
        final km = (meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0);
        return tr(context, "${km.replaceFirst('.', ',')} км", '$km km');
      }
    case NodeSort.hops:
      if (observation?.hops case final hops?) {
        return hops == 0
            ? tr(context, 'Напрямую', 'Direct')
            : tr(context, 'Ретрансляций · $hops', 'Hops · $hops');
      }
    case NodeSort.channel:
      if (observation?.channel case final channel?) {
        return controller.cache?.peers['ch:$channel']?.name ??
            tr(context, 'Канал $channel', 'Channel $channel');
      }
    case NodeSort.mqtt:
      if (observation?.viaMqtt case final viaMqtt?) {
        return viaMqtt ? 'MQTT' : 'LoRa';
      }
    case NodeSort.favorite:
      if (observation?.favorite == true) {
        return tr(context, 'В избранном', 'Favorite');
      }
    case NodeSort.activity:
    case NodeSort.name:
    case NodeSort.messages:
      break;
  }
  return switch (controller.cache?.identities[peer.id]?.type) {
    2 => tr(context, 'Ретранслятор', 'Repeater'),
    3 => tr(context, 'Комната', 'Room'),
    4 => tr(context, 'Датчик', 'Sensor'),
    _ => null,
  };
}

class MeshNodeRow extends StatelessWidget {
  const MeshNodeRow({
    super.key,
    required this.peer,
    required this.lastSeen,
    required this.now,
    required this.subtitle,
    required this.onTap,
    this.onAvatar,
    this.onLongPress,
    this.unread = 0,
    this.selected,
  });

  final Peer peer;
  final DateTime? lastSeen;
  final DateTime now;
  final String? subtitle;
  final VoidCallback? onTap, onAvatar, onLongPress;
  final int unread;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final localizations = MaterialLocalizations.of(context);
    final last = lastSeen;
    final stamp = last == null
        ? '—'
        : DateUtils.isSameDay(last, now)
        ? localizations.formatTimeOfDay(
            TimeOfDay.fromDateTime(last),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          )
        : localizations.formatShortDate(last);
    return InkWell(
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 17, 8),
        child: Row(
          children: [
            if (selected case final checked?)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  checked
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: checked ? style.accent : style.secondary,
                ),
              ),
            MeshAvatar(
              peer.name,
              size: 52,
              online: nodeIsOnline(last, now),
              onTap: onAvatar,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: style.text,
                    ),
                  ),
                  if (subtitle case final detail?) ...[
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: style.secondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (unread > 0)
              MeshUnreadBadge(unread)
            else
              Text(
                stamp,
                semanticsLabel: last == null
                    ? tr(
                        context,
                        'Время обнаружения неизвестно',
                        'Detection time unavailable',
                      )
                    : tr(
                        context,
                        'Последняя активность $stamp',
                        'Last active $stamp',
                      ),
                style: TextStyle(fontSize: 12, color: style.secondary),
              ),
          ],
        ),
      ),
    );
  }
}

String _sortLabel(BuildContext context, NodeSort sort) => switch (sort) {
  NodeSort.activity => tr(context, 'По активности', 'Last heard'),
  NodeSort.name => tr(context, 'По имени', 'Name'),
  NodeSort.messages => tr(context, 'По последней переписке', 'Recent messages'),
  NodeSort.distance => tr(context, 'По расстоянию', 'Distance'),
  NodeSort.hops => tr(context, 'По числу ретрансляций', 'Hops away'),
  NodeSort.channel => tr(context, 'По каналу', 'Channel'),
  NodeSort.mqtt => tr(context, 'Сначала LoRa, затем MQTT', 'LoRa before MQTT'),
  NodeSort.favorite => tr(context, 'Сначала избранные', 'Favorites first'),
};

IconData _sortIcon(NodeSort sort) => switch (sort) {
  NodeSort.activity => Icons.schedule_rounded,
  NodeSort.name => Icons.sort_by_alpha_rounded,
  NodeSort.messages => Icons.chat_bubble_outline_rounded,
  NodeSort.distance => Icons.near_me_outlined,
  NodeSort.hops => Icons.route_rounded,
  NodeSort.channel => Icons.tag_rounded,
  NodeSort.mqtt => Icons.swap_vert_rounded,
  NodeSort.favorite => Icons.star_outline_rounded,
};
