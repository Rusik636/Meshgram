// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';

import '../mesh/controller.dart';
import '../mesh/network.dart';
import 'ios_control.dart';
import 'navigation.dart';
import 'search_field.dart';
import 'style.dart';

Future<MessageExcerpt?> selectMessageExcerpt(
  BuildContext context,
  String text,
) {
  MessageExcerpt? excerpt;
  return showMeshDialog<MessageExcerpt>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => MeshDialog(
        title: Text(tr(context, 'Выделите фрагмент', 'Select a fragment')),
        content: SelectableText(
          text,
          onSelectionChanged: (selection, _) {
            final selected =
                selection.isValid &&
                    !selection.isCollapsed &&
                    selection.end <= text.length
                ? selection.textInside(text)
                : '';
            setState(
              () => excerpt = selected.trim().isEmpty
                  ? null
                  : MessageExcerpt(selection.start, selected),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          FilledButton(
            onPressed: excerpt == null
                ? null
                : () => Navigator.pop(context, excerpt),
            child: Text(tr(context, 'Цитировать', 'Quote')),
          ),
        ],
      ),
    ),
  );
}

typedef ForwardTargets = ({List<Peer> chats, bool saved});

Future<ForwardTargets?> pickForwardChats(
  BuildContext context,
  MeshController controller,
) => showMeshSheet<ForwardTargets>(
  context: context,
  dragArea: MeshSheetGrip.height,
  builder: (_) => _ForwardPicker(controller: controller),
);

class _ForwardPicker extends StatefulWidget {
  const _ForwardPicker({required this.controller});

  final MeshController controller;

  @override
  State<_ForwardPicker> createState() => _ForwardPickerState();
}

class _ForwardPickerState extends State<_ForwardPicker> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  final _iosSearch = GlobalKey<IosControlState>();
  final _selected = <String, Peer>{};
  String _query = '';
  bool _multiple = false, _contacts = false, _saved = false;
  int _folder = 0;

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _choose(Peer? peer) {
    if (!_multiple) {
      Navigator.pop(context, (chats: <Peer>[?peer], saved: peer == null));
      return;
    }
    setState(() {
      if (peer == null) {
        _saved = !_saved;
      } else if (_selected.remove(peer.id) == null) {
        _selected[peer.id] = peer;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final style = MeshStyle.of(context);
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final folders = controller.chatFolders;
    final savedLabel = tr(context, 'Избранное', 'Saved Messages');
    final query = _query.trim().toLowerCase();
    final chats = _contacts ? controller.peers : controller.conversations;
    final peers = [
      for (final peer in chats)
        if (controller.canSendTo(peer) &&
            !controller.isOwnChat(peer.id) &&
            (!_contacts || !peer.channel) &&
            (_contacts ||
                switch (_folder) {
                  0 => true,
                  1 => !peer.channel,
                  2 => peer.channel,
                  final index =>
                    folders
                            .elementAtOrNull(index - 3)
                            ?.chats
                            .contains(peer.id) ??
                        true,
                }) &&
            (peer.name.toLowerCase().contains(query) ||
                peer.id.toLowerCase().contains(query)))
          peer,
    ];
    final showSaved =
        !_contacts && _folder == 0 && savedLabel.toLowerCase().contains(query);
    final count = _selected.length + (_saved ? 1 : 0);
    final contactsLabel = tr(context, 'Контакты', 'Contacts');
    final chatsLabel = tr(context, 'Чаты', 'Chats');
    void switchDirectory(int index) => setState(() => _contacts = index == 1);
    final directory = ChatFilters(
      labels: [chatsLabel, contactsLabel],
      selected: _contacts ? 1 : 0,
      onSelect: switchDirectory,
    );
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final height =
        (MediaQuery.sizeOf(context).height - keyboard) * (ios ? .87 : .78);
    final showTabs = keyboard == 0 || height > 280;
    final panel = SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            PageHeading(
              tr(context, 'Переслать', 'Forward'),
              sideWidth: 108,
              leading: GlassButton(
                icon: Icons.close_rounded,
                label: tr(context, 'Закрыть', 'Close'),
                onTap: () => Navigator.pop(context),
              ),
              trailing: GlassActionButton(
                fitContent: true,
                primary: false,
                label: _multiple
                    ? tr(context, 'Готово', 'Done')
                    : tr(context, 'Выбрать', 'Select'),
                onTap: () => setState(() {
                  _multiple = !_multiple;
                  _selected.clear();
                  _saved = false;
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MeshSearchEditor(
                placeholder: tr(context, 'Поиск', 'Search'),
                controller: _search,
                focusNode: _focus,
                iosKey: _iosSearch,
                autofocus: false,
                initialText: _query,
                onChanged: (value) => setState(() => _query = value),
                onDismissKeyboard: () {
                  _focus.unfocus();
                  _iosSearch.currentState?.dismissKeyboard();
                },
              ),
            ),
            if (!ios && showTabs) directory,
            if (!_contacts && showTabs)
              ChatFilters(
                labels: [
                  tr(context, 'Все', 'All'),
                  tr(context, 'Личные', 'Direct'),
                  tr(context, 'Каналы', 'Channels'),
                  for (final folder in folders) folder.name,
                ],
                selected: _folder,
                onSelect: (index) => setState(() => _folder = index),
              ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (useIosControls)
                    const IgnorePointer(
                      child: IosControl(kind: 'messagePreview', properties: {}),
                    ),
                  peers.isEmpty && !showSaved
                      ? Center(
                          child: Text(
                            tr(context, 'Нет получателей', 'No recipients'),
                            style: TextStyle(color: style.secondary),
                          ),
                        )
                      : ListView.separated(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: peers.length + (showSaved ? 1 : 0),
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            indent: 68,
                            color: style.separator,
                          ),
                          itemBuilder: (context, index) {
                            final peer = showSaved && index == 0
                                ? null
                                : peers[index - (showSaved ? 1 : 0)];
                            final selected = peer == null
                                ? _saved
                                : _selected.containsKey(peer.id);
                            return ListTile(
                              leading: peer == null
                                  ? CircleAvatar(
                                      backgroundColor: style.accent,
                                      child: const Icon(
                                        Icons.bookmark_rounded,
                                        color: Colors.white,
                                      ),
                                    )
                                  : MeshAvatar(
                                      peer.name,
                                      size: 40,
                                      channel: peer.channel,
                                    ),
                              title: Text(
                                peer?.name ?? savedLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: _multiple
                                  ? Icon(
                                      selected
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked,
                                      color: selected
                                          ? style.accent
                                          : style.secondary,
                                    )
                                  : null,
                              selected: selected,
                              onTap: () => _choose(peer),
                            );
                          },
                        ),
                ],
              ),
            ),
            if (_multiple)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 5, 16, 8),
                child: GlassActionButton(
                  label: tr(
                    context,
                    'Подготовить · $count',
                    'Prepare · $count',
                  ),
                  onTap: count == 0
                      ? null
                      : () => Navigator.pop(context, (
                          chats: _selected.values.toList(),
                          saved: _saved,
                        )),
                ),
              ),
            if (ios && showTabs) directory,
          ],
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: panel,
    );
  }
}
