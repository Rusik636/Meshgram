// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FragmentProgram, FragmentShader, ImageFilter, lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../mesh/controller.dart';
import '../mesh/network.dart';
import '../mesh/nodes.dart';
import 'ios_control.dart';
import 'node_list.dart';
import 'search_field.dart';
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
    required this.onToggleExpand,
    required this.onSelect,
    required this.beginSheetDrag,
    this.bottomObstruction = 0,
  });

  final List<ShareableNode> contacts;
  final MeshController? controller;
  final TextEditingController search;
  final bool expanded;
  final VoidCallback onClose, onToggleExpand;
  final ValueChanged<String> onSelect;
  final Drag? Function() beginSheetDrag;
  final double bottomObstruction;

  @override
  State<AttachmentContacts> createState() => _AttachmentContactsState();
}

class _AttachmentContactsState extends State<AttachmentContacts>
    with SingleTickerProviderStateMixin {
  late final _scroll = _AttachmentContactScrollController(
    () => widget.beginSheetDrag(),
  );
  final _focus = FocusNode();
  var _iosSearch = GlobalKey<IosControlState>();
  late bool _searching = widget.search.text.isNotEmpty;
  late final _motion = AnimationController(
    vsync: this,
    value: _searching ? 1 : 0,
  );
  late String _initialQuery = widget.search.text;
  bool _autofocus = false;
  NodeSort _defaultSort = NodeSort.activity;

  @override
  void didUpdateWidget(AttachmentContacts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded != widget.expanded) _dismissKeyboard();
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
    setState(() {
      _searching = true;
      _initialQuery = widget.search.text;
      _autofocus = true;
      _iosSearch = GlobalKey();
    });
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
    animateMeshSearch(context, _motion, open: false);
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
    ScrollController? scroll,
    PageStorageKey<String>? key,
  }) {
    final controller = widget.controller;
    final sort = controller?.nodeSort;
    final now = DateTime.now();
    return CustomScrollView(
      key: key,
      controller: scroll,
      physics: scroll == null ? null : const AlwaysScrollableScrollPhysics(),
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
    const headingTop = 7.0;
    const compactRight = side + (meshSearchButtonSize + gap) * 2;
    final headingHeight =
        math.max(
          meshSearchButtonSize,
          MediaQuery.textScalerOf(context).scale(18) * 1.2,
        ) +
        16;
    final fieldHeight = meshSearchFieldHeight(context);
    final normalFieldTop = headingHeight + 3;
    final collapseRange = fieldHeight + 9;
    final normalHeaderHeight = normalFieldTop + collapseRange;
    final fieldCompactTop =
        headingTop + (headingHeight - 16 - meshSearchButtonSize) / 2;
    final session = _iosSearch;
    return AnimatedBuilder(
      animation: Listenable.merge([_motion, _scroll]),
      builder: (context, _) {
        final progress = meshSearchProgress(_motion);
        final scroll = _scroll.hasClients ? _scroll.position : null;
        final collapse =
            scroll != null &&
                scroll.hasContentDimensions &&
                scroll.maxScrollExtent > 0
            ? (scroll.pixels / collapseRange).clamp(0.0, 1.0)
            : 0.0;
        final field = meshSearchFieldRect(
          width: constraints.maxWidth,
          normalTop: normalFieldTop,
          compactTop: fieldCompactTop,
          activeTop: headingTop,
          fieldHeight: fieldHeight,
          compactRight: compactRight,
          progress: progress,
          collapse: collapse,
        );
        final listTop = field.top + fieldHeight + 9;
        final launchButton = !_searching && collapse == 1 && progress == 0;
        final scrollFade = Curves.easeOut.transform(
          (collapse * 3).clamp(0.0, 1.0),
        );
        final topEdge = lerpDouble(
          lerpDouble(
            18,
            normalHeaderHeight - collapseRange * collapse,
            scrollFade,
          )!,
          listTop,
          progress,
        )!;
        final bottomEdge = (widget.bottomObstruction * .7).clamp(38.0, 92.0);
        final bottom = math.max(bottomEdge, widget.bottomObstruction);
        return Stack(
          children: [
            Positioned.fill(
              child: _ContactScrollEdges(
                key: const ValueKey('attachment-contact-scroll-edges'),
                top: topEdge,
                bottom: bottomEdge,
                height: constraints.maxHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Offstage(
                      offstage: progress == 1,
                      child: IgnorePointer(
                        ignoring: _searching,
                        child: ExcludeSemantics(
                          excluding: _searching,
                          child: Opacity(
                            opacity: 1 - progress,
                            child: _list(
                              context,
                              key: const PageStorageKey('attachment-contacts'),
                              scroll: _scroll,
                              contacts: contacts,
                              top: normalHeaderHeight,
                              bottom: bottom,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_searching || progress > 0)
                      IgnorePointer(
                        ignoring: !_searching,
                        child: ExcludeSemantics(
                          excluding: !_searching,
                          child: Opacity(
                            opacity: progress,
                            child: _list(
                              context,
                              contacts: results,
                              top: math.min(listTop, constraints.maxHeight),
                              bottom: bottom,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (progress < 1)
              Positioned(
                left: side,
                right: side,
                top: lerpDouble(0, -headingHeight, progress),
                height: headingHeight,
                child: IgnorePointer(
                  ignoring: _searching,
                  child: ExcludeSemantics(
                    excluding: _searching,
                    child: Row(
                      children: [
                        GlassButton(
                          icon: Icons.close_rounded,
                          label: tr(context, 'Закрыть', 'Close'),
                          onTap: widget.onClose,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
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
                        SizedBox(
                          width: (meshSearchButtonSize + gap) * collapse,
                        ),
                        GlassButton(
                          icon: Icons.sort_rounded,
                          label: tr(context, 'Сортировка', 'Sort by'),
                          onTap: contacts.isEmpty
                              ? null
                              : () => unawaited(_sortContacts()),
                        ),
                        const SizedBox(width: gap),
                        GlassButton(
                          icon: widget.expanded
                              ? Icons.close_fullscreen_rounded
                              : Icons.open_in_full_rounded,
                          label: widget.expanded
                              ? tr(context, 'Свернуть', 'Collapse')
                              : tr(context, 'На весь экран', 'Expand'),
                          onTap: widget.onToggleExpand,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned.fromRect(
              rect: field,
              child: launchButton
                  ? GlassButton(
                      icon: Icons.search_rounded,
                      label: placeholder,
                      onTap: _startSearch,
                    )
                  : _searching && field.width >= 128
                  ? MeshSearchEditor(
                      placeholder: placeholder,
                      controller: widget.search,
                      focusNode: _focus,
                      iosKey: session,
                      autofocus: _autofocus,
                      initialText: _initialQuery,
                      onChanged: (value) {
                        if (_searching &&
                            _iosSearch == session &&
                            widget.search.text != value) {
                          widget.search.text = value;
                        }
                      },
                      onDismissKeyboard: _dismissKeyboard,
                    )
                  : MeshSearchLauncher(
                      placeholder: placeholder,
                      onTap: _startSearch,
                      collapse: collapse * (1 - progress),
                    ),
            ),
            if (_searching || progress > 0)
              Positioned(
                top: field.top + (fieldHeight - meshSearchButtonSize) / 2,
                right: lerpDouble(-meshSearchButtonSize, side, progress),
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

class _ContactScrollEdges extends StatefulWidget {
  const _ContactScrollEdges({
    super.key,
    required this.top,
    required this.bottom,
    required this.height,
    required this.child,
  });

  final double top, bottom, height;
  final Widget child;

  @override
  State<_ContactScrollEdges> createState() => _ContactScrollEdgesState();
}

class _ContactScrollEdgesState extends State<_ContactScrollEdges> {
  static Future<FragmentProgram>? _program;
  final _content = GlobalKey();
  FragmentProgram? _loadedProgram;
  FragmentShader? _shader;
  (double, double)? _extents;

  @override
  void initState() {
    super.initState();
    if (ImageFilter.isShaderFilterSupported) unawaited(_loadShader());
  }

  Future<void> _loadShader() async {
    try {
      final program = await (_program ??= FragmentProgram.fromAsset(
        'shaders/contact_scroll_edges.frag',
      ));
      if (mounted) setState(() => _loadedProgram = program);
    } catch (_) {
      // A transparent alpha ramp is also available without a shader filter.
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(key: _content, child: widget.child);
    if (widget.height <= 0) return child;
    final extent = math.max(widget.height, widget.top + widget.bottom);
    final top = widget.top / extent;
    final bottom = widget.bottom / extent;
    final program = _loadedProgram;
    if (program != null && !MediaQuery.highContrastOf(context)) {
      if (_extents != (top, bottom)) {
        _shader?.dispose();
        _shader = program.fragmentShader()
          ..setFloat(2, top)
          ..setFloat(3, bottom);
        _extents = (top, bottom);
      }
      return ImageFiltered(
        imageFilter: ImageFilter.shader(_shader!),
        child: child,
      );
    }
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Colors.transparent,
          Colors.transparent,
          Color(0x40ffffff),
          Color(0xbfffffff),
          Colors.white,
          Colors.white,
          Color(0xbfffffff),
          Color(0x40ffffff),
          Colors.transparent,
        ],
        stops: [
          0,
          .45 * top,
          .63 * top,
          .82 * top,
          top,
          1 - bottom,
          1 - .67 * bottom,
          1 - .33 * bottom,
          1,
        ],
      ).createShader(bounds),
      child: child,
    );
  }
}

class _AttachmentContactScrollController extends ScrollController {
  _AttachmentContactScrollController(this.beginSheetDrag);

  final Drag? Function() beginSheetDrag;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _AttachmentContactScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    beginSheetDrag: beginSheetDrag,
  );
}

class _AttachmentContactScrollPosition extends ScrollPositionWithSingleContext {
  _AttachmentContactScrollPosition({
    required super.physics,
    required super.context,
    required super.oldPosition,
    required this.beginSheetDrag,
  });

  final Drag? Function() beginSheetDrag;

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) =>
      _ContactDrag(
        super.drag(details, dragCancelCallback),
        () => pixels <= minScrollExtent + 1 ? beginSheetDrag() : null,
      );
}

class _ContactDrag extends Drag {
  _ContactDrag(this._scroll, this._beginSheetDrag);

  final Drag _scroll;
  final Drag? Function() _beginSheetDrag;
  Drag? _sheet;

  @override
  void update(DragUpdateDetails details) {
    if (details.delta.dy > 0) _sheet ??= _beginSheetDrag();
    (_sheet ?? _scroll).update(details);
  }

  @override
  void end(DragEndDetails details) {
    if (_sheet case final sheet?) {
      _scroll.cancel();
      sheet.end(details);
    } else {
      _scroll.end(details);
    }
  }

  @override
  void cancel() {
    _scroll.cancel();
    _sheet?.cancel();
  }
}
