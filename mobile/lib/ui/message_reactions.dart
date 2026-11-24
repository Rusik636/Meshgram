// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';

import '../mesh/network.dart';
import 'emoji_text.dart';
import 'style.dart';

typedef ReactionAuthor = ({String? name, bool hasKey, Peer? peer});
typedef ChatReaction = ({MeshReaction reaction, ReactionAuthor author});
typedef ReactionGlyphTarget = ({Key target, String emojiKey});

Map<String, List<ChatReaction>> groupReactions(List<ChatReaction> reactions) {
  final groups = <String, List<ChatReaction>>{};
  for (final item in reactions) {
    final group = groups.putIfAbsent(item.reaction.emojiKey, () => []);
    if (!group.any((member) => member.reaction.actor == item.reaction.actor)) {
      group.add(item);
    }
  }
  return groups;
}

class ReactionAvatar extends StatelessWidget {
  const ReactionAvatar(this.author, {super.key, this.size = chipSize});

  static const chipSize = 22.0;

  final ReactionAuthor author;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final name = author.name;
    if (author.hasKey && name != null && name.isNotEmpty) {
      return Semantics(
        label: name,
        child: MeshAvatar(name, size: size),
      );
    }
    return Semantics(
      label: tr(context, 'Публичный ключ неизвестен', 'Public key unknown'),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: style.pill, shape: BoxShape.circle),
        child: Icon(
          Icons.priority_high_rounded,
          size: size * .68,
          color: style.secondary,
        ),
      ),
    );
  }
}

class MessageReactionChips extends StatelessWidget {
  const MessageReactionChips(
    this.reactions, {
    super.key,
    this.onReact,
    this.outsideBubble = false,
    this.alignment = WrapAlignment.start,
    this.flight,
  });

  final List<ChatReaction> reactions;
  final ValueChanged<String>? onReact;
  final bool outsideBubble;
  final WrapAlignment alignment;
  final ReactionGlyphTarget? flight;

  static const spacing = 5.0;
  static const _inset = 8.0;
  static const _gap = 5.0;
  static TextStyle get _emojiText =>
      emojiGlyphStyle(const TextStyle(fontSize: 16));
  static const _countText = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  Iterable<double> chipWidths(
    double Function(String, TextStyle) measure,
  ) sync* {
    for (final group in groupReactions(reactions).values) {
      yield _inset * 2 +
          _gap +
          measure(group.first.reaction.emoji, _emojiText) +
          (group.length == 1
              ? ReactionAvatar.chipSize
              : measure('${group.length}', _countText));
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final groups = groupReactions(reactions);
    final selectedColor = outsideBubble
        ? (style.dark ? const Color(0xff3564c4) : style.accent)
        : style.selection;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        alignment: alignment,
        spacing: spacing,
        runSpacing: 4,
        children: groups.values.map((group) {
          final selected = group.any((item) => item.reaction.own);
          final emoji = group.first.reaction.emoji;
          final moving =
              flight != null &&
              flight!.emojiKey == group.first.reaction.emojiKey &&
              selected;
          return Material(
            color: selected
                ? selectedColor
                : (outsideBubble ? style.surface : style.field),
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onReact == null ? null : () => onReact!(emoji),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _inset,
                  vertical: 4,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        key: moving ? flight!.target : null,
                        opacity: moving ? 0 : 1,
                        alwaysIncludeSemantics: true,
                        child: Text(emoji, style: _emojiText),
                      ),
                      const SizedBox(width: _gap),
                      if (group.length == 1)
                        ReactionAvatar(group.single.author)
                      else
                        Text(
                          '${group.length}',
                          style: _countText.copyWith(
                            color: outsideBubble && selected
                                ? Colors.white
                                : style.accent,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
