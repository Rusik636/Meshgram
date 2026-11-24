// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

part of 'chat.dart';

Future<void> showSavedChat(
  BuildContext context,
  MeshController controller, {
  MeshChatOpener? open,
}) => _pushConversation(
  context,
  (_) => SavedMessagesPage(controller: controller),
  open: open,
);

class SavedMessagesPage extends StatefulWidget {
  const SavedMessagesPage({super.key, required this.controller});

  final MeshController controller;

  @override
  State<SavedMessagesPage> createState() => _SavedMessagesPageState();
}

class _SavedMessagesPageState extends State<SavedMessagesPage> {
  MeshController get controller => widget.controller;
  late final _draft = EmojiEditingController(
    text: controller.store.savedChatDraft,
  );
  final _scroll = ScrollController();
  final _input = GlobalKey<MessageInputState>();
  bool _saving = false;

  @override
  void dispose() {
    _scroll.dispose();
    _draft.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    final draft = _draft.text;
    if (_saving || draft.trim().isEmpty) return;
    setState(() => _saving = true);
    final saved = await controller.saveOwnNote(draft);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) {
      _notice(
        context,
        tr(context, 'Не удалось сохранить заметку', 'Could not save the note'),
      );
      return;
    }
    if (_draft.text == draft) {
      _draft.clear();
      unawaited(controller.store.setSavedChatDraft(''));
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _notice(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _openRadioProfile() {
    final radio = controller.active;
    if (radio == null) return;
    unawaited(
      Navigator.of(context).push(
        radioSettingsRoute(
          context,
          RadioSettingsPage(controller: controller, radio: radio),
        ),
      ),
    );
  }

  Future<void> _openSource(BuildContext context, SavedMessage item) async {
    if (!controller.selectSavedMessageSource(item)) {
      _notice(
        context,
        tr(
          context,
          'Сообщения больше нет в локальной истории',
          'This message is no longer in local history',
        ),
      );
      return;
    }
    await openMeshMessage(
      context,
      controller: controller,
      chatId: item.message.chat,
      messageId: item.message.id,
    );
  }

  Future<void> _editLabels(BuildContext context, SavedMessage item) async {
    final title = tr(context, 'Метки', 'Labels');
    var value = item.labels.join(', ');
    final labels = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: value,
          autofocus: true,
          onChanged: (text) => value = text,
          decoration: InputDecoration(
            helperText: tr(
              context,
              'Через запятую',
              'Separate labels with commas',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, value),
            child: Text(tr(context, 'Сохранить', 'Save')),
          ),
        ],
      ),
    );
    if (labels == null) return;
    if (!await controller.setSavedLabels(item, labels.split(',')) &&
        context.mounted) {
      _notice(
        context,
        tr(context, 'Не удалось сохранить метки', 'Could not save labels'),
      );
    }
  }

  Future<void> _remove(BuildContext context, SavedMessage item) async {
    if (!await controller.removeSavedMessage(item) && context.mounted) {
      _notice(
        context,
        tr(
          context,
          'Не удалось удалить копию',
          'Could not remove the saved copy',
        ),
      );
    }
  }

  Future<void> _messageActions(SavedMessage item, Rect anchor) async {
    final box = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromSize(
        box.globalToLocal(anchor.topLeft) & anchor.size,
        box.size,
      ),
      items: [
        PopupMenuItem(
          value: 'copy',
          child: Text(tr(context, 'Копировать', 'Copy')),
        ),
        if (!item.isNote)
          PopupMenuItem(
            value: 'source',
            child: Text(tr(context, 'К оригиналу', 'Go to original')),
          ),
        PopupMenuItem(
          value: 'labels',
          child: Text(tr(context, 'Метки', 'Labels')),
        ),
        PopupMenuItem(
          value: 'remove',
          child: Text(tr(context, 'Удалить', 'Delete')),
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: item.message.text));
      case 'source':
        await _openSource(context, item);
      case 'labels':
        await _editLabels(context, item);
      case 'remove':
        await _remove(context, item);
    }
  }

  Widget _bubble(SavedMessage item, BuildContext context) {
    final position = chatPosition(item.message.text);
    final source = item.isNote
        ? null
        : _SavedSource(
            item: item,
            onTap: () => unawaited(_openSource(context, item)),
          );
    final content = [
      ?source,
      if (position != null && !position.standalone)
        MeshLocationPreview(position: position.point, loadTiles: false),
      if (item.labels.isNotEmpty)
        Wrap(
          spacing: 6,
          runSpacing: 2,
          children: [for (final label in item.labels) Chip(label: Text(label))],
        ),
    ];
    return _Bubble(
      key: ValueKey(item.key),
      item: MeshMessage(
        id: item.message.id,
        chat: 'self:saved',
        author: '',
        text: item.message.text,
        time: item.savedAt,
        delivery: Delivery.acknowledged,
      ),
      emoji: null,
      channel: false,
      joinsPrevious: false,
      joinsNext: false,
      quoted: null,
      reactions: const [],
      hideText: false,
      standalonePosition: position?.standalone == true ? position?.point : null,
      localOnly: true,
      link: firstMessageLink(item.message.text),
      preview: content.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content,
            ),
      onMenu: (anchor) => unawaited(_messageActions(item, anchor)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final pane = ChatWorkspacePane.of(context);
    final split = pane?.split ?? false;
    final covered =
        pane?.visible == false || ModalRoute.isCurrentOf(context) == false;
    final radio = controller.active;
    final name = controller.profileName.trim();
    final editor = MessageInput(
      key: _input,
      controller: _draft,
      onChanged: (value) =>
          unawaited(controller.store.setSavedChatDraft(value)),
      coveredByModal: covered,
    );
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const MeshChatWallpaper(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    ChatWorkspacePane.toolbarTop(context),
                    14,
                    5,
                  ),
                  child: Row(
                    children: [
                      GlassButton(
                        icon: split
                            ? Icons.close_rounded
                            : Icons.arrow_back_ios_new_rounded,
                        label: split
                            ? tr(context, 'Закрыть чат', 'Close chat')
                            : tr(context, 'Назад', 'Back'),
                        onTap: () => Navigator.pop(context),
                        coveredByModal: covered,
                      ),
                      Expanded(
                        child: Center(
                          child: _ChatTitle(
                            name: name.isEmpty ? radio?.name ?? appName : name,
                            subtitle: tr(
                              context,
                              'Избранное',
                              'Saved Messages',
                            ),
                            nativeProperties: useIosControls
                                ? {
                                    'dark': style.dark,
                                    'enabled': radio != null,
                                    'coveredByModal': covered,
                                    'foreground': style.text.toARGB32(),
                                    'secondary': style.secondary.toARGB32(),
                                    'surface': style.surface.toARGB32(),
                                  }
                                : null,
                            onTap: radio == null ? null : _openRadioProfile,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      final items = controller.savedMessages;
                      if (items.isEmpty) {
                        return Center(
                          child: GlassSurface(
                            radius: 15,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              child: Text(
                                tr(
                                  context,
                                  'Начало переписки',
                                  'Start of conversation',
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      return ListView.builder(
                        reverse: true,
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(11, 5, 11, 8),
                        itemCount: items.length,
                        itemBuilder: (context, index) =>
                            _bubble(items[index], context),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: TextFieldTapRegion(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: useIosControls
                              ? editor
                              : GlassSurface(radius: 23, child: editor),
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder(
                          valueListenable: _draft,
                          builder: (context, value, _) {
                            final enabled =
                                !_saving && value.text.trim().isNotEmpty;
                            return GlassButton(
                              icon: Icons.arrow_upward_rounded,
                              label: tr(
                                context,
                                'Сохранить заметку',
                                'Save note',
                              ),
                              primary: enabled,
                              onTap: enabled
                                  ? () => unawaited(_saveNote())
                                  : null,
                              coveredByModal: covered,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedSource extends StatelessWidget {
  const _SavedSource({required this.item, required this.onTap});

  final SavedMessage item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final localizations = MaterialLocalizations.of(context);
    final time = item.message.time.toLocal();
    final date = localizations.formatShortDate(time);
    final clock = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(time),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: style.text.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.author.isEmpty
                      ? tr(context, 'Автор неизвестен', 'Unknown author')
                      : item.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: style.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${item.chatName} · ${item.radioName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: style.secondary, fontSize: 12),
                ),
                Text(
                  '$date · $clock',
                  style: TextStyle(color: style.secondary, fontSize: 12),
                ),
                Text(
                  tr(context, 'К оригиналу', 'Go to original'),
                  style: TextStyle(color: style.accent, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
