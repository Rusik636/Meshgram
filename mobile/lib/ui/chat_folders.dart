// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';

import 'package:flutter/material.dart';

import '../mesh/controller.dart';
import '../mesh/network.dart';
import '../mesh/store.dart';
import 'page_route.dart';
import 'style.dart';

typedef ChatFolderEdit = ({String name, Set<String> chats});

Future<void> showChatFolders(
  BuildContext context, {
  required MeshController controller,
  required Future<void> Function(ChatFolder?) onEdit,
  required ValueChanged<String> onDelete,
  required ValueChanged<List<String>> onReorder,
}) => Navigator.of(context).push<void>(
  meshPageRoute(
    context,
    builder: (context) => Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PageHeading(
              tr(context, 'Папки чатов', 'Chat folders'),
              leading: GlassButton(
                icon: Icons.arrow_back_ios_new_rounded,
                label: tr(context, 'Назад', 'Back'),
                onTap: () => Navigator.pop(context),
              ),
              trailing: GlassButton(
                icon: Icons.add_rounded,
                label: tr(context, 'Новая папка', 'New folder'),
                onTap: () => unawaited(onEdit(null)),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final folders = controller.chatFolders;
                  return ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: folders.length,
                    onReorderItem: (from, to) {
                      final ids = folders.map((folder) => folder.id).toList();
                      ids.insert(to, ids.removeAt(from));
                      onReorder(ids);
                    },
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      return ListTile(
                        key: ValueKey(folder.id),
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle_rounded),
                        ),
                        title: Text(folder.name),
                        trailing: IconButton(
                          tooltip: tr(
                            context,
                            'Удалить папку',
                            'Delete folder',
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => onDelete(folder.id),
                        ),
                        onTap: () => unawaited(onEdit(folder)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

Future<ChatFolderEdit?> editChatFolder(
  BuildContext context, {
  required List<Peer> chats,
  ChatFolder? folder,
}) {
  var name = folder?.name ?? '';
  final selected = {...?folder?.chats};
  return Navigator.of(context).push<ChatFolderEdit>(
    meshPageRoute(
      context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                PageHeading(
                  folder == null
                      ? tr(context, 'Новая папка', 'New folder')
                      : tr(context, 'Изменить папку', 'Edit folder'),
                  sideWidth: 108,
                  leading: GlassButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    label: tr(context, 'Назад', 'Back'),
                    onTap: () => Navigator.pop(context),
                  ),
                  trailing: GlassActionButton(
                    fitContent: true,
                    label: tr(context, 'Сохранить', 'Save'),
                    onTap: name.trim().isEmpty
                        ? null
                        : () => Navigator.pop(context, (
                            name: name.trim(),
                            chats: selected,
                          )),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextFormField(
                    initialValue: name,
                    maxLength: 36,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: tr(context, 'Название', 'Name'),
                      counterText: '',
                    ),
                    onChanged: (text) => setState(() => name = text),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: chats.length,
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      return CheckboxListTile(
                        secondary: MeshAvatar(
                          chat.name,
                          size: 38,
                          channel: chat.channel,
                        ),
                        title: Text(chat.name),
                        value: selected.contains(chat.id),
                        onChanged: (checked) => setState(() {
                          if (checked == true) {
                            selected.add(chat.id);
                          } else {
                            selected.remove(chat.id);
                          }
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
