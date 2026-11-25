// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../mesh/network.dart';
import 'emoji_picker.dart';
import 'emoji_text.dart';
import 'message_reactions.dart';
import 'ios_control.dart';
import 'navigation.dart';
import 'mesh_scroll_edge.dart';
import 'style.dart';

typedef MessageMenuChoice = ({String value, Rect? reactionSource});

class _MessageMenuRoute extends RawDialogRoute<MessageMenuChoice> {
  _MessageMenuRoute({
    required super.pageBuilder,
    required super.barrierLabel,
    required super.transitionDuration,
    required super.transitionBuilder,
  }) : super(barrierColor: Colors.transparent);

  @override
  bool didPop(MessageMenuChoice? result) {
    if (result?.reactionSource != null) {
      controller?.reverseDuration = Duration.zero;
    }
    return super.didPop(result);
  }
}

Future<MessageMenuChoice?> showMessageMenu({
  Uint8List? backdrop,
  required BuildContext context,
  required Rect anchor,
  Rect? desktopBounds,
  required bool canReact,
  List<String> recentReactions = const [],
  required bool canReply,
  bool saved = false,
  bool? pinned,
  bool canForward = false,
  bool canQuoteText = false,
  required bool outgoing,
  required Widget bubble,
  required List<ChatReaction> reactions,
  required ValueChanged<Peer> onOpenProfile,
  required Widget details,
}) async {
  final route = _MessageMenuRoute(
    barrierLabel: tr(context, 'Закрыть меню', 'Close menu'),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: desktopBounds == null ? 350 : 140),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (_, _, _) => MessageMenuBackdrop(
      image: backdrop,
      child: _MessageMenu(
        anchor: anchor,
        desktopBounds: desktopBounds,
        canReact: canReact,
        recentReactions: recentReactions,
        canReply: canReply,
        saved: saved,
        pinned: pinned,
        canForward: canForward,
        canQuoteText: canQuoteText,
        outgoing: outgoing,
        bubble: bubble,
        reactions: reactions,
        onOpenProfile: onOpenProfile,
        details: details,
      ),
    ),
  );
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  if (result?.reactionSource == null) await route.completed;
  return result;
}

class _MessageMenu extends StatefulWidget {
  const _MessageMenu({
    required this.anchor,
    required this.desktopBounds,
    required this.canReact,
    required this.recentReactions,
    required this.canReply,
    required this.saved,
    required this.pinned,
    required this.canForward,
    required this.canQuoteText,
    required this.outgoing,
    required this.bubble,
    required this.reactions,
    required this.onOpenProfile,
    required this.details,
  });

  final Rect anchor;
  final Rect? desktopBounds;
  final bool canReact, canReply, outgoing, saved;
  final bool? pinned;
  final bool canForward, canQuoteText;
  final List<String> recentReactions;
  final Widget bubble, details;
  final List<ChatReaction> reactions;
  final ValueChanged<Peer> onOpenProfile;

  @override
  State<_MessageMenu> createState() => _MessageMenuState();
}

enum _MenuPanel { actions, emoji, reactions, details }

class _MessageMenuState extends State<_MessageMenu> {
  var _panel = _MenuPanel.actions;

  void _select(String value, [Rect? reactionSource]) =>
      Navigator.of(context).pop((value: value, reactionSource: reactionSource));
  void _show(_MenuPanel panel) => setState(() => _panel = panel);

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    if (widget.desktopBounds case final bounds?) {
      return _desktopMenu(bounds, style);
    }
    final media = MediaQuery.of(context);
    final showPicker =
        _panel == _MenuPanel.actions || _panel == _MenuPanel.emoji;
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        key: const ValueKey('message-menu'),
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () => Navigator.of(context).pop(),
        child: ColoredBox(
          color: messageMenuDim(context),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              media.padding.top,
              0,
              media.padding.bottom + media.viewInsets.bottom,
            ),
            child: LayoutBuilder(
              builder: (context, bounds) {
                final align = widget.outgoing
                    ? Alignment.centerRight
                    : Alignment.centerLeft;
                return CustomSingleChildLayout(
                  delegate: _MenuPosition(
                    anchor: widget.anchor.shift(Offset(0, -media.padding.top)),
                    outgoing: widget.outgoing,
                    progress: ModalRoute.of(context)!.animation!,
                    expanded: _panel != _MenuPanel.actions,
                    quickReactions: showPicker && widget.canReact,
                  ),
                  child: SizedBox(
                    width:
                        bounds.maxWidth.clamp(0.0, 560.0) -
                        (bounds.maxWidth < 28 ? 0 : 28),
                    child: MeshScrollViewport(
                      edgeExtent: 12,
                      child: SingleChildScrollView(
                        primary: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showPicker && widget.canReact)
                              AnimatedSwitcher(
                                duration: meshMotion(context),
                                child: ScaleTransition(
                                  alignment: Alignment.bottomCenter,
                                  scale: ModalRoute.of(context)!.animation!
                                      .drive(
                                        Tween<double>(begin: .78, end: 1).chain(
                                          CurveTween(curve: Curves.easeOutBack),
                                        ),
                                      ),
                                  child: _panel == _MenuPanel.emoji
                                      ? EmojiPicker(
                                          key: const ValueKey('emoji-catalog'),
                                          gridHeight: (bounds.maxHeight * .39)
                                              .clamp(95, 275)
                                              .toDouble(),
                                          onSelect: _select,
                                          onSelectFrom: _select,
                                          onCollapse: () =>
                                              _show(_MenuPanel.actions),
                                        )
                                      : _QuickReactions(
                                          recent: widget.recentReactions,
                                          onSelect: _select,
                                          onExpand: () =>
                                              _show(_MenuPanel.emoji),
                                        ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            IgnorePointer(
                              key: const ValueKey('message-menu-preview'),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  if (useIosControls)
                                    // Give the preview its own Flutter overlay above
                                    // the UIKit views and the dimmed chat below.
                                    const Positioned(
                                      left: -4,
                                      right: -4,
                                      top: 0,
                                      bottom: 0,
                                      child: IosControl(
                                        kind: 'messagePreview',
                                        properties: {},
                                      ),
                                    ),
                                  widget.bubble,
                                ],
                              ),
                            ),
                            if (_panel != _MenuPanel.emoji) ...[
                              const SizedBox(height: 9),
                              Align(
                                alignment: align,
                                child: SizedBox(
                                  width: _panel == _MenuPanel.actions
                                      ? 242
                                      : 362,
                                  child: ScaleTransition(
                                    alignment: widget.outgoing
                                        ? Alignment.topRight
                                        : Alignment.topLeft,
                                    scale: ModalRoute.of(context)!.animation!
                                        .drive(
                                          Tween<double>(
                                            begin: .78,
                                            end: 1,
                                          ).chain(
                                            CurveTween(
                                              curve: Curves.easeOutBack,
                                            ),
                                          ),
                                        ),
                                    child: _actionSurface(
                                      _panel == _MenuPanel.actions
                                          ? _actions(style)
                                          : _details(bounds, style),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopMenu(Rect pane, MeshStyle style) => CustomSingleChildLayout(
    key: const ValueKey('message-menu'),
    delegate: _DesktopMenuPosition(
      pointer: widget.anchor.bottomLeft,
      pane: pane,
    ),
    child: SizedBox(
      width: _panel == _MenuPanel.actions ? 288 : 362,
      child: LayoutBuilder(
        builder: (context, bounds) => SingleChildScrollView(
          primary: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_panel == _MenuPanel.actions && widget.canReact) ...[
                _QuickReactions(
                  recent: widget.recentReactions,
                  onSelect: _select,
                  onExpand: () => _show(_MenuPanel.emoji),
                  compact: true,
                ),
                const SizedBox(height: 6),
              ],
              if (_panel == _MenuPanel.emoji)
                EmojiPicker(
                  key: const ValueKey('emoji-catalog'),
                  gridHeight: (bounds.maxHeight * .55).clamp(95.0, 275.0),
                  onSelect: _select,
                  onSelectFrom: _select,
                  onCollapse: () => _show(_MenuPanel.actions),
                )
              else
                MessageMenuSurface(
                  radius: 14,
                  child: _panel == _MenuPanel.actions
                      ? _actions(style)
                      : _details(bounds, style),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _actionSurface(Widget child) => useIosControls
      ? MessageMenuSurface(radius: 22, child: child)
      : GlassSurface(modal: true, radius: 22, child: child);

  Widget _actions(MeshStyle style) {
    final count = groupReactions(widget.reactions).values
        .fold(0, (total, group) => total + group.length);
    final authors = <String, ReactionAuthor>{
      for (final item in widget.reactions) item.reaction.actor: item.author,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.reactions.isNotEmpty) ...[
          _action(
            Icons.favorite_border_rounded,
            '${tr(context, 'Реакции', 'Reactions')} ($count)',
            () => _show(_MenuPanel.reactions),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final author in authors.values.take(2))
                  ReactionAvatar(author),
              ],
            ),
          ),
          Divider(height: 1, indent: 15, endIndent: 15, color: style.separator),
        ],
        if (widget.canReply)
          _action(
            Icons.reply_rounded,
            tr(context, 'Ответить', 'Reply'),
            () => _select('reply'),
          ),
        _action(
          Icons.content_copy_rounded,
          tr(context, 'Копировать', 'Copy'),
          () => _select('copy'),
        ),
        if (widget.canQuoteText)
          _action(
            Icons.format_quote_rounded,
            tr(context, 'Цитировать фрагмент', 'Quote selection'),
            () => _select('quote-text'),
          ),
        if (widget.canForward)
          _action(
            Icons.forward_rounded,
            tr(context, 'Переслать текст', 'Forward as text'),
            () => _select('forward-text'),
          ),
        _action(
          widget.saved
              ? Icons.bookmark_remove_outlined
              : Icons.bookmark_border_rounded,
          widget.saved
              ? tr(context, 'Убрать из Избранного', 'Remove from Saved')
              : tr(context, 'В Избранное', 'Save message'),
          () => _select('saved'),
        ),
        if (widget.pinned case final pinned?)
          _action(
            pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
            pinned
                ? tr(context, 'Открепить', 'Unpin message')
                : tr(context, 'Закрепить', 'Pin message'),
            () => _select('pin'),
          ),
        _action(
          Icons.info_outline_rounded,
          tr(context, 'О сообщении', 'Message info'),
          () => _show(_MenuPanel.details),
        ),
      ],
    );
  }

  Widget _details(BoxConstraints bounds, MeshStyle style) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ListTile(
        leading: MeshIconButton(
          icon: Icon(Icons.arrow_back_rounded, color: style.text, size: 21),
          label: tr(context, 'Назад к меню сообщения', 'Back to message menu'),
          onPressed: () => _show(_MenuPanel.actions),
        ),
        title: Text(
          _panel == _MenuPanel.reactions
              ? tr(context, 'Реакции', 'Reactions')
              : tr(context, 'О сообщении', 'Message info'),
        ),
        visualDensity: VisualDensity.compact,
      ),
      Divider(height: 1, indent: 15, endIndent: 15, color: style.separator),
      if (_panel == _MenuPanel.reactions)
        _ReactionList(
          reactions: widget.reactions,
          onOpenProfile: widget.onOpenProfile,
          maxHeight: (bounds.maxHeight * .44).clamp(72.0, 340.0),
        )
      else
        widget.details,
    ],
  );

  Widget _action(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Widget? trailing,
  }) => ListTile(
    dense: true,
    leading: Icon(icon, size: 20, color: MeshStyle.of(context).text),
    title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: trailing,
    onTap: onTap,
  );
}

class _ReactionList extends StatefulWidget {
  const _ReactionList({
    required this.reactions,
    required this.maxHeight,
    required this.onOpenProfile,
  });

  final List<ChatReaction> reactions;
  final double maxHeight;
  final ValueChanged<Peer> onOpenProfile;

  @override
  State<_ReactionList> createState() => _ReactionListState();
}

class _ReactionListState extends State<_ReactionList> {
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final locale = MaterialLocalizations.of(context);
    final groups = groupReactions(widget.reactions);
    final visible =
        (_filter == null
              ? groups.values.expand((items) => items).toList()
              : List<ChatReaction>.of(groups[_filter] ?? const []))
          ..sort(
            (a, b) => (b.reaction.time?.millisecondsSinceEpoch ?? 0).compareTo(
              a.reaction.time?.millisecondsSinceEpoch ?? 0,
            ),
          );
    Widget filter(String? emoji, String label) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: EmojiText(label),
        showCheckmark: false,
        selectedColor: style.selection,
        selected: emoji == _filter,
        onSelected: (_) => setState(() => _filter = emoji),
      ),
    );
    return Column(
      children: [
        if (groups.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            child: Row(
              children: [
                filter(null, tr(context, 'Все', 'All')),
                for (final entry in groups.entries)
                  filter(
                    entry.key,
                    '${entry.value.first.reaction.emoji} ${entry.value.length}',
                  ),
              ],
            ),
          ),
        SizedBox(
          height: math.min(widget.maxHeight, visible.length * 61.0),
          child: MeshScrollViewport(
            edgeExtent: 10,
            child: ListView.builder(
              key: ValueKey(_filter),
              primary: false,
              padding: const EdgeInsets.only(bottom: 6),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final item = visible[index];
                final time = item.reaction.time?.toLocal();
                final peer = item.author.peer;
                return ListTile(
                  dense: true,
                  onTap: peer == null ? null : () => widget.onOpenProfile(peer),
                  leading: ReactionAvatar(item.author, size: 32),
                  title: Text(
                    item.reaction.own
                        ? tr(context, 'Вы', 'You')
                        : item.author.name ??
                              tr(context, 'Неизвестный узел', 'Unknown node'),
                  ),
                  subtitle: time == null
                      ? null
                      : Text(
                          '${locale.formatShortDate(time)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(time), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}',
                          style: TextStyle(color: style.secondary),
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      Text(
                        item.reaction.emoji,
                        style: emojiGlyphStyle(const TextStyle(fontSize: 20)),
                      ),
                      if (peer != null)
                        Icon(
                          Icons.chevron_right_rounded,
                          color: style.secondary,
                          size: 18,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuPosition extends SingleChildLayoutDelegate {
  const _MenuPosition({
    required this.anchor,
    required this.outgoing,
    required this.progress,
    required this.expanded,
    required this.quickReactions,
  }) : super(relayout: progress);

  final Rect anchor;
  final bool outgoing;
  final Animation<double> progress;
  final bool expanded, quickReactions;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          constraints.maxWidth,
          (constraints.maxHeight - 24).clamp(0, double.infinity),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final preferred = expanded
        ? (size.height - childSize.height) * .48
        : anchor.top - (quickReactions ? 62 : 8);
    final target = Offset(
      (size.width - childSize.width) / 2,
      preferred.clamp(
        12.0,
        (size.height - childSize.height - 12).clamp(12.0, double.infinity),
      ),
    );
    final start = Offset(
      outgoing ? anchor.right - childSize.width : anchor.left,
      anchor.top - (quickReactions ? 61 : 8),
    );
    return Offset.lerp(
      start,
      target,
      Curves.easeOutBack.transform(progress.value),
    )!;
  }

  @override
  bool shouldRelayout(_MenuPosition old) =>
      old.anchor != anchor ||
      old.progress != progress ||
      old.outgoing != outgoing ||
      old.expanded != expanded ||
      old.quickReactions != quickReactions;
}

class _DesktopMenuPosition extends SingleChildLayoutDelegate {
  const _DesktopMenuPosition({required this.pointer, required this.pane});

  final Offset pointer;
  final Rect pane;

  Rect _available(Size size) {
    final window = Offset.zero & size;
    final viewport = pane.intersect(window);
    final visible = viewport.isEmpty ? window : viewport;
    final inset = math.min(8.0, math.min(visible.width, visible.height) / 2);
    return visible.deflate(inset);
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(_available(constraints.biggest).size);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bounds = _available(size);
    final maxX = bounds.right - childSize.width;
    final maxY = bounds.bottom - childSize.height;
    final left = pointer.dx <= maxX ? pointer.dx : pointer.dx - childSize.width;
    const gap = 4.0;
    final top = pointer.dy + gap <= maxY
        ? pointer.dy + gap
        : pointer.dy - gap - childSize.height;
    return Offset(left.clamp(bounds.left, maxX), top.clamp(bounds.top, maxY));
  }

  @override
  bool shouldRelayout(_DesktopMenuPosition old) =>
      old.pointer != pointer || old.pane != pane;
}

class _QuickReactions extends StatelessWidget {
  const _QuickReactions({
    required this.recent,
    required this.onSelect,
    required this.onExpand,
    this.compact = false,
  });

  final List<String> recent;

  final void Function(String emoji, Rect? source) onSelect;
  final VoidCallback onExpand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final renderedKeys = <String>{};
    final options = [
      for (final emoji in [...recent, ...quickReactions])
        if (renderedKeys.add(reactionEmojiKey(emoji))) emoji,
    ];
    return MessageMenuSurface(
      radius: compact ? 14 : 29,
      child: SizedBox(
        height: compact ? 44 : 53,
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                scrollDirection: Axis.horizontal,
                itemCount: options.length,
                separatorBuilder: (_, _) => const SizedBox(width: 2),
                itemBuilder: (context, index) {
                  final emoji = options[index];
                  return Builder(
                    builder: (context) => MeshIconButton(
                      label: '${tr(context, 'Реакция', 'React')} $emoji',
                      onPressed: () =>
                          onSelect(emoji, reactionGlyphBounds(context, 25)),
                      icon: Text(
                        emoji,
                        style: emojiGlyphStyle(const TextStyle(fontSize: 25)),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: style.field,
                shape: BoxShape.circle,
              ),
              child: MeshIconButton(
                label: tr(context, 'Все эмодзи', 'All emoji'),
                onPressed: onExpand,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
