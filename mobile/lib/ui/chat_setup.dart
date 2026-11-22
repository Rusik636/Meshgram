// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';

import 'package:flutter/material.dart';

import '../mesh/controller.dart';
import '../mesh/network.dart';
import 'style.dart';
import 'page_route.dart';
import 'qr_scanner.dart';
import 'contact_qr.dart';

const _blue = Color(0xff2978d5);
const _teal = Color(0xff168a87);

Future<Peer?> showNewChatSheet(
  BuildContext context,
  MeshController controller,
) => showMeshSheet<Peer>(
  context: context,
  builder: (_) => _NewChatSheet(controller: controller),
);

Future<void> showRadioChannels(
  BuildContext context,
  MeshController controller,
) => showMeshSheet<void>(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => SheetBody(
      title: tr(context, 'Каналы', 'Channels'),
      children: [
        MeshGroup(
          children: [
            for (final peer in controller.peers.where((peer) => peer.channel))
              MeshRow(
                title: peer.name,
                icon: Icons.tag_rounded,
                tint: _teal,
                showChevron: controller.canShareChannel(peer),
                onTap: controller.canShareChannel(peer)
                    ? () => unawaited(
                        showPeerChannelQr(context, controller, peer),
                      )
                    : null,
              ),
            MeshRow(
              title: tr(context, 'Добавить канал', 'Add channel'),
              icon: Icons.add_rounded,
              titleColor: MeshStyle.of(context).accent,
              tint: _blue,
              onTap: () => unawaited(
                Navigator.of(context).push<Peer>(
                  meshPageRoute(
                    context,
                    builder: (_) => _ChannelActionsPage(controller: controller),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  ),
);

class _NewChatSheet extends StatelessWidget {
  const _NewChatSheet({required this.controller});
  final MeshController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final available = controller.channelActions.isNotEmpty;
      return SheetBody(
        title: tr(context, 'Новый чат', 'New chat'),
        children: [
          MeshGroup(
            children: [
              MeshRow(
                title: tr(context, 'Новый канал', 'New channel'),
                icon: Icons.add_rounded,
                tint: _blue,
                titleColor: available
                    ? MeshStyle.of(context).accent
                    : MeshStyle.of(context).secondary,
                onTap: !available
                    ? null
                    : () async {
                        final result = await Navigator.of(context).push<Peer>(
                          meshPageRoute(
                            context,
                            builder: (_) =>
                                _ChannelActionsPage(controller: controller),
                          ),
                        );
                        if (context.mounted && result != null) {
                          Navigator.pop(context, result);
                        }
                      },
              ),
            ],
          ),
          if (!available)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
              child: Text(
                tr(
                  context,
                  'Подключите рацию, чтобы добавить канал.',
                  'Connect a radio to add a channel.',
                ),
                style: TextStyle(color: MeshStyle.of(context).secondary),
              ),
            ),
        ],
      );
    },
  );
}

class _ChannelActionsPage extends StatefulWidget {
  const _ChannelActionsPage({required this.controller});
  final MeshController controller;

  @override
  State<_ChannelActionsPage> createState() => _ChannelActionsState();
}

class _ChannelActionsState extends State<_ChannelActionsPage> {
  bool _saving = false;
  String? _error;

  (String, String, IconData) _describe(ChannelAction action) =>
      switch (action) {
        ChannelAction.createPrivate => (
          tr(context, 'Создать приватный канал', 'Create a private channel'),
          tr(context, 'Сгенерировать новый ключ', 'Generate a new key'),
          Icons.add_rounded,
        ),
        ChannelAction.joinPrivate => (
          tr(context, 'Войти в приватный канал', 'Join a private channel'),
          tr(context, 'Ввести имя и ключ вручную', 'Enter the name and key'),
          Icons.lock_outline_rounded,
        ),
        ChannelAction.publicChannel => (
          tr(context, 'Войти в публичный канал', 'Join the public channel'),
          tr(
            context,
            'Доступен всем участникам сети',
            'Open to everyone on the network',
          ),
          Icons.public_rounded,
        ),
        ChannelAction.hashtag => (
          tr(context, 'Войти в хэштег-канал', 'Join a hashtag channel'),
          tr(context, 'Достаточно названия с #', 'Enter the channel hashtag'),
          Icons.tag_rounded,
        ),
        ChannelAction.invitation => (
          tr(context, 'Сканировать QR-код', 'Scan a QR code'),
          tr(context, 'Или вставить ссылку', 'Or paste an invitation link'),
          Icons.qr_code_scanner_rounded,
        ),
      };

  Future<void> _select(ChannelAction action) async {
    if (_saving) return;
    var request = (action: action, name: '', secret: '', invitation: '');
    if (action == ChannelAction.invitation) {
      final invite = await Navigator.of(context).push<String>(
        meshPageRoute(
          context,
          builder: (_) => MeshQrScannerPage(
            title: tr(context, 'QR-код канала', 'Channel QR code'),
          ),
        ),
      );
      if (invite == null) return;
      request = (action: action, name: '', secret: '', invitation: invite);
    } else if (action != ChannelAction.publicChannel) {
      final values = await _details(action);
      if (values == null) return;
      request = (
        action: action,
        name: values.$1,
        secret: values.$2,
        invitation: '',
      );
    }
    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.controller.addChannel(request);
      if (!mounted) return;
      if (result.invitation case final invite?) {
        final network = widget.controller.active?.network;
        await showChannelQr(
          context,
          name: result.peer.name,
          invitation: invite,
          network: network == null ? null : widget.controller.label(network),
        );
      }
      if (mounted) Navigator.of(context).pop(result.peer);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _message(Object error) => switch (error) {
    StateError(message: 'channel-full') => tr(
      context,
      'В рации нет свободного слота для канала.',
      'The radio has no free channel slots.',
    ),
    StateError(message: 'channel-duplicate') => tr(
      context,
      'В рации уже есть канал с таким именем и другим ключом.',
      'This channel name is already in use.',
    ),
    FormatException(message: 'channel-name') => tr(
      context,
      'Измените название канала. Кириллица занимает больше байтов.',
      'Choose a different channel name. Non-ASCII names use more bytes.',
    ),
    FormatException(message: 'channel-key') => tr(
      context,
      'Проверьте ключ канала и его длину.',
      'Check the channel key and its length.',
    ),
    FormatException(message: 'channel-region') => tr(
      context,
      'У приглашения другой регион LoRa. Сначала проверьте настройки рации.',
      'This invitation uses a different LoRa region. Check your radio settings first.',
    ),
    FormatException(message: 'channel-primary') => tr(
      context,
      'Приглашение требует изменения главного канала. Сверьте параметры LoRa с отправителем.',
      'The invitation requires a different primary channel. Check the LoRa settings with the sender.',
    ),
    FormatException(message: 'channel-scope') => tr(
      context,
      'Приглашение использует региональный охват MeshCore.',
      'This MeshCore invitation requires a region scope.',
    ),
    FormatException() => tr(
      context,
      'Приглашение не подходит для подключённой рации.',
      'This invitation does not match the connected radio.',
    ),
    _ => tr(
      context,
      'Рация не подтвердила добавление канала.',
      'The radio did not confirm the channel addition.',
    ),
  };

  Future<(String, String)?> _details(ChannelAction action) =>
      showMeshDialog<(String, String)>(
        context: context,
        builder: (context) {
          var name = '';
          var key = '';
          final needsKey = action == ChannelAction.joinPrivate;
          return MeshDialog(
            title: Text(_describe(action).$1),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: action == ChannelAction.hashtag
                        ? tr(context, 'Хэштег', 'Hashtag')
                        : tr(context, 'Название канала', 'Channel name'),
                  ),
                  onChanged: (value) => name = value,
                ),
                if (needsKey)
                  TextField(
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (value) => key = value,
                    decoration: InputDecoration(
                      labelText: tr(
                        context,
                        'Ключ в HEX или Base64',
                        'Key in HEX or Base64',
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(tr(context, 'Отмена', 'Cancel')),
              ),
              TextButton(
                onPressed: () {
                  if (name.trim().isEmpty || (needsKey && key.trim().isEmpty)) {
                    return;
                  }
                  Navigator.of(context).pop((name, key));
                },
                child: Text(tr(context, 'Добавить', 'Add')),
              ),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      top: false,
      bottom: false,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final actions = widget.controller.channelActions;
          final style = MeshStyle.of(context);
          return PinnedPageList(
            padding: meshScrollPadding(context),
            header: PageHeading(
              tr(context, 'Добавить канал', 'Add channel'),
              leading: GlassButton(
                icon: Icons.arrow_back_ios_new_rounded,
                label: tr(context, 'Назад', 'Back'),
                onTap: _saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            children: [
              if (_saving) const LinearProgressIndicator(minHeight: 2),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(17),
                  child: Text(_error!, style: TextStyle(color: style.warning)),
                ),
              if (actions.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(17),
                  child: Text(
                    tr(
                      context,
                      'Подключите рацию для добавления канала.',
                      'Connect your radio to add a channel.',
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: MeshGroup(
                    children: [
                      for (final action in actions)
                        MeshRow(
                          title: _describe(action).$1,
                          subtitle: _describe(action).$2,
                          icon: _describe(action).$3,
                          tint: _blue,
                          onTap: _saving
                              ? null
                              : () => unawaited(_select(action)),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
