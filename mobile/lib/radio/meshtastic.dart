// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:protobuf/protobuf.dart';

import '../mesh/contact_attachment.dart';
import '../mesh/message_packet.dart';
import '../mesh/network.dart';
import '../mesh/nodes.dart';
import '../mesh/radio_settings_index.dart';
import 'channel_invitation.dart';
import 'channel_keys.dart';

part 'meshtastic_settings.dart';

class MeshtasticAdapter
    implements
        NetworkAdapter,
        NetworkLanAdapter,
        NetworkBufferedMessages,
        NetworkMessageBudget,
        NetworkMessageReferences,
        NetworkContactCodes,
        NetworkNodeSorting {
  const MeshtasticAdapter();
  @override
  String get id => 'meshtastic';
  @override
  String get label => 'Meshtastic';
  @override
  List<NodeSort> get additionalNodeSorts => const [
    NodeSort.distance,
    NodeSort.hops,
    NodeSort.channel,
    NodeSort.mqtt,
    NodeSort.favorite,
  ];
  @override
  String get service => '6ba1b218-15a8-461f-9fa8-5dcae273eafd';
  @override
  LanRadioProtocol get lan => const LanRadioProtocol(
    port: 4403,
    inputPrefix: [0x94, 0xc3],
    outputPrefix: [0x94, 0xc3],
    endian: Endian.big,
    maxPayload: 512,
    rx: _TasticSession._tx,
    tx: _TasticSession._rx,
    notice: _TasticSession._notice,
    bonjourService: '_meshtastic._tcp',
    wake: [0x94, 0x94, 0x94, 0x94],
    heartbeat: [0x3a, 0x02, 0x08, 0x01],
  );
  @override
  NetworkSession createSession(RadioLink link) => _TasticSession(link);
  @override
  NetworkEvent? bufferedMessage(
    Uint8List frame,
    Map<String, Peer> peers,
    int? localNode,
    DateTime receivedAt,
  ) {
    if (localNode == null) return null;
    try {
      return _tasticMessageEvent(
        _protobuf(frame).message(2),
        peers,
        localNode,
        receivedAt,
      );
    } on FormatException {
      return null;
    } on InvalidProtocolBufferException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  String? referenceFor(MeshMessage message) {
    if (message.remoteId != null) return message.remoteId;
    // Earlier releases stored the peer and Meshtastic packet ID only in this key.
    final parts = message.id.split(':');
    if (parts.length != 4 || parts.first != 'mt') return null;
    final packet = int.tryParse(parts.last);
    return packet != null && packet > 0 ? '$packet' : null;
  }

  @override
  Uri? contactCode(Peer peer, NodeIdentity identity) {
    final number = int.tryParse(peer.id.split(':').last);
    final key = identity.publicKey;
    if (number == null ||
        number <= 0 ||
        number >= meshBroadcast ||
        !validContactKey(key)) {
      return null;
    }
    final contact = _sharedContact(number, peer.name, identity.shortName, key);
    return Uri.https(
      'meshtastic.org',
      '/v/',
    ).replace(fragment: base64Url.encode(contact).replaceAll('=', ''));
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
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    final web =
        uri.scheme == 'https' &&
        (uri.host == 'meshtastic.org' || uri.host == 'www.meshtastic.org') &&
        segments.length == 1 &&
        segments.first == 'v';
    final app =
        uri.scheme == 'meshtastic' &&
        ((uri.host == 'v' && segments.isEmpty) ||
            (uri.host.isEmpty &&
                segments.length == 1 &&
                segments.first == 'v'));
    if ((!web && !app) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.fragment.isEmpty) {
      return null;
    }
    try {
      final contact = _protobuf(
        base64Url.decode(base64Url.normalize(uri.fragment)),
      );
      final number = contact.number(1);
      final user = contact.message(2);
      final key = user.bytes(8);
      if (number <= 0 ||
          number >= meshBroadcast ||
          user.string(1).toLowerCase() != _nodeLabel(number) ||
          key.length != 32 ||
          key.every((byte) => byte == 0)) {
        return null;
      }
      final name = fitContactName(user.string(2), 39);
      final shortName = fitContactName(user.string(3), 4);
      return (
        network: id,
        id: 'node:$number',
        name: name.isNotEmpty
            ? name
            : shortName.isNotEmpty
            ? shortName
            : _nodeLabel(number),
        publicKey: _hexKey(key),
        type: null,
        shortName: shortName.isNotEmpty ? shortName : null,
      );
    } on FormatException {
      return null;
    } on InvalidProtocolBufferException {
      return null;
    } on RangeError {
      return null;
    } on TypeError {
      return null;
    }
  }

  static const maximumTextBytes = 200;

  @override
  int messageBytes(Peer peer, String radioName) => maximumTextBytes;
}

const meshBroadcast = 0xffffffff;
String _hexKey(Iterable<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

Map<int, Object> _protobuf(List<int> bytes) {
  final result = <int, Object>{};
  final reader = CodedBufferReader(bytes);
  for (var tag = reader.readTag(); tag != 0; tag = reader.readTag()) {
    switch (tag & 7) {
      case 0:
        result[tag >> 3] = reader.readUint64().toInt();
      case 2:
        result[tag >> 3] = reader.readBytes();
      case 5:
        result[tag >> 3] = reader.readFixed32();
      default:
        if (!reader.skipField(tag)) {
          throw const FormatException('Malformed protobuf');
        }
    }
  }
  return result;
}

extension _Fields on Map<int, Object> {
  int number(int key) => this[key] as int? ?? 0;
  Uint8List bytes(int key) => this[key] as Uint8List? ?? Uint8List(0);
  String string(int key) => utf8.decode(bytes(key), allowMalformed: true);
  Map<int, Object> message(int key) => _protobuf(bytes(key));
}

String _nodeLabel(int number) => '!${number.toRadixString(16).padLeft(8, '0')}';

Uint8List _sharedContact(
  int number,
  String name,
  String? shortName,
  String publicKey,
) {
  final user = CodedBufferWriter()
    ..writeField(1, PbFieldType.OY, utf8.encode(_nodeLabel(number)))
    ..writeField(2, PbFieldType.OY, utf8.encode(fitContactName(name, 39)))
    ..writeField(
      3,
      PbFieldType.OY,
      utf8.encode(fitContactName(shortName ?? '', 4)),
    )
    ..writeField(8, PbFieldType.OY, contactKeyBytes(publicKey));
  return (CodedBufferWriter()
        ..writeField(1, PbFieldType.OU3, number)
        ..writeField(2, PbFieldType.OY, user.toBuffer()))
      .toBuffer();
}

({double? snr, int? rssi}) _receivedSignal(Map<int, Object> packet) {
  final snr = packet.containsKey(8)
      ? (ByteData(4)..setUint32(0, packet.number(8))).getFloat32(0)
      : null;
  final rssi = packet.number(12).toSigned(32);
  return (
    snr: snr?.isFinite == true ? snr : null,
    rssi: rssi < 0 ? rssi : null,
  );
}

NetworkEvent? _tasticMessageEvent(
  Map<int, Object> packet,
  Map<String, Peer> peers,
  int localNode,
  DateTime receivedAt,
) {
  final from = packet.number(1);
  final to = packet.number(2);
  final packetId = packet.number(6);
  final payload = packet.message(4);
  if (payload.number(1) != 1 ||
      from == 0 ||
      from == localNode ||
      (to != localNode && to != meshBroadcast)) {
    return null;
  }
  final hopStart = packet.number(15), hopLimit = packet.number(9);
  final hops = hopStart > 0 && hopStart >= hopLimit
      ? hopStart - hopLimit
      : null;
  final text = payload.string(2);
  if (text.isEmpty) return null;
  final stamp = packet.number(7);
  final channel = to == meshBroadcast;
  final channelNumber = packet.number(3);
  final chat = channel ? 'ch:$channelNumber' : 'node:$from';
  final replyTo = payload.number(7);
  if (payload.number(8) != 0) {
    if (replyTo > 0 && utf8.encode(text).length <= 64) {
      return ReactionReceived(
        MeshReaction(
          chat,
          '$replyTo',
          '$from',
          text,
          time: nodeTimeFromSeconds(stamp),
        ),
      );
    }
    return null;
  }
  final sender = peers['node:$from']?.name ?? _nodeLabel(from);
  final signal = _receivedSignal(packet);
  final relaySuffix = packet.number(19);
  return TextReceived(
    MeshMessage(
      id: 'mt:$from:$to:$packetId',
      chat: chat,
      author: sender,
      text: text,
      time: stamp == 0
          ? receivedAt
          : DateTime.fromMillisecondsSinceEpoch(stamp * 1000),
      delivery: Delivery.received,
      remoteId: packetId > 0 ? '$packetId' : null,
      replyTo: replyTo > 0 ? '$replyTo' : null,
      packet: MessagePacket(
        sender: 'node:$from',
        recipient: channel ? null : 'node:$to',
        channel: channelNumber,
        hops: hops,
        hopLimit: hops != null || packet.containsKey(9) ? hopLimit : null,
        snr: signal.snr,
        rssi: signal.rssi,
        relaySuffix: packet.containsKey(19) && relaySuffix <= 255
            ? relaySuffix
            : null,
        viaMqtt: packet.number(14) != 0 ? true : null,
        pkiEncrypted: packet.number(17) != 0 ? true : null,
      ),
    ),
    peers[chat] ??
        (
          id: chat,
          name: channel ? '#$channelNumber' : sender,
          writable: false,
          channel: channel,
        ),
  );
}

Uint8List meshtasticTextPacket(
  int packetId,
  int destination,
  int channel,
  String text, {
  int? replyTo,
  bool reaction = false,
}) {
  final bytes = utf8.encode(text);
  if (bytes.isEmpty || bytes.length > MeshtasticAdapter.maximumTextBytes) {
    throw ArgumentError.value(bytes.length, 'length');
  }
  final payload = CodedBufferWriter()
    ..writeField(1, PbFieldType.OU3, 1)
    ..writeField(2, PbFieldType.OY, bytes);
  if (replyTo != null) payload.writeField(7, PbFieldType.OF3, replyTo);
  if (reaction) payload.writeField(8, PbFieldType.OF3, 1);
  final packet = CodedBufferWriter()
    ..writeField(2, PbFieldType.OF3, destination)
    ..writeField(3, PbFieldType.OU3, channel)
    ..writeField(4, PbFieldType.OY, payload.toBuffer())
    ..writeField(6, PbFieldType.OF3, packetId)
    ..writeField(10, PbFieldType.OB, true);
  if (destination != meshBroadcast) packet.writeField(17, PbFieldType.OB, true);
  return (CodedBufferWriter()..writeField(1, PbFieldType.OY, packet.toBuffer()))
      .toBuffer();
}

const _regions = {
  '0': 'UNSET',
  '1': 'US',
  '2': 'EU 433',
  '3': 'EU 868',
  '4': 'CN',
  '5': 'JP',
  '6': 'ANZ',
  '7': 'KR',
  '8': 'TW',
  '9': 'RU',
  '10': 'IN',
  '11': 'NZ 865',
  '12': 'TH',
  '13': 'LORA 24',
  '14': 'UA 433',
  '15': 'UA 868',
  '16': 'MY 433',
  '17': 'MY 919',
  '18': 'SG 923',
  '19': 'PH 433',
  '20': 'PH 868',
  '21': 'PH 915',
  '22': 'ANZ 433',
  '23': 'KZ 433',
  '24': 'KZ 863',
  '25': 'NP 865',
  '26': 'BR 902',
  '27': 'ITU1 2M',
  '28': 'ITU2 2M',
  '29': 'EU 866',
  '30': 'EU 874',
  '31': 'EU 917',
  '32': 'EU N 868',
  '33': 'ITU3 2M',
  '34': 'ITU1 70CM',
  '35': 'ITU2 70CM',
  '36': 'ITU3 70CM',
  '37': 'ITU2 125CM',
};

const _presets = {
  '0': 'LONG FAST',
  '1': 'LONG SLOW',
  '2': 'VERY LONG SLOW',
  '3': 'MEDIUM SLOW',
  '4': 'MEDIUM FAST',
  '5': 'SHORT SLOW',
  '6': 'SHORT FAST',
  '7': 'LONG MODERATE',
  '8': 'SHORT TURBO',
  '9': 'LONG TURBO',
  '10': 'LITE FAST',
  '11': 'LITE SLOW',
  '12': 'NARROW FAST',
  '13': 'NARROW SLOW',
  '14': 'TINY FAST',
  '15': 'TINY SLOW',
  '16': 'MEDIUM TURBO',
};

const _roles = {
  '0': 'CLIENT',
  '1': 'CLIENT MUTE',
  '2': 'ROUTER',
  '3': 'ROUTER CLIENT',
  '4': 'REPEATER',
  '5': 'TRACKER',
  '6': 'SENSOR',
  '7': 'TAK',
  '8': 'CLIENT HIDDEN',
  '9': 'LOST AND FOUND',
  '10': 'TAK TRACKER',
  '11': 'ROUTER LATE',
  '12': 'CLIENT BASE',
};

class _TasticSession
    implements
        NetworkSession,
        NetworkRadioIdentity,
        RemoteAdminSession,
        RadioSettingsSession,
        RadioSettingsCatalog,
        RadioSettingsIndex,
        RadioTelemetrySession,
        NetworkNodeActions,
        NetworkRouteTracing,
        NetworkMessageActions,
        RadioOnboardingSession,
        RadioChannelSession,
        RadioConversationSession,
        RadioContactSession,
        RadioPositionSession,
        RadioRestartSession {
  _TasticSession(this.link);
  static const _tx = 'f75c76d2-129e-4dad-a1dd-7866124401e7';
  static const _rx = '2c55e69e-4993-11ed-b878-0242ac120002';
  static const _notice = 'ed9da18c-a800-4f66-a670-aa7547e34453';
  final RadioLink link;
  final _events = StreamController<NetworkEvent>.broadcast();
  final _directory = <String, Peer>{};
  final _publicKeys = <int, Uint8List>{};
  final _shortNames = <int, String>{};
  final _nodeRoles = <int, MeshNodeRole>{};
  final _slots = <int, Map<int, Object>>{};
  final _random = Random.secure();
  Completer<void>? _directorySync;
  final _sent = <int, ({String id, int destination})>{};
  final _confirmed = <int>{};
  StreamSubscription<void>? _disconnect;
  StreamSubscriptionHandle? _notifications;
  bool _closed = false, _reading = false, _readAgain = false, _ready = false;
  bool _neighborInfoEnabled = false;
  int _nonce = 0, _self = 0, _primaryChannel = 0;
  String? _hardwareId;
  String _name = '';
  String? _publicKey;
  Map<int, Object> _metadata = {};
  int _hardwareModel = 0;
  final _reportedConfigs = <int>{};
  final _reportedModules = <int>{};
  bool _hasDeviceUi = false;
  final _deviceMetrics = <int, Object>{};
  Future<void> _adminQueue = Future.value();
  int? _adminRequest, _adminTarget;
  Completer<Map<int, Object>>? _adminReply;
  final _adminKeys = <int, Uint8List>{};
  ({int target, int id, int port, Completer<Uint8List> reply})? _nodeRequest;

  @override
  Stream<NetworkEvent> get events => _events.stream;
  void _emit(NetworkEvent event) {
    if (!_closed) _events.add(event);
  }

  bool _linkInterrupted = false;

  void _linkEnded() {
    _linkInterrupted = true;
    _emit(const RadioEnded());
  }

  @override
  Future<void> start() async {
    _disconnect = link.disconnected.listen((_) => _linkEnded());
    _notifications = await link.subscribe(_notice, (_) => _requestRead());
    await _syncDirectory(1 + _random.nextInt(65000));
    if (_self == 0) {
      throw StateError('Meshtastic radio did not report its identity');
    }
    _ready = true;
    _publish();
  }

  Future<void> _syncDirectory(int nonce) async {
    final sync = _directorySync = Completer<void>();
    _nonce = nonce;
    final ready = sync.future.timeout(const Duration(seconds: 22));
    unawaited(ready.then<void>((_) {}, onError: (Object _) {}));
    try {
      await link.write(
        _tx,
        (CodedBufferWriter()..writeField(3, PbFieldType.OU3, nonce)).toBuffer(),
      );
      _requestRead();
      await ready;
    } finally {
      _nonce = 0;
      _directorySync = null;
      if (_ready) _publish();
    }
  }

  void _requestRead() {
    if (_closed) return;
    _readAgain = true;
    if (_reading) return;
    _reading = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (_readAgain && !_closed) {
        _readAgain = false;
        while (!_closed) {
          final data = await link.read(_rx);
          if (data.isEmpty || _closed) break;
          try {
            _receive(_protobuf(data));
          } on FormatException {
            continue;
          } on InvalidProtocolBufferException {
            continue;
          } on RangeError {
            continue;
          } on TypeError {
            continue;
          }
        }
      }
    } catch (error) {
      if (!_closed) {
        debugPrint('Meshtastic read interrupted: ${error.runtimeType}');
        _linkEnded();
      }
    } finally {
      _reading = false;
    }
  }

  @override
  RadioIdentity get radioIdentity => (
    hardwareId: _hardwareId,
    nodeNumber: _self == 0 ? null : _self,
    publicKey: _publicKey,
  );

  void _publish() => _emit(
    DirectoryUpdate(
      _directory.values.toList(),
      name: _name,
      radioPublicKey: _publicKey,
      radioHardwareId: _hardwareId,
      radioNodeNumber: _self == 0 ? null : _self,
      deviceInfo: (
        firmware: _metadata.string(1).isEmpty ? null : _metadata.string(1),
        board: _board,
        boardModel: _boardModel == 0 ? null : _boardModel,
        build: null,
        protocol: null,
      ),
      identities: {
        for (final entry in _publicKeys.entries)
          'node:${entry.key}': (
            publicKey: _hexKey(entry.value),
            type: null,
            shortName: _shortNames[entry.key],
          ),
      },
    ),
  );

  int get _boardModel {
    final reported = _metadata.number(9);
    return reported == 0 ? _hardwareModel : reported;
  }

  String? get _board => _boardModel == 0
      ? null
      : _tasticHardwareModels[_boardModel] ?? '#$_boardModel';

  void _node(int number, Map<int, Object> user) {
    if (number == 0 || number == meshBroadcast) return;
    if (user.isEmpty &&
        (number == _self || _directory.containsKey('node:$number'))) {
      return;
    }
    final long = user.string(2), short = user.string(3);
    final name = long.isNotEmpty
        ? long
        : short.isNotEmpty
        ? short
        : _nodeLabel(number);
    if (number == _self) {
      _name = name;
      if (user.number(5) != 0) _hardwareModel = user.number(5);
      final key = user.bytes(8);
      if (key.length == 32 && key.any((byte) => byte != 0)) {
        _publicKey = _hexKey(key);
      }
    } else {
      final id = 'node:$number';
      if (user.isNotEmpty) {
        final role = _nodeRoles[number] = switch (user.number(7)) {
          2 || 3 || 11 => MeshNodeRole.router,
          4 => MeshNodeRole.repeater,
          5 || 9 || 10 => MeshNodeRole.tracker,
          6 => MeshNodeRole.sensor,
          7 => MeshNodeRole.gateway,
          _ => MeshNodeRole.client,
        };
        _emit(
          NodeObserved(
            id,
            NodeObservation(
              role: role,
              boardModel: user.number(5) == 0 ? null : user.number(5),
              canMessage: user.containsKey(9)
                  ? user.number(9) == 0
                  : role != MeshNodeRole.repeater,
            ),
          ),
        );
      }
      final key = user.bytes(8);
      if (key.length == 32 && key.any((value) => value != 0)) {
        _publicKeys[number] = key;
        _shortNames[number] = short;
      }
      _directory[id] = (
        id: id,
        name: name,
        channel: false,
        writable:
            key.length == 32 &&
            key.any((value) => value != 0) &&
            (user.containsKey(9)
                ? user.number(9) == 0
                : _nodeRoles[number] != MeshNodeRole.repeater),
      );
    }
    if (_ready && _directorySync == null) _publish();
  }

  NodePosition? _position(Map<int, Object> fields) {
    if (!fields.containsKey(1) || !fields.containsKey(2)) return null;
    return nodePosition(
      fields.number(1).toSigned(32) / 1e7,
      fields.number(2).toSigned(32) / 1e7,
    );
  }

  void _updateDeviceMetrics(Map<int, Object> metrics) {
    _deviceMetrics.addAll(metrics);
    if (!metrics.containsKey(1)) return;
    final level = metrics.number(1);
    _emit(
      RadioBatteryChanged((
        percent: level <= 100 ? level : null,
        powered: level > 100,
        estimated: false,
      )),
    );
  }

  void _receive(Map<int, Object> data) {
    if (data.containsKey(3)) {
      final local = data.message(3);
      _self = local.number(1);
      final id = local.bytes(12);
      if (id.any((byte) => byte != 0)) _hardwareId = _hexKey(id);
    }
    if (data.containsKey(13)) {
      _metadata = data.message(13);
      if (_ready) _publish();
    }
    _reportedConfigs.addAll(data.message(6).keys);
    if (data.containsKey(17)) _hasDeviceUi = true;
    if (data.containsKey(4)) {
      final node = data.message(4);
      final number = node.number(1);
      final position = _position(node.message(3));
      _node(number, node.message(2));
      if (_self != 0 && number == _self) {
        _updateDeviceMetrics(node.message(6));
        if (position != null) _emit(LocalNodePosition(position));
      } else if (number != 0 && number != meshBroadcast) {
        _emit(
          NodeObserved(
            'node:$number',
            NodeObservation(
              lastSeen: nodeTimeFromSeconds(node.number(5)),
              position: position,
              hops: node.containsKey(9) ? node.number(9) : null,
              channel: node.number(7),
              viaMqtt: node.number(8) != 0,
              favorite: node.number(10) != 0,
              ignored: node.number(11) != 0,
            ),
          ),
        );
      }
    }
    final module = data.message(9);
    _reportedModules.addAll(module.keys);
    if (module.containsKey(10)) {
      _neighborInfoEnabled = module.message(10).number(1) != 0;
    }
    if (data.containsKey(10)) _rememberChannel(data.message(10));
    if (_directorySync case final sync?
        when data.number(7) == _nonce && !sync.isCompleted) {
      sync.complete();
    }
    if (data.containsKey(11)) {
      final status = data.message(11);
      if (status.number(1) != 0) {
        final request = status.number(4);
        final sent = _sent.remove(request);
        if (sent != null) _emit(DeliveryUpdate(sent.id, Delivery.failed));
        if (request != 0 && sent == null) {
          _emit(RouteTraceRejected(request, RouteTraceFailure.rejected));
        }
      }
    }
    final notification = data.message(16);
    final limited =
        notification.number(5) == 2 ||
        (notification.number(5) == 0 &&
            notification
                .string(4)
                .toLowerCase()
                .contains('trace route was rate limited'));
    if (limited && notification.number(1) != 0) {
      _emit(
        RouteTraceRejected(
          notification.number(1),
          RouteTraceFailure.rateLimited,
        ),
      );
    }
    if (!data.containsKey(2)) return;
    final packet = data.message(2);
    final from = packet.number(1), to = packet.number(2);
    final payload = packet.message(4);
    final port = payload.number(1);
    final request = payload.number(6);
    if (to == _self && request != 0) {
      if (port == 70) {
        final signal = _receivedSignal(packet);
        _emit(
          RouteTraceReceived(
            'node:$from',
            request,
            _traceFields(
              from,
              payload.bytes(2),
              snr: signal.snr,
              rssi: signal.rssi,
            ),
          ),
        );
      } else if (port == 5 && payload.message(2).number(3) != 0) {
        _emit(RouteTraceRejected(request, RouteTraceFailure.rejected));
      }
    }
    if (_nodeRequest case final pending?
        when to == _self &&
            payload.number(6) == pending.id &&
            !pending.reply.isCompleted) {
      if (from == pending.target && port == pending.port) {
        pending.reply.complete(payload.bytes(2));
      } else if ((from == pending.target || from == _self) &&
          port == 5 &&
          payload.message(2).number(3) != 0) {
        pending.reply.completeError(StateError('Node request rejected'));
      }
    }
    final position = port == 3 ? _position(payload.message(2)) : null;
    final hopStart = packet.number(15), hopLimit = packet.number(9);
    final hops = hopStart > 0 && hopStart >= hopLimit
        ? hopStart - hopLimit
        : null;
    if (from == _self && position != null) {
      _emit(LocalNodePosition(position));
    }
    if (from != 0 && from != _self && from != meshBroadcast) {
      final id = 'node:$from';
      final known = _directory[id];
      final peer =
          known ??
          (id: id, name: _nodeLabel(from), writable: false, channel: false);
      _directory[id] = peer;
      _emit(
        NodeObserved(
          id,
          NodeObservation(
            lastSeen:
                nodeTimeFromSeconds(packet.number(7)) ??
                (_ready && packet.containsKey(12) ? DateTime.now() : null),
            position: position,
            hops: hops,
            viaMqtt: packet.number(14) != 0,
          ),
          peer: known == null ? peer : null,
        ),
      );
    }
    final target = _adminTarget;
    final local = target == _self;
    final adminSender = local
        ? from == _self || from == 0
        : from == target && to == _self;
    if (target != null && adminSender && payload.number(6) == _adminRequest) {
      final reply = _adminReply;
      if (reply != null && !reply.isCompleted) {
        if (payload.number(1) == 6 && (local || packet.number(17) != 0)) {
          final admin = payload.message(2);
          final key = admin.bytes(101);
          if (key.isNotEmpty) _adminKeys[target] = key;
          reply.complete(admin);
        } else if (payload.number(1) == 5 &&
            payload.message(2).number(3) != 0) {
          reply.completeError(StateError('Meshtastic rejected admin request'));
        }
      }
    }
    switch (port) {
      case 1:
        if (_tasticMessageEvent(packet, _directory, _self, DateTime.now())
            case final event?) {
          _emit(event);
        }
      case 4:
        _node(from, _protobuf(payload.bytes(2)));
      case 67:
        if (_self != 0 && from == _self) {
          _updateDeviceMetrics(payload.message(2).message(2));
        }
      case 5:
        if (to != _self) return;
        final request = payload.number(6);
        final sent = _sent[request];
        if (sent == null || _confirmed.contains(request)) return;
        final reason = _protobuf(payload.bytes(2)).number(3);
        if (reason != 0 && (from == _self || from == sent.destination)) {
          _emit(
            DeliveryUpdate(
              sent.id,
              Delivery.failed,
              packet: MessagePacket(routingError: reason),
            ),
          );
        } else if (reason == 0 &&
            from == sent.destination &&
            sent.destination != meshBroadcast) {
          _confirmed.add(request);
          final signal = _receivedSignal(packet);
          _emit(
            DeliveryUpdate(
              sent.id,
              Delivery.acknowledged,
              packet: MessagePacket(
                confirmedBy: 'node:$from',
                ackSnr: signal.snr,
                ackRssi: signal.rssi,
              ),
            ),
          );
        } else if (reason == 0 && from == _self) {
          if (sent.destination == meshBroadcast) {
            // The firmware emits this implicit ACK after hearing the broadcast relayed.
            _confirmed.add(request);
            _emit(DeliveryUpdate(sent.id, Delivery.acknowledged));
          } else {
            _emit(DeliveryUpdate(sent.id, Delivery.relayed));
          }
        }
    }
  }

  Future<T> _serialAdmin<T>(Future<T> Function() action) {
    final task = _adminQueue.then((_) => action());
    _adminQueue = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  @override
  Set<NodeAction> nodeActions(Peer peer) {
    final target = int.tryParse(peer.id.substring(peer.id.indexOf(':') + 1));
    if (!_ready ||
        _closed ||
        peer.channel ||
        target == null ||
        target <= 0 ||
        target == _self ||
        target >= meshBroadcast ||
        !_directory.containsKey(peer.id)) {
      return const {};
    }
    final role = _nodeRoles[target];
    return {
      NodeAction.trace,
      if (_neighborInfoEnabled) NodeAction.neighbors,
      NodeAction.position,
      NodeAction.telemetry,
      NodeAction.identity,
      NodeAction.favorite,
      NodeAction.ignore,
      if (role == MeshNodeRole.sensor) NodeAction.environment,
    };
  }

  @override
  Future<List<RadioField>> runNodeAction(
    Peer peer,
    NodeAction action, {
    bool enabled = true,
    String? password,
  }) async {
    if (!nodeActions(peer).contains(action)) {
      throw StateError('Node action unavailable');
    }
    final target = int.parse(peer.id.substring(5));
    switch (action) {
      case NodeAction.favorite:
      case NodeAction.ignore:
        final favorite = action == NodeAction.favorite;
        final field = favorite ? (enabled ? 39 : 40) : (enabled ? 47 : 48);
        await _serialAdmin(
          () => _admin(
            CodedBufferWriter()..writeField(field, PbFieldType.OU3, target),
            reply: false,
          ),
        );
        _emit(
          NodeObserved(
            peer.id,
            NodeObservation(
              favorite: favorite ? enabled : null,
              ignored: favorite ? null : enabled,
            ),
          ),
        );
        return const [];
      case NodeAction.neighbors:
        return _neighbors(await _requestNode(target, 71, const []));
      case NodeAction.identity:
        final frame = await _requestNode(target, 4, const []);
        final user = _protobuf(frame);
        if (user.isEmpty) throw const FormatException('Empty node identity');
        _node(target, user);
        return [
          RadioField(
            'name',
            'Node name',
            'Имя узла',
            _directory[peer.id]!.name,
            editable: false,
          ),
          if (user.string(3).isNotEmpty)
            RadioField(
              'short',
              'Short name',
              'Короткое имя',
              user.string(3),
              editable: false,
            ),
        ];
      case NodeAction.position:
        final frame = await _requestNode(target, 3, const []);
        final coordinates = _position(_protobuf(frame));
        if (coordinates == null) throw const FormatException('No position');
        return nodePositionFields(coordinates);
      case NodeAction.telemetry:
      case NodeAction.environment:
        final environment = action == NodeAction.environment;
        final variant = environment ? 3 : 2;
        final query =
            (CodedBufferWriter()..writeField(variant, PbFieldType.OY, <int>[]))
                .toBuffer();
        final answer = _protobuf(await _requestNode(target, 67, query))
            .message(variant);
        return _telemetryFields(answer, environment: environment);
      default:
        throw StateError('Node action unavailable');
    }
  }

  Future<Uint8List> _requestNode(int target, int port, List<int> data) async {
    if (_nodeRequest != null || !_ready || _closed) {
      throw StateError('Radio busy');
    }
    final id = int.parse(nextMessageReference());
    final reply = Completer<Uint8List>();
    _nodeRequest = (target: target, id: id, port: port, reply: reply);
    final response = reply.future.timeout(const Duration(seconds: 35));
    unawaited(response.then<void>((_) {}, onError: (Object _) {}));
    try {
      await _sendNodeRequest(target, port, data, id);
      return await response;
    } finally {
      _nodeRequest = null;
      if (!reply.isCompleted) {
        reply.completeError(StateError('Node request ended'));
      }
    }
  }

  @override
  Duration get routeTraceInterval => const Duration(seconds: 30);

  @override
  DateTime? get routeTracePendingUntil => null;

  @override
  Future<void> startRouteTrace(Peer peer, int request) {
    if (!nodeActions(peer).contains(NodeAction.trace)) {
      throw StateError('Node action unavailable');
    }
    return _sendNodeRequest(
      int.parse(peer.id.substring(5)),
      70,
      const [],
      request,
    );
  }

  Future<void> _sendNodeRequest(
    int target,
    int port,
    List<int> data,
    int id,
  ) async {
    final payload = CodedBufferWriter()
      ..writeField(1, PbFieldType.OU3, port)
      ..writeField(2, PbFieldType.OY, data)
      ..writeField(3, PbFieldType.OB, true);
    final packet = CodedBufferWriter()
      ..writeField(2, PbFieldType.OF3, target)
      ..writeField(3, PbFieldType.OU3, _primaryChannel)
      ..writeField(4, PbFieldType.OY, payload.toBuffer())
      ..writeField(6, PbFieldType.OF3, id)
      ..writeField(10, PbFieldType.OB, true);
    await link.write(
      _tx,
      (CodedBufferWriter()..writeField(1, PbFieldType.OY, packet.toBuffer()))
          .toBuffer(),
    );
    _requestRead();
  }

  List<RadioField> _traceFields(
    int target,
    Uint8List bytes, {
    double? snr,
    int? rssi,
  }) {
    final (outbound, forwardSnr, inbound, reverseSnr) = _traceHops(bytes);
    List<RadioHop> readings(
      List<int> hops,
      List<int> signals,
      int destination, {
      double? snr,
      int? rssi,
    }) => [
      for (final (index, node) in [...hops, destination].indexed)
        (
          name: node == _self
              ? (_name.isEmpty ? _nodeLabel(node) : _name)
              : _directory['node:$node']?.name ?? _nodeLabel(node),
          snr: index < signals.length && signals[index] != -128
              ? signals[index] / 4
              : index == hops.length
              ? snr
              : null,
          rssi: index == hops.length ? rssi : null,
        ),
    ];
    String display(List<int> hops) => hops.isEmpty
        ? '0'
        : hops
              .map((id) => _directory['node:$id']?.name ?? _nodeLabel(id))
              .join(' → ');
    return [
      RadioField(
        'route',
        'To node',
        'До узла',
        display(outbound),
        hops: readings(outbound, forwardSnr, target),
        editable: false,
      ),
      RadioField(
        'return',
        'Return path',
        'Обратный путь',
        display(inbound),
        hops: readings(inbound, reverseSnr, _self, snr: snr, rssi: rssi),
        editable: false,
      ),
    ];
  }

  (List<int>, List<int>, List<int>, List<int>) _traceHops(Uint8List bytes) {
    final reader = CodedBufferReader(bytes);
    final forward = <int>[],
        forwardSnr = <int>[],
        back = <int>[],
        backSnr = <int>[];
    for (var tag = reader.readTag(); tag != 0; tag = reader.readTag()) {
      final field = tag >> 3;
      final wire = tag & 7;
      if ((field == 1 || field == 3) && (wire == 5 || wire == 2)) {
        final hops = field == 1 ? forward : back;
        if (wire == 5) {
          hops.add(reader.readFixed32());
        } else {
          final packed = reader.readBytes();
          if (packed.length % 4 != 0) {
            throw const FormatException('Invalid route');
          }
          final data = ByteData.sublistView(packed);
          for (var offset = 0; offset < packed.length; offset += 4) {
            hops.add(data.getUint32(offset, Endian.little));
          }
        }
      } else if ((field == 2 || field == 4) && (wire == 0 || wire == 2)) {
        final signals = field == 2 ? forwardSnr : backSnr;
        if (wire == 0) {
          signals.add(reader.readInt32());
        } else {
          final packed = CodedBufferReader(reader.readBytes());
          while (!packed.isAtEnd()) {
            signals.add(packed.readInt32());
          }
        }
      } else {
        reader.skipField(tag);
      }
    }
    return (forward, forwardSnr, back, backSnr);
  }

  List<RadioField> _neighbors(Uint8List bytes) {
    final reader = CodedBufferReader(bytes);
    final rows = <RadioField>[];
    for (var tag = reader.readTag(); tag != 0; tag = reader.readTag()) {
      if (tag != 34) {
        reader.skipField(tag);
        continue;
      }
      final entry = _protobuf(reader.readBytes());
      final id = entry.number(1);
      if (id == 0 || id == meshBroadcast) continue;
      final name = _directory['node:$id']?.name ?? _nodeLabel(id);
      final raw = entry.number(2);
      final signal = (ByteData(4)..setUint32(0, raw)).getFloat32(0);
      rows.add(
        RadioField(
          '$id',
          name,
          name,
          entry.containsKey(2) && signal.isFinite
              ? signal.toStringAsFixed(1)
              : '—',
          units: entry.containsKey(2) && signal.isFinite ? 'dB SNR' : null,
          editable: false,
        ),
      );
    }
    return rows;
  }

  List<RadioField> _telemetryFields(
    Map<int, Object> metrics, {
    required bool environment,
  }) {
    final fields = environment
        ? const {
            1: ('Temperature', 'Температура', '°C', false),
            2: ('Humidity', 'Влажность', '%', false),
            3: ('Pressure', 'Давление', 'hPa', false),
            5: ('Voltage', 'Напряжение', 'V', false),
            6: ('Current', 'Ток', 'mA', false),
            9: ('Light', 'Освещённость', 'lx', false),
          }
        : const {
            1: ('Battery', 'Заряд батареи', '%', true),
            2: ('Voltage', 'Напряжение', 'V', false),
            3: ('Channel utilization', 'Занятость канала', '%', false),
            4: ('TX airtime', 'Время в эфире', '%', false),
            5: ('Uptime', 'Время работы', 's', true),
          };
    final results = <RadioField>[];
    for (final entry in fields.entries) {
      if (!metrics.containsKey(entry.key)) continue;
      final (en, ru, units, integer) = entry.value;
      final raw = metrics.number(entry.key);
      final value = integer
          ? raw
          : (ByteData(4)..setUint32(0, raw)).getFloat32(0);
      if (!value.isFinite || (!environment && entry.key == 1 && raw > 100)) {
        continue;
      }
      results.add(
        RadioField(
          '${entry.key}',
          en,
          ru,
          integer ? '$value' : value.toStringAsFixed(2),
          units: units,
          editable: false,
        ),
      );
    }
    if (results.isEmpty) throw const FormatException('No telemetry');
    return results;
  }

  Future<Map<int, Object>> _admin(
    CodedBufferWriter command, {
    bool reply = true,
    int? target,
    Duration? timeout,
    bool mayRestart = false,
    bool restart = false,
  }) async {
    if (!_ready || _closed) throw StateError('Meshtastic radio disconnected');
    final id = 1 + _random.nextInt(0x7ffffffe);
    final destination = target ?? _self;
    final remote = destination != _self;
    final sessionKey = _adminKeys[destination];
    if (!reply && remote && sessionKey == null) {
      throw StateError('Meshtastic admin key unavailable');
    }
    if (sessionKey case final key? when !reply) {
      command.writeField(101, PbFieldType.OY, key);
    }
    final data = CodedBufferWriter()
      ..writeField(1, PbFieldType.OU3, 6)
      ..writeField(2, PbFieldType.OY, command.toBuffer())
      ..writeField(3, PbFieldType.OB, reply);
    final packet = CodedBufferWriter()
      ..writeField(2, PbFieldType.OF3, destination)
      ..writeField(4, PbFieldType.OY, data.toBuffer())
      ..writeField(6, PbFieldType.OF3, id)
      ..writeField(10, PbFieldType.OB, true);
    if (remote) packet.writeField(17, PbFieldType.OB, true);
    final wire =
        (CodedBufferWriter()..writeField(1, PbFieldType.OY, packet.toBuffer()))
            .toBuffer();
    final answer = reply ? Completer<Map<int, Object>>() : null;
    if (answer != null) {
      _adminRequest = id;
      _adminTarget = destination;
      _adminReply = answer;
    }
    final wait = answer?.future.timeout(
      timeout ?? Duration(seconds: remote ? 28 : 8),
    );
    unawaited(wait?.then<void>((_) {}, onError: (Object _) {}));
    try {
      if (!remote && (mayRestart || restart)) {
        _emit(RadioRestartExpected(explicit: restart));
      }
      await link.write(_tx, wire);
      _requestRead();
      return wait == null ? {} : await wait;
    } finally {
      _adminRequest = null;
      _adminTarget = null;
      _adminReply = null;
    }
  }

  Future<T> _verifyWrite<T>(
    Future<T> Function(_TasticSession) fromRadio, {
    required bool mayRestart,
  }) async {
    try {
      return await fromRadio(this);
    } catch (_) {
      if (!mayRestart || !_linkInterrupted) rethrow;
      throw RadioWriteInterrupted<T>((session) {
        final radio = session as _TasticSession;
        return radio._serialAdmin(() => fromRadio(radio));
      });
    }
  }

  void _rememberChannel(Map<int, Object> channel) {
    final index = channel.number(1);
    final role = channel.number(3);
    _slots[index] = channel;
    final id = 'ch:$index';
    if (role == 0) {
      _directory.remove(id);
    } else {
      if (role == 1) _primaryChannel = index;
      final name = channel.message(2).string(3);
      _directory[id] = (
        id: id,
        name: name.isEmpty ? (index == 0 ? 'Public' : '#$index') : name,
        writable: true,
        channel: true,
      );
    }
    if (_ready) _publish();
  }

  @override
  Future<List<RadioSetupStep>> setupSteps() async {
    final lora = await _serialAdmin(() async => _protobuf(await _config(5, 6)));
    if (lora.number(7) != 0) return [];
    final fields = await readSettings();
    return [
      (
        title: 'Name your radio',
        russian: 'Назовите рацию',
        fields: fields
            .where((field) => field.id == 'long' || field.id == 'short')
            .toList(),
      ),
      (
        title: 'Choose your LoRa region',
        russian: 'Выберите регион LoRa',
        fields: [
          RadioField(
            'region',
            'LoRa region',
            'Регион LoRa',
            '',
            kind: RadioFieldKind.choice,
            choices: Map.of(_regions)..remove('0'),
          ),
          ...fields.where((field) => field.id == 'preset' && field.editable),
        ],
      ),
    ];
  }

  @override
  List<ChannelAction> get channelActions => [
    ChannelAction.createPrivate,
    ChannelAction.joinPrivate,
    ChannelAction.invitation,
  ];

  @override
  Future<ChannelProvision> addChannel(
    ChannelRequest request,
  ) => _serialAdmin(() async {
    await _owner(); // Refresh local admin session key.
    final localLoRa = await _config(5, 6);
    final configs = <List<int>>[];
    if (request.action == ChannelAction.invitation) {
      final uri = Uri.tryParse(request.invitation.trim());
      if (uri == null) throw const FormatException('channel-invite');
      final invite = readMeshtasticChannelInvitation(uri);
      final invitedLoRa = invite.getField(2)?.lengthDelimited.firstOrNull;
      if (invitedLoRa != null) {
        final region = _protobuf(invitedLoRa).number(7);
        final current = _protobuf(localLoRa).number(7);
        if (region != 0 && current != 0 && region != current) {
          throw const FormatException('channel-region');
        }
      }
      for (final settings
          in invite.getField(1)?.lengthDelimited ?? const <List<int>>[]) {
        final fields = _protobuf(settings);
        final name = fields.string(3);
        final key = fields.bytes(2);
        if (name.isEmpty) {
          final primary = _slots[_primaryChannel]?.message(2);
          if (primary != null &&
              primary.string(3).isEmpty &&
              sameChannelKey(primary.bytes(2), key)) {
            continue;
          }
          throw const FormatException('channel-primary');
        }
        if (!const {0, 1, 16, 32}.contains(key.length)) {
          throw const FormatException('channel-key');
        }
        _validateName(name);
        // Preserve channel encoding, but don't enable internet relays or location sharing.
        final safe = UnknownFieldSet()
          ..mergeFromCodedBufferReader(CodedBufferReader(settings));
        for (final tag in [5, 6, 7]) {
          safe.clearField(tag);
        }
        final encoded = CodedBufferWriter();
        safe.writeToCodedBufferWriter(encoded);
        configs.add(encoded.toBuffer());
      }
      if (configs.isEmpty) {
        final primary = _directory['ch:$_primaryChannel'];
        if (primary != null && invite.hasField(1)) {
          return (peer: primary, invitation: null);
        }
        throw const FormatException('channel-invite');
      }
    } else {
      final name = request.name.trim();
      final nameBytes = _validateName(name);
      final secret = request.action == ChannelAction.createPrivate
          ? createChannelKey(32)
          : parseChannelKey(request.secret, {16, 32});
      configs.add(
        (CodedBufferWriter()
              ..writeField(2, PbFieldType.OY, secret)
              ..writeField(3, PbFieldType.OY, nameBytes))
            .toBuffer(),
      );
    }

    final free = [
      for (final slot in _slots.entries)
        if (slot.key != 0 && slot.value.number(3) == 0) slot.key,
    ]..sort();
    final pending = <(int, List<int>)>[];
    final names = <String>{};
    Peer? first;
    for (final config in configs) {
      final fields = _protobuf(config);
      final name = fields.string(3);
      if (!names.add(name)) throw StateError('channel-duplicate');
      final existing = _slots.entries
          .where(
            (item) =>
                item.value.number(3) != 0 &&
                item.value.message(2).string(3) == name,
          )
          .firstOrNull;
      if (existing != null) {
        final previous = existing.value.message(2);
        if (!sameChannelKey(previous.bytes(2), fields.bytes(2)) ||
            previous.number(8) != fields.number(8)) {
          throw StateError('channel-duplicate');
        }
        first ??= _directory['ch:${existing.key}'];
        continue;
      }
      if (free.isEmpty) throw StateError('channel-full');
      pending.add((free.removeAt(0), config));
    }
    if (pending.length > 1) {
      await _admin(
        CodedBufferWriter()..writeField(64, PbFieldType.OB, true),
        reply: false,
      );
    }
    for (final (index, config) in pending) {
      final channel = CodedBufferWriter()
        ..writeField(1, PbFieldType.OU3, index)
        ..writeField(2, PbFieldType.OY, config)
        ..writeField(3, PbFieldType.OU3, 2);
      await _admin(
        CodedBufferWriter()..writeField(33, PbFieldType.OY, channel.toBuffer()),
        reply: false,
      );
    }
    if (pending.length > 1) {
      await _admin(
        CodedBufferWriter()..writeField(65, PbFieldType.OB, true),
        reply: false,
        mayRestart: true,
      );
    }
    return _verifyWrite((radio) async {
      for (final (index, config) in pending) {
        final readback = await radio._admin(
          CodedBufferWriter()..writeField(1, PbFieldType.OU3, index + 1),
        );
        final channel = readback.message(2);
        final expected = _protobuf(config);
        final actual = channel.message(2);
        if (channel.number(1) != index ||
            channel.number(3) != 2 ||
            actual.string(3) != expected.string(3) ||
            !sameChannelKey(actual.bytes(2), expected.bytes(2))) {
          throw StateError('channel-write');
        }
        radio._rememberChannel(channel);
        first ??= radio._directory['ch:$index'];
      }
      final peer = first;
      if (peer == null) throw StateError('channel-write');
      String? invitation;
      if (request.action == ChannelAction.createPrivate) {
        final set =
            (CodedBufferWriter()
                  ..writeField(1, PbFieldType.OY, configs.first)
                  ..writeField(2, PbFieldType.OY, localLoRa))
                .toBuffer();
        invitation =
            'https://meshtastic.org/e/?add=true#${base64Url.encode(set).replaceAll('=', '')}';
      }
      return (peer: peer, invitation: invitation);
    }, mayRestart: pending.length > 1);
  });

  @override
  Future<Peer> importContact(ContactAttachment contact) =>
      _serialAdmin(() async {
        if (!_ready || _closed || contact.network != 'meshtastic') {
          throw StateError('contact-import-unavailable');
        }
        final number = int.tryParse(contact.id.split(':').last);
        final publicKey = contact.publicKey;
        if (number == null ||
            number <= 0 ||
            number >= meshBroadcast ||
            number == _self ||
            publicKey == _publicKey ||
            contact.id != 'node:$number' ||
            !validContactKey(publicKey)) {
          throw const FormatException('Invalid Meshtastic contact');
        }
        await _owner();
        final existing = _publicKeys[number];
        if (existing != null) {
          if (_hexKey(existing) != publicKey) {
            throw StateError('contact-key-conflict');
          }
          return _directory[contact.id]!;
        }
        await _admin(
          CodedBufferWriter()..writeField(
            66,
            PbFieldType.OY,
            _sharedContact(number, contact.name, contact.shortName, publicKey),
          ),
          reply: false,
        );
        // Wait for a later local admin reply before requesting the snapshot.
        // An admin write alone can still be queued on the radio.
        await _owner();
        // 69421 requests the node directory on current companions. Older radio
        // firmware responds with the standard configuration and directory.
        await _syncDirectory(69421);
        final confirmed = _publicKeys[number];
        if (confirmed == null || _hexKey(confirmed) != publicKey) {
          throw StateError('contact-import-unconfirmed');
        }
        return _directory[contact.id]!;
      });

  @override
  bool canRemovePeer(Peer peer) {
    if (!_ready || _closed || !_directory.containsKey(peer.id)) return false;
    if (!peer.channel) return true;
    final slot = int.tryParse(peer.id.substring(3));
    return slot != null &&
        slot != _primaryChannel &&
        _slots[slot]?.number(3) == 2;
  }

  @override
  Future<void> removePeer(Peer peer) => _serialAdmin(() async {
    if (!canRemovePeer(peer)) throw StateError('peer-remove-unavailable');
    await _owner();
    if (peer.channel) {
      final slot = int.parse(peer.id.substring(3));
      final disabled = CodedBufferWriter()
        ..writeField(1, PbFieldType.OU3, slot)
        ..writeField(3, PbFieldType.OU3, 0);
      await _admin(
        CodedBufferWriter()
          ..writeField(33, PbFieldType.OY, disabled.toBuffer()),
        reply: false,
      );
      final result = await _admin(
        CodedBufferWriter()..writeField(1, PbFieldType.OU3, slot + 1),
      );
      if (!result.containsKey(2)) throw StateError('channel-write');
      final changed = result.message(2);
      if (changed.number(1) != slot || changed.number(3) != 0) {
        throw StateError('channel-write');
      }
      _rememberChannel(changed);
    } else {
      final number = int.parse(peer.id.substring(5));
      await _admin(
        CodedBufferWriter()..writeField(38, PbFieldType.OU3, number),
        reply: false,
      );
      _directory.remove(peer.id);
      _publicKeys.remove(number);
      _shortNames.remove(number);
      _nodeRoles.remove(number);
      _publish();
    }
  });

  @override
  bool canShareChannel(Peer peer) {
    if (!_ready || _closed || !peer.channel) return false;
    final channel = _slots[int.tryParse(peer.id.substring(3))];
    return channel != null &&
        channel.number(3) != 0 &&
        channel.bytes(2).isNotEmpty;
  }

  @override
  Future<String> shareChannel(Peer peer) => _serialAdmin(() async {
    if (!canShareChannel(peer)) throw StateError('channel-share-unavailable');
    final channel = _slots[int.parse(peer.id.substring(3))]!;
    final lora = await _config(5, 6);
    final set =
        (CodedBufferWriter()
              ..writeField(1, PbFieldType.OY, channel.bytes(2))
              ..writeField(2, PbFieldType.OY, lora))
            .toBuffer();
    return 'https://meshtastic.org/e/?add=true#${base64Url.encode(set).replaceAll('=', '')}';
  });

  @override
  Future<void> setFixedPosition(NodePosition position) =>
      _writeFixedPosition(position);

  Future<void> _writeFixedPosition(NodePosition position, [int? target]) =>
      _serialAdmin(() async {
        await _owner(target);
        final point = CodedBufferWriter()
          ..writeField(1, PbFieldType.OSF3, (position.latitude * 1e7).round())
          ..writeField(2, PbFieldType.OSF3, (position.longitude * 1e7).round());
        await _admin(
          CodedBufferWriter()..writeField(41, PbFieldType.OY, point.toBuffer()),
          reply: false,
          target: target,
        );
        if (target == null) {
          _emit(LocalNodePosition(position));
        } else {
          _emit(
            NodeObserved('node:$target', NodeObservation(position: position)),
          );
        }
      });

  List<int> _validateName(String name) {
    if (name.toLowerCase() == 'admin') {
      throw const FormatException('channel-name');
    }
    return channelNameBytes(name, 11);
  }

  Future<Map<int, Object>> _owner([int? target]) async {
    final state = await _admin(
      CodedBufferWriter()..writeField(3, PbFieldType.OB, true),
      target: target,
    );
    if (!state.containsKey(4)) throw StateError('Meshtastic owner unavailable');
    return state.message(4);
  }

  Future<Uint8List> _config(
    int type,
    int field, [
    int? target,
    bool module = false,
  ]) async {
    final state = await _admin(
      CodedBufferWriter()..writeField(module ? 7 : 5, PbFieldType.OU3, type),
      target: target,
    );
    final config = state.message(module ? 8 : 6);
    if (!config.containsKey(field)) {
      throw const _TasticConfigUnavailable();
    }
    return config.bytes(field);
  }

  @override
  Future<List<RadioField>> readSettings() => _readSettings(null);

  @override
  Future<void> restartRadio() => _serialAdmin(() async {
    await _owner();
    await _admin(
      CodedBufferWriter()..writeField(97, PbFieldType.O3, 2),
      reply: false,
      restart: true,
    );
  });

  @override
  bool get adminRequiresPassword => false;

  @override
  bool canAdminister(Peer peer) =>
      _ready &&
      !peer.channel &&
      _publicKeys.containsKey(int.tryParse(peer.id.split(':').last));

  @override
  Future<RadioSettingsSession> openAdmin(Peer peer, String password) async {
    if (!canAdminister(peer)) throw StateError('Admin unavailable');
    final target = int.parse(peer.id.split(':').last);
    return _TasticRemoteSettings(this, target);
  }

  Future<List<RadioField>> _readSettings(int? target) => _serialAdmin(() async {
    final owner = await _owner(target);
    final device = _protobuf(await _config(0, 1, target));
    final lora = _protobuf(await _config(5, 6, target));
    final name = owner.string(2);
    if (target == null && owner.isNotEmpty) _node(_self, owner);
    return [
      RadioField('long', 'Long name', 'Полное имя', name),
      RadioField('short', 'Short name', 'Короткое имя', owner.string(3)),
      RadioField(
        'role',
        'Device role',
        'Роль устройства',
        '${device.number(1)}',
        kind: RadioFieldKind.choice,
        choices: _roles,
      ),
      RadioField(
        'region',
        'LoRa region',
        'Регион LoRa',
        '${lora.number(7)}',
        section: RadioFieldSection.lora,
        kind: RadioFieldKind.choice,
        choices: _regions,
      ),
      RadioField(
        'preset',
        'Modem preset',
        'Режим модуляции',
        '${lora.number(2)}',
        section: RadioFieldSection.lora,
        kind: RadioFieldKind.choice,
        choices: _presets,
        editable: lora.number(1) != 0,
      ),
      RadioField(
        'hops',
        'Hop limit',
        'Лимит переходов',
        '${lora.number(8)}',
        section: RadioFieldSection.lora,
        kind: RadioFieldKind.integer,
      ),
      RadioField(
        'power',
        'Transmit power',
        'Мощность передачи',
        '${lora.number(10)}',
        section: RadioFieldSection.lora,
        kind: RadioFieldKind.integer,
        units: 'dBm',
      ),
      RadioField(
        'transmit',
        'Enable transmission',
        'Разрешить передачу',
        '${lora.number(9) != 0}',
        section: RadioFieldSection.lora,
        kind: RadioFieldKind.toggle,
      ),
    ];
  });

  @override
  Future<void> writeSettings(Map<String, String> values) =>
      _writeSettings(values, null);

  Future<void> _writeSettings(
    Map<String, String> values,
    int? target,
  ) => _serialAdmin(() async {
    final owner = CodedBufferWriter();
    var ownerChanged = false;
    for (final (key, field, limit) in [('long', 2, 39), ('short', 3, 4)]) {
      final value = values[key]?.trim();
      if (value == null) continue;
      final text = utf8.encode(value);
      if (text.isEmpty || text.length > limit || text.contains(0)) {
        throw const FormatException('Invalid node name');
      }
      owner.writeField(field, PbFieldType.OY, text);
      ownerChanged = true;
    }
    final device = <int, int>{};
    final lora = <int, int>{};
    void choice(
      String key,
      Map<String, String> allowed,
      Map<int, int> patch,
      int field,
    ) {
      if (!values.containsKey(key)) return;
      final value = values[key]!;
      if (!allowed.containsKey(value)) {
        throw const FormatException('Unknown choice');
      }
      patch[field] = int.parse(value);
    }

    void range(String key, int field, int minimum, int maximum) {
      if (!values.containsKey(key)) return;
      final value = int.tryParse(values[key]!);
      if (value == null || value < minimum || value > maximum) {
        throw const FormatException('Invalid LoRa value');
      }
      lora[field] = value;
    }

    choice('role', _roles, device, 1);
    choice('region', _regions, lora, 7);
    choice('preset', _presets, lora, 2);
    range('hops', 8, 0, 7);
    range('power', 10, 0, 30);
    if (values.containsKey('transmit')) {
      lora[9] = values['transmit'] == 'true' ? 1 : 0;
    }

    // Refresh the session key and preserve the existing radio identity flags.
    if (target != null) _adminKeys.remove(target);
    final previousOwner = await _owner(target);
    final pending = <CodedBufferWriter>[];
    if (ownerChanged) {
      owner.writeField(6, PbFieldType.OB, previousOwner.number(6) != 0);
      if (previousOwner.containsKey(9)) {
        owner.writeField(9, PbFieldType.OB, previousOwner.number(9) != 0);
      }
      pending.add(
        CodedBufferWriter()..writeField(32, PbFieldType.OY, owner.toBuffer()),
      );
    }
    if (device.isNotEmpty) {
      pending.add(await _configPatch(0, 1, device, target));
    }
    if (lora.isNotEmpty) pending.add(await _configPatch(5, 6, lora, target));
    final batch = pending.length > 1;
    final mayRestart = target == null && (device.isNotEmpty || lora.isNotEmpty);
    if (batch) {
      await _admin(
        CodedBufferWriter()..writeField(64, PbFieldType.OB, true),
        reply: false,
        target: target,
      );
    }
    for (final update in pending) {
      await _admin(
        update,
        reply: false,
        target: target,
        mayRestart: !batch && mayRestart,
      );
    }
    if (batch) {
      await _admin(
        CodedBufferWriter()..writeField(65, PbFieldType.OB, true),
        reply: false,
        target: target,
        mayRestart: mayRestart,
      );
    }

    await _verifyWrite((radio) async {
      if (ownerChanged) {
        final current = await radio._owner(target);
        for (final (key, field) in [('long', 2), ('short', 3)]) {
          if (values[key] != null &&
              current.string(field) != values[key]!.trim()) {
            throw StateError('Meshtastic did not confirm the node name');
          }
        }
      }
      if (device.isNotEmpty) await radio._verifyConfig(0, 1, device, target);
      if (lora.isNotEmpty) await radio._verifyConfig(5, 6, lora, target);
    }, mayRestart: mayRestart);
  });

  Future<void> _verifyConfig(
    int type,
    int field,
    Map<int, int> patch,
    int? target,
  ) async {
    final actual = _protobuf(await _config(type, field, target));
    if (patch.entries.any((entry) => actual.number(entry.key) != entry.value)) {
      throw StateError('Meshtastic did not apply the requested configuration');
    }
  }

  Future<CodedBufferWriter> _configPatch(
    int type,
    int field,
    Map<int, int> patch,
    int? target, [
    bool module = false,
    Uint8List? previous,
  ]) async {
    final config = previous ?? await _config(type, field, target, module);
    final settings = UnknownFieldSet()
      ..mergeFromCodedBufferReader(CodedBufferReader(config));
    for (final tag in patch.keys) {
      settings.clearField(tag);
    }
    final encoded = CodedBufferWriter();
    settings.writeToCodedBufferWriter(encoded);
    for (final update in patch.entries) {
      encoded.writeField(update.key, PbFieldType.OU3, update.value);
    }
    final wrapped = CodedBufferWriter()
      ..writeField(field, PbFieldType.OY, encoded.toBuffer());
    return CodedBufferWriter()
      ..writeField(module ? 35 : 34, PbFieldType.OY, wrapped.toBuffer());
  }

  static const _legacySections = {
    RadioFieldSection.position,
    RadioFieldSection.routing,
    RadioFieldSection.power,
    RadioFieldSection.connectivity,
    RadioFieldSection.display,
    RadioFieldSection.lora,
    RadioFieldSection.bluetooth,
    RadioFieldSection.security,
    RadioFieldSection.mqtt,
    RadioFieldSection.sensors,
    RadioFieldSection.notifications,
  };
  final _unsupportedSections = <(int?, RadioFieldSection)>{};

  List<RadioFieldSection> _sections([int? target]) => [
    for (final entry in _tasticSections.entries)
      if (_supportsSection(entry.key, entry.value, target)) entry.key,
  ];

  bool _supportsSection(
    RadioFieldSection section,
    _TasticSection spec,
    int? target,
  ) {
    if (_unsupportedSections.contains((target, section))) return false;
    if (target != null) return _legacySections.contains(section);
    if (spec.since case final since?) {
      if (!_firmwareAtLeast(_metadata.string(1), since)) return false;
    }
    if (section == RadioFieldSection.security &&
        _firmwareAtLeast(_metadata.string(1), '0.0.0') &&
        !_firmwareAtLeast(_metadata.string(1), '2.5.0')) {
      return false;
    }
    // ExcludedModules places two hardware flags between Paxcounter and Status Message.
    final exclusion = spec.module
        ? 1 << (spec.type < 13 ? spec.type : spec.type + 2)
        : switch (section) {
            RadioFieldSection.bluetooth => 0x2000,
            RadioFieldSection.connectivity => 0x4000,
            _ => 0,
          };
    if ((_metadata.number(12) & exclusion) != 0) return false;
    if (_metadata.string(1).isNotEmpty) {
      if (section == RadioFieldSection.bluetooth && _metadata.number(5) == 0) {
        return false;
      }
      if (section == RadioFieldSection.connectivity &&
          _metadata.number(4) == 0 &&
          _metadata.number(6) == 0) {
        return false;
      }
    }
    if (section == RadioFieldSection.deviceUi && _hasDeviceUi) return true;
    final reported = spec.module ? _reportedModules : _reportedConfigs;
    return reported.isEmpty
        ? _legacySections.contains(section)
        : reported.contains(spec.field);
  }

  Iterable<_TasticSetting> _supportedItems(
    _TasticSection section,
    int? target,
  ) {
    final firmware = target == null ? _metadata.string(1) : '';
    return section.items.where(
      (item) =>
          (item.since == null || _firmwareAtLeast(firmware, item.since!)) &&
          (item.before == null ||
              (_firmwareAtLeast(firmware, '0.0.0') &&
                  !_firmwareAtLeast(firmware, item.before!))) &&
          (section.module ||
              section.field != 8 ||
              item.tag != 9 ||
              _metadata.number(14) != 0),
    );
  }

  Future<Uint8List> _readCatalogWire(_TasticSection spec, int? target) async {
    if (!spec.module && spec.field == 10) {
      final reply = await _admin(
        CodedBufferWriter()..writeField(44, PbFieldType.OB, true),
        target: target,
      );
      if (!reply.containsKey(45)) throw const _TasticConfigUnavailable();
      return reply.bytes(45);
    }
    return _config(spec.type, spec.field, target, spec.module);
  }

  Future<String?> _readAuxiliary(_TasticAuxiliary spec, int? target) async {
    try {
      final reply = await _admin(
        CodedBufferWriter()..writeField(spec.get, PbFieldType.OB, true),
        target: target,
        timeout: const Duration(seconds: 3),
      );
      return reply.containsKey(spec.response)
          ? reply.string(spec.response)
          : null;
    } on TimeoutException {
      return null;
    }
  }

  Iterable<RadioSettingName> _settingNames(
    RadioFieldSection section,
    int? target,
  ) sync* {
    final spec = _tasticSections[section];
    if (spec == null || !_supportsSection(section, spec, target)) return;
    for (final setting in _supportedItems(spec, target)) {
      yield (id: setting.id, title: setting.en, russian: setting.ru);
    }
    if (_auxiliarySettings[section] case final auxiliary? when target == null) {
      yield (id: 'content', title: auxiliary.en, russian: auxiliary.ru);
    }
  }

  @override
  Iterable<RadioSettingName> settingNames(RadioFieldSection section) =>
      _settingNames(section, null);

  @override
  List<RadioFieldSection> get extraSettings => _sections();

  @override
  Future<List<RadioField>> readSection(RadioFieldSection section) =>
      _readSection(section, null);

  Future<List<RadioField>> _readSection(
    RadioFieldSection section,
    int? target,
  ) => _serialAdmin(() async {
    final spec = _tasticSections[section];
    if (spec == null || !_supportsSection(section, spec, target)) return [];
    final Uint8List wire;
    try {
      wire = await _readCatalogWire(spec, target);
    } on _TasticConfigUnavailable {
      _unsupportedSections.add((target, section));
      return [];
    }
    final config = _settingsFields(wire);
    final auxiliary = target == null ? _auxiliarySettings[section] : null;
    final value = auxiliary == null
        ? null
        : await _readAuxiliary(auxiliary, target);
    return [
      for (final item in _supportedItems(spec, target))
        item.toField(section, config),
      if (auxiliary != null && value != null)
        RadioField(
          'content',
          auxiliary.en,
          auxiliary.ru,
          value,
          section: section,
        ),
    ];
  });

  @override
  Future<void> writeSection(
    RadioFieldSection section,
    Map<String, String> values,
  ) => _writeSection(section, values, null);

  Future<void> _writeSection(
    RadioFieldSection section,
    Map<String, String> values,
    int? target,
  ) => _serialAdmin(() async {
    if (values.isEmpty) return;
    final spec = _tasticSections[section];
    if (spec == null || !_supportsSection(section, spec, target)) {
      throw const FormatException('Unsupported Meshtastic settings');
    }
    final fields = {
      for (final setting in _supportedItems(spec, target)) setting.id: setting,
    };
    final updates = Map<String, String>.of(values);
    final content = target == null ? updates.remove('content') : null;
    final auxiliary = _auxiliarySettings[section];
    if (content != null &&
        (auxiliary == null ||
            utf8.encode(content).length > auxiliary.limit ||
            content.contains('\u0000'))) {
      throw const FormatException('Invalid module text');
    }
    if (!updates.keys.every(fields.containsKey)) {
      throw const FormatException('Unsupported Meshtastic setting');
    }
    if (target != null) _adminKeys.remove(target);
    final config = _settingsFields(await _readCatalogWire(spec, target));
    for (final change in updates.entries) {
      if (section == RadioFieldSection.bluetooth &&
          change.key == '3' &&
          !RegExp(r'^\d{6}$').hasMatch(change.value)) {
        throw const FormatException('Expected a six-digit PIN');
      }
      fields[change.key]!.write(config, change.value);
    }
    if (content != null && await _readAuxiliary(auxiliary!, target) == null) {
      throw const FormatException('Unsupported module text');
    }
    final mayRestart =
        target == null &&
        updates.isNotEmpty &&
        !const {
          RadioFieldSection.deviceUi,
          RadioFieldSection.statusMessage,
          RadioFieldSection.beacon,
        }.contains(section);
    if (content != null) {
      await _admin(
        CodedBufferWriter()
          ..writeField(auxiliary!.set, PbFieldType.OY, utf8.encode(content)),
        reply: false,
        target: target,
      );
    }
    if (updates.isNotEmpty) {
      final wrap = CodedBufferWriter()
        ..writeField(spec.field, PbFieldType.OY, _settingsBytes(config));
      final command = CodedBufferWriter();
      if (!spec.module && spec.field == 10) {
        command.writeField(46, PbFieldType.OY, _settingsBytes(config));
      } else {
        command.writeField(
          spec.module ? 35 : 34,
          PbFieldType.OY,
          wrap.toBuffer(),
        );
      }
      await _admin(
        command,
        reply: false,
        target: target,
        mayRestart: mayRestart,
      );
    }
    await _verifyWrite((radio) async {
      if (updates.isNotEmpty) {
        final actual = _settingsFields(
          await radio._readCatalogWire(spec, target),
        );
        if (updates.keys.any(
          (key) => fields[key]!.read(actual) != fields[key]!.read(config),
        )) {
          throw StateError('Meshtastic did not confirm the setting');
        }
      }
      if (content != null &&
          await radio._readAuxiliary(auxiliary!, target) != content) {
        throw StateError('Meshtastic did not confirm the module text');
      }
    }, mayRestart: mayRestart);
  });

  @override
  Future<List<RadioField>> readTelemetry() async {
    if (!_ready || _closed) throw StateError('Meshtastic radio disconnected');
    final readings = <RadioField>[];
    void reading(
      int tag,
      String id,
      String title,
      String russian,
      String units, {
      bool floating = false,
      int decimals = 0,
      int? maximum,
    }) {
      if (!_deviceMetrics.containsKey(tag)) return;
      final value = _deviceMetrics.number(tag);
      if (maximum != null && value > maximum) return;
      final numeric = floating
          ? (ByteData(4)..setUint32(0, value)).getFloat32(0)
          : value;
      if (!numeric.isFinite) return;
      readings.add(
        RadioField(
          id,
          title,
          russian,
          numeric.toStringAsFixed(decimals),
          editable: false,
          units: units,
          section: RadioFieldSection.telemetry,
        ),
      );
    }

    reading(1, 'charge', 'Battery level', 'Заряд батареи', '%', maximum: 100);
    reading(
      2,
      'voltage',
      'Battery voltage',
      'Напряжение батареи',
      'V',
      floating: true,
      decimals: 2,
    );
    reading(
      3,
      'channel',
      'Channel utilization',
      'Загрузка канала',
      '%',
      floating: true,
      decimals: 1,
    );
    reading(
      4,
      'airtime',
      'Transmit airtime',
      'Эфирное время передачи',
      '%',
      floating: true,
      decimals: 1,
    );
    reading(5, 'uptime', 'Uptime', 'Время работы', 's');
    return readings;
  }

  @override
  int textLimit(Peer peer) => MeshtasticAdapter.maximumTextBytes;

  @override
  String nextMessageReference() {
    int packet;
    do {
      packet = 1 + _random.nextInt(0x7ffffffe);
    } while (_sent.containsKey(packet));
    return '$packet';
  }

  (int, int) _recipient(Peer peer) {
    if (!_ready || _closed || !peer.writable) {
      throw StateError('Meshtastic radio cannot send to this recipient');
    }
    return peer.channel
        ? (meshBroadcast, int.parse(peer.id.substring(3)))
        : (int.parse(peer.id.substring(5)), _primaryChannel);
  }

  @override
  Future<void> react(Peer peer, String target, String emoji) async {
    final (destination, channel) = _recipient(peer);
    await link.write(
      _tx,
      meshtasticTextPacket(
        int.parse(nextMessageReference()),
        destination,
        channel,
        emoji,
        replyTo: int.parse(target),
        reaction: true,
      ),
    );
  }

  @override
  Future<void> send(Peer peer, MeshMessage message) async {
    final (destination, channel) = _recipient(peer);
    final packet = int.parse(message.remoteId ?? nextMessageReference());
    _sent[packet] = (id: message.id, destination: destination);
    if (_sent.length > 128) {
      final oldest = _sent.keys.first;
      _sent.remove(oldest);
      _confirmed.remove(oldest);
    }
    try {
      await link.write(
        _tx,
        meshtasticTextPacket(
          packet,
          destination,
          channel,
          message.text,
          replyTo: message.replyTo == null ? null : int.parse(message.replyTo!),
        ),
      );
      _emit(
        MessagePacketUpdated(
          message.id,
          MessagePacket(
            sender: _self == 0 ? null : 'node:$_self',
            recipient: peer.channel ? null : 'node:$destination',
            channel: channel,
          ),
        ),
      );
    } catch (_) {
      _sent.remove(packet);
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final admin = _adminReply;
    if (admin != null && !admin.isCompleted) {
      admin.completeError(StateError('Radio disconnected'));
    }
    if (_nodeRequest case final pending? when !pending.reply.isCompleted) {
      pending.reply.completeError(StateError('Radio disconnected'));
    }
    if (_directorySync case final sync? when !sync.isCompleted) {
      sync.completeError(StateError('Radio disconnected'));
    }
    await _disconnect?.cancel();
    await _notifications?.cancel();
    await link.close();
    await _events.close();
  }
}

class _TasticRemoteSettings
    implements
        RadioSettingsSession,
        RadioSettingsCatalog,
        RadioSettingsIndex,
        RemoteNodePower,
        RadioPositionSession {
  _TasticRemoteSettings(this.session, this.target);

  final _TasticSession session;
  final int target;

  @override
  Future<void> setFixedPosition(NodePosition position) =>
      session._writeFixedPosition(position, target);

  @override
  Future<void> setPower({required bool reboot}) =>
      session._serialAdmin(() async {
        if (!session._adminKeys.containsKey(target)) {
          await session._config(0, 1, target);
        }
        await session._admin(
          CodedBufferWriter()..writeField(reboot ? 97 : 98, PbFieldType.O3, 2),
          reply: false,
          target: target,
        );
      });

  @override
  Future<List<RadioField>> readSettings() => session._readSettings(target);

  @override
  Future<void> writeSettings(Map<String, String> values) =>
      session._writeSettings(values, target);
  @override
  List<RadioFieldSection> get extraSettings => session._sections(target);

  @override
  Iterable<RadioSettingName> settingNames(RadioFieldSection section) =>
      session._settingNames(section, target);

  @override
  Future<List<RadioField>> readSection(RadioFieldSection section) =>
      session._readSection(section, target);

  @override
  Future<void> writeSection(
    RadioFieldSection section,
    Map<String, String> values,
  ) => session._writeSection(section, values, target);
}
