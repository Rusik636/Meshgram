// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import 'haptics.dart';
import 'ios_control.dart';
import 'style.dart';

Color _tabSelection(MeshStyle style) =>
    style.dark ? const Color(0xff373c48) : const Color(0xffe1e5ec);

class MeshNavigation extends StatelessWidget {
  const MeshNavigation({
    super.key,
    required this.index,
    required this.unread,
    this.settingsUnread = 0,
    required this.onSelect,
  });
  final int index, unread, settingsUnread;
  final ValueChanged<int> onSelect;

  static const chatIcon = Icons.chat_bubble_outline_rounded;

  static Widget activeChatIcon(Color color, double size) => useIosControls
      ? Center(
          child: SizedBox.square(
            dimension: size,
            child: IosControl(
              kind: 'chatIcon',
              properties: {'accent': color.toARGB32()},
            ),
          ),
        )
      : Icon(chatIcon, color: color, size: size);

  static double contentHeight(BuildContext context) =>
      (60 + (MediaQuery.textScalerOf(context).scale(12) - 12))
          .clamp(60, 84)
          .toDouble();

  static double bottomContentInset(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    if (Theme.of(context).platform != TargetPlatform.android) {
      return safeBottom + 5;
    }
    return math.max(
          safeBottom,
          MediaQuery.systemGestureInsetsOf(context).bottom,
        ) +
        14;
  }

  @override
  Widget build(BuildContext context) => MeshTabBar(
    labels: [
      tr(context, 'Чаты', 'Chats'),
      tr(context, 'Настройки', 'Settings'),
    ],
    icons: const [chatIcon, Icons.settings_outlined],
    symbols: const ['bubble.left', 'gearshape'],
    index: index,
    onSelect: onSelect,
    unreadCounts: [unread, settingsUnread],
  );
}

/// Shared bottom navigation for the app and its compact attachment sheet.
class MeshTabBar extends StatelessWidget {
  const MeshTabBar({
    super.key,
    required this.labels,
    required this.icons,
    required this.symbols,
    required this.index,
    required this.onSelect,
    this.unreadCounts = const [],
  }) : assert(labels.length == icons.length),
       assert(labels.length == symbols.length);

  final List<String> labels, symbols;
  final List<IconData> icons;
  final int index;
  final ValueChanged<int> onSelect;
  final List<int> unreadCounts;

  static double bottomOffset(BuildContext context) =>
      MeshNavigation.bottomContentInset(context);

  static double heightOf(BuildContext context) =>
      MeshNavigation.contentHeight(context);

  @override
  Widget build(BuildContext context) {
    void select(int next) {
      if (next != index) unawaited(playMeshHaptic(MeshHaptic.selection));
      onSelect(next);
    }

    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 208),
        child: _FlutterTabs(
          labels: labels,
          icons: icons,
          symbols: symbols,
          height: heightOf(context),
          index: index,
          unreadCounts: unreadCounts,
          onSelect: select,
        ),
      ),
    );
  }
}

class _FlutterTabs extends StatefulWidget {
  const _FlutterTabs({
    required this.labels,
    required this.height,
    required this.index,
    this.icons = const [],
    this.symbols = const [],
    this.unreadCounts = const [],
    this.textOnly = false,
    required this.onSelect,
  });

  final List<String> labels, symbols;
  final List<IconData> icons;
  final List<int> unreadCounts;
  final double height;
  final int index;
  final bool textOnly;
  final ValueChanged<int> onSelect;

  @override
  State<_FlutterTabs> createState() => _FlutterTabsState();
}

class _FlutterTabsState extends State<_FlutterTabs> {
  double? _dragIndex;
  var _startX = 0.0;
  var _startIndex = 0;

  void _endDrag({required bool select}) {
    final drag = _dragIndex;
    if (drag == null) return;
    final target = drag.round();
    setState(() => _dragIndex = null);
    if (select && target != widget.index) {
      widget.onSelect(target);
    }
  }

  Widget _item(int index, bool highlighted, MeshStyle style) {
    final color = highlighted ? style.accent : style.text;
    final text = Text(
      widget.labels[index],
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: widget.textOnly ? 15 : 11.5,
        fontWeight: widget.textOnly && !highlighted
            ? FontWeight.w400
            : FontWeight.w600,
        color: color,
      ),
    );
    if (widget.textOnly) return Center(child: text);
    final count = index < widget.unreadCounts.length
        ? widget.unreadCounts[index]
        : 0;
    final display = count > 99 ? (index == 0 ? '99+' : '+99') : '$count';
    final icon = useIosControls
        ? SizedBox.square(
            dimension: 19,
            child: IgnorePointer(
              child: IosControl(
                kind: 'symbolIcon',
                properties: {
                  'symbol': widget.symbols[index],
                  'selected': highlighted,
                  'accent': color.toARGB32(),
                },
              ),
            ),
          )
        : Icon(widget.icons[index], size: 19, color: color);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Badge(
          isLabelVisible: count > 0,
          label: Semantics(
            label: tr(context, 'Непрочитанных: $count', 'Unread: $count'),
            excludeSemantics: true,
            child: Text(display),
          ),
          child: icon,
        ),
        const SizedBox(height: 2),
        Flexible(child: text),
      ],
    );
  }

  Widget _surface(MeshStyle style, Widget child) {
    if (widget.textOnly) return GlassSurface(radius: 24, child: child);
    return Material(
      color: MediaQuery.highContrastOf(context)
          ? style.surface
          : style.pill.withAlpha(255),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
        side: BorderSide(color: style.separator),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final count = widget.labels.length;
    final indicatorRadius = BorderRadius.circular(widget.textOnly ? 20 : 25);
    final index = _dragIndex ?? widget.index.toDouble();
    final highlightedIndex = index.round();
    final platform = Theme.of(context).platform;
    final draggable =
        widget.textOnly ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS;
    final direction = Directionality.of(context) == TextDirection.ltr ? 1 : -1;
    return _surface(
      style,
      SizedBox(
        height: widget.height,
        child: Padding(
          padding: EdgeInsets.all(widget.textOnly ? 3 : 4),
          child: Listener(
            onPointerCancel: draggable ? (_) => _endDrag(select: false) : null,
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onHorizontalDragStart: draggable
                    ? (details) {
                        _startX = details.localPosition.dx;
                        _startIndex = widget.index;
                        setState(() => _dragIndex = _startIndex.toDouble());
                      }
                    : null,
                onHorizontalDragUpdate: draggable
                    ? (details) {
                        final tabWidth = constraints.maxWidth / count;
                        final next =
                            _startIndex +
                            direction *
                                (details.localPosition.dx - _startX) /
                                tabWidth;
                        setState(
                          () => _dragIndex = next.clamp(0.0, count - 1.0),
                        );
                      }
                    : null,
                onHorizontalDragEnd: draggable
                    ? (_) => _endDrag(select: true)
                    : null,
                onHorizontalDragCancel: draggable
                    ? () => _endDrag(select: false)
                    : null,
                child: Stack(
                  children: [
                    AnimatedAlign(
                      alignment: AlignmentDirectional(
                        2 * index / (count - 1) - 1,
                        0,
                      ),
                      duration: _dragIndex == null
                          ? meshMotion(context)
                          : Duration.zero,
                      curve: Curves.easeOutCubic,
                      child: FractionallySizedBox(
                        widthFactor: 1 / count,
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: indicatorRadius,
                            color: _tabSelection(style),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < count; i++)
                          Expanded(
                            child: Semantics(
                              selected: widget.index == i,
                              button: true,
                              child: InkWell(
                                borderRadius: indicatorRadius,
                                splashFactory: widget.textOnly
                                    ? null
                                    : NoSplash.splashFactory,
                                highlightColor: widget.textOnly
                                    ? null
                                    : Colors.transparent,
                                onTap: () => widget.onSelect(i),
                                child: _item(i, highlightedIndex == i, style),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Duration meshMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 240);

class ChatFilters extends StatelessWidget {
  const ChatFilters({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final int selected;
  final ValueChanged<int> onSelect;

  static double contentHeight(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(15) * 1.2 + 30).ceilToDouble();

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final labels = [
      tr(context, 'Все', 'All'),
      tr(context, 'Личные', 'Direct'),
      tr(context, 'Каналы', 'Channels'),
    ];
    final titleSize = MediaQuery.textScalerOf(context).scale(15);
    final height = contentHeight(context);
    if (useIosControls) {
      return SizedBox(
        height: height,
        child: IosControl(
          kind: 'tabs',
          horizontalDrag: true,
          eagerGestures: true,
          onSelect: onSelect,
          properties: {
            'labels': labels,
            'index': selected,
            'textOnly': true,
            'titleSize': titleSize,
            'dark': style.dark,
            'accent': style.accent.toARGB32(),
          },
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: _FlutterTabs(
        labels: labels,
        height: height - 8,
        index: selected,
        textOnly: true,
        onSelect: onSelect,
      ),
    );
  }
}
