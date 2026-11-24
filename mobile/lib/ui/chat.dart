// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, setEquals;
import 'package:flutter/material.dart' hide Radio;
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:leap_sliver_list/leap_sliver_list.dart';

import '../app_name.dart';
import '../mesh/chat_position.dart';
import '../mesh/controller.dart';
import '../mesh/network.dart';
import '../mesh/nodes.dart' show NodePosition;
import '../mesh/radio_outbox.dart';
import '../radio/channel_invitation.dart';
import 'channel_avatars.dart';
import 'chat_attachments.dart';
import 'style.dart';
import 'page_route.dart';
import 'ios_control.dart';
import 'contact_qr.dart';
import 'emoji_picker.dart';
import 'emoji_text.dart';
import 'radio_settings.dart';
import 'profile_page.dart';
import 'haptics.dart';
import 'mesh_scroll_edge.dart';
import 'message_input.dart';
import 'message_link_metadata.dart' show canFetchMessageLink;
import 'message_links.dart';
import 'message_details.dart';
import 'message_menu.dart';
import 'message_reactions.dart';
import 'message_search.dart';
import 'message_text_actions.dart';
import 'navigation.dart';
import 'node_actions.dart';
import 'position_picker.dart';
import 'quick_phrases.dart';
import 'search_field.dart';
import 'chat_workspace.dart';
import '../mesh/store.dart';

part 'radio_outbox.dart';
part 'saved_messages.dart';

typedef MeshChatOpener = Future<void> Function(
  WidgetBuilder builder, {
  String? peerId,
  required bool jump,
});

Future<void> _pushConversation(
  BuildContext context,
  WidgetBuilder builder, {
  MeshChatOpener? open,
  String? peerId,
  bool jump = false,
}) =>
    open?.call(builder, peerId: peerId, jump: jump) ??
    Navigator.of(context).push<void>(meshPageRoute(context, builder: builder));

/// Opens a chat at an exact entry in the active radio profile's local history.
Future<void> openMeshMessage(
  BuildContext context, {
  required MeshController controller,
  required String chatId,
  required String messageId,
  MeshChatOpener? open,
}) async {
  final peer = controller.cache?.peers[chatId];
  if (peer != null && !peer.channel && controller.isOwnChat(peer.id)) {
    return showSavedChat(context, controller, open: open);
  }
  if (peer == null ||
      !controller.messages(chatId).any((message) => message.id == messageId)) {
    _showMessageUnavailable(context);
    return;
  }
  await _pushConversation(
    context,
    (_) => MeshChatPage(
      controller: controller,
      peer: peer,
      initialMessageId: messageId,
    ),
    open: open,
    peerId: peer.id,
    jump: true,
  );
}

void _showMessageUnavailable(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        tr(
          context,
          'Сообщения больше нет в локальной истории',
          'This message is no longer in local history',
        ),
      ),
    ),
  );
}

typedef ChatPreviewMenuItem = ({
  String label,
  IconData icon,
  VoidCallback onTap,
  bool destructive,
});

typedef _ChatPreviewChoice = ({bool open, VoidCallback? action});

class _ChatPreviewRoute extends RawDialogRoute<_ChatPreviewChoice> {
  _ChatPreviewRoute({
    required super.pageBuilder,
    required super.barrierLabel,
    required super.transitionDuration,
    required this.reverseTransitionDuration,
  }) : super(
         barrierColor: Colors.transparent,
         transitionBuilder: (_, _, _, child) => child,
       );

  @override
  final Duration reverseTransitionDuration;
}

enum _ChatPreviewContent { history, heading }

class _ChatPreviewContentLayout extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final heading = layoutChild(
      _ChatPreviewContent.heading,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height,
      ),
    );
    layoutChild(
      _ChatPreviewContent.history,
      BoxConstraints.tight(Size(size.width, size.height - heading.height)),
    );
    positionChild(_ChatPreviewContent.heading, Offset.zero);
    positionChild(_ChatPreviewContent.history, Offset(0, heading.height));
  }

  @override
  bool shouldRelayout(_ChatPreviewContentLayout oldDelegate) => false;
}

final _iosPreviewSpring = SpringSimulation(
  const SpringDescription(mass: 5, stiffness: 900, damping: 104),
  0,
  1,
  0,
);

double _previewOpeningProgress(double time, {required bool ios}) {
  if (time == 0 || time == 1) return time;
  // The iOS spring settles in 0.741 seconds before being fit to the route.
  if (ios) return _iosPreviewSpring.x(.741194 * time);
  final remaining = time - 1;
  return 1 + remaining * remaining * (2.02 * remaining + 1.02);
}

/// Shows a snapshot of the local history without activating the conversation.
Future<bool> showMeshChatPreview(
  BuildContext context,
  MeshController controller,
  Peer peer,
  Rect anchor, {
  required Widget sourceRow,
  List<ChatPreviewMenuItem> actions = const [],
  GlobalKey? backdropSource,
}) async {
  Uint8List? backdrop;
  if (useIosControls &&
      backdropSource != null &&
      actions.isNotEmpty &&
      !MediaQuery.highContrastOf(context)) {
    try {
      backdrop = await captureMessageMenuBackdrop(backdropSource);
    } on Exception {
      // The menu uses its opaque surface if the snapshot is unavailable.
    }
  }
  if (!context.mounted) return false;
  final messages = controller.messages(peer.id).reversed.take(12).toList();
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final ios = Theme.of(context).platform == TargetPlatform.iOS;
  final duration = reduceMotion
      ? Duration.zero
      : Duration(milliseconds: ios ? 420 : 190);
  final route = _ChatPreviewRoute(
    barrierLabel: tr(context, 'Закрыть предпросмотр', 'Close preview'),
    transitionDuration: duration,
    reverseTransitionDuration: reduceMotion
        ? Duration.zero
        : Duration(milliseconds: ios ? 200 : 150),
    pageBuilder: (context, animation, _) {
      final style = MeshStyle.of(context);
      final padding = MediaQuery.paddingOf(context);
      final pinned = controller.pinnedMessageId(peer.id);
      final pinnedMessage = pinned == null
          ? null
          : controller
                .messages(peer.id)
                .where((item) => item.id == pinned)
                .firstOrNull;
      var fullyOpened = false;
      return LayoutBuilder(
        builder: (context, bounds) {
          final width = math.min(
            480.0,
            bounds.maxWidth - padding.horizontal - 28,
          );
          final usableHeight = bounds.maxHeight - padding.vertical;
          final rowHeight = math.max(
            46.0,
            MediaQuery.textScalerOf(context).scale(16) * 2 + 14,
          );
          final menuHeight = math.min(
            actions.length * rowHeight,
            usableHeight * .40,
          );
          final menuGap = actions.isEmpty ? 0.0 : 8.0;
          final height = math.max(
            0.0,
            math.min(
              480.0,
              math.min(
                usableHeight * .68,
                usableHeight - menuHeight - menuGap - 24,
              ),
            ),
          );
          final card = Rect.fromLTWH(
            padding.left + (bounds.maxWidth - padding.horizontal - width) / 2,
            padding.top + (usableHeight - height - menuHeight - menuGap) / 2,
            width,
            height,
          );
          return AnimatedBuilder(
            animation: animation,
            child: Material(
              type: MaterialType.transparency,
              child: Semantics(
                button: true,
                label: tr(context, 'Открыть чат', 'Open chat'),
                child: GestureDetector(
                  key: const ValueKey('open-chat-preview'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      Navigator.pop(context, (open: true, action: null)),
                  child: CustomPaint(
                    painter: _ContourPaper(style),
                    child: CustomMultiChildLayout(
                      delegate: _ChatPreviewContentLayout(),
                      children: [
                        LayoutId(
                          id: _ChatPreviewContent.history,
                          child: messages.isEmpty
                              ? Center(
                                  child: Text(
                                    tr(
                                      context,
                                      'Начало переписки',
                                      'Start of conversation',
                                    ),
                                  ),
                                )
                              // The entire snapshot can paint as it scrolls
                              // under the heading, up to the card's outer clip.
                              : SingleChildScrollView(
                                  primary: false,
                                  clipBehavior: Clip.none,
                                  reverse: true,
                                  padding: const EdgeInsets.fromLTRB(
                                    9,
                                    2,
                                    9,
                                    8,
                                  ),
                                  child: Column(
                                    children: [
                                      for (final message in messages.reversed)
                                        _Bubble(
                                          item: message,
                                          emoji: null,
                                          hideText: false,
                                          standalonePosition:
                                              switch (chatPosition(
                                                message.text,
                                              )) {
                                                (
                                                  point: final point,
                                                  standalone: true,
                                                ) =>
                                                  point,
                                                _ => null,
                                              },
                                          channel: peer.channel,
                                          joinsPrevious: false,
                                          joinsNext: false,
                                          quoted: controller.referencedMessage(
                                            peer.id,
                                            message.replyTo,
                                          ),
                                          reactions: [
                                            for (final reaction
                                                in controller.reactionsFor(
                                                  message,
                                                ))
                                              (
                                                reaction: reaction,
                                                author: controller
                                                    .reactionAuthor(reaction),
                                              ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                        ),
                        LayoutId(
                          id: _ChatPreviewContent.heading,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  style.canvas.withValues(alpha: .88),
                                  style.canvas.withValues(alpha: 0),
                                ],
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    9,
                                    12,
                                    6,
                                  ),
                                  child: Center(
                                    child: GlassSurface(
                                      modal: true,
                                      radius: 22,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 7,
                                        ),
                                        child: Text(
                                          peer.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (pinnedMessage != null)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      4,
                                    ),
                                    child: GlassSurface(
                                      radius: 17,
                                      child: ListTile(
                                        dense: true,
                                        leading: Icon(
                                          Icons.push_pin_outlined,
                                          color: style.accent,
                                          size: 17,
                                        ),
                                        title: Text(
                                          tr(
                                            context,
                                            'Закреплённое сообщение',
                                            'Pinned message',
                                          ),
                                        ),
                                        subtitle: Text(
                                          pinnedMessage.text,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            builder: (_, child) {
              if (animation.isCompleted) fullyOpened = true;
              final closing =
                  fullyOpened && animation.status == AnimationStatus.reverse;
              final time = animation.value;
              const quint = Cubic(.23, 1, .32, 1);
              final position = reduceMotion
                  ? 1.0
                  : closing
                  ? 1 - (ios ? Curves.easeInOut : quint).transform(1 - time)
                  : _previewOpeningProgress(time, ios: ios);
              final amount = position.clamp(0.0, 1.0);
              final details = reduceMotion
                  ? 1.0
                  : !ios
                  ? amount
                  : closing
                  ? ((time - .2) / .8).clamp(0.0, 1.0)
                  : (time * 420 / 150).clamp(0.0, 1.0);
              final dim = ios && !reduceMotion
                  ? (closing ? time : (time * 420 / 200).clamp(0.0, 1.0))
                  : amount;
              final scale = 1 + math.max(0.0, position - 1) * .3;
              final extent = Size.lerp(anchor.size, card.size, amount)!;
              final frame = Rect.fromCenter(
                center: Offset.lerp(anchor.center, card.center, position)!,
                width: extent.width * scale,
                height: extent.height * scale,
              );
              final scrim = messageMenuDim(context);
              final blur = !MediaQuery.accessibleNavigationOf(context);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: useIosControls
                          ? IosControl(
                              kind: 'chatPreviewBackdrop',
                              properties: {
                                'blur': blur,
                                'dark': style.dark,
                                'color': scrim.toARGB32(),
                                'progress': dim,
                              },
                            )
                          : ClipRect(
                              child: BackdropFilter(
                                enabled: blur && dim > 0,
                                filter: ImageFilter.blur(
                                  sigmaX: 18 * dim,
                                  sigmaY: 18 * dim,
                                  tileMode: TileMode.clamp,
                                ),
                                child: ColoredBox(
                                  color: scrim.withValues(alpha: scrim.a * dim),
                                ),
                              ),
                            ),
                    ),
                  ),
                  if (actions.isNotEmpty && details > 0)
                    Positioned(
                      key: const ValueKey('chat-preview-actions'),
                      top: card.bottom + menuGap + (1 - amount) * 14,
                      right: bounds.maxWidth - card.right,
                      width: math.min(264, width),
                      height: menuHeight,
                      child: IgnorePointer(
                        ignoring: !animation.isCompleted,
                        child: Opacity(
                          opacity: Curves.easeIn.transform(details),
                          child: MessageMenuSurface(
                            radius: 22,
                            backdrop: backdrop,
                            child: ListView(
                              primary: false,
                              padding: EdgeInsets.zero,
                              children: [
                                for (final action in actions)
                                  InkWell(
                                    onTap: () => Navigator.pop(context, (
                                      open: false,
                                      action: action.onTap,
                                    )),
                                    child: SizedBox(
                                      height: rowHeight,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              action.icon,
                                              size: 20,
                                              color: action.destructive
                                                  ? Colors.redAccent
                                                  : style.text,
                                            ),
                                            const SizedBox(width: 11),
                                            Expanded(
                                              child: Text(
                                                action.label,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  height: 1.15,
                                                  color: action.destructive
                                                      ? Colors.redAccent
                                                      : style.text,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Paint the actions before the card inserts its UIKit
                  // title surface, so they stay above the full-screen blur.
                  Positioned.fromRect(
                    key: const ValueKey('chat-preview-card'),
                    rect: frame,
                    child: IgnorePointer(
                      ignoring: !animation.isCompleted,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          (ios ? 26 : 12) * amount,
                        ),
                        child: ColoredBox(
                          color: style.canvas,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (useIosControls && backdrop != null)
                                // Keep the chat bubbles in a Flutter overlay
                                // above the native blur and action material.
                                const IgnorePointer(
                                  child: IosControl(
                                    kind: 'messagePreview',
                                    properties: {},
                                  ),
                                ),
                              if (details < 1)
                                ExcludeSemantics(
                                  child: OverflowBox(
                                    minWidth: anchor.width,
                                    maxWidth: anchor.width,
                                    minHeight: anchor.height,
                                    maxHeight: anchor.height,
                                    child: sourceRow,
                                  ),
                                ),
                              Opacity(
                                opacity: details,
                                child: OverflowBox(
                                  minWidth: width,
                                  maxWidth: width,
                                  minHeight: height,
                                  maxHeight: height,
                                  child: child,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
  final choice = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  choice?.action?.call();
  return choice?.open == true;
}

class MeshChatPage extends StatefulWidget {
  const MeshChatPage({
    super.key,
    required this.controller,
    required this.peer,
    this.initialSearch = false,
    this.initialMessageId,
  });
  final MeshController controller;
  final Peer peer;
  final bool initialSearch;
  final String? initialMessageId;
  @override
  State<MeshChatPage> createState() => _ChatState();
}

typedef _SendTextFlight = ({
  String id,
  String text,
  String draft,
  Rect source,
  Rect? destination,
  bool ios,
});

typedef _SharedChatLink = ({
  String link,
  String caption,
  ContactAttachment? contact,
  ChannelInvitation? channel,
});

_SharedChatLink? _sharedChatLink(MeshController controller, String text) {
  for (final candidate in meshLinksInMessage(text)) {
    final contact = controller.contactAttachment(candidate.link);
    final invite = contact == null ? channelInvitation(candidate.link) : null;
    if (contact != null || invite != null) {
      var start = candidate.start;
      var end = start + candidate.source.length;
      const wrapped = {'(': ')', '[': ']', '<': '>', '«': '»', '"': '"'};
      if (start > 0 &&
          end < text.length &&
          wrapped[text[start - 1]] == text[end]) {
        start--;
        end++;
      }
      return (
        link: candidate.link,
        caption: text.replaceRange(start, end, '').trim(),
        contact: contact,
        channel: invite,
      );
    }
  }
  return null;
}

class _ReactionFlight {
  _ReactionFlight(this.messageId, this.emoji, this.source);

  final String messageId, emoji;
  final Rect source;
  bool accepted = false;
  Rect? destination;
}

class _ChatState extends State<MeshChatPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _draft = EmojiEditingController(
    text: widget.controller.draft(widget.peer.id),
  );
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _iosSearch = GlobalKey<IosControlState>();
  MessageSearchFilters _searchFilters = const MessageSearchFilters();
  final _input = GlobalKey<MessageInputState>();
  final _inputSurface = GlobalKey();
  final _sendControl = GlobalKey();
  final _sendFlightTarget = GlobalKey();
  _SendTextFlight? _sendTextFlight;
  Completer<void>? _sendFlightCompletion;
  late final _sendFlightAnimation = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _finishSentText();
      }
    });
  late final _sendTargetOpacity = _sendFlightAnimation.drive(
    CurveTween(curve: const Interval(.50, 1)),
  );
  _ReactionFlight? _reactionFlight;
  final _reactionTarget = GlobalKey();
  late final _reactionAnimation = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _clearReactionFlight();
    });
  final _scroll = ScrollController(keepScrollOffset: false);
  final _history = ListController();
  AssetBundle? _emojiBundle;
  late Future<EmojiCatalog> _emojiCatalog;
  ItemAnimation? _messageScroll;
  int _messageJump = 0;
  String? _highlighted;
  MessageExcerpt? _highlightedExcerpt;
  late final _highlight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  );
  late final _highlightOpacity = _highlight.drive(
    TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: .24), weight: 12),
      TweenSequenceItem(tween: ConstantTween(.24), weight: 42),
      TweenSequenceItem(tween: Tween(begin: .24, end: 0.0), weight: 46),
    ]),
  );
  late bool _searching = widget.initialSearch;
  double? _searchOriginOffset;
  bool _sending = false;
  Timer? _replyRevealTimer;
  Uri? _dismissedDraftLink;
  Uri? _linkBehindReply;
  bool _menuVisible = false;
  bool _attachmentOpen = false;
  bool _quickPhrasesOpen = false;
  bool _quickPhrasePickerOpen = false;
  bool _openingSharedLink = false;
  final _menuBackground = GlobalKey();
  final _headerKey = GlobalKey();
  final _footerKey = GlobalKey();
  final _attachmentButton = GlobalKey();
  final _attachmentSourceHidden = ValueNotifier(false);
  double _headerHeight = 59;
  double _footerHeight = 76;
  bool _measurementPending = false;
  final _latestButtonVisible = ValueNotifier(false);
  final _visibleLinkMessages = ValueNotifier<Set<String>>(const {});
  late final String? _radio;
  VoidCallback? _untrackViewport;
  ModalRoute<dynamic>? _route;
  bool _workspaceVisible = true;
  List<MeshMessage> _listedMessages = const [];
  final _incomingRows = <String, GlobalKey>{};
  String? _unreadBoundary;
  ({String id, double position})? _historyAnchor;
  bool _listedSearch = false;
  bool _historyScheduled = false;
  late bool _atInitialPosition = widget.initialMessageId != null;
  bool _goingToLatest = false;
  AppLifecycleState? _lifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    _scroll.addListener(_scheduleHistoryUpdate);
    _history.addListener(_scheduleHistoryUpdate);
    final active = widget.controller.active;
    _radio = active == null ? null : radioKey(active);
    if (_radio case final profile?) {
      _untrackViewport = widget.controller.trackChatViewport(
        profile,
        widget.peer.id,
        () => _canReadHistory && _atInitialPosition && _distanceToLatest < 2,
      );
    }
    if (widget.initialMessageId case final id?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_revealMessage(id));
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final couldPreview = _canPreviewLinks;
    _lifecycle = state;
    if (couldPreview != _canPreviewLinks) setState(() {});
    if (state == AppLifecycleState.resumed) _scheduleHistoryUpdate();
  }

  @override
  void didChangeMetrics() {
    if (_replyRevealTimer != null && View.of(context).viewInsets.bottom > 0) {
      _revealReplyAccessory();
    }
  }

  void _revealReplyAccessory() {
    _replyRevealTimer?.cancel();
    if (mounted) setState(() => _replyRevealTimer = null);
  }

  bool get _canPreviewLinks =>
      mounted &&
      !_menuVisible &&
      !_attachmentOpen &&
      _workspaceVisible &&
      (_route?.isCurrent ?? true) &&
      (_lifecycle == null || _lifecycle == AppLifecycleState.resumed);

  bool get _controlsCovered =>
      !_workspaceVisible ||
      _menuVisible ||
      _attachmentOpen ||
      _quickPhrasePickerOpen;

  bool get _canReadHistory => !_searching && _canPreviewLinks;

  double get _distanceToLatest {
    if (!_scroll.hasClients) return 0;
    final position = _scroll.position;
    return position.pixels - position.minScrollExtent;
  }

  void _configureHistory(List<MeshMessage> messages, Set<String> unreadIds) {
    final old = _listedMessages;
    final range = _history.isAttached ? _history.visibleRange : null;
    if (!_searching &&
        !_listedSearch &&
        !_goingToLatest &&
        _distanceToLatest > 2 &&
        old.isNotEmpty &&
        messages.isNotEmpty &&
        (old.length != messages.length ||
            old.first.id != messages.first.id ||
            old.last.id != messages.last.id) &&
        range != null) {
      final index = (range.$1 + range.$2) ~/ 2;
      if (index < old.length && _history.numberOfItems == old.length) {
        _historyAnchor = (
          id: old[old.length - 1 - index].id,
          position: _history.offsetForIndex(index) - _scroll.offset,
        );
      }
    }
    _listedMessages = messages;
    _listedSearch = _searching;
    if (_incomingRows.length > messages.length + 40) {
      final ids = messages.map((item) => item.id).toSet();
      _incomingRows.removeWhere((id, _) => !ids.contains(id));
    }
    if (!_searching &&
        (_unreadBoundary == null ||
            !messages.any((item) => item.id == _unreadBoundary)) &&
        (!_atInitialPosition || _distanceToLatest > 2)) {
      _unreadBoundary = messages
          .where((item) => unreadIds.contains(item.id))
          .firstOrNull
          ?.id;
    }
    _scheduleHistoryUpdate();
  }

  void _scheduleHistoryUpdate() {
    if (_historyScheduled) return;
    _historyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyScheduled = false;
      if (!mounted) return;
      _updateHistoryPosition();
      if (!_historyScheduled) _updateLinkPreviewVisibility();
    });
  }

  void _updateLinkPreviewVisibility() {
    final range = _canPreviewLinks && _history.isAttached
        ? _history.visibleRange
        : null;
    final visible = <String>{};
    if (range != null) {
      for (
        var index = range.$1;
        index <= range.$2 && index < _listedMessages.length;
        index++
      ) {
        visible.add(_listedMessages[_listedMessages.length - index - 1].id);
      }
    }
    if (!setEquals(_visibleLinkMessages.value, visible)) {
      _visibleLinkMessages.value = visible;
    }
  }

  void _updateHistoryPosition() {
    final radio = _radio;
    if (radio == null || _searching) return;
    if (!_history.isAttached ||
        !_scroll.hasClients ||
        _listedMessages.isEmpty) {
      _latestButtonVisible.value = false;
      if (_canReadHistory) {
        widget.controller.clearUnreadFlag(radio, widget.peer.id);
      }
      return;
    }
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    if (_historyAnchor case final anchor?) {
      _historyAnchor = null;
      final message = _listedMessages.indexWhere(
        (item) => item.id == anchor.id,
      );
      if (message >= 0) {
        final index = _listedMessages.length - message - 1;
        final offset = (_history.offsetForIndex(index) - anchor.position).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if ((offset - position.pixels).abs() > .5) {
          _scroll.jumpTo(offset);
          _scheduleHistoryUpdate();
          return;
        }
      }
    }
    final top = MediaQuery.paddingOf(context).top + _headerHeight + 8;
    final bottom = _composerBottom(context) + _footerHeight + 8;
    if (!_atInitialPosition) {
      _atInitialPosition = true;
      final message = _listedMessages.indexWhere(
        (item) => item.id == _unreadBoundary,
      );
      if (message >= 0) {
        final before = position.pixels;
        _history.jumpToItem(
          index: _listedMessages.length - message - 1,
          scrollController: _scroll,
          // The trailing edge of the reversed viewport is next to the title.
          alignment: 1,
          obstruction: ChildObstructionExtent(leading: bottom, trailing: top),
        );
        if ((position.pixels - before).abs() > .5) {
          _scheduleHistoryUpdate();
          return;
        }
      }
    }
    if (_canReadHistory) {
      widget.controller.clearUnreadFlag(radio, widget.peer.id);
    }
    final unread = widget.controller.cache?.unread[widget.peer.id] ?? 0;
    _latestButtonVisible.value =
        _distanceToLatest > 128 || (_distanceToLatest > 2 && unread > 0);
    if (!_canReadHistory || unread == 0) return;
    final range = _history.visibleRange;
    if (range == null) return;
    final box = _menuBackground.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final visibleBottom = box.size.height - bottom;
    // Rows are arranged newest-first. Measure the bubble itself so that a
    // date label or unread divider alone cannot advance the read position.
    for (
      var index = range.$1;
      index <= range.$2 && index < _listedMessages.length;
      index++
    ) {
      final item = _listedMessages[_listedMessages.length - index - 1];
      final row = _incomingRows[item.id]?.currentContext?.findRenderObject();
      if (row is! RenderBox || !row.attached || !row.hasSize) continue;
      final y = row.localToGlobal(Offset.zero, ancestor: box).dy;
      final overlap =
          math.min(y + row.size.height, visibleBottom) - math.max(y, top);
      if (overlap >= math.min(24, row.size.height * .5)) {
        widget.controller.readChatThrough(radio, widget.peer.id, item.id);
        break;
      }
    }
  }

  Future<void> _goToLatest() async {
    if (!_scroll.hasClients || _goingToLatest) return;
    final position = _scroll.position;
    final bottom = position.minScrollExtent;
    final duration = meshMotion(context);
    _messageScroll?.cancel();
    if (duration == Duration.zero) {
      _scroll.jumpTo(bottom);
      return;
    }
    _goingToLatest = true;
    try {
      if (position.pixels - bottom > position.viewportDimension * 2) {
        _scroll.jumpTo(bottom + position.viewportDimension * .6);
      }
      await _scroll.animateTo(
        bottom,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    } finally {
      _goingToLatest = false;
      if (mounted) _scheduleHistoryUpdate();
    }
  }

  Widget _latestButton(int unread) => ValueListenableBuilder(
    valueListenable: _latestButtonVisible,
    builder: (context, visible, _) => AnimatedSwitcher(
      duration: meshMotion(context),
      child: !visible
          ? const SizedBox.shrink()
          : Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                GlassButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  label: tr(
                    context,
                    'К последнему сообщению',
                    'Go to latest message',
                  ),
                  onTap: () => unawaited(_goToLatest()),
                  coveredByModal: _controlsCovered,
                ),
                if (unread > 0)
                  Positioned(
                    top: -11,
                    child: IgnorePointer(child: MeshUnreadBadge(unread)),
                  ),
              ],
            ),
    ),
  );

  void _measureOverlays() {
    if (_measurementPending) return;
    _measurementPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementPending = false;
      if (!mounted) return;
      final header = _headerKey.currentContext?.size?.height ?? 0;
      final footer = _footerKey.currentContext?.size?.height ?? 0;
      if (header == _headerHeight && footer == _footerHeight) return;
      setState(() {
        _headerHeight = header;
        _footerHeight = footer;
      });
    });
  }

  Widget _measure(GlobalKey key, Widget child) =>
      NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          _measureOverlays();
          return false;
        },
        child: SizeChangedLayoutNotifier(key: key, child: child),
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _workspaceVisible = ChatWorkspacePane.of(context)?.visible ?? true;
    _scheduleHistoryUpdate();
    final bundle = DefaultAssetBundle.of(context);
    if (_emojiBundle == bundle) return;
    _emojiBundle = bundle;
    _emojiCatalog = EmojiCatalog.load(bundle);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _untrackViewport?.call();
    _scroll.removeListener(_scheduleHistoryUpdate);
    _history.removeListener(_scheduleHistoryUpdate);
    _attachmentSourceHidden.dispose();
    _latestButtonVisible.dispose();
    _visibleLinkMessages.dispose();
    ++_messageJump;
    _messageScroll?.cancel();
    _history.dispose();
    _scroll.dispose();
    _highlight.dispose();
    _sendFlightAnimation.dispose();
    _reactionAnimation.dispose();
    _sendFlightCompletion?.complete();
    _sendFlightCompletion = null;
    _replyRevealTimer?.cancel();
    _draft.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  double _composerBottom(BuildContext context) {
    final padding = MediaQuery.paddingOf(context).bottom;
    if (Theme.of(context).platform != TargetPlatform.android ||
        MediaQuery.viewInsetsOf(context).bottom > 0) {
      return padding;
    }
    return math.max(34.0, padding);
  }

  Future<void> _revealMessage(
    String? messageId, {
    MessageExcerpt? excerpt,
  }) async {
    final jump = ++_messageJump;
    _messageScroll?.cancel();
    _historyAnchor = null;
    _highlight.value = 0;
    if (messageId == null) {
      _showMessageUnavailable(context);
      return;
    }
    if (_searching) {
      _closeSearch(restorePosition: false);
      await WidgetsBinding.instance.endOfFrame;
    } else {
      _dismissKeyboard();
    }
    if (!mounted || jump != _messageJump) return;
    int? index() {
      final messages = widget.controller.messages(widget.peer.id);
      final i = messages.indexWhere((item) => item.id == messageId);
      return i < 0 ? null : messages.length - i - 1;
    }

    final target = index();
    if (target == null) {
      _showMessageUnavailable(context);
      return;
    }
    if (!_history.isAttached || !_scroll.hasClients) return;
    final obstruction = ChildObstructionExtent(
      leading: _composerBottom(context) + _footerHeight,
      trailing: MediaQuery.paddingOf(context).top + _headerHeight,
    );
    if (meshMotion(context) == Duration.zero) {
      _history.jumpToItem(
        index: target,
        scrollController: _scroll,
        alignment: .5,
        obstruction: obstruction,
      );
    } else {
      final animation = _messageScroll = _history.animateToItem(
        index: index,
        scrollController: _scroll,
        alignment: .5,
        obstruction: obstruction,
        duration: (_) => const Duration(milliseconds: 320),
        curve: (_) => Curves.easeInOutCubic,
      );
      await animation;
      if (!mounted || jump != _messageJump) return;
      if (index() == null) {
        _showMessageUnavailable(context);
        return;
      }
      if (animation.isCanceled) return;
    }
    setState(() {
      _highlighted = messageId;
      _highlightedExcerpt = excerpt;
    });
    unawaited(_highlight.forward(from: 0));
  }

  Future<void> _send(Peer peer) async {
    final originalDraft = _draft.text;
    final text = originalDraft.trim();
    if (_sending || text.isEmpty) return;
    final controller = widget.controller;
    final reply = controller.replyDraft(peer.id);
    if (reply != null && !controller.canUseMessageActions(peer, reply)) return;
    final canvas = _menuBackground.currentContext?.findRenderObject();
    final animate =
        !MediaQuery.disableAnimationsOf(context) &&
        canvas != null &&
        _distanceToLatest < 2 &&
        !_searching;
    final profile = controller.active;
    setState(() => _sending = true);
    try {
      final source = animate
          ? await _input.currentState?.textBounds(canvas)
          : null;
      if (!mounted || controller.active != profile) return;
      final dismissed = _dismissedDraftLink;
      Future<void>? movement;
      final sent = await controller.send(
        peer,
        text,
        reply: reply,
        replyExcerpt: controller.replyDraftExcerpt(peer.id),
        suppressLinkPreview:
            dismissed != null && firstMessageLink(text) == dismissed,
        onQueued: source == null || source.isEmpty
            ? null
            : (message) {
                movement = _animateSentText(message, originalDraft, source);
              },
      );
      if (sent) await movement;
      if (mounted &&
          sent &&
          controller.active == profile &&
          controller.replyDraft(peer.id)?.id == reply?.id) {
        if (reply != null) controller.setReplyDraft(peer.id, null);
        if (_draft.text == originalDraft) {
          _draft.clear();
          _dismissedDraftLink = null;
          controller.setDraft(peer.id, '');
        }
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _finishSentText() {
    setState(() => _sendTextFlight = null);
    _sendFlightCompletion?.complete();
    _sendFlightCompletion = null;
  }

  Future<void> _animateSentText(
    MeshMessage message,
    String draft,
    Rect source,
  ) {
    _sendFlightCompletion?.complete();
    final completion = _sendFlightCompletion = Completer<void>();
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    _sendFlightAnimation
      ..reset()
      ..duration = Duration(milliseconds: ios ? 300 : 250);
    setState(
      () => _sendTextFlight = (
        id: message.id,
        text: message.text,
        draft: draft,
        source: source,
        destination: null,
        ios: ios,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final flight = _sendTextFlight;
      if (!mounted || flight == null || flight.id != message.id) return;
      final target = _sendFlightTarget.currentContext?.findRenderObject();
      final canvas = _menuBackground.currentContext?.findRenderObject();
      if (target is! RenderBox ||
          !target.hasSize ||
          canvas is! RenderBox ||
          !canvas.hasSize) {
        _finishSentText();
        return;
      }
      final destination =
          target.localToGlobal(Offset.zero, ancestor: canvas) & target.size;
      if (destination.isEmpty ||
          !(Offset.zero & canvas.size).overlaps(destination)) {
        _finishSentText();
        return;
      }
      setState(
        () => _sendTextFlight = (
          id: flight.id,
          text: flight.text,
          draft: flight.draft,
          source: flight.source,
          destination: destination,
          ios: flight.ios,
        ),
      );
      unawaited(_sendFlightAnimation.forward());
    });
    return completion.future;
  }

  Widget _sendFlight(
    _SendTextFlight flight,
    MeshStyle style,
  ) => AnimatedBuilder(
    animation: _sendFlightAnimation,
    builder: (_, _) {
      final progress = _sendFlightAnimation.value;
      final destination = flight.destination ?? flight.source;
      const vertical = Cubic(.199194729, .010644531, .279209370, .910253906);
      const horizontal = Cubic(.23, 1, .32, 1);
      final y = vertical.transform(progress);
      final x = flight.ios
          ? horizontal.transform(progress)
          : Curves.easeOut.transform(horizontal.transform(progress));
      final rect = Rect.fromLTRB(
        flight.source.left + (destination.left - flight.source.left) * x,
        flight.source.top + (destination.top - flight.source.top) * y,
        flight.source.right + (destination.right - flight.source.right) * x,
        flight.source.bottom + (destination.bottom - flight.source.bottom) * y,
      );
      return Positioned.fromRect(
        key: const ValueKey('sending-text-flight'),
        rect: rect,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: Align(
              alignment: Alignment.topLeft,
              child: EmojiText(
                flight.text,
                maxLines: 4,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: flight.ios ? 17 - y : 16,
                  height: 1.27,
                  color: style.text,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Future<void> _openOutbox(Peer peer) async {
    final controller = widget.controller;
    final profile = controller.active;
    if (profile == null) return;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    _dismissKeyboard();
    await Navigator.of(context).push(
      meshPageRoute<void>(
        context,
        builder: (_) => RadioOutboxPage(
          controller: controller,
          peer: peer,
          profile: profile,
        ),
      ),
    );
  }

  Future<void> _sendOptions(Peer peer) async {
    final controller = widget.controller;
    final profile = controller.active;
    final box = _sendControl.currentContext?.findRenderObject();
    if (profile == null || box is! RenderBox || !box.hasSize || _sending) {
      return;
    }
    final draft = _draft.text;
    final text = draft.trim();
    final limit = controller.limit(peer);
    final reply = controller.replyDraft(peer.id);
    final canQueue =
        controller.canSendTo(peer) &&
        text.isNotEmpty &&
        limit != null &&
        utf8.encode(text).length <= limit &&
        (reply == null || controller.canDraftMessageReply(peer, reply));
    final hasOutbox = controller.outboxFor(peer.id).isNotEmpty;
    if (!canQueue && !hasOutbox) return;
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    final anchor = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    Uint8List? backdrop;
    if (useIosControls && !MediaQuery.highContrastOf(context)) {
      try {
        backdrop = await _glassBackdrop();
      } on Exception {
        // The regular menu surface remains available if the snapshot fails.
      }
    }
    if (!mounted || controller.active != profile) return;
    final action = await showRadioSendMenu(
      context,
      button: anchor,
      canQueue: canQueue,
      hasOutbox: hasOutbox,
      draft: text,
      backdrop: backdrop,
    );
    if (!mounted || controller.active != profile || action == null) return;
    if (action == RadioSendOption.openOutbox) {
      await _openOutbox(peer);
      return;
    }
    final suppress =
        _dismissedDraftLink != null &&
        firstMessageLink(text) == _dismissedDraftLink;
    setState(() => _sending = true);
    final saved = await controller.enqueueRadioMessage(
      peer,
      text,
      reply: reply,
      excerpt: controller.replyDraftExcerpt(peer.id),
      suppressLinkPreview: suppress,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (controller.active != profile) return;
    if (!saved) {
      _notice(
        tr(
          context,
          'Не удалось сохранить в очередь',
          'Could not add to outbox',
        ),
      );
      return;
    }
    if (_draft.text == draft &&
        controller.replyDraft(peer.id)?.id == reply?.id) {
      if (reply != null) controller.setReplyDraft(peer.id, null);
      _dismissedDraftLink = null;
      _updateDraft(peer, '');
    }
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      await _openOutbox(peer);
    } else {
      _notice(
        tr(context, 'Добавлено в очередь рации', 'Added to radio outbox'),
      );
    }
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Rect? _attachmentButtonRect() {
    if (_attachmentButton.currentContext?.findRenderObject()
        case final RenderBox box when box.attached && box.hasSize) {
      return Rect.fromCenter(
        center: box.localToGlobal(box.size.center(Offset.zero)),
        width: 40,
        height: 40,
      );
    }
    return null;
  }

  Future<void> _attach(Peer peer) async {
    final controller = widget.controller;
    final radio = controller.active;
    final budget = controller.limit(peer);
    if (_sending || _attachmentOpen || radio == null || budget == null) return;
    final sourceRect =
        !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.iOS &&
            !MediaQuery.disableAnimationsOf(context)
        ? _attachmentButtonRect()
        : null;
    if (sourceRect != null) _attachmentSourceHidden.value = true;
    _dismissKeyboard();
    setState(() => _attachmentOpen = true);
    final contacts = [
      for (final node in controller.nodes)
        (peer: node, link: controller.shareContactAttachment(node, budget)),
    ];
    final String? text;
    try {
      text = await pickChatAttachment(
        context,
        contacts: contacts,
        controller: controller,
        initialPosition: controller.cache?.localPosition,
        paperclip: sourceRect == null
            ? null
            : (
                start: sourceRect,
                viewport: MediaQuery.sizeOf(context),
                currentRect: _attachmentButtonRect,
                setHidden: (hidden) {
                  if (mounted) _attachmentSourceHidden.value = hidden;
                },
              ),
        locationNodes: [
          for (final contact in contacts)
            if (controller.nodeObservation(contact.peer.id)?.position
                case final position?)
              (name: contact.peer.name, position: position),
        ],
      );
    } finally {
      if (mounted) setState(() => _attachmentOpen = false);
    }
    if (!mounted || text == null || _sending) return;
    if (controller.active != radio || !controller.connected) {
      _notice(
        tr(
          context,
          'Рация отключилась. Подключите её и повторите отправку.',
          'The radio disconnected. Reconnect it and send again.',
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      if (!await controller.sendAttachment(peer, text) && mounted) {
        _notice(
          tr(
            context,
            'Не удалось отправить вложение',
            'Could not send attachment',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showQuickPhraseList(Peer peer) async {
    if (!_quickPhrasesOpen ||
        _controlsCovered ||
        _sending ||
        _route?.isCurrent == false) {
      return;
    }
    final controller = widget.controller;
    final radio = controller.active;
    _dismissKeyboard();
    setState(() => _quickPhrasePickerOpen = true);
    final String? phrase;
    try {
      phrase = await pickQuickPhrase(context, controller.store);
    } finally {
      if (mounted) {
        setState(() {
          _quickPhrasePickerOpen = false;
          _quickPhrasesOpen = false;
        });
      }
    }
    if (!mounted || controller.active != radio || phrase == null) return;
    _insertQuickPhrase(peer, phrase);
  }

  void _insertQuickPhrase(Peer peer, String phrase) {
    if (_sending) return;
    final draft = _draft.value;
    final selection =
        draft.selection.isValid && draft.selection.end <= draft.text.length
        ? draft.selection
        : TextSelection.collapsed(offset: draft.text.length);
    final before = draft.text.substring(0, selection.start);
    final after = draft.text.substring(selection.end);
    final separator = RegExp(r'\s');
    final prefix =
        selection.isCollapsed &&
            before.isNotEmpty &&
            !separator.hasMatch(before[before.length - 1])
        ? ' '
        : '';
    final suffix =
        selection.isCollapsed &&
            after.isNotEmpty &&
            !separator.hasMatch(after[0])
        ? ' '
        : '';
    final text = '$before$prefix$phrase$suffix$after';
    _updateDraft(
      peer,
      text,
      cursor: before.length + prefix.length + phrase.length + suffix.length,
    );
    _collapseQuickPhrases();
  }

  void _collapseQuickPhrases() {
    if (_quickPhrasesOpen) setState(() => _quickPhrasesOpen = false);
  }

  void _updateDraft(Peer peer, String text, {int? cursor}) {
    _draft.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor ?? text.length),
    );
    widget.controller.setDraft(peer.id, text);
    setState(() {});
  }

  Future<void> _forwardText(Peer peer, MeshMessage message) async {
    final controller = widget.controller;
    final profile = controller.active;
    final text = '${_quoteAuthor(context, message)}:\n${message.text}';
    final targets = await pickForwardChats(context, controller);
    if (!mounted || targets == null || controller.active != profile) return;
    if (targets.saved &&
        !await controller.toggleSavedMessage(peer, message, keepSaved: true) &&
        mounted) {
      _notice(
        tr(
          context,
          'Не удалось сохранить сообщение',
          'Could not save the message',
        ),
      );
    }
    if (!mounted || controller.active != profile) return;
    final chats = targets.chats.where(controller.canSendTo).toList();
    for (final target in chats) {
      final prior = controller.draft(target.id);
      final draft = prior.isEmpty ? text : '$prior\n\n$text';
      if (target.id == peer.id) {
        _updateDraft(peer, draft);
      } else {
        controller.setDraft(target.id, draft);
      }
    }
    if (chats.length == 1 && chats.single.id != peer.id) {
      await showMeshChat(context, controller, chats.single);
    } else if (chats.length > 1) {
      _notice(tr(context, 'Черновики подготовлены', 'Drafts prepared'));
    }
  }

  Future<void> _quoteSelectedText(Peer peer, MeshMessage message) async {
    final controller = widget.controller;
    final profile = controller.active;
    final excerpt = await selectMessageExcerpt(context, message.text);
    if (!mounted || excerpt == null || controller.active != profile) return;
    if (controller.canDraftMessageReply(peer, message)) {
      _selectReply(peer, message, excerpt: excerpt);
      return;
    }
    final limit =
        (controller.limit(peer) ?? 0) -
        utf8.encode(_draft.text.trim()).length -
        utf8.encode('«»\n').length;
    final quote = StringBuffer();
    var used = 0;
    for (final character in excerpt.text.trim().characters) {
      used += utf8.encode(character).length;
      if (used > math.min(64, limit)) break;
      quote.write(character);
    }
    if (quote.isEmpty) {
      _notice(
        tr(
          context,
          'Для цитаты нет места в сообщении',
          'No room for a quote in this message',
        ),
      );
      return;
    }
    final prefix = '«$quote»\n';
    _updateDraft(peer, '$prefix${_draft.text}', cursor: prefix.length);
  }

  bool get _sharedContextIsCurrent {
    final radio = widget.controller.active;
    return _route?.isCurrent != false &&
        radio != null &&
        radioKey(radio) == _radio;
  }

  Future<void> _useContact(String link, {required bool openChat}) async {
    if (!mounted || _openingSharedLink || !_sharedContextIsCurrent) return;
    _openingSharedLink = true;
    try {
      final controller = widget.controller;
      final contact = controller.contactAttachment(link);
      if (contact != null &&
          contact.network == controller.active?.network &&
          controller.isOwnChat(contact.id, publicKey: contact.publicKey)) {
        _dismissKeyboard();
        await showSavedChat(context, controller);
        return;
      }
      final wasKnown = controller.findContactCode(link) != null;
      final peer = await controller.importContactAttachment(link);
      if (!mounted || !_sharedContextIsCurrent) return;
      if (peer == null) {
        _notice(
          tr(
            context,
            'Контакт недоступен для выбранной рации',
            'This contact is unavailable for the selected radio',
          ),
        );
        return;
      }
      if (!wasKnown) unawaited(playMeshHaptic(MeshHaptic.success));
      if (!openChat) {
        _dismissKeyboard();
        await _openPeerProfile(peer);
      } else if (controller.canSendTo(peer)) {
        if (peer.id == widget.peer.id) {
          _input.currentState?.focusInput();
        } else {
          _dismissKeyboard();
          await showMeshChat(context, controller, peer);
        }
      }
    } catch (_) {
      if (mounted && _sharedContextIsCurrent) {
        _notice(
          tr(
            context,
            'Не удалось добавить контакт. Проверьте соединение с рацией и ключ узла.',
            'Could not add contact. Check the radio connection and node key.',
          ),
        );
      }
    } finally {
      _openingSharedLink = false;
    }
  }

  Future<void> _joinSharedChannel(ChannelInvitation invite) async {
    if (!mounted || _openingSharedLink || !_sharedContextIsCurrent) return;
    final controller = widget.controller;
    if (controller.active?.network != invite.network) {
      _notice(
        tr(
          context,
          'Выберите рацию сети ${controller.label(invite.network)}',
          'Select a ${controller.label(invite.network)} radio',
        ),
      );
      return;
    }
    if (!controller.channelActions.contains(ChannelAction.invitation)) {
      _notice(
        tr(
          context,
          'Подключите рацию, чтобы открыть канал',
          'Connect the radio to open the channel',
        ),
      );
      return;
    }
    _openingSharedLink = true;
    try {
      final result = await controller.addChannel((
        action: ChannelAction.invitation,
        name: invite.name ?? '',
        secret: '',
        invitation: invite.link,
      ));
      if (!mounted || !_sharedContextIsCurrent) return;
      if (result.peer.id != widget.peer.id) {
        _dismissKeyboard();
        await showMeshChat(context, controller, result.peer);
      }
    } catch (_) {
      if (mounted && _sharedContextIsCurrent) {
        _notice(
          tr(context, 'Не удалось открыть канал', 'Could not open the channel'),
        );
      }
    } finally {
      _openingSharedLink = false;
    }
  }

  Future<void> _retry(Peer peer, MeshMessage message) async {
    final controller = widget.controller;
    final radio = controller.active;
    final sent = await controller.retryMessage(peer, message.id);
    if (!mounted || controller.active != radio) return;
    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Не удалось повторить отправку',
              'Could not resend message',
            ),
          ),
        ),
      );
      return;
    }
    if (!message.isAttachment && _draft.text.trim() == message.text) {
      _draft.clear();
      controller.setDraft(peer.id, '');
    }
    final reply = controller.replyDraft(peer.id);
    if (!message.isAttachment &&
        reply != null &&
        controller.referenceFor(reply) == message.replyTo) {
      controller.setReplyDraft(peer.id, null);
    }
  }

  void _dismissKeyboard() {
    _input.currentState?.dismissKeyboard();
    _iosSearch.currentState?.dismissKeyboard();
    FocusScope.of(context).unfocus();
  }

  void _closeSearch({bool restorePosition = true}) {
    _dismissKeyboard();
    final offset = _searchOriginOffset;
    _searchOriginOffset = null;
    setState(() {
      _search.clear();
      _searchFilters = const MessageSearchFilters();
      _searching = false;
    });
    if (restorePosition && offset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _searching || !_scroll.hasClients) return;
        final position = _scroll.position;
        _scroll.jumpTo(
          offset.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      });
    }
  }

  void _beginMessageSearch() {
    if (_searching) return;
    if (_scroll.hasClients) _searchOriginOffset = _scroll.offset;
    _dismissKeyboard();
    setState(() => _searching = true);
  }

  void _selectReply(Peer peer, MeshMessage message, {MessageExcerpt? excerpt}) {
    final controller = widget.controller;
    final supported = excerpt == null
        ? controller.canUseMessageActions(peer, message)
        : controller.canDraftMessageReply(peer, message);
    if (!supported) return;
    // Android introduces the first accessory as the keyboard starts moving.
    // A physical keyboard or disabled IME can leave the inset at zero.
    if (Theme.of(context).platform == TargetPlatform.android &&
        MediaQuery.viewInsetsOf(context).bottom == 0 &&
        controller.replyDraft(peer.id) == null &&
        !MediaQuery.disableAnimationsOf(context)) {
      _replyRevealTimer = Timer(
        const Duration(milliseconds: 200),
        _revealReplyAccessory,
      );
    }
    if (_searching) {
      _closeSearch();
    }
    _linkBehindReply = firstMessageLink(_draft.text);
    controller.setReplyDraft(peer.id, message, excerpt: excerpt);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _input.currentState?.focusInput();
    });
  }

  String? _previewMessageId;

  // Capture only the chat before inserting the overlay and its controls.
  // The downsampled image isolates UIKit glass from the foreground.
  Future<Uint8List?> _glassBackdrop() =>
      captureMessageMenuBackdrop(_menuBackground);

  Future<void> _messageMenu(
    Peer peer,
    MeshMessage message,
    Rect anchor,
    Widget bubble,
    List<ChatReaction> reactions,
  ) async {
    final controller = widget.controller;
    final profile = controller.active;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    _dismissKeyboard();
    if (_menuVisible) return;
    setState(() {
      _menuVisible = true;
      _previewMessageId = message.id;
    });
    final MessageMenuChoice? choice;
    try {
      Uint8List? backdrop;
      if (useIosControls && !MediaQuery.highContrastOf(context)) {
        try {
          backdrop = await _glassBackdrop();
        } on Exception {
          // The menu also works with the system's solid accessibility surface.
        }
        if (!mounted) return;
      }
      choice = await showMessageMenu(
        backdrop: backdrop,
        context: context,
        anchor: overlay.globalToLocal(anchor.topLeft) & anchor.size,
        canReact: controller.canChooseReaction(peer, message),
        recentReactions: controller.recentReactionEmojis,
        canReply: controller.canUseMessageActions(peer, message),
        saved: controller.isMessageSaved(message),
        pinned: profile == null
            ? null
            : controller.pinnedMessageId(peer.id) == message.id,
        canForward:
            profile != null &&
            message.text.trim().isNotEmpty &&
            controller.conversations.any(controller.canSendTo),
        canQuoteText:
            profile != null &&
            message.text.trim().isNotEmpty &&
            controller.canSendTo(peer),
        outgoing: message.outgoing,
        bubble: bubble,
        reactions: reactions,
        onOpenProfile: _openPeerProfile,
        details: MessageDetails(
          message: message,
          peer: peer,
          radio: controller.active,
          networkLabel: switch (controller.active) {
            final Radio radio => controller.label(radio.network),
            null => null,
          },
          nodeName: controller.nodeName,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _menuVisible = false;
          _previewMessageId = null;
        });
      }
    }
    if (!mounted || choice == null) return;
    final value = choice.value;
    if (value == 'reply') {
      _selectReply(peer, message);
    } else if (value == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.text));
    } else if (value == 'forward-text' && controller.active == profile) {
      await _forwardText(peer, message);
    } else if (value == 'quote-text' && controller.active == profile) {
      await _quoteSelectedText(peer, message);
    } else if (value == 'pin' && controller.active == profile) {
      controller.setPinnedMessage(
        peer.id,
        controller.pinnedMessageId(peer.id) == message.id ? null : message.id,
      );
    } else if (value == 'saved') {
      if (!await controller.toggleSavedMessage(peer, message) && mounted) {
        _notice(
          tr(
            context,
            'Не удалось обновить Избранное',
            'Could not update Saved Messages',
          ),
        );
      }
    } else if (controller.active == profile) {
      await _react(peer, message, value, source: choice.reactionSource);
    }
  }

  Future<void> _react(
    Peer peer,
    MeshMessage message,
    String emoji, {
    Rect? source,
  }) async {
    final controller = widget.controller;
    if (!controller.connected) {
      final radio = controller.active;
      if (radio == null || !controller.canChooseReaction(peer, message)) return;
      await controller.connect(radio);
      if (!mounted || controller.active != radio) return;
    }
    final radio = controller.active;
    final key = reactionEmojiKey(emoji);
    final canvas = _menuBackground.currentContext?.findRenderObject();
    final moves =
        source != null &&
        !MediaQuery.disableAnimationsOf(context) &&
        _route?.isCurrent == true &&
        canvas is RenderBox &&
        canvas.hasSize &&
        _reactionFlight == null &&
        !controller
            .reactionsFor(message)
            .any((reaction) => reaction.own && reaction.emojiKey == key);
    final flight = moves
        ? _ReactionFlight(
            message.id,
            emoji,
            canvas.globalToLocal(source.topLeft) & source.size,
          )
        : null;
    if (flight != null) setState(() => _reactionFlight = flight);
    final sent = await controller.react(peer, message, emoji);
    if (!mounted) return;
    if (flight != null) {
      if (sent) {
        setState(() => flight.accepted = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || _reactionFlight != flight) return;
        final target = _reactionTarget.currentContext?.findRenderObject();
        if (controller.active == radio &&
            _route?.isCurrent == true &&
            target is RenderBox &&
            target.hasSize &&
            canvas is RenderBox &&
            canvas.attached) {
          final destination = MatrixUtils.transformRect(
            target.getTransformTo(canvas),
            Offset.zero & target.size,
          );
          if (!(Offset.zero & canvas.size).overlaps(destination)) {
            _clearReactionFlight();
            return;
          }
          setState(() => flight.destination = destination);
          _reactionAnimation.duration = Duration(
            milliseconds: Theme.of(context).platform == TargetPlatform.iOS
                ? 200
                : 350,
          );
          unawaited(_reactionAnimation.forward(from: 0));
          return;
        }
      }
      _clearReactionFlight();
    }
    if (!sent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Не удалось отправить реакцию',
              'Could not send reaction',
            ),
          ),
        ),
      );
    }
  }

  void _clearReactionFlight() {
    if (mounted) setState(() => _reactionFlight = null);
  }

  Widget _movingReaction(_ReactionFlight flight, {required bool ios}) =>
      AnimatedBuilder(
        animation: _reactionAnimation,
        builder: (_, _) {
          final target = flight.destination ?? flight.source;
          final progress = flight.destination == null
              ? 0.0
              : _reactionAnimation.value;
          const standard = Cubic(.25, .1, .25, 1);
          final time = ios ? progress : standard.transform(progress);
          final x = ios ? time : const Cubic(.23, 1, .32, 1).transform(time);
          final y = ios ? time : standard.transform(time);
          final origin = flight.source.center;
          final landing = target.center;
          final rise = (landing - origin).distance < 5
              ? 0.0
              : 30 + (landing.dy - origin.dy) / 2;
          final center = Offset(
            origin.dx + (landing.dx - origin.dx) * x,
            origin.dy +
                (landing.dy - origin.dy) * y -
                (ios ? 4 * time * (1 - time) * rise : 0),
          );
          final size = Size.lerp(flight.source.size, target.size, x)!;
          return Positioned.fromRect(
            key: const ValueKey('reaction-flight'),
            rect: center - size.center(Offset.zero) & size,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: FittedBox(
                  child: Text(
                    flight.emoji,
                    style: emojiGlyphStyle(const TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ),
          );
        },
      );

  Future<void> _profile(Peer peer) async {
    final route = meshPageRoute<bool>(
      context,
      builder: (_) =>
          MeshChatProfile(controller: widget.controller, peer: peer),
    );
    final result = await Navigator.push(context, route);
    await route.completed;
    if (result == true && mounted) _beginMessageSearch();
  }

  Future<void> _editSearchFilters(List<MeshMessage> messages) async {
    _dismissKeyboard();
    final filters = await showMessageSearchFilters(
      context,
      controller: widget.controller,
      messages: messages,
      filters: _searchFilters,
    );
    if (mounted && filters != null) setState(() => _searchFilters = filters);
  }

  Future<void> _jumpToDate(List<MeshMessage> messages) async {
    if (messages.isEmpty) return;
    _dismissKeyboard();
    final first = DateUtils.dateOnly(messages.first.time);
    final last = DateUtils.dateOnly(messages.last.time);
    final date = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDate: last,
    );
    if (!mounted || date == null) return;
    final history = widget.controller.messages(widget.peer.id);
    final message = history
        .where((item) => !item.time.isBefore(date))
        .firstOrNull;
    await _revealMessage((message ?? history.lastOrNull)?.id);
  }

  Widget _chatSearchEditor() {
    final placeholder = tr(context, 'Поиск в чате', 'Search messages');
    if (useIosControls) {
      return MeshSearchEditor(
        placeholder: placeholder,
        controller: _search,
        focusNode: _searchFocus,
        iosKey: _iosSearch,
        initialText: _search.text,
        onChanged: (text) {
          if (_searching && text != _search.text) {
            setState(() => _search.text = text);
          }
        },
        onDismissKeyboard: _dismissKeyboard,
      );
    }
    return GlassSurface(
      radius: 100,
      child: TextField(
        autofocus: true,
        controller: _search,
        focusNode: _searchFocus,
        onTapOutside: (_) => _dismissKeyboard(),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: placeholder,
          border: InputBorder.none,
          suffixIcon: IconButton(
            tooltip: tr(context, 'Закрыть поиск', 'Close search'),
            onPressed: _closeSearch,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ),
    );
  }

  Widget _pinnedMessage(Peer peer, String id, MeshMessage? message) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
    child: GlassSurface(
      radius: 18,
      child: Row(
        children: [
          Expanded(
            child: ListTile(
              visualDensity: VisualDensity.compact,
              leading: const Icon(Icons.push_pin_rounded, size: 18),
              title: Text(
                tr(context, 'Закреплённое сообщение', 'Pinned message'),
              ),
              subtitle: Text(
                message?.text ??
                    tr(
                      context,
                      'Вне локальной истории',
                      'Outside local history',
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => unawaited(_revealMessage(id)),
            ),
          ),
          IconButton(
            tooltip: tr(context, 'Открепить', 'Unpin message'),
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => widget.controller.setPinnedMessage(peer.id, null),
          ),
        ],
      ),
    ),
  );

  Future<void> _openPeerProfile(Peer peer) {
    if (peer.id == widget.peer.id) return _profile(peer);
    return Navigator.of(context).push<void>(
      meshPageRoute<void>(
        context,
        builder: (_) => MeshChatProfile(
          controller: widget.controller,
          peer: peer,
          openNewChat: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _emojiCatalog,
    builder: (context, snapshot) => _buildChat(snapshot.data),
  );

  Widget _buildChat(EmojiCatalog? emojiCatalog) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final peer = controller.cache?.peers[widget.peer.id] ?? widget.peer;
      final style = MeshStyle.of(context);
      final outgoing = _draft.text.trim();
      final draftLink =
          chatPosition(outgoing) == null &&
              _sharedChatLink(controller, outgoing) == null
          ? firstMessageLink(outgoing)
          : null;
      final previewLink = draftLink == _dismissedDraftLink ? null : draftLink;
      final bytes = utf8.encode(outgoing).length;
      final characters = outgoing.characters.length;
      final limit = controller.limit(peer);
      final reply = controller.replyDraft(peer.id);
      final replyExcerpt = controller.replyDraftExcerpt(peer.id);
      final canCompose = controller.canOpenChat(peer);
      final canSend = controller.canSendTo(peer);
      final canQueue =
          canSend &&
          !_sending &&
          bytes > 0 &&
          limit != null &&
          bytes <= limit &&
          (reply == null || controller.canDraftMessageReply(peer, reply));
      final send =
          controller.connected &&
          canSend &&
          !_sending &&
          bytes > 0 &&
          (reply == null || controller.canUseMessageActions(peer, reply)) &&
          limit != null &&
          bytes <= limit;
      final query = _search.text.trim().toLowerCase();
      final history = controller.messages(peer.id);
      final pin = controller.pinnedMessageId(peer.id);
      final messages = _searching
          ? history
                .where(
                  (message) =>
                      _searchFilters.accepts(controller, message, query),
                )
                .toList()
          : history;

      final padding = MediaQuery.paddingOf(context);
      final top = padding.top;
      final bottom = _searching ? padding.bottom : _composerBottom(context);
      final historyBottom = bottom + (_searching ? 0 : _footerHeight) + 8;
      _measureOverlays();
      final unread = controller.cache?.unread[peer.id] ?? 0;
      _configureHistory(
        messages,
        controller.cache?.unreadIds(peer.id) ?? const {},
      );
      final unreadBoundary = _searching ? null : _unreadBoundary;
      final authorGroups = peer.channel
          ? _authorGroups(messages, unreadBoundary)
          : null;

      return Scaffold(
        body: RepaintBoundary(
          key: _menuBackground,
          child: ImageFiltered(
            enabled:
                _menuVisible && !MediaQuery.accessibleNavigationOf(context),
            imageFilter: ImageFilter.blur(
              sigmaX: 18,
              sigmaY: 18,
              tileMode: TileMode.clamp,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _ContourPaper(style)),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _collapseQuickPhrases();
                    _dismissKeyboard();
                  },
                  child: messages.isEmpty
                      ? Center(
                          child: GlassSurface(
                            radius: 15,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              child: Text(
                                _searching
                                    ? tr(
                                        context,
                                        'Ничего не найдено',
                                        'No results',
                                      )
                                    : tr(
                                        context,
                                        'Начало переписки',
                                        'Start of conversation',
                                      ),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: style.secondary,
                                ),
                              ),
                            ),
                          ),
                        )
                      : ChatMessageList(
                          controller: _scroll,
                          listController: _history,
                          physics: const _ChatScrollPhysics(),
                          insets: EdgeInsets.fromLTRB(
                            11,
                            top + _headerHeight + 8,
                            11,
                            historyBottom,
                          ),
                          avatars: authorGroups == null || authorGroups.isEmpty
                              ? null
                              : ChannelAuthorAvatars(
                                  bottomInset: historyBottom,
                                  history: _history,
                                  scroll: _scroll,
                                  groups: authorGroups,
                                  messageCount: messages.length,
                                  authorFor: controller.messageAuthor,
                                  onOpenProfile: _openPeerProfile,
                                ),
                          itemCount: messages.length,
                          findChildIndexCallback: (key) {
                            if (key is! ValueKey<String>) return null;
                            final i = messages.indexWhere(
                              (message) => message.id == key.value,
                            );
                            return i < 0 ? null : messages.length - i - 1;
                          },
                          itemBuilder: (context, index) {
                            final i = messages.length - index - 1;
                            final item = messages[i];
                            final previous = i == 0 ? null : messages[i - 1];
                            final startsUnread = item.id == unreadBoundary;
                            final next = i == messages.length - 1
                                ? null
                                : messages[i + 1];
                            final reactions = [
                              for (final reaction in controller.reactionsFor(
                                item,
                              ))
                                (
                                  reaction: reaction,
                                  author: controller.reactionAuthor(reaction),
                                ),
                            ];
                            final quote = controller.referencedMessage(
                              peer.id,
                              item.replyTo,
                            );
                            final draftExcerpt = reply?.id == item.id
                                ? replyExcerpt
                                : null;
                            final revealedExcerpt = _highlighted == item.id
                                ? _highlightedExcerpt
                                : null;
                            final movingText = _sendTextFlight?.id == item.id;
                            final emoji = emojiCatalog?.singleEmoji(item.text);
                            final shared = _sharedChatLink(
                              controller,
                              item.text,
                            );
                            final contact = shared?.contact;
                            final invitation = shared?.channel;
                            final location = shared == null
                                ? chatPosition(item.text)
                                : null;
                            final knownContact = contact == null
                                ? null
                                : controller.findContactCode(shared!.link);
                            final link = firstMessageLink(
                              shared?.caption ?? item.text,
                            );
                            Widget? card(bool interactive) {
                              if (contact != null) {
                                final canOpen =
                                    interactive &&
                                    contact.network ==
                                        controller.active?.network;
                                final canWrite = knownContact != null
                                    ? controller.canSendTo(knownContact)
                                    : contact.type == null || contact.type == 1;
                                final isMeshtastic =
                                    contact.network == 'meshtastic';
                                final localShortName = controller
                                    .cache
                                    ?.identities[knownContact?.id]
                                    ?.shortName
                                    ?.trim();
                                return _ContactCard(
                                  name: knownContact?.name ?? contact.name,
                                  id: isMeshtastic
                                      ? meshtasticNodeAddress(contact.id) ??
                                            contact.id
                                      : contact.id,
                                  shortName: isMeshtastic
                                      ? localShortName?.isNotEmpty == true
                                            ? localShortName
                                            : contact.shortName?.trim()
                                      : null,
                                  onOpenProfile: canOpen
                                      ? () => unawaited(
                                          _useContact(
                                            shared!.link,
                                            openChat: false,
                                          ),
                                        )
                                      : null,
                                  onWrite: canOpen && canWrite
                                      ? () => unawaited(
                                          _useContact(
                                            shared!.link,
                                            openChat: true,
                                          ),
                                        )
                                      : null,
                                );
                              }
                              if (invitation != null) {
                                final network = controller.label(
                                  invitation.network,
                                );
                                final open = !interactive
                                    ? null
                                    : () => unawaited(
                                        _joinSharedChannel(invitation),
                                      );
                                return _ContactCard(
                                  name:
                                      invitation.name ??
                                      tr(
                                        context,
                                        'Канал $network',
                                        '$network channel',
                                      ),
                                  id: network,
                                  channel: true,
                                  actionLabel: tr(
                                    context,
                                    'Присоединиться к каналу',
                                    'Join channel',
                                  ),
                                  onOpenProfile: open,
                                  onWrite: open,
                                );
                              }
                              if (location != null && !location.standalone) {
                                return MeshLocationPreview(
                                  position: location.point,
                                  loadTiles: false,
                                  attributionTextOnly: true,
                                );
                              }
                              return null;
                            }

                            Widget bubble([ValueChanged<Rect>? onMenu]) {
                              _Bubble content(Widget? attachment) => _Bubble(
                                item: item,
                                emoji: emoji,
                                displayedText: shared?.caption,
                                hideText: shared?.caption.isEmpty == true,
                                standalonePosition: location?.standalone == true
                                    ? location?.point
                                    : null,
                                preview: attachment == null || onMenu != null
                                    ? attachment
                                    : IgnorePointer(child: attachment),
                                link: link,
                                channel: peer.channel,
                                joinsPrevious:
                                    !startsUnread && _joins(previous, item),
                                joinsNext:
                                    next?.id != unreadBoundary &&
                                    _joins(item, next),
                                quoted: quote,
                                flightTarget: movingText
                                    ? _sendFlightTarget
                                    : null,
                                reactionTarget:
                                    onMenu != null &&
                                        _reactionFlight?.messageId == item.id
                                    ? (
                                        target: _reactionTarget,
                                        emojiKey: reactionEmojiKey(
                                          _reactionFlight!.emoji,
                                        ),
                                      )
                                    : null,
                                highlightedExcerpt:
                                    draftExcerpt ?? revealedExcerpt,
                                excerptAnimation:
                                    draftExcerpt == null &&
                                        revealedExcerpt != null
                                    ? _highlightOpacity
                                    : null,
                                onQuote: onMenu == null || item.replyTo == null
                                    ? null
                                    : () => unawaited(
                                        _revealMessage(
                                          quote?.id,
                                          excerpt: item.replyExcerpt,
                                        ),
                                      ),
                                highlight:
                                    onMenu != null && _highlighted == item.id
                                    ? _highlightOpacity
                                    : null,
                                reactions: reactions,
                                onMenu: onMenu,
                                onAuthor: onMenu == null
                                    ? null
                                    : () => openChannelAuthorProfile(
                                        context,
                                        item,
                                        controller.messageAuthor(item),
                                        _openPeerProfile,
                                      ),
                                onReact:
                                    onMenu != null &&
                                        controller.canReact(peer, item)
                                    ? (emoji) =>
                                          unawaited(_react(peer, item, emoji))
                                    : null,
                                onRetry:
                                    canSend &&
                                        item.delivery.canRetry &&
                                        !controller.isOutboxAttempt(item.id) &&
                                        onMenu != null
                                    ? () => unawaited(_retry(peer, item))
                                    : null,
                              );
                              if (shared != null ||
                                  location != null ||
                                  link == null ||
                                  item.suppressLinkPreview ||
                                  !canFetchMessageLink(link)) {
                                return content(card(onMenu != null));
                              }
                              if (onMenu == null) {
                                return MessageLinkPreview(
                                  uri: link,
                                  foreground: style.text,
                                  autoLoad: false,
                                  builder: content,
                                );
                              }
                              return ValueListenableBuilder(
                                valueListenable: _visibleLinkMessages,
                                builder: (_, visible, _) => MessageLinkPreview(
                                  uri: link,
                                  foreground: style.text,
                                  autoLoad:
                                      _canPreviewLinks &&
                                      visible.contains(item.id),
                                  builder: content,
                                ),
                              );
                            }

                            final messageBubble = bubble(
                              (anchor) => unawaited(
                                _messageMenu(
                                  peer,
                                  item,
                                  anchor,
                                  bubble(),
                                  reactions,
                                ),
                              ),
                            );
                            return Column(
                              key: ValueKey(item.id),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (previous == null ||
                                    !DateUtils.isSameDay(
                                      previous.time,
                                      item.time,
                                    ))
                                  _day(item.time, style),
                                if (startsUnread)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      bottom: 5,
                                    ),
                                    child: _unreadDivider(style),
                                  ),
                                _ReplySwipe(
                                  key: item.outgoing
                                      ? null
                                      : _incomingRows.putIfAbsent(
                                          item.id,
                                          GlobalKey.new,
                                        ),
                                  onReply:
                                      !_searching &&
                                          controller.canUseMessageActions(
                                            peer,
                                            item,
                                          )
                                      ? () => _selectReply(peer, item)
                                      : null,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: peer.channel && !item.outgoing
                                          ? ChannelAuthorAvatars.gutter
                                          : 0,
                                    ),
                                    child: Opacity(
                                      opacity: _previewMessageId == item.id
                                          ? 0
                                          : 1,
                                      child: _searching
                                          ? Semantics(
                                              button: true,
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTap: () => unawaited(
                                                  _revealMessage(item.id),
                                                ),
                                                child: IgnorePointer(
                                                  child: messageBubble,
                                                ),
                                              ),
                                            )
                                          : movingText
                                          ? IgnorePointer(
                                              child: FadeTransition(
                                                opacity: _sendTargetOpacity,
                                                child: messageBubble,
                                              ),
                                            )
                                          : messageBubble,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: top + _headerHeight + 8,
                  child: MeshScrollEdge(top: true, tint: style.canvas),
                ),
                if (!_searching)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: bottom + _footerHeight + 9,
                    child: MeshScrollEdge(top: false, tint: style.canvas),
                  ),
                Positioned(
                  top: top,
                  left: padding.left,
                  right: padding.right,
                  child: _measure(
                    _headerKey,
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_searching) ...[
                          _heading(peer, style),
                          if (pin != null)
                            _pinnedMessage(
                              peer,
                              pin,
                              history
                                  .where((item) => item.id == pin)
                                  .firstOrNull,
                            ),
                        ] else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                            child: Row(
                              children: [
                                Expanded(child: _chatSearchEditor()),
                                const SizedBox(width: 6),
                                GlassButton(
                                  icon: Icons.tune_rounded,
                                  label: tr(
                                    context,
                                    'Фильтры сообщений',
                                    'Message filters',
                                  ),
                                  primary: !_searchFilters.isEmpty,
                                  onTap: () =>
                                      unawaited(_editSearchFilters(history)),
                                ),
                                const SizedBox(width: 6),
                                GlassButton(
                                  icon: Icons.calendar_today_rounded,
                                  label: tr(
                                    context,
                                    'Перейти к дате',
                                    'Go to date',
                                  ),
                                  onTap: history.isEmpty
                                      ? null
                                      : () => unawaited(_jumpToDate(history)),
                                ),
                                if (useIosControls) ...[
                                  const SizedBox(width: 6),
                                  GlassButton(
                                    icon: Icons.close_rounded,
                                    label: tr(
                                      context,
                                      'Закрыть поиск',
                                      'Close search',
                                    ),
                                    onTap: _closeSearch,
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!_searching && messages.isNotEmpty)
                  PositionedDirectional(
                    bottom: historyBottom + 7,
                    end: padding.right + 14,
                    child: _latestButton(unread),
                  ),
                if (!_searching)
                  Positioned(
                    bottom: bottom,
                    left: padding.left,
                    right: padding.right,
                    child: _measure(
                      _footerKey,
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 7, 12, 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!canCompose)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  tr(
                                    context,
                                    'Отправка недоступна',
                                    'Sending unavailable',
                                  ),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: style.secondary,
                                  ),
                                ),
                              )
                            else ...[
                              _composerAccessories(
                                peer,
                                canSend: canSend,
                                limit: limit,
                                bytes: bytes,
                                characters: characters,
                              ),
                              _composerControls(
                                peer,
                                _replyRevealTimer == null ? reply : null,
                                previewLink,
                                canSend: canSend,
                                send: send,
                                canQueue: canQueue,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_sendTextFlight case final flight?
                    when flight.destination != null)
                  _sendFlight(flight, style),
                if (_reactionFlight case final flight? when flight.accepted)
                  _movingReaction(
                    flight,
                    ios: Theme.of(context).platform == TargetPlatform.iOS,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _composerAccessories(
    Peer peer, {
    required bool canSend,
    required int? limit,
    required int bytes,
    required int characters,
  }) {
    final controller = widget.controller;
    final enabled = !_controlsCovered && !_sending;
    final hasOutbox = controller.outboxFor(peer.id).isNotEmpty;
    final status = _ComposerStatus(
      connected: controller.connected,
      canSend: canSend,
      characters: characters,
      bytes: bytes,
      limit: limit,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _quickPhrasesOpen ? 1 : 0),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
        builder: (context, progress, _) => LayoutBuilder(
          builder: (context, constraints) {
            final expanded = progress == 1 && _quickPhrasesOpen;
            final extent = QuickPhraseStrip.extent(context);
            final start = math.min(48.0, constraints.maxWidth);
            final width = start + (constraints.maxWidth - start) * progress;
            final triggerSpace = 54 * (1 - progress);
            final statusInset = triggerSpace + (hasOutbox ? 54 : 0);
            return Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: 48 - 24 * progress,
                      ),
                      child: Row(
                        children: [
                          SizedBox(width: triggerSpace),
                          if (hasOutbox) ...[
                            GlassButton(
                              coveredByModal: _controlsCovered,
                              icon: Icons.schedule_rounded,
                              label: tr(
                                context,
                                'Очередь рации',
                                'Radio outbox',
                              ),
                              onTap: () => unawaited(_openOutbox(peer)),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(child: status),
                          SizedBox(width: statusInset),
                        ],
                      ),
                    ),
                    SizedBox(height: extent * progress),
                  ],
                ),
                if (progress > 0)
                  PositionedDirectional(
                    start: 0,
                    bottom: 0,
                    width: width,
                    child: IgnorePointer(
                      ignoring: !expanded,
                      child: ExcludeSemantics(
                        excluding: !expanded,
                        child: TextFieldTapRegion(
                          child: QuickPhraseStrip(
                            progress: progress,
                            store: controller.store,
                            onSelect: enabled
                                ? (phrase) => _insertQuickPhrase(peer, phrase)
                                : null,
                            onExpand: enabled
                                ? () => unawaited(_showQuickPhraseList(peer))
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (progress == 0)
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    child: GlassButton(
                      coveredByModal: _controlsCovered,
                      icon: Icons.short_text_rounded,
                      label: tr(context, 'Быстрые фразы', 'Quick phrases'),
                      onTap: enabled && !_quickPhrasesOpen
                          ? () => setState(() => _quickPhrasesOpen = true)
                          : null,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _composerControls(
    Peer peer,
    MeshMessage? reply,
    Uri? previewLink, {
    required bool canSend,
    required bool send,
    required bool canQueue,
  }) {
    final controller = widget.controller;
    final native = useIosControls;
    final excerpt = controller.replyDraftExcerpt(peer.id);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Widget editorFor(DraftLinkPreview? preview) {
      final showLink =
          preview != null && (reply == null || _linkBehindReply != previewLink);
      final MessageInputAccessory? accessory = showLink
          ? (
              title: preview.title,
              text: preview.text,
              image: preview.image,
              link: true,
            )
          : reply == null
          ? null
          : (
              title: _quoteAuthor(context, reply),
              text: excerpt?.text ?? reply.text,
              image: null,
              link: false,
            );
      void open() {
        if (showLink) {
          unawaited(openMessageLink(context, previewLink!));
        } else if (reply != null) {
          unawaited(_revealMessage(reply.id, excerpt: excerpt));
        }
      }

      void dismiss() {
        if (showLink) {
          setState(() => _dismissedDraftLink = previewLink);
        } else {
          controller.setReplyDraft(peer.id, null);
        }
      }

      final editor = MessageInput(
        key: _input,
        enabled: controller.connected,
        coveredByModal:
            _controlsCovered || ModalRoute.isCurrentOf(context) == false,
        controller: _draft,
        hidesMovingText:
            _sendTextFlight?.destination != null &&
            _sendTextFlight?.draft == _draft.text,
        accessory: native ? accessory : null,
        onOpenAccessory: open,
        onDismissAccessory: dismiss,
        onChanged: (value) {
          controller.setDraft(peer.id, value);
          setState(() {
            final link = firstMessageLink(value);
            if (link != _dismissedDraftLink) _dismissedDraftLink = null;
            if (link != _linkBehindReply) _linkBehindReply = null;
          });
        },
      );
      final accessoryRow = accessory == null
          ? const SizedBox.shrink()
          : _ComposerAccessoryRow(
              key: ValueKey(showLink ? previewLink : reply?.id),
              accessory: accessory,
              onOpen: open,
              onDismiss: dismiss,
            );
      return KeyedSubtree(
        key: _inputSurface,
        child: native
            ? editor
            : GlassSurface(
                radius: 23,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (reduceMotion)
                      accessoryRow
                    else
                      AnimatedSize(
                        alignment: Alignment.bottomCenter,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: accessoryRow,
                      ),
                    editor,
                  ],
                ),
              ),
      );
    }

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _attachmentSourceHidden,
          child: GlassButton(
            key: _attachmentButton,
            coveredByModal: _controlsCovered,
            icon: Icons.attach_file_rounded,
            label: tr(context, 'Вложения', 'Attachments'),
            onTap: controller.connected && canSend && !_sending
                ? () => unawaited(_attach(peer))
                : null,
          ),
          builder: (context, hidden, button) => Visibility(
            visible: !hidden,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: true,
            child: button!,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: previewLink == null
              ? editorFor(null)
              : MessageLinkPreview(
                  uri: previewLink,
                  compact: true,
                  autoLoad: _canPreviewLinks,
                  draftBuilder: editorFor,
                ),
        ),
        const SizedBox(width: 8),
        GlassButton(
          key: _sendControl,
          coveredByModal: _controlsCovered,
          icon: Icons.arrow_upward_rounded,
          primary: send,
          label: tr(context, 'Отправить', 'Send'),
          onTap: send ? () => unawaited(_send(peer)) : null,
          longPressLabel: tr(context, 'Варианты отправки', 'Send options'),
          onLongPress:
              !_sending &&
                  (canQueue || controller.outboxFor(peer.id).isNotEmpty)
              ? () => unawaited(_sendOptions(peer))
              : null,
        ),
      ],
    );
    return native ? row : TextFieldTapRegion(child: row);
  }

  Widget _heading(Peer peer, MeshStyle style) {
    final split = ChatWorkspacePane.of(context)?.split ?? false;
    final title = peer.channel
        ? tr(context, 'Канал', 'Channel')
        : tr(context, 'Личный чат', 'Direct chat');
    final native = useIosControls;
    final (avatarTop, avatarBottom) = MeshAvatar.colorsFor(peer.name);
    final avatar = MeshAvatar.initialsFor(peer.name);
    final properties = <String, Object>{
      'dark': style.dark,
      'enabled': true,
      'coveredByModal':
          _controlsCovered ||
          !_workspaceVisible ||
          ModalRoute.isCurrentOf(context) == false,
      'foreground': style.text.toARGB32(),
      'surface': style.surface.toARGB32(),
      'accent': style.accent.toARGB32(),
      'secondary': style.secondary.toARGB32(),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 5),
      child: Row(
        children: [
          GlassButton(
            coveredByModal: _controlsCovered,
            icon: split
                ? Icons.close_rounded
                : Icons.arrow_back_ios_new_rounded,
            label: split
                ? tr(context, 'Закрыть чат', 'Close chat')
                : tr(context, 'Назад', 'Back'),
            onTap: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Center(
              child: _ChatTitle(
                name: peer.name,
                subtitle: title,
                nativeProperties: native ? properties : null,
                onTap: () => unawaited(_profile(peer)),
                onLongPress: _beginMessageSearch,
              ),
            ),
          ),
          const SizedBox(width: 9),
          if (split) ...[
            GlassButton(
              icon: Icons.search_rounded,
              label: tr(context, 'Поиск в чате', 'Search in chat'),
              onTap: _beginMessageSearch,
            ),
            const SizedBox(width: 8),
          ],
          if (native)
            SizedBox.square(
              dimension: 48,
              child: IosControl(
                kind: 'chatAvatar',
                properties: {
                  ...properties,
                  'label': tr(context, 'Профиль чата', 'Chat profile'),
                  'avatarTop': avatarTop.toARGB32(),
                  'avatarBottom': avatarBottom.toARGB32(),
                  if (!peer.channel &&
                      widget.controller.isNodeOnline(peer.id)) ...{
                    'online': true,
                    'onlineLabel': tr(
                      context,
                      'Активен за последний час',
                      'Active in the past hour',
                    ),
                    'onlineColor': style.onlineDot.toARGB32(),
                    'onlineBorder': style.canvas.toARGB32(),
                  },
                  'initials': peer.channel
                      ? '#'
                      : (avatar.isEmpty ? 'M' : avatar),
                },
                onSelect: (_) => unawaited(_profile(peer)),
              ),
            )
          else
            IconButton(
              tooltip: tr(context, 'Профиль чата', 'Chat profile'),
              padding: EdgeInsets.zero,
              onPressed: () => unawaited(_profile(peer)),
              icon: MeshAvatar(
                peer.name,
                size: 43,
                channel: peer.channel,
                online: widget.controller.isNodeOnline(peer.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _unreadDivider(MeshStyle style) {
    final line = Divider(height: 1, color: style.accent.withValues(alpha: .32));
    return Padding(
      key: const ValueKey('unread-divider'),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(child: line),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * .76,
                ),
                child: Text(
                  tr(context, 'Непрочитанные сообщения', 'Unread messages'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: style.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            Expanded(child: line),
          ],
        ),
      ),
    );
  }

  Widget _day(DateTime date, MeshStyle style) => Padding(
    padding: const EdgeInsets.only(top: 7, bottom: 7),
    child: GlassSurface(
      radius: 13,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          DateUtils.isSameDay(date, DateTime.now())
              ? tr(context, 'Сегодня', 'Today')
              : MaterialLocalizations.of(context).formatMediumDate(date),
          style: TextStyle(
            fontSize: 12,
            color: style.secondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );

  bool _joins(MeshMessage? first, MeshMessage? second) =>
      first != null &&
      second != null &&
      first.outgoing == second.outgoing &&
      (first.outgoing || _senderKey(first) == _senderKey(second)) &&
      DateUtils.isSameDay(first.time, second.time) &&
      second.time.difference(first.time).inMinutes < 5;

  String _senderKey(MeshMessage message) =>
      message.packet?.sender ??
      (message.author.isEmpty
          ? 'message:${message.id}'
          : 'name:${message.author}');

  List<ChannelAuthorGroup> _authorGroups(
    List<MeshMessage> messages,
    String? unreadBoundary,
  ) {
    final groups = <ChannelAuthorGroup>[];
    final last = messages.length - 1;
    for (var end = last; end >= 0; end--) {
      final message = messages[end];
      if (message.outgoing) continue;
      var start = end;
      while (start > 0 &&
          messages[start].id != unreadBoundary &&
          _joins(messages[start - 1], messages[start])) {
        start--;
      }
      groups.add((newest: last - end, oldest: last - start, message: message));
      end = start;
    }
    return groups;
  }
}

class _ChatScrollPhysics extends ScrollPhysics {
  const _ChatScrollPhysics({super.parent});

  static const _bounce = BouncingScrollPhysics();

  bool _fits(ScrollMetrics position) =>
      position.minScrollExtent == position.maxScrollExtent;

  @override
  _ChatScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _ChatScrollPhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      _fits(position) || super.shouldAcceptUserOffset(position);

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (!_fits(position)) {
      return super.applyPhysicsToUserOffset(position, offset);
    }
    // A short history is already at both edges when the drag starts.
    return position.outOfRange
        ? _bounce.applyPhysicsToUserOffset(position, offset)
        : offset * _bounce.frictionFactor(0);
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) =>
      _fits(position) ? 0 : super.applyBoundaryConditions(position, value);

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => _fits(position)
      ? _bounce.createBallisticSimulation(position, velocity)
      : super.createBallisticSimulation(position, velocity);
}

class _MessageHold extends StatefulWidget {
  const _MessageHold({required this.onOpen, required this.child});
  final VoidCallback? onOpen;
  final Widget child;

  @override
  State<_MessageHold> createState() => _MessageHoldState();
}

class _MessageHoldState extends State<_MessageHold> {
  bool pressed = false;

  void _press(bool value) {
    if (pressed != value) setState(() => pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onOpen == null) return widget.child;
    return GestureDetector(
      onLongPressDown: (_) => _press(true),
      onLongPressCancel: () => _press(false),
      onLongPressStart: (_) {
        _press(false);
        unawaited(playMeshHaptic(MeshHaptic.light));
        widget.onOpen!();
      },
      child: AnimatedScale(
        scale: pressed ? .97 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Duration(milliseconds: pressed ? 400 : 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _ComposerStatus extends StatefulWidget {
  const _ComposerStatus({
    required this.connected,
    required this.canSend,
    required this.characters,
    required this.bytes,
    required this.limit,
  });

  final bool connected, canSend;
  final int characters, bytes;
  final int? limit;

  @override
  State<_ComposerStatus> createState() => _ComposerStatusState();
}

class _ComposerStatusState extends State<_ComposerStatus> {
  Timer? _confirmation;

  @override
  void didUpdateWidget(_ComposerStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected == oldWidget.connected) return;
    _confirmation?.cancel();
    _confirmation = widget.connected
        ? Timer(
            const Duration(milliseconds: 1400),
            () => setState(() => _confirmation = null),
          )
        : null;
  }

  @override
  void dispose() {
    _confirmation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final limit = widget.limit;
    final bytes = widget.bytes;
    final characters = widget.characters;
    final overLimit = limit != null && bytes > limit;
    final Widget content;
    if (!widget.connected || _confirmation != null) {
      content = Semantics(
        key: ValueKey(widget.connected),
        liveRegion: true,
        child: Text(
          widget.connected
              ? tr(context, 'Соединение установлено', 'Connection established')
              : tr(context, 'Рация не подключена', 'Radio disconnected'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: widget.connected
                ? Color.lerp(style.success, style.text, .25)
                : style.error,
          ),
        ),
      );
    } else {
      content = Wrap(
        key: const ValueKey('composer-budget'),
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          if (!widget.canSend || overLimit)
            Text(
              !widget.canSend
                  ? tr(context, 'Отправка недоступна', 'Sending unavailable')
                  : tr(
                      context,
                      'Лимит одного сообщения',
                      'Single message limit',
                    ),
              style: TextStyle(fontSize: 12, color: style.secondary),
            ),
          Semantics(
            label: limit == null
                ? tr(context, 'Символов: $characters', '$characters characters')
                : tr(
                    context,
                    'Символов: $characters, байт: $bytes из $limit',
                    '$characters characters, $bytes of $limit bytes',
                  ),
            excludeSemantics: true,
            child: Text(
              [
                tr(context, '$characters симв.', '$characters chars'),
                if (limit != null) '$bytes/$limit ${tr(context, 'Б', 'B')}',
              ].join(' · '),
              style: TextStyle(
                fontSize: 12,
                color: overLimit ? style.warning : style.secondary,
              ),
            ),
          ),
        ],
      );
    }
    if (MediaQuery.disableAnimationsOf(context)) return Center(child: content);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: content,
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.item,
    required this.emoji,
    required this.channel,
    required this.joinsPrevious,
    required this.joinsNext,
    required this.quoted,
    required this.reactions,
    required this.hideText,
    this.standalonePosition,
    this.preview,
    this.link,
    this.onMenu,
    this.onReact,
    this.onRetry,
    this.onQuote,
    this.onAuthor,
    this.highlight,
    this.highlightedExcerpt,
    this.excerptAnimation,
    this.waitingForRadio = false,
    this.flightTarget,
    this.reactionTarget,
    this.localOnly = false,
    this.displayedText,
  });
  final VoidCallback? onAuthor;
  final MeshMessage item;
  final String? emoji;
  final bool hideText;
  final NodePosition? standalonePosition;
  final Widget? preview;
  final Uri? link;
  final bool channel, joinsPrevious, joinsNext;
  final MeshMessage? quoted;
  final List<ChatReaction> reactions;
  final ValueChanged<Rect>? onMenu;
  final ValueChanged<String>? onReact;
  final VoidCallback? onRetry;
  final VoidCallback? onQuote;
  final Animation<double>? highlight;
  final MessageExcerpt? highlightedExcerpt;
  final Animation<double>? excerptAnimation;
  final bool waitingForRadio;
  final Key? flightTarget;
  final ReactionGlyphTarget? reactionTarget;
  final bool localOnly;
  final String? displayedText;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final own = item.outgoing;
    final sticker = emoji;
    final mapOnly = standalonePosition != null;
    final showAuthor = channel && !own && (sticker != null || !joinsPrevious);
    const corner = Radius.circular(19), join = Radius.circular(7);
    final subtitle = waitingForRadio
        ? tr(context, 'Ожидает отправки', 'Waiting to send')
        : messageDeliveryLabel(context, item.delivery, channel: channel);
    return LayoutBuilder(
      builder: (context, layout) => Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(top: joinsPrevious ? 2 : 5),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(layout.maxWidth * .84, 460),
            ),
            child: Builder(
              builder: (context) {
                void openMenu() {
                  final box = context.findRenderObject()! as RenderBox;
                  onMenu!(box.localToGlobal(Offset.zero) & box.size);
                }

                final tap = onMenu == null ? null : openMenu;
                if (sticker != null) {
                  return _MessageHold(
                    onOpen: tap,
                    child: _StickerContent(
                      item: item,
                      emoji: sticker,
                      stateLabel: subtitle,
                      showAuthor: showAuthor,
                      quoted: quoted,
                      reactions: reactions,
                      reactionTarget: reactionTarget,
                      highlight: highlight,
                      onTap: tap,
                      onReact: onReact,
                      onRetry: onRetry,
                      onQuote: onQuote,
                      onAuthor: onAuthor,
                    ),
                  );
                }
                return _MessageHold(
                  onOpen: tap,
                  child: CustomPaint(
                    key: ValueKey(('bubble', item.id)),
                    painter: mapOnly
                        ? null
                        : _BubbleShape(
                            color: own ? style.outgoing : style.incoming,
                            highlight: highlight,
                            highlightColor: style.accent,
                            gradient: own && style.dark
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xff433a9d),
                                      Color(0xff2845a7),
                                    ],
                                  )
                                : null,
                            corners: BorderRadius.only(
                              topLeft: !own && joinsPrevious ? join : corner,
                              topRight: own && joinsPrevious ? join : corner,
                              bottomLeft: !own ? join : corner,
                              bottomRight: own ? join : corner,
                            ),
                            tail: !joinsNext,
                            outgoing: own,
                          ),
                    child: Padding(
                      padding: mapOnly
                          ? EdgeInsets.zero
                          : const EdgeInsets.fromLTRB(12, 7, 9, 5),
                      child: _MessageContent(
                        item: item,
                        hideText: hideText || mapOnly,
                        standalonePosition: standalonePosition,
                        mapHighlight: highlight,
                        preview: preview,
                        link: link,
                        stateLabel: subtitle,
                        showAuthor: showAuthor,
                        quoted: quoted,
                        highlightedExcerpt: highlightedExcerpt,
                        excerptAnimation: excerptAnimation,
                        waitingForRadio: waitingForRadio,
                        textKey: flightTarget,
                        localOnly: localOnly,
                        displayedText: displayedText,
                        reactions: reactions,
                        reactionTarget: reactionTarget,
                        onTap: tap,
                        onReact: onReact,
                        onRetry: onRetry,
                        onQuote: onQuote,
                        onAuthor: onAuthor,
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
}

String _messageTime(BuildContext context, MeshMessage item) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(item.time.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

class _StickerContent extends StatelessWidget {
  const _StickerContent({
    required this.item,
    required this.emoji,
    required this.stateLabel,
    required this.showAuthor,
    required this.quoted,
    required this.reactions,
    this.highlight,
    this.onTap,
    this.onReact,
    this.onRetry,
    this.onQuote,
    this.onAuthor,
    this.reactionTarget,
  });

  final VoidCallback? onAuthor;
  final MeshMessage item;
  final String emoji, stateLabel;
  final bool showAuthor;
  final MeshMessage? quoted;
  final List<ChatReaction> reactions;
  final Animation<double>? highlight;
  final VoidCallback? onTap, onRetry, onQuote;
  final ValueChanged<String>? onReact;
  final ReactionGlyphTarget? reactionTarget;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final own = item.outgoing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: own
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (showAuthor && item.author.isNotEmpty)
          GestureDetector(
            onTap: onAuthor,
            child: Text(
              item.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: style.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (item.replyTo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: style.pill,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: _MessageQuote(
                message: quoted,
                excerpt: item.replyExcerpt?.text,
                onTap: onQuote,
              ),
            ),
          ),
        SizedBox(
          key: ValueKey(('sticker', item.id)),
          width: 132,
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              if (highlight case final pulse?)
                IgnorePointer(
                  child: FadeTransition(
                    opacity: pulse,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: style.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                onDoubleTap: onReact == null ? null : () => onReact!('❤️'),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      emoji,
                      style: emojiGlyphStyle(
                        const TextStyle(fontSize: 112, height: 1),
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xc5202330),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        child: _MessageStamp(
                          item: item,
                          time: _messageTime(context, item),
                          timeStyle: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                          stateLabel: stateLabel,
                          receiptColor: Colors.white,
                          onRetry: onRetry,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (reactions.isNotEmpty)
          MessageReactionChips(
            reactions,
            outsideBubble: true,
            alignment: own ? WrapAlignment.end : WrapAlignment.start,
            onReact: onReact,
            flight: reactionTarget,
          ),
      ],
    );
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({
    required this.item,
    required this.stateLabel,
    required this.showAuthor,
    required this.quoted,
    required this.reactions,
    required this.hideText,
    this.standalonePosition,
    this.mapHighlight,
    this.preview,
    this.link,
    this.onTap,
    this.onReact,
    this.onRetry,
    this.onQuote,
    this.onAuthor,
    this.highlightedExcerpt,
    this.excerptAnimation,
    required this.waitingForRadio,
    this.textKey,
    this.reactionTarget,
    this.localOnly = false,
    this.displayedText,
  });

  final VoidCallback? onAuthor;
  final MeshMessage item;
  final String stateLabel;
  final bool hideText;
  final NodePosition? standalonePosition;
  final Animation<double>? mapHighlight;
  final Widget? preview;
  final Uri? link;
  final bool showAuthor;
  final MeshMessage? quoted;
  final List<ChatReaction> reactions;
  final VoidCallback? onTap;
  final ValueChanged<String>? onReact;
  final VoidCallback? onRetry;
  final VoidCallback? onQuote;
  final MessageExcerpt? highlightedExcerpt;
  final Animation<double>? excerptAnimation;
  final bool waitingForRadio;
  final Key? textKey;
  final bool localOnly;
  final String? displayedText;
  final ReactionGlyphTarget? reactionTarget;

  Widget _text(MeshStyle style, TextStyle textStyle) {
    final highlighted = highlightedExcerpt;
    final text = displayedText ?? item.text;
    final range = highlighted != null && highlighted.matches(text)
        ? TextRange(
            start: highlighted.offset,
            end: highlighted.offset + highlighted.text.length,
          )
        : null;
    Widget render(double opacity) =>
        link == null && (range == null || opacity == 0)
        ? EmojiText(text, style: textStyle, textAlign: TextAlign.left)
        : MessageLinkifiedText(
            text: text,
            style: textStyle,
            linkColor: item.outgoing && style.dark ? style.text : style.accent,
            textAlign: TextAlign.left,
            highlight: range == null || opacity == 0
                ? null
                : (
                    range: range,
                    color: style.accent.withValues(alpha: .32 * opacity),
                  ),
          );
    final animation = excerptAnimation;
    final body = animation == null
        ? render(1)
        : AnimatedBuilder(
            animation: animation,
            builder: (_, _) => render(animation.value),
          );
    return textKey == null ? body : Opacity(opacity: 0, child: body);
  }

  Widget _standaloneMap(
    NodePosition position,
    String time,
    MeshStyle style,
    double width,
  ) => SizedBox(
    width: width,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          IgnorePointer(
            ignoring: onTap == null,
            child: MeshLocationPreview(
              position: position,
              standaloneMessage: true,
              loadTiles: false,
              attributionTextOnly: true,
            ),
          ),
          if (mapHighlight case final highlight?)
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: highlight,
                  child: ColoredBox(color: style.accent),
                ),
              ),
            ),
          PositionedDirectional(
            end: 7,
            bottom: 6,
            child: DecoratedBox(
              key: const ValueKey('location-message-stamp'),
              decoration: BoxDecoration(
                color: const Color(0xa32a3038),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(0, width - 28),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _MessageStamp(
                      item: item,
                      time: time,
                      timeStyle: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                      ),
                      stateLabel: stateLabel,
                      receiptColor: Colors.white,
                      onRetry: onRetry,
                      waitingForRadio: waitingForRadio,
                      showReceipt: !localOnly,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final time = _messageTime(context, item);
    final textStyle = TextStyle(fontSize: 16, height: 1.27, color: style.text);
    final timeStyle = TextStyle(fontSize: 11, color: style.messageTime);
    final defaults = DefaultTextStyle.of(context);
    final bold = MediaQuery.boldTextOf(context);
    final height = MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
    final letterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(context);
    final wordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context);
    TextPainter measure(String text, TextStyle style, double maxWidth) =>
        TextPainter(
          text: emojiTextSpan(
            text,
            style: defaults.style
                .merge(style)
                .copyWith(
                  fontWeight: bold ? FontWeight.bold : null,
                  height: height,
                  letterSpacing: letterSpacing,
                  wordSpacing: wordSpacing,
                ),
          ),
          textAlign: TextAlign.left,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
          textWidthBasis: defaults.textWidthBasis,
          textHeightBehavior:
              defaults.textHeightBehavior ??
              DefaultTextHeightBehavior.maybeOf(context),
        )..layout(maxWidth: maxWidth);
    return LayoutBuilder(
      builder: (context, constraints) {
        final mapPosition = standalonePosition;
        final timePainter = measure(time, timeStyle, double.infinity);
        final stampSize = item.outgoing
            ? Size(
                timePainter.width + (localOnly ? 0 : _MessageStamp.statusWidth),
                math.max(timePainter.height, _MessageStamp.iconSize),
              )
            : timePainter.size;
        timePainter.dispose();

        final maxWidth = constraints.maxWidth;
        final stampWidth = math.min(stampSize.width, maxWidth);
        final body = measure(
          hideText ? '' : displayedText ?? item.text,
          textStyle,
          maxWidth,
        );
        final lastLine = body.computeLineMetrics().lastOrNull;
        final bodyWidth = body.width;
        body.dispose();
        const gap = 6.0;
        final inlineWidth = lastLine == null
            ? double.infinity
            : (lastLine.left + lastLine.width + gap + stampWidth)
                  .ceilToDouble();
        final textHasRoom =
            preview == null &&
            lastLine != null &&
            inlineWidth <= maxWidth &&
            lastLine.height >= stampSize.height;
        final textMinWidth = textHasRoom ? inlineWidth : stampWidth;
        final chips = reactions.isEmpty
            ? null
            : MessageReactionChips(
                reactions,
                onReact: onReact,
                flight: reactionTarget,
              );
        var bubbleWidth = math.max(bodyWidth, textMinWidth);
        var inlineReactions = false;
        if (chips != null) {
          final widths = chips.chipWidths((text, style) {
            final painter = measure(text, style, double.infinity);
            final width = painter.width;
            painter.dispose();
            return width;
          }).toList();
          var rowWidth = 0.0;
          for (final naturalWidth in widths) {
            final width = math.min(naturalWidth, maxWidth);
            if (rowWidth == 0 ||
                rowWidth + MessageReactionChips.spacing + width > maxWidth) {
              rowWidth = width;
            } else {
              rowWidth += MessageReactionChips.spacing + width;
            }
            bubbleWidth = math.max(bubbleWidth, rowWidth);
          }
          final widthWithStamp = (rowWidth + gap + stampWidth).ceilToDouble();
          if (widths.length == 1 && widthWithStamp <= maxWidth) {
            bubbleWidth = math.max(bubbleWidth, widthWithStamp);
          }
          inlineReactions = widthWithStamp <= bubbleWidth;
        }
        final inlineText = chips == null && textHasRoom;

        return Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showAuthor && item.author.isNotEmpty)
                  GestureDetector(
                    onTap: onAuthor,
                    child: Text(
                      item.author,
                      style: TextStyle(
                        color: style.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                if (item.replyTo != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: _MessageQuote(
                      message: quoted,
                      excerpt: item.replyExcerpt?.text,
                      onTap: onQuote,
                    ),
                  ),
                if (!hideText)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap,
                    onDoubleTap: onReact == null ? null : () => onReact!('❤️'),
                    child: ConstrainedBox(
                      key: textKey,
                      constraints: BoxConstraints(
                        minWidth: chips == null ? textMinWidth : bubbleWidth,
                      ),
                      child: _text(style, textStyle),
                    ),
                  ),
                if (preview case final card?)
                  Padding(
                    padding: EdgeInsets.only(top: hideText ? 0 : 7, bottom: 3),
                    child: SizedBox(width: maxWidth, child: card),
                  ),
                if (mapPosition != null)
                  _standaloneMap(mapPosition, time, style, maxWidth),
                ?chips,
                if (mapPosition == null && !inlineText && !inlineReactions)
                  SizedBox(height: stampSize.height + 2),
              ],
            ),
            if (mapPosition == null)
              Positioned(
                right: 0,
                bottom: inlineReactions ? 5 : 0,
                width: stampWidth,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: _MessageStamp(
                    item: item,
                    time: time,
                    timeStyle: timeStyle,
                    stateLabel: stateLabel,
                    onRetry: onRetry,
                    waitingForRadio: waitingForRadio,
                    showReceipt: !localOnly,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.name,
    required this.id,
    this.shortName,
    this.onOpenProfile,
    this.onWrite,
    this.channel = false,
    this.actionLabel,
  });

  final String name, id;
  final String? shortName;
  final bool channel;
  final String? actionLabel;
  final VoidCallback? onOpenProfile, onWrite;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final nameSize = Theme.of(context).textTheme.bodyMedium?.fontSize ?? 16;
    final nameStyle = TextStyle(
      color: style.text,
      fontSize: nameSize,
      fontWeight: FontWeight.w700,
    );
    final shortStyle = TextStyle(
      color: style.dark ? style.text : Colors.black,
      fontSize: nameSize - 2,
    );
    final addressStyle = TextStyle(color: style.secondary, fontSize: 12);
    final short = shortName;
    final hasShortName = short != null && short.isNotEmpty;
    double textHeight(
      String text,
      TextStyle style, {
      double width = double.infinity,
      int maxLines = 1,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(maxWidth: width);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final detailHeight = hasShortName
        ? textHeight(short, shortStyle) + textHeight(id, addressStyle)
        : 0.0;
    return Material(
      color: style.text.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenProfile,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 9.0;
                  final limit = constraints.maxWidth * .4;
                  var avatarSize = math.min(36.0, limit);
                  if (hasShortName) {
                    final singleLineSize = math.min(
                      limit,
                      textHeight(name, nameStyle) + detailHeight,
                    );
                    final nameWidth = math.max(
                      0.0,
                      constraints.maxWidth - gap - singleLineSize,
                    );
                    avatarSize = math.min(
                      limit,
                      textHeight(
                            name,
                            nameStyle,
                            width: nameWidth,
                            maxLines: 2,
                          ) +
                          detailHeight,
                    );
                  }
                  return Row(
                    children: [
                      MeshAvatar(name, size: avatarSize, channel: channel),
                      const SizedBox(width: gap),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: nameStyle,
                            ),
                            if (hasShortName)
                              Text(
                                short,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: shortStyle,
                              ),
                            Text(
                              id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: addressStyle,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (onWrite != null) ...[
                const SizedBox(height: 6),
                Divider(height: 1, color: style.text.withValues(alpha: .16)),
                TextButton(
                  onPressed: onWrite,
                  child: Text(
                    actionLabel ?? tr(context, 'Написать', 'Message'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageStamp extends StatelessWidget {
  const _MessageStamp({
    required this.item,
    required this.time,
    required this.timeStyle,
    required this.stateLabel,
    this.onRetry,
    this.receiptColor,
    this.waitingForRadio = false,
    this.showReceipt = true,
  });

  static const iconSize = 15.0;
  static const _gap = 3.0;
  static const statusWidth = iconSize + _gap;
  final MeshMessage item;
  final String time, stateLabel;
  final TextStyle timeStyle;
  final VoidCallback? onRetry;
  final Color? receiptColor;
  final bool waitingForRadio;
  final bool showReceipt;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final stamp = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(time, style: timeStyle),
        if (item.outgoing && showReceipt) ...[
          const SizedBox(width: _gap),
          Tooltip(
            message: onRetry == null
                ? stateLabel
                : '$stateLabel. ${tr(context, 'Повторить отправку', 'Resend message')}',
            child: SizedBox.square(
              dimension: iconSize,
              child: waitingForRadio
                  ? Icon(
                      Icons.schedule_rounded,
                      size: iconSize,
                      color: style.messageTime,
                    )
                  : item.delivery.awaitingReceipt
                  ? Center(
                      child: SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: style.accent,
                        ),
                      ),
                    )
                  : Icon(
                      item.delivery == Delivery.acknowledged
                          ? Icons.done_all_rounded
                          : Icons.error_outline_rounded,
                      size: iconSize,
                      color: item.delivery == Delivery.acknowledged
                          ? receiptColor ?? style.success
                          : style.deliveryWarning,
                    ),
            ),
          ),
        ],
      ],
    );
    if (onRetry == null) return stamp;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onRetry,
        child: stamp,
      ),
    );
  }
}

class _ChatTitle extends StatelessWidget {
  const _ChatTitle({
    required this.name,
    required this.subtitle,
    required this.nativeProperties,
    required this.onTap,
    this.onLongPress,
  });

  final String name, subtitle;
  final Map<String, Object>? nativeProperties;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final titleStyle = base.copyWith(fontSize: 16, fontWeight: FontWeight.w600);
    final subtitleStyle = base.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w400,
      color: MeshStyle.of(context).secondary,
    );
    final scaler = MediaQuery.textScalerOf(context);
    Size measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final titleSize = measure(name, titleStyle);
    final subtitleSize = measure(subtitle, subtitleStyle);
    const padding = 13.0;
    final properties = nativeProperties;
    return SizedBox(
      width: math.max(
        48,
        math.max(titleSize.width, subtitleSize.width).ceilToDouble() +
            2 * padding +
            2,
      ),
      height: math.max(48, titleSize.height + subtitleSize.height + 8),
      child: properties != null
          ? IosControl(
              kind: 'chatTitle',
              eagerGestures: true,
              properties: {
                ...properties,
                'label': name,
                if (onLongPress != null)
                  'longPressLabel': tr(
                    context,
                    'Поиск по сообщениям',
                    'Search messages',
                  ),
                'subtitle': subtitle,
                'titleFontSize': scaler.scale(16),
                'subtitleFontSize': scaler.scale(11),
              },
              onSelect: onTap == null ? null : (_) => onTap?.call(),
              onLongPress: onLongPress,
            )
          : GlassSurface(
              radius: 100,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: padding),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: subtitleStyle,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _ReplySwipe extends StatefulWidget {
  const _ReplySwipe({super.key, this.onReply, required this.child});
  final VoidCallback? onReply;
  final Widget child;

  @override
  State<_ReplySwipe> createState() => _ReplySwipeState();
}

class _ReplySwipeState extends State<_ReplySwipe> {
  double _offset = 0;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.onReply;
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        if (_offset > 0)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Opacity(
              opacity: (_offset / 43).clamp(0.0, 1.0),
              child: Icon(
                Icons.reply_rounded,
                color: MeshStyle.of(context).accent,
              ),
            ),
          ),
        TweenAnimationBuilder<double>(
          tween: Tween(end: _offset),
          duration: _dragging ? Duration.zero : meshMotion(context),
          curve: Curves.easeOutCubic,
          builder: (context, offset, child) =>
              Transform.translate(offset: Offset(-offset, 0), child: child),
          child: GestureDetector(
            onHorizontalDragStart: action == null
                ? null
                : (_) => setState(() => _dragging = true),
            onHorizontalDragUpdate: action == null
                ? null
                : (details) {
                    setState(
                      () => _offset = (_offset - details.delta.dx).clamp(
                        0.0,
                        56.0,
                      ),
                    );
                  },
            onHorizontalDragEnd: action == null
                ? null
                : (_) {
                    if (_offset >= 43) {
                      unawaited(playMeshHaptic(MeshHaptic.medium));
                      action();
                    }
                    _reset();
                  },
            onHorizontalDragCancel: action == null ? null : _reset,
            child: widget.child,
          ),
        ),
      ],
    );
  }

  void _reset() => setState(() {
    _offset = 0;
    _dragging = false;
  });
}

String _quoteAuthor(BuildContext context, MeshMessage? source) =>
    source?.outgoing == true
    ? tr(context, 'Вы', 'You')
    : source?.author.isNotEmpty == true
    ? source!.author
    : tr(context, 'Ответ', 'Reply');

class _ComposerAccessoryRow extends StatelessWidget {
  const _ComposerAccessoryRow({
    super.key,
    required this.accessory,
    required this.onOpen,
    required this.onDismiss,
  });

  final MessageInputAccessory accessory;
  final VoidCallback onOpen, onDismiss;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              hint: accessory.link
                  ? tr(context, 'Открыть ссылку', 'Open link')
                  : tr(
                      context,
                      'Перейти к исходному сообщению',
                      'Go to original message',
                    ),
              child: InkWell(
                onTap: onOpen,
                child: Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(7, 3, 0, 3),
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(color: style.accent, width: 2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              accessory.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: style.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            EmojiText(
                              accessory.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: style.text, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (accessory.image case final image?)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            image,
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            cacheWidth: 96,
                            excludeFromSemantics: true,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            tooltip: accessory.link
                ? tr(context, 'Убрать предпросмотр', 'Remove preview')
                : tr(context, 'Отменить ответ', 'Cancel reply'),
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _MessageQuote extends StatelessWidget {
  const _MessageQuote({required this.message, this.excerpt, this.onTap});
  final MeshMessage? message;
  final String? excerpt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final source = message;
    final author = _quoteAuthor(context, source);
    final quote = Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 4, 3),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: style.accent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: style.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          EmojiText(
            excerpt ??
                source?.text ??
                tr(context, 'Исходное сообщение', 'Original message'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: style.text, fontSize: 12),
          ),
        ],
      ),
    );
    if (onTap == null) return quote;
    return Semantics(
      button: true,
      hint: tr(
        context,
        'Перейти к исходному сообщению',
        'Go to original message',
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: quote,
      ),
    );
  }
}

class _BubbleShape extends CustomPainter {
  _BubbleShape({
    required this.color,
    required this.highlightColor,
    this.highlight,
    this.gradient,
    required this.corners,
    required this.tail,
    required this.outgoing,
  }) : super(repaint: highlight);

  final Color color;
  final Color highlightColor;
  final Animation<double>? highlight;
  final Gradient? gradient;
  final BorderRadius corners;
  final bool tail, outgoing;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Offset.zero & size;
    var outline = Path()..addRRect(corners.toRRect(body));
    if (tail) {
      final edge = outgoing ? size.width : 0.0;
      final sign = outgoing ? 1 : -1;
      final height = size.height;
      final tip = Path()
        ..moveTo(edge - sign * 7, height - 1)
        ..lineTo(edge - sign * 1, height - 10)
        ..quadraticBezierTo(
          edge + sign * 1,
          height - 3,
          edge + sign * 6,
          height,
        )
        ..quadraticBezierTo(
          edge + sign * 2,
          height + 1,
          edge - sign * 7,
          height - 1,
        )
        ..close();
      outline = Path.combine(PathOperation.union, outline, tip);
    }
    final fill = Paint()..color = color;
    if (gradient case final colors?) fill.shader = colors.createShader(body);
    canvas.drawPath(outline, fill);
    if (highlight case final pulse? when pulse.value > 0) {
      canvas.drawPath(
        outline,
        Paint()..color = highlightColor.withValues(alpha: pulse.value),
      );
    }
  }

  @override
  bool shouldRepaint(_BubbleShape old) =>
      color != old.color ||
      highlight != old.highlight ||
      highlightColor != old.highlightColor ||
      gradient != old.gradient ||
      corners != old.corners ||
      tail != old.tail ||
      outgoing != old.outgoing;
}

Future<void> showMeshChat(
  BuildContext context,
  MeshController controller,
  Peer peer, {
  bool search = false,
  MeshChatOpener? open,
}) => !peer.channel && controller.isOwnChat(peer.id)
    ? showSavedChat(context, controller, open: open)
    : _pushConversation(
        context,
        (_) => MeshChatPage(
          controller: controller,
          peer: peer,
          initialSearch: search,
        ),
        open: open,
        peerId: peer.id,
        jump: search,
      );

class MeshChatProfile extends StatelessWidget {
  const MeshChatProfile({
    super.key,
    required this.controller,
    required this.peer,
    this.openNewChat = false,
    this.allowReadOnlyChat = false,
  });
  final MeshController controller;
  final Peer peer;
  final bool openNewChat;
  final bool allowReadOnlyChat;

  void _chat(BuildContext context, {bool search = false}) {
    if (openNewChat || (!peer.channel && controller.isOwnChat(peer.id))) {
      unawaited(showMeshChat(context, controller, peer, search: search));
    } else {
      Navigator.pop(context, search);
    }
  }

  Future<void> _clearHistory(BuildContext context) async {
    final radio = controller.active;
    final confirm = await showMeshDialog<bool>(
      context: context,
      builder: (context) => MeshDialog(
        title: Text(tr(context, 'Очистить переписку?', 'Clear conversation?')),
        content: Text(
          tr(
            context,
            'Сообщения будут удалены из $appName на этом телефоне.',
            'Messages will be removed from $appName on this phone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Очистить', 'Clear')),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted && controller.active == radio) {
      controller.clearChat(peer.id);
    }
  }

  Future<void> _openAdmin(
    BuildContext context,
    RemoteAdminSession admin,
    Radio radio,
  ) async {
    final remote = await showMeshDialog<RadioSettingsSession>(
      context: context,
      builder: (_) => _AdminAccessDialog(
        admin: admin,
        peer: peer,
        store: controller.store,
        passwordKey: controller.cache?.identities[peer.id]?.publicKey,
      ),
    );
    if (!context.mounted || remote == null) return;
    await Navigator.push<void>(
      context,
      radioSettingsRoute(
        context,
        RadioSettingsPage(
          controller: controller,
          radio: radio,
          remote: remote,
          peer: peer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final muted = controller.cache?.muted.contains(peer.id) ?? false;
      final radio = controller.active;
      final detail = peer.id;
      final role = controller.nodeObservation(peer.id)?.role;
      final hasChat =
          !openNewChat ||
          allowReadOnlyChat ||
          (!peer.channel && controller.isOwnChat(peer.id)) ||
          controller.canOpenChat(peer);
      final code = controller.contactCode(peer);
      final admin = controller.adminFor(peer);
      final heroTag = ('node-qr', peer.id);
      return Scaffold(
        body: ProfilePage(
          identity:
              controller.cache?.identities[peer.id]?.publicKey ??
              'peer:${radio?.network ?? ''}:${peer.id}',
          title: peer.name,
          subtitle: peer.channel
              ? tr(context, 'Канал', 'Channel')
              : nodeRoleLabel(context, role),
          avatarSize: 105,
          avatar: MeshAvatar(
            peer.name,
            size: 105,
            channel: peer.channel,
            online: controller.isNodeOnline(peer.id),
          ),
          padding: meshScrollPadding(
            context,
            const EdgeInsets.fromLTRB(16, 0, 16, 26),
          ),
          leading: GlassButton(
            icon: Icons.arrow_back_ios_new_rounded,
            label: tr(context, 'Назад', 'Back'),
            onTap: () => Navigator.pop(context),
          ),
          trailing: controller.canShareChannel(peer)
              ? GlassButton(
                  icon: Icons.qr_code_2_rounded,
                  label: tr(context, 'QR-код канала', 'Channel QR code'),
                  onTap: () =>
                      unawaited(showPeerChannelQr(context, controller, peer)),
                )
              : !peer.channel
              ? HeroMode(
                  enabled:
                      !useIosControls &&
                      !MediaQuery.disableAnimationsOf(context),
                  child: Hero(
                    tag: heroTag,
                    flightShuttleBuilder: (context, _, _, _, _) => GlassButton(
                      icon: Icons.qr_code_2_rounded,
                      label: tr(context, 'QR-код контакта', 'Contact QR code'),
                      onTap: null,
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: GlassButton(
                        icon: Icons.qr_code_2_rounded,
                        label: code == null
                            ? tr(
                                context,
                                'Загрузите ключ узла с рации',
                                'Sync the node key from the radio',
                              )
                            : tr(context, 'QR-код контакта', 'Contact QR code'),
                        onTap: code == null
                            ? null
                            : () async {
                                final match = await showContactQr(
                                  context,
                                  controller: controller,
                                  peer: peer,
                                  code: code,
                                  heroTag: heroTag,
                                );
                                if (!context.mounted ||
                                    match == null ||
                                    match.id == peer.id) {
                                  return;
                                }
                                await Navigator.push<void>(
                                  context,
                                  meshPageRoute(
                                    context,
                                    builder: (_) => MeshChatProfile(
                                      controller: controller,
                                      peer: match,
                                      openNewChat: true,
                                    ),
                                  ),
                                );
                              },
                      ),
                    ),
                  ),
                )
              : null,
          children: [
            if (hasChat) const SizedBox(height: 4),
            if (hasChat)
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    _action(
                      context,
                      tr(context, 'Чат', 'Chat'),
                      Icons.forum_outlined,
                      () => _chat(context),
                    ),
                    _action(
                      context,
                      tr(context, 'Поиск', 'Search'),
                      Icons.search_rounded,
                      () => _chat(context, search: true),
                    ),
                    _action(
                      context,
                      muted
                          ? tr(context, 'Без звука', 'Muted')
                          : tr(context, 'Звук', 'Sound'),
                      muted
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_outlined,
                      () => controller.toggleMute(peer.id),
                    ),
                    _action(
                      context,
                      tr(context, 'Очистить', 'Clear'),
                      Icons.delete_outline_rounded,
                      () => unawaited(_clearHistory(context)),
                    ),
                  ],
                ),
              ),
            if (!peer.channel)
              NodeActionsPanel(
                controller: controller,
                peer: peer,
                openAdmin: radio == null || admin == null
                    ? null
                    : () => unawaited(_openAdmin(context, admin, radio)),
              ),
            const SizedBox(height: 25),
            MeshGroup(
              children: [
                if (radio != null)
                  MeshRow(
                    title: controller.label(radio.network),
                    subtitle: radio.name,
                    icon: Icons.cell_tower_rounded,
                    tint: const Color(0xff168a87),
                  ),
                MeshRow(
                  title: tr(context, 'Идентификатор', 'Identifier'),
                  subtitle: detail,
                  icon: Icons.qr_code_2_rounded,
                  tint: const Color(0xff2978d5),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: detail));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(tr(context, 'Скопировано', 'Copied')),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _action(
    BuildContext context,
    String text,
    IconData icon,
    VoidCallback onTap,
  ) {
    final style = MeshStyle.of(context);
    final size = (MediaQuery.textScalerOf(context).scale(13) + 61)
        .clamp(74, 108)
        .toDouble();
    if (useIosControls) {
      final symbol = switch (icon) {
        Icons.forum_outlined => 'bubble.left',
        Icons.search_rounded => 'magnifyingglass',
        Icons.notifications_off_outlined => 'bell.slash',
        Icons.notifications_outlined => 'bell',
        _ => 'trash',
      };
      return GlassActionButton(
        label: text,
        onTap: onTap,
        primary: false,
        height: size,
        width: size,
        symbol: symbol,
      );
    }
    return SizedBox.square(
      dimension: size,
      child: Material(
        color: style.pill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(19),
          side: BorderSide(color: style.separator),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: style.text, size: 20),
                const SizedBox(height: 4),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: style.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminAccessDialog extends StatefulWidget {
  const _AdminAccessDialog({
    required this.admin,
    required this.peer,
    required this.store,
    required this.passwordKey,
  });

  final RemoteAdminSession admin;
  final MeshStore store;
  final String? passwordKey;
  final Peer peer;

  @override
  State<_AdminAccessDialog> createState() => _AdminAccessState();
}

class _AdminAccessState extends State<_AdminAccessDialog> {
  final _password = TextEditingController();
  bool _working = false;
  bool _visible = false, _remember = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.admin.adminRequiresPassword) unawaited(_loadPassword());
  }

  Future<void> _loadPassword() async {
    final key = widget.passwordKey;
    if (key == null) return;
    try {
      final saved = await widget.store.adminPassword(key);
      if (mounted && !_working && saved != null && _password.text.isEmpty) {
        setState(() {
          _password.text = saved;
          _remember = true;
        });
      }
    } on PlatformException {
      // Authentication still works while secure storage is unavailable.
    } on MissingPluginException {
      // Widget tests and environments without secure storage can still authenticate.
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_working ||
        (widget.admin.adminRequiresPassword && _password.text.isEmpty)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final password = _password.text;
      final remote = await widget.admin.openAdmin(widget.peer, password);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final key = widget.passwordKey;
      if (widget.admin.adminRequiresPassword && key != null) {
        try {
          await widget.store.setAdminPassword(key, _remember ? password : null);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  tr(
                    context,
                    'Не удалось обновить сохранённый пароль',
                    'Could not update the saved password',
                  ),
                ),
              ),
            );
          }
        }
      }
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context, remote);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _working = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => MeshDialog(
    title: Text(tr(context, 'Управление узлом', 'Manage node')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.peer.name),
        const SizedBox(height: 10),
        if (widget.admin.adminRequiresPassword) ...[
          TextField(
            controller: _password,
            autofocus: true,
            enabled: !_working,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: tr(
                context,
                'Пароль администратора',
                'Administrator password',
              ),
              suffixIcon: IconButton(
                tooltip: _visible
                    ? tr(context, 'Скрыть пароль', 'Hide password')
                    : tr(context, 'Показать пароль', 'Show password'),
                onPressed: () => setState(() => _visible = !_visible),
                icon: Icon(
                  _visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
            onSubmitted: (_) => unawaited(_open()),
          ),
          if (widget.passwordKey != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(tr(context, 'Запомнить пароль', 'Remember password')),
              value: _remember,
              onChanged: _working
                  ? null
                  : (value) => setState(() => _remember = value ?? false),
            ),
        ] else
          Text(
            tr(
              context,
              'На удалённом узле должен быть разрешён публичный ключ вашей рации.',
              'The remote node must authorize your radio’s public key.',
            ),
          ),
        if (_working)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(switch (error) {
              TimeoutException() => tr(
                context,
                'Репитер не ответил на запрос входа. Проверьте радиосвязь.',
                'The repeater did not reply to the login request. Check the radio link.',
              ),
              NodeAdminDenied(guest: true) => tr(
                context,
                'Узел подтвердил вход с гостевыми правами.',
                'The node accepted guest access.',
              ),
              NodeAdminDenied() => tr(
                context,
                'Узел отклонил вход.',
                'The node rejected the login.',
              ),
              FormatException() => tr(
                context,
                'Укажите пароль MeshCore длиной до 15 байт.',
                'Enter a MeshCore password up to 15 bytes long.',
              ),
              _ => tr(
                context,
                'Не удалось отправить запрос входа через рацию.',
                'The radio could not complete the login request.',
              ),
            }, style: TextStyle(color: MeshStyle.of(context).warning)),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, 'Отмена', 'Cancel')),
      ),
      TextButton(
        onPressed: _working ? null : () => unawaited(_open()),
        child: Text(tr(context, 'Открыть', 'Open')),
      ),
    ],
  );
}

class MeshChatWallpaper extends StatelessWidget {
  const MeshChatWallpaper({super.key});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ContourPaper(MeshStyle.of(context)));
}

class _ContourPaper extends CustomPainter {
  const _ContourPaper(this.style);
  final MeshStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: style.dark
            ? const [Color(0xff101521), Color(0xff0b0e16), Color(0xff171b2d)]
            : style.lightChatWallpaper,
      ).createShader(area);
    canvas.drawRect(area, fill);
    canvas.save();
    canvas.clipRect(area);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = style.dark ? const Color(0x3b768fc3) : const Color(0x30829fba);
    for (final center in [
      Offset(size.width * 1.02, size.height * .24),
      Offset(-size.width * .10, size.height * .79),
    ]) {
      for (var ring = 0; ring < 13; ring++) {
        final path = Path(), radius = 27.0 + ring * 17;
        for (var j = 0; j <= 92; j++) {
          final angle = j * 2 * math.pi / 92;
          final stretch =
              1 +
              .14 * math.sin(3 * angle + .6) +
              .055 * math.cos(7 * angle + .4);
          final x = center.dx + radius * stretch * math.cos(angle);
          final y = center.dy + radius * stretch * math.sin(angle) * 1.2;
          if (j == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(path..close(), line);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ContourPaper oldDelegate) =>
      oldDelegate.style.dark != style.dark;
}
