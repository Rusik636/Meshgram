enum MessageRoute { direct, flood }

/// Information attached to this packet or to its matching delivery response.
class MessagePacket {
  const MessagePacket({
    this.sender,
    this.recipient,
    this.channel,
    this.hops,
    this.hopLimit,
    this.snr,
    this.rssi,
    this.route,
    this.relaySuffix,
    this.viaMqtt,
    this.pkiEncrypted,
    this.confirmedBy,
    this.ackSnr,
    this.ackRssi,
    this.roundTripMs,
    this.routingError,
  });

  final String? sender, recipient, confirmedBy;
  final int? channel, hops, hopLimit, rssi, relaySuffix, ackRssi;
  final int? roundTripMs, routingError;
  final double? snr, ackSnr;
  final MessageRoute? route;
  final bool? viaMqtt, pkiEncrypted;

  MessagePacket merge(MessagePacket update) => MessagePacket(
    sender: update.sender ?? sender,
    recipient: update.recipient ?? recipient,
    channel: update.channel ?? channel,
    hops: update.hops ?? hops,
    hopLimit: update.hopLimit ?? hopLimit,
    snr: update.snr ?? snr,
    rssi: update.rssi ?? rssi,
    route: update.route ?? route,
    relaySuffix: update.relaySuffix ?? relaySuffix,
    viaMqtt: update.viaMqtt ?? viaMqtt,
    pkiEncrypted: update.pkiEncrypted ?? pkiEncrypted,
    confirmedBy: update.confirmedBy ?? confirmedBy,
    ackSnr: update.ackSnr ?? ackSnr,
    ackRssi: update.ackRssi ?? ackRssi,
    roundTripMs: update.roundTripMs ?? roundTripMs,
    routingError: update.routingError ?? routingError,
  );

  Map<String, Object> toJson() => {
    'sender': ?sender,
    'recipient': ?recipient,
    'channel': ?channel,
    'hops': ?hops,
    'hopLimit': ?hopLimit,
    'snr': ?snr,
    'rssi': ?rssi,
    'route': ?route?.name,
    'relaySuffix': ?relaySuffix,
    'viaMqtt': ?viaMqtt,
    'pkiEncrypted': ?pkiEncrypted,
    'confirmedBy': ?confirmedBy,
    'ackSnr': ?ackSnr,
    'ackRssi': ?ackRssi,
    'roundTripMs': ?roundTripMs,
    'routingError': ?routingError,
  };

  factory MessagePacket.fromJson(Map json) => MessagePacket(
    sender: json['sender'] as String?,
    recipient: json['recipient'] as String?,
    channel: json['channel'] as int?,
    hops: json['hops'] as int?,
    hopLimit: json['hopLimit'] as int?,
    snr: (json['snr'] as num?)?.toDouble(),
    rssi: json['rssi'] as int?,
    route: MessageRoute.values
        .where((route) => route.name == json['route'])
        .firstOrNull,
    relaySuffix: json['relaySuffix'] as int?,
    viaMqtt: json['viaMqtt'] as bool?,
    pkiEncrypted: json['pkiEncrypted'] as bool?,
    confirmedBy: json['confirmedBy'] as String?,
    ackSnr: (json['ackSnr'] as num?)?.toDouble(),
    ackRssi: json['ackRssi'] as int?,
    roundTripMs: json['roundTripMs'] as int?,
    routingError: json['routingError'] as int?,
  );
}
