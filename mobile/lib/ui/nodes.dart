// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';

import 'package:flutter/material.dart';

import '../mesh/controller.dart';
import '../mesh/network.dart';
import '../mesh/nodes.dart';
import 'chat_management.dart';
import 'mesh_map.dart';
import 'page_route.dart';
import 'style.dart';
import 'swipe_actions.dart';

class MeshNodesPage extends StatefulWidget {
  const MeshNodesPage({
    super.key,
    required this.controller,
    required this.openChat,
    required this.openProfile,
  });

  final MeshController controller;
  final Future<void> Function(Peer) openChat, openProfile;

  @override
  State<MeshNodesPage> createState() => _MeshNodesPageState();
}

class _MeshNodesPageState extends State<MeshNodesPage> {
  MeshController get controller => widget.controller;
  String? _revealed;
  bool _deleting = false;
  final _selected = <String>{};

  void _select(Peer peer) => setState(() {
    _revealed = null;
    if (!_selected.remove(peer.id)) _selected.add(peer.id);
  });

  Future<void> _remove(List<Peer> peers) async {
    if (_deleting) return;
    final active = controller.active;
    if (active == null) return;
    final profile = radioKey(active);
    final removable = peers.where(controller.canRemovePeer).toList();
    if (removable.isEmpty) return;
    setState(() => _revealed = null);
    final confirmed = await confirmChatRemoval(
      context,
      removable.map((peer) => peer.name).toList(),
    );
    if (!mounted ||
        confirmed != true ||
        controller.active == null ||
        radioKey(controller.active!) != profile) {
      return;
    }
    setState(() => _deleting = true);
    var failed = false;
    for (final peer in removable) {
      if (controller.active == null ||
          radioKey(controller.active!) != profile) {
        break;
      }
      try {
        await controller.removePeer(peer);
        _selected.remove(peer.id);
      } catch (_) {
        failed = true;
      }
    }
    if (!mounted) return;
    setState(() => _deleting = false);
    if (failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Не удалось удалить часть записей',
              'Some entries could not be deleted',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _pickSort(BuildContext context) async {
    final sorts = controller.nodeSorts;
    final selected = controller.nodeSort;
    final network = controller.active?.network;
    final style = MeshStyle.of(context);
    final sort = await showMeshSheet<NodeSort>(
      context: context,
      builder: (context) {
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
            if (network != null && sorts.length > 2) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 16, 7),
                child: Text(
                  controller.label(network),
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
    if (sort != null && controller.active?.network == network) {
      await controller.setNodeSort(sort);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final nodes = controller.nodes;
      final editing = _selected.isNotEmpty;
      final style = MeshStyle.of(context);
      final safe = MediaQuery.paddingOf(context);
      final now = DateTime.now();
      final sort = controller.nodeSort;
      return Scaffold(
        body: CustomScrollView(
          slivers: [
            PinnedHeaderSliver(
              child: ColoredBox(
                color: style.canvas,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    safe.left,
                    safe.top,
                    safe.right,
                    4,
                  ),
                  child: PageHeading(
                    editing
                        ? tr(
                            context,
                            'Выбрано ${_selected.length}',
                            'Selected ${_selected.length}',
                          )
                        : tr(context, 'Узлы', 'Nodes'),
                    leading: GlassButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      label: tr(context, 'Назад', 'Back'),
                      onTap: () => editing
                          ? setState(_selected.clear)
                          : Navigator.pop(context),
                    ),
                    sideWidth: editing ? 48 : 104,
                    trailing: editing
                        ? GlassButton(
                            icon: Icons.delete_outline_rounded,
                            label: tr(
                              context,
                              'Удалить выбранные',
                              'Delete selected',
                            ),
                            onTap: _deleting
                                ? null
                                : () => unawaited(
                                    _remove([
                                      for (final peer in nodes)
                                        if (_selected.contains(peer.id)) peer,
                                    ]),
                                  ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GlassButton(
                                icon: Icons.map_outlined,
                                label: tr(context, 'Карта узлов', 'Node map'),
                                onTap: () => unawaited(_openMap(context)),
                              ),
                              const SizedBox(width: 8),
                              GlassButton(
                                icon: Icons.sort_rounded,
                                label: tr(context, 'Сортировка', 'Sort by'),
                                onTap: controller.active == null
                                    ? null
                                    : () => unawaited(_pickSort(context)),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            if (nodes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      controller.connected
                          ? tr(context, 'Пока нет узлов', 'No nodes yet')
                          : tr(
                              context,
                              'Подключите рацию, чтобы найти узлы',
                              'Connect a radio to discover nodes',
                            ),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: style.secondary),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  safe.left,
                  0,
                  safe.right,
                  safe.bottom + 12,
                ),
                sliver: SliverList.separated(
                  itemCount: nodes.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    thickness: .5,
                    indent: 80,
                    color: style.separator,
                  ),
                  itemBuilder: (context, index) {
                    final peer = nodes[index];
                    final lastSeen = controller
                        .nodeObservation(peer.id)
                        ?.lastSeen;
                    final removable = controller.canRemovePeer(peer);
                    final row = _NodeRow(
                      peer: peer,
                      lastSeen: lastSeen?.toLocal(),
                      now: now,
                      subtitle: _subtitle(context, peer, sort),
                      unread: controller.cache?.unread[peer.id] ?? 0,
                      selected: editing ? _selected.contains(peer.id) : null,
                      onLongPress: removable ? () => _select(peer) : null,
                      onTap: () {
                        if (editing) {
                          if (removable) _select(peer);
                        } else {
                          unawaited(widget.openChat(peer));
                        }
                      },
                      onAvatar: () {
                        if (editing) {
                          if (removable) _select(peer);
                        } else {
                          unawaited(widget.openProfile(peer));
                        }
                      },
                    );
                    if (!removable || editing) return row;
                    return SwipeActionsRow(
                      key: ValueKey(peer.id),
                      revealed: _revealed == peer.id,
                      onReveal: (value) =>
                          setState(() => _revealed = value ? peer.id : null),
                      surface: style.surface,
                      background: style.canvas,
                      closedSurface: style.canvas,
                      actions: [
                        deleteSwipeAction(
                          context,
                          () => unawaited(_remove([peer])),
                        ),
                      ],
                      child: row,
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );

  Future<void> _openMap(BuildContext context) => Navigator.of(context)
      .push<void>(
        meshPageRoute(
          context,
          builder: (_) => _NodeMapPage(
            controller: controller,
            openProfile: widget.openProfile,
          ),
        ),
      );

  String? _subtitle(BuildContext context, Peer peer, NodeSort sort) {
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
}

class _NodeMapPage extends StatelessWidget {
  const _NodeMapPage({required this.controller, required this.openProfile});

  final MeshController controller;
  final Future<void> Function(Peer) openProfile;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final style = MeshStyle.of(context);
      final safe = MediaQuery.paddingOf(context);
      final pins = [
        for (final peer in controller.nodes)
          if (controller.nodeObservation(peer.id)?.position
              case final position?)
            MeshMapPin(
              position: position,
              label: peer.name,
              onTap: () => unawaited(openProfile(peer)),
            ),
      ];
      return Scaffold(
        body: Padding(
          padding: EdgeInsets.only(bottom: safe.bottom),
          child: Stack(
            children: [
              Positioned.fill(
                child: MeshMap(
                  key: ValueKey((controller.active, pins.isEmpty)),
                  center: pins.isEmpty ? controller.cache?.localPosition : null,
                  pins: pins,
                  fitPins: true,
                ),
              ),
              Positioned(
                left: safe.left,
                right: safe.right,
                top: safe.top,
                child: PageHeading(
                  tr(context, 'Карта узлов', 'Node map'),
                  titleBackground: style.surface,
                  leading: GlassButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    label: tr(context, 'Назад', 'Back'),
                    onTap: () => Navigator.pop(context),
                  ),
                ),
              ),
              if (pins.isEmpty)
                Positioned(
                  left: safe.left + 16,
                  right: safe.right + 16,
                  bottom: 29,
                  child: GlassSurface(
                    radius: 15,
                    color: style.surface,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        tr(
                          context,
                          'Пока нет узлов с известными координатами',
                          'No nodes with known coordinates yet',
                        ),
                        style: TextStyle(color: style.secondary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.peer,
    required this.lastSeen,
    required this.now,
    required this.subtitle,
    required this.onTap,
    required this.onAvatar,
    required this.onLongPress,
    required this.unread,
    required this.selected,
  });

  final Peer peer;
  final DateTime? lastSeen;
  final DateTime now;
  final String? subtitle;
  final VoidCallback onTap, onAvatar;
  final VoidCallback? onLongPress;
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
