// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';

import '../app_name.dart';
import 'style.dart';
import 'swipe_actions.dart';

Future<bool?> confirmChatRemoval(
  BuildContext context,
  List<String> names,
) => showMeshDialog<bool>(
  context: context,
  builder: (context) => MeshDialog(
    title: Text(tr(context, 'Удалить полностью?', 'Delete permanently?')),
    content: Text(
      names.length == 1
          ? tr(
              context,
              '«${names.single}» будет удалён с выбранной рации вместе с историей в $appName.',
              '“${names.single}” will be removed from this radio. Its history in $appName will be deleted.',
            )
          : tr(
              context,
              'С выбранной рации будут удалены записи (${names.length}). История этих чатов в $appName будет удалена.',
              '${names.length} entries will be removed from this radio. Their history in $appName will be deleted.',
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(tr(context, 'Отмена', 'Cancel')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(tr(context, 'Удалить', 'Delete')),
      ),
    ],
  ),
);

SwipeAction deleteSwipeAction(BuildContext context, VoidCallback onTap) => (
  label: tr(context, 'Удалить', 'Delete'),
  icon: Icons.delete_outline_rounded,
  color: const Color(0xffd73d50),
  onTap: onTap,
);

class ChatSwipeRow extends StatelessWidget {
  const ChatSwipeRow({
    super.key,
    required this.revealed,
    required this.onReveal,
    required this.hidden,
    required this.onVisibility,
    required this.onDelete,
    required this.child,
    this.onPin,
    this.pinned = false,
  });

  final bool revealed, hidden, pinned;
  final ValueChanged<bool> onReveal;
  final VoidCallback onVisibility, onDelete;
  final VoidCallback? onPin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return SwipeActionsRow(
      revealed: revealed,
      onReveal: onReveal,
      background: style.canvas,
      surface: style.surface,
      closedSurface: style.canvas,
      actions: [
        if (onPin case final pin?)
          (
            label: pinned
                ? tr(context, 'Открепить чат', 'Unpin chat')
                : tr(context, 'Закрепить чат', 'Pin chat'),
            icon: pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
            color: const Color(0xff6051ac),
            onTap: pin,
          ),
        (
          label: hidden
              ? tr(context, 'Показать', 'Show')
              : tr(context, 'Скрыть', 'Hide'),
          icon: hidden
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          color: const Color(0xff1978ca),
          onTap: onVisibility,
        ),
        deleteSwipeAction(context, onDelete),
      ],
      child: child,
    );
  }
}
