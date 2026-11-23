// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Radio;

import '../local_notifications.dart';
import '../mesh/controller.dart';
import '../mesh/network.dart';
import 'page_route.dart';
import 'mesh_scroll_edge.dart';
import 'style.dart';

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({
    super.key,
    required this.controller,
    required this.notifications,
    required this.configureWifi,
  });

  final MeshController controller;
  final LocalMessageNotifications notifications;
  final Future<void> Function() configureWifi;

  @override
  Widget build(BuildContext context) => _NotificationPage(
    title: tr(context, 'Уведомления', 'Notifications'),
    notifications: notifications,
    controller: controller,
    buildGroups: (context) {
      final style = MeshStyle.of(context);
      final permission = notifications.permission;
      return [
        _NotificationGroup(
          title: tr(context, 'Получение уведомлений', 'Delivery'),
          note: tr(
            context,
            'Выключите, чтобы получать уведомления только от выбранной рации.',
            'Turn off to receive notifications only from the selected radio.',
          ),
          rows: [
            _toggle(
              context,
              notifications,
              NotificationSetting.allRadios,
              'Все рации',
              'All radios',
            ),
            MeshRow(
              title: tr(context, 'Разрешение системы', 'System permission'),
              icon: Icons.phonelink_ring_outlined,
              tint: style.accent,
              detail: permission == NotificationPermission.enabled
                  ? _status(context, true)
                  : _status(context, false),
              onTap: () => unawaited(notifications.managePermission()),
            ),
            if (notifications.wifiPushAvailable)
              MeshRow(
                title: tr(
                  context,
                  'Уведомления по Wi-Fi',
                  'Wi-Fi notifications',
                ),
                icon: Icons.wifi_rounded,
                tint: style.accent,
                subtitle: notifications.wifiPushSsid.isEmpty
                    ? null
                    : notifications.wifiPushSsid,
                detail: notifications.wifiPushSsid.isEmpty
                    ? _status(context, false)
                    : notifications.wifiPushActive
                    ? tr(context, 'Сеть найдена', 'Network matched')
                    : tr(context, 'Ожидание сети', 'Waiting for network'),
                onTap: () => unawaited(configureWifi()),
              ),
          ],
        ),
        _NotificationGroup(
          title: tr(context, 'Что показывать', 'What to notify about'),
          rows: [
            for (final channel in [false, true])
              MeshRow(
                title: _category(context, channel),
                icon: channel
                    ? Icons.campaign_outlined
                    : Icons.person_outline_rounded,
                tint: channel ? const Color(0xffb56836) : style.accent,
                subtitle: _exceptionCount(context, controller, channel),
                detail: _status(
                  context,
                  notifications.option(
                    channel
                        ? NotificationSetting.channels
                        : NotificationSetting.direct,
                  ),
                ),
                onTap: () => unawaited(
                  Navigator.of(context).push<void>(
                    meshPageRoute(
                      context,
                      builder: (_) =>
                          _CategoryPage(controller, notifications, channel),
                    ),
                  ),
                ),
              ),
            MeshRow(
              title: tr(context, 'Реакции', 'Reactions'),
              icon: Icons.favorite_border_rounded,
              tint: const Color(0xffa74e79),
              detail: _status(
                context,
                notifications.option(NotificationSetting.reactions),
              ),
              onTap: () => unawaited(
                Navigator.of(context).push<void>(
                  meshPageRoute(
                    context,
                    builder: (context) => _NotificationPage(
                      title: tr(context, 'Реакции', 'Reactions'),
                      controller: controller,
                      notifications: notifications,
                      buildGroups: (context) => [
                        _NotificationGroup(
                          rows: [
                            _toggle(
                              context,
                              notifications,
                              NotificationSetting.reactions,
                              'Реакции на мои сообщения',
                              'Reactions to my messages',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        _NotificationGroup(
          title: tr(context, 'В приложении', 'In the app'),
          rows: [
            _toggle(
              context,
              notifications,
              NotificationSetting.inAppSound,
              'Звук',
              'Sound',
            ),
            _toggle(
              context,
              notifications,
              NotificationSetting.vibration,
              'Вибрация',
              'Vibration',
            ),
          ],
        ),
        _NotificationGroup(
          title: tr(context, 'Предпросмотр', 'Preview'),
          rows: [
            _toggle(
              context,
              notifications,
              NotificationSetting.preview,
              'Показывать текст',
              'Show message text',
            ),
            _toggle(
              context,
              notifications,
              NotificationSetting.names,
              'Показывать имена',
              'Show names',
            ),
          ],
        ),
        if (Platform.isIOS)
          _NotificationGroup(
            title: tr(context, 'Счётчик на иконке', 'App icon badge'),
            note: tr(
              context,
              'Можно считать непрочитанные сообщения или чаты.',
              'Choose whether to count unread messages or chats.',
            ),
            rows: [
              _toggle(
                context,
                notifications,
                NotificationSetting.badge,
                'Показывать счётчик',
                'Show badge',
              ),
              if (notifications.option(NotificationSetting.badge)) ...[
                _toggle(
                  context,
                  notifications,
                  NotificationSetting.badgeChannels,
                  'Учитывать каналы',
                  'Include channels',
                ),
                _toggle(
                  context,
                  notifications,
                  NotificationSetting.badgeMessages,
                  'Считать сообщения',
                  'Count messages',
                ),
              ],
            ],
          ),
        _NotificationGroup(
          rows: [
            MeshRow(
              title: tr(
                context,
                'Сбросить настройки уведомлений',
                'Reset notification settings',
              ),
              titleColor: Theme.of(context).colorScheme.error,
              showChevron: false,
              onTap: () => unawaited(_reset(context)),
            ),
          ],
        ),
      ];
    },
  );

  Future<void> _reset(BuildContext context) async {
    final confirmed = await showMeshDialog<bool>(
      context: context,
      builder: (context) => MeshDialog(
        title: Text(tr(context, 'Сбросить настройки?', 'Reset settings?')),
        content: Text(
          tr(
            context,
            'Настройки вернутся к исходным значениям. Исключения для чатов будут удалены.',
            'Defaults will be restored and chat exceptions will be removed.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Сбросить', 'Reset')),
          ),
        ],
      ),
    );
    if (confirmed == true) notifications.resetPreferences();
  }
}

typedef _Exception = ({Radio radio, Peer peer});

Iterable<_Exception> _peers(MeshController controller, bool channel) sync* {
  for (final radio in controller.radios) {
    for (final peer in controller.peersFor(radio)) {
      if (peer.channel == channel) yield (radio: radio, peer: peer);
    }
  }
}

String? _exceptionCount(
  BuildContext context,
  MeshController controller,
  bool channel,
) {
  final count = _peers(controller, channel)
      .where(
        (item) =>
            controller.notificationException(item.radio, item.peer.id) != null,
      )
      .length;
  return count == 0
      ? null
      : tr(context, 'Исключений: $count', 'Exceptions: $count');
}

class _CategoryPage extends StatelessWidget {
  const _CategoryPage(this.controller, this.notifications, this.channel);
  final MeshController controller;
  final LocalMessageNotifications notifications;
  final bool channel;

  @override
  Widget build(BuildContext context) => _NotificationPage(
    title: _category(context, channel),
    notifications: notifications,
    controller: controller,
    buildGroups: (context) {
      final style = MeshStyle.of(context);
      final chats = _peers(controller, channel).toList();
      final exceptions = chats
          .where(
            (item) =>
                controller.notificationException(item.radio, item.peer.id) !=
                null,
          )
          .toList();
      return [
        _NotificationGroup(
          rows: [
            _toggle(
              context,
              notifications,
              channel
                  ? NotificationSetting.channels
                  : NotificationSetting.direct,
              'Показывать уведомления',
              'Show notifications',
            ),
          ],
        ),
        _NotificationGroup(
          title: tr(
            context,
            'Оформление уведомлений',
            'Notification appearance',
          ),
          rows: [
            _toggle(
              context,
              notifications,
              channel
                  ? NotificationSetting.channelPreview
                  : NotificationSetting.directPreview,
              'Показывать текст',
              'Show message text',
            ),
            _toggle(
              context,
              notifications,
              channel
                  ? NotificationSetting.channelSound
                  : NotificationSetting.directSound,
              'Звук',
              'Sound',
            ),
          ],
        ),
        _NotificationGroup(
          title: tr(context, 'Исключения', 'Exceptions'),
          rows: [
            MeshRow(
              title: tr(context, 'Добавить исключение', 'Add exception'),
              icon: Icons.add,
              tint: style.accent,
              titleColor: style.accent,
              showChevron: false,
              onTap: () => unawaited(_pick(context, chats)),
            ),
            for (final item in exceptions)
              MeshRow(
                title: item.peer.name,
                leading: MeshAvatar(item.peer.name, size: 34, channel: channel),
                subtitle: item.radio.name,
                detail: _status(
                  context,
                  controller.notificationException(item.radio, item.peer.id)!,
                ),
                onTap: () => unawaited(_edit(context, item)),
              ),
          ],
        ),
      ];
    },
  );

  Future<void> _pick(BuildContext context, List<_Exception> items) async {
    final selected = await showMeshSheet<_Exception>(
      context: context,
      builder: (context) => SheetBody(
        title: tr(context, 'Добавить исключение', 'Add exception'),
        children: items.isEmpty
            ? [
                Text(
                  tr(
                    context,
                    'Список появится после подключения рации.',
                    'Connect a radio to load this list.',
                  ),
                ),
              ]
            : [
                MeshGroup(
                  children: [
                    for (final item in items)
                      MeshRow(
                        title: item.peer.name,
                        subtitle: item.radio.name,
                        leading: MeshAvatar(
                          item.peer.name,
                          size: 34,
                          channel: channel,
                        ),
                        onTap: () => Navigator.pop(context, item),
                      ),
                  ],
                ),
              ],
      ),
    );
    if (selected != null && context.mounted) await _edit(context, selected);
  }

  Future<void> _edit(BuildContext context, _Exception item) async {
    final selection = await showMeshSheet<String>(
      context: context,
      builder: (context) => SheetBody(
        title: item.peer.name,
        children: [
          MeshGroup(
            children: [
              for (final (key, ru, en) in [
                ('on', 'Включить уведомления', 'Enable notifications'),
                ('off', 'Выключить уведомления', 'Mute notifications'),
                ('default', 'По настройке раздела', 'Use category setting'),
              ])
                MeshRow(
                  title: tr(context, ru, en),
                  showChevron: false,
                  onTap: () => Navigator.pop(context, key),
                ),
            ],
          ),
        ],
      ),
    );
    if (selection != null &&
        controller.radios.any(
          (radio) => radioKey(radio) == radioKey(item.radio),
        )) {
      controller.setNotificationException(
        item.radio,
        item.peer.id,
        selection == 'default' ? null : selection == 'on',
      );
    }
  }
}

class _NotificationPage extends StatelessWidget {
  const _NotificationPage({
    required this.title,
    required this.controller,
    required this.notifications,
    required this.buildGroups,
  });
  final String title;
  final MeshController controller;
  final LocalMessageNotifications notifications;
  final List<Widget> Function(BuildContext) buildGroups;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          PageHeading(
            title,
            leading: GlassButton(
              icon: Icons.arrow_back_ios_new_rounded,
              label: tr(context, 'Назад', 'Back'),
              onTap: () => Navigator.pop(context),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([notifications, controller]),
              builder: (context, _) => MeshScrollViewport(
                tint: MeshStyle.of(context).canvas,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: buildGroups(context),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _NotificationGroup extends StatelessWidget {
  const _NotificationGroup({required this.rows, this.title, this.note});
  final List<Widget> rows;
  final String? title, note;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title case final text?)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Text(
                text,
                style: TextStyle(
                  color: style.secondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          MeshGroup(
            inset:
                rows.whereType<MeshRow>().any(
                  (row) => row.icon != null || row.leading != null,
                )
                ? 63
                : 15,
            children: rows,
          ),
          if (note case final text?)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Text(
                text,
                style: TextStyle(
                  color: style.secondary,
                  height: 1.3,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _category(BuildContext context, bool channel) => channel
    ? tr(context, 'Каналы', 'Channels')
    : tr(context, 'Личные чаты', 'Direct chats');

String _status(BuildContext context, bool value) =>
    value ? tr(context, 'Вкл.', 'On') : tr(context, 'Выкл.', 'Off');

Widget _toggle(
  BuildContext context,
  LocalMessageNotifications notifications,
  NotificationSetting setting,
  String ru,
  String en,
) {
  final title = tr(context, ru, en);
  final value = notifications.option(setting);
  return MeshRow(
    title: title,
    showChevron: false,
    trailing: Semantics(
      label: title,
      child: Switch.adaptive(
        value: value,
        onChanged: (value) => notifications.setOption(setting, value),
      ),
    ),
  );
}
