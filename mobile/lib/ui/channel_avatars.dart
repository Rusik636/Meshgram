// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderViewport, ViewportOffset;
import 'package:leap_sliver_list/leap_sliver_list.dart';

import '../mesh/network.dart';
import 'page_route.dart';
import 'profile_page.dart';
import 'style.dart';

typedef ChannelAuthorGroup = ({int newest, int oldest, MeshMessage message});

class ChatMessageList extends SuperListView {
  ChatMessageList({
    super.key,
    required super.controller,
    required super.listController,
    required super.physics,
    required super.itemCount,
    required super.itemBuilder,
    required super.findChildIndexCallback,
    required this.insets,
    required this.avatars,
  }) : super.builder(
         reverse: true,
         keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
         padding: insets,
       );

  final EdgeInsets insets;
  final ChannelAuthorAvatars? avatars;

  @override
  Widget buildViewport(
    BuildContext context,
    ViewportOffset offset,
    AxisDirection axisDirection,
    List<Widget> slivers,
  ) {
    final viewport = super.buildViewport(
      context,
      offset,
      axisDirection,
      slivers,
    );
    final layer = avatars;
    if (layer == null) return viewport;
    return Stack(
      fit: StackFit.expand,
      children: [
        viewport,
        Positioned(
          top: 0,
          bottom: 0,
          left: insets.left,
          width: ChannelAuthorAvatars.size,
          child: Semantics(
            tagForChildren: RenderViewport.useTwoPaneSemantics,
            child: Semantics(
              tagForChildren: RenderViewport.excludeFromScrolling,
              child: ClipRect(child: layer),
            ),
          ),
        ),
      ],
    );
  }
}

/// Places each avatar at the bottom of its message group. While the group
/// extends under the composer, the avatar stays within the visible history.
class ChannelAuthorAvatars extends StatefulWidget {
  const ChannelAuthorAvatars({
    super.key,
    required this.bottomInset,
    required this.history,
    required this.scroll,
    required this.groups,
    required this.messageCount,
    required this.authorFor,
    required this.onOpenProfile,
  });

  static const size = 34.0;
  static const gutter = size + 10.0;

  final double bottomInset;
  final ListController history;
  final ScrollController scroll;
  final List<ChannelAuthorGroup> groups;
  final int messageCount;
  final Peer? Function(MeshMessage) authorFor;
  final ValueChanged<Peer> onOpenProfile;

  @override
  State<ChannelAuthorAvatars> createState() => _ChannelAuthorAvatarsState();
}

class _ChannelAuthorAvatarsState extends State<ChannelAuthorAvatars> {
  (int, int)? _range;
  bool _refreshScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.history.addListener(_refreshRange);
    _refreshRange();
  }

  @override
  void didUpdateWidget(ChannelAuthorAvatars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.history != widget.history) {
      oldWidget.history.removeListener(_refreshRange);
      widget.history.addListener(_refreshRange);
      _refreshRange();
    }
  }

  @override
  void dispose() {
    widget.history.removeListener(_refreshRange);
    super.dispose();
  }

  void _refreshRange() {
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!mounted) return;
      final history = widget.history;
      final range = history.isAttached ? history.visibleRange : null;
      if (_range != range) setState(() => _range = range);
    });
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    if (range == null) return const SizedBox.shrink();
    final groups = widget.groups
        .where(
          (group) =>
              group.oldest >= range.$1 - 2 && group.newest <= range.$2 + 2,
        )
        .toList();
    return Flow(
      clipBehavior: Clip.none,
      delegate: _AvatarPositions(
        widget.history,
        widget.scroll,
        groups,
        widget.messageCount,
        widget.bottomInset,
      ),
      children: [
        for (final group in groups)
          _ChannelAuthorAvatar(
            key: ValueKey(('channel-author', group.message.id)),
            message: group.message,
            peer: widget.authorFor(group.message),
            onOpenProfile: widget.onOpenProfile,
          ),
      ],
    );
  }
}

void openChannelAuthorProfile(
  BuildContext context,
  MeshMessage message,
  Peer? peer,
  ValueChanged<Peer> onOpenProfile,
) {
  if (peer != null) {
    onOpenProfile(peer);
    return;
  }
  final name = message.author;
  unawaited(
    Navigator.of(context).push<void>(
      meshPageRoute<void>(
        context,
        builder: (context) => Scaffold(
          body: ProfilePage(
            title: name.isEmpty
                ? tr(context, 'Неизвестный автор', 'Unknown sender')
                : name,
            subtitle: tr(context, 'Узла нет в списке', 'Node not in directory'),
            avatar: MeshAvatar(name.isEmpty ? '?' : name, size: 105),
            avatarSize: 105,
            padding: meshScrollPadding(
              context,
              const EdgeInsets.fromLTRB(16, 0, 16, 26),
            ),
            leading: GlassButton(
              icon: Icons.arrow_back_ios_new_rounded,
              label: tr(context, 'Назад', 'Back'),
              onTap: () => Navigator.pop(context),
            ),
            children: [
              MeshGroup(
                children: [
                  MeshRow(
                    title: tr(context, 'Идентификатор', 'Identifier'),
                    subtitle:
                        message.packet?.sender ??
                        tr(context, 'Не передан', 'Unavailable'),
                    icon: Icons.qr_code_2_rounded,
                    tint: MeshStyle.of(context).accent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ChannelAuthorAvatar extends StatelessWidget {
  const _ChannelAuthorAvatar({
    super.key,
    required this.message,
    required this.peer,
    required this.onOpenProfile,
  });

  final MeshMessage message;
  final Peer? peer;
  final ValueChanged<Peer> onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final sender = peer;
    final name = sender?.name ?? message.author;
    return Semantics(
      label: sender != null
          ? null
          : name.isEmpty
          ? tr(context, 'Неизвестный автор', 'Unknown sender')
          : name,
      child: MeshAvatar(
        name.isEmpty ? '?' : name,
        size: ChannelAuthorAvatars.size,
        onTap: () =>
            openChannelAuthorProfile(context, message, sender, onOpenProfile),
      ),
    );
  }
}

class _AvatarPositions extends FlowDelegate {
  _AvatarPositions(
    this.history,
    this.scroll,
    this.groups,
    this.messageCount,
    this.bottomInset,
  ) : super(repaint: Listenable.merge([history, scroll]));

  final ListController history;
  final ScrollController scroll;
  final List<ChannelAuthorGroup> groups;
  final int messageCount;
  final double bottomInset;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      const BoxConstraints.tightFor(
        width: ChannelAuthorAvatars.size,
        height: ChannelAuthorAvatars.size,
      );

  @override
  void paintChildren(FlowPaintingContext context) {
    if (!history.isAttached ||
        !scroll.hasClients ||
        history.numberOfItems != messageCount) {
      return;
    }
    const avatarSize = ChannelAuthorAvatars.size;
    final visibleBottom = context.size.height - bottomInset;
    // Pin above the composer, but let departing groups paint beneath its blur.
    final origin = visibleBottom + scroll.offset;
    for (var index = 0; index < groups.length; index++) {
      final group = groups[index];
      final bottom = origin - history.offsetForIndex(group.newest);
      final top =
          origin -
          history.offsetForIndex(group.oldest) -
          history.extentForIndex(group.oldest).$1;
      final avatarTop = math.max(
        math.min(top, bottom - avatarSize),
        math.min(bottom, visibleBottom) - avatarSize,
      );
      context.paintChild(
        index,
        transform: Matrix4.translationValues(0, avatarTop, 0),
        opacity: avatarTop >= context.size.height || avatarTop + avatarSize <= 0
            ? 0
            : 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarPositions oldDelegate) =>
      oldDelegate.bottomInset != bottomInset ||
      oldDelegate.groups != groups ||
      oldDelegate.history != history ||
      oldDelegate.scroll != scroll ||
      oldDelegate.messageCount != messageCount;
}
