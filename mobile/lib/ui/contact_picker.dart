// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../mesh/controller.dart';
import '../mesh/network.dart';
import '../mesh/nodes.dart';
import 'ios_control.dart';
import 'mesh_scroll_edge.dart';
import 'node_list.dart';
import 'search_field.dart';
import 'sheet_scroll.dart';
import 'style.dart';

typedef ShareableNode = ({Peer peer, String? link});

class AttachmentContacts extends StatefulWidget {
  const AttachmentContacts({
    super.key,
    required this.contacts,
    required this.controller,
    required this.search,
    required this.expanded,
    required this.onClose,
    required this.onSearchChanged,
    required this.onSelect,
    required this.beginSheetDrag,
    this.bottomObstruction = 0,
  });

  final List<ShareableNode> contacts;
  final MeshController? controller;
  final TextEditingController search;
  final bool expanded;
  final VoidCallback onClose;
  final ValueChanged<bool> onSearchChanged;
  final ValueChanged<String> onSelect;
  final Drag? Function() beginSheetDrag;
  final double bottomObstruction;

  @override
  State<AttachmentContacts> createState() => _AttachmentContactsState();
}

class _AttachmentContactsState extends State<AttachmentContacts>
    with SingleTickerProviderStateMixin {
  late final _scroll = MeshSheetScrollController(
    () => widget.beginSheetDrag(),
    transferRemainder: Theme.of(context).platform == TargetPlatform.iOS,
  );
  final _focus = FocusNode();
  final _iosSearch = GlobalKey<IosControlState>();
  late bool _searching = widget.search.text.isNotEmpty;
  late final _motion = AnimationController(
    vsync: this,
    value: _searching ? 1 : 0,
  );
  double _browseOffset = 0;
  NodeSort _defaultSort = NodeSort.activity;

  @override
  void didUpdateWidget(AttachmentContacts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_searching && oldWidget.expanded != widget.expanded) {
      _dismissKeyboard();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startSearch() {
    if (_searching) return;
    _browseOffset = _scroll.hasClients ? _scroll.offset : 0;
    setState(() => _searching = true);
    widget.onSearchChanged(true);
    animateMeshSearch(context, _motion, open: true);
  }

  void _dismissKeyboard() {
    _focus.unfocus();
    _iosSearch.currentState?.dismissKeyboard();
  }

  void _closeSearch() {
    _dismissKeyboard();
    setState(() {
      _searching = false;
      widget.search.clear();
    });
    widget.onSearchChanged(false);
    animateMeshSearch(context, _motion, open: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _searching || !_scroll.hasClients) return;
      final position = _scroll.position;
      _scroll.jumpTo(_browseOffset.clamp(0.0, position.maxScrollExtent));
    });
  }

  void _changeQuery(String value) {
    if (!_searching) return;
    if (widget.search.text != value) widget.search.text = value;
    if (_scroll.hasClients && _scroll.offset != 0) _scroll.jumpTo(0);
  }

  Future<void> _sortContacts() async {
    final controller = widget.controller;
    final network = controller?.active?.network;
    final selected = await pickNodeSort(
      context,
      sorts: controller?.nodeSorts ?? [NodeSort.activity, NodeSort.name],
      selected: controller?.nodeSort ?? _defaultSort,
      networkLabel: network == null ? null : controller?.label(network),
    );
    if (!mounted || selected == null) return;
    if (controller == null) {
      setState(() => _defaultSort = selected);
    } else if (controller.active?.network == network) {
      await controller.setNodeSort(selected);
    }
  }

  List<ShareableNode> _orderedContacts(MeshController? controller) {
    final contactsById = {
      for (final contact in widget.contacts) contact.peer.id: contact,
    };
    if (controller != null) {
      final ordered = [
        for (final peer in controller.nodes) ?contactsById.remove(peer.id),
        ...contactsById.values,
      ];
      return ordered;
    }
    final ordered = widget.contacts.toList();
    if (_defaultSort == NodeSort.name) {
      ordered.sort(
        (a, b) =>
            a.peer.name.toLowerCase().compareTo(b.peer.name.toLowerCase()),
      );
    }
    return ordered;
  }

  Widget _list(
    BuildContext context, {
    required List<ShareableNode> contacts,
    required double top,
    required double bottom,
  }) {
    final controller = widget.controller;
    final sort = controller?.nodeSort;
    final now = DateTime.now();
    return CustomScrollView(
      key: const PageStorageKey('attachment-contacts'),
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: top)),
        if (contacts.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
                child: Text(
                  widget.contacts.isEmpty
                      ? tr(context, 'Пока нет узлов', 'No nodes yet')
                      : tr(context, 'Узлы не найдены', 'No matching nodes'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MeshStyle.of(context).secondary),
                ),
              ),
            ),
          )
        else ...[
          SliverList.separated(
            itemCount: contacts.length,
            separatorBuilder: nodeRowSeparator,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              final peer = contact.peer;
              final link = contact.link;
              return MeshNodeRow(
                peer: peer,
                lastSeen: controller
                    ?.nodeObservation(peer.id)
                    ?.lastSeen
                    ?.toLocal(),
                now: now,
                subtitle: link == null
                    ? tr(
                        context,
                        'Ссылка недоступна',
                        'Contact link unavailable',
                      )
                    : controller != null && sort != null
                    ? nodeSortSubtitle(context, controller, peer, sort)
                    : null,
                unread: controller?.cache?.unread[peer.id] ?? 0,
                onTap: link == null
                    ? null
                    : () {
                        _dismissKeyboard();
                        widget.onSelect(link);
                      },
              );
            },
          ),
          SliverToBoxAdapter(child: SizedBox(height: bottom)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_searching,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _searching) _closeSearch();
    },
    child: ListenableBuilder(
      listenable: Listenable.merge([widget.controller, widget.search]),
      builder: (context, _) {
        final ordered = _orderedContacts(widget.controller);
        final query = widget.search.text.trim().toLowerCase();
        final results = query.isEmpty
            ? ordered
            : ordered.where((contact) {
                final peer = contact.peer;
                return peer.name.toLowerCase().contains(query) ||
                    peer.id.toLowerCase().contains(query);
              }).toList();
        return LayoutBuilder(
          builder: (context, constraints) =>
              _layout(context, constraints, ordered, results),
        );
      },
    ),
  );

  Widget _layout(
    BuildContext context,
    BoxConstraints constraints,
    List<ShareableNode> contacts,
    List<ShareableNode> results,
  ) {
    final title = tr(context, 'Контакты', 'Contacts');
    final placeholder = tr(context, 'Поиск узлов', 'Search nodes');
    const side = 16.0;
    const gap = 6.0;
    const headingTop = 11.0;
    const searchBottomGap = 8.0;
    final headingHeight =
        math.max(
          meshSearchButtonSize,
          MediaQuery.textScalerOf(context).scale(18) * 1.2,
        ) +
        16;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final fieldHeight = meshSearchFieldHeight(context);
    final searchBottom = MediaQuery.paddingOf(context).bottom + searchBottomGap;
    final surface = MeshStyle.of(context).surface;
    final compact = Rect.fromLTWH(
      width - side - meshSearchButtonSize,
      headingTop + (headingHeight - 16 - meshSearchButtonSize) / 2,
      meshSearchButtonSize,
      meshSearchButtonSize,
    );
    final active = Rect.fromLTWH(
      side,
      math.max(0, height - fieldHeight - searchBottom),
      math.max(
        meshSearchButtonSize,
        width - 2 * side - gap - meshSearchButtonSize,
      ),
      fieldHeight,
    );
    return AnimatedBuilder(
      animation: _motion,
      builder: (context, _) {
        final progress = meshSearchProgress(_motion);
        final obstruction = math.max(
          widget.bottomObstruction,
          (searchBottom + fieldHeight + gap) * progress,
        );
        final bottomEdge = math.max(38.0, obstruction);
        final field = Rect.lerp(compact, active, progress)!;
        final list = _list(
          context,
          contacts: _searching ? results : contacts,
          top: headingHeight,
          bottom: math.max(obstruction, bottomEdge),
        );
        return Stack(
          children: [
            Positioned.fill(child: list),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: math.min(height, headingHeight + 12),
              child: MeshScrollEdge(top: true, tint: surface, opaqueEdge: true),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: math.min(height, bottomEdge),
              child: MeshScrollEdge(top: false, tint: surface),
            ),
            Positioned(
              top: 4,
              left: side + meshSearchButtonSize + 12,
              right: lerpDouble(
                side + 2 * meshSearchButtonSize + 2 * gap,
                side + meshSearchButtonSize + 12,
                progress,
              ),
              height: headingHeight,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.lerp(
                    Alignment.centerLeft,
                    Alignment.center,
                    progress,
                  )!,
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: side,
              right: side,
              top: 4,
              height: headingHeight,
              child: Row(
                children: [
                  GlassButton(
                    icon: Icons.close_rounded,
                    label: tr(context, 'Закрыть', 'Close'),
                    onTap: widget.onClose,
                  ),
                  const Spacer(),
                  if (progress < 1)
                    IgnorePointer(
                      ignoring: _searching,
                      child: ExcludeSemantics(
                        excluding: _searching,
                        child: Opacity(
                          opacity: 1 - progress,
                          child: GlassButton(
                            icon: Icons.sort_rounded,
                            label: tr(context, 'Сортировка', 'Sort by'),
                            onTap: contacts.isEmpty
                                ? null
                                : () => unawaited(_sortContacts()),
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: meshSearchButtonSize),
                  const SizedBox(width: meshSearchButtonSize + gap),
                ],
              ),
            ),
            Positioned.fromRect(
              rect: field,
              child: MeshSearchEditor(
                key: const ValueKey('attachment-contact-search-control'),
                placeholder: placeholder,
                controller: widget.search,
                focusNode: _focus,
                iosKey: _iosSearch,
                initialText: widget.search.text,
                active: _searching,
                progress: progress,
                onActivate: _startSearch,
                onChanged: _changeQuery,
                onDismissKeyboard: _dismissKeyboard,
              ),
            ),
            if (_searching || progress > 0)
              Positioned(
                top: field.center.dy - meshSearchButtonSize / 2,
                left: lerpDouble(
                  width,
                  width - side - meshSearchButtonSize,
                  progress,
                ),
                child: GlassButton(
                  icon: Icons.close_rounded,
                  label: tr(context, 'Закрыть поиск', 'Close search'),
                  onTap: _searching ? _closeSearch : null,
                ),
              ),
          ],
        );
      },
    );
  }
}
