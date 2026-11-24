// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

part of 'chat.dart';

enum RadioSendOption { queue, openOutbox }

Future<RadioSendOption?> showRadioSendMenu(
  BuildContext context, {
  required Rect button,
  required bool canQueue,
  required bool hasOutbox,
  required String draft,
  Uint8List? backdrop,
}) {
  final style = MeshStyle.of(context);
  final ios = Theme.of(context).platform == TargetPlatform.iOS;
  if (ios) {
    return _showIosSendMenu(
      context,
      button: button,
      canQueue: canQueue,
      hasOutbox: hasOutbox,
      draft: draft,
      backdrop: backdrop,
    );
  }
  final size = MediaQuery.sizeOf(context);
  final height = (canQueue && hasOutbox ? 2 : 1) * 48.0 + 16;
  return showMenu<RadioSendOption>(
    context: context,
    position: RelativeRect.fromSize(
      Rect.fromLTRB(
        button.left,
        button.top - height - 2,
        button.right + 8,
        button.top - 2,
      ),
      size,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    color: style.surface,
    items: [
      if (canQueue)
        PopupMenuItem(
          value: RadioSendOption.queue,
          child: Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 20),
              const SizedBox(width: 14),
              Flexible(
                child: Text(
                  tr(
                    context,
                    'Отправить при подключении рации',
                    'Send when the radio connects',
                  ),
                ),
              ),
            ],
          ),
        ),
      if (hasOutbox)
        PopupMenuItem(
          value: RadioSendOption.openOutbox,
          child: Row(
            children: [
              const Icon(Icons.outbox_outlined, size: 20),
              const SizedBox(width: 14),
              Text(tr(context, 'Очередь рации', 'Radio outbox')),
            ],
          ),
        ),
    ],
  );
}

Future<RadioSendOption?> _showIosSendMenu(
  BuildContext context, {
  required Rect button,
  required bool canQueue,
  required bool hasOutbox,
  required String draft,
  Uint8List? backdrop,
}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<RadioSendOption>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: messageMenuDim(context),
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 420),
    pageBuilder: (context, animation, _) {
      final style = MeshStyle.of(context);
      final size = MediaQuery.sizeOf(context);
      final padding = MediaQuery.viewPaddingOf(context);
      final bottom = math.max(
        padding.bottom + 7,
        size.height - button.bottom - 8,
      );
      final right = math.max(padding.right + 8, size.width - button.left + 6);
      final width = (size.width - right - padding.left - 12).clamp(0.0, 250.0);
      Widget action(RadioSendOption option, IconData icon, String label) =>
          ListTile(
            minTileHeight: 46,
            title: Text(label, style: TextStyle(color: style.text)),
            trailing: Icon(icon, size: 20, color: style.text),
            onTap: () => Navigator.pop(context, option),
          );
      return Stack(
        children: [
          Positioned(
            right: right,
            bottom: bottom,
            width: width,
            child: Material(
              type: MaterialType.transparency,
              child: FadeTransition(
                opacity: animation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (draft.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 7),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: style.outgoing,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: EmojiText(
                          draft,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, color: style.text),
                        ),
                      ),
                    ScaleTransition(
                      alignment: Alignment.bottomRight,
                      scale: animation.drive(
                        Tween(
                          begin: .88,
                          end: 1.0,
                        ).chain(CurveTween(curve: Curves.easeOutBack)),
                      ),
                      child: MessageMenuBackdrop(
                        image: backdrop,
                        child: MessageMenuSurface(
                          radius: 19,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (canQueue)
                                action(
                                  RadioSendOption.queue,
                                  Icons.schedule_rounded,
                                  tr(
                                    context,
                                    'Отправить при подключении рации',
                                    'Send when the radio connects',
                                  ),
                                ),
                              if (canQueue && hasOutbox)
                                Divider(
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                  color: style.separator,
                                ),
                              if (hasOutbox)
                                action(
                                  RadioSendOption.openOutbox,
                                  Icons.outbox_outlined,
                                  tr(context, 'Очередь рации', 'Radio outbox'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class RadioOutboxPage extends StatelessWidget {
  const RadioOutboxPage({
    super.key,
    required this.controller,
    required this.peer,
    required this.profile,
  });

  final MeshController controller;
  final Peer peer;
  final Radio profile;

  Future<void> _edit(BuildContext context, OutboxMessage item) async {
    var text = item.text;
    final limit = controller.limit(peer) ?? 0;
    final value = await showMeshDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final bytes = utf8.encode(text.trim()).length;
          final valid = bytes > 0 && bytes <= limit;
          return MeshDialog(
            title: Text(tr(context, 'Изменить сообщение', 'Edit message')),
            content: TextFormField(
              initialValue: item.text,
              minLines: 2,
              maxLines: 5,
              onChanged: (value) => setState(() => text = value),
              decoration: InputDecoration(
                counterText: '$bytes / $limit',
                errorText: bytes <= limit
                    ? null
                    : tr(context, 'Превышен лимит', 'Message too long'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr(context, 'Отмена', 'Cancel')),
              ),
              FilledButton(
                onPressed: valid ? () => Navigator.pop(context, text) : null,
                child: Text(tr(context, 'Сохранить', 'Save')),
              ),
            ],
          );
        },
      ),
    );
    if (!context.mounted || controller.active != profile || value == null) {
      return;
    }
    await controller.updateOutbox(item, peer, text: value);
  }

  Future<void> _retry(BuildContext context, OutboxMessage item) async {
    final confirmed = await showMeshDialog<bool>(
      context: context,
      builder: (context) => MeshDialog(
        title: Text(tr(context, 'Повторить отправку?', 'Send again?')),
        content: Text(
          tr(
            context,
            'Сообщение могло уже уйти в эфир.',
            'The message may already have been transmitted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Повторить', 'Retry')),
          ),
        ],
      ),
    );
    if (!context.mounted || controller.active != profile || confirmed != true) {
      return;
    }
    await controller.updateOutbox(item, peer, retry: true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final current = controller.active == profile;
      final entries = current
          ? controller.outboxFor(peer.id)
          : const <OutboxMessage>[];
      final title = tr(context, 'Очередь рации', 'Radio outbox');
      final link = current && controller.connected
          ? tr(context, 'Рация подключена', 'Radio connected')
          : tr(context, 'Рация не подключена', 'Radio disconnected');
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: Center(
            child: GlassButton(
              icon: Icons.arrow_back_ios_new_rounded,
              label: tr(context, 'Назад', 'Back'),
              onTap: () => Navigator.pop(context),
            ),
          ),
        ),
        body: MeshChatWallpaper(
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                GlassSurface(
                  radius: 18,
                  child: ListTile(
                    title: Text(profile.name),
                    subtitle: Text(link),
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: Text(
                            tr(context, 'Очередь пуста', 'No queued messages'),
                          ),
                        )
                      : ListView(
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          children: [
                            for (final entry in entries.reversed)
                              _entry(context, entry),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _entry(BuildContext context, OutboxMessage item) {
    final delivery = controller.outboxDelivery(item);
    final status = delivery == Delivery.acknowledged
        ? messageDeliveryLabel(context, delivery!, channel: peer.channel)
        : switch (item.status) {
            OutboxStatus.waiting => tr(
              context,
              'Ожидает отправки',
              'Waiting to send',
            ),
            OutboxStatus.sending => tr(
              context,
              'Передача рации',
              'Handing off to radio',
            ),
            OutboxStatus.uncertain => tr(
              context,
              'Отправка не подтверждена',
              'Transmission unconfirmed',
            ),
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Bubble(
          item: MeshMessage(
            id: item.id,
            chat: item.chat,
            author: '',
            text: item.text,
            time: item.createdAt ?? DateTime.now(),
            delivery:
                item.status == OutboxStatus.uncertain &&
                    (delivery == null || delivery.awaitingReceipt)
                ? Delivery.unconfirmed
                : delivery ?? Delivery.queued,
            replyTo: item.replyTo,
            replyExcerpt: item.replyExcerpt,
          ),
          emoji: null,
          channel: peer.channel,
          joinsPrevious: false,
          joinsNext: false,
          quoted: controller.referencedMessage(peer.id, item.replyTo),
          reactions: const [],
          hideText: false,
          waitingForRadio: item.status == OutboxStatus.waiting,
          onMenu: item.status == OutboxStatus.sending
              ? null
              : (anchor) =>
                    unawaited(_entryActions(context, item, delivery, anchor)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 3, 7, 5),
          child: Text(
            status,
            style: TextStyle(
              fontSize: 12,
              color: MeshStyle.of(context).secondary,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _entryActions(
    BuildContext context,
    OutboxMessage item,
    Delivery? delivery,
    Rect anchor,
  ) async {
    final action = await showMenu<_OutboxAction>(
      context: context,
      position: RelativeRect.fromSize(anchor, MediaQuery.sizeOf(context)),
      items: [
        if (delivery != Delivery.acknowledged)
          PopupMenuItem(
            value: _OutboxAction.edit,
            child: Text(tr(context, 'Изменить', 'Edit')),
          ),
        if (item.status == OutboxStatus.uncertain &&
            delivery != Delivery.acknowledged)
          PopupMenuItem(
            value: _OutboxAction.retry,
            child: Text(tr(context, 'Повторить', 'Retry')),
          ),
        PopupMenuItem(
          value: _OutboxAction.cancel,
          child: Text(tr(context, 'Убрать из очереди', 'Remove from outbox')),
        ),
      ],
    );
    if (!context.mounted || controller.active != profile) return;
    switch (action) {
      case _OutboxAction.edit:
        await _edit(context, item);
      case _OutboxAction.retry:
        await _retry(context, item);
      case _OutboxAction.cancel:
        await controller.cancelOutbox(item);
      case null:
        break;
    }
  }
}

enum _OutboxAction { edit, retry, cancel }
