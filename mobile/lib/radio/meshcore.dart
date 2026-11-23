// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' show AESEngine, KeyParameter;

import '../app_name.dart';
import '../mesh/contact_attachment.dart';
import '../mesh/message_packet.dart';
import '../mesh/network.dart';
import '../mesh/nodes.dart';
import '../mesh/radio_settings_index.dart';
import '../mesh/route_trace.dart';
import 'channel_keys.dart';
import 'meshcore_reactions.dart';

part 'meshcore_settings.dart';

class MeshCoreAdapter
    implements
        NetworkAdapter,
        NetworkLanAdapter,
        NetworkBufferedMessages,
        NetworkMessageBudget,
        NetworkMessageReferences,
        NetworkContactCodes,
        NetworkNodeSorting {
  const MeshCoreAdapter();

  @override
  String get id => 'meshcore';
  @override
  String get label => 'MeshCore';
  @override
  List<NodeSort> get additionalNodeSorts => const [NodeSort.messages];
  @override
  String get service => '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  @override
  LanRadioProtocol get lan => const LanRadioProtocol(
    port: 5000,
    inputPrefix: [0x3e],
    outputPrefix: [0x3c],
    endian: Endian.little,
    maxPayload: 176,
    rx: _CoreSession._rx,
    tx: _CoreSession._tx,
  );
  @override
  NetworkSession createSession(RadioLink link) => _CoreSession(link);

  @override
  NetworkEvent? bufferedMessage(
    Uint8List frame,
    Map<String, Peer> peers,
    int? localNode,
    DateTime receivedAt,
  ) => MeshCoreFrames.messageEvent(frame, peers);

  @override
  String? referenceFor(MeshMessage message) =>
      message.outgoing && message.chat.startsWith('ch:')
      ? null
      : meshCoreMessageReference(
          message.text,
          message.time.millisecondsSinceEpoch ~/ 1000,
          sender: message.chat.startsWith('ch:') ? message.author : null,
        );

  @override
  Uri? contactCode(Peer peer, NodeIdentity identity) {
    final type = identity.type;
    if (type == null ||
        type < 1 ||
        type > 4 ||
        !validContactKey(identity.publicKey)) {
      return null;
    }
    return Uri(
      scheme: 'meshcore',
      host: 'contact',
      path: '/add',
      queryParameters: {
        'name': fitContactName(peer.name, 31),
        'public_key': identity.publicKey,
        'type': '$type',
      },
    );
  }

  @override
  ({String id, String publicKey})? readContactCode(Uri uri) {
    final contact = readContactAttachment(uri);
    return contact == null
        ? null
        : (id: contact.id, publicKey: contact.publicKey);
  }

  @override
  ContactAttachment? readContactAttachment(Uri uri) {
    if (uri.scheme != 'meshcore' ||
        uri.host != 'contact' ||
        uri.path != '/add' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment) {
      return null;
    }
    final key = uri.queryParameters['public_key']?.toLowerCase();
    final type = int.tryParse(uri.queryParameters['type'] ?? '');
    if (key == null ||
        !validContactKey(key) ||
        type == null ||
        type < 1 ||
        type > 4) {
      return null;
    }
    final prefix = key.substring(0, 12);
    final name = fitContactName(uri.queryParameters['name'] ?? '', 31);
    return (
      network: id,
      id: 'node:$prefix',
      name: name.isNotEmpty ? name : prefix,
      publicKey: key,
      type: type,
      shortName: null,
    );
  }

  @override
  int messageBytes(Peer peer, String radioName) =>
      peer.channel ? (158 - utf8.encode(radioName).length).clamp(80, 156) : 156;
}

class MeshCoreFrames {
  static String hex(Iterable<int> data) =>
      data.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static String text(List<int> data, {bool trim = true}) {
    final value = utf8.decode(
      data.takeWhile((byte) => byte != 0).toList(),
      allowMalformed: true,
    );
    return trim ? value.trim() : value;
  }

  static Uint8List littleEndian32(int value) =>
      (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

  static int u32(Uint8List data, int offset) =>
      ByteData.sublistView(data).getUint32(offset, Endian.little);

  static Peer? contact(Uint8List data) {
    if (data.length < 132) return null;
    final id = 'node:${hex(data.sublist(1, 7))}';
    final name = text(data.sublist(100, 132));
    return (
      id: id,
      name: name.isEmpty ? id.substring(5) : name,
      channel: false,
      writable: data[33] == 1,
    );
  }

  static List<RadioField> repeaterStatus(Uint8List frame) {
    if (frame.length < 32 || frame[0] != 0x87) {
      throw const FormatException('Incomplete MeshCore status');
    }
    final data = ByteData.sublistView(frame, 8);
    RadioField stat(
      String id,
      String en,
      String ru,
      num value, [
      String? units,
    ]) => RadioField(
      id,
      en,
      ru,
      '$value',
      editable: false,
      section: RadioFieldSection.telemetry,
      units: units,
    );
    return [
      stat(
        'voltage',
        'Battery',
        'Батарея',
        data.getUint16(0, Endian.little),
        'mV',
      ),
      stat(
        'queued',
        'Transmit queue',
        'Очередь отправки',
        data.getUint16(2, Endian.little),
      ),
      stat(
        'noise',
        'Noise floor',
        'Уровень шума',
        data.getInt16(4, Endian.little),
        'dBm',
      ),
      stat(
        'rssi',
        'Last RSSI',
        'Последний RSSI',
        data.getInt16(6, Endian.little),
        'dBm',
      ),
      stat(
        'received',
        'Packets received',
        'Получено пакетов',
        data.getUint32(8, Endian.little),
      ),
      stat(
        'sent',
        'Packets sent',
        'Отправлено пакетов',
        data.getUint32(12, Endian.little),
      ),
      stat(
        'airtime',
        'Airtime',
        'Время передачи',
        data.getUint32(16, Endian.little),
        's',
      ),
      stat(
        'uptime',
        'Uptime',
        'Время работы',
        data.getUint32(20, Endian.little),
        's',
      ),
      if (data.lengthInBytes >= 44)
        stat(
          'snr',
          'Last SNR',
          'Последний SNR',
          data.getInt16(42, Endian.little) / 4,
          'dB',
        ),
    ];
  }

  /// The firmware logs the original encrypted payload when a repeater forwards it.
  static ({String payload, int hops})? relayedGroup(Uint8List log) {
    if (log.length < 6 || log[0] != 0x88) return null;
    final header = log[3];
    final route = header & 3;
    if ((header >> 2) & 15 != 5 || (route != 0 && route != 1)) return null;
    final pathIndex = route == 0 ? 8 : 4;
    if (pathIndex >= log.length) return null;
    final path = log[pathIndex];
    final count = path & 63;
    final width = (path >> 6) + 1;
    if (count == 0 || width > 3) return null;
    final payload = pathIndex + 1 + count * width;
    if (payload + 19 > log.length || (log.length - payload - 3) % 16 != 0) {
      return null;
    }
    return (payload: hex(log.sublist(payload)), hops: count);
  }

  static String groupPayload(
    Uint8List key,
    int stamp,
    String sender,
    String text,
  ) {
    final body = utf8.encode('$sender: $text');
    final length = 5 + body.length;
    final data = Uint8List((length + 15) ~/ 16 * 16);
    ByteData.sublistView(data).setUint32(0, stamp, Endian.little);
    data.setRange(5, length, body);
    final encoded = Uint8List(data.length);
    final cipher = AESEngine()..init(true, KeyParameter(key));
    for (var offset = 0; offset < data.length; offset += cipher.blockSize) {
      cipher.processBlock(data, offset, encoded, offset);
    }
    final auth = Hmac(sha256, key).convert(encoded).bytes;
    return hex([sha256.convert(key).bytes.first, auth[0], auth[1], ...encoded]);
  }

  static List<int> send(Peer peer, MeshMessage message, {int? stamp}) {
    final timestamp = stamp ?? message.time.millisecondsSinceEpoch ~/ 1000;
    final time = (ByteData(
      4,
    )..setUint32(0, timestamp, Endian.little)).buffer.asUint8List();
    final body = utf8.encode(message.text);
    if (peer.channel) {
      return [3, 0, int.parse(peer.id.substring(3)), ...time, ...body];
    }
    final prefix = peer.id.substring(5);
    return [
      2,
      0,
      0,
      ...time,
      for (var i = 0; i < 12; i += 2)
        int.parse(prefix.substring(i, i + 2), radix: 16),
      ...body,
    ];
  }

  static MeshMessage? incoming(Uint8List data, Map<String, Peer> peers) {
    if (data.isEmpty || !const [7, 8, 16, 17].contains(data[0])) return null;
    final direct = data[0] == 7 || data[0] == 16;
    final base = data[0] >= 16 ? 4 : 1;
    final stampAt = base + (direct ? 8 : 3);
    if (data.length <= stampAt + 4) return null;
    final kind = data[stampAt - 1];
    if (kind != 0 && kind != 2) return null;
    final chat = direct
        ? 'node:${hex(data.sublist(base, base + 6))}'
        : 'ch:${data[base]}';
    final stamp = u32(data, stampAt);
    final start = stampAt + 4 + (direct && kind == 2 ? 4 : 0);
    if (start >= data.length) return null;
    final original = text(data.sublist(start), trim: false);
    final wireText = original.trim();
    final separation = direct ? -1 : wireText.indexOf(': ');
    final author = direct
        ? peers[chat]?.name ?? chat.substring(5)
        : separation > 0
        ? wireText.substring(0, separation)
        : '';
    final body = separation > 0 ? wireText.substring(separation + 2) : wireText;
    if (body.isEmpty) return null;
    final originalBody = separation > 0
        ? original.substring(original.indexOf(': ') + 2)
        : original;
    final path = data[stampAt - 2];
    return MeshMessage(
      id: 'mc:$chat:$stamp:${base64Encode(utf8.encode(wireText))}',
      chat: chat,
      author: author,
      text: body,
      time: DateTime.fromMillisecondsSinceEpoch(stamp * 1000),
      delivery: Delivery.received,
      remoteId: meshCoreMessageReference(
        originalBody,
        stamp,
        sender: direct ? null : author,
      ),
      packet: MessagePacket(
        sender: direct ? chat : null,
        channel: direct ? null : data[base],
        route: path == 0xff ? MessageRoute.direct : MessageRoute.flood,
        hops: path == 0xff ? null : path & 63,
        snr: base == 4 ? data[1].toSigned(8) / 4 : null,
      ),
    );
  }

  static NetworkEvent? messageEvent(Uint8List frame, Map<String, Peer> peers) {
    final message = incoming(frame, peers);
    if (message == null) return null;
    final channel = message.chat.startsWith('ch:');
    final reaction = readMeshCoreReaction(message.text, channel: channel);
    if (reaction != null) {
      return ReactionReceived(
        MeshReaction(
          message.chat,
          reaction.target,
          channel ? 'name:${message.author}' : message.chat,
          reaction.emoji,
          time: message.time,
        ),
      );
    }
    return TextReceived(
      message,
      peers[message.chat] ??
          (
            id: message.chat,
            name: channel ? '#${message.chat.substring(3)}' : message.author,
            writable: false,
            channel: channel,
          ),
    );
  }
}

class _CoreSession
    implements
        NetworkSession,
        NetworkReactions,
        RemoteAdminSession,
        RadioSettingsSession,
        RadioSettingsCatalog,
        RadioSettingsIndex,
        RadioTelemetrySession,
        RadioBatteryReader,
        NetworkNodeActions,
        NetworkRouteTracing,
        RadioOnboardingSession,
        RadioChannelSession,
        RadioConversationSession,
        RadioContactSession,
        RadioPositionSession,
        RadioRestartSession {
  _CoreSession(this.link);
  static const _rx = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const _tx = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  final RadioLink link;
  final _events = StreamController<NetworkEvent>.broadcast();
  final _directory = <String, Peer>{};
  final _identities = <String, NodeIdentity>{};
  ({String id, Set<int> responses, Completer<Uint8List> result})? _adminPush;
  final _acks = <int, String>{};
  final _channelKeys = <int, Uint8List>{};
  final _groupEchoes = <String, String>{};
  int _lastGroupStamp = 0;
  Completer<Uint8List>? _binaryReply;
  int? _binaryTag;
  StreamSubscription<void>? _disconnect;
  StreamSubscriptionHandle? _notices;
  Future<void> _queue = Future.value();
  Completer<Uint8List>? _response;
  ({Peer peer, int request, DateTime until})? _routeDiscovery;
  final _routeProbes = <int, bool Function(Uint8List)>{};
  Set<int> _expected = {};
  Timer? _poll;
  String _name = '';
  String? _publicKey;
  String? _factoryName;
  RadioDeviceInfo? _deviceMetadata;
  int _protocol = 0;
  int? _blePin;
  bool _catalogProbed = false;
  bool _autoAddSupported = false;
  bool _scopeSupported = false;
  final _cliFields = <String>{};
  bool _hasCustomSettings = false;
  int _channelSlots = 8;
  int _cliTimestamp = 0;
  final _batteryClock = Stopwatch()..start();
  ({int millivolts, Duration time})? _lastBatterySample;
  bool _batteryCharging = false;
  bool _closed = false, _ready = false, _draining = false;

  @override
  Stream<NetworkEvent> get events => _events.stream;
  void _emit(NetworkEvent event) {
    if (!_closed) _events.add(event);
  }

  Future<T> _serial<T>(Future<T> Function() run) {
    final result = _queue.then((_) {
      if (_closed) throw StateError('Radio disconnected');
      return run();
    });
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Uint8List> _command(
    List<int> packet,
    Set<int> expected, {
    int seconds = 5,
  }) async {
    if (_closed) throw StateError('Radio disconnected');
    final reply = _response = Completer<Uint8List>();
    _expected = expected;
    final future = reply.future.timeout(Duration(seconds: seconds));
    unawaited(future.then<void>((_) {}, onError: (Object _) {}));
    try {
      await link.write(_rx, packet);
      return await future;
    } finally {
      _response = null;
      _expected = {};
    }
  }

  Future<Uint8List> _selfInfo() =>
      _command([1, 3, 0, 0, 0, 0, 0, 0, ...utf8.encode(appName)], {5});

  Future<Uint8List> _deviceInfo() => _command([22, 3], {13});

  @override
  Future<void> restartRadio() => _serial(_sendRestart);

  Future<void> _sendRestart() async {
    _emit(const RadioRestartExpected(explicit: true));
    await link.write(_rx, [19, ...'reboot'.codeUnits]);
  }

  void _rememberDevice(Uint8List frame) {
    if (frame.length < 2 || frame[0] != 13) return;
    if (frame[1] >= 3 && frame.length >= 4) {
      _channelSlots = frame[3].clamp(1, 64);
    }
    _protocol = frame[1];
    if (_protocol >= 3 && frame.length >= 8) {
      _blePin = MeshCoreFrames.u32(frame, 4);
    }
    String? text(int start, int end) {
      if (frame.length < end) return null;
      final value = MeshCoreFrames.text(frame.sublist(start, end));
      return value.isEmpty ? null : value;
    }

    _deviceMetadata = (
      firmware: text(60, 80),
      board: text(20, 60),
      boardModel: null,
      build: text(8, 20),
      protocol: '$_protocol',
    );
  }

  @override
  Future<List<RadioField>> readSettings() => _serial(() async {
    final self = await _selfInfo();
    if (self[0] != 5 || self.length < 58) {
      throw StateError('MeshCore returned incomplete radio settings');
    }
    await _discoverSettings();
    final name = MeshCoreFrames.text(self.sublist(58));
    _factoryName = MeshCoreFrames.hex(self.sublist(4, 8));
    if (name.isNotEmpty && name != _name) {
      _name = name;
      _publish();
    }
    return [
      RadioField('name', 'Node name', 'Имя узла', name),
      RadioField(
        'frequency',
        'Frequency',
        'Частота',
        '${MeshCoreFrames.u32(self, 48) / 1000}',
        section: RadioFieldSection.lora,
        kind: RadioFieldKind.decimal,
        units: 'MHz',
      ),
      RadioField(
        'bandwidth',
        'Bandwidth',
        'Ширина полосы',
        '${MeshCoreFrames.u32(self, 52) / 1000}',
        section: RadioFieldSection.lora,
        kind: RadioFieldKind.decimal,
        units: 'kHz',
      ),
      RadioField(
        'sf',
        'Spreading factor',
        'Коэффициент расширения',
        '${self[56]}',
        section: RadioFieldSection.lora,
        kind: RadioFieldKind.integer,
      ),
      RadioField(
        'cr',
        'Coding rate',
        'Скорость кодирования',
        '${self[57]}',
        section: RadioFieldSection.lora,
        kind: RadioFieldKind.integer,
      ),
      RadioField(
        'power',
        'Transmit power',
        'Мощность передачи',
        '${self[2].toSigned(8)}',
        section: RadioFieldSection.lora,
        kind: RadioFieldKind.integer,
        units: 'dBm',
      ),
    ];
  });

  @override
  List<RadioFieldSection> get extraSettings => [
    RadioFieldSection.position,
    RadioFieldSection.routing,
    if (_protocol >= 5) RadioFieldSection.sensors,
    if (_blePin != null) RadioFieldSection.bluetooth,
    if (_protocol >= 3) RadioFieldSection.contacts,
    for (final section in [
      RadioFieldSection.connectivity,
      RadioFieldSection.notifications,
    ])
      if (_coreCliSettings.any(
        (item) => item.section == section && _cliFields.contains(item.key),
      ))
        section,
  ];

  @override
  Iterable<RadioSettingName> settingNames(RadioFieldSection section) sync* {
    if (!extraSettings.contains(section)) return;
    for (final setting in _coreCliSettings) {
      if (setting.section == section && _cliFields.contains(setting.key)) {
        yield (id: setting.key, title: setting.title, russian: setting.russian);
      }
    }
    final names = switch (section) {
      RadioFieldSection.position => [
        ('latitude', 'Latitude', 'Широта'),
        ('longitude', 'Longitude', 'Долгота'),
        (
          'advertPosition',
          'Advertise position',
          'Добавлять позицию в объявление',
        ),
        if (_hasCustomSettings) ...[
          ('custom:gps', 'GPS', 'GPS'),
          ('custom:gps_interval', 'GPS interval', 'Интервал GPS'),
        ],
      ],
      RadioFieldSection.bluetooth => [('pin', 'Pairing PIN', 'PIN сопряжения')],
      RadioFieldSection.contacts => [
        ('manual', 'Manually add contacts', 'Добавлять контакты вручную'),
        if (_autoAddSupported) ...[
          for (final (id, en, ru, _) in _coreContactFlags) (id, en, ru),
          (
            'maxHops',
            'Automatic import hop limit',
            'Лимит переходов для автодобавления',
          ),
        ],
      ],
      RadioFieldSection.sensors => [
        ('base', 'Battery data', 'Данные батареи'),
        ('position', 'Position data', 'Данные позиции'),
        ('environment', 'Environmental data', 'Данные окружающей среды'),
      ],
      RadioFieldSection.routing => [
        if (_protocol >= 9) ('repeat', 'Forward packets', 'Пересылать пакеты'),
        if (_protocol >= 10)
          ('path', 'Path hash length', 'Длина идентификатора маршрута'),
        if (_protocol >= 7)
          ('acks', 'Additional acknowledgments', 'Доп. подтверждения'),
        ('rxDelay', 'Receive delay factor', 'Множитель задержки приёма'),
        ('airtime', 'Airtime factor', 'Множитель эфирного времени'),
        if (_scopeSupported) ...[
          ('scopeName', 'Default scope name', 'Область маршрутизации'),
          ('scopeKey', 'Scope key', 'Ключ области'),
        ],
      ],
      _ => const <(String, String, String)>[],
    };
    for (final (id, title, russian) in names) {
      yield (id: id, title: title, russian: russian);
    }
  }

  static const _telemetryAccess = {
    '0': 'Disabled',
    '1': 'Contacts',
    '2': 'Everyone',
  };

  @override
  Future<List<RadioField>> readSection(RadioFieldSection section) =>
      _serial(() => _readSection(section));

  Future<List<RadioField>> _readSection(RadioFieldSection section) async {
    if (!extraSettings.contains(section)) return [];
    if (section == RadioFieldSection.connectivity ||
        section == RadioFieldSection.notifications) {
      return _readCliSettings(section);
    }
    if (section == RadioFieldSection.contacts) return _readContactSettings();
    if (section == RadioFieldSection.bluetooth) {
      return [
        RadioField(
          'pin',
          'Pairing PIN',
          'PIN сопряжения',
          '${_blePin ?? 0}',
          section: section,
          kind: RadioFieldKind.integer,
          secret: true,
        ),
      ];
    }
    final self = await _selfInfo();
    if (self[0] != 5 || self.length < 58) {
      throw StateError('Radio data unavailable');
    }
    switch (section) {
      case RadioFieldSection.position:
        final data = ByteData.sublistView(self);
        return [
          RadioField(
            'latitude',
            'Latitude',
            'Широта',
            '${data.getInt32(36, Endian.little) / 1000000}',
            kind: RadioFieldKind.decimal,
            section: section,
          ),
          RadioField(
            'longitude',
            'Longitude',
            'Долгота',
            '${data.getInt32(40, Endian.little) / 1000000}',
            kind: RadioFieldKind.decimal,
            section: section,
          ),
          RadioField(
            'advertPosition',
            'Advertise position',
            'Добавлять позицию в объявление',
            '${self[45] != 0}',
            kind: RadioFieldKind.toggle,
            section: section,
          ),
          ...await _readCliSettings(section),
          ...await _readCustomSettings(section),
        ];
      case RadioFieldSection.routing:
        final device = _protocol == 0
            ? null
            : await _optionalCommand([22, 3], 13);
        final tuning = await _optionalCommand([43], 23);
        return [
          if (device != null && device.length > 80 && device[1] >= 9)
            RadioField(
              'repeat',
              'Forward packets',
              'Пересылать пакеты',
              '${device[80] != 0}',
              kind: RadioFieldKind.toggle,
              section: section,
            ),
          if (device != null && device.length > 81 && device[1] >= 10)
            RadioField(
              'path',
              'Path hash length',
              'Длина идентификатора маршрута',
              '${device[81]}',
              kind: RadioFieldKind.choice,
              section: section,
              choices: const {'0': '1 B', '1': '2 B', '2': '3 B'},
            ),
          if (_protocol >= 7)
            RadioField(
              'acks',
              'Additional acknowledgments',
              'Доп. подтверждения',
              '${self[44]}',
              kind: RadioFieldKind.choice,
              section: section,
              choices: const {'0': '0', '1': '1', '2': '2'},
            ),
          if (tuning != null && tuning.length >= 9) ...[
            RadioField(
              'rxDelay',
              'Receive delay factor',
              'Множитель задержки приёма',
              '${MeshCoreFrames.u32(tuning, 1) / 1000}',
              kind: RadioFieldKind.decimal,
              section: section,
            ),
            RadioField(
              'airtime',
              'Airtime factor',
              'Множитель эфирного времени',
              '${MeshCoreFrames.u32(tuning, 5) / 1000}',
              kind: RadioFieldKind.decimal,
              section: section,
            ),
          ],
          ...await _readCliSettings(section),
          if (_scopeSupported) ...await _readScope(),
        ];
      case RadioFieldSection.sensors:
        return [
          for (final (id, en, ru, shift) in const [
            ('base', 'Battery data', 'Данные батареи', 0),
            ('position', 'Position data', 'Данные позиции', 2),
            ('environment', 'Environmental data', 'Данные окружающей среды', 4),
          ])
            RadioField(
              id,
              en,
              ru,
              '${(self[46] >> shift) & 3}',
              kind: RadioFieldKind.choice,
              section: section,
              choices: _telemetryAccess,
            ),
          ...await _readCustomSettings(section),
        ];
      default:
        return [];
    }
  }

  @override
  Future<void> writeSection(
    RadioFieldSection section,
    Map<String, String> values,
  ) => _serial(() async {
    if (values.isEmpty) return;
    final fields = await _readSection(section);
    final editable = fields
        .where((field) => field.editable)
        .map((field) => field.id)
        .toSet();
    if (!editable.containsAll(values.keys)) {
      throw const FormatException('Unsupported radio setting');
    }
    if (section == RadioFieldSection.bluetooth) {
      final pin = int.tryParse(values['pin'] ?? '');
      if (pin == null || (pin != 0 && (pin < 100000 || pin > 999999))) {
        throw const FormatException('Enter a six-digit PIN or zero');
      }
      if (pin == _blePin) return;
      await _requireOk([37, ...MeshCoreFrames.littleEndian32(pin)]);
      _blePin = pin;
      await _sendRestart();
      return;
    }
    if (section == RadioFieldSection.contacts) {
      await _writeContactSettings(values);
      return;
    }
    final cli = _prepareCliWrites(section, values);
    final custom = _prepareCustomWrites(values);
    if (section == RadioFieldSection.connectivity) {
      _emit(const RadioRestartExpected());
      final needsRestart = await _writeCliSettings(cli);
      if (needsRestart) await _sendRestart();
      return;
    }
    if (section == RadioFieldSection.notifications) {
      await _writeCliSettings(cli);
      return;
    }
    final self = await _selfInfo();
    if (self[0] != 5 || self.length < 58) {
      throw StateError('Radio data unavailable');
    }
    final commands = <List<int>>[];
    int number(String key, int old, int min, int max) =>
        values[key] == null ? old : _bounded(values[key]!, min, max);
    int decimal(String key, int old, int scale, double min, double max) {
      final input = values[key];
      if (input == null) return old;
      final value = double.tryParse(input.replaceAll(',', '.'));
      if (value == null || !value.isFinite || value < min || value > max) {
        throw const FormatException('Invalid radio setting');
      }
      return (value * scale).round();
    }

    int toggle(String key, int old) => values[key] == null
        ? old
        : switch (values[key]) {
            'true' => 1,
            'false' => 0,
            _ => throw const FormatException('Expected on or off'),
          };

    var policy = self[45];
    var acks = self[44];
    var telemetry = self[46];
    switch (section) {
      case RadioFieldSection.position:
        final data = ByteData.sublistView(self);
        final lat = decimal(
          'latitude',
          data.getInt32(36, Endian.little),
          1000000,
          -90,
          90,
        );
        final lon = decimal(
          'longitude',
          data.getInt32(40, Endian.little),
          1000000,
          -180,
          180,
        );
        if (values.containsKey('latitude') || values.containsKey('longitude')) {
          final frame = ByteData(9)
            ..setUint8(0, 14)
            ..setInt32(1, lat, Endian.little)
            ..setInt32(5, lon, Endian.little);
          commands.add(frame.buffer.asUint8List());
        }
        policy = toggle('advertPosition', policy);
      case RadioFieldSection.routing:
        acks = number('acks', acks, 0, 2);
        if (values.containsKey('repeat')) {
          commands.add([11, ...self.sublist(48, 58), toggle('repeat', 0)]);
        }
        if (values.containsKey('path')) {
          commands.add([61, 0, number('path', 0, 0, 2)]);
        }
        if (values.containsKey('scopeName') || values.containsKey('scopeKey')) {
          final current = {for (final field in fields) field.id: field.value};
          commands.add(
            _scopeCommand(
              values['scopeName'] ?? current['scopeName']!,
              values['scopeKey'] ?? current['scopeKey']!,
            ),
          );
        }
        if (values.containsKey('rxDelay') || values.containsKey('airtime')) {
          final current = await _command([43], {23});
          if (current[0] != 23 || current.length < 9) {
            throw StateError('Radio tuning unavailable');
          }
          final frame = ByteData(9)
            ..setUint8(0, 21)
            ..setUint32(
              1,
              decimal('rxDelay', MeshCoreFrames.u32(current, 1), 1000, 0, 30),
              Endian.little,
            )
            ..setUint32(
              5,
              decimal(
                'airtime',
                MeshCoreFrames.u32(current, 5),
                1000,
                0.05,
                30,
              ),
              Endian.little,
            );
          commands.add(frame.buffer.asUint8List());
        }
      case RadioFieldSection.sensors:
        for (final (name, shift) in const [
          ('base', 0),
          ('position', 2),
          ('environment', 4),
        ]) {
          telemetry =
              (telemetry & ~(3 << shift)) |
              (number(name, (telemetry >> shift) & 3, 0, 2) << shift);
        }
      default:
        throw const FormatException('Unsupported radio section');
    }
    if (policy != self[45] || telemetry != self[46] || acks != self[44]) {
      commands.add([38, self[47], telemetry, policy, acks]);
    }
    for (final command in commands) {
      await _requireOk(command);
    }
    await _writeCliSettings(cli);
    for (final command in custom) {
      await _requireOk(command);
    }
  });

  Future<({int millivolts, int used, int total})?> _batteryAndStorage() async {
    final battery = await _command([20], {12});
    if (battery[0] != 12 || battery.length < 3) return null;
    return (
      millivolts: ByteData.sublistView(battery).getUint16(1, Endian.little),
      used: battery.length >= 11 ? MeshCoreFrames.u32(battery, 3) : 0,
      total: battery.length >= 11 ? MeshCoreFrames.u32(battery, 7) : 0,
    );
  }

  @override
  Future<RadioBattery?> readBattery() => _serial(() async {
    final millivolts = (await _batteryAndStorage())?.millivolts;
    if (millivolts == null || millivolts < 2800 || millivolts > 4350) {
      _lastBatterySample = null;
      _batteryCharging = false;
      return null;
    }
    // Companion reports voltage only. A jump to full voltage can indicate
    // external power on a single Li-ion cell.
    final previous = _lastBatterySample;
    final now = _batteryClock.elapsed;
    final jumpedToFull =
        previous != null &&
        now - previous.time <= const Duration(seconds: 65) &&
        millivolts >= 4200 &&
        millivolts - previous.millivolts >= 150;
    _batteryCharging = jumpedToFull || (_batteryCharging && millivolts >= 4100);
    _lastBatterySample = (millivolts: millivolts, time: now);
    return (
      percent: ((millivolts - 3000) / 12).round().clamp(0, 100),
      powered: _batteryCharging,
      estimated: true,
    );
  });

  @override
  Future<List<RadioField>> readTelemetry() => _serial(() async {
    final sample = await _batteryAndStorage();
    if (sample == null) return [];
    final (:millivolts, :used, :total) = sample;
    return [
      if (millivolts > 0)
        RadioField(
          'battery',
          'Battery voltage',
          'Напряжение батареи',
          (millivolts / 1000).toStringAsFixed(2),
          editable: false,
          units: 'V',
          section: RadioFieldSection.telemetry,
        ),
      if (total > 0)
        RadioField(
          'storage',
          'Radio storage',
          'Память рации',
          '$used / $total',
          editable: false,
          units: 'KB',
          section: RadioFieldSection.telemetry,
        ),
    ];
  });

  @override
  Future<void> writeSettings(Map<String, String> values) => _serial(() async {
    final self = await _selfInfo();
    if (self[0] != 5 || self.length < 58) {
      throw StateError('Missing radio settings');
    }
    final name = values['name']?.trim();
    final power = values['power'];
    final radio = values.keys.any(
      (key) => const {'frequency', 'bandwidth', 'sf', 'cr'}.contains(key),
    );
    final commands = <List<int>>[];
    if (name != null) {
      final bytes = utf8.encode(name);
      if (bytes.isEmpty || bytes.length > 31 || bytes.contains(0)) {
        throw const FormatException('Invalid node name');
      }
      commands.add([8, ...bytes]);
    }
    if (power != null) {
      commands.add([12, _bounded(power, -9, self[3]).toUnsigned(8)]);
    }
    if (radio) {
      final device = await _deviceInfo();
      if (device[0] != 13 ||
          device.length < 2 ||
          (device[1] >= 9 && device.length < 81)) {
        throw StateError('Could not preserve the radio repeater setting');
      }
      int decimal(String key, int offset, int min, int max) {
        final value = values[key];
        if (value == null) return MeshCoreFrames.u32(self, offset);
        final parsed = double.tryParse(value.replaceAll(',', '.'));
        if (parsed == null ||
            !parsed.isFinite ||
            parsed * 1000 < min ||
            parsed * 1000 > max) {
          throw const FormatException('Invalid LoRa parameter');
        }
        return (parsed * 1000).round();
      }

      final frequency = decimal('frequency', 48, 150000, 2500000);
      final bandwidth = decimal('bandwidth', 52, 7000, 500000);
      final settings = ByteData(11)
        ..setUint8(0, 11)
        ..setUint32(1, frequency, Endian.little)
        ..setUint32(5, bandwidth, Endian.little)
        ..setUint8(
          9,
          values['sf'] == null ? self[56] : _bounded(values['sf']!, 5, 12),
        )
        ..setUint8(
          10,
          values['cr'] == null ? self[57] : _bounded(values['cr']!, 5, 8),
        );
      commands.add([
        ...settings.buffer.asUint8List(),
        if (device[1] >= 9) device[80],
      ]);
    }
    for (final command in commands) {
      final reply = await _command(command, {0});
      if (reply[0] != 0) throw StateError('MeshCore rejected a setting');
    }
  });

  int _bounded(String input, int min, int max) {
    final value = int.tryParse(input);
    if (value == null || value < min || value > max) {
      throw const FormatException('Invalid radio parameter');
    }
    return value;
  }

  @override
  Future<void> start() async {
    _disconnect = link.disconnected.listen((_) => _emit(const RadioEnded()));
    _notices = await link.subscribe(_tx, _onFrame);
    await _serial(() async {
      final info = await _selfInfo();
      if (info[0] != 5) throw StateError('MeshCore identification failed');
      if (info.length >= 58) {
        final key = info.sublist(4, 36);
        if (key.any((byte) => byte != 0)) _publicKey = MeshCoreFrames.hex(key);
        _name = MeshCoreFrames.text(info.sublist(58));
        _factoryName = MeshCoreFrames.hex(info.sublist(4, 8));
      }
      try {
        _rememberDevice(await _deviceInfo());
      } on TimeoutException {
        // Older radios can identify without a device-query response.
      }
      try {
        await _contacts();
      } on TimeoutException {
        // A large directory can be interrupted without losing the BLE link.
      } on StateError {
        if (_closed) rethrow;
      }
      for (var index = 0; index < _channelSlots; index++) {
        final Uint8List packet;
        try {
          packet = await _command([31, index], {18});
        } on TimeoutException {
          break;
        }
        if (packet[0] != 18 || packet.length < 34 || packet[1] != index) {
          continue;
        }
        final name = MeshCoreFrames.text(packet.sublist(2, 34));
        if (name.isEmpty) continue;
        if (packet.length >= 50) _channelKeys[index] = packet.sublist(34, 50);
        final id = 'ch:$index';
        _directory[id] = (id: id, name: name, writable: true, channel: true);
      }
      _ready = true;
      _publish();
    });
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _requestInbox());
    _requestInbox();
  }

  @override
  Future<List<RadioSetupStep>> setupSteps() async {
    if (_name.isNotEmpty &&
        _name.toUpperCase() != 'NONAME' &&
        _name.toLowerCase() != _factoryName) {
      return [];
    }
    final fields = await readSettings();
    return [
      (
        title: 'Name your radio',
        russian: 'Назовите рацию',
        fields: const [RadioField('name', 'Node name', 'Имя узла', '')],
      ),
      (
        title: 'Set up LoRa',
        russian: 'Проверьте параметры LoRa',
        fields: fields
            .where((field) => field.section == RadioFieldSection.lora)
            .toList(),
      ),
    ];
  }

  @override
  List<ChannelAction> get channelActions => [
    ChannelAction.createPrivate,
    ChannelAction.joinPrivate,
    ChannelAction.publicChannel,
    ChannelAction.hashtag,
    ChannelAction.invitation,
  ];

  @override
  Future<ChannelProvision> addChannel(ChannelRequest request) =>
      _serial(() async {
        var name = request.name.trim();
        final List<int> secret;
        switch (request.action) {
          case ChannelAction.createPrivate:
            secret = createChannelKey(16);
          case ChannelAction.joinPrivate:
            secret = parseChannelKey(request.secret, {16});
          case ChannelAction.publicChannel:
            name = 'Public';
            secret = parseChannelKey('8b3387e9c5cdea6ac9e5edbaa115cd72', {16});
          case ChannelAction.hashtag:
            if (!name.startsWith('#')) name = '#$name';
            if (name.length <= 1 || RegExp(r'\s').hasMatch(name)) {
              throw const FormatException('channel-name');
            }
            secret = sha256.convert(utf8.encode(name)).bytes.sublist(0, 16);
          case ChannelAction.invitation:
            final uri = Uri.tryParse(request.invitation.trim());
            if (uri == null ||
                uri.scheme != 'meshcore' ||
                uri.host != 'channel' ||
                uri.path != '/add') {
              throw const FormatException('channel-invite');
            }
            if (uri.queryParameters['region_scope']?.isNotEmpty == true) {
              throw const FormatException('channel-scope');
            }
            name = uri.queryParameters['name']?.trim() ?? '';
            secret = parseChannelKey(uri.queryParameters['secret'] ?? '', {16});
        }
        if (request.action == ChannelAction.createPrivate ||
            request.action == ChannelAction.joinPrivate) {
          if (name.startsWith('#') || name.toLowerCase() == 'public') {
            throw const FormatException('channel-name');
          }
        }
        final nameBytes = channelNameBytes(name, 31);
        int? free;
        for (var slot = 0; slot < _channelSlots; slot++) {
          final frame = await _command([31, slot], {18});
          if (frame[0] != 18 || frame.length < 50 || frame[1] != slot) continue;
          final foundName = MeshCoreFrames.text(frame.sublist(2, 34));
          if (foundName == name) {
            if (!sameChannelKey(secret, frame.sublist(34, 50))) {
              throw StateError('channel-duplicate');
            }
            _channelKeys[slot] = frame.sublist(34, 50);
            return (peer: _putChannel(slot, name), invitation: null);
          }
          if (foundName.isEmpty) free ??= slot;
        }
        if (free == null) throw StateError('channel-full');
        final result = await _command(
          [
            32,
            free,
            ...nameBytes,
            ...List.filled(32 - nameBytes.length, 0),
            ...secret,
          ],
          {0},
        );
        if (result[0] != 0) throw StateError('channel-write');
        _channelKeys[free] = Uint8List.fromList(secret);
        final peer = _putChannel(free, name);
        final invitation = request.action == ChannelAction.createPrivate
            ? Uri(
                scheme: 'meshcore',
                host: 'channel',
                path: '/add',
                queryParameters: {
                  'name': name,
                  'secret': MeshCoreFrames.hex(secret),
                },
              ).toString()
            : null;
        return (peer: peer, invitation: invitation);
      });

  Peer _putChannel(int slot, String name) {
    final id = 'ch:$slot';
    final peer = (id: id, name: name, writable: true, channel: true);
    _directory[id] = peer;
    _publish();
    return peer;
  }

  @override
  Future<Peer> importContact(ContactAttachment contact) => _serial(() async {
    if (!_ready || _closed || contact.network != 'meshcore') {
      throw StateError('contact-import-unavailable');
    }
    final type = contact.type;
    final publicKey = contact.publicKey;
    if (!validContactKey(publicKey) ||
        type == null ||
        type < 1 ||
        type > 4 ||
        publicKey == _publicKey ||
        contact.id != 'node:${publicKey.substring(0, 12)}') {
      throw const FormatException('Invalid MeshCore contact');
    }
    final existing = _identities[contact.id];
    if (existing != null) {
      if (existing.publicKey != publicKey) {
        throw StateError('contact-key-conflict');
      }
      return _directory[contact.id]!;
    }
    final key = _keyBytes(publicKey);
    final name = utf8.encode(fitContactName(contact.name, 31));
    await _expectNodeCommand([
      9,
      ...key,
      type,
      0, // Flags.
      0xff, // Unknown route, flood discovery on first send.
      ...List.filled(64, 0),
      ...name,
      ...List.filled(32 - name.length, 0),
      ...List.filled(8, 0), // No advertisement timestamp or shared position.
    ]);
    final stored = await _command([30, ...key], {3});
    if (stored.length < 132 ||
        MeshCoreFrames.hex(stored.sublist(1, 33)) != publicKey) {
      throw StateError('contact-import-unconfirmed');
    }
    return _directory[contact.id]!;
  });

  @override
  bool canRemovePeer(Peer peer) =>
      _ready &&
      !_closed &&
      _directory.containsKey(peer.id) &&
      (peer.channel ? peer.id != 'ch:0' : _identities.containsKey(peer.id));

  @override
  Future<void> removePeer(Peer peer) => _serial(() async {
    if (!canRemovePeer(peer)) throw StateError('peer-remove-unavailable');
    if (peer.channel) {
      final slot = int.parse(peer.id.substring(3));
      await _expectNodeCommand([32, slot, ...List.filled(48, 0)]);
      final readback = await _command([31, slot], {18});
      if (readback[0] != 18 ||
          readback.length < 34 ||
          readback[1] != slot ||
          MeshCoreFrames.text(readback.sublist(2, 34)).isNotEmpty) {
        throw StateError('channel-write');
      }
      _channelKeys.remove(slot);
    } else {
      await _expectNodeCommand([
        15,
        ..._keyBytes(_identities[peer.id]!.publicKey),
      ]);
      _identities.remove(peer.id);
    }
    _directory.remove(peer.id);
    _publish();
  });

  @override
  bool canShareChannel(Peer peer) =>
      _ready &&
      !_closed &&
      peer.channel &&
      _channelKeys[int.tryParse(peer.id.substring(3))]?.length == 16;

  @override
  Future<String> shareChannel(Peer peer) async {
    if (!canShareChannel(peer)) throw StateError('channel-share-unavailable');
    final slot = int.parse(peer.id.substring(3));
    return Uri(
      scheme: 'meshcore',
      host: 'channel',
      path: '/add',
      queryParameters: {
        'name': _directory[peer.id]!.name,
        'secret': MeshCoreFrames.hex(_channelKeys[slot]!),
      },
    ).toString();
  }

  @override
  Future<void> setFixedPosition(NodePosition position) => writeSettings({
    'latitude': position.latitude.toStringAsFixed(6),
    'longitude': position.longitude.toStringAsFixed(6),
  });

  Future<void> _contacts() async {
    final result = await _command([4], {4}, seconds: 24);
    if (result[0] != 4) throw StateError('MeshCore contacts unavailable');
  }

  void _publish() => _emit(
    DirectoryUpdate(
      _directory.values.toList(),
      name: _name,
      identities: Map.of(_identities),
      radioPublicKey: _publicKey,
      deviceInfo: _deviceMetadata,
    ),
  );

  void _onFrame(Uint8List bytes) {
    if (_closed || bytes.isEmpty) return;
    final type = bytes[0];
    if (type == 0x8d) {
      try {
        _receiveRouteDiscovery(bytes);
      } on FormatException {
        return;
      }
    }
    if (type == 0x89 && bytes.length >= 13) {
      final request = MeshCoreFrames.u32(bytes, 4);
      if (_routeProbes[request]?.call(bytes) == true) {
        _routeProbes.remove(request);
      }
    }
    if (_binaryReply case final reply? when !reply.isCompleted) {
      if (type == 6 && bytes.length >= 10) {
        _binaryTag = MeshCoreFrames.u32(bytes, 2);
      } else if (type == 0x8c &&
          bytes.length >= 6 &&
          MeshCoreFrames.u32(bytes, 2) == _binaryTag) {
        reply.complete(bytes.sublist(6));
      }
    }
    if (_adminPush case final pending?
        when pending.responses.contains(type) &&
            bytes.length >= 8 &&
            'node:${MeshCoreFrames.hex(bytes.sublist(2, 8))}' == pending.id &&
            !pending.result.isCompleted) {
      pending.result.complete(bytes);
      _emit(
        NodeObserved(pending.id, NodeObservation(lastSeen: DateTime.now())),
      );
    }
    if (type == 3 || type == 0x8a) {
      final peer = MeshCoreFrames.contact(bytes);
      if (peer != null) {
        _directory[peer.id] = peer;
        _identities[peer.id] = (
          publicKey: MeshCoreFrames.hex(bytes.sublist(1, 33)),
          type: bytes[33],
          shortName: null,
        );
        final seen = type == 0x8a
            ? DateTime.now()
            : bytes.length >= 136
            ? nodeTimeFromSeconds(MeshCoreFrames.u32(bytes, 132))
            : null;
        final data = ByteData.sublistView(bytes);
        _emit(
          NodeObserved(
            peer.id,
            NodeObservation(
              lastSeen: seen,
              favorite: bytes[34] & 1 != 0,
              canMessage: bytes[33] == 1,
              role: switch (bytes[33]) {
                1 => MeshNodeRole.client,
                2 => MeshNodeRole.repeater,
                3 => MeshNodeRole.room,
                4 => MeshNodeRole.sensor,
                _ => null,
              },
              position: bytes.length < 144
                  ? null
                  : nodePosition(
                      data.getInt32(136, Endian.little) / 1e6,
                      data.getInt32(140, Endian.little) / 1e6,
                    ),
            ),
          ),
        );
        if (_ready) _publish();
      }
    }
    if (type == 0x82 && bytes.length >= 5) {
      final id = _acks.remove(MeshCoreFrames.u32(bytes, 1));
      if (id != null) {
        _emit(
          DeliveryUpdate(
            id,
            Delivery.acknowledged,
            packet: bytes.length < 9
                ? null
                : MessagePacket(roundTripMs: MeshCoreFrames.u32(bytes, 5)),
          ),
        );
      }
    }
    if (type == 0x88 && _groupEchoes.isNotEmpty) {
      final group = MeshCoreFrames.relayedGroup(bytes);
      final id = group == null ? null : _groupEchoes.remove(group.payload);
      if (id != null) {
        _emit(
          DeliveryUpdate(
            id,
            Delivery.acknowledged,
            packet: MessagePacket(hops: group!.hops),
          ),
        );
      }
    }
    if (type == 0x83) _requestInbox();
    if (type == 0x80 && _ready && bytes.length >= 33) {
      final id = 'node:${MeshCoreFrames.hex(bytes.sublist(1, 7))}';
      _emit(NodeObserved(id, NodeObservation(lastSeen: DateTime.now())));
      if (!_directory.containsKey(id)) {
        unawaited(_serial(_contacts).catchError((Object _) {}));
      }
    }
    if (MeshCoreFrames.messageEvent(bytes, _directory) case final event?) {
      _emit(event);
    }
    final response = _response;
    if (response != null &&
        !response.isCompleted &&
        (type == 1 || type == 15 || _expected.contains(type))) {
      response.complete(bytes);
    }
  }

  @override
  Set<NodeAction> nodeActions(Peer peer) {
    final type = _identities[peer.id]?.type;
    if (!_ready ||
        _closed ||
        peer.channel ||
        type == null ||
        type < 1 ||
        type > 4) {
      return const {};
    }
    return {
      NodeAction.trace,
      NodeAction.savedPath,
      NodeAction.resetPath,
      NodeAction.favorite,
      if (type == 1 || type == 4) ...{
        NodeAction.position,
        NodeAction.telemetry,
      },
      if (type == 4) NodeAction.sensorLogin,
    };
  }

  @override
  Future<List<RadioField>> runNodeAction(
    Peer peer,
    NodeAction action, {
    bool enabled = true,
    String? password,
  }) => _serial(() async {
    if (!nodeActions(peer).contains(action)) {
      throw StateError('Node action unavailable');
    }
    final identity = _identities[peer.id]!;
    final key = _keyBytes(identity.publicKey);
    switch (action) {
      case NodeAction.savedPath:
      case NodeAction.favorite:
        final contact = await _command([30, ...key], {3});
        if (contact.length < 148 ||
            MeshCoreFrames.hex(contact.sublist(1, 33)) != identity.publicKey) {
          throw StateError('Could not read this contact');
        }
        if (action == NodeAction.savedPath) {
          final (route, _) = _path(contact, 35);
          return [
            RadioField(
              'route',
              'Saved path',
              'Сохранённый маршрут',
              route,
              editable: false,
            ),
          ];
        }
        final flags = contact[34];
        final updated = Uint8List.fromList(contact)
          ..[0] = 9
          ..[34] = enabled ? (flags | 1) : (flags & 0xfe);
        ByteData.sublistView(updated).setUint32(
          144,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          Endian.little,
        );
        await _expectNodeCommand(updated);
        _emit(NodeObserved(peer.id, NodeObservation(favorite: enabled)));
        return const [];
      case NodeAction.resetPath:
        await _expectNodeCommand([13, ...key]);
        return const [];
      case NodeAction.position:
      case NodeAction.telemetry:
        final Uint8List data;
        if (identity.type == 4) {
          data = await _requestBinary([50, ...key, 3, 0, 0, 0, 0]);
          _emit(
            NodeObserved(peer.id, NodeObservation(lastSeen: DateTime.now())),
          );
        } else {
          final reply = await _requestAdmin(
            peer.id,
            [39, 0, 0, 0, ...key],
            {0x8b},
          );
          data = reply.sublist(8);
        }
        final (metrics, position) = _nodeTelemetry(data);
        if (position != null) {
          _emit(
            NodeObserved(
              peer.id,
              NodeObservation(lastSeen: DateTime.now(), position: position),
            ),
          );
        }
        if (action == NodeAction.position) {
          if (position == null) throw const FormatException('No position');
          return nodePositionFields(position);
        }
        if (metrics.isEmpty) throw const FormatException('No telemetry');
        return metrics;
      case NodeAction.sensorLogin:
        final encoded = utf8.encode(password ?? '');
        if (encoded.isEmpty || encoded.length > 64 || encoded.contains(0)) {
          throw const FormatException('Invalid password');
        }
        final response = await _requestAdmin(
          peer.id,
          [26, ...key, ...encoded],
          {0x85, 0x86},
        );
        if (response[0] != 0x85) throw StateError('Sensor rejected login');
        return const [];
      default:
        throw StateError('Node action unavailable');
    }
  });

  Future<void> _expectNodeCommand(List<int> bytes) async {
    if ((await _command(bytes, {0})).first != 0) {
      throw StateError('Radio rejected contact change');
    }
  }

  Future<Uint8List> _requestBinary(List<int> command) async {
    final reply = _binaryReply = Completer<Uint8List>();
    unawaited(reply.future.then<void>((_) {}, onError: (Object _) {}));
    try {
      final sent = await _command(command, {6});
      return await reply.future.timeout(_radioTimeout(sent));
    } finally {
      _binaryReply = null;
      _binaryTag = null;
    }
  }

  @override
  Duration get routeTraceInterval => Duration.zero;

  @override
  DateTime? get routeTracePendingUntil => _routeDiscovery?.until;

  @override
  Future<void> startRouteTrace(Peer peer, int request) => _serial(() async {
    if (!nodeActions(peer).contains(NodeAction.trace) ||
        routeTracePendingUntil?.isAfter(DateTime.now()) == true) {
      throw StateError('Route discovery unavailable');
    }
    final key = _keyBytes(_identities[peer.id]!.publicKey);
    final previous = _routeDiscovery;
    final discovery = (peer: peer, request: request, until: DateTime.now());
    _routeDiscovery = discovery;
    try {
      final sent = await _command([52, 0, ...key], {6});
      final estimate = _radioTimeout(sent);
      // Sending another discovery replaces the one pending on the firmware.
      final wait = estimate < routeTraceNoticeDelay
          ? routeTraceNoticeDelay
          : estimate;
      if (_routeDiscovery == discovery) {
        _routeDiscovery = (
          peer: peer,
          request: request,
          until: DateTime.now().add(wait),
        );
      }
    } catch (_) {
      if (_routeDiscovery == discovery) _routeDiscovery = previous;
      rethrow;
    }
  });

  void _receiveRouteDiscovery(Uint8List frame) {
    final discovery = _routeDiscovery;
    if (discovery == null ||
        frame.length < 10 ||
        'node:${MeshCoreFrames.hex(frame.sublist(2, 8))}' !=
            discovery.peer.id) {
      return;
    }
    final (outbound, reverseOffset) = _path(frame, 8);
    final (inbound, _) = _path(frame, reverseOffset);
    _routeDiscovery = null;
    final peer = discovery.peer;
    final request = discovery.request;
    final identity = _identities[peer.id];
    void report([
      List<RadioHop> forward = const [],
      List<RadioHop> reverse = const [],
    ]) {
      _emit(
        RouteTraceReceived(peer.id, request, [
          RadioField(
            'route',
            'To node',
            'До узла',
            outbound,
            hops: forward,
            editable: false,
          ),
          RadioField(
            'return',
            'Return path',
            'Обратный путь',
            inbound,
            hops: reverse,
            editable: false,
          ),
        ]),
      );
    }

    report();
    _emit(NodeObserved(peer.id, NodeObservation(lastSeen: DateTime.now())));
    if (identity?.type == 2 && _protocol >= 10) {
      unawaited(
        _serial(
          () => _startRouteProbe(
            peer,
            request,
            _keyBytes(identity!.publicKey),
            frame,
            reverseOffset,
            report,
          ),
        ).catchError((Object _) {}),
      );
    }
  }

  Future<void> _startRouteProbe(
    Peer peer,
    int request,
    List<int> key,
    Uint8List discovered,
    int reverseOffset,
    void Function(List<RadioHop>, List<RadioHop>) report,
  ) async {
    final outward = discovered[8], back = discovered[reverseOffset];
    if (outward == 255 || back == 255) return;
    final outCount = outward & 63, backCount = back & 63;
    final outWidth = (outward >> 6) + 1, backWidth = (back >> 6) + 1;
    final width = outCount == 0 ? backWidth : outWidth;
    if (width > 2 || (backCount > 0 && backWidth != width)) return;
    final hashes = [
      ...discovered.sublist(9, reverseOffset),
      ...key.take(width),
      ...discovered.sublist(
        reverseOffset + 1,
        reverseOffset + 1 + backCount * width,
      ),
    ];
    final count = outCount + 1 + backCount;
    if (count > 64) return;
    final pathHash = MeshCoreFrames.hex(hashes);

    // Tags let a late probe add signal readings without delaying other commands.
    if (_routeProbes.length >= 128) {
      _routeProbes.remove(_routeProbes.keys.first);
    }
    _routeProbes[request] = (trace) {
      if (trace[2] != hashes.length ||
          trace[3] != width - 1 ||
          trace.length != 12 + hashes.length + count + 1 ||
          MeshCoreFrames.hex(trace.sublist(12, 12 + hashes.length)) !=
              pathHash) {
        return false;
      }
      RadioHop hop(String name, int i) => (
        name: name,
        snr: trace[12 + hashes.length + i].toSigned(8) / 4,
        rssi: null,
      );
      String nameFor(int index) {
        final hash = MeshCoreFrames.hex(
          hashes.sublist(index * width, (index + 1) * width),
        );
        final peers = _identities.entries.where(
          (entry) => entry.value.publicKey.startsWith(hash),
        );
        return peers.length == 1
            ? _directory[peers.single.key]?.name ?? hash.toUpperCase()
            : hash.toUpperCase();
      }

      report(
        [
          for (var i = 0; i < outCount; i++) hop(nameFor(i), i),
          hop(peer.name, outCount),
        ],
        [
          for (var i = outCount + 1; i < count; i++) hop(nameFor(i), i),
          hop(_name.isEmpty ? 'Local radio' : _name, count),
        ],
      );
      return true;
    };

    try {
      final sent = await _command(
        [
          36,
          ...MeshCoreFrames.littleEndian32(request),
          0,
          0,
          0,
          0,
          width - 1,
          ...hashes,
        ],
        {6},
      );
      if (sent[0] != 6) _routeProbes.remove(request);
    } catch (_) {
      _routeProbes.remove(request);
    }
  }

  (String, int) _path(Uint8List frame, int offset) {
    if (offset >= frame.length) throw const FormatException('Missing path');
    final encoded = frame[offset];
    if (encoded == 255) return ('Flood', offset + 1);
    final width = (encoded >> 6) + 1;
    final length = (encoded & 63) * width;
    if (length > 64 || offset + 1 + length > frame.length) {
      throw const FormatException('Invalid path');
    }
    final path = [
      for (var pos = offset + 1; pos < offset + 1 + length; pos += width)
        MeshCoreFrames.hex(frame.sublist(pos, pos + width)).toUpperCase(),
    ];
    return (path.isEmpty ? '0' : path.join(' → '), offset + 1 + length);
  }

  (List<RadioField>, NodePosition?) _nodeTelemetry(Uint8List bytes) {
    const sizes = {
      0: 1,
      1: 1,
      2: 2,
      3: 2,
      100: 4,
      101: 2,
      102: 1,
      103: 2,
      104: 1,
      113: 6,
      115: 2,
      116: 2,
      117: 2,
      118: 4,
      120: 1,
      121: 2,
      125: 2,
      128: 2,
      130: 4,
      131: 4,
      132: 2,
      133: 4,
      134: 6,
      135: 3,
      136: 9,
      142: 1,
    };
    final values = <RadioField>[];
    NodePosition? position;
    final data = ByteData.sublistView(bytes);
    for (var offset = 0; offset + 2 <= bytes.length;) {
      final channel = bytes[offset++];
      final type = bytes[offset++];
      if (channel == 0 && type == 0) break;
      final length = sizes[type];
      if (length == null || offset + length > bytes.length) break;
      final at = offset;
      offset += length;
      int coordinate(int index) =>
          ((bytes[index] << 16) | (bytes[index + 1] << 8) | bytes[index + 2])
              .toSigned(24);
      if (type == 136) {
        position =
            nodePosition(coordinate(at) / 1e4, coordinate(at + 3) / 1e4) ??
            position;
      }
      final reading = switch (type) {
        101 => ('Light', 'Освещённость', data.getUint16(at).toDouble(), 'lx'),
        103 => ('Temperature', 'Температура', data.getInt16(at) / 10, '°C'),
        104 => ('Humidity', 'Влажность', data.getUint8(at) / 2, '%'),
        115 => ('Pressure', 'Давление', data.getUint16(at) / 10, 'hPa'),
        116 => ('Voltage', 'Напряжение', data.getUint16(at) / 100, 'V'),
        117 => ('Current', 'Ток', data.getUint16(at) / 1000, 'A'),
        120 => ('Level', 'Уровень', data.getUint8(at).toDouble(), '%'),
        125 => (
          'Concentration',
          'Концентрация',
          data.getUint16(at).toDouble(),
          'ppm',
        ),
        _ => null,
      };
      if (reading != null) {
        final (en, ru, value, units) = reading;
        values.add(
          RadioField(
            '$type.$channel.$at',
            en,
            ru,
            value.toStringAsFixed(2),
            units: units,
            editable: false,
          ),
        );
      }
    }
    return (values, position);
  }

  @override
  bool get adminRequiresPassword => true;

  @override
  bool canAdminister(Peer peer) {
    final type = _identities[peer.id]?.type;
    return _ready && !_closed && !peer.channel && (type == 2 || type == 3);
  }

  @override
  Future<RadioSettingsSession> openAdmin(Peer peer, String password) =>
      _serial(() async {
        if (!canAdminister(peer)) throw StateError('Admin unavailable');
        final key = _identities[peer.id]!.publicKey;
        final passwordBytes = utf8.encode(password);
        if (passwordBytes.isEmpty ||
            passwordBytes.length > 15 ||
            passwordBytes.contains(0)) {
          throw const FormatException('MeshCore password must be 1–15 bytes');
        }
        await _syncAdminClock();
        final publicKey = _keyBytes(key);
        final request = [26, ...publicKey, ...passwordBytes, 0];
        var usedDirectPath = false;
        Uint8List result;
        try {
          result = await _requestAdmin(
            peer.id,
            request,
            {0x85, 0x86},
            onSent: (frame) {
              usedDirectPath = frame.length >= 2 && frame[1] == 0;
            },
          );
        } on TimeoutException {
          if (!usedDirectPath || _closed) rethrow;
          // A stale route is common after a repeater moves. Preserve it if
          // a fresh flood login fails or cannot be started.
          final saved = await _command([30, ...publicKey], {3});
          if (saved.length < 148 ||
              MeshCoreFrames.hex(saved.sublist(1, 33)) != key) {
            rethrow;
          }
          await _expectNodeCommand([13, ...publicKey]);
          var accepted = false;
          try {
            result = await _requestAdmin(peer.id, request, {0x85, 0x86});
            accepted = result[0] == 0x85;
          } finally {
            if (!accepted && !_closed) {
              await _expectNodeCommand([9, ...saved.skip(1)]);
            }
          }
        }
        if (result[0] != 0x85) throw const NodeAdminDenied();
        final aclAdmin = result.length > 12 && result[12] & 3 == 3;
        if (result[1] & 1 == 0 && !aclAdmin) {
          if (result.length > 8) throw const NodeAdminDenied(guest: true);
          // Older companions omit the permission flags in login replies.
          await _getRemoteName(peer, key);
        }
        return _CoreRemoteSettings(this, peer, key);
      });

  Future<void> _syncAdminClock() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final frame = await _command([5], {9});
    if (frame[0] != 9 || frame.length < 5) return;
    final radio = MeshCoreFrames.u32(frame, 1);
    if (radio < now - 5) {
      await _expectNodeCommand([6, ...MeshCoreFrames.littleEndian32(now)]);
    }
    if (radio > _cliTimestamp) _cliTimestamp = radio;
  }

  Future<void> _getRemoteName(Peer peer, String key) async {
    final response = await _cliForPeer(peer, key, 'get name');
    if (!response.startsWith('> ')) throw const NodeAdminDenied(guest: true);
  }

  List<int> _keyBytes(String key) => [
    for (var i = 0; i < key.length; i += 2)
      int.parse(key.substring(i, i + 2), radix: 16),
  ];

  Future<Uint8List> _requestAdmin(
    String peerId,
    List<int> request,
    Set<int> responses, {
    void Function(Uint8List)? onSent,
  }) async {
    final response = Completer<Uint8List>();
    _adminPush = (id: peerId, responses: responses, result: response);
    // A disconnect may finish the push while the immediate BLE response is pending.
    unawaited(response.future.then<void>((_) {}, onError: (Object _) {}));
    try {
      final sent = await _command(request, {6});
      onSent?.call(sent);
      return await response.future.timeout(_radioTimeout(sent));
    } finally {
      _adminPush = null;
    }
  }

  Duration _radioTimeout(Uint8List sent) {
    if (sent[0] != 6) throw StateError('MeshCore rejected the request');
    final estimate = sent.length >= 10 ? MeshCoreFrames.u32(sent, 6) : 0;
    return Duration(milliseconds: (estimate + 3000).clamp(8000, 90000));
  }

  Future<String> _cli(Peer peer, String key, String command) =>
      _serial(() => _cliForPeer(peer, key, command));

  Future<String> _cliForPeer(Peer peer, String key, String command) async {
    if (!canAdminister(peer) || _identities[peer.id]?.publicKey != key) {
      throw StateError('Admin contact changed');
    }
    final body = utf8.encode(command);
    if (body.isEmpty ||
        body.length > 130 ||
        command.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const FormatException('Invalid repeater command');
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _cliTimestamp = now > _cliTimestamp ? now : _cliTimestamp + 1;
    final sent = await _command(
      [
        2,
        1,
        0,
        ...MeshCoreFrames.littleEndian32(_cliTimestamp),
        ..._keyBytes(key.substring(0, 12)),
        ...body,
        0,
      ],
      {6},
    );
    final timer = Stopwatch()..start();
    final timeout = _radioTimeout(sent);
    // Commands such as reboot deliberately have no firmware response.
    if (const {'reboot', 'shutdown', 'poweroff'}.contains(command)) {
      return '';
    }
    while (timer.elapsed < timeout && !_closed) {
      final packet = await _command([10], {7, 8, 10, 16, 17, 27});
      final type = packet[0];
      if (type == 7 || type == 16) {
        final base = type == 7 ? 1 : 4;
        final cli = base + 7;
        if (packet.length > cli + 5 &&
            packet[cli] == 1 &&
            MeshCoreFrames.hex(packet.sublist(base, base + 6)) ==
                key.substring(0, 12)) {
          return MeshCoreFrames.text(packet.sublist(cli + 5));
        }
      }
      if (type == 10 || type == 1) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw TimeoutException('MeshCore command response unavailable');
  }

  Future<List<RadioField>> _remoteTelemetry(Peer peer, String key) =>
      _serial(() async {
        if (!canAdminister(peer) || _identities[peer.id]?.publicKey != key) {
          throw StateError('Admin contact changed');
        }
        final packet = await _requestAdmin(
          peer.id,
          [27, ..._keyBytes(key)],
          {0x87},
        );
        return MeshCoreFrames.repeaterStatus(packet);
      });

  void _requestInbox() {
    if (_closed || !_ready || _draining) return;
    _draining = true;
    unawaited(
      _serial(() async {
        for (var i = 0; i < 64 && !_closed; i++) {
          final packet = await _command([10], {7, 8, 10, 16, 17, 27});
          if (packet[0] == 10 || packet[0] == 1) return;
        }
      }).catchError((Object _) {}).whenComplete(() => _draining = false),
    );
  }

  @override
  int textLimit(Peer peer) => const MeshCoreAdapter().messageBytes(peer, _name);

  @override
  Future<void> react(Peer peer, String target, String emoji) => _send(
    peer,
    MeshMessage(
      id: '',
      chat: peer.id,
      author: '',
      text: meshCoreReactionText(target, emoji, channel: peer.channel),
      time: DateTime.now(),
      delivery: Delivery.queued,
    ),
    track: false,
  );

  @override
  Future<void> send(Peer peer, MeshMessage message) => _send(peer, message);

  Future<void> _send(Peer peer, MeshMessage message, {bool track = true}) =>
      _serial(() async {
        if (!peer.writable ||
            utf8.encode(message.text).length > textLimit(peer)) {
          throw StateError('MeshCore message cannot be sent');
        }
        String? echo;
        int? stamp;
        if (peer.channel) {
          final now = message.time.millisecondsSinceEpoch ~/ 1000;
          stamp = _lastGroupStamp = now > _lastGroupStamp
              ? now
              : _lastGroupStamp + 1;
          final key = _channelKeys[int.parse(peer.id.substring(3))];
          if (key != null && track) {
            echo = MeshCoreFrames.groupPayload(key, stamp, _name, message.text);
            _groupEchoes[echo] = message.id;
            if (_groupEchoes.length > 128) {
              _groupEchoes.remove(_groupEchoes.keys.first);
            }
          }
        }
        try {
          final response = await _command(
            MeshCoreFrames.send(peer, message, stamp: stamp),
            peer.channel ? {0, 6} : {6},
          );
          if (response[0] == 1) {
            throw StateError('MeshCore radio declined the message');
          }
          if (!track) return;
          if (!peer.channel && response.length >= 6) {
            _acks[MeshCoreFrames.u32(response, 2)] = message.id;
            if (_acks.length > 128) _acks.remove(_acks.keys.first);
          }
          final packet = MessagePacket(
            sender: _publicKey == null
                ? null
                : 'node:${_publicKey!.substring(0, 12)}',
            channel: peer.channel ? int.parse(peer.id.substring(3)) : null,
            recipient: peer.channel ? null : peer.id,
            route: peer.channel
                ? MessageRoute.flood
                : response.length < 2
                ? null
                : switch (response[1]) {
                    0 => MessageRoute.direct,
                    1 => MessageRoute.flood,
                    _ => null,
                  },
          );
          _emit(
            MessagePacketUpdated(
              message.id,
              packet,
              reference: meshCoreMessageReference(
                message.text,
                stamp ?? message.time.millisecondsSinceEpoch ~/ 1000,
                sender: peer.channel ? _name : null,
              ),
            ),
          );
        } catch (_) {
          if (echo != null) _groupEchoes.remove(echo);
          rethrow;
        }
      });

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _poll?.cancel();
    final response = _response;
    if (response != null && !response.isCompleted) {
      response.completeError(StateError('Radio disconnected'));
    }
    final admin = _adminPush?.result;
    if (admin != null && !admin.isCompleted) {
      admin.completeError(StateError('Radio disconnected'));
    }
    if (_binaryReply case final reply? when !reply.isCompleted) {
      reply.completeError(StateError('Radio disconnected'));
    }
    _routeDiscovery = null;
    _routeProbes.clear();
    await _disconnect?.cancel();
    await _notices?.cancel();
    await link.close();
    await _events.close();
  }
}

class _CoreRemoteSettings
    implements
        RadioSettingsSession,
        RadioTelemetrySession,
        RemoteAdminConsole,
        RemoteNeighborTable,
        RemoteNodePower {
  _CoreRemoteSettings(this.session, this.peer, this.key);

  final _CoreSession session;
  final Peer peer;
  final String key;

  @override
  bool get canReadNeighbors => session._identities[peer.id]?.type == 2;

  @override
  Future<String> readNeighbors() async {
    if (!canReadNeighbors) throw StateError('Neighbor table unavailable');
    return runCommand('neighbors');
  }

  @override
  Future<void> setPower({required bool reboot}) async {
    await runCommand(reboot ? 'reboot' : 'shutdown');
  }

  @override
  Future<String> runCommand(String command) => session._cli(peer, key, command);

  @override
  Future<List<RadioField>> readTelemetry() =>
      session._remoteTelemetry(peer, key);

  Future<String> _get(String setting) async {
    final reply = await runCommand('get $setting');
    if (!reply.startsWith('> ')) {
      throw StateError('MeshCore setting unavailable');
    }
    return reply.substring(2).trim();
  }

  @override
  Future<List<RadioField>> readSettings() async {
    final name = await _get('name');
    final forwarding = await _get('repeat');
    final radio = await _get('radio');
    return [
      RadioField('name', 'Node name', 'Имя узла', name),
      RadioField(
        'repeat',
        'Forward packets',
        'Пересылать пакеты',
        '${forwarding == 'on'}',
        kind: RadioFieldKind.toggle,
      ),
      RadioField(
        'radio',
        'LoRa parameters',
        'Параметры LoRa',
        radio,
        editable: false,
        section: RadioFieldSection.lora,
      ),
    ];
  }

  @override
  Future<void> writeSettings(Map<String, String> values) async {
    for (final entry in values.entries) {
      final value = switch (entry.key) {
        'repeat' when entry.value == 'true' => 'on',
        'repeat' when entry.value == 'false' => 'off',
        'name'
            when entry.value.trim().isNotEmpty &&
                utf8.encode(entry.value.trim()).length <= 31 =>
          entry.value.trim(),
        _ => throw const FormatException('Invalid MeshCore setting'),
      };
      final result = await runCommand('set ${entry.key} $value');
      if (!result.toLowerCase().startsWith('ok') ||
          await _get(entry.key) != value) {
        throw StateError('MeshCore did not confirm the setting');
      }
    }
  }
}
