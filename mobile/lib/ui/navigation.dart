import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import 'ios_control.dart';
import 'style.dart';

Color _tabSelection(MeshStyle style) =>
    style.dark ? const Color(0xff373c48) : const Color(0xffe1e5ec);

class MeshNavigation extends StatelessWidget {
  const MeshNavigation({
    super.key,
    required this.index,
    required this.unread,
    required this.onSelect,
  });
  final int index, unread;
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

  @override
  Widget build(BuildContext context) {
    final labels = [
      tr(context, 'Чаты', 'Chats'),
      tr(context, 'Настройки', 'Settings'),
    ];
    final style = MeshStyle.of(context);
    final height = contentHeight(context);
    if (useIosControls) {
      return SizedBox(
        height: height + MediaQuery.viewPaddingOf(context).bottom,
        child: IosControl(
          kind: 'tabs',
          horizontalDrag: true,
          onSelect: onSelect,
          properties: {
            'labels': labels,
            'index': index,
            'unread': unread,
            'dark': style.dark,
            'accent': style.accent.toARGB32(),
          },
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 208),
        child: _FlutterTabs(
          labels: labels,
          height: height,
          index: index,
          unread: unread,
          onSelect: onSelect,
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
    this.unread = 0,
    this.textOnly = false,
    required this.onSelect,
  });

  final List<String> labels;
  final double height;
  final int index, unread;
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Badge(
          isLabelVisible: index == 0 && widget.unread > 0,
          label: Text(widget.unread > 99 ? '99+' : '${widget.unread}'),
          child: Icon(
            index == 0 ? MeshNavigation.chatIcon : Icons.settings_outlined,
            size: 19,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Flexible(child: text),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final count = widget.labels.length;
    final indicatorRadius = BorderRadius.circular(widget.textOnly ? 20 : 25);
    final index = _dragIndex ?? widget.index.toDouble();
    final highlightedIndex = index.round();
    final draggable =
        widget.textOnly || Theme.of(context).platform == TargetPlatform.android;
    final direction = Directionality.of(context) == TextDirection.ltr ? 1 : -1;
    return GlassSurface(
      radius: widget.textOnly ? 24 : 30,
      child: SizedBox(
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
