// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';

import '../mesh/network.dart';
import '../mesh/store.dart';
import 'style.dart';

typedef ChatFolderEdit = ({String name, Set<String> chats});

Future<ChatFolderEdit?> editChatFolder(
  BuildContext context, {
  required List<Peer> chats,
  ChatFolder? folder,
}) {
  var name = folder?.name ?? '';
  final selected = {...?folder?.chats};
  return showMeshDialog<ChatFolderEdit>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => MeshDialog(
        title: Text(
          folder == null
              ? tr(context, 'Новая папка', 'New folder')
              : tr(context, 'Изменить папку', 'Edit folder'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: name,
              maxLength: 36,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr(context, 'Название', 'Name'),
                counterText: '',
              ),
              onChanged: (text) => setState(() => name = text),
            ),
            if (chats.isNotEmpty)
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 96).clamp(
                  0.0,
                  320.0,
                ),
                height:
                    ((MediaQuery.sizeOf(context).height -
                                MediaQuery.viewInsetsOf(context).bottom) *
                            .32)
                        .clamp(0.0, 56.0 * chats.length),
                child: ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          FilledButton(
            onPressed: name.trim().isEmpty
                ? null
                : () => Navigator.pop(context, (
                    name: name.trim(),
                    chats: selected,
                  )),
            child: Text(tr(context, 'Сохранить', 'Save')),
          ),
        ],
      ),
    ),
  );
}
