// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../mesh/controller.dart';
import '../mesh/network.dart';
import 'chat_management.dart';
import 'ios_control.dart';
import 'mesh_map.dart';
import 'message_details.dart';
import 'node_list.dart';
import 'page_route.dart';
import 'search_field.dart';
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

class _MeshNodesPageState extends State<MeshNodesPage>
    with SingleTickerProviderStateMixin {
  static const _headingInset = 14.0;
  static const _headingGap = 8.0;
  static const _headingSlot = meshSearchButtonSize + _headingGap;
  static const _headingFade = 10.0;

  MeshController get controller => widget.controller;
  String? _revealed;
  bool _deleting = false;
  final _selected = <String>{};
  final _scroll = ScrollController();
  final _results = ScrollController();
  final _query = TextEditingController();
  final _searchFocus = FocusNode();
  final _iosSearch = GlobalKey<IosControlState>();
  late final _motion = AnimationController(vsync: this);
  bool _searching = false;

  @override
  void dispose() {
    _motion.dispose();
    _searchFocus.dispose();
    _query.dispose();
    _results.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _openSearch() {
    if (_searching) return;
    setState(() {
      _searching = true;
      _revealed = null;
    });
    animateMeshSearch(context, _motion, open: true);
  }

  void _dismissSearchKeyboard() {
    _searchFocus.unfocus();
    _iosSearch.currentState?.dismissKeyboard();
  }

  void _closeSearch() {
    _dismissSearchKeyboard();
    setState(() => _searching = false);
    animateMeshSearch(context, _motion, open: false);
    if (_query.text.isNotEmpty) _changeQuery('');
  }

  void _changeQuery(String value) {
    if (_query.text != value) _query.text = value;
    if (_results.hasClients && _results.offset != 0) _results.jumpTo(0);
  }

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
    if (_searching) _dismissSearchKeyboard();
    final network = controller.active?.network;
    final sort = await pickNodeSort(
      context,
      sorts: controller.nodeSorts,
      selected: controller.nodeSort,
      networkLabel: network == null ? null : controller.label(network),
    );
    if (sort != null && controller.active?.network == network) {
      await controller.setNodeSort(sort);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_searching,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _searching) _closeSearch();
    },
    child: Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([controller, _query]),
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) => _scene(context, constraints),
          ),
        ),
      ),
    ),
  );

  Widget _scene(BuildContext context, BoxConstraints constraints) {
    final nodes = controller.nodes;
    final editing = _selected.isNotEmpty;
    final safe = MediaQuery.viewPaddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final preferNative = ModalRoute.isCurrentOf(context) != false;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final headingHeight = math.max(
      48.0,
      MediaQuery.textScalerOf(context).scale(18) * 2.6,
    );
    final normalTop = safe.top + headingHeight + 16;
    final fieldHeight = meshSearchFieldHeight(context);
    final collapseRange = fieldHeight + 8;
    final safeBottom = math.max(
      safe.bottom,
      MediaQuery.systemGestureInsetsOf(context).bottom,
    );
    final activeTop = math.max(
      0.0,
      height - math.max(keyboard, safeBottom) - fieldHeight - 8,
    );
    final placeholder = tr(context, 'Поиск узлов', 'Search nodes');
    final query = _query.text.trim().toLowerCase();
    final tastic = controller.active?.network == 'meshtastic';
    final results = query.isEmpty
        ? nodes
        : nodes.where((peer) {
            return peer.name.toLowerCase().contains(query) ||
                peer.id.toLowerCase().contains(query) ||
                (tastic &&
                    (meshtasticNodeAddress(peer.id)?.contains(query) ?? false));
          }).toList();
    final canSearch = !editing && nodes.isNotEmpty;
    final heading = _heading(context, nodes, editing, canSearch || _searching);
    final browse = _nodeList(
      context,
      scroll: _scroll,
      nodes: nodes,
      padding: EdgeInsets.only(
        top: normalTop + (canSearch ? collapseRange : 0),
        bottom: safeBottom + 12,
      ),
      editing: editing,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_motion, _scroll]),
      builder: (context, _) {
        final progress = meshSearchProgress(_motion);
        final offset = _scroll.hasClients ? _scroll.offset : 0.0;
        final collapse = (offset / collapseRange).clamp(0.0, 1.0);
        final active = _searching || progress > 0;
        final compact = !active && collapse == 1;
        final field = meshSearchFieldRect(
          width: width,
          normalTop: normalTop,
          compactTop: safe.top + 7 + (headingHeight - meshSearchButtonSize) / 2,
          activeTop: activeTop,
          fieldHeight: fieldHeight,
          compactRight: _headingInset + 2 * _headingSlot,
          progress: progress,
          collapse: collapse,
        );
        final browseFadeEnd =
            normalTop +
            (canSearch ? collapseRange * (1 - collapse) * (1 - progress) : 0);
        return Stack(
          children: [
            Positioned.fill(
              child: Offstage(
                offstage: progress == 1,
                child: IgnorePointer(
                  ignoring: _searching,
                  child: ExcludeSemantics(
                    excluding: _searching,
                    child: Opacity(
                      opacity: 1 - progress,
                      child: _NodeHeaderFade(
                        hiddenUntil: browseFadeEnd - _headingFade,
                        visibleFrom: browseFadeEnd,
                        child: browse,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (active)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: (height - activeTop + 8).clamp(0.0, height),
                child: IgnorePointer(
                  ignoring: !_searching,
                  child: ExcludeSemantics(
                    excluding: !_searching,
                    child: Opacity(
                      opacity: progress,
                      child: _NodeHeaderFade(
                        hiddenUntil: normalTop - _headingFade,
                        visibleFrom: normalTop,
                        child: _nodeList(
                          context,
                          scroll: _results,
                          nodes: results,
                          padding: EdgeInsets.only(top: normalTop, bottom: 12),
                          editing: false,
                          searching: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              key: const ValueKey('nodes-heading'),
              top: safe.top + 7,
              left: _headingInset,
              right: _headingInset,
              height: headingHeight,
              child: heading,
            ),
            if (canSearch || active)
              Positioned.fromRect(
                key: const ValueKey('nodes-search-field'),
                rect: field,
                child: compact
                    ? GlassButton(
                        icon: Icons.search_rounded,
                        label: placeholder,
                        onTap: _openSearch,
                        preferNative: preferNative,
                      )
                    : _searching && field.width >= 120
                    ? MeshSearchEditor(
                        placeholder: placeholder,
                        controller: _query,
                        focusNode: _searchFocus,
                        iosKey: _iosSearch,
                        initialText: _query.text,
                        onChanged: _changeQuery,
                        onDismissKeyboard: _dismissSearchKeyboard,
                        autofocus: preferNative,
                        preferNative: preferNative,
                      )
                    : MeshSearchLauncher(
                        placeholder: placeholder,
                        collapse: collapse * (1 - progress),
                        onTap: active ? null : _openSearch,
                      ),
              ),
            if (active)
              Positioned(
                top: field.center.dy - meshSearchButtonSize / 2,
                right: lerpDouble(-meshSearchButtonSize, 16, progress),
                child: GlassButton(
                  icon: Icons.close_rounded,
                  label: tr(context, 'Закрыть поиск', 'Close search'),
                  onTap: _searching ? _closeSearch : null,
                  preferNative: preferNative,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _heading(
    BuildContext context,
    List<Peer> nodes,
    bool editing,
    bool reserveSearchSlot,
  ) {
    final preferNative = ModalRoute.isCurrentOf(context) != false;
    return Row(
      children: [
        GlassButton(
          icon: Icons.arrow_back_ios_new_rounded,
          label: tr(context, 'Назад', 'Back'),
          preferNative: preferNative,
          onTap: () {
            if (_searching) {
              _closeSearch();
            } else if (editing) {
              setState(_selected.clear);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        const SizedBox(width: _headingGap),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              editing
                  ? tr(
                      context,
                      'Выбрано ${_selected.length}',
                      'Selected ${_selected.length}',
                    )
                  : tr(context, 'Узлы', 'Nodes'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: MeshStyle.of(context).text,
              ),
            ),
          ),
        ),
        const SizedBox(width: _headingGap),
        if (editing)
          GlassButton(
            icon: Icons.delete_outline_rounded,
            label: tr(context, 'Удалить выбранные', 'Delete selected'),
            onTap: _deleting
                ? null
                : () => unawaited(
                    _remove([
                      for (final peer in nodes)
                        if (_selected.contains(peer.id)) peer,
                    ]),
                  ),
          )
        else ...[
          if (reserveSearchSlot) const SizedBox(width: _headingSlot),
          GlassButton(
            icon: Icons.map_outlined,
            label: tr(context, 'Карта узлов', 'Node map'),
            preferNative: preferNative,
            onTap: () {
              if (_searching) _dismissSearchKeyboard();
              unawaited(_openMap(context));
            },
          ),
          const SizedBox(width: _headingGap),
          GlassButton(
            icon: Icons.sort_rounded,
            label: tr(context, 'Сортировка', 'Sort by'),
            preferNative: preferNative,
            onTap: controller.active == null
                ? null
                : () => unawaited(_pickSort(context)),
          ),
        ],
      ],
    );
  }

  Widget _nodeList(
    BuildContext context, {
    required ScrollController scroll,
    required List<Peer> nodes,
    required EdgeInsets padding,
    required bool editing,
    bool searching = false,
  }) {
    final now = DateTime.now();
    final sort = controller.nodeSort;
    return CustomScrollView(
      controller: scroll,
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: nodes.isEmpty
              ? SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        searching
                            ? tr(
                                context,
                                'Узлы не найдены',
                                'No matching nodes',
                              )
                            : controller.connected
                            ? tr(context, 'Пока нет узлов', 'No nodes yet')
                            : tr(
                                context,
                                'Подключите рацию, чтобы найти узлы',
                                'Connect a radio to discover nodes',
                              ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: MeshStyle.of(context).secondary,
                        ),
                      ),
                    ),
                  ),
                )
              : SliverList.separated(
                  itemCount: nodes.length,
                  separatorBuilder: nodeRowSeparator,
                  itemBuilder: (context, index) {
                    final peer = nodes[index];
                    final lastSeen = controller
                        .nodeObservation(peer.id)
                        ?.lastSeen;
                    final removable = controller.canRemovePeer(peer);
                    void open(Future<void> Function(Peer) action) {
                      if (editing) {
                        if (removable) _select(peer);
                      } else {
                        if (searching) _dismissSearchKeyboard();
                        unawaited(action(peer));
                      }
                    }

                    final row = MeshNodeRow(
                      peer: peer,
                      lastSeen: lastSeen?.toLocal(),
                      now: now,
                      subtitle: nodeSortSubtitle(
                        context,
                        controller,
                        peer,
                        sort,
                      ),
                      unread: controller.cache?.unread[peer.id] ?? 0,
                      selected: editing ? _selected.contains(peer.id) : null,
                      onLongPress: removable && !searching
                          ? () => _select(peer)
                          : null,
                      onTap: () => open(widget.openChat),
                      onAvatar: () => open(widget.openProfile),
                    );
                    if (!removable || editing || searching) return row;
                    final style = MeshStyle.of(context);
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
    );
  }

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
}

class _NodeHeaderFade extends StatelessWidget {
  const _NodeHeaderFade({
    required this.hiddenUntil,
    required this.visibleFrom,
    required this.child,
  });

  final double hiddenUntil, visibleFrom;
  final Widget child;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) {
      final height = math.max(1.0, bounds.height);
      final start = (hiddenUntil / height).clamp(0.0, 1.0);
      final end = (visibleFrom / height).clamp(start, 1.0);
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Colors.transparent,
          Colors.transparent,
          Color(0x66ffffff),
          Colors.white,
        ],
        stops: [0, start, (start + end) / 2, end],
      ).createShader(bounds);
    },
    child: child,
  );
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
            MeshMapPin.node(
              position: position,
              id: peer.id,
              name: peer.name,
              online: controller.isNodeOnline(peer.id),
              onTap: () => unawaited(openProfile(peer)),
            ),
      ];
      return Scaffold(
        body: Stack(
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
                bottom: safe.bottom + 29,
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
      );
    },
  );
}
