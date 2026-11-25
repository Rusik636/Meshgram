// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';

import '../mesh/chat_position.dart';
import '../mesh/controller.dart';
import '../mesh/network.dart';
import 'message_links.dart';
import 'style.dart';

enum MessageContentFilter { link, location, contact }

class MessageSearchFilters {
  const MessageSearchFilters({
    this.author,
    this.period,
    this.content = const {},
  });

  final String? author;
  final DateTimeRange? period;
  final Set<MessageContentFilter> content;

  bool get isEmpty => author == null && period == null && content.isEmpty;

  bool accepts(MeshController controller, MeshMessage message, String query) {
    if (query.isNotEmpty && !message.text.toLowerCase().contains(query)) {
      return false;
    }
    if (author != null && author != _authorKey(message)) return false;
    if (period case final range?) {
      final date = DateUtils.dateOnly(message.time);
      if (date.isBefore(range.start) || date.isAfter(range.end)) return false;
    }
    return content.isEmpty ||
        content.any(
          (type) => switch (type) {
            MessageContentFilter.link => firstMessageLink(message.text) != null,
            MessageContentFilter.location => chatPosition(message.text) != null,
            MessageContentFilter.contact =>
              controller.contactAttachment(message.text) != null,
          },
        );
  }
}

String _authorKey(MeshMessage message) => message.outgoing
    ? 'self'
    : message.packet?.sender ?? 'name:${message.author}';

String _authorLabel(
  BuildContext context,
  MeshController controller,
  MeshMessage message,
) {
  final name = message.outgoing
      ? controller.profileName
      : controller.messageAuthor(message)?.name ?? message.author;
  if (name.isNotEmpty) return name;
  return message.outgoing
      ? tr(context, 'Вы', 'You')
      : tr(context, 'Автор неизвестен', 'Unknown author');
}

String _label(BuildContext context, MessageContentFilter type) =>
    switch (type) {
      MessageContentFilter.link => tr(context, 'Ссылки', 'Links'),
      MessageContentFilter.location => tr(context, 'Координаты', 'Coordinates'),
      MessageContentFilter.contact => tr(context, 'Контакты', 'Contacts'),
    };

Future<MessageSearchFilters?> showMessageSearchFilters(
  BuildContext context, {
  required MeshController controller,
  required Iterable<MeshMessage> messages,
  required MessageSearchFilters filters,
}) {
  final authors = {
    for (final message in messages)
      _authorKey(message): _authorLabel(context, controller, message),
  }.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
  final entries =
      messages.map((message) => DateUtils.dateOnly(message.time)).toList()
        ..sort();
  var period = filters.period;
  var author = filters.author;
  final content = {...filters.content};
  return showDialog<MessageSearchFilters>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final localizations = MaterialLocalizations.of(context);
        return AlertDialog(
          scrollable: true,
          title: Text(tr(context, 'Фильтры сообщений', 'Message filters')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: authors.any((entry) => entry.key == author)
                    ? author
                    : '',
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr(context, 'Автор', 'Author'),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(tr(context, 'Все авторы', 'All authors')),
                  ),
                  for (final entry in authors)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => author = value == '' ? null : value),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range_rounded),
                label: Text(
                  period == null
                      ? tr(context, 'Период', 'Date range')
                      : '${localizations.formatShortDate(period!.start)} – '
                            '${localizations.formatShortDate(period!.end)}',
                ),
                onPressed: entries.isEmpty
                    ? null
                    : () async {
                        final first = entries.first;
                        final last = entries.last;
                        final initial = period;
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: first,
                          lastDate: last,
                          initialDateRange:
                              initial != null &&
                                  !initial.start.isBefore(first) &&
                                  !initial.end.isAfter(last)
                              ? initial
                              : null,
                        );
                        if (picked != null && context.mounted) {
                          setState(() => period = picked);
                        }
                      },
              ),
              if (period != null)
                TextButton(
                  onPressed: () => setState(() => period = null),
                  child: Text(tr(context, 'Весь период', 'Any date')),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final type in MessageContentFilter.values)
                    FilterChip(
                      label: Text(_label(context, type)),
                      selected: content.contains(type),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          content.add(type);
                        } else {
                          content.remove(type);
                        }
                      }),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, const MessageSearchFilters()),
              child: Text(tr(context, 'Сбросить', 'Reset')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                MessageSearchFilters(
                  author: author,
                  period: period,
                  content: Set.unmodifiable(content),
                ),
              ),
              child: Text(tr(context, 'Применить', 'Apply')),
            ),
          ],
        );
      },
    ),
  );
}

class MessageSearchResultTile extends StatelessWidget {
  const MessageSearchResultTile({
    super.key,
    required this.controller,
    required this.message,
    required this.query,
    required this.onTap,
    this.chatName,
  });

  final MeshController controller;
  final MeshMessage message;
  final String query;
  final VoidCallback onTap;
  final String? chatName;

  String _snippet() {
    final text = message.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final hit = text.toLowerCase().indexOf(query);
    if (hit <= 32) return text;
    var start = hit - 24;
    if (start >= text.length) return text;
    final first = text.codeUnitAt(start);
    if (first >= 0xdc00 && first <= 0xdfff) start--;
    return '… ${text.substring(start)}';
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatShortDate(message.time);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(message.time),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return ListTile(
      onTap: onTap,
      title: Text(
        [_authorLabel(context, controller, message), ?chatName].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w600, color: style.text),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_snippet(), maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(
            '$date · $time',
            style: TextStyle(color: style.secondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
