// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui'
    show FragmentProgram, FragmentShader, ImageFilter, ImageByteFormat;

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:leap_sliver_list/leap_sliver_list.dart';

import '../app_name.dart';
import '../mesh/chat_position.dart';
import '../mesh/controller.dart';
import '../mesh/network.dart';
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
import 'message_input.dart';
import 'message_links.dart';
import 'message_details.dart';
import 'message_menu.dart';
import 'message_reactions.dart';
import 'navigation.dart';
import 'node_actions.dart';
import 'position_picker.dart';
import '../mesh/store.dart';

class MeshChatPage extends StatefulWidget {
  const MeshChatPage({
    super.key,
    required this.controller,
    required this.peer,
    this.initialSearch = false,
  });
  final MeshController controller;
  final Peer peer;
  final bool initialSearch;
  @override
  State<MeshChatPage> createState() => _ChatState();
}

class _ChatState extends State<MeshChatPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _draft = EmojiEditingController(
    text: widget.controller.draft(widget.peer.id),
  );
  final _search = TextEditingController();
  final _input = GlobalKey<MessageInputState>();
  final _scroll = ScrollController(keepScrollOffset: false);
  final _history = ListController();
  AssetBundle? _emojiBundle;
  late Future<EmojiCatalog> _emojiCatalog;
  ItemAnimation? _quoteScroll;
  String? _highlighted;
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
  bool _sending = false;
  Uri? _dismissedDraftLink;
  bool _menuVisible = false;
  bool _attachmentOpen = false;
  final _menuBackground = GlobalKey();
  final _headerKey = GlobalKey();
  final _footerKey = GlobalKey();
  double _headerHeight = 59;
  double _footerHeight = 76;
  bool _measurementPending = false;
  final _latestButtonVisible = ValueNotifier(false);
  late final String? _radio;
  VoidCallback? _untrackViewport;
  ModalRoute<dynamic>? _route;
  List<MeshMessage> _listedMessages = const [];
  final _incomingRows = <String, GlobalKey>{};
  String? _unreadBoundary;
  ({String id, double position})? _historyAnchor;
  bool _listedSearch = false;
  bool _historyScheduled = false;
  bool _atInitialPosition = false;
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) _scheduleHistoryUpdate();
  }

  bool get _canReadHistory =>
      mounted &&
      !_searching &&
      !_menuVisible &&
      !_attachmentOpen &&
      (_route?.isCurrent ?? true) &&
      (_lifecycle == null || _lifecycle == AppLifecycleState.resumed);

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
      if (mounted) _updateHistoryPosition();
    });
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
    _quoteScroll?.cancel();
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
                  preferNative: !_menuVisible,
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
    _latestButtonVisible.dispose();
    _quoteScroll?.cancel();
    _history.dispose();
    _scroll.dispose();
    _highlight.dispose();
    _draft.dispose();
    _search.dispose();
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

  Future<void> _revealQuote(MeshMessage original) async {
    _quoteScroll?.cancel();
    _dismissKeyboard();
    if (_searching) {
      setState(() {
        _search.clear();
        _searching = false;
      });
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || !_history.isAttached || !_scroll.hasClients) return;
    int? index() {
      final messages = widget.controller.messages(original.chat);
      final i = messages.indexWhere((item) => item.id == original.id);
      return i < 0 ? null : messages.length - i - 1;
    }

    final target = index();
    if (target == null) return;
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
      final animation = _quoteScroll = _history.animateToItem(
        index: index,
        scrollController: _scroll,
        alignment: .5,
        obstruction: obstruction,
        duration: (_) => const Duration(milliseconds: 320),
        curve: (_) => Curves.easeInOutCubic,
      );
      await animation;
      if (!mounted || animation != _quoteScroll || animation.isCanceled) return;
    }
    setState(() => _highlighted = original.id);
    unawaited(_highlight.forward(from: 0));
  }

  Future<void> _send(Peer peer) async {
    final text = _draft.text.trim();
    if (_sending || text.isEmpty) return;
    final controller = widget.controller;
    final reply = controller.replyDraft(peer.id);
    if (reply != null && !controller.canUseMessageActions(peer, reply)) return;
    setState(() => _sending = true);
    try {
      final dismissed = _dismissedDraftLink;
      final sent = await controller.send(
        peer,
        text,
        reply: reply,
        suppressLinkPreview:
            dismissed != null && firstMessageLink(text) == dismissed,
      );
      if (mounted &&
          sent &&
          reply != null &&
          controller.replyDraft(peer.id)?.id == reply.id) {
        controller.setReplyDraft(peer.id, null);
      }
      if (mounted && sent && _draft.text.trim() == text) {
        _draft.clear();
        _dismissedDraftLink = null;
        widget.controller.setDraft(peer.id, '');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _attach(Peer peer) async {
    final controller = widget.controller;
    final radio = controller.active;
    final budget = controller.limit(peer);
    if (_sending || _attachmentOpen || radio == null || budget == null) return;
    _dismissKeyboard();
    setState(() => _attachmentOpen = true);
    final contacts = [
      for (final node in controller.nodes)
        (peer: node, link: controller.shareContactAttachment(node, budget)),
    ];
    final String? text;
    try {
      Uint8List? backdrop;
      if (useIosControls && !MediaQuery.highContrastOf(context)) {
        try {
          backdrop = await _glassBackdrop();
        } on FlutterError {
          // The chat may be relaid out while the system keyboard is closing.
        } on Exception {
          // The sheet can also open with a solid surface.
        }
      }
      if (!mounted || _route?.isCurrent == false) return;
      text = await pickChatAttachment(
        context,
        backdrop: backdrop,
        contacts: contacts,
        controller: controller,
        initialPosition: controller.cache?.localPosition,
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

  final _importing = <String>{};

  Future<void> _useContact(String link, {required bool openChat}) async {
    if (!_importing.add(link)) return;
    try {
      final controller = widget.controller;
      final peer = await controller.importContactAttachment(link);
      if (!mounted) return;
      if (peer == null) {
        _notice(
          tr(
            context,
            'Контакт недоступен для выбранной рации',
            'This contact is unavailable for the selected radio',
          ),
        );
      } else if (openChat &&
          controller.canOpenChat(peer) &&
          peer.writable &&
          peer.id != widget.peer.id) {
        await showMeshChat(context, controller, peer);
      } else if (!openChat) {
        unawaited(playMeshHaptic(MeshHaptic.success));
        _notice(
          tr(context, 'Контакт добавлен в узлы', 'Contact added to nodes'),
        );
      }
    } catch (_) {
      if (mounted) {
        _notice(
          tr(
            context,
            'Не удалось добавить контакт. Проверьте соединение с рацией и ключ узла.',
            'Could not add contact. Check the radio connection and node key.',
          ),
        );
      }
    } finally {
      _importing.remove(link);
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
    FocusScope.of(context).unfocus();
  }

  void _selectReply(Peer peer, MeshMessage message) {
    if (!widget.controller.canUseMessageActions(peer, message)) return;
    if (_searching) {
      _search.clear();
      setState(() => _searching = false);
    }
    widget.controller.setReplyDraft(peer.id, message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _input.currentState?.focusInput();
    });
  }

  String? _previewMessageId;

  // Capture only the chat before inserting the overlay and its controls.
  // The downsampled image isolates UIKit glass from the foreground.
  Future<Uint8List?> _glassBackdrop() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary = _menuBackground.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || boundary.size.isEmpty) {
      return null;
    }
    final image = await boundary.toImage(pixelRatio: 0.125);
    try {
      final data = await image.toByteData(format: ImageByteFormat.png);
      return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  Future<void> _messageMenu(
    Peer peer,
    MeshMessage message,
    Rect anchor,
    Widget bubble,
    List<ChatReaction> reactions,
  ) async {
    final controller = widget.controller;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    _dismissKeyboard();
    if (_menuVisible) return;
    setState(() {
      _menuVisible = true;
      _previewMessageId = message.id;
    });
    final String? value;
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
      value = await showMessageMenu(
        backdrop: backdrop,
        context: context,
        anchor: overlay.globalToLocal(anchor.topLeft) & anchor.size,
        canReact: controller.canChooseReaction(peer, message),
        recentReactions: controller.recentReactionEmojis,
        canReply: controller.canUseMessageActions(peer, message),
        outgoing: message.outgoing,
        bubble: bubble,
        reactions: reactions,
        onOpenProfile: _openAuthorProfile,
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
    if (!mounted || value == null) return;
    if (value == 'reply') {
      _selectReply(peer, message);
    } else if (value == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.text));
    } else {
      await _react(peer, message, value);
    }
  }

  Future<void> _react(Peer peer, MeshMessage message, String emoji) async {
    final controller = widget.controller;
    if (!controller.connected) {
      final radio = controller.active;
      if (radio == null || !controller.canChooseReaction(peer, message)) return;
      await controller.connect(radio);
      if (!mounted || controller.active != radio) return;
    }
    final sent = await controller.react(peer, message, emoji);
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

  Future<void> _profile(Peer peer) async {
    final result = await Navigator.push<bool>(
      context,
      meshPageRoute(
        context,
        builder: (_) =>
            MeshChatProfile(controller: widget.controller, peer: peer),
      ),
    );
    if (result == true && mounted) setState(() => _searching = true);
  }

  void _openAuthorProfile(Peer author) => unawaited(
    Navigator.of(context).push<void>(
      meshPageRoute<void>(
        context,
        builder: (_) => MeshChatProfile(
          controller: widget.controller,
          peer: author,
          openNewChat: author.id != widget.peer.id,
        ),
      ),
    ),
  );

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
              controller.contactAttachment(outgoing) == null
          ? firstMessageLink(outgoing)
          : null;
      final previewLink = draftLink == _dismissedDraftLink ? null : draftLink;
      final bytes = utf8.encode(outgoing).length;
      final characters = outgoing.characters.length;
      final limit = controller.limit(peer);
      final reply = controller.replyDraft(peer.id);
      final canCompose = controller.canOpenChat(peer);
      final canSend = controller.canSendTo(peer);
      final send =
          controller.connected &&
          canSend &&
          !_sending &&
          bytes > 0 &&
          (reply == null || controller.canUseMessageActions(peer, reply)) &&
          limit != null &&
          bytes <= limit;
      final query = _search.text.trim().toLowerCase();
      final messages = controller
          .messages(peer.id)
          .where(
            (message) =>
                !_searching ||
                query.isEmpty ||
                message.text.toLowerCase().contains(query),
          )
          .toList();

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
                  onTap: _dismissKeyboard,
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
                                  onOpenProfile: _openAuthorProfile,
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
                            final emoji = emojiCatalog?.singleEmoji(item.text);
                            final contact = controller.contactAttachment(
                              item.text,
                            );
                            final location = contact == null
                                ? chatPosition(item.text)
                                : null;
                            final knownContact = contact == null
                                ? null
                                : controller.findContactCode(item.text);
                            final link = contact == null
                                ? firstMessageLink(item.text)
                                : null;
                            Widget? card(bool interactive) {
                              if (contact != null) {
                                final canWrite =
                                    knownContact?.writable ??
                                    (contact.type == null || contact.type == 1);
                                return _ContactCard(
                                  name: knownContact?.name ?? contact.name,
                                  id: contact.id,
                                  onAdd:
                                      interactive &&
                                          contact.network ==
                                              controller.active?.network &&
                                          knownContact == null
                                      ? () => unawaited(
                                          _useContact(
                                            item.text,
                                            openChat: false,
                                          ),
                                        )
                                      : null,
                                  onWrite:
                                      interactive &&
                                          contact.network ==
                                              controller.active?.network &&
                                          canWrite
                                      ? () => unawaited(
                                          _useContact(
                                            item.text,
                                            openChat: true,
                                          ),
                                        )
                                      : null,
                                );
                              }
                              if (location != null) {
                                return MeshLocationPreview(
                                  position: location.point,
                                  loadTiles: false,
                                );
                              }
                              return link == null || item.suppressLinkPreview
                                  ? null
                                  : MessageLinkPreview(
                                      uri: link,
                                      foreground: style.text,
                                    );
                            }

                            _Bubble bubble([ValueChanged<Rect>? onMenu]) {
                              final attachment = card(onMenu != null);
                              return _Bubble(
                                item: item,
                                emoji: emoji,
                                hideText:
                                    contact != null ||
                                    location?.standalone == true,
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
                                onQuote: onMenu == null || quote == null
                                    ? null
                                    : () => unawaited(_revealQuote(quote)),
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
                                        _openAuthorProfile,
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
                                        onMenu != null
                                    ? () => unawaited(_retry(peer, item))
                                    : null,
                              );
                            }

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
                                      child: bubble(
                                        (anchor) => unawaited(
                                          _messageMenu(
                                            peer,
                                            item,
                                            anchor,
                                            bubble(),
                                            reactions,
                                          ),
                                        ),
                                      ),
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
                  child: const _ChatEdge(top: true),
                ),
                if (!_searching)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: bottom + _footerHeight + 9,
                    child: const _ChatEdge(top: false),
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
                        _heading(peer, style),
                        if (_searching)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                            child: GlassSurface(
                              radius: 100,
                              child: TextField(
                                autofocus: true,
                                controller: _search,
                                onTapOutside: (_) => _dismissKeyboard(),
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  hintText: tr(
                                    context,
                                    'Поиск в чате',
                                    'Search messages',
                                  ),
                                  border: InputBorder.none,
                                  suffixIcon: IconButton(
                                    tooltip: tr(
                                      context,
                                      'Закрыть поиск',
                                      'Close search',
                                    ),
                                    onPressed: () => setState(() {
                                      _search.clear();
                                      _searching = false;
                                    }),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ),
                              ),
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
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 0, 7, 5),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        !controller.connected
                                            ? tr(
                                                context,
                                                'Рация не подключена',
                                                'Radio disconnected',
                                              )
                                            : !canSend
                                            ? tr(
                                                context,
                                                'Отправка недоступна',
                                                'Sending unavailable',
                                              )
                                            : limit != null && bytes > limit
                                            ? tr(
                                                context,
                                                'Лимит одного сообщения',
                                                'Single message limit',
                                              )
                                            : '',
                                        maxLines: 2,
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: style.secondary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: Semantics(
                                        label: limit == null
                                            ? tr(
                                                context,
                                                'Символов: $characters',
                                                '$characters characters',
                                              )
                                            : tr(
                                                context,
                                                'Символов: $characters, байт: $bytes из $limit',
                                                '$characters characters, $bytes of $limit bytes',
                                              ),
                                        excludeSemantics: true,
                                        child: Text(
                                          [
                                            tr(
                                              context,
                                              '$characters симв.',
                                              '$characters chars',
                                            ),
                                            if (limit != null)
                                              '$bytes/$limit ${tr(context, 'Б', 'B')}',
                                          ].join(' · '),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                limit != null && bytes > limit
                                                ? style.warning
                                                : style.secondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _composerControls(
                                peer,
                                reply,
                                previewLink,
                                canSend: canSend,
                                send: send,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _composerControls(
    Peer peer,
    MeshMessage? reply,
    Uri? previewLink, {
    required bool canSend,
    required bool send,
  }) {
    final controller = widget.controller;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GlassButton(
          preferNative: !_menuVisible,
          icon: Icons.attach_file_rounded,
          label: tr(context, 'Вложения', 'Attachments'),
          onTap:
              controller.connected && canSend && !_sending && !_attachmentOpen
              ? () => unawaited(_attach(peer))
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GlassSurface(
            radius: 23,
            modal: !_menuVisible,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reply != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 3, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _MessageQuote(
                            message: reply,
                            onTap: () => unawaited(_revealQuote(reply)),
                          ),
                        ),
                        IconButton(
                          tooltip: tr(
                            context,
                            'Отменить ответ',
                            'Cancel reply',
                          ),
                          onPressed: () =>
                              controller.setReplyDraft(peer.id, null),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ),
                  ),
                if (previewLink != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(7, 7, 7, 0),
                    child: MessageLinkPreview(
                      uri: previewLink,
                      compact: true,
                      onDismiss: () =>
                          setState(() => _dismissedDraftLink = previewLink),
                    ),
                  ),
                MessageInput(
                  key: _input,
                  hidePlatformView: _menuVisible,
                  controller: _draft,
                  onChanged: (value) {
                    controller.setDraft(peer.id, value);
                    setState(() {
                      if (firstMessageLink(value) != _dismissedDraftLink) {
                        _dismissedDraftLink = null;
                      }
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        GlassButton(
          preferNative: !_menuVisible,
          icon: Icons.arrow_upward_rounded,
          primary: send,
          label: tr(context, 'Отправить', 'Send'),
          onTap: send ? () => unawaited(_send(peer)) : null,
        ),
      ],
    );
  }

  Widget _heading(Peer peer, MeshStyle style) {
    final title = peer.channel
        ? tr(context, 'Канал', 'Channel')
        : tr(context, 'Личный чат', 'Direct chat');
    final native = useIosControls && !_menuVisible;
    final (avatarTop, avatarBottom) = MeshAvatar.colorsFor(peer.name);
    final avatar = MeshAvatar.initialsFor(peer.name);
    final properties = <String, Object>{
      'dark': style.dark,
      'enabled': true,
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
            preferNative: !_menuVisible,
            icon: Icons.arrow_back_ios_new_rounded,
            label: tr(context, 'Назад', 'Back'),
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
              ),
            ),
          ),
          const SizedBox(width: 9),
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

  Widget _unreadDivider(MeshStyle style) => Container(
    key: const ValueKey('unread-divider'),
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
    decoration: BoxDecoration(
      color: style.accent.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(9),
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
  );

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

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.item,
    required this.emoji,
    required this.channel,
    required this.joinsPrevious,
    required this.joinsNext,
    required this.quoted,
    required this.reactions,
    required this.hideText,
    this.preview,
    this.link,
    this.onMenu,
    this.onReact,
    this.onRetry,
    this.onQuote,
    this.onAuthor,
    this.highlight,
  });
  final VoidCallback? onAuthor;
  final MeshMessage item;
  final String? emoji;
  final bool hideText;
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

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final own = item.outgoing;
    final sticker = emoji;
    final showAuthor = channel && !own && (sticker != null || !joinsPrevious);
    const corner = Radius.circular(19), join = Radius.circular(7);
    final subtitle = messageDeliveryLabel(
      context,
      item.delivery,
      channel: channel,
    );
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
                    painter: _BubbleShape(
                      color: own ? style.outgoing : style.incoming,
                      highlight: highlight,
                      highlightColor: style.accent,
                      gradient: own && style.dark
                          ? const LinearGradient(
                              colors: [Color(0xff433a9d), Color(0xff2845a7)],
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
                      padding: const EdgeInsets.fromLTRB(12, 7, 9, 5),
                      child: _MessageContent(
                        item: item,
                        hideText: hideText,
                        preview: preview,
                        link: link,
                        stateLabel: subtitle,
                        showAuthor: showAuthor,
                        quoted: quoted,
                        reactions: reactions,
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
              child: _MessageQuote(message: quoted, onTap: onQuote),
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
    this.preview,
    this.link,
    this.onTap,
    this.onReact,
    this.onRetry,
    this.onQuote,
    this.onAuthor,
  });

  final VoidCallback? onAuthor;
  final MeshMessage item;
  final String stateLabel;
  final bool hideText;
  final Widget? preview;
  final Uri? link;
  final bool showAuthor;
  final MeshMessage? quoted;
  final List<ChatReaction> reactions;
  final VoidCallback? onTap;
  final ValueChanged<String>? onReact;
  final VoidCallback? onRetry;
  final VoidCallback? onQuote;

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
        final timePainter = measure(time, timeStyle, double.infinity);
        final stampSize = item.outgoing
            ? Size(
                timePainter.width + _MessageStamp.statusWidth,
                math.max(timePainter.height, _MessageStamp.iconSize),
              )
            : timePainter.size;
        timePainter.dispose();

        final maxWidth = constraints.maxWidth;
        final stampWidth = math.min(stampSize.width, maxWidth);
        final body = measure(hideText ? '' : item.text, textStyle, maxWidth);
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
            : MessageReactionChips(reactions, onReact: onReact);
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
                    child: _MessageQuote(message: quoted, onTap: onQuote),
                  ),
                if (!hideText)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap,
                    onDoubleTap: onReact == null ? null : () => onReact!('❤️'),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: chips == null ? textMinWidth : bubbleWidth,
                      ),
                      child: link == null
                          ? EmojiText(
                              item.text,
                              style: textStyle,
                              textAlign: TextAlign.left,
                            )
                          : MessageLinkifiedText(
                              text: item.text,
                              style: textStyle,
                              linkColor: item.outgoing && style.dark
                                  ? style.text
                                  : style.accent,
                              textAlign: TextAlign.left,
                            ),
                    ),
                  ),
                if (preview case final card?)
                  Padding(
                    padding: EdgeInsets.only(top: hideText ? 0 : 7, bottom: 3),
                    child: SizedBox(width: maxWidth, child: card),
                  ),
                ?chips,
                if (!inlineText && !inlineReactions)
                  SizedBox(height: stampSize.height + 2),
              ],
            ),
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
    this.onAdd,
    this.onWrite,
  });

  final String name, id;
  final VoidCallback? onAdd, onWrite;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return Material(
      color: style.text.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(13),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                MeshAvatar(name, size: 36),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: style.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: style.secondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (onAdd != null || onWrite != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Wrap(
                  spacing: 5,
                  children: [
                    if (onWrite != null)
                      TextButton(
                        onPressed: onWrite,
                        child: Text(tr(context, 'Написать', 'Message')),
                      ),
                    if (onAdd != null)
                      TextButton(
                        onPressed: onAdd,
                        child: Text(tr(context, 'Добавить', 'Add contact')),
                      ),
                  ],
                ),
              ),
          ],
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
  });

  static const iconSize = 15.0;
  static const _gap = 3.0;
  static const statusWidth = iconSize + _gap;
  final MeshMessage item;
  final String time, stateLabel;
  final TextStyle timeStyle;
  final VoidCallback? onRetry;
  final Color? receiptColor;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final stamp = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(time, style: timeStyle),
        if (item.outgoing) ...[
          const SizedBox(width: _gap),
          Tooltip(
            message: onRetry == null
                ? stateLabel
                : '$stateLabel. ${tr(context, 'Повторить отправку', 'Resend message')}',
            child: SizedBox.square(
              dimension: iconSize,
              child: item.delivery.awaitingReceipt
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
  });

  final String name, subtitle;
  final Map<String, Object>? nativeProperties;
  final VoidCallback onTap;

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
              properties: {
                ...properties,
                'label': name,
                'subtitle': subtitle,
                'titleFontSize': scaler.scale(16),
                'subtitleFontSize': scaler.scale(11),
              },
              onSelect: (_) => onTap(),
            )
          : GlassSurface(
              radius: 100,
              child: InkWell(
                onTap: onTap,
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

class _MessageQuote extends StatelessWidget {
  const _MessageQuote({required this.message, this.onTap});
  final MeshMessage? message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final source = message;
    final author = source?.outgoing == true
        ? tr(context, 'Вы', 'You')
        : source?.author.isNotEmpty == true
        ? source!.author
        : tr(context, 'Ответ', 'Reply');
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
}) => Navigator.of(context).push<void>(
  meshPageRoute(
    context,
    builder: (_) =>
        MeshChatPage(controller: controller, peer: peer, initialSearch: search),
  ),
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
    if (openNewChat) {
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
          !openNewChat || allowReadOnlyChat || controller.canOpenChat(peer);
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

class _ChatEdge extends StatefulWidget {
  const _ChatEdge({required this.top});

  final bool top;

  @override
  State<_ChatEdge> createState() => _ChatEdgeState();
}

class _ChatEdgeState extends State<_ChatEdge> {
  static Future<FragmentProgram>? _program;
  FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (ImageFilter.isShaderFilterSupported) unawaited(_loadShader());
  }

  Future<void> _loadShader() async {
    try {
      final program = await (_program ??= FragmentProgram.fromAsset(
        'shaders/chat_edge.frag',
      ));
      if (!mounted) return;
      final shader = program.fragmentShader()..setFloat(2, widget.top ? 1 : 0);
      setState(() => _shader = shader);
    } catch (_) {
      // The gradient remains available if the runtime cannot load the shader.
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final top = widget.top;
    final shader = _shader;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (shader != null && !MediaQuery.highContrastOf(context))
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.shader(shader),
                child: const SizedBox.expand(),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [
                  style.canvas.withValues(alpha: .84),
                  style.canvas.withValues(alpha: .55),
                  style.canvas.withValues(alpha: .17),
                  style.canvas.withValues(alpha: 0),
                ],
                stops: const [0, .40, .73, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
