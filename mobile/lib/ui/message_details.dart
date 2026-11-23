// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart' hide Radio;

import '../mesh/message_packet.dart';
import '../mesh/network.dart';
import 'style.dart';

String? meshtasticNodeAddress(String id) {
  final number = int.tryParse(id.startsWith('node:') ? id.substring(5) : id);
  if (number == null || number < 0 || number > 0xffffffff) return null;
  return '!${number.toRadixString(16).padLeft(8, '0')}';
}

String messageDeliveryLabel(
  BuildContext context,
  Delivery delivery, {
  required bool channel,
}) => switch (delivery) {
  Delivery.received => tr(context, 'Получено', 'Received'),
  Delivery.queued || Delivery.submitted || Delivery.relayed => tr(
    context,
    'Ожидание подтверждения',
    'Waiting for confirmation',
  ),
  Delivery.acknowledged =>
    channel
        ? tr(context, 'Получено узлом сети', 'Heard by a mesh node')
        : tr(context, 'Доставлено', 'Delivered'),
  Delivery.unconfirmed => tr(
    context,
    'Подтверждение не получено',
    'No confirmation received',
  ),
  Delivery.failed => tr(context, 'Отправка не удалась', 'Send failed'),
};

class MessageDetails extends StatelessWidget {
  const MessageDetails({
    super.key,
    required this.message,
    required this.peer,
    required this.radio,
    required this.networkLabel,
    required this.nodeName,
  });

  final MeshMessage message;
  final Peer peer;
  final Radio? radio;
  final String? networkLabel;
  final String? Function(String) nodeName;

  String? _node(String? id, [String? name]) {
    if (id == null) return name?.isNotEmpty == true ? name : null;
    final key = id.startsWith('node:') ? id.substring(5) : id;
    final address = radio?.network == 'meshtastic'
        ? meshtasticNodeAddress(id) ?? key
        : key;
    final label = nodeName(id) ?? name;
    return label == null || label.isEmpty || label == address
        ? address
        : '$label ($address)';
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final packet = message.packet;
    final local = message.time.toLocal();
    final locale = MaterialLocalizations.of(context);
    String l(String ru, String en) => tr(context, ru, en);
    final db = l('дБ', 'dB'), dbm = l('дБм', 'dBm');
    final rows = <(String, String?)>[
      (l('Протокол', 'Protocol'), networkLabel),
      (l('Рация', 'Radio'), radio?.name),
      (
        l('Отправитель', 'Sender'),
        _node(packet?.sender, message.outgoing ? radio?.name : message.author),
      ),
      if (peer.channel)
        (l('Канал', 'Channel'), peer.name)
      else
        (
          l('Получатель', 'Recipient'),
          _node(packet?.recipient, message.outgoing ? peer.name : radio?.name),
        ),
      (
        l('Время', 'Time'),
        '${locale.formatShortDate(local)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}',
      ),
      (
        l('Статус', 'Status'),
        messageDeliveryLabel(context, message.delivery, channel: peer.channel),
      ),
      if (radio?.network == 'meshtastic')
        (l('ID пакета', 'Packet ID'), message.remoteId),
      if (packet?.channel case final channel?)
        (l('Индекс канала', 'Channel index'), '$channel'),
      if (packet?.route case final route?)
        (
          l('Маршрут', 'Route'),
          route == MessageRoute.direct
              ? l('Прямой', 'Direct')
              : l('Рассылка', 'Flood'),
        ),
      if (packet?.hops case final hops?) (l('Переходы', 'Hops'), '$hops'),
      if (packet?.hopLimit case final limit?)
        (l('Осталось переходов', 'Remaining hops'), '$limit'),
      if (packet?.relaySuffix case final relay?)
        (
          l('Окончание ID ретранслятора', 'Relay ID suffix'),
          '…${relay.toRadixString(16).padLeft(2, '0')}',
        ),
      if (packet?.snr case final snr?) ('SNR', '${snr.toStringAsFixed(2)} $db'),
      if (packet?.rssi case final rssi?) ('RSSI', '$rssi $dbm'),
      if (packet?.viaMqtt == true) (l('Транспорт', 'Transport'), 'MQTT'),
      if (packet?.pkiEncrypted == true) (l('Шифрование', 'Encryption'), 'PKI'),
      if (packet?.confirmedBy case final id?)
        (l('Подтвердил', 'Confirmed by'), _node(id)),
      if (packet?.ackSnr case final snr?)
        (l('SNR подтверждения', 'ACK SNR'), '${snr.toStringAsFixed(2)} $db'),
      if (packet?.ackRssi case final rssi?)
        (l('RSSI подтверждения', 'ACK RSSI'), '$rssi $dbm'),
      if (packet?.roundTripMs case final value?)
        (l('Время ответа', 'Round-trip time'), '$value ${l('мс', 'ms')}'),
      if (packet?.routingError case final error?)
        (l('Код ошибки маршрутизации', 'Routing error code'), '$error'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        children: [
          for (final (label, value) in rows)
            if (value != null && value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(color: style.secondary, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: style.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
