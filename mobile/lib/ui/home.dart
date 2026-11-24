// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../app_name.dart';
import '../local_notifications.dart';
import '../mesh/controller.dart';
import '../mesh/network.dart';
import '../mesh/store.dart';
import '../radio/desktop_usb.dart';
import 'about.dart';
import 'chat.dart';
import 'chat_archive.dart';
import 'chat_folders.dart';
import 'chat_management.dart';
import 'chat_setup.dart';
import 'chat_workspace.dart';
import 'firmware_page.dart';
import 'emoji_text.dart';
import 'haptics.dart';
import 'radio_discovery.dart';
import 'ios_control.dart';
import 'navigation.dart';
import 'nodes.dart';
import 'notification_settings.dart';
import 'radio_settings.dart';
import 'profile_page.dart';
import 'search_field.dart';
import 'mesh_scroll_edge.dart';
import 'message_search.dart';
import 'style.dart';
import 'usb_radio_page.dart';
import 'swipe_actions.dart';
import 'page_route.dart';

const _blue = Color(0xff2978d5);
const _teal = Color(0xff168a87);
const _violet = Color(0xff7b5bc3);

class MeshHome extends StatefulWidget {
  const MeshHome({
    super.key,
    required this.controller,
    this.notifications,
    this.tabletDisplay = false,
  });
  final MeshController controller;
  final LocalMessageNotifications? notifications;
  final bool tabletDisplay;

  @override
  State<MeshHome> createState() => _HomeState();
}

class _ChatDetailObserver extends NavigatorObserver {
  _ChatDetailObserver(this.onTopChanged, this.onGesture);

  final ValueChanged<Route<dynamic>> onTopChanged;
  final ValueChanged<bool> onGesture;
  Route<dynamic>? top;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    top = topRoute;
    onTopChanged(topRoute);
  }

  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) => onGesture(true);

  @override
  void didStopUserGesture() => onGesture(false);
}

class _HomeState extends State<MeshHome> with TickerProviderStateMixin {
  static const _android = MethodChannel('meshgrame/android');

  Future<void> _applySystemNavigation() async {
    if (Platform.isAndroid) {
      await _android.invokeMethod<void>(
        'hideNavigation',
        controller.hideSystemNavigation,
      );
    }
  }

  late final _tabs = MeshNavigationFade(this);
  late final _chatCategories = MeshNavigationFade(this);
  late final _searchCategories = MeshNavigationFade(this);
  String? _revealedRadio;
  final _search = TextEditingController();
  MessageSearchFilters _messageSearchFilters = const MessageSearchFilters();
  final _searchFocus = FocusNode();
  final _chatScroll = MeshSearchScrollController();
  late final _searchMotion = AnimationController(vsync: this);
  GlobalKey<IosControlState> _iosSearch = GlobalKey();
  bool _searchActive = false;
  bool _editingChats = false, _showHidden = false, _removingChats = false;
  bool _archiveRevealed = false;
  bool _archiveSwipeOpen = false;
  bool _archiveClosingShownRow = false;
  bool _archiveReady = false, _archiveMature = false;
  Timer? _archiveDwell;
  int? _archivePointer;
  double _archiveDistance = 0;
  late final _archiveProgress = AnimationController(
    vsync: this,
    value: controller.archiveHidden ? 0 : 1,
  );
  late final _archivePhysics = ChatArchiveScrollPhysics(
    _applyArchiveDrag,
    parent: const AlwaysScrollableScrollPhysics(),
  );
  ({int sequence, double extent}) _archiveRetraction = (sequence: 0, extent: 0);
  String? _revealedChat;
  final _previewBackground = GlobalKey();
  final _folderTabsScroll = ScrollController();
  Radio? _folderProfile;
  final _selectedChats = <String>{};
  late final AppLifecycleListener _lifecycle;
  final _detailKey = GlobalKey<NavigatorState>();
  late final _detailObserver = _ChatDetailObserver(_detailTopChanged, (active) {
    if (mounted) setState(() => _detailBackGesture = active);
  });
  bool _workspaceEnabled = false;
  bool _split = false;
  bool _desktopRail = false;
  double? _resizedChatListWidth;
  String? _detailPeer;
  bool _detailOpen = false;
  bool _detailBackGesture = false;
  Route<void>? _workspaceSettings;
  Route<void>? _workspaceConversation;
  MeshController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    _folderProfile = controller.active;
    controller.addListener(_changed);
    if (controller.hideSystemNavigation) unawaited(_applySystemNavigation());
    _lifecycle = AppLifecycleListener(
      onInactive: () => _finishArchiveDrag(released: false),
      onResume: () {
        controller.refreshNodePresence();
        unawaited(controller.flushOutbox());
        if (widget.notifications == null) {
          unawaited(controller.restoreConnection());
        }
      },
    );
  }

  Future<void> _configureWifiPush(
    LocalMessageNotifications notifications,
  ) async {
    var input = notifications.wifiPushSsid;
    final ssid = await showMeshDialog<String>(
      context: context,
      builder: (context) => MeshDialog(
        title: Text(tr(context, 'Уведомления по Wi-Fi', 'Wi-Fi notifications')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(
                context,
                'Подключите рацию по Wi-Fi и введите точное имя сети, общей для iPhone и рации.',
                'Connect to the radio over Wi-Fi and enter the exact name of the network it shares with the iPhone.',
              ),
            ),
            TextFormField(
              initialValue: input,
              onChanged: (value) => input = value,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'SSID'),
            ),
          ],
        ),
        actions: [
          if (notifications.wifiPushSsid.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: Text(tr(context, 'Выключить', 'Turn off')),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          TextButton(
            onPressed: () {
              if (input.isNotEmpty) Navigator.pop(context, input);
            },
            child: Text(tr(context, 'Сохранить', 'Save')),
          ),
        ],
      ),
    );
    if (ssid == null || !mounted) return;
    final saved = await notifications.configureWifiPush(ssid);
    if (!saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Не удалось настроить уведомления по Wi-Fi. Проверьте имя сети и разрешения приложения.',
              'Could not set up Wi-Fi notifications. Check the network name and app permissions.',
            ),
          ),
        ),
      );
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      final profile = controller.active;
      if (profile != _folderProfile) {
        final previous = _folderProfile;
        _folderProfile = profile;
        if (_detailPeer != null &&
            (previous == null ||
                profile == null ||
                radioKey(previous) != radioKey(profile))) {
          _detailPeer = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                controller.active == profile &&
                _detailPeer == null) {
              final detail = _detailKey.currentState;
              if (_workspaceSettings?.isActive == true) {
                if (_workspaceConversation case final route?
                    when route.isActive) {
                  detail?.removeRoute(route);
                }
              } else {
                detail?.popUntil((route) => route.isFirst);
              }
            }
          });
        }
        _resetArchiveVisibility();
        if (_chatCategories.selected >= 3) _chatCategories.jumpTo(0);
      } else if (controller.cache?.hiddenChats.isNotEmpty != true) {
        _resetArchiveVisibility();
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    controller.removeListener(_changed);
    _search.dispose();
    _searchFocus.dispose();
    _chatScroll.dispose();
    _folderTabsScroll.dispose();
    _searchMotion.dispose();
    _archiveDwell?.cancel();
    _archiveProgress.dispose();
    _tabs.opacity.dispose();
    _chatCategories.opacity.dispose();
    _searchCategories.opacity.dispose();
    super.dispose();
  }

  void _openSettings() {
    if (_flashingFirmware) return;
    if (_workspaceEnabled && _detailKey.currentState != null) {
      final detail = _detailKey.currentState!;
      if (_workspaceSettings case final existing? when existing.isActive) {
        detail.popUntil((route) => route.isFirst || route == existing);
        return;
      }
      final route = meshPageRoute<void>(
        context,
        conversationPane: true,
        builder: (panelContext) => ListenableBuilder(
          listenable: controller,
          builder: (context, _) =>
              _settings(MeshStyle.of(context), panelContext: panelContext),
        ),
      );
      setState(() => _workspaceSettings = route);
      unawaited(
        detail.push(route).whenComplete(() {
          if (mounted && _workspaceSettings == route) {
            setState(() => _workspaceSettings = null);
          }
        }),
      );
      return;
    }
    _selectTab(1);
  }

  bool get _flashingFirmware =>
      _detailObserver.top?.settings.name == firmwareBoardRoute &&
      _detailObserver.top?.popDisposition == RoutePopDisposition.doNotPop;

  Future<T?> _pushWorkspacePage<T>(PageRoute<T> route) async {
    if (_flashingFirmware) return null;
    final inWorkspace = _split || _workspaceSettings?.isActive == true;
    final navigation =
        (inWorkspace ? _detailKey.currentState : null) ?? Navigator.of(context);
    return navigation.push<T>(route);
  }

  Future<void> _openWorkspacePage(WidgetBuilder builder) async {
    await _pushWorkspacePage(
      meshPageRoute<void>(context, builder: builder, conversationPane: _split),
    );
  }

  void _selectTab(int index) {
    FocusScope.of(context).unfocus();
    if (_workspaceEnabled && _detailKey.currentState != null) {
      if (index == 1) {
        _openSettings();
        return;
      }
      _closeWorkspaceSettings();
    }
    _select(_tabs, index);
  }

  void _closeWorkspaceSettings() {
    if (_flashingFirmware || _workspaceSettings?.isActive != true) return;
    _detailKey.currentState?.popUntil(
      (route) =>
          route.isFirst ||
          (_detailPeer != null && route.settings.name == _detailPeer),
    );
  }

  void _select(MeshNavigationFade navigation, int index) {
    unawaited(
      navigation.select(
        index,
        animate: meshMotion(context) != Duration.zero,
        rebuild: _changed,
      ),
    );
  }

  Future<void> _openChat(Peer peer) async {
    if (_searchActive) {
      controller.rememberSearch(peer.id);
      _exitSearch();
    }
    FocusScope.of(context).unfocus();
    await showMeshChat(context, controller, peer, open: _openDetail);
  }

  void _detailTopChanged(Route<dynamic> route) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _detailObserver.top != route) return;
      final open = !route.isFirst;
      if (_detailOpen == open) return;
      setState(() {
        _detailOpen = open;
        if (!open) _detailPeer = null;
      });
    });
  }

  Future<void> _openDetail(
    WidgetBuilder builder, {
    String? peerId,
    bool jump = false,
  }) async {
    if (_flashingFirmware) return;
    final detail = _detailKey.currentState;
    if (detail == null) {
      await Navigator.of(context)
          .push<void>(meshPageRoute(context, builder: builder));
      return;
    }
    if (!jump && peerId != null && peerId == _detailPeer) {
      detail.popUntil(
        (route) => route.isFirst || route.settings.name == peerId,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _detailPeer = peerId);
    final route = meshPageRoute<void>(
      context,
      builder: builder,
      settings: RouteSettings(name: peerId),
      conversationPane: true,
    );
    _workspaceConversation = route;
    await detail.pushAndRemoveUntil<void>(route, (route) => route.isFirst);
    if (_workspaceConversation == route) _workspaceConversation = null;
  }

  Future<void> _openProfile(Peer peer, {bool allowReadOnlyChat = false}) async {
    if (_searchActive) _dismissSearchKeyboard();
    FocusScope.of(context).unfocus();
    await _openWorkspacePage(
      (_) => MeshChatProfile(
        controller: controller,
        peer: peer,
        openNewChat: true,
        allowReadOnlyChat: allowReadOnlyChat,
      ),
    );
  }

  void _newChat() => unawaited(_compose());

  Future<void> _compose() async {
    if (!controller.connected && controller.peers.isEmpty) {
      _openSettings();
      return;
    }
    final peer = await showNewChatSheet(context, controller);
    if (mounted && peer != null) await _openChat(peer);
  }

  void _enterSearch() {
    if (_searchActive) return;
    _finishArchiveDrag(released: false);
    setState(() {
      _iosSearch = GlobalKey();
      _searchActive = true;
      _searchCategories.jumpTo(
        _chatCategories.selected < 3 ? _chatCategories.selected : 0,
      );
    });
    animateMeshSearch(context, _searchMotion, open: true);
  }

  void _dismissSearchKeyboard() {
    _searchFocus.unfocus();
    _iosSearch.currentState?.dismissKeyboard();
  }

  void _exitSearch() {
    if (!_searchActive) return;
    _dismissSearchKeyboard();
    setState(() {
      _searchActive = false;
      _search.clear();
      _messageSearchFilters = const MessageSearchFilters();
    });
    animateMeshSearch(context, _searchMotion, open: false);
  }

  Future<void> _showRadioSettings(Radio radio) => _pushWorkspacePage(
    radioSettingsRoute(
      context,
      RadioSettingsPage(controller: controller, radio: radio),
    ),
  );

  void _toggleChatEditing() {
    if (_removingChats) return;
    _finishArchiveDrag(released: false);
    setState(() {
      _editingChats = !_editingChats;
      _revealedChat = null;
      _archiveSwipeOpen = false;
      _selectedChats.clear();
    });
  }

  void _showChats(bool hidden) {
    _finishArchiveDrag(released: false);
    if (_chatScroll.hasClients) _chatScroll.jumpTo(0);
    setState(() {
      _showHidden = hidden;
      _archiveSwipeOpen = false;
      _revealedChat = null;
      _selectedChats.clear();
    });
  }

  bool get _archiveIsIos => Theme.of(context).platform == TargetPlatform.iOS;

  double get _archiveExtent =>
      math.max(70, 28 + MediaQuery.textScalerOf(context).scale(30));

  bool get _archiveAvailable =>
      !_showHidden &&
      !_editingChats &&
      !_searchActive &&
      _chatCategories.selected == 0 &&
      controller.cache?.hiddenChats.isNotEmpty == true;

  bool get _canPullArchive =>
      _archiveAvailable && controller.archiveHidden && !_archiveRevealed;

  bool get _archiveCanScrollAway =>
      _archiveAvailable && controller.archiveHidden && _archiveRevealed;

  void _resetArchiveDrag() {
    _archiveDwell?.cancel();
    _archiveDwell = null;
    _archivePointer = null;
    _archiveDistance = 0;
    _archiveMature = false;
    _archiveReady = false;
  }

  void _resetArchiveVisibility() {
    _resetArchiveDrag();
    _archiveRevealed = false;
    _archiveSwipeOpen = false;
    _archiveClosingShownRow = false;
    final target = controller.archiveHidden ? 0.0 : 1.0;
    if (_archiveProgress.isAnimating || _archiveProgress.value != target) {
      _archiveProgress.value = target;
    }
  }

  double _applyArchiveDrag(ScrollMetrics position, double offset) {
    if (_archivePointer == null || !_canPullArchive) return offset;
    final atTop = position.pixels - position.minScrollExtent;
    final delta = offset > 0 ? math.max(0.0, offset - atTop) : offset;
    final extent = _archiveExtent;
    final fraction = _archiveIsIos ? .67 : 1.0;
    final previous = math.max(
      _archiveDistance,
      _archiveProgress.value * extent / fraction,
    );
    if (delta == 0 || (delta < 0 && previous == 0)) return offset;
    _archiveClosingShownRow = false;
    _archiveDistance = (previous + delta).clamp(0.0, extent * 1.4);
    _archiveProgress.value = math.min(
      1.0,
      _archiveDistance * fraction / extent,
    );
    if (!_archiveIsIos && !_archiveMature && _archiveDwell == null) {
      _archiveDwell = Timer(const Duration(milliseconds: 200), () {
        _archiveDwell = null;
        _archiveMature = true;
        _checkArchiveThreshold();
      });
    }
    _checkArchiveThreshold();
    return offset - (delta > 0 ? delta : math.max(-previous, delta));
  }

  void _checkArchiveThreshold() {
    if (!_canPullArchive || _archivePointer == null) return;
    final ready = _archiveIsIos
        ? _archiveProgress.value * _archiveExtent >= 40
        : _archiveMature && _archiveProgress.value >= .85;
    if (ready == _archiveReady) return;
    setState(() => _archiveReady = ready);
    if (ready) {
      unawaited(playMeshHaptic(MeshHaptic.medium));
      if (_archiveIsIos) _revealArchive(pointerHeld: true);
    }
  }

  void _settleArchive() {
    final target = controller.archiveHidden && !_archiveRevealed ? 0.0 : 1.0;
    unawaited(
      _archiveProgress.animateTo(
        target,
        duration: meshMotion(context),
        curve: target == 0 ? Curves.easeInOutCubic : Curves.easeOutCubic,
      ),
    );
  }

  void _revealArchive({bool pointerHeld = false}) {
    if (!pointerHeld) _resetArchiveDrag();
    setState(() => _archiveRevealed = true);
    _settleArchive();
  }

  void _finishArchiveDrag({required bool released}) {
    if (_archivePointer == null) return;
    if (_archiveRevealed) {
      setState(_resetArchiveDrag);
      if (!_archiveProgress.isAnimating) _settleArchive();
    } else if (released && _canPullArchive && _archiveReady) {
      _revealArchive();
    } else {
      _resetArchiveDrag();
      _settleArchive();
    }
  }

  bool _trackArchiveScroll(ScrollNotification event) {
    if (event.depth != 0 || event.metrics.axis != Axis.vertical) return false;
    if (event is ScrollStartNotification && _archiveSwipeOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _archiveSwipeOpen) {
          setState(() => _archiveSwipeOpen = false);
        }
      });
    }
    if (!_archiveCanScrollAway ||
        event.metrics.extentBefore <
            _chatScroll.collapseRange + _archiveExtent) {
      return false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_archiveCanScrollAway ||
          !_chatScroll.hasClients ||
          _chatScroll.position.extentBefore <
              _chatScroll.collapseRange + _archiveExtent) {
        return;
      }
      final height = _archiveProgress.value * _archiveExtent;
      setState(() {
        _resetArchiveVisibility();
        _archiveRetraction = (
          sequence: _archiveRetraction.sequence + 1,
          extent: height,
        );
      });
    });
    return false;
  }

  static bool _inCategory(Peer peer, int filter) => switch (filter) {
    1 => !peer.channel,
    2 => peer.channel,
    _ => true,
  };

  ChatFolder? _folderAt(int index) =>
      index < 3 ? null : controller.chatFolders.elementAtOrNull(index - 3);

  ChatFolder? get _chatFolder =>
      _showHidden ? null : _folderAt(_chatCategories.shown);

  bool _matchesChatTab(Peer peer, int index) {
    if (_showHidden) return true;
    return _inCategory(peer, index) &&
        (_folderAt(index)?.chats.contains(peer.id) ?? true);
  }

  List<String> _chatPins(ChatFolder? folder) =>
      folder?.pinned ?? controller.cache?.pinnedChats ?? const [];

  void _toggleChatPin(ChatFolder? folder, String id) {
    setState(() => _revealedChat = null);
    if (folder == null) {
      controller.toggleChatPin(id);
    } else {
      controller.toggleFolderPin(folder.id, id);
    }
  }

  List<ChatPreviewMenuItem> _previewActions(
    Peer peer,
    ChatFolder? folder,
    Radio? profile,
  ) {
    final unread = controller.isChatUnread(peer.id);
    final pinned = _chatPins(folder).contains(peer.id);
    final muted = controller.cache?.muted.contains(peer.id) ?? false;
    ChatPreviewMenuItem item(
      String label,
      IconData icon,
      VoidCallback run, {
      bool destructive = false,
    }) => (
      label: label,
      icon: icon,
      destructive: destructive,
      onTap: () {
        if (mounted && controller.active == profile) run();
      },
    );

    return [
      if (folder != null)
        item(
          tr(context, 'Убрать из папки', 'Remove from folder'),
          Icons.folder_off_outlined,
          () => controller.saveChatFolder(
            id: folder.id,
            name: folder.name,
            chats: folder.chats.where((id) => id != peer.id).toSet(),
          ),
        )
      else
        item(
          _showHidden
              ? tr(context, 'Показать чат', 'Show chat')
              : tr(context, 'Скрыть чат', 'Hide chat'),
          _showHidden
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          () => _changeVisibility([peer]),
        ),
      item(
        unread
            ? tr(context, 'Пометить прочитанным', 'Mark as read')
            : tr(context, 'Пометить непрочитанным', 'Mark as unread'),
        unread
            ? Icons.mark_chat_read_outlined
            : Icons.mark_chat_unread_outlined,
        () => unread
            ? controller.markChatsRead([peer.id])
            : controller.markChatsUnread([peer.id]),
      ),
      item(
        pinned
            ? tr(context, 'Открепить чат', 'Unpin chat')
            : tr(context, 'Закрепить чат', 'Pin chat'),
        pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
        () => _toggleChatPin(folder, peer.id),
      ),
      item(
        muted
            ? tr(context, 'Включить уведомления', 'Unmute notifications')
            : tr(context, 'Выключить уведомления', 'Mute notifications'),
        muted ? Icons.notifications_outlined : Icons.notifications_off_outlined,
        () => controller.toggleMute(peer.id),
      ),
      item(
        tr(context, 'Удалить чат', 'Delete chat'),
        Icons.delete_outline_rounded,
        () => unawaited(_deleteChats([peer])),
        destructive: true,
      ),
    ];
  }

  List<Peer> _visibleChats([int? filter]) {
    final index = filter ?? _chatCategories.shown;
    final folder = _showHidden ? null : _folderAt(index);
    final chats = _showHidden
        ? controller.hiddenConversations
        : controller.conversations;
    final peers = {
      for (final peer in chats)
        if (_matchesChatTab(peer, index)) peer.id: peer,
    };
    return [
      for (final id in _chatPins(folder)) ?peers.remove(id),
      ...peers.values,
    ];
  }

  void _selectChatTab(int index) {
    if (_removingChats || index == _chatCategories.selected) return;
    _resetArchiveVisibility();
    _revealedChat = null;
    _selectedChats.clear();
    _select(_chatCategories, index);
  }

  void _showNewFolder(String id) {
    final index = controller.chatFolders.indexWhere(
      (folder) => folder.id == id,
    );
    if (index < 0) return;
    _selectChatTab(index + 3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_folderTabsScroll.hasClients) return;
      final end = _folderTabsScroll.position.maxScrollExtent;
      final duration = meshMotion(context);
      if (duration == Duration.zero) {
        _folderTabsScroll.jumpTo(end);
      } else {
        unawaited(
          _folderTabsScroll.animateTo(
            end,
            duration: duration,
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }

  Future<void> _addFolder() async {
    final profile = controller.active;
    final chats = Set<String>.of(_selectedChats);
    final name = await nameNewChatFolder(context);
    if (!mounted || controller.active != profile || name == null) return;
    final id = controller.saveChatFolder(name: name, chats: chats);
    if (id != null) _showNewFolder(id);
  }

  Future<void> _editFolder(String id) async {
    final profile = controller.active;
    final folder = controller.chatFolders.firstWhere(
      (folder) => folder.id == id,
    );
    final result = await editChatFolder(
      context,
      folder: folder,
      chats: [...controller.conversations, ...controller.hiddenConversations],
    );
    if (!mounted || controller.active != profile || result == null) return;
    controller.saveChatFolder(id: id, name: result.name, chats: result.chats);
  }

  void _refreshFolderOrder(VoidCallback action) {
    final current = _folderAt(_chatCategories.selected)?.id;
    action();
    if (current == null) return;
    final index = controller.chatFolders.indexWhere(
      (folder) => folder.id == current,
    );
    setState(() => _chatCategories.jumpTo(index < 0 ? 0 : index + 3));
  }

  void _reorderFolders(int from, int to) {
    if (from == to) return;
    final ids = controller.chatFolders.map((folder) => folder.id).toList();
    ids.insert(to, ids.removeAt(from));
    _refreshFolderOrder(() => controller.reorderChatFolders(ids));
  }

  Future<void> _deleteFolder(String id) async {
    final profile = controller.active;
    final folder = controller.chatFolders.firstWhere(
      (folder) => folder.id == id,
    );
    final confirmed = await showMeshDialog<bool>(
      context: context,
      builder: (context) => MeshDialog(
        title: Text(tr(context, 'Удалить папку?', 'Delete folder?')),
        content: Text(folder.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Удалить', 'Delete')),
          ),
        ],
      ),
    );
    if (!mounted || controller.active != profile || confirmed != true) return;
    _refreshFolderOrder(() => controller.removeChatFolder(id));
  }

  void _changeVisibility(Iterable<Peer> peers) {
    final items = peers.toList();
    controller.hideChats(items.map((peer) => peer.id), hidden: !_showHidden);
    setState(() {
      _revealedChat = null;
      _selectedChats.removeAll(items.map((peer) => peer.id));
    });
  }

  Future<void> _deleteChats(List<Peer> peers) async {
    if (_removingChats || peers.isEmpty) return;
    final selectedRadio = controller.active;
    final removable = peers.where(controller.canRemovePeer).toList();
    if (removable.isEmpty) {
      _chatNotice(
        controller.connected
            ? tr(
                context,
                'Рация не позволяет удалить выбранные записи.',
                'The radio cannot remove these entries.',
              )
            : tr(
                context,
                'Подключите рацию для полного удаления.',
                'Connect the radio to delete these entries.',
              ),
      );
      return;
    }
    final yes = await confirmChatRemoval(
      context,
      removable.map((peer) => peer.name).toList(),
    );
    if (yes != true || !mounted || controller.active != selectedRadio) return;
    setState(() {
      _removingChats = true;
      _revealedChat = null;
    });
    final removed = <String>{};
    final device = selectedRadio == null ? null : radioKey(selectedRadio);
    for (final peer in removable) {
      final current = controller.active;
      if (current == null || radioKey(current) != device) break;
      try {
        await controller.removePeer(peer);
        removed.add(peer.id);
      } catch (_) {
        // Keep failed entries selected so the user can retry.
      }
    }
    if (!mounted) return;
    setState(() {
      _selectedChats.removeAll(removed);
      _removingChats = false;
    });
    final pending = peers.length - removed.length;
    if (pending > 0) {
      _chatNotice(
        tr(
          context,
          'Осталось записей: $pending',
          '$pending entries could not be removed.',
        ),
      );
    }
  }

  void _chatNotice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Widget _chatActionsBar() {
    final visible = _visibleChats();
    final selected = visible
        .where((peer) => _selectedChats.contains(peer.id))
        .toList();
    final read = selected.isEmpty ? visible : selected;
    final markUnread =
        selected.isNotEmpty &&
        !selected.any((peer) => controller.isChatUnread(peer.id));
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: GlassActionButton(
            primary: false,
            label: selected.isEmpty
                ? tr(context, 'Прочитать все', 'Read all')
                : markUnread
                ? tr(context, 'Не прочитано', 'Unread')
                : tr(context, 'Прочитать', 'Read'),
            onTap: _removingChats || read.isEmpty
                ? null
                : () {
                    final ids = read.map((peer) => peer.id);
                    if (markUnread) {
                      controller.markChatsUnread(ids);
                    } else {
                      controller.markChatsRead(ids);
                    }
                    setState(_selectedChats.clear);
                  },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: GlassActionButton(
            primary: false,
            label: _showHidden
                ? tr(context, 'Показать', 'Show')
                : tr(context, 'Скрыть', 'Hide'),
            onTap: _removingChats || selected.isEmpty
                ? null
                : () => _changeVisibility(selected),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: GlassActionButton(
            primary: false,
            label: tr(context, 'Удалить', 'Delete'),
            onTap: _removingChats || selected.isEmpty
                ? null
                : () => unawaited(_deleteChats(selected)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = meshDesktop(context);
    final size = MediaQuery.sizeOf(context);
    final apple = Theme.of(context).platform == TargetPlatform.iOS;
    final tablet =
        widget.tabletDisplay || size.shortestSide >= (apple ? 700 : 600);
    _split =
        size.width >=
            (desktop
                ? 800
                : apple
                ? 740
                : 840) &&
        (desktop || tablet);
    _workspaceEnabled |= desktop || _split || widget.tabletDisplay;
    _desktopRail = desktop && _split;
    final rail = _desktopRail ? ChatFolderRail.width : 0.0;
    final divider = _split ? (_desktopRail ? 6.0 : 1.0) : 0.0;
    final maximum = math.min(480.0, size.width - rail - divider - 400);
    final sidebarWidth = _split
        ? (_resizedChatListWidth ?? (size.width - rail) / 3)
              .clamp(300.0, maximum)
              .toDouble()
        : size.width;
    final sidebarCanGoBack =
        (_split || !_detailOpen) &&
        (_searchActive || _editingChats || _showHidden);
    final sidebarCovered = !_split && _detailOpen;
    return PopScope(
      canPop: !sidebarCanGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && sidebarCanGoBack) _dismissSidebarMode();
      },
      child: CallbackShortcuts(
        bindings: desktop
            ? {
                const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                    _showWorkspaceSearch,
                const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                    _showWorkspaceSearch,
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  if (_searchActive || _editingChats || _showHidden) {
                    _dismissSidebarMode();
                  } else {
                    unawaited(_detailKey.currentState?.maybePop());
                  }
                },
              }
            : const {},
        child: Focus(
          autofocus: desktop,
          child: RepaintBoundary(
            key: _previewBackground,
            child: Stack(
              children: [
                if (_desktopRail)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    width: rail,
                    child: _folderRail(),
                  ),
                Positioned(
                  left: rail,
                  top: 0,
                  bottom: 0,
                  width: sidebarWidth,
                  child: Offstage(
                    offstage: sidebarCovered && !_detailBackGesture,
                    child: ExcludeFocus(
                      excluding: sidebarCovered,
                      child: ExcludeSemantics(
                        excluding: sidebarCovered,
                        child: IgnorePointer(
                          ignoring: sidebarCovered,
                          child: MediaQuery.removePadding(
                            context: context,
                            removeLeft: _desktopRail,
                            removeRight: _split,
                            child: Builder(builder: _sidebar),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_split)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: rail + sidebarWidth,
                    width: divider,
                    child: _desktopRail
                        ? ChatWorkspaceResizeHandle(
                            onResize: (delta) => setState(() {
                              _resizedChatListWidth = (sidebarWidth + delta)
                                  .clamp(300.0, maximum)
                                  .toDouble();
                            }),
                          )
                        : ColoredBox(color: MeshStyle.of(context).separator),
                  ),
                if (_workspaceEnabled)
                  Positioned(
                    key: const ValueKey('conversation-pane'),
                    left: _split ? rail + sidebarWidth + divider : 0,
                    top: 0,
                    bottom: 0,
                    right: 0,
                    // A route in the detail navigator can block earlier
                    // semantics within its pane, while the list stays usable.
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      child: IgnorePointer(
                        ignoring: !_split && !_detailOpen,
                        child: MediaQuery.removePadding(
                          context: context,
                          removeLeft: _split,
                          child: ChatWorkspacePane(
                            split: _split,
                            visible: ModalRoute.isCurrentOf(context) != false,
                            child: NavigatorPopHandler<void>(
                              enabled: _detailOpen && !sidebarCanGoBack,
                              onPopWithResult: (_) => unawaited(
                                _detailKey.currentState?.maybePop(),
                              ),
                              child: ScaffoldMessenger(
                                child: Navigator(
                                  key: _detailKey,
                                  observers: [_detailObserver],
                                  onGenerateRoute: (_) =>
                                      PageRouteBuilder<void>(
                                        opaque: false,
                                        transitionDuration: Duration.zero,
                                        reverseTransitionDuration:
                                            Duration.zero,
                                        pageBuilder: (context, _, _) =>
                                            ChatWorkspacePane.of(context)!.split
                                            ? _noConversation(context)
                                            : const SizedBox.shrink(),
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
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

  void _dismissSidebarMode() {
    if (_searchActive) {
      _exitSearch();
    } else if (_editingChats) {
      _toggleChatEditing();
    } else if (_showHidden) {
      _showChats(false);
    }
  }

  void _showWorkspaceSearch() {
    if (_editingChats) _toggleChatEditing();
    if (_showHidden) _showChats(false);
    if (_tabs.selected != 0) _selectTab(0);
    _enterSearch();
  }

  Widget _noConversation(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const MeshChatWallpaper(),
      Center(
        child: GlassSurface(
          radius: 14,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(tr(context, 'Выберите чат', 'Select a chat')),
          ),
        ),
      ),
    ],
  );

  List<String> _builtInFolders(BuildContext context) => [
    tr(context, 'Все', 'All'),
    tr(context, 'Личные', 'Direct'),
    tr(context, 'Каналы', 'Channels'),
  ];

  Widget _folderRail() {
    final labels = [
      ..._builtInFolders(context),
      for (final folder in controller.chatFolders) folder.name,
    ];
    final unread = controller.cache?.unread;
    final unreadPeers = controller.cache?.markedUnread;
    final chats = controller.conversations;
    return ChatFolderRail(
      labels: labels,
      selected: _tabs.selected == 0 ? _chatCategories.selected : null,
      settingsSelected: _workspaceSettings?.isActive == true,
      unread: [
        for (var i = 0; i < labels.length; i++)
          chats.where((peer) => _matchesChatTab(peer, i)).fold(0, (
            count,
            peer,
          ) {
            final value = unread?[peer.id] ?? 0;
            return count +
                (value == 0 && unreadPeers?.contains(peer.id) == true
                    ? 1
                    : value);
          }),
      ],
      settingsUnread: controller.unreadOnOtherRadios,
      onFolder: (index) {
        if (_flashingFirmware) return;
        _dismissSidebarMode();
        _closeWorkspaceSettings();
        if (_tabs.selected != 0) _selectTab(0);
        _selectChatTab(index);
      },
      onSettings: () {
        _dismissSidebarMode();
        _openSettings();
      },
    );
  }

  Widget _sidebar(BuildContext context) {
    final style = MeshStyle.of(context);
    final keyboard = !_split || _searchActive
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;
    final nativeNavigation = useIosControls;
    final showingChats = _tabs.shown == 0;
    return Scaffold(
      // The keyboard can resize the content without relocating the navigation.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              bottom: keyboard,
              child: IgnorePointer(
                ignoring: _tabs.shown != _tabs.selected,
                child: FadeTransition(
                  opacity: _tabs.opacity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Keep the list's scroll position attached to the header
                      // while settings is visible.
                      Offstage(
                        offstage: !showingChats,
                        child: ExcludeFocus(
                          excluding: !showingChats,
                          child: _chatScene(style, keyboard),
                        ),
                      ),
                      if (!showingChats) _settings(style),
                    ],
                  ),
                ),
              ),
            ),
            if (_tabs.shown == 0 && _editingChats && !_searchActive)
              Positioned(
                left: 12,
                right: 12,
                bottom: MeshNavigation.bottomContentInset(context),
                child: _chatActionsBar(),
              )
            else if (!_searchActive && !_desktopRail)
              Positioned(
                left: nativeNavigation ? 0 : 14,
                right: nativeNavigation ? 0 : 14,
                bottom: MeshNavigation.bottomBarOffset(context),
                child: ExcludeSemantics(
                  excluding: keyboard > 0,
                  child: IgnorePointer(
                    ignoring: keyboard > 0,
                    child: MeshNavigation(
                      index: _split && _workspaceSettings?.isActive == true
                          ? 1
                          : _tabs.selected,
                      unread: controller.unreadTotal,
                      settingsUnread: controller.unreadOnOtherRadios,
                      onSelect: _selectTab,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double get _scrollBottom =>
      (_desktopRail && !_editingChats
          ? 0
          : MeshNavigation.contentHeight(context)) +
      MeshNavigation.bottomContentInset(context) +
      9;

  Widget _chatScene(MeshStyle style, double keyboard) => LayoutBuilder(
    builder: (context, constraints) {
      final safe = MediaQuery.paddingOf(context);
      final scaler = MediaQuery.textScalerOf(context);
      final caption = _showHidden
          ? tr(context, 'Архив', 'Archive')
          : tr(context, 'Чаты', 'Chats');
      final headingText = TextPainter(
        text: TextSpan(
          text: caption,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout(maxWidth: math.max(0, constraints.maxWidth - 216));
      final headingHeight = math.max(48.0, headingText.height) + 16;
      headingText.dispose();
      final fieldHeight = meshSearchFieldHeight(context);
      final collapseRange = fieldHeight + 9;
      _chatScroll
        ..collapseRange = !_editingChats && !_showHidden && !_searchActive
            ? collapseRange
            : 0
        ..trailingSnapExtent = _archiveCanScrollAway ? _archiveExtent : 0
        ..reduceMotion = MediaQuery.disableAnimationsOf(context);
      final normalFieldTop = safe.top + headingHeight + 3;
      final normalCategoriesTop = normalFieldTop + fieldHeight + 9;
      final categoryHeight = ChatFilters.contentHeight(context);
      final hasChatCategories =
          !_showHidden &&
          (controller.active != null || controller.conversations.isNotEmpty);
      final categoriesInChats =
          hasChatCategories && (!_desktopRail || _editingChats);
      final categoriesInSearch =
          controller.peers.isNotEmpty || controller.conversations.isNotEmpty;
      final searchBottom = (keyboard > 0 ? 0 : safe.bottom) + 2;
      final searchCategoriesTop = math.max(
        0.0,
        constraints.maxHeight - searchBottom - categoryHeight,
      );
      final normalHeaderHeight =
          normalCategoriesTop + (categoriesInChats ? categoryHeight : 0) + 8;
      final chatList = _chats(style, normalHeaderHeight, collapseRange);
      final searchResults = _searchActive || _searchMotion.value > 0
          ? _searchResults(style)
          : null;
      final editSideWidth = ((constraints.maxWidth - 112) / 2).clamp(
        96.0,
        128.0,
      );
      final heading = PageHeading(
        caption,
        sideWidth: _editingChats
            ? editSideWidth
            : _showHidden
            ? 92
            : 104,
        leading: _showHidden && !_editingChats
            ? GlassButton(
                icon: Icons.arrow_back_ios_new_rounded,
                label: tr(context, 'Назад', 'Back'),
                onTap: () => _showChats(false),
              )
            : GlassActionButton(
                primary: false,
                width: _editingChats ? 84 : 68,
                label: _editingChats
                    ? tr(context, 'Готово', 'Done')
                    : tr(context, 'Изм.', 'Edit'),
                onTap: _removingChats || (!hasChatCategories && !_editingChats)
                    ? null
                    : _toggleChatEditing,
              ),
        trailing: _showHidden && !_editingChats
            ? GlassActionButton(
                primary: false,
                width: 68,
                label: tr(context, 'Изм.', 'Edit'),
                onTap: controller.hiddenConversations.isNotEmpty
                    ? _toggleChatEditing
                    : null,
              )
            : _editingChats
            ? (_showHidden
                  ? null
                  : GlassActionButton(
                      primary: false,
                      width: editSideWidth,
                      icon: Icons.create_new_folder_outlined,
                      label: tr(context, 'Добавить', 'Add'),
                      onTap: controller.active == null || _removingChats
                          ? null
                          : () => unawaited(_addFolder()),
                    ))
            : GlassButton(
                icon: Icons.edit_note_rounded,
                label: tr(context, 'Новый чат', 'New chat'),
                primary: true,
                onTap: _newChat,
              ),
      );
      final categoryBar = _searchActive || _showHidden
          ? ChatFilters(
              selected: _searchActive ? _searchCategories.selected : 0,
              onSelect: (index) => _select(_searchCategories, index),
            )
          : ChatFolderTabs(
              builtInLabels: _builtInFolders(context),
              folders: controller.chatFolders,
              scrollController: _folderTabsScroll,
              selected: _chatCategories.selected,
              editing: _editingChats,
              onSelect: _selectChatTab,
              onReorder: _reorderFolders,
              onEdit: (id) => unawaited(_editFolder(id)),
              onDelete: (id) => unawaited(_deleteFolder(id)),
            );
      final closeSearch = GlassButton(
        icon: Icons.close_rounded,
        label: tr(context, 'Закрыть поиск', 'Close search'),
        onTap: _searchActive ? _exitSearch : null,
      );
      return AnimatedBuilder(
        animation: Listenable.merge([_searchMotion, _chatScroll]),
        builder: (context, _) {
          final progress = meshSearchProgress(_searchMotion);
          final scroll = _chatScroll.hasClients ? _chatScroll.position : null;
          final collapse =
              !_editingChats &&
                  !_showHidden &&
                  scroll != null &&
                  scroll.hasContentDimensions &&
                  scroll.maxScrollExtent > 0
              ? (scroll.pixels / collapseRange).clamp(0.0, 1.0)
              : 0.0;
          final buttonTop =
              safe.top + 7 + (headingHeight - 16 - meshSearchButtonSize) / 2;
          final categoriesTop = normalCategoriesTop - collapseRange * collapse;
          final headerHeight = normalHeaderHeight - collapseRange * collapse;
          final field = meshSearchFieldRect(
            width: constraints.maxWidth,
            normalTop: normalFieldTop,
            compactTop: buttonTop,
            activeTop: safe.top + 7,
            fieldHeight: fieldHeight,
            compactRight: 72,
            progress: progress,
            collapse: collapse,
          );
          final compact = !_searchActive && collapse == 1 && progress == 0;
          final resultsTop = field.top + fieldHeight + 9;
          final showCategories = progress == 0
              ? categoriesInChats
              : progress == 1
              ? categoriesInSearch
              : categoriesInChats || categoriesInSearch;
          return Stack(
            children: [
              Positioned.fill(
                key: const ValueKey('chat-list'),
                child: Offstage(
                  offstage: progress == 1,
                  child: IgnorePointer(
                    ignoring: _searchActive,
                    child: ExcludeSemantics(
                      excluding: _searchActive,
                      child: Opacity(opacity: 1 - progress, child: chatList),
                    ),
                  ),
                ),
              ),
              if (searchResults != null && (_searchActive || progress > 0))
                Positioned(
                  key: const ValueKey('chat-search-results'),
                  top: resultsTop,
                  bottom:
                      searchBottom + (categoriesInSearch ? categoryHeight : 0),
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    ignoring: !_searchActive,
                    child: ExcludeSemantics(
                      excluding: !_searchActive,
                      child: Opacity(opacity: progress, child: searchResults),
                    ),
                  ),
                ),
              Positioned(
                key: const ValueKey('chat-header-background'),
                top: 0,
                left: 0,
                right: 0,
                height: lerpDouble(headerHeight, resultsTop, progress)!,
                child: MeshScrollEdge(
                  top: true,
                  tint: style.canvas,
                  opaqueEdge: true,
                ),
              ),
              if (progress < 1)
                Positioned(
                  key: const ValueKey('chat-heading'),
                  top: lerpDouble(safe.top, -headingHeight, progress),
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    ignoring: _searchActive,
                    child: ExcludeSemantics(
                      excluding: _searchActive,
                      child: heading,
                    ),
                  ),
                ),
              Positioned(
                key: const ValueKey('chat-search-field'),
                top: field.top,
                left: field.left,
                width: field.width,
                height: field.height,
                child: compact
                    ? GlassButton(
                        icon: Icons.search_rounded,
                        label: tr(context, 'Поиск', 'Search'),
                        onTap: _enterSearch,
                      )
                    : _searchActive && field.width >= 128
                    ? _activeSearchField()
                    : MeshSearchLauncher(
                        placeholder: tr(context, 'Поиск', 'Search'),
                        collapse: collapse * (1 - progress),
                        onTap: _editingChats || _showHidden
                            ? null
                            : _enterSearch,
                      ),
              ),
              if (_searchActive || progress > 0)
                Positioned(
                  key: const ValueKey('chat-search-close'),
                  top: field.top + (fieldHeight - meshSearchButtonSize) / 2,
                  right: lerpDouble(-48, 16, progress),
                  child: closeSearch,
                ),
              if (showCategories)
                Positioned(
                  key: const ValueKey('chat-categories'),
                  left: 0,
                  right: 0,
                  top: lerpDouble(categoriesTop, searchCategoriesTop, progress),
                  child: categoryBar,
                ),
            ],
          );
        },
      );
    },
  );

  Widget _chats(MeshStyle style, double headerHeight, double collapseRange) {
    final hiddenCount = controller.hiddenConversations.length;
    final folder = _chatFolder;
    final pins = _chatPins(folder);
    final visible = _visibleChats();
    Widget item(BuildContext context, int index) {
      final peer = visible[index];
      final row = _chatRow(
        peer,
        style,
        editing: _editingChats,
        reorderIndex: index,
        selected: _selectedChats.contains(peer.id),
        pinned: pins.contains(peer.id),
        onTap: _editingChats
            ? () {
                if (!_removingChats) {
                  setState(() {
                    if (!_selectedChats.remove(peer.id)) {
                      _selectedChats.add(peer.id);
                    }
                  });
                }
              }
            : null,
      );
      return FadeTransition(
        key: ValueKey(peer.id),
        opacity: _chatCategories.visibility(
          shared: _matchesChatTab(peer, _chatCategories.counterpart),
        ),
        child: Column(
          children: [
            if (_editingChats)
              ColoredBox(color: style.canvas, child: row)
            else
              ChatSwipeRow(
                revealed: _revealedChat == peer.id,
                hidden: _showHidden,
                onReveal: (opened) =>
                    setState(() => _revealedChat = opened ? peer.id : null),
                onVisibility: () => _changeVisibility([peer]),
                onDelete: () => unawaited(_deleteChats([peer])),
                onPin: () => _toggleChatPin(folder, peer.id),
                pinned: pins.contains(peer.id),
                child: row,
              ),
            if (index != visible.length - 1)
              Divider(
                height: 1,
                thickness: .65,
                indent: 80,
                color: style.separator,
              ),
          ],
        ),
      );
    }

    final viewport = MeshScrollViewport(
      tint: style.canvas,
      fadeTop: false,
      edgeExtent: _scrollBottom,
      child: CustomScrollView(
        key: const PageStorageKey('chats'),
        controller: _chatScroll,
        physics: _archivePhysics,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
          if (_archiveAvailable && hiddenCount > 0)
            ChatArchiveSliver(
              retraction: _archiveRetraction,
              child: _archiveRow(style, hiddenCount),
            ),
          if (visible.isNotEmpty) ...[
            SliverPadding(
              padding: EdgeInsets.only(bottom: _scrollBottom),
              sliver: _editingChats
                  ? SliverReorderableList(
                      itemCount: visible.length,
                      itemBuilder: item,
                      onReorderItem: (from, to) {
                        if (_removingChats) return;
                        final ids = visible.map((peer) => peer.id).toList();
                        ids.insert(to, ids.removeAt(from));
                        controller.reorderChats(ids, hidden: _showHidden);
                      },
                    )
                  : SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: item,
                      findChildIndexCallback: (key) {
                        final index = visible.indexWhere(
                          (peer) => ValueKey(peer.id) == key,
                        );
                        return index < 0 ? null : index;
                      },
                    ),
            ),
            if (!_editingChats && !_showHidden)
              SliverLayoutBuilder(
                builder: (context, layout) => SliverToBoxAdapter(
                  child: SizedBox(
                    height: math.max(
                      0,
                      layout.viewportMainAxisExtent +
                          collapseRange +
                          (_archiveRevealed && _archiveAvailable
                              ? _archiveExtent
                              : 0) -
                          layout.precedingScrollExtent,
                    ),
                  ),
                ),
              ),
          ] else
            SliverFillRemaining(
              hasScrollBody: false,
              child: FadeTransition(
                opacity: _chatCategories.visibility(
                  shared: _visibleChats(_chatCategories.counterpart).isEmpty,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 4, 24, _scrollBottom),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 82,
                            height: 82,
                            decoration: BoxDecoration(
                              color: style.field,
                              shape: BoxShape.circle,
                            ),
                            child: MeshNavigation.activeChatIcon(
                              style.accent,
                              35,
                            ),
                          ),
                          const SizedBox(height: 17),
                          Text(
                            _showHidden
                                ? tr(
                                    context,
                                    'Скрытых чатов нет',
                                    'No hidden chats',
                                  )
                                : tr(context, 'Пока нет чатов', 'No chats yet'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (!controller.connected) ...[
                            const SizedBox(height: 7),
                            Text(
                              tr(
                                context,
                                'Подключите рацию в настройках, чтобы начать переписку.',
                                'Connect a radio in Settings to start messaging.',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: style.secondary,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: GlassSurface(
                                radius: 24,
                                color: style.surface,
                                child: TextButton.icon(
                                  onPressed: _openSettings,
                                  icon: const Icon(Icons.cell_tower_rounded),
                                  label: Text(
                                    tr(
                                      context,
                                      'Подключить рацию',
                                      'Connect a radio',
                                    ),
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
              ),
            ),
          if (visible.isEmpty && _archiveRevealed && _archiveAvailable)
            SliverToBoxAdapter(
              child: SizedBox(height: collapseRange + _archiveExtent),
            ),
        ],
      ),
    );
    return Semantics(
      customSemanticsActions: {
        if (_archiveAvailable && hiddenCount > 0)
          CustomSemanticsAction(label: tr(context, 'Архив', 'Archive')): () =>
              _showChats(true),
      },
      child: Listener(
        onPointerDown: (event) {
          if (_canPullArchive) _archivePointer ??= event.pointer;
        },
        onPointerUp: (event) {
          if (event.pointer == _archivePointer) {
            _finishArchiveDrag(released: true);
          }
        },
        onPointerCancel: (event) {
          if (event.pointer == _archivePointer) {
            _finishArchiveDrag(released: false);
          }
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: _trackArchiveScroll,
          child: viewport,
        ),
      ),
    );
  }

  void _setArchiveHidden(bool hidden) {
    if (controller.archiveHidden == hidden) return;
    final radio = controller.active;
    _applyArchivePreference(hidden);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          hidden
              ? tr(context, 'Архив скрыт', 'Archive hidden')
              : tr(context, 'Архив закреплён', 'Archive pinned'),
        ),
        action: SnackBarAction(
          label: tr(context, 'Отменить', 'Undo'),
          onPressed: () {
            if (mounted && controller.active == radio) {
              _applyArchivePreference(!hidden);
            }
          },
        ),
      ),
    );
  }

  void _applyArchivePreference(bool hidden) {
    setState(() {
      _resetArchiveDrag();
      _archiveRevealed = false;
      _archiveSwipeOpen = false;
      _archiveClosingShownRow = hidden;
    });
    controller.setArchiveHidden(hidden);
    _settleArchive();
  }

  String _archiveAction(bool hidden) => hidden
      ? tr(context, 'Закрепить в списке', 'Pin in the list')
      : tr(context, 'Скрыть из списка', 'Hide from the list');

  Future<void> _archiveMenu(Offset position) async {
    final hidden = controller.archiveHidden;
    final radio = controller.active;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final anchor = overlay.globalToLocal(position) & Size.zero;
    final next = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromSize(anchor, overlay.size),
      items: [
        PopupMenuItem(value: !hidden, child: Text(_archiveAction(hidden))),
      ],
    );
    if (mounted && controller.active == radio && next != null) {
      _setArchiveHidden(next);
    }
  }

  Widget _archiveRow(MeshStyle style, int count) {
    final hidden = controller.archiveHidden;
    final shown = !hidden || _archiveRevealed;
    final label = tr(context, 'Архив', 'Archive');
    return AnimatedBuilder(
      animation: Listenable.merge([_archiveProgress, _chatScroll]),
      builder: (context, _) {
        final extent = _archiveExtent;
        final progress = _archiveProgress.value;
        if (progress == 0) return const SizedBox.shrink();
        var visibleFraction = progress;
        if (_archiveCanScrollAway &&
            _chatScroll.hasClients &&
            _chatScroll.position.hasContentDimensions) {
          final covered = math.max(
            0.0,
            _chatScroll.position.extentBefore - _chatScroll.collapseRange,
          );
          visibleFraction = (progress - covered / extent).clamp(0.0, 1.0);
        }
        final opacity = Curves.easeInOut.transform(visibleFraction);
        final displaysArchive = shown || _archiveClosingShownRow;
        final row = ListTile(
          key: const ValueKey('archive-row'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: MeshRowIcon(
            icon: displaysArchive
                ? Icons.archive_outlined
                : _archiveReady
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            tint: displaysArchive || _archiveReady
                ? style.accent
                : style.secondary,
          ),
          title: Text(
            displaysArchive || _archiveIsIos
                ? label
                : _archiveReady
                ? tr(
                    context,
                    'Отпустите, чтобы показать архив',
                    'Release to show Archive',
                  )
                : tr(
                    context,
                    'Потяните, чтобы показать архив',
                    'Pull down to show Archive',
                  ),
          ),
          trailing: displaysArchive ? Text('$count') : null,
          onTap: shown ? () => _showChats(true) : null,
        );
        final content = shown
            ? SwipeActionsRow(
                revealed: _archiveSwipeOpen,
                onReveal: (open) => setState(() => _archiveSwipeOpen = open),
                surface: style.canvas,
                background: style.canvas,
                actions: [
                  (
                    label: _archiveAction(hidden),
                    icon: hidden
                        ? Icons.push_pin_outlined
                        : Icons.visibility_off_outlined,
                    color: style.accent,
                    onTap: () => _setArchiveHidden(!hidden),
                  ),
                ],
                child: Semantics(
                  customSemanticsActions: {
                    CustomSemanticsAction(label: _archiveAction(hidden)): () =>
                        _setArchiveHidden(!hidden),
                  },
                  child: GestureDetector(
                    onLongPressStart: (details) =>
                        unawaited(_archiveMenu(details.globalPosition)),
                    child: row,
                  ),
                ),
              )
            : ExcludeSemantics(child: IgnorePointer(child: row));
        return IgnorePointer(
          ignoring: opacity == 0,
          child: Opacity(
            key: const ValueKey('archive-opacity'),
            opacity: opacity,
            child: ClipRect(
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: progress,
                child: SizedBox(
                  height: extent,
                  child: Center(
                    child: AnimatedPadding(
                      duration: meshMotion(context),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.only(
                        // Center the archive between the visible folder bar
                        // and the avatar of the first chat.
                        bottom: _archivePointer == null
                            ? ChatFolderTabs.verticalInset(context)
                            : 0,
                      ),
                      child: content,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _activeSearchField() {
    final session = _iosSearch;
    return MeshSearchEditor(
      placeholder: tr(context, 'Поиск', 'Search'),
      controller: _search,
      focusNode: _searchFocus,
      iosKey: session,
      onChanged: (text) {
        if (_searchActive && _iosSearch == session) {
          setState(() {
            if (_search.text != text) _search.text = text;
          });
        }
      },
      onDismissKeyboard: _dismissSearchKeyboard,
    );
  }

  Widget _searchResults(MeshStyle style) {
    final query = _search.text.trim().toLowerCase();
    final peers = {for (final peer in controller.peers) peer.id: peer};
    final ordered = <String, Peer>{
      for (final peer in controller.conversations) peer.id: peer,
      ...peers,
    }.values;
    bool matchesFilter(Peer peer) => _inCategory(peer, _searchCategories.shown);
    bool unchanged(Peer peer) =>
        _inCategory(peer, _searchCategories.counterpart);
    final scopedMessages = (controller.cache?.messages ?? const <MeshMessage>[])
        .where((message) {
          final peer = peers[message.chat];
          return peer != null && matchesFilter(peer);
        });
    final seekingMessages = query.isNotEmpty || !_messageSearchFilters.isEmpty;
    final hits = seekingMessages
        ? (scopedMessages
              .where(
                (message) =>
                    _messageSearchFilters.accepts(controller, message, query),
              )
              .toList()
            ..sort((a, b) => b.time.compareTo(a.time)))
        : const <MeshMessage>[];
    final matching = query.isEmpty
        ? [
            for (final id in controller.cache?.searchHistory ?? const [])
              ?peers[id],
          ]
        : [
            for (final peer in ordered)
              if (peer.name.toLowerCase().contains(query)) peer,
          ];
    final results = _messageSearchFilters.isEmpty
        ? matching.where(matchesFilter).toList()
        : <Peer>[];
    final counterpartHasResults = matching.any(unchanged);
    final shortcuts = !seekingMessages
        ? ordered.where(matchesFilter).take(10).toList()
        : <Peer>[];
    final counterpartShortcuts = query.isEmpty
        ? ordered.where(unchanged).take(10).map((peer) => peer.id).toSet()
        : const <String>{};
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismissSearchKeyboard,
      child: NotificationListener<ScrollStartNotification>(
        onNotification: (notice) {
          if (notice.depth == 0 && notice.dragDetails != null) {
            _dismissSearchKeyboard();
          }
          return false;
        },
        child: MeshScrollViewport(
          tint: style.canvas,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 14),
                    child: GlassButton(
                      icon: Icons.tune_rounded,
                      label: tr(
                        context,
                        'Фильтры сообщений',
                        'Message filters',
                      ),
                      primary: !_messageSearchFilters.isEmpty,
                      onTap: () async {
                        _dismissSearchKeyboard();
                        final filters = await showMessageSearchFilters(
                          context,
                          controller: controller,
                          messages: scopedMessages,
                          filters: _messageSearchFilters,
                        );
                        if (mounted && _searchActive && filters != null) {
                          setState(() => _messageSearchFilters = filters);
                        }
                      },
                    ),
                  ),
                ),
              ),
              if (shortcuts.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 95,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                      itemCount: shortcuts.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 9),
                      itemBuilder: (context, index) {
                        final peer = shortcuts[index];
                        return FadeTransition(
                          key: ValueKey(peer.id),
                          opacity: _searchCategories.visibility(
                            shared: counterpartShortcuts.contains(peer.id),
                          ),
                          child: SizedBox(
                            width: 68,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(17),
                              onTap: () => unawaited(_openChat(peer)),
                              child: Column(
                                children: [
                                  MeshAvatar(
                                    peer.name,
                                    size: 55,
                                    channel: peer.channel,
                                    online: controller.isNodeOnline(peer.id),
                                    onTap: () => unawaited(
                                      _openProfile(
                                        peer,
                                        allowReadOnlyChat: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    peer.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (query.isEmpty && results.isNotEmpty)
                SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _searchCategories.visibility(
                      shared: counterpartHasResults,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 17, right: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr(context, 'Недавние', 'Recent'),
                              style: TextStyle(
                                color: style.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: controller.clearSearchHistory,
                            child: Text(tr(context, 'Очистить', 'Clear')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (seekingMessages && results.isEmpty && hits.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: FadeTransition(
                    opacity: _searchCategories.visibility(
                      shared: !counterpartHasResults,
                    ),
                    child: Center(
                      child: Text(
                        tr(context, 'Ничего не найдено', 'No results'),
                        style: TextStyle(color: style.secondary),
                      ),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: results.length,
                  itemBuilder: (_, index) => FadeTransition(
                    key: ValueKey(results[index].id),
                    opacity: _searchCategories.visibility(
                      shared: unchanged(results[index]),
                    ),
                    child: Column(
                      children: [
                        _chatRow(results[index], style),
                        if (index < results.length - 1)
                          Divider(
                            height: 1,
                            indent: 79,
                            color: style.separator,
                          ),
                      ],
                    ),
                  ),
                ),
              if (hits.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 9, 16, 0),
                    child: Text(
                      tr(context, 'Сообщения', 'Messages'),
                      style: TextStyle(
                        color: style.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (hits.isNotEmpty)
                SliverList.builder(
                  itemCount: hits.length,
                  itemBuilder: (_, index) {
                    final message = hits[index];
                    return MessageSearchResultTile(
                      key: ValueKey((message.chat, message.id)),
                      controller: controller,
                      message: message,
                      query: query,
                      chatName: peers[message.chat]?.name,
                      onTap: () {
                        _dismissSearchKeyboard();
                        controller.rememberSearch(message.chat);
                        if (_split) _exitSearch();
                        unawaited(
                          openMeshMessage(
                            context,
                            controller: controller,
                            chatId: message.chat,
                            messageId: message.id,
                            open: _openDetail,
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chatRow(
    Peer peer,
    MeshStyle style, {
    bool editing = false,
    bool selected = false,
    bool pinned = false,
    int reorderIndex = 0,
    VoidCallback? onTap,
  }) {
    final message = controller.messages(peer.id).lastOrNull;
    final unread = controller.cache?.unread[peer.id] ?? 0;
    final markedUnread =
        controller.cache?.markedUnread.contains(peer.id) ?? false;
    final muted = controller.cache?.muted.contains(peer.id) ?? false;
    final draft = controller.draft(peer.id);
    final summary = draft.isNotEmpty
        ? '${tr(context, 'Черновик', 'Draft')}: $draft'
        : message?.text ??
              (peer.channel ? tr(context, 'Канал', 'Channel') : '');
    final current = _split && _detailOpen && _detailPeer == peer.id;
    Widget row(BuildContext rowContext, {bool preview = false}) => InkWell(
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      onTap: preview ? null : onTap ?? () => unawaited(_openChat(peer)),
      onSecondaryTapDown:
          !preview && !editing && !_searchActive && meshDesktop(context)
          ? (details) =>
                unawaited(_showChatContextMenu(peer, details.globalPosition))
          : null,
      onLongPress: preview || editing || _searchActive
          ? null
          : () async {
              final box = rowContext.findRenderObject() as RenderBox;
              final navigator = Navigator.of(rowContext, rootNavigator: true);
              final overlay = navigator.overlay!.context.findRenderObject();
              final anchor = box.localToGlobal(Offset.zero, ancestor: overlay);
              final profile = controller.active;
              final folder = _chatFolder;
              final open = await showMeshChatPreview(
                rowContext,
                controller,
                peer,
                anchor & box.size,
                sourceRow: Material(
                  type: MaterialType.transparency,
                  child: row(rowContext, preview: true),
                ),
                actions: _previewActions(peer, folder, profile),
                backdropSource: _previewBackground,
              );
              if (open && mounted && controller.active == profile) {
                await _openChat(peer);
              }
            },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 17, 8),
        child: Row(
          children: [
            if (editing) ...[
              Semantics(
                checked: selected,
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 24,
                  color: selected ? style.accent : style.secondary,
                ),
              ),
              const SizedBox(width: 9),
            ],
            MeshAvatar(
              peer.name,
              size: 52,
              channel: peer.channel,
              online: controller.isNodeOnline(peer.id),
              onTap: editing || preview
                  ? null
                  : () =>
                        unawaited(_openProfile(peer, allowReadOnlyChat: true)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          peer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: style.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (muted)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.notifications_off_outlined,
                            size: 14,
                            color: style.secondary,
                          ),
                        ),
                      if (pinned)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.push_pin_rounded,
                            size: 14,
                            color: style.secondary,
                            semanticLabel: tr(context, 'Закреплён', 'Pinned'),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  EmojiText(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: draft.isNotEmpty ? style.accent : style.secondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            if (editing)
              ReorderableDragStartListener(
                index: reorderIndex,
                enabled: !_removingChats,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 2, 12),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    color: style.secondary,
                    size: 24,
                  ),
                ),
              ),
            if (!editing &&
                (message != null || unread > 0 || markedUnread)) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (message != null)
                    Text(
                      MaterialLocalizations.of(
                        context,
                      ).formatTimeOfDay(TimeOfDay.fromDateTime(message.time)),
                      style: TextStyle(color: style.secondary, fontSize: 12),
                    ),
                  if (unread > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: muted ? style.field : style.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$unread',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: muted
                                ? style.secondary
                                : style.dark
                                ? const Color(0xff0f2445)
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (unread == 0 && markedUnread)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Semantics(
                        label: tr(
                          context,
                          'Отмечено как непрочитанное',
                          'Marked unread',
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: muted ? style.secondary : style.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: 10),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    final chat = Builder(builder: row);
    if (!_split || editing) return chat;
    return Semantics(
      selected: current,
      child: Material(
        color: current ? style.selection : Colors.transparent,
        child: chat,
      ),
    );
  }

  Future<void> _showChatContextMenu(Peer peer, Offset position) async {
    final actions = _previewActions(peer, _chatFolder, controller.active);
    if (actions.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final selection = await showMenu<int>(
      context: context,
      position: RelativeRect.fromSize(
        overlay.globalToLocal(position) & Size.zero,
        overlay.size,
      ),
      items: [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem(
            value: i,
            child: Text(
              actions[i].label,
              style: actions[i].destructive
                  ? TextStyle(color: MeshStyle.of(context).error)
                  : null,
            ),
          ),
      ],
    );
    if (mounted && selection != null) actions[selection].onTap();
  }

  String? get _status => switch (controller.linkState) {
    _ when controller.reconnecting => tr(
      context,
      'Переподключение…',
      'Reconnecting…',
    ),
    LinkState.online => null,
    LinkState.connecting => tr(context, 'Подключение…', 'Connecting…'),
    LinkState.offline when controller.error == 'notNearby' => tr(
      context,
      'Рация не найдена по BLE',
      'Radio not found over BLE',
    ),
    LinkState.offline => tr(context, 'Не подключено', 'Disconnected'),
  };

  Widget _settings(MeshStyle style, {BuildContext? panelContext}) {
    final profile = controller.profileName.isEmpty
        ? appName
        : controller.profileName;
    final active = controller.active;
    final busy = controller.linkState == LinkState.connecting;
    return ProfilePage(
      key: const PageStorageKey('settings'),
      identity:
          (active == null ? null : controller.radioPublicKey(active)) ??
          'local:$profile',
      heading: tr(context, 'Настройки', 'Settings'),
      title: profile,
      subtitle:
          active?.name ?? tr(context, 'Локальный профиль', 'Local profile'),
      avatar: MeshAvatar(profile, size: 90),
      avatarSize: 90,
      leading: panelContext == null
          ? null
          : GlassButton(
              icon: Icons.arrow_back_rounded,
              label: tr(context, 'Назад', 'Back'),
              onTap: () => Navigator.of(panelContext).maybePop(),
            ),
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: _scrollBottom,
      ),
      trailing: GlassButton(
        icon: Icons.edit_outlined,
        label: tr(context, 'Изменить имя', 'Edit name'),
        onTap: _editProfile,
      ),
      children: [
        _sectionTitle(tr(context, 'Рации', 'Radios'), style),
        _settingsGroup([
          for (final radio in controller.radios) _radioRow(radio),
          MeshRow(
            title: tr(context, 'Добавить рацию', 'Add a radio'),
            titleColor: style.accent,
            icon: Icons.add_rounded,
            tint: _blue,
            showChevron: false,
            onTap: busy ? null : _discoverRadios,
          ),
          if (controller.usbTransport != null)
            MeshRow(
              title: tr(context, 'Подключить по USB', 'Connect over USB'),
              icon: Icons.usb_rounded,
              tint: _teal,
              onTap: busy
                  ? null
                  : () => unawaited(
                      _openWorkspacePage(
                        (_) => UsbRadioPage(controller: controller),
                      ),
                    ),
            ),
          if (controller.usbTransport case final DesktopUsbTransport usb)
            MeshRow(
              title: tr(context, 'Прошивки', 'Firmware'),
              icon: Icons.memory_rounded,
              tint: _violet,
              onTap: () =>
                  unawaited(_openWorkspacePage((_) => FirmwarePage(usb: usb))),
            ),
        ]),
        if (busy || controller.scanning)
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 10, 25, 0),
            child: LinearProgressIndicator(
              borderRadius: BorderRadius.circular(3),
              minHeight: 2,
            ),
          ),
        if (controller.bluetoothProblem case final bluetooth?) ...[
          _statusLine(
            bluetoothProblemMessage(context, bluetooth),
            style.warning,
          ),
          if (bluetooth == BluetoothProblem.off &&
              controller.canEnableBluetooth &&
              Theme.of(context).platform == TargetPlatform.android)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: GlassActionButton(
                label: tr(context, 'Включить Bluetooth', 'Turn on Bluetooth'),
                onTap: () async {
                  if (await controller.enableBluetooth() &&
                      mounted &&
                      active != null) {
                    await controller.connect(active);
                  }
                },
              ),
            ),
        ] else if (controller.error != null)
          _statusLine(switch (controller.error) {
            'bluetooth' => tr(
              context,
              'Проверьте Bluetooth и разрешение на поиск.',
              'Check Bluetooth and scanning permission.',
            ),
            'lost' => tr(
              context,
              'Связь с рацией потеряна.',
              'Connection to the radio was lost.',
            ),
            _ => tr(
              context,
              'Подключение не удалось. Проверьте рацию и повторите попытку.',
              'Connection failed. Check your radio and try again.',
            ),
          }, style.warning),
        const SizedBox(height: 20),
        _settingsGroup([
          MeshRow(
            title: tr(context, 'Узлы', 'Nodes'),
            icon: Icons.hub_outlined,
            tint: _violet,
            detail: '${controller.peers.where((peer) => !peer.channel).length}',
            onTap: _nodes,
          ),
        ]),
        const SizedBox(height: 14),
        _settingsGroup([
          MeshRow(
            title: tr(context, 'Оформление', 'Appearance'),
            icon: Icons.dark_mode_outlined,
            tint: _blue,
            detail: _appearanceName(controller.appearance),
            onTap: _appearance,
          ),
          if (widget.notifications case final notifications?)
            MeshRow(
              title: tr(context, 'Уведомления', 'Notifications'),
              icon: Icons.notifications_outlined,
              tint: _blue,
              onTap: () => unawaited(
                _openWorkspacePage(
                  (_) => NotificationSettingsPage(
                    controller: controller,
                    notifications: notifications,
                    configureWifi: () => _configureWifiPush(notifications),
                  ),
                ),
              ),
            ),
          MeshRow(
            title: tr(context, 'О приложении', 'About'),
            icon: Icons.info_outline_rounded,
            tint: _teal,
            onTap: () =>
                unawaited(_openWorkspacePage((_) => const AboutPage())),
          ),
        ]),
        const SizedBox(height: 14),
        _settingsGroup([
          MeshRow(
            title: tr(context, 'Избранное', 'Saved Messages'),
            icon: Icons.bookmark_border_rounded,
            tint: _blue,
            onTap: () => unawaited(
              showSavedChat(context, controller, open: _openDetail),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _radioRow(Radio radio) {
    final id = radioKey(radio);
    final style = MeshStyle.of(context);
    final active = controller.active;
    final selected = active != null && radioKey(active) == id;
    final connected = controller.isConnectedTo(radio);
    final opened = _revealedRadio == id;
    final canConfigure = controller.canConfigureRadio(radio);
    final unread = selected ? 0 : controller.unreadFor(radio);
    final route = controller.connectionRoute(radio);
    final local = lanEndpoint(route) != null;
    final usb = usbPortOf(route) != null;
    final (iconTint, glyphColor) = switch ((connected, selected)) {
      (true, true) => (const Color(0xffd5e88b), const Color(0xff253315)),
      (true, false) => (const Color(0xffa9e0b4), const Color(0xff173c26)),
      _ => (const Color(0xff6a7280), Colors.white),
    };
    final status = selected ? _status : null;
    final connectionLabel = [
      controller.label(radio.network),
      if (usb) 'USB',
      ?status,
    ].join(' · ');
    void close() => setState(() => _revealedRadio = null);
    void configure() => unawaited(_showRadioSettings(radio));
    return RadioSwipeRow(
      key: ValueKey(id),
      revealed: opened,
      onReveal: (reveal) => setState(() => _revealedRadio = reveal ? id : null),
      onDisconnect: controller.stateFor(radio) != LinkState.offline
          ? () {
              close();
              unawaited(controller.disconnectRadio(radio));
            }
          : null,
      onRemove: () {
        close();
        unawaited(_forgetRadio(radio));
      },
      child: Material(
        color: style.surface,
        child: MeshRow(
          title: radio.name,
          leading: Semantics(
            label: usb
                ? 'USB'
                : local
                ? 'Wi-Fi'
                : 'Bluetooth',
            child: MeshRowIcon(
              icon: usb
                  ? Icons.usb_rounded
                  : local
                  ? Icons.wifi_rounded
                  : Icons.bluetooth_rounded,
              tint: iconTint,
              glyphColor: glyphColor,
            ),
          ),
          subtitle: connectionLabel,
          selected: selected,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (connected)
                RadioConnectionStatus(
                  rssi: controller.signalFor(radio),
                  latency: controller.latencyFor(radio),
                  battery: controller.batteryFor(radio),
                  wifi: local,
                ),
              if (unread > 0) ...[
                if (connected) const SizedBox(width: 8),
                MeshUnreadBadge(unread),
              ],
            ],
          ),
          onTap: () {
            if (opened) {
              close();
            } else if (selected && canConfigure) {
              configure();
            } else {
              unawaited(controller.connect(radio));
            }
          },
          onLongPress: () =>
              setState(() => _revealedRadio = opened ? null : id),
        ),
      ),
    );
  }

  Future<void> _forgetRadio(Radio radio) async {
    final confirmed = await showMeshDialog<bool>(
      context: context,
      builder: (context) => MeshDialog(
        title: Text(tr(context, 'Удалить рацию?', 'Remove radio?')),
        content: Text(radio.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Удалить', 'Remove')),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.forget(radio);
  }

  Widget _sectionTitle(String title, MeshStyle style) => Padding(
    padding: const EdgeInsets.fromLTRB(25, 0, 20, 7),
    child: Text(
      title,
      style: TextStyle(
        color: style.secondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _statusLine(String text, Color color) => Padding(
    padding: const EdgeInsets.fromLTRB(23, 10, 23, 0),
    child: Text(text, style: TextStyle(color: color, fontSize: 14)),
  );

  Widget _settingsGroup(List<Widget> rows) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: MeshGroup(children: rows),
  );

  void _discoverRadios() => unawaited(
    _openWorkspacePage((_) => RadioDiscoveryPage(controller: controller)),
  );

  void _nodes() => unawaited(
    _openWorkspacePage(
      (_) => MeshNodesPage(
        controller: controller,
        openChat: (peer) =>
            controller.canOpenChat(peer) ? _openChat(peer) : _openProfile(peer),
        openProfile: _openProfile,
      ),
    ),
  );

  void _editProfile() {
    var name = controller.profileName;
    unawaited(
      showMeshSheet<void>(
        context: context,
        builder: (context) => SheetBody(
          title: tr(context, 'Имя профиля', 'Profile name'),
          children: [
            TextFormField(
              initialValue: name,
              onChanged: (value) => name = value,
              maxLength: 30,
              decoration: InputDecoration(
                labelText: tr(context, 'Ваше имя', 'Your name'),
              ),
            ),
            GlassActionButton(
              onTap: () {
                controller.setName(name);
                Navigator.pop(context);
              },
              label: tr(context, 'Сохранить', 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  String _appearanceName(String mode) => switch (mode) {
    'dark' => tr(context, 'Тёмное', 'Dark'),
    'light' => tr(context, 'Светлое', 'Light'),
    _ => tr(context, 'Как в системе', 'System'),
  };

  void _appearance() => unawaited(
    showMeshSheet<void>(
      context: context,
      builder: (context) => SheetBody(
        title: tr(context, 'Оформление', 'Appearance'),
        children: [
          MeshGroup(
            children: [
              for (final value in ['system', 'light', 'dark'])
                MeshRow(
                  title: _appearanceName(value),
                  icon: Icons.contrast_rounded,
                  tint: _blue,
                  selected: value == controller.appearance,
                  onTap: () {
                    controller.setAppearance(value);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
          if (Theme.of(context).platform == TargetPlatform.android)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => MeshGroup(
                  children: [
                    SwitchListTile.adaptive(
                      title: Text(
                        tr(
                          context,
                          'Скрывать системную панель',
                          'Hide system navigation bar',
                        ),
                      ),
                      subtitle: Text(
                        tr(
                          context,
                          'Свайп снизу временно вернёт кнопки',
                          'Swipe up from the bottom to reveal it',
                        ),
                      ),
                      value: controller.hideSystemNavigation,
                      onChanged: (hidden) {
                        controller.setHideSystemNavigation(hidden);
                        unawaited(_applySystemNavigation());
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
