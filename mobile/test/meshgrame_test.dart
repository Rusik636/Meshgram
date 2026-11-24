// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart' hide Radio;
import 'package:flutter/cupertino.dart' show CupertinoPageTransition;
import 'package:flutter/rendering.dart'
    show RenderParagraph, RenderRepaintBoundary, SliverPaintOrder;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:protobuf/protobuf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshgrame/main.dart';
import 'package:meshgrame/local_notifications.dart';
import 'package:meshgrame/mesh/contact_attachment.dart';
import 'package:meshgrame/mesh/controller.dart';
import 'package:meshgrame/mesh/message_packet.dart';
import 'package:meshgrame/mesh/network.dart';
import 'package:meshgrame/mesh/nodes.dart';
import 'package:meshgrame/mesh/radio_outbox.dart';
import 'package:meshgrame/mesh/route_trace.dart';
import 'package:meshgrame/mesh/store.dart';
import 'package:meshgrame/radio/meshcore.dart';
import 'package:meshgrame/radio/meshtastic.dart';
import 'package:meshgrame/ui/radio_settings.dart';
import 'package:meshgrame/ui/about.dart';
import 'package:meshgrame/ui/signal.dart';
import 'package:meshgrame/ui/radio_avatar.dart';
import 'package:meshgrame/ui/profile_page.dart';
import 'package:meshgrame/ui/profile_wallpaper.dart';
import 'package:meshgrame/ui/swipe_actions.dart';
import 'package:meshgrame/ui/radio_discovery.dart';
import 'package:meshgrame/ui/navigation.dart';
import 'package:meshgrame/ui/ios_control.dart';
import 'package:meshgrame/ui/contact_qr.dart';
import 'package:meshgrame/ui/position_picker.dart';
import 'package:meshgrame/ui/style.dart';
import 'package:meshgrame/ui/nodes.dart';
import 'package:meshgrame/ui/notification_settings.dart';
import 'package:meshgrame/ui/node_actions.dart';
import 'package:meshgrame/ui/chat.dart';
import 'package:meshgrame/ui/chat_folders.dart';
import 'package:meshgrame/ui/channel_avatars.dart';
import 'package:meshgrame/ui/emoji_picker.dart';
import 'package:meshgrame/ui/emoji_text.dart';
import 'package:meshgrame/ui/message_details.dart';
import 'package:meshgrame/ui/message_input.dart';
import 'package:meshgrame/ui/message_reactions.dart';
import 'package:meshgrame/ui/quick_phrases.dart';
import 'package:meshgrame/ui/qr_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _TestEmojiBundle extends CachingAssetBundle {
  _TestEmojiBundle(this.catalog);

  final String catalog;

  @override
  Future<ByteData> load(String key) => rootBundle.load(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      key == 'assets/emoji/unicode17.json'
      ? Future.value(catalog)
      : rootBundle.loadString(key, cache: cache);
}

class _TestBoardBundle extends CachingAssetBundle {
  _TestBoardBundle(this.catalog);
  final String catalog;

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      key == 'assets/boards/catalog.json'
      ? Future.value(catalog)
      : rootBundle.loadString(key, cache: cache);

  @override
  Future<ByteData> load(String key) => rootBundle.load(key);
}

class _TestCamera extends MobileScannerPlatform {
  @override
  Stream<BarcodeCapture?> get barcodesStream => const Stream.empty();

  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async =>
      const MobileScannerViewAttributes(
        cameraDirection: CameraFacing.back,
        currentTorchMode: TorchState.off,
        size: Size(640, 480),
      );

  @override
  Widget buildCameraView() => const SizedBox(
    width: 640,
    height: 480,
    child: ColoredBox(color: Colors.blueGrey),
  );

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Future<void> dispose() async {}
}

class _TestTransport implements RadioTransport {
  final links = <_TestLink>[];
  List<DiscoveredRadio> found = [];
  Map<String, String> scanned = {};
  @override
  Future<void> scan(
    Map<String, String> services,
    void Function(List<DiscoveredRadio>) update,
  ) async {
    scanned = services;
    update(found);
  }

  @override
  Future<void> stopScan() async {}
  @override
  Future<RadioLink> connect(Radio radio, String service) async {
    final link = _TestLink();
    links.add(link);
    return link;
  }
}

class _BluetoothTestTransport extends _TestTransport
    implements BluetoothControl {
  bool off = true;

  @override
  Future<void> enableBluetooth() async => off = false;

  @override
  Future<void> scan(
    Map<String, String> services,
    void Function(List<DiscoveredRadio>) update,
  ) async {
    if (off) throw BluetoothProblem.off;
    await super.scan(services, update);
  }

  @override
  Future<RadioLink> connect(Radio radio, String service) async {
    if (off) throw BluetoothProblem.off;
    return super.connect(radio, service);
  }
}

class _PendingConnectTransport extends _TestTransport {
  final result = Completer<RadioLink>();

  @override
  Future<RadioLink> connect(Radio radio, String service) => result.future;
}

class _TestLink implements RadioLink, RadioSignalLink {
  bool closed = false;
  @override
  Future<int> readSignalRssi() async => -62;
  @override
  Future<void> close() async => closed = true;
  @override
  bool contains(String characteristic) => false;
  @override
  Stream<void> get disconnected => const Stream.empty();
  @override
  Future<Uint8List> read(String characteristic) async => Uint8List(0);
  @override
  Future<StreamSubscriptionHandle> subscribe(
    String characteristic,
    void Function(Uint8List) onFrame,
  ) => throw UnimplementedError();
  @override
  Future<void> write(String characteristic, List<int> bytes) async {}
}

class _ProtocolTestTransport extends _TestTransport {
  _ProtocolTestTransport(this.link);
  final RadioLink link;

  @override
  Future<RadioLink> connect(Radio radio, String service) async => link;
}

class _ReconnectTestTransport extends _TestTransport {
  _ReconnectTestTransport(this.boots);

  final List<RadioLink? Function()> boots;
  final attempts = <Radio>[];

  @override
  Future<RadioLink> connect(Radio radio, String service) async {
    attempts.add(radio);
    return boots.removeAt(0)() ?? (throw const RadioNotNearby());
  }
}

class _TestLanTransport implements RadioLanTransport {
  _TestLanTransport(this.link, this.radio, {this.open});
  final RadioLink link;
  final Radio radio;
  final Future<RadioLink> Function(LanEndpoint)? open;
  LanEndpoint? endpoint;
  LanRadioProtocol? wire;

  @override
  Future<void> scan(
    Map<String, LanRadioProtocol> protocols,
    void Function(List<DiscoveredRadio>) update,
  ) async {
    expect(protocols[radio.network]?.bonjourService, '_meshtastic._tcp');
    update([(radio: radio, rssi: 0)]);
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<RadioLink> connect(
    LanEndpoint endpoint,
    LanRadioProtocol protocol,
  ) async {
    this.endpoint = endpoint;
    wire = protocol;
    return open == null ? link : open!(endpoint);
  }
}

class _FakeAdapter implements NetworkAdapter {
  _FakeAdapter(this.id);
  @override
  final String id;
  @override
  String get label => id;
  @override
  String get service => id;
  final sessions = <_FakeNetwork>[];
  @override
  NetworkSession createSession(RadioLink link) {
    final session = _FakeNetwork(link);
    sessions.add(session);
    return session;
  }
}

const _peer = (
  id: 'shared',
  name: 'Local channel',
  writable: true,
  channel: true,
);

class _FakeNetwork
    implements
        NetworkSession,
        RadioSettingsSession,
        RadioTelemetrySession,
        RadioSettingsCatalog,
        RadioOnboardingSession,
        RadioChannelSession {
  _FakeNetwork(this.link);
  final RadioLink link;
  final stream = StreamController<NetworkEvent>.broadcast(sync: true);
  int setupChecks = 0;
  bool needsSetup = true;
  @override
  Stream<NetworkEvent> get events => stream.stream;
  @override
  Future<void> start() async => stream.add(const DirectoryUpdate([_peer]));
  @override
  int textLimit(Peer peer) => 60;
  bool autoAcknowledge = true;
  bool failSends = false;
  Completer<void>? sendCompletion;
  @override
  Future<void> send(Peer peer, MeshMessage message) async {
    if (sendCompletion case final completion?) await completion.future;
    if (failSends) throw StateError('Test transport declined the message');
    if (autoAcknowledge) {
      stream.add(DeliveryUpdate(message.id, Delivery.acknowledged));
    }
  }

  String radioName = 'Test node';
  @override
  Future<List<RadioField>> readSettings() async => [
    RadioField('name', 'Node name', 'Имя узла', radioName),
    const RadioField(
      'frequency',
      'Frequency',
      'Частота',
      '868.1',
      section: RadioFieldSection.lora,
    ),
  ];
  @override
  Future<List<RadioField>> readTelemetry() async => [
    const RadioField(
      'battery',
      'Battery voltage',
      'Напряжение батареи',
      '3.79',
      section: RadioFieldSection.telemetry,
      editable: false,
      units: 'V',
    ),
  ];
  bool telemetrySettings = false;
  @override
  List<RadioFieldSection> get extraSettings =>
      telemetrySettings ? [RadioFieldSection.sensors] : [];
  @override
  Future<List<RadioField>> readSection(RadioFieldSection section) async => [
    const RadioField(
      'interval',
      'Sample interval',
      'Интервал измерений',
      '30',
      section: RadioFieldSection.sensors,
    ),
  ];
  @override
  Future<void> writeSection(
    RadioFieldSection section,
    Map<String, String> values,
  ) async {}
  @override
  Future<List<RadioSetupStep>> setupSteps() async {
    setupChecks++;
    if (!needsSetup) return [];
    return const [
      (
        title: 'Name your radio',
        russian: 'Назовите рацию',
        fields: [RadioField('name', 'Node name', 'Имя узла', '')],
      ),
      (
        title: 'Check radio settings',
        russian: 'Проверьте параметры LoRa',
        fields: [RadioField('frequency', 'Frequency', 'Частота', '868.1')],
      ),
    ];
  }

  bool acceptsInvitations = false;
  ChannelRequest? lastChannelRequest;

  @override
  List<ChannelAction> get channelActions => [
    ChannelAction.createPrivate,
    if (acceptsInvitations) ChannelAction.invitation,
  ];

  @override
  Future<ChannelProvision> addChannel(ChannelRequest request) async {
    lastChannelRequest = request;
    return (
      peer: (id: 'ch:2', name: request.name, channel: true, writable: true),
      invitation: null,
    );
  }

  @override
  Future<void> writeSettings(Map<String, String> values) async {
    radioName = values['name'] ?? radioName;
  }

  @override
  Future<void> close() async {
    await stream.close();
    await link.close();
  }
}

class _FrameSubscription implements StreamSubscriptionHandle {
  @override
  Future<void> cancel() async {}
}

class _CoreSettingsLink extends _TestLink {
  late void Function(Uint8List) reply;
  final commands = <List<int>>[];
  List<int>? importedContact;
  var power = 14;
  var batteryMillivolts = 3754;
  var name = 'Field node';
  int firmwareProtocol = 9;
  bool wifiEnabled = true;
  var latitude = 0,
      longitude = 1250000,
      advertPosition = 0,
      telemetryFlags = 5,
      contactFlags = 3;
  bool includeRepeater = false;
  bool delayRouteDiscovery = false;
  bool rejectContactCatalog = false;
  bool staleAdminPath = false;
  int deviceClock = 1577836800, lastCliTimestamp = 0;
  int repeaterLastAdvert = 0;
  int contactType = 2, storedContactFlags = 0x24;
  String? cliResponse;
  static final repeaterKey = List<int>.generate(32, (i) => i + 1);

  void replyRouteDiscovery() => reply(
    Uint8List.fromList([0x8d, 0, ...repeaterKey.take(6), 0x41, 0x12, 0xab, 0]),
  );
  final channels = <int, List<int>>{
    0: [
      ...'Public'.codeUnits,
      ...List.filled(26, 0),
      0x8b,
      0x33,
      0x87,
      0xe9,
      0xc5,
      0xcd,
      0xea,
      0x6a,
      0xc9,
      0xe5,
      0xed,
      0xba,
      0xa1,
      0x15,
      0xcd,
      0x72,
    ],
  };

  @override
  Future<StreamSubscriptionHandle> subscribe(
    String characteristic,
    void Function(Uint8List) onFrame,
  ) async {
    reply = onFrame;
    return _FrameSubscription();
  }

  @override
  Future<void> write(String characteristic, List<int> bytes) async {
    commands.add(List.of(bytes));
    final info = ByteData(58)
      ..setUint8(0, 5)
      ..setInt8(2, power)
      ..setUint8(3, 22)
      ..setInt32(36, latitude, Endian.little)
      ..setInt32(40, longitude, Endian.little)
      ..setUint8(45, advertPosition)
      ..setUint8(46, telemetryFlags)
      ..setUint8(47, contactFlags)
      ..setUint32(48, 868100, Endian.little)
      ..setUint32(52, 62500, Endian.little)
      ..setUint8(56, 8)
      ..setUint8(57, 5);
    if ((bytes.first == 4 || bytes.first == 30) && includeRepeater) {
      final peer = Uint8List(148)
        ..[0] = 3
        ..setRange(1, 33, repeaterKey)
        ..[33] = contactType
        ..[34] = storedContactFlags
        ..[35] = 1
        ..[36] = 0x23
        ..setRange(100, 107, 'Hilltop'.codeUnits);
      ByteData.sublistView(peer)
        ..setUint32(132, repeaterLastAdvert, Endian.little)
        ..setUint32(
          144,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          Endian.little,
        );
      reply(peer);
      if (bytes.first == 30) return;
    }
    if (bytes.first == 9) {
      storedContactFlags = bytes[34];
      importedContact = [3, ...bytes.skip(1)];
    }
    if (bytes.first == 30 && importedContact != null) {
      reply(Uint8List.fromList(importedContact!));
      return;
    }
    if (bytes.first == 13) staleAdminPath = false;
    if (bytes.first == 52) {
      expect(bytes, [52, 0, ...repeaterKey]);
      reply(Uint8List.fromList([6, 0, 0, 0, 0, 0, 0, 0, 0, 0]));
      reply(Uint8List.fromList([0x8d, 0, ...List.filled(6, 99), 0, 0]));
      if (!delayRouteDiscovery) replyRouteDiscovery();
      return;
    }
    if (bytes.first == 36) {
      final tag = bytes.sublist(1, 5);
      final path = bytes.sublist(10);
      expect(bytes[9], 1);
      expect(path, [0x12, 0xab, ...repeaterKey.take(2)]);
      reply(Uint8List.fromList([6, 0, ...tag, 0, 0, 0, 0]));
      reply(
        Uint8List.fromList([
          0x89,
          0,
          path.length,
          1,
          ...tag,
          0,
          0,
          0,
          0,
          ...path,
          32,
          252,
          16,
        ]),
      );
      return;
    }
    if (bytes.first == 50) {
      expect(bytes, [50, ...repeaterKey, 3, 0, 0, 0, 0]);
      reply(Uint8List.fromList([6, 0, 10, 0, 0, 0, 0, 0, 0, 0]));
      reply(Uint8List.fromList([0x8c, 0, 11, 0, 0, 0, 1, 116, 0, 1]));
      reply(Uint8List.fromList([0x8c, 0, 10, 0, 0, 0, 1, 116, 1, 0x7a]));
      return;
    }
    if (bytes.first == 26 || bytes.first == 27) {
      expect(bytes.sublist(1, 33), repeaterKey);
      final stale = bytes.first == 26 && staleAdminPath;
      reply(Uint8List.fromList([6, stale ? 0 : 1, 0, 0, 0, 0, 0, 0, 0, 0]));
      if (stale) return;
      // An unrelated node's push must never finish the request.
      reply(Uint8List.fromList([0x86, 0, ...List.filled(6, 99)]));
      final prefix = repeaterKey.take(6);
      if (bytes.first == 26) {
        reply(Uint8List.fromList([0x85, 1, ...prefix]));
      } else {
        final status = ByteData(44)
          ..setUint16(0, 3926, Endian.little)
          ..setInt16(6, -106, Endian.little)
          ..setInt16(42, 19, Endian.little);
        reply(
          Uint8List.fromList([
            0x87,
            0,
            ...prefix,
            ...status.buffer.asUint8List(),
          ]),
        );
      }
      return;
    }
    if (bytes.first == 2 && bytes[1] == 1) {
      expect(bytes.sublist(7, 13), repeaterKey.take(6));
      final stamp = MeshCoreFrames.u32(Uint8List.fromList(bytes), 3);
      expect(stamp, greaterThanOrEqualTo(deviceClock));
      expect(stamp, greaterThan(lastCliTimestamp));
      lastCliTimestamp = stamp;
      cliResponse = switch (String.fromCharCodes(
        bytes.skip(13).takeWhile((ch) => ch != 0),
      )) {
        'get name' => '> Hilltop',
        'get repeat' => '> on',
        'get radio' => '> 868.100,62.5,8,5',
        _ => 'OK',
      };
      reply(Uint8List.fromList([6, 0, 0, 0, 0, 0, 0, 0, 0, 0]));
      return;
    }
    if (cliResponse case final answer? when bytes.first == 10) {
      cliResponse = null;
      reply(
        Uint8List.fromList([
          16,
          0,
          0,
          0,
          ...repeaterKey.take(6),
          0,
          1,
          0,
          0,
          0,
          0,
          ...answer.codeUnits,
        ]),
      );
      return;
    }
    if (bytes.first == 66) {
      final String cli = String.fromCharCodes(bytes.skip(1));
      if (cli.startsWith('set wifi.enabled ')) {
        wifiEnabled = cli.endsWith('1');
      }
      final answer = switch (cli) {
        'get wifi.enabled' => '> ${wifiEnabled ? 1 : 0}',
        'get wifi.ssid' => '> Lab Wi-Fi',
        'get wifi.pwd' => '> pass',
        'get wifi.status' => '> connected',
        'get wifi.ip' => '> 192.168.1.50',
        'set wifi.enabled 0' || 'set wifi.enabled 1' => 'OK',
        _ => null,
      };
      reply(
        Uint8List.fromList(answer == null ? [1, 1] : [29, ...answer.codeUnits]),
      );
      return;
    }
    final frame = switch (bytes.first) {
      1 => [...info.buffer.asUint8List(), ...name.codeUnits],
      22 => [13, firmwareProtocol, 3, 3, ...List.filled(76, 0), 1],
      4 => rejectContactCatalog ? [1, 3] : [4],
      5 => [9, ...MeshCoreFrames.littleEndian32(deviceClock)],
      31 => [18, bytes[1], ...channels[bytes[1]] ?? List.filled(48, 0)],
      10 => [10],
      20 => [12, batteryMillivolts & 0xff, batteryMillivolts >> 8],
      40 || 59 || 64 => [1, 1],
      _ => [0],
    };
    if (bytes.first == 6) {
      deviceClock = MeshCoreFrames.u32(Uint8List.fromList(bytes), 1);
    }
    if (bytes.first == 32) channels[bytes[1]] = bytes.sublist(2);
    if (bytes.first == 12) power = bytes[1].toSigned(8);
    if (bytes.first == 8) name = String.fromCharCodes(bytes.skip(1));
    if (bytes.first == 14) {
      final data = ByteData.sublistView(Uint8List.fromList(bytes));
      latitude = data.getInt32(1, Endian.little);
      longitude = data.getInt32(5, Endian.little);
    }
    if (bytes.first == 38) {
      contactFlags = bytes[1];
      telemetryFlags = bytes[2];
      advertPosition = bytes[3];
    }
    reply(Uint8List.fromList(frame));
  }
}

UnknownFieldSet _fields(List<int> bytes) =>
    UnknownFieldSet()..mergeFromCodedBufferReader(CodedBufferReader(bytes));

int _varint(UnknownFieldSet packet, int field) =>
    packet.getField(field)?.varints.firstOrNull?.toInt() ?? 0;
int _fixed(UnknownFieldSet packet, int field) =>
    packet.getField(field)?.fixed32s.firstOrNull ?? 0;
List<int> _buffer(UnknownFieldSet packet, int field) =>
    packet.getField(field)?.lengthDelimited.firstOrNull ?? [];

Future<List<RadioField>> _traceResult(
  NetworkSession session,
  Peer peer,
  int request, {
  bool signals = false,
}) async {
  final answer = session.events
      .where((event) => event is RouteTraceReceived)
      .cast<RouteTraceReceived>()
      .firstWhere(
        (event) =>
            event.request == request &&
            event.peer == peer.id &&
            (!signals || event.fields.any((field) => field.hops.isNotEmpty)),
      );
  await (session as NetworkRouteTracing).startRouteTrace(peer, request);
  return (await answer).fields;
}

class _TasticSettingsLink extends _TestLink {
  final frames = <Uint8List>[];
  List<int>? importedContact;
  var deviceRead = false;
  bool includeRemote = false;
  bool delayRouteReply = false;
  final traceRequests = <int>[];
  int remoteLastHeard = 0;
  int remoteRole = 0;
  final nodeCommands = <(int, int, int)>[];
  (int, int)? fixedPosition;
  List<int> remoteOwner = [];
  final remoteKey = [9, 8, 7, 6];
  final channels = <int, List<int>>{};
  String? firmware;
  int excludedModules = 0;
  final localPublicKey = List<int>.filled(32, 3);
  List<int>? hardwareId;
  List<int>? remoteHardware;
  final _disconnected = StreamController<void>.broadcast();
  bool rebootOnNetworkWrite = false, _rebooting = false;
  int networkWrites = 0;

  @override
  Stream<void> get disconnected => _disconnected.stream;

  @override
  Future<void> close() async {
    await super.close();
    await _disconnected.close();
  }

  List<int> network =
      (CodedBufferWriter()
            ..writeField(9, PbFieldType.OY, 'log.local'.codeUnits)
            ..writeField(99, PbFieldType.OU3, 71))
          .toBuffer();
  List<int> lora =
      (CodedBufferWriter()
            ..writeField(1, PbFieldType.OB, true)
            ..writeField(8, PbFieldType.OU3, 3)
            ..writeField(99, PbFieldType.OY, [1, 2, 3]))
          .toBuffer();
  List<int> owner =
      (CodedBufferWriter()
            ..writeField(2, PbFieldType.OY, 'Long'.codeUnits)
            ..writeField(3, PbFieldType.OY, 'AB'.codeUnits)
            ..writeField(6, PbFieldType.OB, true)
            ..writeField(9, PbFieldType.OB, true))
          .toBuffer();
  final key = [9, 7, 1, 8];

  late void Function(Uint8List) notify;

  @override
  Future<StreamSubscriptionHandle> subscribe(
    String characteristic,
    void Function(Uint8List) onFrame,
  ) async {
    notify = onFrame;
    return _FrameSubscription();
  }

  void incoming(
    int port,
    List<int> bytes, {
    int from = 42,
    int id = 19,
    int? replyTo,
    int? request,
    bool reacts = false,
    int to = 123,
    int? receivedAt,
    double? receivedSnr,
    int? receivedRssi,
    int? hopStart,
    int? hopLimit,
    int? relaySuffix,
  }) {
    final data = CodedBufferWriter()
      ..writeField(1, PbFieldType.OU3, port)
      ..writeField(2, PbFieldType.OY, bytes);
    if (request != null) data.writeField(6, PbFieldType.OF3, request);
    if (replyTo != null) data.writeField(7, PbFieldType.OF3, replyTo);
    if (reacts) data.writeField(8, PbFieldType.OF3, 1);
    final packet = CodedBufferWriter()
      ..writeField(1, PbFieldType.OF3, from)
      ..writeField(2, PbFieldType.OF3, to)
      ..writeField(4, PbFieldType.OY, data.toBuffer())
      ..writeField(6, PbFieldType.OF3, id);
    if (receivedSnr != null) packet.writeField(8, PbFieldType.OF, receivedSnr);
    if (receivedRssi != null) {
      packet.writeField(12, PbFieldType.O3, receivedRssi);
    }
    if (receivedAt != null) packet.writeField(7, PbFieldType.OF3, receivedAt);
    if (hopStart != null) packet.writeField(15, PbFieldType.OU3, hopStart);
    if (hopLimit != null) packet.writeField(9, PbFieldType.OU3, hopLimit);
    if (relaySuffix != null) {
      packet.writeField(19, PbFieldType.OU3, relaySuffix);
    }
    frames.add(
      (CodedBufferWriter()..writeField(2, PbFieldType.OY, packet.toBuffer()))
          .toBuffer(),
    );
    notify(Uint8List(0));
  }

  @override
  Future<Uint8List> read(String characteristic) async =>
      frames.isEmpty ? Uint8List(0) : frames.removeAt(0);

  @override
  Future<void> write(String characteristic, List<int> bytes) async {
    if (_rebooting) throw StateError('Radio rebooting');
    final wire = _fields(bytes);
    if (wire.hasField(3)) {
      final identity = CodedBufferWriter()..writeField(1, PbFieldType.OU3, 123);
      if (hardwareId case final id?) {
        identity.writeField(12, PbFieldType.OY, id);
      }
      if (firmware case final version?) {
        final metadata = CodedBufferWriter()
          ..writeField(1, PbFieldType.OY, version.codeUnits)
          ..writeField(4, PbFieldType.OB, true)
          ..writeField(9, PbFieldType.OU3, 43)
          ..writeField(12, PbFieldType.OU3, excludedModules);
        frames.add(
          (CodedBufferWriter()
                ..writeField(13, PbFieldType.OY, metadata.toBuffer())
                ..writeField(
                  6,
                  PbFieldType.OY,
                  (CodedBufferWriter()..writeField(4, PbFieldType.OY, network))
                      .toBuffer(),
                )
                ..writeField(
                  9,
                  PbFieldType.OY,
                  (CodedBufferWriter()..writeField(14, PbFieldType.OY, <int>[]))
                      .toBuffer(),
                ))
              .toBuffer(),
        );
        if (remoteHardware case final pins?) {
          final module = CodedBufferWriter()
            ..writeField(9, PbFieldType.OY, pins);
          frames.add(
            (CodedBufferWriter()
                  ..writeField(9, PbFieldType.OY, module.toBuffer()))
                .toBuffer(),
          );
        }
        final user = CodedBufferWriter()
          ..writeField(2, PbFieldType.OY, 'Mesh'.codeUnits)
          ..writeField(8, PbFieldType.OY, localPublicKey);
        final node = CodedBufferWriter()
          ..writeField(1, PbFieldType.OU3, 123)
          ..writeField(2, PbFieldType.OY, user.toBuffer());
        frames.add(
          (CodedBufferWriter()
                ..writeField(3, PbFieldType.OY, identity.toBuffer())
                ..writeField(4, PbFieldType.OY, node.toBuffer()))
              .toBuffer(),
        );
      }
      for (var slot = 0; slot < 4; slot++) {
        final channel =
            (CodedBufferWriter()
                  ..writeField(1, PbFieldType.OU3, slot)
                  ..writeField(3, PbFieldType.OU3, slot == 0 ? 1 : 0))
                .toBuffer();
        channels[slot] = channel;
        frames.add(
          (CodedBufferWriter()..writeField(10, PbFieldType.OY, channel))
              .toBuffer(),
        );
      }
      if (includeRemote) {
        final user = CodedBufferWriter()
          ..writeField(2, PbFieldType.OY, 'Remote'.codeUnits)
          ..writeField(3, PbFieldType.OY, 'RM'.codeUnits)
          ..writeField(7, PbFieldType.OU3, remoteRole)
          ..writeField(8, PbFieldType.OY, List.filled(32, 2));
        remoteOwner = user.toBuffer();
        final node = CodedBufferWriter()
          ..writeField(1, PbFieldType.OU3, 42)
          ..writeField(2, PbFieldType.OY, user.toBuffer())
          ..writeField(5, PbFieldType.OF3, remoteLastHeard)
          ..writeField(7, PbFieldType.OU3, 2)
          ..writeField(8, PbFieldType.OB, true)
          ..writeField(9, PbFieldType.OU3, 0)
          ..writeField(10, PbFieldType.OB, true);
        frames.add(
          (CodedBufferWriter()..writeField(4, PbFieldType.OY, node.toBuffer()))
              .toBuffer(),
        );
      }
      if (importedContact case final contact?) {
        frames.add(
          (CodedBufferWriter()..writeField(4, PbFieldType.OY, contact))
              .toBuffer(),
        );
      }
      frames.add(
        (CodedBufferWriter()
              ..writeField(3, PbFieldType.OY, identity.toBuffer())
              ..writeField(7, PbFieldType.OU3, _varint(wire, 3)))
            .toBuffer(),
      );
      return;
    }
    final packet = _fields(_buffer(wire, 1));
    final payload = _fields(_buffer(packet, 4));
    final destination = _fixed(packet, 2);
    final port = _varint(payload, 1);
    if (port == 70) {
      final request = _fixed(packet, 6);
      expect(destination, 42);
      expect(_varint(payload, 3), 1);
      traceRequests.add(request);
      if (delayRouteReply) return;
      final route = CodedBufferWriter()
        ..writeField(1, PbFieldType.OF3, 43)
        ..writeField(1, PbFieldType.OF3, 44)
        ..writeField(2, PbFieldType.O3, 24)
        ..writeField(2, PbFieldType.O3, -128)
        ..writeField(2, PbFieldType.O3, -8)
        ..writeField(3, PbFieldType.OY, [45, 0, 0, 0])
        ..writeField(4, PbFieldType.OY, [12]);
      incoming(70, [], from: 41, request: request);
      incoming(70, [], request: request + 1);
      incoming(
        70,
        route.toBuffer(),
        request: request,
        receivedSnr: 4.5,
        receivedRssi: -107,
      );
      return;
    }
    if (port == 67) {
      final request = _fixed(packet, 6);
      final variant = _fields(_buffer(payload, 2));
      final metrics = CodedBufferWriter()
        ..writeField(
          1,
          PbFieldType.OF3,
          (ByteData(4)..setFloat32(0, 18.4)).getUint32(0),
        );
      expect(variant.hasField(3), isTrue);
      incoming(
        67,
        (CodedBufferWriter()..writeField(3, PbFieldType.OY, metrics.toBuffer()))
            .toBuffer(),
        request: request,
      );
      return;
    }
    if (port != 6) return;
    final remote = includeRemote && destination == 42;
    expect(destination, remote ? 42 : 123);
    expect(_varint(packet, 17), remote ? 1 : 0);
    final passkey = remote ? remoteKey : key;
    final admin = _fields(_buffer(payload, 2));
    if (admin.hasField(66)) {
      importedContact = _buffer(admin, 66);
      return;
    }
    if (admin.hasField(41)) {
      final position = _fields(_buffer(admin, 41));
      fixedPosition = (
        _fixed(position, 1).toSigned(32),
        _fixed(position, 2).toSigned(32),
      );
      return;
    }
    for (final field in [39, 40, 47, 48, 97, 98]) {
      if (!admin.hasField(field)) continue;
      nodeCommands.add((destination, field, _varint(admin, field)));
      if (remote) expect(_buffer(admin, 101), remoteKey);
      return;
    }
    if (admin.hasField(33)) {
      expect(_buffer(admin, 101), key);
      final channel = _buffer(admin, 33);
      final index = _varint(_fields(channel), 1);
      expect(
        _varint(_fields(channels[index]!), 3),
        _varint(_fields(channel), 3) == 2 ? 0 : 2,
      );
      channels[index] = channel;
      return;
    }
    if (admin.hasField(34)) {
      expect(_buffer(admin, 101), key);
      final config = _fields(_buffer(admin, 34));
      if (config.hasField(4)) {
        network = _buffer(config, 4);
        networkWrites++;
        if (rebootOnNetworkWrite) {
          _rebooting = true;
          _disconnected.add(null);
        }
      } else {
        lora = _buffer(config, 6);
      }
      return;
    }
    if (admin.hasField(35)) {
      final module = _fields(_buffer(admin, 35));
      if (module.hasField(9)) remoteHardware = _buffer(module, 9);
      return;
    }
    if (admin.hasField(32) && remote) {
      expect(_buffer(admin, 101), remoteKey);
      remoteOwner = _buffer(admin, 32);
      return;
    }
    if (admin.hasField(32)) {
      expect(_buffer(admin, 101), key);
      final update = _fields(_buffer(admin, 32));
      final old = _fields(owner);
      expect(_varint(update, 6), 1);
      expect(_varint(update, 9), 1);
      owner =
          (CodedBufferWriter()
                ..writeField(2, PbFieldType.OY, _buffer(update, 2))
                ..writeField(3, PbFieldType.OY, _buffer(old, 3))
                ..writeField(6, PbFieldType.OB, true)
                ..writeField(9, PbFieldType.OB, true))
              .toBuffer();
      return;
    }
    if (!_varint(payload, 3).isOdd) return;
    final response = CodedBufferWriter()
      ..writeField(101, PbFieldType.OY, passkey);
    if (admin.hasField(1)) {
      response.writeField(2, PbFieldType.OY, channels[_varint(admin, 1) - 1]!);
    } else if (admin.hasField(3)) {
      response.writeField(4, PbFieldType.OY, remote ? remoteOwner : owner);
    } else if (admin.hasField(5)) {
      final type = _varint(admin, 5);
      if (type == 0) deviceRead = true;
      final config = CodedBufferWriter()
        ..writeField(
          type == 3
              ? 4
              : type == 0
              ? 1
              : 6,
          PbFieldType.OY,
          type == 3
              ? network
              : type == 0
              ? <int>[]
              : lora,
        );
      response.writeField(6, PbFieldType.OY, config.toBuffer());
    } else if (admin.hasField(7) &&
        _varint(admin, 7) == 8 &&
        remoteHardware != null) {
      final module = CodedBufferWriter()
        ..writeField(9, PbFieldType.OY, remoteHardware!);
      response.writeField(8, PbFieldType.OY, module.toBuffer());
    }
    final answer = CodedBufferWriter()
      ..writeField(1, PbFieldType.OU3, 6)
      ..writeField(2, PbFieldType.OY, response.toBuffer())
      ..writeField(6, PbFieldType.OF3, _fixed(packet, 6));
    if (remote) {
      final unrelated = CodedBufferWriter()
        ..writeField(1, PbFieldType.OF3, 41)
        ..writeField(2, PbFieldType.OF3, 123)
        ..writeField(4, PbFieldType.OY, answer.toBuffer())
        ..writeField(17, PbFieldType.OB, true);
      frames.add(
        (CodedBufferWriter()
              ..writeField(2, PbFieldType.OY, unrelated.toBuffer()))
            .toBuffer(),
      );
    }
    final envelope = CodedBufferWriter()
      ..writeField(1, PbFieldType.OF3, destination)
      ..writeField(2, PbFieldType.OF3, 123)
      ..writeField(4, PbFieldType.OY, answer.toBuffer());
    if (remote) envelope.writeField(17, PbFieldType.OB, true);
    frames.add(
      (CodedBufferWriter()..writeField(2, PbFieldType.OY, envelope.toBuffer()))
          .toBuffer(),
    );
  }
}

void _reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
    'iOS Wi-Fi push hands off a muted chat and imports its messages once',
    (tester) async {
      const system = MethodChannel('meshgrame/notifications');
      const wifi = MethodChannel('meshgrame/wifi_push');
      final messenger = tester.binding.defaultBinaryMessenger;
      final published = <Object?>[];
      messenger.setMockMethodCallHandler(system, (call) async {
        if (call.method == 'permission') return 'enabled';
        if (call.method == 'publish') published.add(call.arguments);
        return null;
      });
      final radio = lanRadio('meshtastic', 'mesh.local', 4403, name: 'Field');
      final payload = CodedBufferWriter()
        ..writeField(1, PbFieldType.OU3, 1)
        ..writeField(2, PbFieldType.OY, 'Offline over Wi-Fi'.codeUnits);
      final packet = CodedBufferWriter()
        ..writeField(1, PbFieldType.OF3, 42)
        ..writeField(2, PbFieldType.OF3, 123)
        ..writeField(4, PbFieldType.OY, payload.toBuffer())
        ..writeField(6, PbFieldType.OF3, 716)
        ..writeField(9, PbFieldType.OU3, 2)
        ..writeField(15, PbFieldType.OU3, 4);
      final frame =
          (CodedBufferWriter()
                ..writeField(2, PbFieldType.OY, packet.toBuffer()))
              .toBuffer();
      final link = _TasticSettingsLink()..includeRemote = true;
      final notifications = LocalMessageNotifications();
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _ProtocolTestTransport(link),
        lanTransport: _TestLanTransport(link, radio),
        adapters: const [MeshtasticAdapter()],
        onIncomingMessage: notifications.received,
        isChatForeground: () => notifications.isForeground,
      );
      final acknowledged = <String>[];
      final snapshots = <Map<Object?, Object?>>[];
      var staged = false;
      messenger.setMockMethodCallHandler(wifi, (call) async {
        switch (call.method) {
          case 'status':
            return {'available': true, 'ssid': 'Field WiFi', 'active': true};
          case 'stage':
            staged = !controller.connected;
            snapshots.addAll(
              (call.arguments as List).cast<Map<Object?, Object?>>(),
            );
            return true;
          case 'resume':
            if (!staged) return [];
            return [
              for (final name in ['first', 'duplicate'])
                {
                  'file': name,
                  'radio': radioKey(radio),
                  'receivedAt': 1800000058123,
                  'frame': frame,
                },
            ];
          case 'acknowledge':
            acknowledged.addAll((call.arguments as List).cast<String>());
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(wifi, null);
        messenger.setMockMethodCallHandler(system, null);
      });

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await notifications.start(controller);
      try {
        await controller.connect(radio);
        expect(controller.connected, isTrue);
        expect(notifications.wifiPushSsid, 'Field WiFi');
        controller.toggleMute('node:42');
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(snapshots.single['muted'], ['node:42']);
        expect(snapshots.single['host'], 'mesh.local');
        await controller.store.setAutoConnect(false);

        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump();
        final messages = controller.cache!.messages;
        expect(messages.single.text, 'Offline over Wi-Fi');
        expect(messages.single.packet?.hops, 2);
        expect(messages.single.time.millisecondsSinceEpoch, 1800000058123);
        expect(controller.cache!.unread['node:42'], 1);
        expect(published, isEmpty);
        expect(acknowledged, ['first', 'duplicate']);
      } finally {
        notifications.dispose();
        controller.dispose();
        if (tester.binding.lifecycleState == AppLifecycleState.paused) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
      }
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'Android uses one bundled text run per emoji sequence and preserves original text',
    (tester) async {
      const text = 'Текст © ❤︎ 👩🏽‍💻 🙂‍↔️ 👁‍🗨 1️⃣ 🫩!';
      final span = emojiTextSpan(text);
      expect(span.toPlainText(), text);
      expect(
        span.children!
            .whereType<TextSpan>()
            .where((run) => run.style?.fontFamily == emojiFontFamily)
            .map((run) => run.text),
        ['👩🏽‍💻', '🙂‍↔️', '👁‍🗨', '1️⃣', '🫩'],
      );
      expect(
        emojiGlyphStyle(const TextStyle(fontSize: 24)).fontFamily,
        emojiFontFamily,
      );
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  for (final (platform, wifi) in [
    (TargetPlatform.android, false),
    (TargetPlatform.android, true),
    (TargetPlatform.iOS, false),
    (TargetPlatform.iOS, true),
  ]) {
    testWidgets(
      'notifies only for supported background messages over ${wifi ? 'local Wi-Fi' : 'BLE'}',
      (tester) async {
        final messenger = tester.binding.defaultBinaryMessenger;
        const channel = MethodChannel('meshgrame/notifications');
        const wifiChannel = MethodChannel('meshgrame/wifi_push');
        messenger.setMockMethodCallHandler(wifiChannel, (call) async {
          if (call.method == 'status') return {'available': false};
          return null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(wifiChannel, null),
        );
        final posted = <Map<Object?, Object?>>[];
        final service = <bool>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'permission':
              return 'enabled';
            case 'publish':
              posted.add(call.arguments as Map<Object?, Object?>);
            case 'connectionService':
              service.add(call.arguments as bool);
              return true;
          }
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final link = _TasticSettingsLink()..includeRemote = true;
        final radio = wifi
            ? lanRadio('meshtastic', 'mesh.local', 4403, name: 'Field')
            : (network: 'meshtastic', device: 'test-ble', name: 'Field');
        final notifications = LocalMessageNotifications();
        final controller = MeshController(
          store: MeshStore(await SharedPreferences.getInstance()),
          transport: _ProtocolTestTransport(link),
          lanTransport: wifi ? _TestLanTransport(link, radio) : null,
          adapters: const [MeshtasticAdapter()],
          onIncomingMessage: notifications.received,
          isChatForeground: () => notifications.isForeground,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await notifications.start(controller);
        await controller.connect(radio);
        await tester.pump();
        expect(controller.connected, isTrue);
        expect(service, platform == TargetPlatform.android ? [true] : isEmpty);

        final stopTracking = controller.trackChatViewport(
          radioKey(radio),
          'node:42',
          () => true,
        );
        addTearDown(stopTracking);
        link.incoming(1, 'While reading'.codeUnits, id: 711);
        await tester.pump();
        expect(posted, isEmpty);
        final visible = controller.messages('node:42').last;
        controller.readChatThrough(radioKey(radio), 'node:42', visible.id);
        expect(controller.cache?.unread['node:42'], isNull);

        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        link.incoming(1, 'From the radio'.codeUnits, id: 712);
        link.incoming(1, 'From the radio'.codeUnits, id: 712);
        await tester.pump();
        final canNotify = platform == TargetPlatform.android || !wifi;
        expect(posted, hasLength(canNotify ? 1 : 0));
        if (canNotify) {
          expect(posted.single['title'], 'Remote');
          expect(posted.single['body'], 'From the radio');
        }
        expect(controller.cache?.unread['node:42'], 1);

        controller.toggleMute('node:42');
        link.incoming(1, 'Muted'.codeUnits, id: 713);
        await tester.pump();
        expect(posted, hasLength(canNotify ? 1 : 0));
        expect(controller.cache?.unread['node:42'], 2);

        if (platform == TargetPlatform.android && wifi) {
          controller.toggleMute('node:42');
          notifications.setOption(NotificationSetting.direct, false);
          link.incoming(1, 'Category muted'.codeUnits, id: 714);
          await tester.pump();
          expect(posted, hasLength(1));

          controller.setNotificationException(radio, 'node:42', true);
          notifications.setOption(NotificationSetting.preview, false);
          notifications.setOption(NotificationSetting.names, false);
          notifications.setOption(NotificationSetting.directSound, false);
          link.incoming(1, 'Private preview'.codeUnits, id: 715);
          await tester.pump();
          expect(posted, hasLength(2));
          expect(posted.last['title'], 'Meshgram');
          expect(posted.last['body'], isNot(contains('Private preview')));
          expect(posted.last['sound'], false);
          expect(controller.unreadFor(radio), 4);
        }

        final disconnected = controller.disconnect();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        await disconnected;
        expect(
          service,
          platform == TargetPlatform.android ? [true, false] : isEmpty,
        );
        notifications.dispose();
        controller.dispose();
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  testWidgets(
    'Android notification Stop pauses all radios until the app is reopened',
    (tester) async {
      const channel = MethodChannel('meshgrame/notifications');
      final messenger = tester.binding.defaultBinaryMessenger;
      final serviceCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'permission':
            return 'enabled';
          case 'connectionService':
            serviceCalls.add(call);
            return true;
          case 'resumeConnectionService':
            serviceCalls.add(call);
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      const first = (network: 'test', device: '1', name: 'First');
      const second = (network: 'test', device: '2', name: 'Second');
      final store = MeshStore(await SharedPreferences.getInstance());
      final transport = _TestTransport();
      final controller = MeshController(
        store: store,
        transport: transport,
        adapters: [_FakeAdapter('test')],
      );
      final notifications = LocalMessageNotifications();
      final lifecycle = tester.binding.handleAppLifecycleStateChanged;
      lifecycle(AppLifecycleState.resumed);
      await notifications.start(controller);
      try {
        await controller.connect(first);
        await controller.connect(second);
        await tester.pump();
        expect(controller.connectedRadios, unorderedEquals([first, second]));
        expect(serviceCalls.single.arguments, true);

        lifecycle(AppLifecycleState.inactive);
        tester.binding.channelBuffers.push(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('backgroundStopped'),
          ),
          (_) {},
        );
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(controller.connectedRadios, isEmpty);
        expect(transport.links.every((link) => link.closed), isTrue);
        expect(
          store.connectedProfiles,
          unorderedEquals([radioKey(first), radioKey(second)]),
        );

        lifecycle(AppLifecycleState.resumed);
        await tester.pump();
        expect(controller.connectedRadios, isEmpty);
        expect(serviceCalls, hasLength(1));

        lifecycle(AppLifecycleState.inactive);
        lifecycle(AppLifecycleState.hidden);
        lifecycle(AppLifecycleState.paused);
        await tester.pump(const Duration(seconds: 16));
        expect(controller.connectedRadios, isEmpty);
        expect(serviceCalls, hasLength(1));

        lifecycle(AppLifecycleState.hidden);
        lifecycle(AppLifecycleState.inactive);
        lifecycle(AppLifecycleState.resumed);
        await tester.pump();
        expect(serviceCalls.map((call) => call.method), [
          'connectionService',
          'resumeConnectionService',
          'connectionService',
        ]);
        expect(controller.connectedRadios, unorderedEquals([first, second]));
        expect(serviceCalls.last.arguments, true);
      } finally {
        notifications.dispose();
        controller.dispose();
      }
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'notification settings expose category exceptions and hold at a narrow width',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshCoreAdapter(), MeshtasticAdapter()],
        preview: true,
      );
      final notifications = LocalMessageNotifications();
      await notifications.start(controller);
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: const MeshStyle(false).theme(),
            home: NotificationSettingsPage(
              controller: controller,
              notifications: notifications,
              configureWifi: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('All radios'), findsOneWidget);
        await tester.tap(find.text('Direct chats'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add exception'));
        await tester.pumpAndSettle();
        final radio = controller.radios.first;
        final peer = controller
            .peersFor(radio)
            .firstWhere((item) => !item.channel);
        await tester.tap(find.text(peer.name).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mute notifications'));
        await tester.pumpAndSettle();
        expect(controller.notificationException(radio, peer.id), false);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        notifications.dispose();
        controller.dispose();
      }
    },
  );

  testWidgets('nodes show one list with the chat delete action', (
    tester,
  ) async {
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: const [MeshCoreAdapter(), MeshtasticAdapter()],
      preview: true,
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: const MeshStyle(false).theme(),
          home: MeshNodesPage(
            controller: controller,
            openChat: (_) async {},
            openProfile: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final peer = controller.nodes.first;
      await tester.drag(find.text(peer.name), const Offset(-240, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(controller.nodes.any((node) => node.id == peer.id), false);

      expect(find.byType(SegmentedButton<bool>), findsNothing);
      expect(find.text(controller.cache!.peers['ch:0']!.name), findsNothing);
      expect(find.byTooltip('Sort by'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    } finally {
      controller.dispose();
    }
  });

  test(
    'Meshtastic filters settings by firmware and preserves unknown fields',
    () async {
      for (final (firmware, ipv6, status, exclusions) in [
        ('2.7.15.old', false, false, 0),
        ('2.7.16.build', true, false, 0),
        ('2.8.0.next', true, true, 0),
        ('2.8.0.next', true, false, 0x8000),
      ]) {
        final link = _TasticSettingsLink()
          ..firmware = firmware
          ..excludedModules = exclusions;
        final session = const MeshtasticAdapter().createSession(link);
        final info = session.events
            .where((event) => event is DirectoryUpdate)
            .cast<DirectoryUpdate>()
            .first;
        try {
          await session.start();
          expect((await info).deviceInfo?.firmware, firmware);
          final catalog = session as RadioSettingsCatalog;
          expect(
            catalog.extraSettings.contains(RadioFieldSection.statusMessage),
            status,
          );
          expect(
            catalog.extraSettings,
            isNot(contains(RadioFieldSection.bluetooth)),
          );
          final fields = await catalog.readSection(
            RadioFieldSection.connectivity,
          );
          expect(fields.any((field) => field.id == '11'), ipv6);
          expect(fields.firstWhere((field) => field.id == '4').secret, isTrue);
          await catalog.writeSection(RadioFieldSection.connectivity, {
            '3': 'Mesh LAN',
            '8.1': '192.168.1.83',
          });
          final patched = _fields(link.network);
          expect(String.fromCharCodes(_buffer(patched, 3)), 'Mesh LAN');
          expect(_fixed(_fields(_buffer(patched, 8)), 1), 0x5301a8c0);
          expect(_varint(patched, 99), 71);
        } finally {
          await session.close();
        }
      }
    },
  );

  test(
    'Meshtastic edits structured options without losing other wire fields',
    () async {
      final gpio = CodedBufferWriter()
        ..writeField(1, PbFieldType.OU3, 12)
        ..writeField(2, PbFieldType.OY, 'Lamp'.codeUnits)
        ..writeField(3, PbFieldType.OU3, 1)
        ..writeField(9, PbFieldType.OU3, 25);
      final link = _TasticSettingsLink()
        ..firmware = '2.8.0.test'
        ..remoteHardware =
            (CodedBufferWriter()
                  ..writeField(1, PbFieldType.OB, true)
                  ..writeField(3, PbFieldType.OY, gpio.toBuffer()))
                .toBuffer();
      final session = const MeshtasticAdapter().createSession(link);
      try {
        await session.start();
        final catalog = session as RadioSettingsCatalog;
        const section = RadioFieldSection.remoteHardware;
        final pin = (await catalog.readSection(section))
            .firstWhere((field) => field.id == '3');
        expect(pin.value, contains('Lamp'));
        await catalog.writeSection(section, {
          '3': '[{"gpio":12,"name":"Light","access":2}]',
        });
        final module = _fields(link.remoteHardware!);
        expect(_varint(module, 1), 1);
        final changed = _fields(_buffer(module, 3));
        expect(_varint(changed, 3), 2);
        expect(_varint(changed, 9), 25);
      } finally {
        await session.close();
      }
    },
  );

  test(
    'discovered LAN radios restore through TCP and persist device information',
    () async {
      final radio = lanRadio(
        'meshtastic',
        'meshradio.local',
        4403,
        name: 'Mesh',
      );
      final store = MeshStore(await SharedPreferences.getInstance());
      await store.setRadios([radio]);
      await store.setActive(radioKey(radio));
      final bluetooth = _TestTransport();
      final lan = _TestLanTransport(
        _TasticSettingsLink()..firmware = '2.8.0.test',
        radio,
      );
      final controller = MeshController(
        store: store,
        transport: bluetooth,
        lanTransport: lan,
        adapters: [const MeshtasticAdapter()],
      );
      try {
        await controller.scan();
        expect(controller.discovered.single.radio, radio);
        await controller.restoreConnection();
        await Future<void>.delayed(Duration.zero);
        expect(controller.connected, isTrue);
        expect(bluetooth.links, isEmpty);
        expect(lan.endpoint, (host: 'meshradio.local', port: 4403));
        expect(lan.wire?.inputPrefix, [0x94, 0xc3]);
        expect(controller.radioDeviceInfo(radio)?.firmware, '2.8.0.test');
        expect(controller.radioDeviceInfo(radio)?.board, 'Heltec v3');
        expect(controller.radioPublicKey(radio), '03' * 32);
        expect(store.load(radioKey(radio)).deviceInfo?.firmware, '2.8.0.test');
      } finally {
        controller.dispose();
      }
    },
  );

  test('Meshtastic merges saved transport profiles and falls back in success order', () async {
    const ble = (network: 'meshtastic', device: 'BLE-123', name: 'Mesh');
    final wifi = lanRadio('meshtastic', 'mesh.local', 4403, name: 'Mesh');
    final store = MeshStore(await SharedPreferences.getInstance());
    const channel = (
      id: 'ch:0',
      name: 'Primary',
      channel: true,
      writable: true,
    );
    ChatCache history(String text) => ChatCache()
      ..radioPublicKey = '03' * 32
      ..peers[channel.id] = channel
      ..messages.add(
        MeshMessage(
          id: text,
          chat: channel.id,
          author: 'Field',
          text: text,
          time: DateTime.now(),
          delivery: Delivery.received,
        ),
      )
      ..drafts[channel.id] = text;
    await store.save(radioKey(ble), history('via Bluetooth'));
    await store.save(radioKey(wifi), history('via Wi-Fi'));
    await store.setRadios([ble, wifi]);
    await store.setActive(radioKey(wifi));

    final attempts = <String>[];
    final transport = _ReconnectTestTransport([
      () {
        attempts.add('bluetooth');
        return _TasticSettingsLink()..firmware = '2.8.0.test';
      },
      () {
        attempts.add('bluetooth');
        throw BluetoothProblem.off;
      },
      () {
        attempts.add('bluetooth');
        return null;
      },
    ]);
    var wifiAttempts = 0;
    final lan = _TestLanTransport(
      _TestLink(),
      wifi,
      open: (_) async {
        attempts.add('wifi');
        if (++wifiAttempts == 2) {
          return _TasticSettingsLink()..firmware = '2.8.0.test';
        }
        throw const RadioNotNearby();
      },
    );
    final controller = MeshController(
      store: store,
      transport: transport,
      lanTransport: lan,
      adapters: [const MeshtasticAdapter()],
    );
    addTearDown(controller.dispose);
    expect(controller.radios, [ble]);
    expect(
      controller.messages(channel.id).map((item) => item.text),
      unorderedEquals(['via Bluetooth', 'via Wi-Fi']),
    );
    expect(controller.draft(channel.id), 'via Wi-Fi');
    final errors = <String?>[];
    controller.addListener(() => errors.add(controller.error));

    await controller.restoreConnection();
    expect(attempts, ['wifi', 'bluetooth']);
    expect(controller.isConnectedTo(wifi), isTrue);
    expect(controller.connectionRoute(ble).device, ble.device);
    expect(controller.bluetoothProblem, isNull);
    expect(errors.whereType<String>(), isEmpty);
    expect(store.radioProfiles.single.routes, [ble.device, wifi.device]);
    expect(store.load(radioKey(ble)).messages, hasLength(2));

    await controller.disconnect(manual: false);
    attempts.clear();
    await controller.connect(wifi);
    expect(attempts, ['bluetooth', 'wifi']);
    expect(controller.isConnectedTo(ble), isTrue);
    expect(controller.connectionRoute(ble).device, wifi.device);
    expect(controller.bluetoothProblem, isNull);
    expect(errors.whereType<String>(), isEmpty);
    expect(store.radioProfiles.single.routes, [wifi.device, ble.device]);

    await controller.disconnect(manual: false);
    attempts.clear();
    final restored = MeshController(
      store: store,
      transport: transport,
      lanTransport: lan,
      adapters: [const MeshtasticAdapter()],
    );
    addTearDown(restored.dispose);
    restored.addListener(() => errors.add(restored.error));
    expect(restored.radios, [ble]);
    expect(restored.draft(channel.id), 'via Wi-Fi');
    await restored.restoreConnection();
    expect(attempts, ['wifi', 'bluetooth']);
    expect(restored.connected, isFalse);
    expect(errors.whereType<String>(), ['notNearby']);
    expect(store.radioProfiles.single.routes, [wifi.device, ble.device]);
  });

  test('Meshtastic recognizes the same hardware on a new route and rejects a reassigned endpoint', () async {
    const ble = (network: 'meshtastic', device: 'BLE-123', name: 'Mesh');
    final wifi = lanRadio('meshtastic', 'mesh.local', 4403, name: 'Mesh');
    final sameName = lanRadio('meshtastic', 'other.local', 4403, name: 'Mesh');
    _TasticSettingsLink link(int hardware) => _TasticSettingsLink()
      ..firmware = '2.8.0.test'
      ..hardwareId = List<int>.filled(6, hardware);
    final transport = _ReconnectTestTransport([() => link(5), () => link(5)]);
    var reassigned = false;
    final lan = _TestLanTransport(
      _TestLink(),
      wifi,
      open: (endpoint) async =>
          link(endpoint.host == 'other.local' || reassigned ? 6 : 5),
    );
    final store = MeshStore(await SharedPreferences.getInstance());
    final controller = MeshController(
      store: store,
      transport: transport,
      lanTransport: lan,
      adapters: [const MeshtasticAdapter()],
    );
    addTearDown(controller.dispose);
    await controller.connect(ble);
    controller.setDraft('ch:0', 'partly written');
    await controller.connect(wifi);
    expect(controller.radios, [ble]);
    expect(controller.isConnectedTo(wifi), isTrue);
    expect(controller.connectionRoute(ble).device, wifi.device);
    expect(controller.draft('ch:0'), 'partly written');
    expect(controller.cache?.radioHardwareId, '05' * 6);
    await controller.connect(sameName);
    expect(controller.radios, [ble, sameName]);
    expect(controller.draft('ch:0'), isEmpty);

    reassigned = true;
    await controller.disconnectRadio(ble, manual: false);
    await controller.connect(ble);
    expect(controller.isConnectedTo(ble), isTrue);
    expect(controller.cache?.radioHardwareId, '05' * 6);
    expect(controller.connectionRoute(ble).device, ble.device);
    expect(controller.draft('ch:0'), 'partly written');
    expect(controller.radios, [ble, sameName]);
  });

  test(
    'Meshtastic reads back saved network settings after the radio restarts',
    () async {
      final first = _TasticSettingsLink()
        ..firmware = '2.7.5'
        ..rebootOnNetworkWrite = true;
      final second = _TasticSettingsLink()..firmware = '2.7.5';
      final transport = _ReconnectTestTransport([
        () => first,
        () => null,
        () => second..network = first.network,
      ]);
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: transport,
        adapters: [const MeshtasticAdapter()],
      );
      addTearDown(controller.dispose);
      const radio = (network: 'meshtastic', device: 'same', name: 'Field');
      await controller.connect(radio);
      await controller.writeRadioSection(
        radio,
        RadioFieldSection.connectivity,
        {'9': 'updated.local'},
      );
      expect(transport.attempts.map(radioKey), List.filled(3, radioKey(radio)));
      expect(controller.isConnectedTo(radio), isTrue);
      expect(controller.reconnecting, isFalse);
      expect(first.networkWrites, 1);
      expect(second.networkWrites, 0);
      expect(
        String.fromCharCodes(_buffer(_fields(second.network), 9)),
        'updated.local',
      );
    },
  );

  test('manual disconnect cancels restart retries', () async {
    final adapter = _FakeAdapter('test');
    final transport = _ReconnectTestTransport([_TestLink.new, () => null]);
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: transport,
      adapters: [adapter],
    );
    try {
      const radio = (network: 'test', device: 'same', name: 'Field');
      await controller.connect(radio);
      adapter.sessions.single.stream.add(
        const RadioRestartExpected(explicit: true),
      );
      adapter.sessions.single.stream.add(const RadioEnded());
      await Future<void>.delayed(Duration.zero);
      expect(controller.reconnecting, isTrue);
      expect(transport.attempts, hasLength(2));
      await controller.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(controller.reconnecting, isFalse);
      expect(controller.linkState, LinkState.offline);
      expect(transport.attempts, hasLength(2));
    } finally {
      controller.dispose();
    }
  });

  testWidgets(
    'discovery is replaced by the first setup and closes on reconnect',
    (tester) async {
      _reduceMotion(tester);
      const radio = (network: 'test', device: 'new', name: 'Field radio');
      final adapter = _FakeAdapter('test');
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport()..found = [(radio: radio, rssi: -62)],
        adapters: [adapter],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RadioDiscoveryPage(controller: controller),
                  ),
                ),
                child: const Text('Open discovery'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open discovery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Field radio'));
      await tester.pumpAndSettle();
      expect(find.text('Radio setup'), findsOneWidget);
      expect(
        find.byType(RadioDiscoveryPage, skipOffstage: false),
        findsNothing,
      );
      await tester.tap(find.text('Set up later'));
      await tester.pumpAndSettle();
      expect(find.text('Open discovery'), findsOneWidget);
      await tester.tap(find.text('Open discovery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Field radio'));
      await tester.pumpAndSettle();
      expect(find.text('Open discovery'), findsOneWidget);
      expect(adapter.sessions.single.setupChecks, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  test(
    'MeshCore exposes Wi-Fi settings only when firmware supports them',
    () async {
      for (final version in [9, 14]) {
        final link = _CoreSettingsLink()..firmwareProtocol = version;
        final session = const MeshCoreAdapter().createSession(link);
        try {
          await session.start();
          await (session as RadioSettingsSession).readSettings();
          final catalog = session as RadioSettingsCatalog;
          const section = RadioFieldSection.connectivity;
          expect(catalog.extraSettings.contains(section), version == 14);
          if (version < 14) continue;
          final fields = await catalog.readSection(section);
          expect(
            fields.firstWhere((field) => field.id == 'wifi.ip').value,
            '192.168.1.50',
          );
          expect(
            fields.firstWhere((field) => field.id == 'wifi.pwd').secret,
            isTrue,
          );
          await catalog.writeSection(section, {'wifi.enabled': 'false'});
          expect(link.wifiEnabled, isFalse);
        } finally {
          await session.close();
        }
      }
    },
  );

  test(
    'MeshCore remains connected when the contact catalog is unavailable',
    () async {
      final link = _CoreSettingsLink()..rejectContactCatalog = true;
      final session = const MeshCoreAdapter().createSession(link);
      const channel = (
        id: 'ch:0',
        name: 'Public',
        writable: true,
        channel: true,
      );
      try {
        await session.start();
        final management = session as RadioConversationSession;
        expect(management.canShareChannel(channel), isTrue);
        final invitation = Uri.parse(await management.shareChannel(channel));
        expect(invitation.scheme, 'meshcore');
        expect(invitation.queryParameters['name'], 'Public');
        expect(invitation.queryParameters['secret'], hasLength(32));
        expect(management.canRemovePeer(channel), isFalse);
        await expectLater(management.removePeer(channel), throwsStateError);
        expect(management.canShareChannel(channel), isTrue);
        final created = await (session as RadioChannelSession).addChannel((
          action: ChannelAction.createPrivate,
          name: 'Field',
          secret: '',
          invitation: '',
        ));
        await management.removePeer(created.peer);
        expect(management.canShareChannel(created.peer), isFalse);
        expect(link.channels[1], everyElement(0));
      } finally {
        await session.close();
      }
    },
  );

  test(
    'Meshtastic accepts fixed map coordinates and removes a secondary channel',
    () async {
      final link = _TasticSettingsLink();
      final session = const MeshtasticAdapter().createSession(link);
      try {
        await session.start();
        await (session as RadioPositionSession).setFixedPosition((
          latitude: -21.123456,
          longitude: 54.654321,
        ));
        expect(link.fixedPosition, (-211234560, 546543210));
        final channel = await (session as RadioChannelSession).addChannel((
          action: ChannelAction.createPrivate,
          name: 'Field',
          secret: '',
          invitation: '',
        ));
        final management = session as RadioConversationSession;
        expect(await management.shareChannel(channel.peer), channel.invitation);
        await management.removePeer(channel.peer);
        expect(management.canShareChannel(channel.peer), isFalse);
        expect(_varint(_fields(link.channels[1]!), 3), 0);
      } finally {
        await session.close();
      }
    },
  );

  test('the archive pin preference survives cached history migration', () {
    final legacyJson = ChatCache().toJson()..['hiddenChats'] = ['node:a'];
    final legacy = ChatCache.fromJson(legacyJson);
    expect(legacy.archiveHidden, isTrue);
    final merged = ChatCache()..mergeHistory(legacy);
    expect(merged.archiveHidden, isTrue);
    merged.archiveHidden = false;
    final restored = ChatCache.fromJson(merged.toJson());
    expect(restored.archiveHidden, isFalse);
    expect(restored.hiddenChats, {'node:a'});
  });

  testWidgets(
    'chat editing marks read, reorders and hides without deleting a node',
    (tester) async {
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter(), MeshCoreAdapter()],
        preview: true,
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MeshGrame(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Select chats'), findsNothing);
      expect(find.byType(SliverReorderableList), findsOneWidget);
      expect(find.byIcon(Icons.drag_handle_rounded), findsWidgets);
      final chats = controller.conversations;
      final reorder = tester.widget<SliverReorderableList>(
        find.byType(SliverReorderableList),
      );
      reorder.onReorderItem!(0, 1);
      await tester.pumpAndSettle();
      expect(controller.conversations.first.id, chats[1].id);
      await tester.tap(find.text('Мира Соколова'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read'));
      await tester.pumpAndSettle();
      expect(controller.cache!.unread['node:a'], isNull);
      await tester.tap(find.text('Мира Соколова'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();
      expect(controller.hiddenConversations.single.id, 'node:a');
      expect(controller.cache!.peers['node:a'], isNotNull);
      expect(controller.messages('node:a'), isNotEmpty);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Archive'), findsOneWidget);
      await tester.longPress(find.text('Archive'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide from the list'));
      await tester.pumpAndSettle();
      expect(
        ChatCache.fromJson(controller.cache!.toJson()).archiveHidden,
        isTrue,
      );
      expect(find.text('Archive'), findsNothing);
      await tester.drag(find.text('Тропа'), const Offset(0, 35));
      await tester.pumpAndSettle();
      expect(find.text('Archive'), findsNothing);
      final pull = await tester.startGesture(
        tester.getCenter(find.text('Тропа')),
      );
      await pull.moveBy(const Offset(0, 28));
      await pull.moveBy(const Offset(0, 95));
      await tester.pump(const Duration(milliseconds: 230));
      expect(find.text('Release to show Archive'), findsOneWidget);
      await pull.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(find.text('Мира Соколова'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Archive'), findsOneWidget);
      await tester.drag(find.text('Тропа'), const Offset(0, -200));
      await tester.pumpAndSettle();
      tester
          .widget<CustomScrollView>(find.byKey(const PageStorageKey('chats')))
          .controller!
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('Archive'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'archive pull arms on Android and reveals at the threshold on iOS',
    (tester) async {
      _reduceMotion(tester);
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter()],
        preview: true,
      );
      controller.hideChats(['node:a'], hidden: true);
      controller.setArchiveHidden(true);
      await tester.pumpWidget(
        MeshGrame(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      final archive = find.byKey(const ValueKey('archive-row'));
      final start = tester.getCenter(find.text('Тропа'));
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, 25));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(tester.getSize(archive).height, greaterThan(0));
      expect(tester.widget<ListTile>(archive).onTap, isNull);
      await gesture.moveBy(const Offset(0, 65));
      await tester.pump(const Duration(milliseconds: 230));
      await tester.pump();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        expect(tester.widget<ListTile>(archive).onTap, isNotNull);
      } else {
        expect(find.text('Release to show Archive'), findsOneWidget);
        expect(tester.widget<ListTile>(archive).onTap, isNull);
        await gesture.moveBy(const Offset(0, -105));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        expect(tester.widget<ListTile>(archive).onTap, isNotNull);
      } else {
        expect(archive, findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  test('MeshCore retries admin login after a stale saved route', () async {
    const peer = (
      id: 'node:010203040506',
      name: 'Hilltop',
      writable: false,
      channel: false,
    );
    final link = _CoreSettingsLink()
      ..includeRepeater = true
      ..staleAdminPath = true;
    final session = const MeshCoreAdapter().createSession(link);
    try {
      await session.start();
      final admin = session as RemoteAdminSession;
      final remote = await admin.openAdmin(peer, 'test-admin');
      expect(await remote.readSettings(), isNotEmpty);
      expect(
        link.commands.where((command) => command.first == 26),
        hasLength(2),
      );
      expect(
        link.commands.where((command) => command.first == 13),
        hasLength(1),
      );
    } finally {
      await session.close();
    }
  });

  testWidgets(
    'a repeater profile offers diagnostics and authenticated management',
    (tester) async {
      _reduceMotion(tester);
      const radio = (network: 'meshcore', device: 'one', name: 'Field radio');
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _ProtocolTestTransport(
          _CoreSettingsLink()..includeRepeater = true,
        ),
        adapters: const [MeshCoreAdapter()],
      );
      await controller.connect(radio);
      await tester.pumpWidget(
        MeshGrame(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Nodes'));
      await tester.tap(find.text('Nodes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hilltop'));
      await tester.pumpAndSettle();
      expect(find.byType(MeshChatProfile), findsOneWidget);
      expect(find.text('Repeater'), findsOneWidget);
      expect(find.text('Sign in to sensor'), findsNothing);
      expect(find.text('Chat'), findsNothing);
      await tester.ensureVisible(find.text('Manage node'));
      expect(find.text('Manage node'), findsOneWidget);
      await tester.ensureVisible(find.text('Trace route'));
      await tester.tap(find.text('Trace route'));
      await tester.pumpAndSettle();
      expect(find.text('Route received'), findsOneWidget);
      await tester.ensureVisible(find.text('Trace history'));
      await tester.tap(find.text('Trace history'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SheetBody),
          matching: find.text('Route received'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('12AB'), findsOneWidget);
      expect(find.text('Direct'), findsOneWidget);
      await tester.tapAt(const Offset(390, 85));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(390, 85));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Manage node'));
      await tester.tap(find.text('Manage node'));
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.enterText(field, 'test-admin');
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(tester.widget<TextField>(field).obscureText, isFalse);
      await tester.tap(find.text('Remember password'));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.byType(RadioSettingsPage), findsOneWidget);
      final key = controller.cache!.identities['node:010203040506']!.publicKey;
      String? saved;
      unawaited(
        controller.store.adminPassword(key).then((value) => saved = value),
      );
      await tester.pump();
      expect(saved, 'test-admin');
      await tester.pumpWidget(const SizedBox());
      final disconnect = controller.disconnect(manual: false);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await disconnect;
      controller.dispose();
    },
  );

  test(
    'MeshCore selects commands by role and validates routes and sensor tags',
    () async {
      const peer = (
        id: 'node:010203040506',
        name: 'Hilltop',
        writable: false,
        channel: false,
      );
      final link = _CoreSettingsLink()..includeRepeater = true;
      final session = const MeshCoreAdapter().createSession(link);
      final actions = session as NetworkNodeActions;
      try {
        await session.start();
        expect(
          actions.nodeActions(peer),
          containsAll([
            NodeAction.trace,
            NodeAction.savedPath,
            NodeAction.favorite,
          ]),
        );
        expect(
          actions.nodeActions(peer),
          isNot(contains(NodeAction.sensorLogin)),
        );
        expect((session as RemoteAdminSession).canAdminister(peer), isTrue);
        final trace = await _traceResult(session, peer, 100);
        expect(trace.map((field) => field.value), ['12AB', '0']);
        final path = await actions.runNodeAction(peer, NodeAction.savedPath);
        expect(path.single.value, '23');
        await actions.runNodeAction(peer, NodeAction.favorite);
        expect(link.storedContactFlags, 0x25);
        await actions.runNodeAction(peer, NodeAction.favorite, enabled: false);
        expect(link.storedContactFlags, 0x24);
      } finally {
        await session.close();
      }

      final sensorLink = _CoreSettingsLink()
        ..includeRepeater = true
        ..contactType = 4;
      final sensor = const MeshCoreAdapter().createSession(sensorLink);
      final sensorActions = sensor as NetworkNodeActions;
      try {
        await sensor.start();
        expect(
          sensorActions.nodeActions(peer),
          containsAll([NodeAction.sensorLogin, NodeAction.telemetry]),
        );
        expect((sensor as RemoteAdminSession).canAdminister(peer), isFalse);
        await sensorActions.runNodeAction(
          peer,
          NodeAction.sensorLogin,
          password: 'test-admin',
        );
        final readings = await sensorActions.runNodeAction(
          peer,
          NodeAction.telemetry,
        );
        expect(readings.single.value, '3.78');
        expect(readings.single.units, 'V');
      } finally {
        await sensor.close();
      }
    },
  );

  test('Meshtastic matches diagnostic replies and targets local and remote admin commands', () async {
    const peer = (
      id: 'node:42',
      name: 'Remote',
      writable: true,
      channel: false,
    );
    final link = _TasticSettingsLink()
      ..includeRemote = true
      ..remoteRole = 6;
    final session = const MeshtasticAdapter().createSession(link);
    final actions = session as NetworkNodeActions;
    try {
      await session.start();
      expect(
        actions.nodeActions(peer),
        containsAll([
          NodeAction.environment,
          NodeAction.trace,
          NodeAction.ignore,
        ]),
      );
      expect(actions.nodeActions(peer), isNot(contains(NodeAction.neighbors)));
      final trace = await _traceResult(session, peer, 100);
      expect(trace.map((field) => field.value), [
        '!0000002b → !0000002c',
        '!0000002d',
      ]);
      expect(trace.first.hops.map((hop) => hop.snr), [6, null, -2]);
      expect(trace.last.hops.map((hop) => hop.snr), [3, 4.5]);
      expect(trace.last.hops.map((hop) => hop.rssi), [null, -107]);
      final sensor = await actions.runNodeAction(peer, NodeAction.environment);
      expect(sensor.single.value, '18.40');
      await actions.runNodeAction(peer, NodeAction.favorite);
      await actions.runNodeAction(peer, NodeAction.ignore, enabled: false);
      final admin = await (session as RemoteAdminSession).openAdmin(peer, '');
      await (admin as RemoteNodePower).setPower(reboot: true);
      expect(link.nodeCommands, [(123, 39, 42), (123, 48, 42), (42, 97, 2)]);
    } finally {
      await session.close();
    }
  });

  testWidgets(
    'node avatars open profiles and iOS child routes keep the screen behind them still',
    (tester) async {
      _reduceMotion(tester);
      final messenger = tester.binding.defaultBinaryMessenger;
      const snapshot = MethodChannel('meshgrame/back_swipe');
      messenger.setMockMethodCallHandler(snapshot, (_) async => false);
      addTearDown(() => messenger.setMockMethodCallHandler(snapshot, null));
      messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (_) async => null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      });
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshCoreAdapter(), MeshtasticAdapter()],
        preview: true,
      );
      await tester.pumpWidget(
        MeshGrame(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      final picker = find.byType(ChatFolderTabs);
      final control = find.descendant(
        of: picker,
        matching: find.byWidgetPredicate(
          (widget) => widget is IosControl && widget.kind == 'folderTabs',
        ),
      );
      IosControl categories() => tester.widget<IosControl>(control);
      expect(categories().kind, 'folderTabs');
      expect(categories().horizontalDrag, isFalse);
      expect(categories().tapOnly, isTrue);
      expect(categories().properties['labels'], ['All', 'Direct', 'Channels']);
      final widths = categories().properties['widths']! as List<double>;
      expect(widths, orderedEquals([...widths]..sort()));
      expect(widths.toSet().length, 3);
      expect(tester.getSize(picker).height, 48);
      final scroll = find.byKey(const ValueKey('native-chat-folder-scroll'));
      expect(
        tester.widget<SingleChildScrollView>(scroll).scrollDirection,
        Axis.horizontal,
      );
      categories().onSelect!(2);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Мира Соколова profile'), findsNothing);
      categories().onSelect!(0);
      await tester.pumpAndSettle();
      final avatar = find.byTooltip('Мира Соколова profile');
      await tester.tap(avatar);
      await tester.pumpAndSettle();
      expect(find.byType(MeshChatProfile), findsOneWidget);
      expect(find.byType(MeshChatPage), findsNothing);
      final title = find.descendant(
        of: find.byType(MeshChatProfile),
        matching: find.text('Мира Соколова'),
      );
      final before = tester.getTopLeft(title);
      final behind = find.byType(MeshNavigation, skipOffstage: false).first;
      final behindStart = tester.getTopLeft(behind);
      final swipe = await tester.startGesture(const Offset(3, 240));
      await swipe.moveBy(const Offset(70, 0));
      await tester.pump();
      await swipe.moveBy(const Offset(480, 0));
      await tester.pump();
      expect(
        find.ancestor(
          of: title,
          matching: find.byType(CupertinoPageTransition),
        ),
        findsNothing,
      );
      expect(tester.getTopLeft(behind), behindStart);
      expect(tester.getTopLeft(title).dx, greaterThan(before.dx + 100));
      await swipe.up();
      await tester.pumpAndSettle();
      expect(find.byType(MeshChatProfile), findsNothing);
      tester.widget<MeshNavigation>(find.byType(MeshNavigation)).onSelect(1);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Nodes'));
      await tester.tap(find.text('Nodes'));
      await tester.pumpAndSettle();
      await tester.tap(avatar);
      await tester.pumpAndSettle();
      expect(find.byType(MeshChatProfile), findsOneWidget);
      tester
          .widget<GlassActionButton>(
            find.byWidgetPredicate(
              (widget) => widget is GlassActionButton && widget.label == 'Chat',
            ),
          )
          .onTap!();
      await tester.pumpAndSettle();
      expect(find.byType(MeshChatPage), findsOneWidget);
      expect(find.byType(MeshChatProfile), findsNothing);

      Future<void> expectEdgeSwipe(Widget child) async {
        final screen = find.byWidget(child);
        expect(
          find.ancestor(
            of: screen,
            matching: find.byType(CupertinoPageTransition),
          ),
          findsNothing,
        );
        final from = tester.getTopLeft(screen);
        final gesture = await tester.startGesture(const Offset(3, 240));
        await gesture.moveBy(const Offset(70, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(480, 0));
        await tester.pump();
        expect(tester.getTopLeft(screen).dx, greaterThan(from.dx + 100));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(screen, findsNothing);
      }

      await expectEdgeSwipe(
        tester.widget<MeshChatPage>(find.byType(MeshChatPage)),
      );
      await expectEdgeSwipe(
        tester.widget<MeshChatProfile>(find.byType(MeshChatProfile)),
      );
      await expectEdgeSwipe(
        tester.widget<MeshNodesPage>(find.byType(MeshNodesPage)),
      );
      await tester.tap(find.text('Add a radio'));
      await tester.pumpAndSettle();
      await expectEdgeSwipe(
        tester.widget<RadioDiscoveryPage>(find.byType(RadioDiscoveryPage)),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  test('node presence expires after an hour and resists stale snapshots', () {
    final now = DateTime.utc(2026, 11, 21, 13);
    final cache = ChatCache()
      ..observe(
        'node:42',
        NodeObservation(lastSeen: now, hops: 0, favorite: true),
        now,
      );
    cache.observe(
      'node:42',
      NodeObservation(lastSeen: now.subtract(const Duration(days: 1)), hops: 3),
      now,
    );
    cache.observe(
      'node:42',
      NodeObservation(lastSeen: now.add(const Duration(days: 1))),
      now,
    );
    final restored = ChatCache.fromJson(cache.toJson())
        .observations['node:42']!;
    expect(restored.lastSeen, now);
    expect(restored.hops, 0);
    expect(restored.favorite, isTrue);
    expect(
      nodeIsOnline(restored.lastSeen, now.add(const Duration(minutes: 59))),
      isTrue,
    );
    expect(nodeIsOnline(restored.lastSeen, now.add(nodeOnlineWindow)), isFalse);
    expect(nodeIsOnline(null, now), isFalse);
  });

  test(
    'MeshCore uses advert time rather than contact modification time',
    () async {
      final link = _CoreSettingsLink()
        ..includeRepeater = true
        ..repeaterLastAdvert = 1795000000;
      final session = const MeshCoreAdapter().createSession(link);
      final events = <NodeObserved>[];
      final subscription = session.events
          .where((event) => event is NodeObserved)
          .cast<NodeObserved>()
          .listen(events.add);
      try {
        await session.start();
        expect(events.single.id, 'node:010203040506');
        expect(
          events.single.observation.lastSeen,
          nodeTimeFromSeconds(1795000000),
        );
        final before = DateTime.now();
        link.reply(
          Uint8List.fromList([0x80, ..._CoreSettingsLink.repeaterKey]),
        );
        await Future<void>.delayed(Duration.zero);
        expect(events.last.observation.lastSeen!.isBefore(before), isFalse);
      } finally {
        await subscription.cancel();
        await session.close();
      }
    },
  );

  test(
    'Meshtastic reports node metrics and activity from a channel packet',
    () async {
      final link = _TasticSettingsLink()
        ..includeRemote = true
        ..remoteLastHeard = 1795000000;
      final session = const MeshtasticAdapter().createSession(link);
      final events = <NodeObserved>[];
      final subscription = session.events
          .where((event) => event is NodeObserved)
          .cast<NodeObserved>()
          .listen(events.add);
      try {
        await session.start();
        final snapshot = events
            .singleWhere((event) => event.observation.lastSeen != null)
            .observation;
        expect(snapshot.lastSeen, nodeTimeFromSeconds(1795000000));
        expect(snapshot.hops, 0);
        expect(snapshot.channel, 2);
        expect(snapshot.favorite, isTrue);
        expect(snapshot.viaMqtt, isTrue);
        link.incoming(
          1,
          'On the air'.codeUnits,
          from: 99,
          to: meshBroadcast,
          receivedAt: 1795000020,
        );
        await Future<void>.delayed(Duration.zero);
        expect(events.last.id, 'node:99');
        expect(
          events.last.observation.lastSeen,
          nodeTimeFromSeconds(1795000020),
        );
        expect(events.last.peer?.channel, isFalse);
      } finally {
        await subscription.cancel();
        await session.close();
      }
    },
  );

  testWidgets('nodes open as a page with localized activity and radio sorts', (
    tester,
  ) async {
    _reduceMotion(tester);
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: const [MeshCoreAdapter(), MeshtasticAdapter()],
      preview: true,
    );
    final today = DateTime.now();
    final older = DateTime(today.year, today.month, today.day - 2, 12, 30);
    await tester.pumpWidget(
      MeshGrame(controller: controller, locale: const Locale('ru')),
    );
    await tester.pumpAndSettle();
    final avatars = find.byType(MeshAvatar);
    expect(
      tester
          .widgetList<MeshAvatar>(avatars)
          .singleWhere((avatar) => avatar.name == 'Мира Соколова')
          .online,
      isTrue,
    );
    controller.cache!.observations['node:b'] = NodeObservation(lastSeen: today);
    controller.cache!.observations['node:c'] = NodeObservation(lastSeen: older);
    controller.refreshNodePresence();
    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Узлы'));
    await tester.tap(find.text('Узлы'));
    await tester.pumpAndSettle();
    final page = find.byType(MeshNodesPage);
    final context = tester.element(page);
    final localizations = MaterialLocalizations.of(context);
    expect(page, findsOneWidget);
    expect(find.byType(SheetBody), findsNothing);
    expect(find.text(localizations.formatShortDate(older)), findsOneWidget);
    expect(
      find.text(
        localizations.formatTimeOfDay(
          TimeOfDay.fromDateTime(today),
          alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Сортировка'));
    await tester.pumpAndSettle();
    expect(find.text('По расстоянию'), findsOneWidget);
    expect(find.text('По последней переписке'), findsNothing);
    await tester.tap(find.text('По имени'));
    await tester.pumpAndSettle();
    expect(controller.nodes.first.name, 'Илья Ветров');
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await controller.connect(controller.radios.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Узлы'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Сортировка'));
    await tester.pumpAndSettle();
    expect(find.text('По последней переписке'), findsOneWidget);
    expect(find.text('По расстоянию'), findsNothing);
    expect(controller.nodeSort, NodeSort.activity);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test(
    'live radios keep independent drafts, incoming messages and unread counts',
    () async {
      final transport = _TestTransport(),
          adapter = _FakeAdapter('test-network');
      final store = MeshStore(await SharedPreferences.getInstance());
      final controller = MeshController(
        store: store,
        transport: transport,
        adapters: [adapter],
      );
      const one = (network: 'test-network', device: 'one', name: 'Radio 1');
      const two = (network: 'test-network', device: 'two', name: 'Radio 2');
      await controller.connect(one);
      expect(controller.connected, isTrue);
      controller.setDraft(_peer.id, 'first draft');
      expect(await controller.send(_peer, 'hello'), isTrue);
      expect(
        controller.messages(_peer.id).single.delivery,
        Delivery.acknowledged,
      );
      controller.setDraft(_peer.id, 'first draft');
      await controller.connect(two);
      expect(transport.links.first.closed, isFalse);
      expect(controller.connectedRadios, [one, two]);
      controller.markChatsRead([_peer.id]);
      adapter.sessions.first.stream.add(
        TextReceived(
          MeshMessage(
            id: 'background-radio',
            chat: _peer.id,
            author: _peer.name,
            text: 'Received on radio one',
            time: DateTime.now(),
            delivery: Delivery.received,
          ),
          _peer,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.unreadFor(one), 1);
      expect(controller.unreadFor(two), 0);
      expect(controller.messages(_peer.id), isEmpty);
      expect(controller.draft(_peer.id), isEmpty);
      await controller.connect(one);
      expect(controller.draft(_peer.id), 'first draft');
      expect(controller.messages(_peer.id).map((item) => item.text), [
        'hello',
        'Received on radio one',
      ]);
      expect(transport.links, hasLength(2));
      await controller.disconnectRadio(two);
      expect(transport.links.last.closed, isTrue);
      expect(controller.connected, isTrue);
      expect(store.connectedProfiles, [radioKey(one)]);
      controller.dispose();
    },
  );

  testWidgets('radio unread pills follow focus and fit their content', (
    tester,
  ) async {
    _reduceMotion(tester);
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: const [MeshCoreAdapter(), MeshtasticAdapter()],
      preview: true,
    );
    final one = controller.active!;
    final two = controller.radios.firstWhere((radio) => radio != one);
    controller.cache!.unread['channel:0'] = 120;
    await controller.connect(two);
    controller.cache!.unread['channel:0'] = 1;
    await tester.pumpWidget(
      MeshGrame(controller: controller, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    Finder badge(Radio radio) => find.descendant(
      of: find.byKey(ValueKey(radioKey(radio))),
      matching: find.byType(MeshUnreadBadge),
    );
    expect(badge(two), findsNothing);
    expect(badge(one), findsOneWidget);
    expect(tester.getSize(badge(one)).height, lessThan(30));
    expect(
      find.descendant(of: badge(one), matching: find.text('99+')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ValueKey(radioKey(one))));
    await tester.pumpAndSettle();
    expect(badge(one), findsNothing);
    expect(badge(two), findsOneWidget);
    expect(tester.getSize(badge(two)).height, lessThan(30));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('radio icons follow transport, connection and focus', (
    tester,
  ) async {
    _reduceMotion(tester);
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: const [MeshCoreAdapter(), MeshtasticAdapter()],
      preview: true,
    );
    final bluetooth = controller.active!;
    final offline = controller.radios.last;
    final wifi = lanRadio(
      'meshtastic',
      '192.0.2.10',
      4403,
      name: 'Wi-Fi relay',
    );
    await controller.connect(wifi);
    await tester.pumpWidget(
      MeshGrame(controller: controller, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    Finder badge(Radio radio) => find.descendant(
      of: find.byKey(ValueKey(radioKey(radio))),
      matching: find.byType(MeshRowIcon),
    );
    void expectGradient(Radio radio, Color tint) {
      final tile = tester.widget<Container>(
        find.descendant(of: badge(radio), matching: find.byType(Container)),
      );
      expect(
        (tile.decoration as BoxDecoration).gradient,
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(tint, Colors.white, .20)!, tint],
        ),
      );
    }

    const lime = Color(0xffd5e88b);
    const green = Color(0xffa9e0b4);
    const gray = Color(0xff6a7280);

    expect(tester.widget<MeshRowIcon>(badge(wifi)).icon, Icons.wifi_rounded);
    expect(
      tester.widget<MeshRowIcon>(badge(bluetooth)).icon,
      Icons.bluetooth_rounded,
    );
    expectGradient(wifi, lime);
    expectGradient(bluetooth, green);
    expectGradient(offline, gray);

    await controller.connect(bluetooth);
    await tester.pumpAndSettle();
    expectGradient(bluetooth, lime);
    expectGradient(wifi, green);

    await controller.disconnectRadio(bluetooth);
    await tester.pumpAndSettle();
    expectGradient(bluetooth, gray);
    expectGradient(wifi, green);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('signal colors and online dot stay vivid in both themes', (
    tester,
  ) async {
    const idle = Color(0xff8a97aa);
    const green = Color(0xff1cd950);
    const bands = [
      (null, 0, idle),
      (-80, 1, Color(0xffff3b39)),
      (-79, 2, Color(0xffff920f)),
      (-67, 3, Color(0xfff8bc00)),
      (-55, 4, green),
    ];
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: MeshStyle(dark).theme(),
          home: Scaffold(
            body: Column(
              children: [
                for (final (rssi, _, _) in bands)
                  SignalQuality(key: ValueKey(rssi), rssi: rssi),
                const MeshAvatar('Node', online: true),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final (rssi, bars, color) in bands) {
        final signal = find.descendant(
          of: find.byKey(ValueKey(rssi)),
          matching: find.byType(Container),
        );
        expect(
          tester
              .widgetList<Container>(signal)
              .map((bar) => (bar.decoration as BoxDecoration).color),
          [for (var bar = 0; bar < 4; bar++) bar < bars ? color : idle],
        );
      }
      expect(
        find.descendant(
          of: find.byType(MeshAvatar),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).color == green,
          ),
        ),
        findsOneWidget,
      );
    }
  });

  test('reports RSSI, applies settings to their radio, and removes only that radio', () async {
    final store = MeshStore(await SharedPreferences.getInstance());
    final controller = MeshController(
      store: store,
      transport: _TestTransport(),
      adapters: [_FakeAdapter('test')],
    );
    const first = (network: 'test', device: 'one', name: 'First');
    const second = (network: 'test', device: 'two', name: 'Second');
    await controller.connect(first);
    await Future<void>.delayed(Duration.zero);
    expect(controller.signalRssi, -62);
    expect(
      (await controller.readRadioSettings(first))
          .singleWhere((field) => field.id == 'name')
          .value,
      'Test node',
    );
    await controller.writeRadioSettings(first, {'name': 'Updated'});
    expect(
      (await controller.readRadioSettings(first))
          .singleWhere((field) => field.id == 'name')
          .value,
      'Updated',
    );
    await controller.connect(second);
    expect(
      (await controller.readRadioSettings(first))
          .singleWhere((field) => field.id == 'name')
          .value,
      'Updated',
    );
    await controller.forget(second);
    expect(controller.radios, [first]);
    expect(controller.active, first);
    expect(controller.connected, isTrue);
    expect(controller.signalRssi, -62);
    expect(store.radios, [first]);
    controller.dispose();
  });

  test('an incoming peer can use opaque ids and is not inferred from a protocol prefix', () async {
    final adapter = _FakeAdapter('third');
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: [adapter],
    );
    await controller.connect((
      network: 'third',
      device: 'radio',
      name: 'Third',
    ));
    const peer = (
      id: 'opaque',
      name: 'A Group',
      writable: false,
      channel: true,
    );
    final message = MeshMessage(
      id: '1',
      chat: peer.id,
      author: 'Alex',
      text: 'Message',
      time: DateTime.now(),
      delivery: Delivery.received,
    );
    adapter.sessions.single.stream.add(TextReceived(message, peer));
    adapter.sessions.single.stream.add(TextReceived(message, peer));
    expect(controller.messages(peer.id), hasLength(1));
    expect(controller.cache!.peers[peer.id], peer);
    expect(controller.unreadTotal, 1);
    controller.dispose();
  });

  test('contact QR uses native protocol formats and full public keys', () {
    final key = List.filled(32, '12').join();
    final tastic = const MeshtasticAdapter();
    const node = (id: 'node:123', name: 'Mira', writable: true, channel: false);
    final url = tastic.contactCode(node, (
      publicKey: key,
      type: null,
      shortName: 'MR',
    ))!;
    expect(url.toString(), startsWith('https://meshtastic.org/v/#'));
    expect(tastic.readContactCode(url), (id: node.id, publicKey: key));
    expect(tastic.readContactCode(url.replace(host: 'example.org')), isNull);
    final core = const MeshCoreAdapter();
    const repeater = (
      id: 'node:121212121212',
      name: 'Hilltop',
      writable: false,
      channel: false,
    );
    final invite = core.contactCode(repeater, (
      publicKey: key,
      type: 2,
      shortName: null,
    ))!;
    expect(invite.queryParameters['type'], '2');
    expect(core.readContactCode(invite), (id: repeater.id, publicKey: key));
  });

  test(
    'MeshCore writes a contact without a saved route and confirms it',
    () async {
      final link = _CoreSettingsLink();
      final adapter = const MeshCoreAdapter();
      final session = adapter.createSession(link);
      addTearDown(session.close);
      await session.start();
      const peer = (
        id: 'node:121212121212',
        name: 'Полевой узел',
        writable: true,
        channel: false,
      );
      final code = adapter.contactCode(peer, (
        publicKey: '12' * 32,
        type: 1,
        shortName: null,
      ))!;
      final contact = adapter.readContactAttachment(code)!;
      expect(
        await (session as RadioContactSession).importContact(contact),
        peer,
      );
      final add = link.commands.singleWhere((item) => item.first == 9);
      expect(add.sublist(33, 36), [1, 0, 0xff]);
      expect(link.commands.singleWhere((item) => item.first == 30), [
        30,
        ...List.filled(32, 0x12),
      ]);
      expect(
        await (session as RadioContactSession).importContact(contact),
        peer,
      );
      expect(link.commands.where((item) => item.first == 9), hasLength(1));
    },
  );

  test('a compact contact fits the smallest channel payload', () {
    final code = const MeshCoreAdapter().contactCode(
      (
        id: 'node:121212121212',
        name: 'Полевой узел',
        writable: true,
        channel: false,
      ),
      (publicKey: '12' * 32, type: 1, shortName: null),
    )!;
    final source = const MeshCoreAdapter().readContactAttachment(code)!;
    expect(code.toString().length, greaterThan(80));
    final invite = compactContactLink(source, 80)!;
    expect(invite.length, lessThanOrEqualTo(80));
    final parsed = readCompactContact(Uri.parse(invite))!;
    expect(parsed.id, source.id);
    expect(parsed.publicKey, source.publicKey);
    expect(parsed.name, 'Поле');
    expect(compactContactLink(source, 10), isNull);
  });

  test(
    'Meshtastic imports a contact without marking its key as verified',
    () async {
      final link = _TasticSettingsLink();
      final adapter = const MeshtasticAdapter();
      final session = adapter.createSession(link);
      addTearDown(session.close);
      await session.start();
      const node = (
        id: 'node:51',
        name: 'Mira',
        writable: true,
        channel: false,
      );
      ContactAttachment details(String key) => adapter.readContactAttachment(
        adapter.contactCode(node, (
          publicKey: key,
          type: null,
          shortName: 'MR',
        ))!,
      )!;
      final importer = session as RadioContactSession;
      final original = details('09' * 32);
      expect(await importer.importContact(original), node);
      final written = _fields(link.importedContact!);
      expect(_varint(written, 1), 51);
      expect(_buffer(_fields(_buffer(written, 2)), 8), List.filled(32, 9));
      expect(written.hasField(3), isFalse);
      expect(written.hasField(4), isFalse);
      await expectLater(
        importer.importContact(details('10' * 32)),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'contact QR expands from its entry point and closes back to it',
    (tester) async {
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger = tester.binding.defaultBinaryMessenger;
      MethodCall? shared;
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        shared = call;
        return 'dev.fluttercommunity.plus/share/dismissed';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter()],
      );
      const peer = (
        id: 'node:42',
        name: 'Mira',
        writable: true,
        channel: false,
      );
      final link = const MeshtasticAdapter().contactCode(peer, (
        publicKey: List.filled(32, 'a1').join(),
        type: null,
        shortName: 'MR',
      ))!;
      const tag = 'contact';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Hero(
                tag: tag,
                child: Material(
                  child: IconButton(
                    icon: const Icon(Icons.qr_code_2_rounded),
                    onPressed: () => showContactQr(
                      context,
                      controller: controller,
                      peer: peer,
                      code: link,
                      heroTag: tag,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.qr_code_2_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      final nativeClose = find.byWidgetPredicate(
        (widget) =>
            widget is IosControl && widget.properties['label'] == 'Close',
      );
      if (useIosControls) {
        expect(nativeClose, findsOneWidget);
        expect(find.byTooltip('Close'), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(find.text('Mira'), findsOneWidget);
      final qr = find.byType(QrImageView);
      expect(tester.getSize(qr).aspectRatio, 1);
      expect(
        tester.getTopLeft(qr).dy,
        greaterThan(tester.getBottomLeft(find.text('Contact QR code')).dy),
      );
      expect(
        tester.getBottomLeft(qr).dy,
        lessThan(tester.getTopLeft(find.text('Mira')).dy),
      );
      if (useIosControls) {
        final share = find.byWidgetPredicate(
          (widget) =>
              widget is IosControl && widget.properties['label'] == 'Share',
        );
        tester.widget<IosControl>(share).onSelect!(0);
      } else {
        await tester.tap(find.byTooltip('Share'));
      }
      await tester.pumpAndSettle();
      expect(shared?.method, 'share');
      expect(shared?.arguments['uri'], link.toString());
      expect(shared?.arguments['paths'], isNull);
      if (useIosControls) {
        tester.widget<IosControl>(nativeClose).onSelect!(0);
      } else {
        await tester.tap(find.byTooltip('Close'));
      }
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.qr_code_2_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  test('MeshCore admin matches the target and reads status and CLI', () async {
    final link = _CoreSettingsLink()..includeRepeater = true;
    final session = const MeshCoreAdapter().createSession(link);
    const peer = (
      id: 'node:010203040506',
      name: 'Hilltop',
      writable: false,
      channel: false,
    );
    try {
      await session.start();
      final admin = session as RemoteAdminSession;
      expect(admin.canAdminister(peer), isTrue);
      final remote = await admin.openAdmin(peer, 'test-admin');
      final fields = await remote.readSettings();
      expect(fields.first.value, 'Hilltop');
      expect(fields[1].value, 'true');
      final status = await (remote as RadioTelemetrySession).readTelemetry();
      expect(status.first.value, '3926');
      expect(status.singleWhere((item) => item.id == 'rssi').value, '-106');
      expect(status.singleWhere((item) => item.id == 'snr').value, '4.75');
    } finally {
      await session.close();
    }
  });

  test('Meshtastic remote administration targets the node and uses its own passkey', () async {
    final link = _TasticSettingsLink()..includeRemote = true;
    final session = const MeshtasticAdapter().createSession(link);
    const peer = (
      id: 'node:42',
      name: 'Remote',
      writable: true,
      channel: false,
    );
    try {
      await session.start();
      final local = session as RadioSettingsSession;
      expect((await local.readSettings()).first.value, 'Long');
      final remote = await (session as RemoteAdminSession).openAdmin(peer, '');
      expect((await remote.readSettings()).first.value, 'Remote');
      await remote.writeSettings({'long': 'New name'});
      expect((await remote.readSettings()).first.value, 'New name');
      expect((await local.readSettings()).first.value, 'Long');
    } finally {
      await session.close();
    }
  });

  test('MeshCore channel requires an exact on-air replay with a relay path', () async {
    final link = _CoreSettingsLink();
    final session = const MeshCoreAdapter().createSession(link);
    final events = <DeliveryUpdate>[];
    final subscription = session.events
        .where((event) => event is DeliveryUpdate)
        .cast<DeliveryUpdate>()
        .listen(events.add);
    const peer = (id: 'ch:0', name: 'Public', writable: true, channel: true);
    final time = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    try {
      await session.start();
      await session.send(
        peer,
        MeshMessage(
          id: 'group',
          chat: peer.id,
          author: '',
          text: 'net check',
          time: time,
          delivery: Delivery.queued,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      const expected =
          '112f092489e48adbab5ad14f05a642e0017e9684954e743adb26b116d198ae12f55289';
      final payload = [
        for (var i = 0; i < expected.length; i += 2)
          int.parse(expected.substring(i, i + 2), radix: 16),
      ];
      link.reply(Uint8List.fromList([0x88, 0, 0, 0x15, 0, ...payload]));
      link.reply(
        Uint8List.fromList([0x88, 0, 0, 0x15, 1, 0xab, ...payload.reversed]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      link.reply(
        Uint8List.fromList([
          0x88,
          0,
          0,
          0x14,
          0,
          0,
          0,
          0,
          0x41,
          0x12,
          0x34,
          ...payload,
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.map((event) => (event.id, event.delivery)), [
        ('group', Delivery.acknowledged),
      ]);
    } finally {
      await subscription.cancel();
      await session.close();
    }
  });

  testWidgets(
    'chat search enters its own view, dismisses focus and remembers a choice',
    (tester) async {
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter(), MeshCoreAdapter()],
        preview: true,
      );
      await tester.pumpWidget(
        MeshGrame(controller: controller, locale: const Locale('ru')),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(MeshNavigation), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        true,
      );
      await tester.tapAt(const Offset(375, 400));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        false,
      );
      await tester.enterText(find.byType(TextField), 'Мира');
      await tester.pumpAndSettle();
      expect(find.text('Мира Соколова'), findsOneWidget);
      await tester.tap(find.text('Мира Соколова'));
      await tester.pumpAndSettle();
      expect(controller.cache?.searchHistory, ['node:a']);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'chat search opens profiles from avatars and read-only chats from rows',
    (tester) async {
      _reduceMotion(tester);
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter(), MeshCoreAdapter()],
        preview: true,
      );
      controller.cache!.observations['node:a'] = const NodeObservation(
        canMessage: false,
      );
      await tester.pumpWidget(
        MeshGrame(controller: controller, locale: const Locale('ru')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      if (useIosControls) {
        final search = tester.widget<IosControl>(
          find.byWidgetPredicate(
            (widget) => widget is IosControl && widget.kind == 'chatSearch',
          ),
        );
        search.onTextChanged!('Мира');
      } else {
        await tester.enterText(find.byType(TextField), 'Мира');
      }
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Профиль Мира Соколова'));
      await tester.pumpAndSettle();
      final profile = find.byType(MeshChatProfile);
      expect(tester.widget<MeshChatProfile>(profile).peer.id, 'node:a');
      expect(find.byType(MeshChatPage), findsNothing);
      for (final label in ['Чат', 'Поиск', 'Звук', 'Очистить']) {
        expect(
          find.descendant(
            of: profile,
            matching: useIosControls
                ? find.byWidgetPredicate(
                    (widget) =>
                        widget is GlassActionButton && widget.label == label,
                  )
                : find.widgetWithText(InkWell, label),
          ),
          findsOneWidget,
        );
      }

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Мира Соколова'));
      await tester.pumpAndSettle();
      final chat = find.byType(MeshChatPage);
      expect(tester.widget<MeshChatPage>(chat).peer.id, 'node:a');
      expect(profile, findsNothing);
      expect(find.text('Вижу метку. Скоро будем.'), findsOneWidget);
      expect(find.text('Отправка недоступна'), findsOneWidget);
      expect(find.byType(MessageInput), findsNothing);
      expect(controller.cache?.searchHistory, ['node:a']);
      expect(
        await controller.send(controller.cache!.peers['node:a']!, 'Тест'),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'entering search moves the header and the same categories above the keyboard',
    (tester) async {
      final view = tester.view;
      view.devicePixelRatio = 1;
      view.physicalSize = const Size(390, 760);
      view.viewPadding = const FakeViewPadding(top: 40, bottom: 32);
      view.padding = view.viewPadding;
      addTearDown(view.resetDevicePixelRatio);
      addTearDown(view.resetPhysicalSize);
      addTearDown(view.resetViewPadding);
      addTearDown(view.resetPadding);
      addTearDown(view.resetViewInsets);
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter(), MeshCoreAdapter()],
        preview: true,
      );
      await tester.pumpWidget(
        MeshGrame(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      final filters = find.byKey(const ValueKey('chat-categories'));
      final heading = find.byType(PageHeading);
      final close = find.byWidgetPredicate(
        (widget) => widget is GlassButton && widget.label == 'Close search',
      );
      final filterElement = tester.element(filters);
      final initialFilters = tester.getRect(filters);
      final initialHeading = tester.getTopLeft(heading);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      final initialClose = tester.getTopLeft(close);
      expect(initialClose.dx, greaterThanOrEqualTo(390));
      view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.getTopLeft(heading).dy, lessThan(initialHeading.dy));
      expect(tester.getTopLeft(filters).dy, greaterThan(initialFilters.top));
      expect(tester.getTopLeft(close).dx, lessThan(initialClose.dx));
      expect(tester.getTopRight(close).dx, greaterThan(374));
      await tester.pumpAndSettle();
      expect(heading, findsNothing);
      expect(tester.element(filters), same(filterElement));
      expect(tester.getBottomLeft(filters).dy, 760 - 280 - 2);
      expect(tester.getTopRight(close).dx, 374);

      view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(filters).dy, 760 - 32 - 2);
      tester.widget<GlassButton>(close).onTap!();
      await tester.pumpAndSettle();
      expect(tester.element(filters), same(filterElement));
      expect(tester.getRect(filters), initialFilters);
      expect(tester.getTopLeft(heading), initialHeading);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'iOS active search uses glass controls and filters native input',
    (tester) async {
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter(), MeshCoreAdapter()],
        preview: true,
      );
      await tester.pumpWidget(
        MeshGrame(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      final input = find.byWidgetPredicate(
        (widget) => widget is IosControl && widget.kind == 'chatSearch',
      );
      final close = find.byWidgetPredicate(
        (widget) =>
            widget is IosControl &&
            widget.properties['label'] == 'Close search',
      );
      expect(find.byType(TextField), findsNothing);
      expect(tester.getSize(input).height, 48);
      expect(tester.getRect(input).top, tester.getRect(close).top);
      final nativeField = tester.widget<IosControl>(input);
      nativeField.onTextChanged!('Мира');
      await tester.pumpAndSettle();
      expect(find.text('Мира Соколова'), findsOneWidget);
      expect(find.text('Тропа'), findsNothing);
      nativeField.onTextChanged!('');
      await tester.pumpAndSettle();
      expect(find.text('Тропа'), findsOneWidget);
      tester.widget<IosControl>(close).onSelect!(0);
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      expect(find.byType(MeshNavigation), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  test(
    'Meshtastic distinguishes a direct relay from an addressable receipt',
    () async {
      final link = _TasticSettingsLink();
      final session = const MeshtasticAdapter().createSession(link);
      const direct = (
        id: 'node:42',
        name: 'Node',
        writable: true,
        channel: false,
      );
      const group = (id: 'ch:0', name: 'Public', writable: true, channel: true);
      final changes = <(String, Delivery)>[];
      final subscription = session.events.listen((event) {
        if (event is DeliveryUpdate) changes.add((event.id, event.delivery));
      });
      MeshMessage message(Peer peer, String reference) => MeshMessage(
        id: peer.id,
        chat: peer.id,
        author: '',
        text: 'Hello',
        time: DateTime.now(),
        delivery: Delivery.queued,
        remoteId: reference,
      );
      try {
        await session.start();
        await session.send(direct, message(direct, '500'));
        await session.send(group, message(group, '501'));
        link.incoming(5, const [], from: 123, request: 500);
        link.incoming(5, const [], from: 50, request: 500);
        await Future<void>.delayed(Duration.zero);
        expect(changes, [(direct.id, Delivery.relayed)]);
        link.incoming(5, const [], from: 123, request: 501);
        link.incoming(5, const [], from: 42, request: 500);
        await Future<void>.delayed(Duration.zero);
        expect(changes, [
          (direct.id, Delivery.relayed),
          (group.id, Delivery.acknowledged),
          (direct.id, Delivery.acknowledged),
        ]);
      } finally {
        await subscription.cancel();
        await session.close();
      }
    },
  );

  testWidgets(
    'a missing confirmation expires and a late receipt can still win',
    (tester) async {
      final adapter = _FakeAdapter('test');
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: [adapter],
      );
      await controller.connect((
        network: 'test',
        device: 'one',
        name: 'Field radio',
      ));
      final radio = adapter.sessions.single..autoAcknowledge = false;
      expect(await controller.send(_peer, 'check'), isTrue);
      final message = controller.messages(_peer.id).single;
      expect(message.delivery, Delivery.submitted);
      await tester.pump(const Duration(seconds: 101));
      expect(
        controller.messages(_peer.id).single.delivery,
        Delivery.unconfirmed,
      );
      radio.stream.add(DeliveryUpdate(message.id, Delivery.acknowledged));
      expect(
        controller.messages(_peer.id).single.delivery,
        Delivery.acknowledged,
      );
      controller.dispose();
    },
  );

  test(
    'MeshCore position settings preserve the other coordinate and policies',
    () async {
      final link = _CoreSettingsLink();
      final session = const MeshCoreAdapter().createSession(link);
      try {
        await session.start();
        final settings = session as RadioSettingsCatalog;
        expect(settings.extraSettings, contains(RadioFieldSection.position));
        await settings.writeSection(RadioFieldSection.position, {
          'latitude': '-33.2',
          'advertPosition': 'true',
        });
        final fields = await settings.readSection(RadioFieldSection.position);
        expect(fields.map((field) => field.value), ['-33.2', '1.25', 'true']);
        expect((link.telemetryFlags, link.contactFlags), (5, 3));
      } finally {
        await session.close();
      }
    },
  );

  test('MeshCore V3 channel frames decode and direct commands use the six-byte address', () {
    final data = Uint8List.fromList([
      17,
      0,
      0,
      0,
      2,
      1,
      0,
      2,
      0,
      0,
      0,
      ...'Alex: Hello'.codeUnits,
    ]);
    final msg = MeshCoreFrames.incoming(data, {})!;
    expect((msg.chat, msg.author, msg.text), ('ch:2', 'Alex', 'Hello'));
    expect(msg.remoteId, 'mc:csk1dgxv:Alex');
    const node = (
      id: 'node:010203040506',
      name: 'Bob',
      writable: true,
      channel: false,
    );
    final outbound = MeshCoreFrames.send(node, msg);
    expect(outbound.take(13), [2, 0, 0, 2, 0, 0, 0, 1, 2, 3, 4, 5, 6]);
  });

  test('MeshCore reacts using the sender timestamp and accepts interoperable reactions', () async {
    final link = _CoreSettingsLink();
    final session = const MeshCoreAdapter().createSession(link);
    final events = <NetworkEvent>[];
    final subscription = session.events.listen(events.add);
    try {
      await session.start();
      const channel = (
        id: 'ch:0',
        name: 'Public',
        channel: true,
        writable: true,
      );
      void incoming(String sender, String body, int stamp) => link.reply(
        Uint8List.fromList([
          17,
          238,
          0,
          0,
          0,
          0x82,
          0,
          ...MeshCoreFrames.littleEndian32(stamp),
          ...utf8.encode('$sender: $body'),
        ]),
      );
      incoming('Jo', '❤️@[Alex]\nj8s7q2bq', 3);
      incoming('Alex', 'Hello ', 2);
      await Future<void>.delayed(Duration.zero);
      final text = events.whereType<TextReceived>().single.message;
      final reaction = events.whereType<ReactionReceived>().single.reaction;
      expect(reaction.target, text.remoteId);
      expect((reaction.actor, reaction.emoji), ('name:Jo', '❤️'));
      expect(text.remoteId, 'mc:j8s7q2bq:Alex');
      expect(
        (text.packet?.hops, text.packet?.snr, text.packet?.route),
        (2, -4.5, MessageRoute.flood),
      );
      await (session as NetworkReactions).react(
        channel,
        text.remoteId!,
        '🇷🇺',
      );
      final command = link.commands.lastWhere((item) => item.first == 3);
      expect(utf8.decode(command.sublist(7)), '@[Alex]🇷🇺\nj8s7q2bq');
      await session.send(
        channel,
        MeshMessage(
          id: 'own',
          chat: channel.id,
          author: '',
          text: 'Own',
          time: DateTime.fromMillisecondsSinceEpoch(4000),
          delivery: Delivery.queued,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final sent = events.whereType<MessagePacketUpdated>().single;
      final stamp = MeshCoreFrames.u32(
        Uint8List.fromList(link.commands.last),
        3,
      );
      expect(stamp, greaterThan(4));
      expect(sent.reference, isNot('mc:n26fvjhq:Field node'));
      expect(sent.packet.route, MessageRoute.flood);
    } finally {
      await subscription.cancel();
      await session.close();
    }
  });

  test(
    'Meshtastic uses different packet fields for channel and direct messages',
    () {
      final packet = meshtasticTextPacket(0x89abcdef, 0x12345678, 2, 'Я');
      expect(packet, [
        0x0a,
        0x19,
        0x15,
        0x78,
        0x56,
        0x34,
        0x12,
        0x18,
        0x02,
        0x22,
        0x06,
        0x08,
        0x01,
        0x12,
        0x02,
        0xd0,
        0xaf,
        0x35,
        0xef,
        0xcd,
        0xab,
        0x89,
        0x50,
        0x01,
        0x88,
        0x01,
        0x01,
      ]);
      expect(
        meshtasticTextPacket(1, meshBroadcast, 0, 'a').length,
        lessThan(packet.length),
      );
      expect(
        () => meshtasticTextPacket(1, meshBroadcast, 0, 'я' * 101),
        throwsArgumentError,
      );
    },
  );

  test(
    'MeshCore writes updated LoRa values without clearing repeat mode',
    () async {
      final link = _CoreSettingsLink();
      final session = const MeshCoreAdapter().createSession(link);
      final settings = session as RadioSettingsSession;
      try {
        await session.start();
        final fields = await settings.readSettings();
        expect(
          fields.singleWhere((field) => field.id == 'frequency').value,
          '868.1',
        );
        final telemetry = await (session as RadioTelemetrySession)
            .readTelemetry();
        expect(
          telemetry.singleWhere((field) => field.id == 'battery').value,
          '3.75',
        );
        expect(await (session as RadioBatteryReader).readBattery(), (
          percent: 63,
          powered: false,
          estimated: true,
        ));
        await settings.writeSettings({
          'sf': '10',
          'power': '-2',
          'name': 'Field',
        });
        final radioChange = link.commands.singleWhere(
          (bytes) => bytes.first == 11,
        );
        expect(radioChange.sublist(9), [10, 5, 1]);
        expect(link.commands.singleWhere((bytes) => bytes.first == 12), [
          12,
          254,
        ]);
        expect(link.name, 'Field');
      } finally {
        await session.close();
      }
    },
  );

  test('MeshCore infers charging from a voltage jump to full', () async {
    final link = _CoreSettingsLink()..batteryMillivolts = 4200;
    final session = const MeshCoreAdapter().createSession(link);
    final battery = session as RadioBatteryReader;
    try {
      await session.start();
      expect(await battery.readBattery(), (
        percent: 100,
        powered: false,
        estimated: true,
      ));
      link.batteryMillivolts = 4120;
      expect((await battery.readBattery())?.powered, isFalse);
      link.batteryMillivolts = 4200;
      expect((await battery.readBattery())?.powered, isFalse);
      link.batteryMillivolts = 4000;
      expect((await battery.readBattery())?.powered, isFalse);
      link.batteryMillivolts = 4210;
      expect(await battery.readBattery(), (
        percent: 100,
        powered: true,
        estimated: true,
      ));
      link.batteryMillivolts = 4150;
      expect((await battery.readBattery())?.powered, isTrue);
      link.batteryMillivolts = 4050;
      expect((await battery.readBattery())?.powered, isFalse);
    } finally {
      await session.close();
    }
  });

  test(
    'Meshtastic admin settings preserve unknown fields and identity flags',
    () async {
      final link = _TasticSettingsLink();
      final session = const MeshtasticAdapter().createSession(link);
      final settings = session as RadioSettingsSession;
      try {
        await session.start();
        final fields = await settings.readSettings();
        expect(link.deviceRead, isTrue);
        expect(fields.singleWhere((field) => field.id == 'hops').value, '3');
        await settings.writeSettings({'hops': '6'});
        expect(_varint(_fields(link.lora), 8), 6);
        expect(_buffer(_fields(link.lora), 99), [1, 2, 3]);
        await settings.writeSettings({'long': 'Field'});
        expect(String.fromCharCodes(_buffer(_fields(link.owner), 2)), 'Field');
      } finally {
        await session.close();
      }
    },
  );

  test('Meshtastic replies and reactions carry the original packet ID', () {
    final reply = meshtasticTextPacket(14, 145, 0, 'Принято', replyTo: 17);
    final reaction = meshtasticTextPacket(
      15,
      meshBroadcast,
      1,
      '👍',
      replyTo: 17,
      reaction: true,
    );
    UnknownFieldSet data(List<int> wire) =>
        _fields(_buffer(_fields(_buffer(_fields(wire), 1)), 4));
    expect(_fixed(data(reply), 7), 17);
    expect(data(reply).hasField(8), isFalse);
    expect(_fixed(data(reaction), 7), 17);
    expect(_fixed(data(reaction), 8), 1);
    expect(_buffer(data(reaction), 2), [0xf0, 0x9f, 0x91, 0x8d]);
  });

  test('Meshtastic receives threaded text, reactions and local device metrics separately', () async {
    final link = _TasticSettingsLink()..includeRemote = true;
    final session = const MeshtasticAdapter().createSession(link);
    final events = <NetworkEvent>[];
    final subscription = session.events.listen(events.add);
    try {
      await session.start();
      link.incoming(
        1,
        [65],
        replyTo: 17,
        receivedSnr: -7.5,
        receivedRssi: -105,
        hopStart: 4,
        hopLimit: 2,
        relaySuffix: 171,
      );
      link.incoming(1, [0xf0, 0x9f, 0x91, 0x8d], replyTo: 17, reacts: true);
      final voltage = ByteData(4)..setFloat32(0, 3.85);
      final measurements =
          (CodedBufferWriter()
                ..writeField(1, PbFieldType.OU3, 89)
                ..writeField(2, PbFieldType.OF3, voltage.getUint32(0)))
              .toBuffer();
      final telemetry =
          (CodedBufferWriter()..writeField(2, PbFieldType.OY, measurements))
              .toBuffer();
      link.incoming(67, telemetry, from: 123);
      await Future<void>.delayed(Duration.zero);
      final text = events.whereType<TextReceived>().single.message;
      expect(text.remoteId, '19');
      expect(text.replyTo, '17');
      final packet = MeshMessage.fromJson(text.toJson()).packet!;
      expect(
        (packet.sender, packet.recipient, packet.channel),
        ('node:42', 'node:123', 0),
      );
      expect((packet.hops, packet.hopLimit, packet.relaySuffix), (2, 2, 171));
      expect((packet.snr, packet.rssi), (-7.5, -105));
      expect(events.whereType<ReactionReceived>().single.reaction.emoji, '👍');
      const peer = (
        id: 'node:42',
        name: 'Remote',
        channel: false,
        writable: true,
      );
      await session.send(
        peer,
        MeshMessage(
          id: 'sent',
          chat: peer.id,
          author: '',
          text: 'Reply',
          time: DateTime.now(),
          delivery: Delivery.queued,
          remoteId: '1234',
        ),
      );
      link.incoming(5, [], request: 1234, receivedSnr: 6, receivedRssi: -81);
      await Future<void>.delayed(Duration.zero);
      final sent = events.whereType<MessagePacketUpdated>().single.packet;
      final ack = events.whereType<DeliveryUpdate>().single.packet!;
      expect(
        (sent.sender, sent.recipient, ack.confirmedBy),
        ('node:123', 'node:42', 'node:42'),
      );
      expect((ack.ackSnr, ack.ackRssi, ack.snr), (6, -81, null));
      final readings = await (session as RadioTelemetrySession).readTelemetry();
      expect(
        readings.singleWhere((field) => field.id == 'voltage').value,
        '3.85',
      );
      expect(events.whereType<RadioBatteryChanged>().last.battery, (
        percent: 89,
        powered: false,
        estimated: false,
      ));
      final externalPower =
          (CodedBufferWriter()..writeField(
                2,
                PbFieldType.OY,
                (CodedBufferWriter()..writeField(1, PbFieldType.OU3, 101))
                    .toBuffer(),
              ))
              .toBuffer();
      link.incoming(67, externalPower, from: 124);
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<RadioBatteryChanged>(), hasLength(1));
      link.incoming(67, externalPower, from: 123);
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<RadioBatteryChanged>().last.battery, (
        percent: null,
        powered: true,
        estimated: false,
      ));
    } finally {
      await subscription.cancel();
      await session.close();
    }
  });

  test(
    'opening the app restores the last radio until explicitly disconnected',
    () async {
      const favorite = (network: 'test', device: 'one', name: 'First');
      final store = MeshStore(await SharedPreferences.getInstance());
      await store.setRadios([favorite]);
      await store.setActive(radioKey(favorite));
      final transport = _TestTransport();
      final controller = MeshController(
        store: store,
        transport: transport,
        adapters: [_FakeAdapter('test')],
      );
      await controller.restoreConnection();
      expect(controller.connected, isTrue);
      await controller.disconnect(manual: false);
      await controller.restoreConnection();
      expect(controller.connected, isTrue);
      await controller.disconnect();
      await controller.restoreConnection();
      expect(controller.connected, isFalse);
      expect(transport.links, hasLength(2));
      controller.dispose();
    },
  );

  testWidgets('connected radio shows the battery under its signal', (
    tester,
  ) async {
    _reduceMotion(tester);
    const radio = (network: 'test', device: 'one', name: 'Field radio');
    final adapter = _FakeAdapter('test');
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: [adapter],
    );
    controller.setAppearance('light');
    await controller.connect(radio);
    await tester.pumpWidget(
      MeshGrame(controller: controller, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final battery = find.byType(RadioConnectionStatus);
    final session = adapter.sessions.single;
    expect(battery, findsOneWidget);
    expect(find.text('test'), findsOneWidget);
    expect(find.textContaining('Connected'), findsNothing);
    expect(tester.widget<RadioConnectionStatus>(battery).battery, isNull);
    session.stream.add(
      const RadioBatteryChanged((
        percent: 41,
        powered: false,
        estimated: false,
      )),
    );
    await tester.pumpAndSettle();
    final percent = find.text('41%');
    final batteryIcon = find.descendant(
      of: battery,
      matching: find.byType(CustomPaint),
    );
    final signal = find.text('≈-62 dBm');
    final signalIcon = find.descendant(of: battery, matching: find.byType(Row));
    expect(
      tester.getTopLeft(percent).dx,
      greaterThan(tester.getTopRight(batteryIcon).dx),
    );
    expect(
      tester.getTopLeft(percent).dy,
      greaterThan(tester.getBottomLeft(signal).dy),
    );
    expect(tester.getTopLeft(percent).dx, tester.getTopLeft(signal).dx);
    expect(tester.getCenter(batteryIcon).dx, tester.getCenter(signalIcon).dx);
    expect(
      tester.widget<Text>(percent).style?.color,
      tester.widget<Text>(signal).style?.color,
    );
    controller.setAppearance('dark');
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(percent).style?.color,
      tester.widget<Text>(signal).style?.color,
    );
    session.stream.add(
      const RadioBatteryChanged((percent: 100, powered: true, estimated: true)),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<RadioConnectionStatus>(battery).battery?.powered,
      true,
    );
    expect(find.text('Charging'), findsOneWidget);
    expect(find.text('≈100%'), findsNothing);
    final disconnect = controller.disconnect();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    await disconnect;
    expect(battery, findsNothing);
    expect(controller.battery, isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'iOS back swipe reveals the previous page below a UIKit snapshot',
    (tester) async {
      _reduceMotion(tester);
      const channel = MethodChannel('meshgrame/back_swipe');
      final calls = <MethodCall>[];
      final firstCapture = Completer<bool>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (calls.length == 1 &&
            call.method == 'capture' &&
            !firstCapture.isCompleted) {
          return firstCapture.future;
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      const radio = (network: 'test', device: 'one', name: 'Field radio');
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: [_FakeAdapter('test')],
      );
      await controller.connect(radio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            bottomNavigationBar: MeshNavigation(
              index: 1,
              unread: 0,
              onSelect: (_) {},
            ),
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  radioSettingsRoute(
                    context,
                    RadioSettingsPage(controller: controller, radio: radio),
                  ),
                ),
                child: const Text('Open radio'),
              ),
            ),
          ),
        ),
      );
      final underneath = find.text('Open radio', skipOffstage: false);
      final original = tester.getTopLeft(underneath);
      await tester.tap(underneath);
      await tester.pump();
      final title = find.text('Radio settings');
      expect(
        ModalRoute.of(tester.element(title))!.animation!.isCompleted,
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(title, findsOneWidget);
      final before = tester.getTopLeft(title);
      final cancelled = await tester.startGesture(const Offset(3, 220));
      await cancelled.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 120));
      await cancelled.moveBy(const Offset(35, 0));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getTopLeft(title), before);
      expect(underneath.hitTestable(), findsNothing);
      firstCapture.complete(true);
      await tester.pump();
      await tester.pump();
      expect(title, findsNothing);
      expect(underneath, findsOneWidget);
      await cancelled.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(title), before);
      expect(calls.first.method, 'capture');
      expect(calls.last.method, 'release');
      final cancelledId = (calls.first.arguments as Map)['id'];
      expect((calls.last.arguments as Map)['id'], cancelledId);
      calls.clear();

      final swipe = await tester.startGesture(const Offset(3, 220));
      await swipe.moveBy(const Offset(65, 0));
      await tester.pump();
      await swipe.moveBy(const Offset(500, 0));
      await tester.pump();
      await tester.pump();
      final tabs = find.byType(MeshNavigation);
      final back = find.byWidgetPredicate(
        (widget) =>
            widget is IosControl && widget.properties['label'] == 'Back',
      );
      expect(tabs, findsOneWidget);
      expect(back, findsNothing);
      expect(tester.getTopLeft(underneath), original);
      expect(title, findsNothing);
      expect(
        calls.any(
          (call) =>
              call.method == 'move' &&
              (call.arguments as Map)['offset'] as double > 0.5,
        ),
        isTrue,
      );
      await swipe.up();
      await tester.pumpAndSettle();
      expect(title, findsNothing);
      expect(underneath, findsOneWidget);
      expect(calls.first.method, 'capture');
      expect(calls.last.method, 'release');
      expect((calls.first.arguments as Map)['id'], isNot(cancelledId));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  test('MeshCore probes a known repeater route for per-hop signal', () async {
    final link = _CoreSettingsLink()
      ..includeRepeater = true
      ..firmwareProtocol = 10;
    final session = const MeshCoreAdapter().createSession(link);
    final peer = (
      id: 'node:010203040506',
      name: 'Hilltop',
      writable: false,
      channel: false,
    );
    try {
      await session.start();
      final trace = await _traceResult(session, peer, 100, signals: true);
      expect(trace.first.hops.map((hop) => hop.snr), [8, -1]);
      expect(trace.first.hops.last.name, 'Hilltop');
      expect(trace.last.hops.single.snr, 4);
    } finally {
      await session.close();
    }
  });

  test(
    'MeshCore keeps a discovery pending until receiving its route',
    () async {
      final link = _CoreSettingsLink()
        ..includeRepeater = true
        ..delayRouteDiscovery = true;
      final session = const MeshCoreAdapter().createSession(link);
      final tracing = session as NetworkRouteTracing;
      const peer = (
        id: 'node:010203040506',
        name: 'Hilltop',
        writable: false,
        channel: false,
      );
      try {
        await session.start();
        final result = _traceResult(session, peer, 100);
        await Future<void>.delayed(Duration.zero);
        expect(tracing.routeTraceInterval, Duration.zero);
        expect(tracing.routeTracePendingUntil?.isAfter(DateTime.now()), isTrue);
        await expectLater(tracing.startRouteTrace(peer, 101), throwsStateError);
        expect(
          link.commands.where((command) => command.first == 52),
          hasLength(1),
        );
        link.replyRouteDiscovery();
        expect((await result).first.value, '12AB');
        expect(tracing.routeTracePendingUntil, isNull);
      } finally {
        await session.close();
      }
    },
  );

  testWidgets(
    'trace status times out inline and a late reply updates saved history',
    (tester) async {
      _reduceMotion(tester);
      const radio = (
        network: 'meshtastic',
        device: 'test-trace',
        name: 'Field radio',
      );
      final link = _TasticSettingsLink()
        ..includeRemote = true
        ..delayRouteReply = true;
      final store = MeshStore(await SharedPreferences.getInstance());
      final controller = MeshController(
        store: store,
        transport: _ProtocolTestTransport(link),
        adapters: const [MeshtasticAdapter()],
      );
      await controller.connect(radio);
      final peer = controller.cache!.peers['node:42']!;
      link.incoming(1, 'Another node'.codeUnits, from: 41);
      await tester.pump();
      final other = controller.cache!.peers['node:41']!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => SingleChildScrollView(
                child: NodeActionsPanel(controller: controller, peer: peer),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trace route'));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for the node…'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Trace route'))
            .onTap,
        isNull,
      );
      expect(controller.canTraceRoute(other), isTrue);
      await controller.startRouteTrace(other);
      final request = link.traceRequests.single;
      expect(store.load(radioKey(radio)).routeTraces[request]?.pending, isTrue);

      // Advance the saved request and cooldown past the 30-second UI deadline.
      final aged = DateTime.now().subtract(const Duration(seconds: 31));
      controller.cache!.routeTraces[request] = RouteTrace(
        request: request,
        peer: peer.id,
        sentAt: aged,
      );
      controller.cache!.routeTraceCooldownUntil = aged.add(
        routeTraceNoticeDelay,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('No reply after 30 seconds. Check the trace history.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Trace history'));
      await tester.pumpAndSettle();
      expect(find.text('No reply yet'), findsOneWidget);

      link.incoming(70, [], from: 41, request: request);
      link.incoming(70, [], request: request + 1);
      await tester.pump();
      expect(find.text('No reply yet'), findsOneWidget);
      link.incoming(70, [], request: request, receivedRssi: -99);
      await tester.pumpAndSettle();
      final history = find.byType(SheetBody);
      final received = find.descendant(
        of: history,
        matching: find.text('Reply received late'),
      );
      expect(received, findsOneWidget);
      final saved = store.load(radioKey(radio)).routeTraces[request]!;
      expect(saved.arrivedLate, isTrue);
      expect(saved.fields.last.hops.last.rssi, -99);
      expect(controller.routeTraceHistory(other.id), isEmpty);
      await tester.tap(received);
      await tester.pumpAndSettle();
      expect(find.text('RSSI -99 dBm'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.pump();
    },
  );

  testWidgets('radio hero resolves a bundled board by model', (tester) async {
    _reduceMotion(tester);
    final catalog = await tester.runAsync(
      () => File('assets/boards/catalog.json').readAsString(),
    );
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _TestBoardBundle(catalog!),
        child: const MaterialApp(
          home: Scaffold(
            body: RadioProfilePage(
              heading: 'Radio settings',
              padding: EdgeInsets.zero,
              publicKey: null,
              boardName: 'Fallback',
              boardModel: 43,
              protocol: 'Meshtastic',
              children: [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Heltec V3'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/boards/heltec-v3.webp',
    );
  });

  testWidgets('Heltec V4 OLED uses the bundled Heltec V4 illustration', (
    tester,
  ) async {
    _reduceMotion(tester);
    final catalog = await tester.runAsync(
      () => File('assets/boards/catalog.json').readAsString(),
    );
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _TestBoardBundle(catalog!),
        child: const MaterialApp(
          home: Scaffold(
            body: RadioProfilePage(
              heading: 'Radio settings',
              padding: EdgeInsets.zero,
              publicKey: null,
              boardName: 'Heltec V4 OLED',
              protocol: 'MeshCore',
              children: [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Heltec V4'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/boards/heltec-v4.webp',
    );
  });

  testWidgets('device information aligns values and copies the full key', (
    tester,
  ) async {
    _reduceMotion(tester);
    final messenger = tester.binding.defaultBinaryMessenger;
    String? copied;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    const radio = (network: 'meshtastic', device: 'one', name: 'Test board');
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _ProtocolTestTransport(
        _TasticSettingsLink()..firmware = '2.8.0.test',
      ),
      adapters: [const MeshtasticAdapter()],
    );
    await controller.connect(radio);
    await tester.pumpWidget(
      MaterialApp(
        home: RadioSettingsPage(controller: controller, radio: radio),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Device information'));
    await tester.tap(find.text('Device information'));
    await tester.pumpAndSettle();
    const prefix = '0303 0303 0303 0303...';
    final name = find.text('Name');
    expect(
      tester.getTopLeft(name).dx,
      tester.getTopLeft(find.text('Firmware version')).dx,
    );
    final key = find.text(prefix);
    expect(tester.getTopLeft(name).dx, tester.getTopLeft(key).dx);
    final copy = find.byTooltip('Copy public key');
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pump();
    expect(copied, '03' * 32);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'the radar keeps sweeping after discovery stops for a connection',
    (tester) async {
      const radio = (network: 'test', device: 'ble', name: 'Test radio');
      final transport = _PendingConnectTransport()
        ..found = [(radio: radio, rssi: -63)];
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: transport,
        adapters: [_FakeAdapter('test')],
      );
      await tester.pumpWidget(
        MaterialApp(home: RadioDiscoveryPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      final radar = find.descendant(
        of: find.byType(AspectRatio),
        matching: find.byType(CustomPaint),
      );
      Animation<double> sweep() =>
          (tester.widget<CustomPaint>(radar).painter as dynamic).sweep
              as Animation<double>;
      expect(sweep().isAnimating, isFalse);

      await tester.tap(find.text('Test radio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.scanning, isFalse);
      expect(controller.linkState, LinkState.connecting);
      final position = sweep().value;
      await tester.pump(const Duration(milliseconds: 150));
      expect(sweep().value, greaterThan(position));

      transport.result.completeError(const RadioNotNearby());
      await tester.pumpAndSettle();
      expect(sweep().isAnimating, isFalse);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  test('Wi-Fi latency levels include the requested cutoff values', () {
    const android = {0: 4, 40: 4, 41: 3, 70: 3, 71: 2, 100: 2, 101: 1, 500: 1};
    for (final MapEntry(key: ms, value: level) in android.entries) {
      expect(SignalBars.latency(Duration(milliseconds: ms)), level);
    }
    const ios = {0: 4, 150: 4, 151: 3, 200: 3, 201: 2, 250: 2, 251: 1, 500: 1};
    for (final MapEntry(key: ms, value: level) in ios.entries) {
      expect(SignalBars.latency(Duration(milliseconds: ms), ios: true), level);
    }
  });

  testWidgets(
    'Wi-Fi latency and battery use aligned, equally wide glyphs',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: RadioConnectionStatus(
                rssi: null,
                wifi: true,
                latency: Duration(milliseconds: 151),
                battery: (percent: 91, powered: false, estimated: true),
              ),
            ),
          ),
        ),
      );
      final icons = find.descendant(
        of: find.byType(RadioConnectionStatus),
        matching: find.byType(CustomPaint),
      );
      expect(icons, findsNWidgets(2));
      expect(
        tester.getSize(icons.first).width,
        tester.getSize(icons.last).width,
      );
      expect(
        tester.getTopLeft(icons.first).dx,
        tester.getTopLeft(icons.last).dx,
      );
      final glyph = tester.widget<SignalBars>(find.byType(SignalBars));
      expect(glyph.level, defaultTargetPlatform == TargetPlatform.iOS ? 3 : 1);
      final latency = find.text('≈151 ms');
      final battery = find.text('≈91%');
      expect(latency, findsOneWidget);
      expect(battery, findsOneWidget);
      expect(tester.getTopLeft(latency).dx, tester.getTopLeft(battery).dx);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'Android discovery explains disabled Bluetooth and retries after enabling it',
    (tester) async {
      const radio = (network: 'test', device: 'ble', name: 'Test radio');
      final transport = _BluetoothTestTransport()
        ..found = [(radio: radio, rssi: -62)];
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: transport,
        adapters: [_FakeAdapter('test')],
      );
      await controller.connect(radio);
      expect(controller.bluetoothProblem, BluetoothProblem.off);
      await tester.pumpWidget(
        MaterialApp(
          home: RadioDiscoveryPage(controller: controller),
          theme: ThemeData(platform: TargetPlatform.android),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Bluetooth is off'), findsOneWidget);
      final button = find.text('Turn on Bluetooth');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(controller.bluetoothProblem, isNull);
      expect(find.text('Test radio'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('Android home navigation clears both gesture and button insets', (
    tester,
  ) async {
    final view = tester.view;
    view.devicePixelRatio = 1;
    view.physicalSize = const Size(390, 844);
    addTearDown(view.resetDevicePixelRatio);
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetViewPadding);
    addTearDown(view.resetSystemGestureInsets);
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: [const MeshtasticAdapter()],
    );
    await tester.pumpWidget(
      MeshGrame(controller: controller, locale: const Locale('en')),
    );
    for (final (safe, gesture, gap) in [
      (0.0, 0.0, 14.0),
      (24.0, 32.0, 46.0),
      (48.0, 12.0, 62.0),
    ]) {
      view.viewPadding = FakeViewPadding(bottom: safe);
      view.systemGestureInsets = FakeViewPadding(bottom: gesture);
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(find.byType(MeshNavigation)).dy, 844 - gap);
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets(
    'Android main tab indicator follows the drag and settles on release',
    (tester) async {
      var index = 0;
      final selections = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) => MeshNavigation(
                  index: index,
                  unread: 0,
                  onSelect: (value) {
                    selections.add(value);
                    setState(() => index = value);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final indicator = find.descendant(
        of: find.byType(MeshNavigation),
        matching: find.byType(FractionallySizedBox),
      );
      final start = tester.getCenter(indicator);
      final drag = await tester.startGesture(start);
      await drag.moveBy(const Offset(24, 0));
      await drag.moveBy(const Offset(16, 0));
      await tester.pump();
      expect(tester.getCenter(indicator).dx, closeTo(start.dx + 40, 1));
      expect(selections, isEmpty);
      await drag.moveBy(const Offset(32, 0));
      await drag.up();
      await tester.pumpAndSettle();
      expect(selections, [1]);
      final target = tester.getCenter(indicator);
      final cancelled = await tester.startGesture(target);
      await cancelled.moveBy(const Offset(-76, 0));
      await tester.pump();
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(tester.getCenter(indicator), target);
      expect(selections, [1]);
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();
      expect(tester.getCenter(indicator), start);
      expect(selections, [1, 0]);
    },
  );

  testWidgets('swipe reveals actions and only deletes after a tap', (
    tester,
  ) async {
    var revealed = false, deletes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, change) {
              return SwipeActionsRow(
                revealed: revealed,
                onReveal: (open) => change(() => revealed = open),
                surface: Colors.white,
                background: Colors.black,
                actions: [
                  (
                    label: 'Hide',
                    icon: Icons.visibility_off,
                    color: Colors.blue,
                    onTap: () {},
                  ),
                  (
                    label: 'Delete',
                    icon: Icons.delete,
                    color: Colors.red,
                    onTap: () => deletes++,
                  ),
                ],
                child: const SizedBox(
                  height: 62,
                  width: double.infinity,
                  child: Center(child: Text('Radio')),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.drag(find.text('Radio'), const Offset(-245, 0));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hide'), findsOneWidget);
    expect(deletes, 0);
    await tester.tap(find.byTooltip('Delete'));
    expect(deletes, 1);
  });

  testWidgets(
    'chat category indicator tracks a drag across three tabs',
    (tester) async {
      var selected = 0;
      final selections = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 330,
                child: StatefulBuilder(
                  builder: (context, setState) => ChatFilters(
                    selected: selected,
                    onSelect: (index) {
                      selections.add(index);
                      setState(() => selected = index);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final filters = find.byType(ChatFilters);
      if (useIosControls) {
        final nativeTabs = find.descendant(
          of: filters,
          matching: find.byType(IosControl),
        );
        final tabs = tester.widget<IosControl>(nativeTabs);
        expect(tabs.kind, 'tabs');
        expect(tabs.properties['textOnly'], isTrue);
        expect(tabs.horizontalDrag, isTrue);
        tabs.onSelect!(2);
        await tester.pumpAndSettle();
        expect(selections, [2]);
        expect(tester.widget<IosControl>(nativeTabs).properties['index'], 2);
        return;
      }
      final indicator = find.descendant(
        of: filters,
        matching: find.byType(FractionallySizedBox),
      );
      final start = tester.getCenter(indicator);
      final drag = await tester.startGesture(start);
      await drag.moveBy(const Offset(48, 0));
      await tester.pump();
      expect(tester.getCenter(indicator).dx, closeTo(start.dx + 48, 1));
      expect(selections, isEmpty);
      await drag.moveBy(const Offset(140, 0));
      await drag.up();
      await tester.pumpAndSettle();
      expect(selections, [2]);
      expect(
        tester.getCenter(indicator).dx,
        closeTo(tester.getCenter(find.text('Channels')).dx, 1),
      );
      await tester.tap(find.text('Direct'));
      await tester.pumpAndSettle();
      expect(selections, [2, 1]);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'profile wallpaper scrolls and the compact header fades over the content',
    (tester) async {
      _reduceMotion(tester);
      final canvasKey = GlobalKey();
      const inset = EdgeInsets.only(top: 64);
      const style = MeshStyle(true);
      const avatar = ValueKey('profile-avatar');
      const rowColor = Color(0xffb9653b);
      await tester.pumpWidget(
        MaterialApp(
          theme: style.theme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: inset, viewPadding: inset),
            child: child!,
          ),
          home: RepaintBoundary(
            key: canvasKey,
            child: Scaffold(
              body: Builder(
                builder: (context) => ProfilePage(
                  identity: 'radio:sample',
                  heading: 'Profile',
                  title: 'Field',
                  subtitle: 'MeshCore',
                  avatar: const ColoredBox(key: avatar, color: Colors.blue),
                  avatarSize: 104,
                  padding: meshScrollPadding(context),
                  leading: IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {},
                  ),
                  children: [
                    for (var i = 0; i < 24; i++)
                      ColoredBox(
                        color: rowColor,
                        child: ListTile(title: Text('Setting $i')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Future<List<Color>?> sampleBackdrop(Iterable<int> rows) {
        final boundary =
            canvasKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        return tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final bytes = (await image.toByteData(
              format: ImageByteFormat.rawRgba,
            ))!;
            return rows.map((y) {
              final index = (y * image.width + 4) * 4;
              return Color.fromARGB(
                255,
                bytes.getUint8(index),
                bytes.getUint8(index + 1),
                bytes.getUint8(index + 2),
              );
            }).toList();
          } finally {
            image.dispose();
          }
        });
      }

      final back = find.byTooltip('Back');
      final avatarView = find.byKey(avatar);
      final wallpaper = find.byType(ProfileWallpaper);
      SliverPaintOrder paintOrder() => tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .paintOrder;
      final expandedOrder = defaultTargetPlatform == TargetPlatform.iOS
          ? SliverPaintOrder.lastIsTop
          : SliverPaintOrder.firstIsTop;
      expect(paintOrder(), expandedOrder);
      final buttonPosition = tester.getTopLeft(back);
      final expandedAvatar = tester.getTopLeft(avatarView);
      expect(buttonPosition.dy, greaterThanOrEqualTo(inset.top));
      expect((await sampleBackdrop([16]))!.single, isNot(style.canvas));

      final drag = await tester.startGesture(const Offset(350, 455));
      await drag.moveBy(const Offset(0, -24));
      await drag.moveBy(const Offset(0, -50));
      await tester.pump();
      expect(paintOrder(), expandedOrder);
      expect(tester.getTopLeft(wallpaper).dy, lessThan(0));
      expect(tester.getCenter(avatarView).dx, lessThan(expandedAvatar.dx + 52));
      expect(
        tester.getTopRight(avatarView).dx - tester.getTopLeft(avatarView).dx,
        lessThan(104),
      );
      await drag.moveBy(const Offset(0, -300));
      await drag.up();
      await tester.pumpAndSettle();
      expect(wallpaper, findsNothing);
      expect(paintOrder(), SliverPaintOrder.firstIsTop);
      final samples = (await sampleBackdrop([16, 76, 112, 140]))!;
      expect(samples.first.r, greaterThan(style.canvas.r));
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i].r, greaterThan(samples[i - 1].r));
      }
      expect(samples.last, rowColor);
      expect(tester.getTopLeft(back), buttonPosition);
      expect(find.text('Profile'), findsNothing);
      expect(
        tester.getCenter(find.text('Field')).dy,
        closeTo(tester.getCenter(back).dy, 1),
      );
      final compactLeft = tester.getTopLeft(avatarView).dx;
      final compactRight = tester.getTopRight(find.text('Field')).dx;
      expect(
        (compactLeft + compactRight) / 2,
        closeTo(tester.getCenter(find.byType(ProfilePage)).dx, 1),
      );
      expect(
        tester.getCenter(avatarView).dy,
        closeTo(tester.getCenter(back).dy, 1),
      );

      await tester.flingFrom(
        const Offset(350, 365),
        const Offset(0, 250),
        4200,
      );
      await tester.pumpAndSettle();
      expect(wallpaper, findsNothing);
      expect(find.text('Setting 0'), findsOneWidget);
      await tester.dragFrom(const Offset(350, 370), const Offset(0, 150));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(avatarView), expandedAvatar);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'a short profile snaps open and closed in both directions',
    (tester) async {
      _reduceMotion(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfilePage(
              identity: 'short',
              title: 'Sample',
              subtitle: 'Node',
              heading: 'Profile',
              avatar: ColoredBox(
                key: ValueKey('short-profile-avatar'),
                color: Colors.blue,
              ),
              avatarSize: 104,
              padding: EdgeInsets.zero,
              children: [Text('One row')],
            ),
          ),
        ),
      );
      final wallpaper = find.byType(ProfileWallpaper);
      final scroll = find.byType(CustomScrollView);
      final expandedRow = tester.getTopLeft(find.text('One row'));
      await tester.timedDrag(
        scroll,
        const Offset(0, -48),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();
      expect(wallpaper, findsOneWidget);
      expect(tester.getTopLeft(find.text('One row')), expandedRow);

      await tester.timedDrag(
        scroll,
        const Offset(0, -145),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();
      expect(wallpaper, findsNothing);
      expect(
        tester.getTopLeft(find.text('One row')).dy,
        lessThan(expandedRow.dy),
      );
      expect(find.text('Node'), findsNothing);

      if (defaultTargetPlatform == TargetPlatform.android) {
        final row = find.text('One row');
        final title = find.text('Sample');
        final avatar = find.byKey(const ValueKey('short-profile-avatar'));
        final settledRow = tester.getCenter(row);
        final settledTitle = tester.getCenter(title);
        final settledAvatar = tester.getCenter(avatar);
        final pull = await tester.startGesture(tester.getCenter(scroll));
        await pull.moveBy(const Offset(0, -28));
        await tester.pump();
        final firstMove = tester.getCenter(row).dy;
        await pull.moveBy(const Offset(0, -44));
        await tester.pump();
        final resisted = firstMove - tester.getCenter(row).dy;
        expect(resisted, greaterThan(0));
        expect(resisted, lessThan(44));
        expect(tester.getCenter(title), settledTitle);
        expect(tester.getCenter(avatar), settledAvatar);
        await pull.up();
        await tester.pumpAndSettle();
        expect(tester.getCenter(row), settledRow);
      }

      await tester.timedDrag(
        scroll,
        const Offset(0, 48),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();
      expect(wallpaper, findsNothing);
      await tester.timedDrag(
        scroll,
        const Offset(0, 145),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();
      expect(wallpaper, findsOneWidget);
      expect(find.text('Node'), findsOneWidget);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('About opens its offline documents and compacts its icon', (
    tester,
  ) async {
    const metadata = MethodChannel('meshgrame/app_info');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      metadata,
      (_) async => {
        'version': '9.1.2',
        'number': '815',
        'date': '2026-11-21T12:00:00Z',
      },
    );
    addTearDown(() => messenger.setMockMethodCallHandler(metadata, null));
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Version 9.1.2'), findsOneWidget);
    expect(find.textContaining('Build 815'), findsOneWidget);
    expect(find.textContaining('Build date'), findsOneWidget);
    expect(find.byType(ProfileWallpaper), findsNothing);
    final icon = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName.endsWith('meshgrame-icon.png'),
    );
    final expanded = tester.getRect(icon);
    await tester.dragFrom(const Offset(380, 460), const Offset(0, -300));
    await tester.pumpAndSettle();
    final compact = tester.getRect(icon);
    expect(compact.width, lessThan(expanded.width));
    expect(compact.top, lessThan(expanded.top));
    expect(find.text('Meshgram'), findsOneWidget);
    await tester.tap(find.text('License agreement'));
    await tester.runAsync(() async {
      await tester.pumpAndSettle();
      await rootBundle.loadString('assets/about/license-agreement.md');
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Прокшин Руслан Владимирович'), findsOneWidget);
    expect(find.textContaining('## 1. Стороны'), findsNothing);
    expect(find.text('1. Стороны и предмет соглашения'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Licenses'));
    await tester.runAsync(() async {
      await tester.pump();
      await rootBundle.loadString('assets/about/third-party.json');
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Material Icons'));
    await tester.runAsync(() async {
      await tester.pump();
      await rootBundle.loadString('assets/about/apache-2.0.txt');
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('TERMS AND CONDITIONS FOR USE'), findsOneWidget);
  });

  testWidgets('node map opens the profile of a located node', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = tester.view.padding;
    addTearDown(tester.view.reset);
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: const [MeshCoreAdapter(), MeshtasticAdapter()],
      preview: true,
    );
    Peer? opened;
    try {
      final positioned = controller.nodes.first;
      final unmapped = controller.nodes.last;
      final lastSeen = DateTime(2024, 12, 31, 18);
      controller.cache!.observations[positioned.id] = NodeObservation(
        position: controller.nodeObservation(positioned.id)!.position,
        lastSeen: lastSeen,
      );
      controller.cache!.unread.remove(positioned.id);
      controller.cache!.observations.remove(unmapped.id);

      await tester.pumpWidget(
        MaterialApp(
          theme: const MeshStyle(true).theme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: MeshNodesPage(
            controller: controller,
            openChat: (_) async {},
            openProfile: (peer) async => opened = peer,
          ),
        ),
      );
      final calendar = MaterialLocalizations.of(
        tester.element(find.byType(MeshNodesPage)),
      );
      final stamp = find.text(calendar.formatShortDate(lastSeen));
      expect(stamp, findsOneWidget);
      expect(tester.getRect(stamp).right, lessThan(320));

      final map = find.byTooltip('Node map');
      expect(map, findsOneWidget);
      final sort = find.byTooltip('Sort by');
      expect(sort, findsOneWidget);
      expect(tester.getRect(map).right, lessThan(tester.getRect(sort).left));

      await tester.tap(map);
      await tester.pumpAndSettle();
      expect(find.text('Node map'), findsOneWidget);
      expect(find.byType(MeshMap), findsOneWidget);
      expect(tester.getRect(find.byType(MeshMapAttribution)).bottom, 640);
      expect(find.text(unmapped.name), findsNothing);

      await tester.tap(find.text(positioned.name));
      expect(opened, positioned);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });

  testWidgets('known position in a contact opens the interactive map', (
    tester,
  ) async {
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: const [MeshCoreAdapter(), MeshtasticAdapter()],
      preview: true,
    );
    try {
      final peer = controller.nodes.first;
      final position = controller.nodeObservation(peer.id)!.position!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NodeActionsPanel(controller: controller, peer: peer),
            ),
          ),
        ),
      );

      final preview = find.byType(MeshLocationPreview);
      expect(preview, findsOneWidget);
      await tester.ensureVisible(preview);
      expect(find.text('Last known position'), findsNothing);
      expect(find.text(formatMapCoordinates(position)), findsNothing);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(find.text(peer.name), findsOneWidget);
      final map = tester.widget<MeshMap>(find.byType(MeshMap));
      expect(map.interactive, isTrue);
      expect(map.pins.single.position, position);
      expect(
        find.text(formatMapCoordinates(position, digits: 6)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });

  testWidgets('map tap and pan keep the selected longitude in range', (
    tester,
  ) async {
    const initial = (latitude: 55.75, longitude: 179.999);
    NodePosition? tapped;
    NodePosition? moved;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeshMap(
              center: initial,
              zoom: 15,
              showCrosshair: true,
              loadTiles: false,
              onMapTap: (position) => tapped = position,
              onCenterChanged: (position) => moved = position,
            ),
          ),
        ),
      );
      final map = find.byType(FlutterMap);
      final layer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(layer.tileProvider, isNot(isA<NetworkTileProvider>()));
      await tester.tapAt(tester.getCenter(map) + const Offset(100, -55));
      await tester.pump(const Duration(milliseconds: 450));
      expect(tapped, isNotNull);
      expect(tapped!.longitude, inInclusiveRange(-180, -179.99));
      expect(tapped!.latitude, greaterThan(initial.latitude));
      await tester.drag(map, const Offset(-100, 55));
      await tester.pumpAndSettle();
      expect(moved, isNotNull);
      expect(moved!.longitude, inInclusiveRange(-180, -179.99));
      expect(moved!.latitude, greaterThan(initial.latitude));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('map attribution stays centered at the physical bottom edge', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = tester.view.padding;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    const initial = (latitude: 55.75, longitude: 37.625);
    NodePosition? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await pickNodePosition(context, initial);
              },
              child: const Text('Open map'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open map'));
    await tester.pumpAndSettle();
    expect(find.text('Map position'), findsNothing);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.text('55.750000, 37.625000'), findsOneWidget);
    final credit = find.text('© OpenStreetMap contributors');
    final creditButton = find.ancestor(
      of: credit,
      matching: find.byType(InkWell),
    );
    final bounds = tester.getRect(creditButton);
    expect(bounds.center.dx, 195);
    expect(bounds.bottom, 844);
    final color = tester
        .element(credit)
        .findAncestorWidgetOfExactType<Material>()!
        .color!;
    expect(color.a, allOf(greaterThan(0), lessThan(1)));
    expect(color.r, color.g);
    expect(color.g, color.b);
    final set = find.text('Set');
    expect(tester.getBottomLeft(set).dy, lessThan(810));
    await tester.tap(set);
    await tester.pumpAndSettle();
    expect(selected, initial);
  });

  testWidgets('page title and controls stay fixed when the body scrolls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinnedPageList(
            padding: const EdgeInsets.only(top: 18),
            header: PageHeading(
              'Radio settings',
              leading: IconButton(
                onPressed: () {},
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
              ),
            ),
            children: [
              for (var i = 0; i < 24; i++) ListTile(title: Text('Setting $i')),
            ],
          ),
        ),
      ),
    );
    final title = find.text('Radio settings');
    final back = find.byTooltip('Back');
    final titlePosition = tester.getTopLeft(title);
    final backPosition = tester.getTopLeft(back);
    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('Setting 0'), findsNothing);
    expect(tester.getTopLeft(title), titlePosition);
    expect(tester.getTopLeft(back), backPosition);
  });

  testWidgets(
    'radio search reaches hidden MeshCore Wi-Fi fields through the toggle',
    (tester) async {
      _reduceMotion(tester);
      const radio = (network: 'meshcore', device: 'test', name: 'Field radio');
      final link = _CoreSettingsLink()
        ..firmwareProtocol = 14
        ..wifiEnabled = false;
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _ProtocolTestTransport(link),
        adapters: const [MeshCoreAdapter()],
      );
      await controller.connect(radio);
      await tester.pumpWidget(
        MaterialApp(
          home: RadioSettingsPage(controller: controller, radio: radio),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Node profile'), findsOneWidget);

      final commands = link.commands.length;
      const query = 'пароль Wi‑Fi';
      final search = find.byKey(const ValueKey('radio-settings-search'));
      await tester.enterText(search, query);
      await tester.pumpAndSettle();
      expect(find.text('Wi-Fi password'), findsOneWidget);
      expect(link.commands.length, commands);
      await tester.tap(find.text('Network'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(search).controller!.text, query);
      final wifi = find.widgetWithText(SwitchListTile, 'Enable Wi-Fi');
      expect(wifi, findsOneWidget);
      expect(find.text('Wi-Fi password'), findsNothing);
      await tester.tap(wifi);
      await tester.pumpAndSettle();
      expect(find.text('Wi-Fi password'), findsOneWidget);
      expect(link.wifiEnabled, isFalse);
      await tester.tap(find.byTooltip('Save to radio'));
      await tester.pumpAndSettle();
      expect(link.wifiEnabled, isTrue);
      expect(find.text('Wi-Fi password'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Wi-Fi network'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      final disconnect = controller.disconnect(manual: false);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await disconnect;
      controller.dispose();
    },
  );

  testWidgets('radio keeps LoRa settings and readings in separate views', (
    tester,
  ) async {
    _reduceMotion(tester);
    const radio = (network: 'test', device: 'one', name: 'Field radio');
    final adapter = _FakeAdapter('test');
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: [adapter],
    );
    await controller.connect(radio);
    adapter.sessions.single.telemetrySettings = true;
    await tester.pumpWidget(
      MaterialApp(
        home: RadioSettingsPage(controller: controller, radio: radio),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Node name'), findsOneWidget);
    expect(find.text('Frequency'), findsNothing);
    expect(find.text('Battery voltage'), findsNothing);
    expect(find.text('Telemetry settings'), findsNothing);
    await tester.tap(find.text('LoRa settings'));
    await tester.pumpAndSettle();
    expect(find.text('Frequency'), findsOneWidget);
    await tester.tap(find.byTooltip('Back').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Telemetry'),
      130,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Telemetry'));
    await tester.pumpAndSettle();
    expect(find.text('Battery voltage'), findsOneWidget);
    expect(find.text('3.79 V'), findsOneWidget);
    expect(find.text('Frequency'), findsNothing);
    await tester.tap(find.text('Telemetry settings'));
    await tester.pumpAndSettle();
    expect(find.text('Sample interval'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'radio save check follows edits and back confirms unsaved settings',
    (tester) async {
      _reduceMotion(tester);
      const radio = (network: 'test', device: 'save', name: 'Field radio');
      final adapter = _FakeAdapter('test');
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: [adapter],
      );
      await controller.connect(radio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            dialogTheme: const DialogThemeData(
              constraints: BoxConstraints.tightFor(width: 240),
            ),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  radioSettingsRoute(
                    context,
                    RadioSettingsPage(controller: controller, radio: radio),
                  ),
                ),
                child: const Text('Open settings'),
              ),
            ),
          ),
        ),
      );
      Future<void> openSettings() async {
        await tester.tap(find.text('Open settings'));
        await tester.pumpAndSettle();
      }

      Future<void> press(String label) async {
        if (useIosControls) {
          final control = find.byWidgetPredicate(
            (widget) =>
                widget is IosControl && widget.properties['label'] == label,
          );
          final button = tester.widget<IosControl>(control);
          expect(button.properties['enabled'], isTrue);
          button.onSelect!(0);
        } else {
          final tooltip = find.byTooltip(label);
          await tester.tap(
            tooltip.evaluate().isEmpty ? find.text(label) : tooltip,
          );
        }
        await tester.pumpAndSettle();
      }

      Future<void> editName(String name) async {
        await tester.tap(find.text('Node name'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), name);
        await press('Done');
      }

      Future<void> leave() async {
        final context = tester.element(find.byType(RadioSettingsPage));
        if (Theme.of(context).platform == TargetPlatform.iOS) {
          await tester.dragFrom(const Offset(2, 200), const Offset(180, 0));
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
      }

      final check = find.byWidgetPredicate(
        (widget) => widget is GlassButton && widget.icon == Icons.check_rounded,
      );
      GlassButton save() => tester.widget<GlassButton>(check);
      final session = adapter.sessions.single;
      await openSettings();
      expect(save().onTap, isNull);
      await editName('Draft');
      expect(save().onTap, isNotNull);
      await editName('Test node');
      expect(save().onTap, isNull);
      await editName('Saved');
      await press('Save to radio');
      expect(session.radioName, 'Saved');
      expect(save().onTap, isNull);

      await editName('Keep editing');
      await press('Back');
      expect(find.text('Unsaved changes'), findsOneWidget);
      final buttons = find.descendant(
        of: find.byType(MeshDialog),
        matching: find.byType(GlassActionButton),
      );
      expect(buttons, findsNWidgets(3));
      expect(tester.widget<GlassActionButton>(buttons.first).primary, isTrue);
      final frames = [
        for (var i = 0; i < 3; i++) tester.getRect(buttons.at(i)),
      ];
      expect(frames.first.width, 200);
      for (var i = 1; i < frames.length; i++) {
        expect(frames[i].left, frames.first.left);
        expect(frames[i].right, frames.first.right);
        expect(frames[i].top - frames[i - 1].bottom, closeTo(8, .01));
      }
      await press('Stay');
      expect(save().onTap, isNotNull);
      await leave();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await press('Discard');
      expect(session.radioName, 'Saved');
      expect(find.text('Open settings'), findsOneWidget);

      await openSettings();
      await editName('Saved before leaving');
      await leave();
      await press('Save and leave');
      expect(find.text('Open settings'), findsOneWidget);
      expect(session.radioName, 'Saved before leaving');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'LAN add form switches protocol defaults and validates its host',
    (tester) async {
      final radio = lanRadio('meshtastic', 'meshradio.local', 4403);
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        lanTransport: _TestLanTransport(_TasticSettingsLink(), radio),
        adapters: [const MeshtasticAdapter(), const MeshCoreAdapter()],
      );
      await tester.pumpWidget(
        MaterialApp(home: RadioDiscoveryPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      final add = find.text('Connect over Wi-Fi');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('4403'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MeshCore').last);
      await tester.pumpAndSettle();
      expect(find.text('5000'), findsOneWidget);
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(find.text('Check the address'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  test(
    'service discovery requests both radios and adds strongest first',
    () async {
      final transport = _TestTransport()
        ..found = [
          (radio: (network: 'a', device: '1', name: 'First'), rssi: -87),
          (radio: (network: 'b', device: '2', name: 'Second'), rssi: -58),
        ];
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: transport,
        adapters: [_FakeAdapter('a'), _FakeAdapter('b')],
      );
      await controller.scan();
      expect(transport.scanned, {'a': 'a', 'b': 'b'});
      expect(controller.discovered.map((result) => result.radio.name), [
        'Second',
        'First',
      ]);
      controller.dispose();
    },
  );

  test(
    'MeshCore adds an interoperable hashtag channel without rewriting Public',
    () async {
      final link = _CoreSettingsLink();
      final session = const MeshCoreAdapter().createSession(link);
      try {
        await session.start();
        final channels = session as RadioChannelSession;
        final result = await channels.addChannel((
          action: ChannelAction.hashtag,
          name: 'test',
          secret: '',
          invitation: '',
        ));
        expect(result.peer.name, '#test');
        expect(link.channels[1]!.sublist(32), [
          0x9c,
          0xd8,
          0xfc,
          0xf2,
          0x2a,
          0x47,
          0x33,
          0x3b,
          0x59,
          0x1d,
          0x96,
          0xa2,
          0xb8,
          0x48,
          0xb7,
          0x3f,
        ]);
        expect(link.channels[0]!.take(6).toList(), 'Public'.codeUnits);
        expect(await (session as RadioOnboardingSession).setupSteps(), isEmpty);
      } finally {
        await session.close();
      }
    },
  );

  test('Meshtastic saves private channels in secondary slots and round-trips the invite', () async {
    final link = _TasticSettingsLink();
    final session = const MeshtasticAdapter().createSession(link);
    try {
      await session.start();
      final channels = session as RadioChannelSession;
      final result = await channels.addChannel((
        action: ChannelAction.createPrivate,
        name: 'Outdoor',
        secret: '',
        invitation: '',
      ));
      expect(result.peer.id, 'ch:1');
      final imported = await channels.addChannel((
        action: ChannelAction.invitation,
        name: '',
        secret: '',
        invitation: result.invitation!,
      ));
      expect(imported.peer, result.peer);
      expect(_varint(_fields(link.channels[0]!), 3), 1);
      expect(
        _buffer(_fields(_buffer(_fields(link.channels[1]!), 2)), 2),
        hasLength(32),
      );
      final steps = await (session as RadioOnboardingSession).setupSteps();
      expect(steps.last.fields.first.id, 'region');
    } finally {
      await session.close();
    }
  });

  testWidgets(
    'radar connects an unconfigured radio and opens channel actions',
    (tester) async {
      _reduceMotion(tester);
      const radio = (
        network: 'mesh-fixture',
        device: 'field',
        name: 'Field radio',
      );
      final adapter = _FakeAdapter('mesh-fixture');
      final transport = _TestTransport()..found = [(radio: radio, rssi: -62)];
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: transport,
        adapters: [adapter],
      );
      await tester.pumpWidget(
        MeshGrame(controller: controller, locale: const Locale('en')),
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a radio'));
      await tester.pumpAndSettle();
      expect(find.text('-62 dBm'), findsOneWidget);
      await tester.tap(find.text('Field radio'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 2'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Field router');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 2'), findsOneWidget);
      await tester.tap(find.text('Save to radio'));
      await tester.pumpAndSettle();
      expect(adapter.sessions.single.radioName, 'Field router');
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New chat'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SheetBody),
          matching: find.text('Local channel'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('New channel'));
      await tester.pumpAndSettle();
      expect(find.text('Create a private channel'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('QR scan frame covers the preview and matches its scan window', (
    tester,
  ) async {
    final platform = MobileScannerPlatform.instance;
    MobileScannerPlatform.instance = _TestCamera();
    addTearDown(() => MobileScannerPlatform.instance = platform);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 760);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const MaterialApp(home: MeshQrScannerPage(title: 'Contact QR code')),
    );
    await tester.pumpAndSettle();
    final scanner = find.byType(MobileScanner);
    final viewport = tester.getSize(scanner);
    final window = tester.widget<MobileScanner>(scanner).scanWindow!;
    expect(window.center, viewport.center(Offset.zero));
    expect(window.width, window.height);
    expect(window.width, lessThan(viewport.shortestSide));
    final mask = find.descendant(
      of: scanner,
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(mask), viewport);
    expect(tester.getCenter(find.text('Contact QR code')).dx, 195);
    final paste = find.widgetWithText(GlassActionButton, 'Paste a link');
    final captionWidth = tester.getSize(find.text('Paste a link')).width;
    expect(tester.getSize(paste).width, captionWidth.ceilToDouble() + 28);
    expect(tester.getCenter(paste).dx, 195);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'chat reactions support avatars, chip taps, double taps and details',
    (tester) async {
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshCoreAdapter(), MeshtasticAdapter()],
        preview: true,
      );
      final cache = controller.cache!;
      final peer = cache.peers['ch:0']!;
      cache.identities['node:a'] = (
        publicKey: 'a' * 64,
        type: null,
        shortName: null,
      );
      cache.radioPublicKey = 'b' * 64;
      final message = MeshMessage(
        id: 'packet-test',
        chat: peer.id,
        author: 'Мира Соколова',
        text: 'Trail check',
        time: DateTime.now(),
        delivery: Delivery.received,
        remoteId: '56',
        packet: const MessagePacket(hops: 2, hopLimit: 1, rssi: -108),
      );
      cache.messages.add(message);
      cache.reactions.addAll([
        MeshReaction(peer.id, '56', 'a', '👍', time: message.time),
        MeshReaction(peer.id, '56', '419', '🔥'),
        MeshReaction(peer.id, '56', 'a', '🎉'),
        MeshReaction(peer.id, '56', 'b', '🎉'),
      ]);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 760);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: MeshChatPage(controller: controller, peer: peer),
        ),
      );
      await tester.pumpAndSettle();
      final bubble = find.text('Trail check');
      final menu = find.byKey(const ValueKey('message-menu'));
      final chips = find.byType(MessageReactionChips);
      Finder tag(String label) =>
          find.descendant(of: chips, matching: find.text(label));
      final avatars = find.descendant(
        of: chips,
        matching: find.byType(ReactionAvatar),
      );
      expect(avatars, findsNWidgets(2));
      expect(
        tester.widget<ReactionAvatar>(avatars.first).author.name,
        'Мира Соколова',
      );
      expect(
        tester.widget<ReactionAvatar>(avatars.first).author.hasKey,
        isTrue,
      );
      expect(
        find.descendant(
          of: chips,
          matching: find.byIcon(Icons.priority_high_rounded),
        ),
        findsOneWidget,
      );
      expect(tag('2'), findsOneWidget);
      expect(
        tester.getCenter(tag('👍')).dx,
        lessThan(tester.getCenter(avatars.first).dx),
      );

      await tester.tap(tag('👍'));
      await tester.pumpAndSettle();
      expect(
        controller.reactionsFor(message).where((item) => item.own).single.emoji,
        '👍',
      );
      expect(tag('2'), findsNWidgets(2));

      await tester.tap(bubble);
      await tester.pump(const Duration(milliseconds: 65));
      await tester.tap(bubble);
      await tester.pumpAndSettle();
      expect(tag('❤️'), findsOneWidget);
      expect(find.text('Message info'), findsNothing);

      await tester.tap(bubble);
      await tester.pump(const Duration(milliseconds: 360));
      await tester.pumpAndSettle();
      expect(find.byTooltip('All emoji'), findsOneWidget);
      await tester.drag(find.byTooltip('React 👍'), const Offset(-90, 0));
      await tester.pumpAndSettle();
      expect(menu, findsOneWidget);
      final previewLayer = find.byKey(const ValueKey('message-menu-preview'));
      final preview = find.descendant(of: previewLayer, matching: bubble);
      expect(
        tester.getRect(preview).bottom,
        lessThan(tester.getRect(find.text('Reply')).top),
      );
      await tester.tapAt(tester.getCenter(preview));
      await tester.pumpAndSettle();
      expect(menu, findsNothing);

      await tester.longPress(bubble);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactions (6)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '👍 2'));
      await tester.pumpAndSettle();
      final author = find.widgetWithText(ListTile, 'Мира Соколова');
      await tester.tap(author);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final profile = find.byType(MeshChatProfile);
      expect(tester.widget<MeshChatProfile>(profile).peer.id, 'node:a');
      await tester.tap(
        find.descendant(of: profile, matching: find.byTooltip('Back')),
      );
      await tester.pumpAndSettle();
      expect(author, findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '🔥 1'));
      await tester.pumpAndSettle();
      expect(find.text('Unknown node'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to message menu'));
      await tester.pumpAndSettle();
      expect(find.text('Message info'), findsOneWidget);
      await tester.tapAt(const Offset(6, 6));
      await tester.pumpAndSettle();

      await tester.longPress(bubble);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Message info'));
      await tester.pumpAndSettle();
      final details = find.byType(MessageDetails);
      Finder metric(String label) =>
          find.descendant(of: details, matching: find.text(label));
      expect(metric('Meshtastic'), findsOneWidget);
      expect(metric('Hops'), findsOneWidget);
      expect(metric('-108 dBm'), findsOneWidget);
      expect(metric('SNR'), findsNothing);
      await tester.tapAt(tester.getCenter(metric('Hops')));
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
      await controller.disconnectRadio(controller.active!);
      await tester.pumpAndSettle();
      expect(controller.connected, isFalse);
      expect(tag('👍'), findsOneWidget);
      await tester.longPress(bubble);
      await tester.pumpAndSettle();
      expect(find.byTooltip('All emoji'), findsOneWidget);
      await tester.tap(find.byTooltip('All emoji'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('emoji-catalog')), findsOneWidget);
      expect(preview, findsOneWidget);
      await tester.tapAt(const Offset(6, 6));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('menu reaction lands in its chip on ${platform.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 760);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter(), MeshCoreAdapter()],
        preview: true,
      );
      final cache = controller.cache!;
      final peer = cache.peers['ch:0']!;
      final message = MeshMessage(
        id: 'reaction-flight-message',
        chat: peer.id,
        author: 'Mira',
        text: 'Choose a reaction',
        time: DateTime.now(),
        delivery: Delivery.received,
        remoteId: '56',
      );
      cache.messages.add(message);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: MeshChatPage(controller: controller, peer: peer),
        ),
      );
      await tester.pumpAndSettle();
      final bubble = find.text(message.text);
      final flight = find.byKey(const ValueKey('reaction-flight'));
      final chip = find.descendant(
        of: find.byType(MessageReactionChips),
        matching: find.text('👍'),
      );
      await tester.longPress(bubble);
      await tester.pumpAndSettle();
      final option = find.byTooltip('React 👍');
      final source = tester.getCenter(option);
      await tester.tap(option);
      for (var frame = 0; frame < 8 && flight.evaluate().isEmpty; frame++) {
        await tester.pump();
      }
      expect(flight, findsOneWidget);
      expect((tester.getCenter(flight) - source).distance, lessThan(2));
      expect(controller.reactionsFor(message).single.emoji, '👍');
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(of: chip, matching: find.byType(Opacity)).first,
            )
            .opacity,
        0,
      );
      final destination = tester.getCenter(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final middle = tester.getCenter(flight);
      if (platform == TargetPlatform.iOS) {
        expect(middle.dy, closeTo(source.dy - 30, 1));
      } else {
        expect(
          (middle - destination).distance,
          lessThan((source - destination).distance),
        );
      }
      await tester.pumpAndSettle();
      expect(flight, findsNothing);
      expect(chip, findsOneWidget);

      _reduceMotion(tester);
      await tester.pumpAndSettle();
      await tester.longPress(bubble);
      await tester.pumpAndSettle();
      final heart = find.byTooltip('React ❤️');
      await tester.ensureVisible(heart);
      await tester.tap(heart);
      await tester.pumpAndSettle();
      expect(flight, findsNothing);
      expect(
        controller.reactionsFor(message).map((reaction) => reaction.emoji),
        unorderedEquals(['👍', '❤️']),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets(
    'channel avatars follow sender groups and pin above the composer',
    (tester) async {
      _reduceMotion(tester);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 650);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter(), MeshCoreAdapter()],
        preview: true,
      );
      final cache = controller.cache!;
      final channel = cache.peers['ch:0']!;
      final newerSender = cache.peers['node:a']!;
      const olderSender = 'node:41072';
      final time = DateTime(2026, 11, 22, 12);
      cache.messages
        ..clear()
        ..addAll([
          for (var index = 0; index < 32; index++)
            MeshMessage(
              id: 'channel-$index',
              chat: channel.id,
              author: 'Same advertised name',
              text: 'Channel message $index',
              time: time.add(Duration(seconds: index)),
              delivery: Delivery.received,
              packet: MessagePacket(
                sender: index < 16 ? olderSender : newerSender.id,
              ),
            ),
        ]);
      controller.markChatsRead(['ch:0']);
      await tester.pumpWidget(
        MaterialApp(
          home: MeshChatPage(controller: controller, peer: channel),
        ),
      );
      await tester.pumpAndSettle();

      final newer = find.byKey(
        const ValueKey(('channel-author', 'channel-31')),
      );
      final older = find.byKey(
        const ValueKey(('channel-author', 'channel-15')),
      );
      final latest = find.byKey(const ValueKey(('bubble', 'channel-31')));
      final list = tester.widget<ChatMessageList>(find.byType(ChatMessageList));
      expect(
        tester.getRect(find.byType(Flow)).bottom,
        tester.getRect(find.byType(ChatMessageList)).bottom,
      );
      final viewportBottom =
          tester.getBottomLeft(find.byType(ChatMessageList)).dy -
          list.insets.bottom;
      expect(tester.getBottomLeft(newer).dy, closeTo(viewportBottom, .1));
      expect(
        tester.getBottomLeft(newer).dy,
        closeTo(tester.getBottomLeft(latest).dy, .1),
      );
      expect(
        tester.getTopLeft(latest).dx,
        greaterThan(tester.getTopRight(newer).dx),
      );
      expect(newer.hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey(('channel-author', 'channel-30'))),
        findsNothing,
      );

      await tester.drag(newer, const Offset(0, 150));
      await tester.pumpAndSettle();
      expect(list.controller!.offset, greaterThan(60));
      expect(tester.getBottomLeft(newer).dy, closeTo(viewportBottom, .1));
      final viewportHeight =
          tester.getSize(find.byType(Flow)).height - list.insets.vertical;
      final boundary = list.listController!.offsetForIndex(16);
      list.controller!.jumpTo(boundary - viewportHeight + 100);
      await tester.pumpAndSettle();
      expect(older.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomLeft(older).dy,
        lessThan(tester.getTopLeft(newer).dy),
      );

      final senderName = find.descendant(
        of: find.byKey(const ValueKey('channel-16')),
        matching: find.text('Same advertised name'),
      );
      await tester.tap(senderName);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MeshChatProfile>(find.byType(MeshChatProfile)).peer.id,
        newerSender.id,
      );
      Navigator.of(tester.element(find.byType(MeshChatProfile))).pop();
      await tester.pumpAndSettle();

      await tester.tap(newer);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final profile = tester.widget<MeshChatProfile>(
        find.byType(MeshChatProfile),
      );
      expect(profile.peer.id, newerSender.id);
      expect(profile.openNewChat, isTrue);
      Navigator.of(tester.element(find.byType(MeshChatProfile))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(older);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(MeshChatProfile), findsNothing);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text(olderSender), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'a reply scrolls to an offscreen original and highlights its bubble',
    (tester) async {
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter(), MeshCoreAdapter()],
        preview: true,
      );
      final cache = controller.cache!;
      final peer = cache.peers['node:a']!;
      final now = DateTime.now();
      cache.messages
        ..clear()
        ..addAll([
          for (var i = 0; i < 65; i++)
            MeshMessage(
              id: 'history-$i',
              chat: peer.id,
              author: peer.name,
              text: i == 14 ? 'Original sample' : 'History entry $i',
              delivery: Delivery.received,
              time: now.add(Duration(minutes: i)),
              remoteId: 'ref-$i',
              replyTo: i == 64 ? 'ref-14' : null,
            ),
        ]);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 730);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: MeshChatPage(controller: controller, peer: peer),
        ),
      );
      await tester.pumpAndSettle();
      final original = find.byKey(const ValueKey('history-14'));
      expect(original, findsNothing);
      await tester.tap(find.text('Original sample'));
      await tester.pump();
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(original, findsOneWidget);
      expect(tester.getCenter(original).dy, inInclusiveRange(165, 555));
      final paint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey(('bubble', 'history-14'))),
      );
      final highlight =
          (paint.painter as dynamic).highlight as Animation<double>;
      expect(highlight.value, greaterThan(0));
      await tester.pumpAndSettle();
      expect(highlight.value, 0);

      cache.messages.removeWhere((message) => message.id == 'history-14');
      controller.refreshNodePresence();
      final history = tester.widget<ChatMessageList>(
        find.byType(ChatMessageList),
      );
      history.controller!.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original message'));
      await tester.pumpAndSettle();
      expect(find.text('This message is no longer in local history'), findsOne);

      unawaited(
        openMeshMessage(
          tester.element(find.byType(MeshChatPage)),
          controller: controller,
          chatId: peer.id,
          messageId: 'history-22',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('history-22')).hitTestable(),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'a sent emoji uses sticker layout with the stamp above its reactions',
    (tester) async {
      final bundle = PlatformAssetBundle();
      await tester.runAsync(() => EmojiCatalog.load(bundle));
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshCoreAdapter(), MeshtasticAdapter()],
        preview: true,
      );
      final cache = controller.cache!;
      final peer = cache.peers['ch:0']!;
      final now = DateTime.now();
      cache.messages
        ..clear()
        ..addAll([
          for (final (index, text) in ['👩🏽‍💻', '👋👋', 'Hi 👋', '1'].indexed)
            MeshMessage(
              id: 'emoji-$index',
              chat: peer.id,
              author: 'Mira',
              text: text,
              time: now.subtract(Duration(minutes: 1, seconds: index)),
              delivery: Delivery.received,
              remoteId: '${31 + index}',
            ),
        ]);
      cache.radioPublicKey = 'b' * 64;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 760);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: bundle,
          child: MaterialApp(
            home: MeshChatPage(controller: controller, peer: peer),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final received = find.byKey(const ValueKey(('sticker', 'emoji-0')));
      expect(received, findsOneWidget);
      for (var i = 1; i <= 3; i++) {
        expect(find.byKey(ValueKey(('bubble', 'emoji-$i'))), findsOneWidget);
      }

      await tester.enterText(find.byType(TextField), '👋');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      final sent = controller.messages(peer.id).last;
      expect(sent.text, '👋');
      expect(sent.delivery, Delivery.acknowledged);
      final sticker = find.byKey(ValueKey(('sticker', sent.id)));
      final row = find.byKey(ValueKey(sent.id));
      expect(sticker, findsOneWidget);
      expect(find.byKey(ValueKey(('bubble', sent.id))), findsNothing);
      final size = tester.getSize(sticker);
      final emoji = find.descendant(of: sticker, matching: find.text('👋'));
      await tester.tap(emoji);
      await tester.pump(const Duration(milliseconds: 65));
      await tester.tap(emoji);
      await tester.pumpAndSettle();

      final chip = find.descendant(
        of: row,
        matching: find.byType(MessageReactionChips),
      );
      final reaction = find.descendant(of: chip, matching: find.text('❤️'));
      final avatar = find.descendant(
        of: chip,
        matching: find.byType(ReactionAvatar),
      );
      final status = find.descendant(
        of: sticker,
        matching: find.byIcon(Icons.done_all_rounded),
      );
      expect(tester.getSize(sticker), size);
      expect(tester.getRect(status).bottom, lessThan(tester.getRect(chip).top));
      expect(
        tester.getRect(chip).right,
        closeTo(tester.getRect(sticker).right, 1),
      );
      expect(
        tester.getCenter(reaction).dx,
        lessThan(tester.getCenter(avatar).dx),
      );

      await tester.longPress(emoji);
      await tester.pumpAndSettle();
      expect(find.text('Reactions (1)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'one reaction grows narrow bubbles while keeping the time with the reaction',
    (tester) async {
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter(), MeshCoreAdapter()],
        preview: true,
      );
      final cache = controller.cache!;
      final peer = cache.peers['node:a']!;
      final now = DateTime.now();
      final messages = [
        for (final (i, body) in [
          '.',
          'Short',
          'A much wider message',
          'A long first line\nNext line',
        ].indexed)
          MeshMessage(
            id: 'resize-$i',
            chat: peer.id,
            author: '',
            text: body,
            time: now.add(Duration(minutes: i)),
            delivery: Delivery.acknowledged,
            remoteId: 'resize-ref-$i',
          ),
      ];
      cache.messages
        ..clear()
        ..addAll(messages);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 760);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: MeshChatPage(controller: controller, peer: peer),
        ),
      );
      await tester.pumpAndSettle();
      Finder row(MeshMessage message) => find.byKey(ValueKey(message.id));
      Finder bubble(MeshMessage message) =>
          find.byKey(ValueKey(('bubble', message.id)));
      final widths = [
        for (final message in messages) tester.getSize(bubble(message)).width,
      ];
      for (final message in messages) {
        expect(await controller.react(peer, message, '👍'), isTrue);
      }
      await tester.pumpAndSettle();
      for (final (i, message) in messages.indexed) {
        final after = tester.getSize(bubble(message)).width;
        expect(after, i == 0 ? greaterThan(widths[i]) : closeTo(widths[i], 1));
        final chip = tester.getRect(
          find.descendant(
            of: row(message),
            matching: find.byType(MessageReactionChips),
          ),
        );
        final status = tester.getRect(
          find.descendant(
            of: row(message),
            matching: find.byIcon(Icons.done_all_rounded),
          ),
        );
        expect(chip.right, lessThan(status.left));
        expect(status.center.dy, inInclusiveRange(chip.top, chip.bottom));
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'short chat history resists vertical drags and springs back',
    (tester) async {
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter(), MeshCoreAdapter()],
        preview: true,
      );
      final cache = controller.cache!;
      final peer = cache.peers['node:a']!;
      cache.messages
        ..clear()
        ..add(
          MeshMessage(
            id: 'short-history',
            chat: peer.id,
            author: peer.name,
            text: 'Radio check',
            time: DateTime.now(),
            delivery: Delivery.received,
          ),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: MeshChatPage(controller: controller, peer: peer),
        ),
      );
      await tester.pumpAndSettle();

      final history = find.byType(Scrollable).first;
      final scroll = tester.state<ScrollableState>(history);
      expect(scroll.position.minScrollExtent, scroll.position.maxScrollExtent);
      final message = find.text('Radio check');
      final date = find.text('Today');
      final header = find.byWidgetPredicate(
        (widget) => widget is GlassButton && widget.label == 'Back',
      );
      final composer = find.byType(MessageInput);
      final resting = tester.getCenter(message);
      final restingDate = tester.getCenter(date);
      final restingHeader = tester.getCenter(header);
      final restingComposer = tester.getCenter(composer);

      for (final direction in [-1.0, 1.0]) {
        final gesture = await tester.startGesture(tester.getCenter(history));
        await gesture.moveBy(Offset(0, 24 * direction));
        await tester.pump();
        final beforePull = tester.getCenter(message).dy;
        await gesture.moveBy(Offset(0, 50 * direction));
        await tester.pump();
        final firstPull = tester.getCenter(message).dy;
        await gesture.moveBy(Offset(0, 50 * direction));
        await tester.pump();
        final secondPull = tester.getCenter(message).dy;
        expect((firstPull - beforePull) * direction, inExclusiveRange(0, 50));
        expect(
          (secondPull - firstPull) * direction,
          inExclusiveRange(0, (firstPull - beforePull).abs()),
        );
        expect(
          tester.getCenter(date).dy - restingDate.dy,
          closeTo(secondPull - resting.dy, 1),
        );
        expect(tester.getCenter(header), restingHeader);
        expect(tester.getCenter(composer), restingComposer);

        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          (tester.getCenter(message).dy - resting.dy).abs(),
          inExclusiveRange(0, (secondPull - resting.dy).abs()),
        );
        await tester.pumpAndSettle();
        expect(tester.getCenter(message).dy, closeTo(resting.dy, 1));
      }

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'Android leaves a home inset under the composer when the keyboard is hidden',
    (tester) async {
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter(), MeshCoreAdapter()],
        preview: true,
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 760);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: MeshChatPage(
            controller: controller,
            peer: controller.cache!.peers['ch:0']!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final composer = find.byType(TextField);
      expect(760 - tester.getBottomLeft(composer).dy, inInclusiveRange(34, 51));

      tester.view.viewInsets = const FakeViewPadding(bottom: 275);
      await tester.pumpAndSettle();
      expect(
        760 - 275 - tester.getBottomLeft(composer).dy,
        inInclusiveRange(0, 17),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'message time and delivery follow the last line inside the bubble',
    (tester) async {
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: [_FakeAdapter('test')],
      );
      await controller.connect((network: 'test', device: 'one', name: 'Radio'));
      final now = DateTime.now();
      const longLine = 'WWWWWWWWWWWWWWWWW';
      const wrapped = '$longLine\nOK';
      final messages = [
        ('Пинг', Delivery.acknowledged),
        (longLine, Delivery.unconfirmed),
        (wrapped, Delivery.unconfirmed),
        ('Слышу', Delivery.received),
      ];
      controller.cache!.messages.addAll([
        for (final (index, message) in messages.indexed)
          MeshMessage(
            id: 'stamp-$index',
            chat: _peer.id,
            author: '',
            text: message.$1,
            time: DateTime(now.year, now.month, now.day, 11, 20 + index),
            delivery: message.$2,
          ),
      ]);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
          home: MeshChatPage(controller: controller, peer: _peer),
        ),
      );
      await tester.pumpAndSettle();

      Rect lastLine(String text) {
        final finder = find.text(text);
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        return paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: text.length),
            )
            .last
            .toRect()
            .shift(tester.getTopLeft(finder));
      }

      for (final (text, time) in [
        ('Пинг', '11:20'),
        (wrapped, '11:22'),
        ('Слышу', '11:23'),
      ]) {
        final line = lastLine(text);
        final stamp = tester.getRect(find.text(time));
        expect(stamp.left, greaterThan(line.right));
        expect(stamp.center.dy, inInclusiveRange(line.top, line.bottom));
      }
      final longTime = tester.getRect(find.text('11:21'));
      final line = lastLine(longLine);
      expect(longTime.top, greaterThanOrEqualTo(line.bottom), reason: '$line');
      final shortTime = tester.getRect(find.text('11:20'));
      final check = tester.getRect(find.byIcon(Icons.done_all_rounded));
      expect(check.left, greaterThan(shortTime.right));
      expect(check.center.dy, closeTo(shortTime.center.dy, 0.5));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'retrying from the warning replaces the failed attempt in the chat',
    (tester) async {
      _reduceMotion(tester);
      const radio = (network: 'test', device: 'one', name: 'Field radio');
      final adapter = _FakeAdapter(radio.network);
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: [adapter],
      );
      await controller.connect(radio);
      final session = adapter.sessions.single..failSends = true;
      expect(await controller.send(_peer, 'Try this again'), isFalse);
      final failed = controller.messages(_peer.id).single;
      expect(failed.delivery, Delivery.failed);
      controller.setDraft(_peer.id, 'Another draft');
      await tester.pumpWidget(
        MaterialApp(
          home: MeshChatPage(controller: controller, peer: _peer),
        ),
      );
      await tester.pumpAndSettle();
      session.failSends = false;
      session.autoAcknowledge = false;
      await tester.tap(find.byIcon(Icons.error_outline_rounded));
      await tester.pump();
      final retried = controller.messages(_peer.id).single;
      expect(retried.id, isNot(failed.id));
      expect(retried.text, failed.text);
      expect(retried.delivery, Delivery.submitted);
      expect(controller.draft(_peer.id), 'Another draft');
      session.stream.add(DeliveryUpdate(failed.id, Delivery.acknowledged));
      expect(controller.messages(_peer.id).single.delivery, Delivery.submitted);
      session.stream.add(DeliveryUpdate(retried.id, Delivery.acknowledged));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(find.text('Try this again'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('tab fades leave shared chat rows and navigation visible', (
    tester,
  ) async {
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: const [MeshCoreAdapter(), MeshtasticAdapter()],
      preview: true,
    );
    await tester.pumpWidget(
      MeshGrame(controller: controller, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    double rowOpacity(String id) =>
        tester.widget<FadeTransition>(find.byKey(ValueKey(id))).opacity.value;
    void filter(int index) => tester
        .widget<ChatFolderTabs>(find.byType(ChatFolderTabs))
        .onSelect(index);
    filter(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(rowOpacity('ch:0'), closeTo(.5, .02));
    expect(rowOpacity('node:a'), 1);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ch:0')), findsNothing);
    filter(0);
    final appearing = find.byKey(const ValueKey('ch:0'));
    for (var frame = 0; frame < 13 && appearing.evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(appearing, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump(const Duration(milliseconds: 25));
    expect(rowOpacity('ch:0'), allOf(greaterThan(0), lessThan(1)));
    expect(rowOpacity('node:a'), 1);
    await tester.pumpAndSettle();
    final nav = find.byType(MeshNavigation);
    final navElement = tester.element(nav);
    tester.widget<MeshNavigation>(nav).onSelect(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.element(nav), same(navElement));
    expect(find.byType(ChatFolderTabs), findsOneWidget);
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('About'), findsOneWidget);
    expect(tester.element(nav), same(navElement));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'chat search shrinks into the pinned header and expands back at the top',
    (tester) async {
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshCoreAdapter(), MeshtasticAdapter()],
        preview: true,
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 465);
      tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
      tester.view.viewPadding = tester.view.padding;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await tester.pumpWidget(
        MeshGrame(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      final list = find.byKey(const PageStorageKey<String>('chats'));
      final heading = find.byType(PageHeading);
      final firstChat = find.text('Тропа');
      Finder glass(String label) => find.byWidgetPredicate(
        (widget) => widget is GlassButton && widget.label == label,
      );
      final fixedControls = [
        find.byWidgetPredicate(
          (widget) => widget is GlassActionButton && widget.label == 'Edit',
        ),
        glass('New chat'),
      ];
      final search = find.byKey(const ValueKey('chat-search-field'));
      final positions = fixedControls.map(tester.getRect).toList();
      final firstChatTop = tester.getTopLeft(firstChat).dy;
      final expanded = tester.getRect(search);
      expect(tester.getTopLeft(list).dy, 0);
      expect(tester.getTopLeft(heading).dy, greaterThanOrEqualTo(48));
      final gesture = await tester.startGesture(tester.getCenter(firstChat));
      await gesture.moveBy(const Offset(0, -20));
      await gesture.moveBy(const Offset(0, -22));
      await tester.pump();
      final mid = tester.getRect(search);
      expect(mid.width, lessThan(expanded.width));
      expect(mid.width, greaterThan(48));
      expect(mid.top, lessThan(expanded.top));
      await gesture.up(timeStamp: const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(tester.getRect(search), expanded);

      final closing = await tester.startGesture(tester.getCenter(firstChat));
      await closing.moveBy(const Offset(0, -20));
      await closing.moveBy(const Offset(0, -41));
      await tester.pump();
      expect(
        tester.getRect(search).width,
        inExclusiveRange(48, expanded.width),
      );
      await closing.up(timeStamp: const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(fixedControls.map(tester.getRect), positions);
      expect(tester.getTopLeft(firstChat).dy, lessThan(firstChatTop));
      final collapsed = tester.getRect(search);
      final compactButton = glass('Search');
      expect(collapsed.width, 48);
      expect(collapsed.center.dy, positions.last.center.dy);
      expect(collapsed.right, lessThan(positions.last.left));
      tester.widget<GlassButton>(compactButton).onTap!();
      await tester.pumpAndSettle();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final input = tester.widget<TextField>(find.byType(TextField));
        expect(input.textAlign, TextAlign.start);
        expect(input.textAlignVertical, TextAlignVertical.center);
        expect(
          tester.getCenter(find.text('Search')).dx,
          tester.getCenter(search).dx,
        );
      } else {
        expect(
          find.byWidgetPredicate(
            (widget) => widget is IosControl && widget.kind == 'chatSearch',
          ),
          findsOneWidget,
        );
      }
      expect(tester.getRect(search).width, greaterThan(collapsed.width));
      tester.widget<GlassButton>(glass('Close search')).onTap!();
      await tester.pumpAndSettle();
      expect(tester.getRect(search), collapsed);
      final opening = await tester.startGesture(tester.getCenter(firstChat));
      await opening.moveBy(const Offset(0, 20));
      await opening.moveBy(const Offset(0, 38));
      await tester.pump();
      expect(
        tester.getRect(search).width,
        inExclusiveRange(48, expanded.width),
      );
      await opening.up(timeStamp: const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(tester.getRect(search), expanded);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();

      Future<double> titleWidth(String name) async {
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
        final capsule = find.ancestor(
          of: find.text(name),
          matching: find.byType(GlassSurface),
        );
        final width = tester.getSize(capsule).width;
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        return width;
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        final short = await titleWidth('Тропа');
        final long = await titleWidth('Мира Соколова');
        expect(short, lessThan(150));
        expect(long, greaterThan(short + 24));
      }
      await tester.drag(firstChat, const Offset(0, -125));
      await tester.pumpAndSettle();
      expect(tester.getRect(search).width, 48);
      await tester.drag(list, const Offset(0, 125));
      await tester.pumpAndSettle();
      expect(tester.getRect(search), expanded);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'sent text moves before the transport receipt and respects reduced motion',
    (tester) async {
      const radio = (network: 'test', device: 'one', name: 'Field radio');
      final adapter = _FakeAdapter(radio.network);
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: [adapter],
      );
      await controller.connect(radio);
      final session = adapter.sessions.single..autoAcknowledge = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MeshChatPage(controller: controller, peer: _peer),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'On the ridge');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      final flight = find.byKey(const ValueKey('sending-text-flight'));
      expect(flight, findsOneWidget);
      final source = tester.getTopLeft(flight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(flight).dy, lessThan(source.dy));
      final sent = controller.messages(_peer.id).single;
      expect(sent.delivery, Delivery.submitted);
      await tester.pump(const Duration(milliseconds: 350));
      expect(flight, findsNothing);
      session.stream.add(DeliveryUpdate(sent.id, Delivery.acknowledged));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(flight, findsNothing);

      _reduceMotion(tester);
      session.autoAcknowledge = true;
      await tester.enterText(find.byType(TextField), 'Ready');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(flight, findsNothing);
      expect(controller.messages(_peer.id), hasLength(2));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'outbox waits for its profile and requires a retry after failure',
    (tester) async {
      const first = (network: 'test', device: 'one', name: 'Field radio');
      const second = (network: 'test', device: 'two', name: 'Backup radio');
      final adapter = _FakeAdapter(first.network);
      final store = MeshStore(await SharedPreferences.getInstance());
      var foreground = false;
      final controller = MeshController(
        store: store,
        transport: _TestTransport(),
        adapters: [adapter],
        isChatForeground: () => foreground,
      );
      await controller.connect(first);
      final firstSession = adapter.sessions.single..failSends = true;
      expect(
        await controller.enqueueRadioMessage(_peer, 'Radio check'),
        isTrue,
      );
      final queued = controller.outboxFor(_peer.id).single;
      expect(store.loadOutbox().single.status, OutboxStatus.waiting);
      expect(controller.messages(_peer.id), isEmpty);
      await controller.connect(second);
      foreground = true;
      await controller.flushOutbox();
      expect(controller.outboxFor(_peer.id), isEmpty);
      expect(controller.messages(_peer.id), isEmpty);
      await controller.connect(first);
      await tester.pumpAndSettle();
      final failed = controller.messages(_peer.id).single;
      final review = controller.outboxFor(_peer.id).single;
      expect(review.id, queued.id);
      expect(review.status, OutboxStatus.uncertain);
      expect(review.attemptId, failed.id);
      expect(
        OutboxMessage.decode(
          review.withChanges(status: OutboxStatus.sending).toJson(),
        )?.status,
        OutboxStatus.uncertain,
      );
      firstSession.failSends = false;
      await controller.flushOutbox();
      expect(controller.messages(_peer.id).single.id, failed.id);
      expect(await controller.retryMessage(_peer, failed.id), isFalse);
      controller.setDraft(_peer.id, 'Keep this draft');
      expect(await controller.updateOutbox(review, _peer, retry: true), isTrue);
      await tester.pumpAndSettle();
      expect(controller.outboxFor(_peer.id), isEmpty);
      expect(
        controller.messages(_peer.id).single.delivery,
        Delivery.acknowledged,
      );
      expect(controller.messages(_peer.id).single.id, isNot(failed.id));
      expect(controller.draft(_peer.id), 'Keep this draft');
      controller.dispose();
    },
  );

  test('a radio loss after handoff does not resend the outbox item', () async {
    const radio = (network: 'test', device: 'one', name: 'Field radio');
    final adapter = _FakeAdapter(radio.network);
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: [adapter],
    );
    await controller.connect(radio);
    final completion = Completer<void>();
    adapter.sessions.single
      ..autoAcknowledge = false
      ..sendCompletion = completion;
    expect(
      await controller.enqueueRadioMessage(_peer, 'Status from the ridge'),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.outboxFor(_peer.id).single.status, OutboxStatus.sending);
    final attempt = controller.messages(_peer.id).single;
    await controller.disconnectRadio(radio);
    completion.complete();
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.outboxFor(_peer.id).single.status,
      OutboxStatus.uncertain,
    );
    expect(controller.messages(_peer.id).single.delivery, Delivery.unconfirmed);
    await controller.connect(radio);
    await Future<void>.delayed(Duration.zero);
    expect(controller.messages(_peer.id).single.id, attempt.id);
    expect(
      controller.outboxFor(_peer.id).single.status,
      OutboxStatus.uncertain,
    );
    controller.dispose();
  });

  testWidgets('holding a disabled send arrow opens the offline radio outbox', (
    tester,
  ) async {
    _reduceMotion(tester);
    final store = MeshStore(await SharedPreferences.getInstance());
    final controller = MeshController(
      store: store,
      transport: _TestTransport(),
      adapters: const [MeshtasticAdapter()],
      preview: true,
    );
    final profile = controller.active!;
    final peer = controller.cache!.peers['node:a']!;
    final messages = controller.messages(peer.id).length;
    await tester.pumpWidget(
      MaterialApp(
        home: MeshChatPage(controller: controller, peer: peer),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ready at the pass');
    await tester.pumpAndSettle();
    await controller.disconnectRadio(profile);
    await tester.pumpAndSettle();
    await tester.longPress(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send when the radio connects'));
    await tester.pumpAndSettle();
    expect(controller.draft(peer.id), isEmpty);
    expect(controller.messages(peer.id), hasLength(messages));
    expect(store.loadOutbox().single.text, 'Ready at the pass');
    await tester.tap(find.byTooltip('Radio outbox'));
    await tester.pumpAndSettle();
    expect(find.text('Waiting to send'), findsOneWidget);
    expect(find.text('Radio disconnected'), findsOneWidget);
    await tester.longPress(find.text('Ready at the pass'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Ready at the ridge');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.loadOutbox().single.text, 'Ready at the ridge');
    await tester.longPress(find.text('Ready at the ridge'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from outbox'));
    await tester.pumpAndSettle();
    expect(store.loadOutbox(), isEmpty);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  for (final network in ['meshtastic', 'meshcore']) {
    testWidgets('selected excerpts and text forwarding on $network', (
      tester,
    ) async {
      _reduceMotion(tester);
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter(), MeshCoreAdapter()],
        preview: true,
      );
      if (network == 'meshcore') {
        await controller.connect(controller.radios.last);
      }
      final peer = controller.cache!.peers['node:a']!;
      final source = controller
          .messages(peer.id)
          .firstWhere((message) => message.text.contains('гребне'));
      await tester.pumpWidget(
        MaterialApp(
          home: MeshChatPage(controller: controller, peer: peer),
        ),
      );
      await tester.pumpAndSettle();
      final sourceBubble = find.byKey(ValueKey(('bubble', source.id)));
      await tester.longPress(sourceBubble);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quote selection'));
      await tester.pumpAndSettle();
      const selected = 'гребне';
      final offset = source.text.indexOf(selected);
      tester
          .widget<SelectableText>(find.byType(SelectableText))
          .onSelectionChanged!(
        TextSelection(
          baseOffset: offset,
          extentOffset: offset + selected.length,
        ),
        SelectionChangedCause.longPress,
      );
      await tester.pump();
      await tester.tap(find.text('Quote'));
      await tester.pumpAndSettle();
      if (network == 'meshtastic') {
        expect(controller.replyDraft(peer.id)?.id, source.id);
        expect(controller.replyDraftExcerpt(peer.id)?.text, selected);
        final restored = ChatCache.fromJson(controller.cache!.toJson());
        expect(restored.replyExcerpts[peer.id]?.offset, offset);
        await tester.enterText(find.byType(TextField), 'OK');
        await tester.pump();
        await tester.tap(find.byTooltip('Send'));
        await tester.pumpAndSettle();
        final sent = controller.messages(peer.id).last;
        expect(sent.replyTo, controller.referenceFor(source));
        expect(sent.replyExcerpt?.text, selected);
      } else {
        expect(controller.replyDraft(peer.id), isNull);
        expect(controller.draft(peer.id), '«$selected»\n');
      }
      await tester.longPress(sourceBubble);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forward as text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Тропа'));
      await tester.pumpAndSettle();
      expect(controller.draft('ch:0'), '${source.author}:\n${source.text}');
      expect(controller.messages('ch:0'), hasLength(1));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.longPress(sourceBubble);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forward as text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved Messages'));
      await tester.tap(find.text('Тропа'));
      await tester.tap(find.text('Contacts'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        peer.name.split(' ').first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, peer.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepare · 3'));
      await tester.pumpAndSettle();
      expect(controller.isMessageSaved(source), isTrue);
      expect(controller.draft(peer.id), contains(source.text));
      expect(controller.draft('ch:0').split(source.text), hasLength(3));
      expect(controller.messages('ch:0'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('quick phrases are edited locally and append to a draft', (
    tester,
  ) async {
    _reduceMotion(tester);
    final store = MeshStore(await SharedPreferences.getInstance());
    final transport = _TestTransport();
    final controller = MeshController(
      store: store,
      transport: transport,
      adapters: const [MeshtasticAdapter()],
      preview: true,
    );
    final peer = controller.cache!.peers['node:a']!;
    final messages = controller.messages(peer.id).length;
    controller.setDraft(peer.id, 'Team:');
    await tester.pumpWidget(
      MaterialApp(
        home: MeshChatPage(controller: controller, peer: peer),
      ),
    );
    await tester.pumpAndSettle();
    final phraseButton = find.byTooltip('Quick phrases');
    final attachmentButton = find.byTooltip('Attachments');
    final counter = find.text('5 chars · 5/200 B');
    void expectCenteredCounter() {
      expect(
        tester.getCenter(counter).dx,
        closeTo(tester.getCenter(find.byType(MeshChatPage)).dx, .1),
      );
    }

    void expectAlignedButtons() {
      expect(
        tester.getCenter(phraseButton).dx,
        tester.getCenter(attachmentButton).dx,
      );
    }

    expectAlignedButtons();
    expectCenteredCounter();
    controller.setReplyDraft(peer.id, controller.messages(peer.id).first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cancel reply'), findsOneWidget);
    expectAlignedButtons();
    controller.setReplyDraft(peer.id, null);
    await tester.pumpAndSettle();

    await tester.tap(phraseButton);
    await tester.pumpAndSettle();
    final strip = find.byKey(const ValueKey('quick-phrase-scroll'));
    expectCenteredCounter();
    expect(
      tester.getBottomLeft(counter).dy,
      lessThan(tester.getTopLeft(strip).dy),
    );
    expect(find.byTooltip('Collapse quick phrases'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    await tester.tapAt(const Offset(7, 140));
    await tester.pumpAndSettle();
    expect(strip, findsNothing);
    await tester.tap(phraseButton);
    await tester.pumpAndSettle();
    expect(find.text('I’m here'), findsOneWidget);
    await tester.tap(find.text('I’m here'));
    await tester.pumpAndSettle();
    expect(controller.draft(peer.id), 'Team: I’m here');
    expect(find.byType(BottomSheet), findsNothing);
    expect(strip, findsNothing);

    await tester.tap(phraseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand quick phrases'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    Finder inSheet(Finder child) => find.descendant(of: sheet, matching: child);
    expect(inSheet(find.byType(Divider)), findsNWidgets(2));
    expect(inSheet(find.byIcon(Icons.edit_outlined)), findsNothing);
    await tester.longPress(inSheet(find.text('I’m here')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'At the ridge');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.quickPhrases?.first, 'At the ridge');
    await tester.tap(inSheet(find.text('At the ridge')));
    await tester.pumpAndSettle();
    expect(controller.draft(peer.id), 'Team: I’m here At the ridge');
    expect(strip, findsNothing);
    expectAlignedButtons();
    expect(controller.messages(peer.id), hasLength(messages));
    expect(transport.links, isEmpty);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('quick phrase strip grows before revealing its contents', (
    tester,
  ) async {
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: const [MeshtasticAdapter()],
      preview: true,
    );
    final peer = controller.cache!.peers['node:a']!;
    await tester.pumpWidget(
      MaterialApp(
        home: MeshChatPage(controller: controller, peer: peer),
      ),
    );
    await tester.pumpAndSettle();
    final trigger = find.byTooltip('Quick phrases');
    final strip = find.byType(QuickPhraseStrip);
    final phrase = find.descendant(of: strip, matching: find.text('I’m here'));
    await tester.tap(trigger);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    final openingWidth = tester.getSize(strip).width;
    expect(openingWidth, greaterThan(48));
    expect(phrase, findsNothing);
    await tester.pumpAndSettle();
    expect(tester.getSize(strip).width, greaterThan(openingWidth));
    expect(phrase, findsOneWidget);
    await tester.tap(phrase);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 185));
    expect(strip, findsOneWidget);
    expect(phrase, findsNothing);
    await tester.pumpAndSettle();
    expect(strip, findsNothing);
    expect(trigger, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'iOS quick phrases use the native glass button as a passive background',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (_) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
      final store = MeshStore(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickPhraseStrip(
              store: store,
              onSelect: null,
              onExpand: null,
              progress: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final glass = tester.widget<IosControl>(find.byType(IosControl));
      expect(glass.kind, 'button');
      expect(glass.properties['enabled'], isTrue);
      expect(glass.properties['readOnly'], isTrue);
      expect(glass.onSelect, isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets('radio status replaces the draft counter until connected', (
    tester,
  ) async {
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: const [MeshtasticAdapter()],
      preview: true,
    );
    final radio = controller.active!;
    await controller.disconnectRadio(radio);
    final peer = controller.cache!.peers['node:a']!;
    controller.setDraft(peer.id, 'Test');
    await tester.pumpWidget(
      MaterialApp(
        home: MeshChatPage(controller: controller, peer: peer),
      ),
    );
    await tester.pumpAndSettle();
    final disconnected = find.text('Radio disconnected');
    final connected = find.text('Connection established');
    final counter = find.text('4 chars · 4/200 B');
    final field = find.descendant(
      of: find.byType(MessageInput),
      matching: find.byType(TextField),
    );
    TextField editor() => tester.widget<TextField>(field);
    expect(disconnected, findsOneWidget);
    expect(
      tester.widget<Text>(disconnected).style?.color,
      const MeshStyle(false).error,
    );
    expect(counter, findsNothing);
    expect(editor().enabled, isFalse);
    await tester.tap(field, warnIfMissed: false);
    await tester.pump();
    expect(editor().focusNode!.hasFocus, isFalse);
    expect(editor().controller!.text, 'Test');

    await controller.connect(radio);
    await tester.pumpAndSettle();
    expect(disconnected, findsNothing);
    expect(connected, findsOneWidget);
    expect(counter, findsNothing);
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();
    expect(connected, findsNothing);
    expect(counter, findsOneWidget);
    expect(editor().enabled, isTrue);
    await tester.tap(field);
    await tester.pump();
    expect(editor().focusNode!.hasFocus, isTrue);

    await controller.disconnectRadio(radio);
    await tester.pumpAndSettle();
    expect(editor().enabled, isFalse);
    expect(editor().focusNode!.hasFocus, isFalse);
    expect(controller.draft(peer.id), 'Test');
    await controller.connect(radio);
    await tester.pumpAndSettle();
    expect(connected, findsOneWidget);
    await controller.disconnectRadio(radio);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(disconnected, findsOneWidget);
    expect(counter, findsNothing);
    expect(connected, findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('the quick phrase pull can be reversed before release', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 760);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final messenger = tester.binding.defaultBinaryMessenger;
    var readyHaptics = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate' &&
          call.arguments == 'HapticFeedbackType.mediumImpact') {
        readyHaptics++;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final store = MeshStore(await SharedPreferences.getInstance());
    await store.setQuickPhrases([
      for (var index = 1; index <= 8; index++) 'Quick reply $index',
    ]);
    final controller = MeshController(
      store: store,
      transport: _TestTransport(),
      adapters: const [MeshtasticAdapter()],
      preview: true,
    );
    final peer = controller.cache!.peers['node:a']!;
    await tester.pumpWidget(
      MaterialApp(
        home: MeshChatPage(controller: controller, peer: peer),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Quick phrases'));
    await tester.pumpAndSettle();
    final strip = find.byKey(const ValueKey('quick-phrase-scroll'));
    expect(
      find.descendant(of: strip, matching: find.byType(VerticalDivider)),
      findsWidgets,
    );
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: strip, matching: find.byType(Scrollable)),
        )
        .position;
    final sheet = find.byType(BottomSheet);
    await tester.drag(strip, const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    await tester.drag(strip, const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(sheet, findsNothing);

    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    final arrow = find.byKey(const ValueKey('pull-arrow'));
    final pencil = find.byKey(const ValueKey('quick-phrase-pencil'));
    double arrowScale() =>
        tester.widget<Transform>(arrow).transform.entry(0, 0);
    final reversed = await tester.startGesture(tester.getCenter(strip));
    await reversed.moveBy(const Offset(-25, 0));
    await reversed.moveBy(const Offset(-24, 0));
    await tester.pumpAndSettle();
    expect(arrow, findsOneWidget);
    expect(readyHaptics, 0);
    final initialScale = arrowScale();

    await reversed.moveBy(const Offset(-45, 0));
    await tester.pumpAndSettle();
    expect(arrowScale(), greaterThan(initialScale));
    expect(readyHaptics, 1);
    expect(sheet, findsNothing);
    await reversed.moveBy(const Offset(56, 0));
    await tester.pumpAndSettle();
    expect(arrowScale(), lessThan(initialScale));
    await reversed.moveBy(const Offset(25, 0));
    await tester.pumpAndSettle();
    expect(pencil, findsOneWidget);
    expect(arrow, findsNothing);
    await reversed.up();
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(readyHaptics, 1);

    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    final confirmed = await tester.startGesture(tester.getCenter(strip));
    await confirmed.moveBy(const Offset(-25, 0));
    await confirmed.moveBy(const Offset(-75, 0));
    await tester.pumpAndSettle();
    expect(readyHaptics, 2);
    expect(sheet, findsNothing);
    await confirmed.up();
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);
    expect(readyHaptics, 2);
    await tester.tap(find.byTooltip('Add phrase'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Added from the list');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.quickPhrases?.last, 'Added from the list');
    expect(controller.draft(peer.id), isEmpty);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('local folders and message pins survive a cache reload', (
    tester,
  ) async {
    _reduceMotion(tester);
    final transport = _TestTransport();
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: transport,
      adapters: const [MeshtasticAdapter()],
      preview: true,
    );
    final peer = controller.cache!.peers['node:a']!;
    final message = controller.messages(peer.id).first;
    await tester.pumpWidget(
      MeshGrame(controller: controller, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unread'), findsNothing);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(peer.name));
    await tester.tap(find.text('Тропа'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.text('New folder'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), ' Field team ');
    await tester.pump();
    await tester.tap(find.descendant(of: dialog, matching: find.text('Add')));
    await tester.pumpAndSettle();
    final folder = controller.chatFolders.single.id;
    expect(find.text('Field team'), findsOneWidget);
    expect(find.byTooltip('Delete folder Field team'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    controller.toggleFolderPin(folder, peer.id);
    controller.setPinnedMessage(peer.id, message.id);
    final cache = ChatCache.fromJson(controller.cache!.toJson());
    expect(cache.folders[folder]?.name, 'Field team');
    expect(cache.folders[folder]?.chats, {peer.id, 'ch:0'});
    expect(cache.folders[folder]?.pinned, [peer.id]);
    expect(cache.pinnedMessages[peer.id], message.id);

    await tester.pumpAndSettle();
    final row = find.text(peer.name);
    expect(
      tester.getTopLeft(row).dy,
      lessThan(tester.getTopLeft(find.text('Тропа')).dy),
    );
    expect(find.text('Илья Ветров'), findsNothing);
    await tester.tap(row);
    await tester.pumpAndSettle();
    final pin = find.text('Pinned message');
    await tester.tap(pin);
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey(('bubble', message.id))).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Unpin message'));
    await tester.pumpAndSettle();
    expect(controller.pinnedMessageId(peer.id), isNull);
    expect(transport.links, isEmpty);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('folder tabs reorder on hold and delete without deleting chats', (
    tester,
  ) async {
    _reduceMotion(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: const [MeshtasticAdapter()],
      preview: true,
    );
    final first = controller.saveChatFolder(
      name: 'Field team',
      chats: {'node:a'},
    );
    final second = controller.saveChatFolder(
      name: 'Survey crew',
      chats: {'ch:0'},
    );
    await tester.pumpWidget(
      MeshGrame(controller: controller, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final scroll = find.byKey(const ValueKey('chat-folder-scroll'));
    await tester.drag(scroll, const Offset(-260, 0));
    await tester.pumpAndSettle();
    final tabs = tester.widget<CustomScrollView>(scroll).controller!;
    expect(tabs.offset, greaterThan(0));
    tabs.jumpTo(tabs.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final left = tester.getCenter(find.text('Field team'));
    final right = tester.getCenter(find.text('Survey crew'));
    expect(find.text('Survey crew').hitTestable(), findsOneWidget);
    final hold = await tester.startGesture(right);
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await hold.moveBy(const Offset(-64, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await hold.moveTo(left + const Offset(35, 0));
    await tester.pump(const Duration(milliseconds: 240));
    await hold.up();
    await tester.pumpAndSettle();
    expect(controller.chatFolders.map((folder) => folder.id), [second, first]);
    expect(
      tester.getCenter(find.text('Survey crew')).dx,
      lessThan(tester.getCenter(find.text('Field team')).dx),
    );

    tabs.jumpTo(tabs.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final deleteButton = find.byTooltip('Delete folder Field team');
    final close = find.descendant(
      of: deleteButton,
      matching: find.byIcon(Icons.close_rounded),
    );
    expect(
      tester.getCenter(close).dx,
      greaterThan(tester.getCenter(find.text('Field team')).dx),
    );
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.chatFolders.map((folder) => folder.id), [second]);
    expect(controller.messages('node:a'), isNotEmpty);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('iOS scrolls folder tabs without changing the selection', (
    tester,
  ) async {
    _reduceMotion(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: const [MeshtasticAdapter()],
      preview: true,
    );
    final names = [for (var i = 1; i <= 8; i++) 'Field $i'];
    for (final name in names) {
      await tester.pump();
      controller.saveChatFolder(name: name, chats: {'node:a'});
    }
    await tester.pumpWidget(
      MeshGrame(controller: controller, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final scroll = find.byKey(const ValueKey('native-chat-folder-scroll'));
    expect(tester.getSize(scroll), const Size(352, 34));
    expect(tester.getTopLeft(scroll).dx, 19);
    expect(
      tester.getCenter(scroll).dy,
      tester.getCenter(find.byType(ChatFolderTabs)).dy,
    );
    final scrollController = tester
        .widget<SingleChildScrollView>(scroll)
        .controller!;
    final picker = find.byType(ChatFolderTabs);
    int selected() => tester.widget<ChatFolderTabs>(picker).selected;
    IosControl tabs() => tester.widget<IosControl>(
      find.descendant(
        of: picker,
        matching: find.byWidgetPredicate(
          (widget) => widget is IosControl && widget.kind == 'folderTabs',
        ),
      ),
    );
    await tester.drag(scroll, const Offset(-550, 0));
    await tester.pumpAndSettle();
    expect(scrollController.offset, greaterThan(0));
    expect(selected(), 0);
    final displayed = tabs().properties['labels']! as List<String>;
    expect(displayed, ['All', 'Direct', 'Channels', ...names]);
    final label = names.last;
    final end = scrollController.position.maxScrollExtent;
    scrollController.jumpTo(end - 18);
    await tester.pumpAndSettle();
    tabs().onSelect!(displayed.indexOf(label));
    await tester.pumpAndSettle();
    expect(selected(), names.indexOf(label) + 3);
    expect(scrollController.offset, end);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('chat preview expands from the row on ${platform.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 760);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshtasticAdapter()],
        preview: true,
      );
      final peer = controller.cache!.peers['node:a']!;
      const row = Rect.fromLTWH(0, 125, 390, 68);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Builder(
            builder: (context) => Scaffold(
              body: Stack(
                children: [
                  Positioned.fromRect(
                    rect: row,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () => unawaited(
                        showMeshChatPreview(
                          context,
                          controller,
                          peer,
                          row,
                          sourceRow: const Text('Row snapshot'),
                        ),
                      ),
                      child: const Center(child: Text('Source chat')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final card = find.byKey(const ValueKey('chat-preview-card'));
      await tester.longPress(find.text('Source chat'));
      await tester.pump();
      expect(tester.getRect(card), row);
      expect(find.text('Row snapshot'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 65));
      expect(tester.getRect(card).height, inExclusiveRange(row.height, 480));
      await tester.pumpAndSettle();
      final expanded = tester.getRect(card);
      expect(expanded.height, 480);
      expect(find.text('Row snapshot'), findsNothing);
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(tester.getRect(card), expanded);
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester.getRect(card).height,
        inExclusiveRange(row.height, expanded.height),
      );
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      expect(tester.getCenter(find.text('Source chat')), row.center);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  for (final network in ['meshtastic', 'meshcore']) {
    testWidgets('shared $network channel and contact links become chat cards', (
      tester,
    ) async {
      _reduceMotion(tester);
      final adapter = _FakeAdapter(network);
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: [adapter],
      );
      await controller.connect((
        device: 'link-radio',
        name: 'Radio',
        network: network,
      ));
      final session = adapter.sessions.single..acceptsInvitations = true;
      final field =
          (CodedBufferWriter()
                ..writeField(2, PbFieldType.OY, List<int>.filled(16, 5))
                ..writeField(3, PbFieldType.OY, utf8.encode('Trail Team')))
              .toBuffer();
      final blob = (CodedBufferWriter()..writeField(1, PbFieldType.OY, field))
          .toBuffer();
      final invite = network == 'meshcore'
          ? 'meshcore://channel/add?name=Trail%20Team&secret=${'05' * 16}'
          : 'https://meshtastic.org/e/?add=true#${base64Url.encode(blob).replaceAll('=', '')}';
      final contact = compactContactLink((
        network: network,
        id: network == 'meshcore' ? 'node:${'a' * 12}' : 'node:42',
        name: 'Base Operator',
        publicKey: 'a' * 64,
        type: network == 'meshcore' ? 1 : null,
        shortName: null,
      ), 200)!;
      for (final (index, text) in [
        'Contact for overnight $contact',
        'Join us ($invite)',
      ].indexed) {
        session.stream.add(
          TextReceived(
            MeshMessage(
              id: 'shared-link-$index',
              chat: _peer.id,
              author: 'Mira',
              text: text,
              time: DateTime.now(),
              delivery: Delivery.received,
            ),
            _peer,
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          home: MeshChatPage(controller: controller, peer: _peer),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Base Operator'), findsOneWidget);
      expect(find.text('Contact for overnight'), findsOneWidget);
      expect(find.text('Trail Team'), findsOneWidget);
      expect(find.text('Join us'), findsOneWidget);
      expect(find.textContaining('secret='), findsNothing);
      expect(session.lastChannelRequest, isNull);
      await tester.tap(find.text('Join channel'));
      await tester.pumpAndSettle();
      expect(session.lastChannelRequest?.invitation, invite);
      expect(controller.cache!.peers['ch:2']?.name, 'Trail Team');
      expect(find.byType(MeshChatPage), findsOneWidget);
      expect(
        tester.widget<MeshChatPage>(find.byType(MeshChatPage)).peer.id,
        'ch:2',
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('new messages promote chats below persistent chat pins', (
    tester,
  ) async {
    _reduceMotion(tester);
    final adapter = _FakeAdapter('meshtastic');
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: _TestTransport(),
      adapters: [adapter],
    );
    await controller.connect((
      device: 'pin-order-radio',
      name: 'Radio',
      network: adapter.id,
    ));
    final session = adapter.sessions.single;
    const first = (
      id: 'node:first',
      name: 'First',
      writable: true,
      channel: false,
    );
    const second = (
      id: 'node:second',
      name: 'Second',
      writable: true,
      channel: false,
    );
    const third = (
      id: 'node:third',
      name: 'Third',
      writable: true,
      channel: false,
    );
    void receive(Peer peer, int index) {
      session.stream.add(
        TextReceived(
          MeshMessage(
            id: '${peer.id}-$index',
            chat: peer.id,
            author: peer.name,
            text: 'Packet $index',
            // A radio's clock may lag behind even though the message arrived last.
            time: DateTime(2026, 11, 24, 12, 30 - index),
            delivery: Delivery.received,
          ),
          peer,
        ),
      );
    }

    receive(first, 1);
    receive(second, 2);
    receive(third, 3);
    await tester.pumpWidget(
      MeshGrame(controller: controller, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    double top(Peer peer) => tester.getTopLeft(find.text(peer.name)).dy;
    expect(top(third), lessThan(top(second)));
    Finder action(String label) => find.descendant(
      of: find.byKey(const ValueKey('chat-preview-actions')),
      matching: find.text(label),
    );
    await tester.longPress(find.text(first.name));
    await tester.pumpAndSettle();
    await tester.tap(action('Pin chat'));
    await tester.pumpAndSettle();
    expect(top(first), lessThan(top(third)));
    receive(second, 4);
    await tester.pumpAndSettle();
    expect(top(first), lessThan(top(second)));
    expect(top(second), lessThan(top(third)));
    final restored = ChatCache.fromJson(controller.cache!.toJson());
    expect(restored.pinnedChats, [first.id]);
    await tester.longPress(find.text(first.name));
    await tester.pumpAndSettle();
    await tester.tap(action('Unpin chat'));
    await tester.pumpAndSettle();
    expect(top(second), lessThan(top(first)));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('chat preview leaves unread messages and row swipes intact', (
    tester,
  ) async {
    _reduceMotion(tester);
    final transport = _TestTransport();
    final controller = MeshController(
      store: MeshStore(await SharedPreferences.getInstance()),
      transport: transport,
      adapters: const [MeshtasticAdapter()],
      preview: true,
    );
    final peer = controller.cache!.peers['node:a']!;
    final unread = controller.cache!.unread[peer.id];
    expect(unread, greaterThan(0));
    final latest = controller.messages(peer.id).last;
    await tester.pumpWidget(
      MeshGrame(controller: controller, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final row = find.text(peer.name);
    final preview = find.byKey(const ValueKey('open-chat-preview'));
    await tester.longPress(row);
    await tester.pumpAndSettle();
    expect(preview, findsOneWidget);
    final menu = find.byKey(const ValueKey('chat-preview-actions'));
    final previewHistory = find.descendant(
      of: preview,
      matching: find.byType(SingleChildScrollView),
    );
    expect(
      tester.widget<SingleChildScrollView>(previewHistory).clipBehavior,
      Clip.none,
    );
    final heading = find.ancestor(
      of: find.descendant(of: preview, matching: find.text(peer.name)),
      matching: find.byType(GlassSurface),
    );
    expect(tester.widget<GlassSurface>(heading.first).modal, isTrue);
    expect(
      tester.getTopLeft(menu).dy,
      greaterThan(tester.getBottomLeft(preview).dy),
    );
    final delete = find.descendant(
      of: menu,
      matching: find.text('Delete chat'),
    );
    expect(delete.hitTestable(), findsOneWidget);
    final text = find.descendant(of: preview, matching: find.text(latest.text));
    expect(
      DefaultTextStyle.of(tester.element(text)).style.decoration,
      isNot(TextDecoration.underline),
    );
    expect(find.byKey(ValueKey(('bubble', latest.id))), findsOneWidget);
    expect(find.byType(MeshChatPage), findsNothing);
    expect(controller.cache!.unread[peer.id], unread);
    expect(transport.links, isEmpty);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(preview, findsNothing);
    expect(controller.cache!.unread[peer.id], unread);
    await tester.longPress(row);
    await tester.pumpAndSettle();
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.byType(MeshChatPage), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.drag(row, const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Delete').hitTestable(), findsOneWidget);
    expect(preview, findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'chat profile, search and switching radios use the two-tab interface',
    (tester) async {
      _reduceMotion(tester);
      final controller = MeshController(
        store: MeshStore(await SharedPreferences.getInstance()),
        transport: _TestTransport(),
        adapters: const [MeshCoreAdapter(), MeshtasticAdapter()],
        preview: true,
      );
      controller.setAppearance('dark');
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = await tester.runAsync(
        () => rootBundle.loadString('assets/emoji/unicode17.json'),
      );
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: _TestEmojiBundle(catalog!),
          child: MeshGrame(controller: controller, locale: const Locale('ru')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Мира Соколова'), findsOneWidget);
      expect(find.text('Heltec V3'), findsNothing);
      final navigation = find.byType(MeshNavigation);
      final initialBottom = tester.getBottomLeft(navigation).dy;
      final searchField = tester.widget<TextField>(find.byType(TextField));
      expect(
        (searchField.decoration!.border as OutlineInputBorder).borderRadius,
        BorderRadius.circular(999),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 275);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(navigation).dy, initialBottom);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Каналы'));
      await tester.pumpAndSettle();
      expect(find.text('Мира Соколова'), findsNothing);
      await tester.tap(find.text('Личные'));
      await tester.pumpAndSettle();
      expect(find.text('Мира Соколова'), findsOneWidget);
      await tester.tap(find.text('Мира Соколова'));
      await tester.pumpAndSettle();
      expect(find.text('Сообщение'), findsOneWidget);
      final input = find.byType(TextField);
      await tester.enterText(input, 'Привет 👋');
      await tester.pumpAndSettle();
      expect(find.text('8 симв. · 17/200 Б'), findsOneWidget);
      await tester.tapAt(const Offset(195, 180));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).focusNode?.hasFocus, isFalse);
      await tester.enterText(input, '');
      await tester.pumpAndSettle();
      final target = find.text('Вижу метку. Скоро будем.');
      await tester.drag(target, const Offset(-115, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Отменить ответ'), findsOneWidget);
      await tester.tap(find.byTooltip('Отменить ответ'));
      await tester.pumpAndSettle();
      await tester.longPress(target);
      await tester.pumpAndSettle();
      expect(find.text('Ответить'), findsOneWidget);
      await tester.tap(find.byTooltip('Реакция 👍'));
      await tester.pumpAndSettle();
      expect(find.text('👍'), findsOneWidget);
      await tester.longPress(target);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Все эмодзи'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Флаги'));
      await tester.tap(find.byTooltip('Флаги'));
      await tester.pumpAndSettle();
      expect(find.text('Флаги'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Россия');
      await tester.pumpAndSettle();
      expect(find.text('🇷🇺'), findsOneWidget);
      await tester.tap(find.text('🇷🇺'));
      await tester.pumpAndSettle();
      expect(find.text('🇷🇺'), findsOneWidget);
      await tester.tap(find.byTooltip('Профиль чата'));
      await tester.pumpAndSettle();
      expect(find.text('Идентификатор'), findsOneWidget);
      await tester.tap(find.text('Поиск'));
      await tester.pumpAndSettle();
      expect(find.text('Поиск в чате'), findsOneWidget);
      await tester.tap(find.byTooltip('Закрыть поиск'));
      await tester.pumpAndSettle();
      expect(find.text('Мира Соколова'), findsOneWidget);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      expect(find.text('Heltec V3'), findsWidgets);
      expect(find.text('≈-59 dBm'), findsOneWidget);
      expect(find.byTooltip('Отключить').hitTestable(), findsNothing);
      await tester.drag(find.text('Heltec V3').last, const Offset(-145, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Отключить').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Удалить').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Отключить'));
      await tester.pumpAndSettle();
      expect(find.text('≈-59 dBm'), findsNothing);
      await tester.tap(find.text('T-Deck Plus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Чаты'));
      await tester.pumpAndSettle();
      expect(find.text('Антон Белов'), findsOneWidget);
      expect(find.text('Мира Соколова'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
