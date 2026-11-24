// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';

import 'package:flutter/material.dart';

import '../mesh/chat_position.dart';
import '../mesh/controller.dart';
import '../mesh/store.dart';
import 'chat.dart';
import 'mesh_map.dart';
import 'message_links.dart';
import 'style.dart';

class SavedMessagesPage extends StatelessWidget {
  const SavedMessagesPage({super.key, required this.controller});

  final MeshController controller;

  void _notice(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PageHeading(
              tr(context, 'Избранное', 'Saved Messages'),
              leading: GlassButton(
                icon: Icons.arrow_back_ios_new_rounded,
                label: tr(context, 'Назад', 'Back'),
                onTap: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final items = controller.savedMessages;
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          tr(
                            context,
                            'Чтобы сохранить сообщение, удерживайте его и выберите «В Избранное».',
                            'To save a message, hold it and choose Save message.',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: style.secondary),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _SavedMessageCard(
                        key: ValueKey(item.key),
                        item: item,
                        onOpenSource: () =>
                            unawaited(_openSource(context, item)),
                        onEditLabels: () =>
                            unawaited(_editLabels(context, item)),
                        onRemove: () => unawaited(_remove(context, item)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedMessageCard extends StatelessWidget {
  const _SavedMessageCard({
    super.key,
    required this.item,
    required this.onOpenSource,
    required this.onEditLabels,
    required this.onRemove,
  });

  final SavedMessage item;
  final VoidCallback onOpenSource, onEditLabels, onRemove;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final localizations = MaterialLocalizations.of(context);
    final time = item.message.time;
    final date = localizations.formatShortDate(time);
    final clock = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(time),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final position = chatPosition(item.message.text);
    final secondary = TextStyle(color: style.secondary, fontSize: 12);
    return GlassSurface(
      radius: 18,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  item.author.isEmpty
                      ? tr(context, 'Автор неизвестен', 'Unknown author')
                      : item.author,
                  style: TextStyle(
                    color: style.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text('$date · $clock', style: secondary),
              ],
            ),
            Text('${item.chatName} · ${item.radioName}', style: secondary),
            const SizedBox(height: 8),
            if (position?.standalone != true)
              SelectionArea(
                child: MessageLinkifiedText(
                  text: item.message.text,
                  style: TextStyle(color: style.text, fontSize: 15),
                  linkColor: style.accent,
                ),
              ),
            if (position case final data?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: MeshLocationPreview(
                  position: data.point,
                  loadTiles: false,
                ),
              ),
            if (item.labels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final label in item.labels) Chip(label: Text(label)),
                  ],
                ),
              ),
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: onOpenSource,
                  child: Text(tr(context, 'К оригиналу', 'Go to original')),
                ),
                TextButton(
                  onPressed: onEditLabels,
                  child: Text(tr(context, 'Метки', 'Labels')),
                ),
                IconButton(
                  tooltip: tr(
                    context,
                    'Убрать из Избранного',
                    'Remove from Saved',
                  ),
                  onPressed: onRemove,
                  icon: const Icon(Icons.bookmark_remove_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
