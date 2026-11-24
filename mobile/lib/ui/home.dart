// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter/services.dart';

import '../app_name.dart';
import '../local_notifications.dart';
import '../mesh/controller.dart';
import '../mesh/network.dart';
import '../mesh/store.dart';
import 'about.dart';
import 'chat.dart';
import 'chat_folders.dart';
import 'chat_management.dart';
import 'chat_setup.dart';
import 'emoji_text.dart';
import 'radio_discovery.dart';
import 'ios_control.dart';
import 'navigation.dart';
import 'nodes.dart';
import 'notification_settings.dart';
import 'radio_settings.dart';
import 'saved_messages.dart';
import 'profile_page.dart';
import 'search_field.dart';
import 'mesh_scroll_edge.dart';
import 'message_search.dart';
import 'style.dart';
import 'page_route.dart';

const _blue = Color(0xff2978d5);
const _teal = Color(0xff168a87);
const _violet = Color(0xff7b5bc3);

class MeshHome extends StatefulWidget {
  const MeshHome({super.key, required this.controller, this.notifications});
  final MeshController controller;
  final LocalMessageNotifications? notifications;

  @override
  State<MeshHome> createState() => _HomeState();
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
  String? _revealedChat;
  String? _chatFolderView;
  final _selectedChats = <String>{};
  late final AppLifecycleListener _lifecycle;
  MeshController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
    if (controller.hideSystemNavigation) unawaited(_applySystemNavigation());
    _lifecycle = AppLifecycleListener(
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
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    controller.removeListener(_changed);
    _search.dispose();
    _searchFocus.dispose();
    _chatScroll.dispose();
    _searchMotion.dispose();
    _tabs.opacity.dispose();
    _chatCategories.opacity.dispose();
    _searchCategories.opacity.dispose();
    super.dispose();
  }

  void _openSettings() {
    _selectTab(1);
  }

  void _selectTab(int index) {
    FocusScope.of(context).unfocus();
    _select(_tabs, index);
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
    await showMeshChat(context, controller, peer);
  }

  Future<void> _openProfile(Peer peer, {bool allowReadOnlyChat = false}) async {
    if (_searchActive) _dismissSearchKeyboard();
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push<void>(
      meshPageRoute(
        context,
        builder: (_) => MeshChatProfile(
          controller: controller,
          peer: peer,
          openNewChat: true,
          allowReadOnlyChat: allowReadOnlyChat,
        ),
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
    setState(() {
      _iosSearch = GlobalKey();
      _searchActive = true;
      _searchCategories.jumpTo(_chatCategories.selected);
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

  Future<void> _showRadioSettings(Radio radio) => Navigator.of(context).push(
    radioSettingsRoute(
      context,
      RadioSettingsPage(controller: controller, radio: radio),
    ),
  );

  void _toggleChatEditing() {
    if (_removingChats) return;
    setState(() {
      _editingChats = !_editingChats;
      _revealedChat = null;
      _selectedChats.clear();
    });
  }

  void _showChats(bool hidden) => setState(() {
    _showHidden = hidden;
    _revealedChat = null;
    _selectedChats.clear();
  });

  static bool _inCategory(Peer peer, int filter) => switch (filter) {
    1 => !peer.channel,
    2 => peer.channel,
    _ => true,
  };

  ChatFolder? get _chatFolder =>
      _showHidden ? null : controller.cache?.folders[_chatFolderView];

  List<Peer> _visibleChats([int? filter]) {
    final folder = _chatFolder;
    final unread = !_showHidden && _chatFolderView == 'unread';
    final chats = _showHidden
        ? controller.hiddenConversations
        : controller.conversations;
    final peers = {
      for (final peer in chats)
        if (_inCategory(peer, filter ?? _chatCategories.shown) &&
            (!unread || controller.isChatUnread(peer.id)) &&
            (folder == null || folder.chats.contains(peer.id)))
          peer.id: peer,
    };
    if (folder == null) return peers.values.toList();
    return [for (final id in folder.pinned) ?peers.remove(id), ...peers.values];
  }

  void _setFolderView(String? value) => setState(() {
    _chatFolderView = value;
    _revealedChat = null;
    _selectedChats.clear();
  });

  Future<void> _editFolder(ChatFolder? folder) async {
    final profile = controller.active;
    final result = await editChatFolder(
      context,
      folder: folder,
      chats: [...controller.conversations, ...controller.hiddenConversations],
    );
    if (!mounted || controller.active != profile || result == null) return;
    final id = controller.saveChatFolder(
      id: folder?.id,
      name: result.name,
      chats: result.chats,
    );
    if (id != null) _setFolderView(id);
  }

  Widget _folderPicker() {
    final folder = _chatFolder;
    final unread = tr(context, 'Непрочитанные', 'Unread');
    final label =
        folder?.name ??
        (_chatFolderView == 'unread'
            ? unread
            : tr(context, 'Папки', 'Folders'));
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: GlassSurface(
        radius: 24,
        child: PopupMenuButton<String>(
          tooltip: tr(context, 'Папки чатов', 'Chat folders'),
          enabled: !_editingChats,
          onSelected: (value) {
            switch (value) {
              case 'all':
                _setFolderView(null);
              case 'new':
                unawaited(_editFolder(null));
              case 'edit':
                unawaited(_editFolder(folder));
              case 'remove':
                if (folder != null) {
                  controller.removeChatFolder(folder.id);
                  _setFolderView(null);
                }
              default:
                _setFolderView(value);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'all',
              child: Text(tr(context, 'Все чаты', 'All chats')),
            ),
            PopupMenuItem(value: 'unread', child: Text(unread)),
            for (final entry in controller.chatFolders)
              PopupMenuItem(value: entry.id, child: Text(entry.name)),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'new',
              child: Text(tr(context, 'Новая папка', 'New folder')),
            ),
            if (folder != null) ...[
              PopupMenuItem(
                value: 'edit',
                child: Text(tr(context, 'Изменить папку', 'Edit folder')),
              ),
              PopupMenuItem(
                value: 'remove',
                child: Text(tr(context, 'Удалить папку', 'Delete folder')),
              ),
            ],
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_outlined, size: 18),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.expand_more_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
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
    final style = MeshStyle.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final nativeNavigation = useIosControls;
    return PopScope(
      canPop: !_searchActive && !_editingChats && !_showHidden,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_searchActive) {
          _exitSearch();
        } else if (_editingChats) {
          _toggleChatEditing();
        } else if (_showHidden) {
          _showChats(false);
        }
      },
      child: Scaffold(
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
                    child: _tabs.shown == 0
                        ? _chatScene(style, keyboard)
                        : _settings(style),
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
              else if (!_searchActive)
                Positioned(
                  left: nativeNavigation ? 0 : 14,
                  right: nativeNavigation ? 0 : 14,
                  bottom: MeshNavigation.bottomBarOffset(context),
                  child: ExcludeSemantics(
                    excluding: keyboard > 0,
                    child: IgnorePointer(
                      ignoring: keyboard > 0,
                      child: MeshNavigation(
                        index: _tabs.selected,
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
      ),
    );
  }

  double get _scrollBottom =>
      MeshNavigation.contentHeight(context) +
      MeshNavigation.bottomContentInset(context) +
      9;

  Widget _chatScene(MeshStyle style, double keyboard) => LayoutBuilder(
    builder: (context, constraints) {
      final safe = MediaQuery.paddingOf(context);
      final scaler = MediaQuery.textScalerOf(context);
      final caption = _showHidden
          ? tr(context, 'Скрытые чаты', 'Hidden chats')
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
        ..reduceMotion = MediaQuery.disableAnimationsOf(context);
      final normalFieldTop = safe.top + headingHeight + 3;
      final normalCategoriesTop = normalFieldTop + fieldHeight + 9;
      final categoryHeight = ChatFilters.contentHeight(context);
      final categoriesInChats =
          (_showHidden
                  ? controller.hiddenConversations
                  : controller.conversations)
              .isNotEmpty;
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
      final heading = PageHeading(
        caption,
        sideWidth: _editingChats || _showHidden ? 92 : 104,
        leading: GlassActionButton(
          primary: false,
          width: _editingChats ? 84 : 68,
          label: _editingChats
              ? tr(context, 'Готово', 'Done')
              : tr(context, 'Изм.', 'Edit'),
          onTap: _removingChats || (!categoriesInChats && !_editingChats)
              ? null
              : _toggleChatEditing,
        ),
        trailing: _editingChats || _showHidden
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassButton(
                    icon: Icons.bookmark_border_rounded,
                    label: tr(context, 'Избранное', 'Saved Messages'),
                    onTap: () => unawaited(
                      Navigator.of(context).push<void>(
                        meshPageRoute(
                          context,
                          builder: (_) =>
                              SavedMessagesPage(controller: controller),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GlassButton(
                    icon: Icons.edit_note_rounded,
                    label: tr(context, 'Новый чат', 'New chat'),
                    primary: true,
                    onTap: _newChat,
                  ),
                ],
              ),
      );
      final categoryBar = ChatFilters(
        selected: _searchActive
            ? _searchCategories.selected
            : _chatCategories.selected,
        onSelect: (index) {
          if (_searchActive) {
            _select(_searchCategories, index);
          } else if (!_removingChats && index != _chatCategories.selected) {
            _revealedChat = null;
            _selectedChats.clear();
            _select(_chatCategories, index);
          }
        },
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
    final visible = _visibleChats();
    Widget item(BuildContext context, int index) {
      final peer = visible[index];
      final row = _chatRow(
        peer,
        style,
        editing: _editingChats,
        reorderIndex: index,
        selected: _selectedChats.contains(peer.id),
        pinned: folder?.pinned.contains(peer.id) ?? false,
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
          shared: _inCategory(peer, _chatCategories.counterpart),
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
                onPin: folder == null
                    ? null
                    : () {
                        setState(() => _revealedChat = null);
                        controller.toggleFolderPin(folder.id, peer.id);
                      },
                pinned: folder?.pinned.contains(peer.id) ?? false,
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

    return MeshScrollViewport(
      tint: style.canvas,
      fadeTop: false,
      edgeExtent: _scrollBottom,
      child: CustomScrollView(
        key: const PageStorageKey('chats'),
        controller: _chatScroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
          if (!_showHidden && controller.active != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: _folderPicker(),
              ),
            ),
          if (_showHidden || hiddenCount > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GlassActionButton(
                    width: 166,
                    height: 38,
                    primary: false,
                    label: _showHidden
                        ? tr(context, 'Все чаты', 'All chats')
                        : tr(
                            context,
                            'Скрытые ($hiddenCount)',
                            'Hidden ($hiddenCount)',
                          ),
                    onTap: _editingChats
                        ? null
                        : () => _showChats(!_showHidden),
                  ),
                ),
              ),
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
                          collapseRange -
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
        ],
      ),
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
                        unawaited(
                          openMeshMessage(
                            context,
                            controller: controller,
                            chatId: message.chat,
                            messageId: message.id,
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
    Widget row(BuildContext rowContext) => InkWell(
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      onTap: onTap ?? () => unawaited(_openChat(peer)),
      onLongPress: editing || _searchActive
          ? null
          : () async {
              final box = rowContext.findRenderObject() as RenderBox;
              final navigator = Navigator.of(rowContext, rootNavigator: true);
              final overlay = navigator.overlay!.context.findRenderObject();
              final anchor = box.localToGlobal(Offset.zero, ancestor: overlay);
              final profile = controller.active;
              final open = await showMeshChatPreview(
                rowContext,
                controller,
                peer,
                anchor & box.size,
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
              onTap: editing
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
    return Builder(builder: row);
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

  Widget _settings(MeshStyle style) {
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
                Navigator.of(context).push<void>(
                  meshPageRoute(
                    context,
                    builder: (_) => NotificationSettingsPage(
                      controller: controller,
                      notifications: notifications,
                      configureWifi: () => _configureWifiPush(notifications),
                    ),
                  ),
                ),
              ),
            ),
          MeshRow(
            title: tr(context, 'О приложении', 'About'),
            icon: Icons.info_outline_rounded,
            tint: _teal,
            onTap: () => unawaited(
              Navigator.of(context).push(
                meshPageRoute<void>(context, builder: (_) => const AboutPage()),
              ),
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
    final local = lanEndpoint(controller.connectionRoute(radio)) != null;
    final (iconTint, glyphColor) = switch ((connected, selected)) {
      (true, true) => (const Color(0xffd5e88b), const Color(0xff253315)),
      (true, false) => (const Color(0xffa9e0b4), const Color(0xff173c26)),
      _ => (const Color(0xff6a7280), Colors.white),
    };
    final status = selected ? _status : null;
    final connectionLabel = [
      controller.label(radio.network),
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
            label: local ? 'Wi-Fi' : 'Bluetooth',
            child: MeshRowIcon(
              icon: local ? Icons.wifi_rounded : Icons.bluetooth_rounded,
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
    Navigator.of(context).push<void>(
      meshPageRoute(
        context,
        builder: (_) => RadioDiscoveryPage(controller: controller),
      ),
    ),
  );

  void _nodes() => unawaited(
    Navigator.of(context).push<void>(
      meshPageRoute(
        context,
        builder: (_) => MeshNodesPage(
          controller: controller,
          openChat: (peer) => controller.canOpenChat(peer)
              ? _openChat(peer)
              : _openProfile(peer),
          openProfile: _openProfile,
        ),
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
