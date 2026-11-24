// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';

import '../mesh/network.dart';
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

Future<Peer?> pickForwardChat(BuildContext context, List<Peer> peers) =>
    showMeshSheet<Peer>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          children: [
            ListTile(
              title: Text(
                tr(context, 'Переслать в чат', 'Forward to chat'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final peer in peers)
              ListTile(
                leading: MeshAvatar(peer.name, size: 38, channel: peer.channel),
                title: Text(
                  peer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, peer),
              ),
          ],
        ),
      ),
    );
