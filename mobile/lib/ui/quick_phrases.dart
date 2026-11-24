// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';

import '../mesh/store.dart';
import 'style.dart';

Future<String?> pickQuickPhrase(BuildContext context, MeshStore store) {
  var phrases =
      store.quickPhrases ??
      [
        tr(context, 'На месте', 'I’m here'),
        tr(context, 'Задержусь', 'I’m running late'),
        tr(context, 'Пришли координаты', 'Send me your coordinates'),
      ];
  return showMeshSheet<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> edit(int? index) async {
          final text = await _editPhrase(
            context,
            index == null ? null : phrases[index],
          );
          if (!context.mounted || text == null) return;
          final next = [...phrases];
          if (index == null) {
            next.add(text);
          } else if (text.isEmpty) {
            next.removeAt(index);
          } else {
            next[index] = text;
          }
          if (await store.setQuickPhrases(next) && context.mounted) {
            setState(() => phrases = next);
          } else if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text(
                  tr(
                    context,
                    'Не удалось сохранить фразы',
                    'Could not save phrases',
                  ),
                ),
              ),
            );
          }
        }

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .56,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          container: true,
                          header: true,
                          child: Text(
                            tr(context, 'Быстрые фразы', 'Quick phrases'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ),
                      Semantics(
                        container: true,
                        child: GlassButton(
                          icon: Icons.add_rounded,
                          label: tr(context, 'Добавить фразу', 'Add phrase'),
                          onTap: () => edit(null),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final (index, phrase) in phrases.indexed)
                  ListTile(
                    title: Text(
                      phrase,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(context, phrase),
                    trailing: IconButton(
                      tooltip: tr(context, 'Изменить фразу', 'Edit phrase'),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => edit(index),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<String?> _editPhrase(BuildContext context, String? phrase) {
  var value = phrase ?? '';
  return showMeshDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => MeshDialog(
        title: Text(
          phrase == null
              ? tr(context, 'Добавить фразу', 'Add phrase')
              : tr(context, 'Изменить фразу', 'Edit phrase'),
        ),
        content: TextFormField(
          initialValue: value,
          decoration: InputDecoration(
            labelText: tr(context, 'Текст фразы', 'Phrase text'),
          ),
          textCapitalization: TextCapitalization.sentences,
          maxLength: 280,
          minLines: 2,
          maxLines: 4,
          onChanged: (text) => setState(() => value = text),
        ),
        actions: [
          if (phrase != null)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: Text(tr(context, 'Удалить', 'Delete')),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          FilledButton(
            onPressed: value.trim().isEmpty
                ? null
                : () => Navigator.pop(context, value.trim()),
            child: Text(tr(context, 'Сохранить', 'Save')),
          ),
        ],
      ),
    ),
  );
}
