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

Future<String?> showMessageMenu({
  Uint8List? backdrop,
  required BuildContext context,
  required Rect anchor,
  required bool canReact,
  List<String> recentReactions = const [],
  required bool canReply,
  bool saved = false,
  bool? pinned,
  required bool outgoing,
  required Widget bubble,
  required List<ChatReaction> reactions,
  required ValueChanged<Peer> onOpenProfile,
  required Widget details,
}) async {
  final route = RawDialogRoute<String>(
    barrierDismissible: true,
    barrierLabel: tr(context, 'Закрыть меню', 'Close menu'),
    barrierColor: Colors.transparent,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 350),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (_, _, _) => MessageMenuBackdrop(
      image: backdrop,
      child: _MessageMenu(
        anchor: anchor,
        canReact: canReact,
        recentReactions: recentReactions,
        canReply: canReply,
        saved: saved,
        pinned: pinned,
        outgoing: outgoing,
        bubble: bubble,
        reactions: reactions,
        onOpenProfile: onOpenProfile,
        details: details,
      ),
    ),
  );
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  return result;
}

class _MessageMenu extends StatefulWidget {
  const _MessageMenu({
    required this.anchor,
    required this.canReact,
    required this.recentReactions,
    required this.canReply,
    required this.saved,
    required this.pinned,
    required this.outgoing,
    required this.bubble,
    required this.reactions,
    required this.onOpenProfile,
    required this.details,
  });

  final Rect anchor;
  final bool canReact, canReply, outgoing, saved;
  final bool? pinned;
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

  void _select(String value) => Navigator.of(context).pop(value);
  void _show(_MenuPanel panel) => setState(() => _panel = panel);

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: style.text, size: 21),
          tooltip: tr(
            context,
            'Назад к меню сообщения',
            'Back to message menu',
          ),
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

class _QuickReactions extends StatelessWidget {
  const _QuickReactions({
    required this.recent,
    required this.onSelect,
    required this.onExpand,
  });

  final List<String> recent;

  final ValueChanged<String> onSelect;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final renderedKeys = <String>{};
    final options = [
      for (final emoji in [...recent, ...quickReactions])
        if (renderedKeys.add(reactionEmojiKey(emoji))) emoji,
    ];
    return MessageMenuSurface(
      radius: 29,
      child: SizedBox(
        height: 53,
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
                  return IconButton(
                    tooltip: '${tr(context, 'Реакция', 'React')} $emoji',
                    onPressed: () => onSelect(emoji),
                    icon: Text(
                      emoji,
                      style: emojiGlyphStyle(const TextStyle(fontSize: 25)),
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
              child: IconButton(
                tooltip: tr(context, 'Все эмодзи', 'All emoji'),
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
