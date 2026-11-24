// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:typed_data';

import 'message_packet.dart';
import 'nodes.dart';

enum Delivery {
  received,
  queued,
  submitted,
  relayed,
  acknowledged,
  unconfirmed,
  failed;

  bool get awaitingReceipt =>
      this == queued || this == submitted || this == relayed;
  bool get canRetry => this == failed || this == unconfirmed;
}

enum LinkState { offline, connecting, online }

typedef Radio = ({String network, String device, String name});
typedef DiscoveredRadio = ({Radio radio, int rssi});
typedef RadioIdentity = ({
  String? hardwareId,
  int? nodeNumber,
  String? publicKey,
});
typedef Peer = ({String id, String name, bool writable, bool channel});

String radioKey(Radio radio) => '${radio.network}/${radio.device}';

typedef LanEndpoint = ({String host, int port});

LanEndpoint? lanEndpoint(Radio radio) {
  final uri = Uri.tryParse(radio.device);
  if (uri == null || uri.scheme != 'tcp' || !uri.hasPort) return null;
  return (host: uri.host, port: uri.port);
}

String? usbPortOf(Radio radio) {
  final uri = Uri.tryParse(radio.device);
  return uri?.scheme == 'usb' && uri!.path.isNotEmpty ? uri.path : null;
}

typedef UsbPort = ({String path, String name});

Radio usbRadio(String network, UsbPort port) => (
  network: network,
  device: Uri(scheme: 'usb', path: port.path).toString(),
  name: port.name,
);

Radio lanRadio(String network, String host, int port, {String? name}) {
  final input = host.trim();
  final address = input.startsWith('[') && input.endsWith(']')
      ? input.substring(1, input.length - 1)
      : input;
  if (address.isEmpty ||
      !RegExp(r'^[a-z0-9_.:%-]+$', caseSensitive: false).hasMatch(address) ||
      port < 1 ||
      port > 65535) {
    throw const FormatException('Invalid local network address');
  }
  if (address.contains(':')) Uri.parseIPv6Address(address);
  final uri = Uri(scheme: 'tcp', host: address.toLowerCase(), port: port);
  return (network: network, device: uri.toString(), name: name ?? uri.host);
}

class MessageExcerpt {
  const MessageExcerpt(this.offset, this.text);

  final int offset;
  final String text;

  bool matches(String source) =>
      offset >= 0 && offset < source.length && source.startsWith(text, offset);

  List<Object> toJson() => [offset, text];

  static MessageExcerpt? decode(Object? value) {
    if (value case [final int offset, final String text]
        when offset >= 0 && text.isNotEmpty) {
      return MessageExcerpt(offset, text);
    }
    return null;
  }
}

class MeshMessage {
  const MeshMessage({
    required this.id,
    required this.chat,
    required this.author,
    required this.text,
    required this.time,
    required this.delivery,
    this.remoteId,
    this.replyTo,
    this.replyExcerpt,
    this.packet,
    this.isAttachment = false,
    this.suppressLinkPreview = false,
  });

  final String id, chat, author, text;
  final DateTime time;
  final Delivery delivery;
  final String? remoteId, replyTo;
  final MessageExcerpt? replyExcerpt;
  final MessagePacket? packet;
  final bool isAttachment;
  final bool suppressLinkPreview;
  bool get outgoing => delivery != Delivery.received;

  MeshMessage withDelivery(Delivery value) => withUpdate(delivery: value);

  MeshMessage withUpdate({
    Delivery? delivery,
    MessagePacket? packet,
    String? reference,
  }) => MeshMessage(
    id: id,
    chat: chat,
    author: author,
    text: text,
    time: time,
    delivery: delivery ?? this.delivery,
    remoteId: reference ?? remoteId,
    replyTo: replyTo,
    replyExcerpt: replyExcerpt,
    isAttachment: isAttachment,
    suppressLinkPreview: suppressLinkPreview,
    packet: packet == null ? this.packet : this.packet?.merge(packet) ?? packet,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'chat': chat,
    'author': author,
    'text': text,
    'time': time.millisecondsSinceEpoch,
    'delivery': delivery.name,
    'remoteId': ?remoteId,
    'replyTo': ?replyTo,
    'replyExcerpt': ?replyExcerpt?.toJson(),
    if (isAttachment) 'isAttachment': true,
    if (suppressLinkPreview) 'suppressLinkPreview': true,
    'packet': ?packet?.toJson(),
  };

  factory MeshMessage.fromJson(Map<String, Object?> json) => MeshMessage(
    id: json['id'] as String,
    chat: json['chat'] as String,
    author: json['author'] as String,
    text: json['text'] as String,
    time: DateTime.fromMillisecondsSinceEpoch(json['time'] as int),
    delivery: Delivery.values.byName(json['delivery'] as String),
    remoteId: json['remoteId'] as String?,
    replyTo: json['replyTo'] as String?,
    replyExcerpt: MessageExcerpt.decode(json['replyExcerpt']),
    isAttachment: json['isAttachment'] == true,
    suppressLinkPreview: json['suppressLinkPreview'] == true,
    packet: switch (json['packet']) {
      final Map value => MessagePacket.fromJson(value),
      _ => null,
    },
  );
}

String reactionEmojiKey(String emoji) => emoji.replaceAll('\ufe0f', '');

class MeshReaction {
  const MeshReaction(
    this.chat,
    this.target,
    this.actor,
    this.emoji, {
    this.own = false,
    this.time,
  });
  final String chat, target, actor, emoji;
  final bool own;
  final DateTime? time;
  String get emojiKey => reactionEmojiKey(emoji);

  bool matches(MeshReaction other) =>
      chat == other.chat &&
      target == other.target &&
      actor == other.actor &&
      emojiKey == other.emojiKey;

  Map<String, Object> toJson() => {
    'chat': chat,
    'target': target,
    'actor': actor,
    'emoji': emoji,
    'own': own,
    'time': ?time?.millisecondsSinceEpoch,
  };

  factory MeshReaction.fromJson(Map<String, Object?> json) => MeshReaction(
    json['chat'] as String,
    json['target'] as String,
    json['actor'] as String,
    json['emoji'] as String,
    own: json['own'] as bool,
    time: switch (json['time']) {
      final int value => DateTime.fromMillisecondsSinceEpoch(value),
      _ => null,
    },
  );
}

abstract interface class RadioLink {
  bool contains(String characteristic);
  Future<StreamSubscriptionHandle> subscribe(
    String characteristic,
    void Function(Uint8List) onFrame,
  );
  Future<Uint8List> read(String characteristic);
  Future<void> write(String characteristic, List<int> bytes);
  Stream<void> get disconnected;
  Future<void> close();
}

abstract interface class StreamSubscriptionHandle {
  Future<void> cancel();
}

abstract interface class RadioTransport {
  Future<void> scan(
    Map<String, String> services,
    void Function(List<DiscoveredRadio>) update,
  );
  Future<void> stopScan();
  Future<RadioLink> connect(Radio radio, String service);
}

enum BluetoothProblem implements Exception {
  off,
  permission,
  location,
  unsupported,
  pairing,
}

abstract interface class BluetoothControl {
  Future<void> enableBluetooth();
}

/// Settings needed to carry a protocol's existing companion frames over TCP.
class LanRadioProtocol {
  const LanRadioProtocol({
    required this.port,
    required this.inputPrefix,
    required this.outputPrefix,
    required this.endian,
    required this.maxPayload,
    required this.rx,
    required this.tx,
    this.notice,
    this.bonjourService,
    this.wake = const [],
    this.heartbeat = const [],
  });

  final int port, maxPayload;
  final List<int> inputPrefix, outputPrefix, wake, heartbeat;
  final Endian endian;
  final String rx, tx;
  final String? notice, bonjourService;
}

abstract interface class NetworkLanAdapter {
  LanRadioProtocol get lan;
}

typedef UsbRadioProtocol = ({LanRadioProtocol framing, int baudRate});

abstract interface class NetworkUsbAdapter {
  UsbRadioProtocol get usb;
}

abstract interface class RadioUsbTransport {
  List<UsbPort> ports();
  Future<RadioLink> connect(String port, UsbRadioProtocol protocol);
}

abstract interface class NetworkBufferedMessages {
  NetworkEvent? bufferedMessage(
    Uint8List frame,
    Map<String, Peer> peers,
    int? localNode,
    DateTime receivedAt,
  );
}

abstract interface class RadioLanTransport {
  Future<void> scan(
    Map<String, LanRadioProtocol> protocols,
    void Function(List<DiscoveredRadio>) update,
  );
  Future<void> stopScan();
  Future<RadioLink> connect(LanEndpoint endpoint, LanRadioProtocol protocol);
}

class RadioNotNearby implements Exception {
  const RadioNotNearby();
}

sealed class NetworkEvent {
  const NetworkEvent();
}

final class DirectoryUpdate extends NetworkEvent {
  const DirectoryUpdate(
    this.peers, {
    this.name,
    this.identities = const {},
    this.radioPublicKey,
    this.radioHardwareId,
    this.radioNodeNumber,
    this.deviceInfo,
  });
  final Map<String, NodeIdentity> identities;
  final String? radioPublicKey;
  final String? radioHardwareId;
  final int? radioNodeNumber;
  final RadioDeviceInfo? deviceInfo;
  final List<Peer> peers;
  final String? name;

  RadioIdentity get radioIdentity => (
    hardwareId: radioHardwareId,
    nodeNumber: radioNodeNumber,
    publicKey: radioPublicKey,
  );
}

typedef RadioDeviceInfo = ({
  String? firmware,
  String? board,
  int? boardModel,
  String? build,
  String? protocol,
});

final class TextReceived extends NetworkEvent {
  const TextReceived(this.message, this.peer);
  final MeshMessage message;
  final Peer peer;
}

final class NodeObserved extends NetworkEvent {
  const NodeObserved(this.id, this.observation, {this.peer});
  final String id;
  final NodeObservation observation;
  final Peer? peer;
}

final class LocalNodePosition extends NetworkEvent {
  const LocalNodePosition(this.position);
  final NodePosition position;
}

final class DeliveryUpdate extends NetworkEvent {
  const DeliveryUpdate(this.id, this.delivery, {this.packet});
  final String id;
  final Delivery delivery;
  final MessagePacket? packet;
}

final class MessagePacketUpdated extends NetworkEvent {
  const MessagePacketUpdated(this.id, this.packet, {this.reference});
  final String id;
  final MessagePacket packet;
  final String? reference;
}

final class ReactionReceived extends NetworkEvent {
  const ReactionReceived(this.reaction);
  final MeshReaction reaction;
}

final class RouteTraceReceived extends NetworkEvent {
  const RouteTraceReceived(this.peer, this.request, this.fields);
  final String peer;
  final int request;
  final List<RadioField> fields;
}

enum RouteTraceFailure { rejected, rateLimited }

final class RouteTraceRejected extends NetworkEvent {
  const RouteTraceRejected(this.request, this.failure);
  final int request;
  final RouteTraceFailure failure;
}

final class RadioEnded extends NetworkEvent {
  const RadioEnded();
}

final class RadioRestartExpected extends NetworkEvent {
  const RadioRestartExpected({this.explicit = false});
  final bool explicit;
}

// A write reached the old session. Only its readback can run on the new one.
class RadioWriteInterrupted<T> implements Exception {
  const RadioWriteInterrupted(this.verify);
  final Future<T> Function(NetworkSession) verify;
}

typedef RadioBattery = ({int? percent, bool powered, bool estimated});

final class RadioBatteryChanged extends NetworkEvent {
  const RadioBatteryChanged(this.battery);
  final RadioBattery battery;
}

abstract interface class NetworkSession {
  Stream<NetworkEvent> get events;
  Future<void> start();
  int textLimit(Peer peer);
  Future<void> send(Peer peer, MeshMessage message);
  Future<void> close();
}

abstract interface class NetworkRadioIdentity {
  RadioIdentity get radioIdentity;
}

abstract interface class NetworkReactions {
  Future<void> react(Peer peer, String target, String emoji);
}

abstract interface class NetworkMessageActions implements NetworkReactions {
  String nextMessageReference();
}

abstract interface class NetworkMessageReferences {
  String? referenceFor(MeshMessage message);
}

abstract interface class NetworkAdapter {
  String get id;
  String get label;
  String get service;
  NetworkSession createSession(RadioLink link);
}

abstract interface class RadioSignalLink {
  Future<int?> readSignalRssi();
}

abstract interface class RadioLatencyLink {
  Future<Duration?> readLinkLatency();
}

enum RadioFieldSection {
  device,
  lora,
  telemetry,
  position,
  connectivity,
  bluetooth,
  power,
  display,
  security,
  routing,
  mqtt,
  sensors,
  notifications,
  contacts,
  serial,
  storeForward,
  rangeTest,
  quickMessages,
  audio,
  remoteHardware,
  neighborInfo,
  ambientLighting,
  detectionSensor,
  paxCounter,
  statusMessage,
  trafficManagement,
  tak,
  beacon,
  deviceUi,
}

abstract interface class NetworkMessageBudget {
  int messageBytes(Peer peer, String radioName);
}

enum RadioFieldKind { text, multiline, decimal, integer, toggle, choice }

class RadioField {
  const RadioField(
    this.id,
    this.title,
    this.russian,
    this.value, {
    this.kind = RadioFieldKind.text,
    this.section = RadioFieldSection.device,
    this.editable = true,
    this.secret = false,
    this.units,
    this.example,
    this.hops = const [],
    this.choices = const {},
  });

  final String id, title, russian, value;
  final RadioFieldKind kind;
  final RadioFieldSection section;
  final bool editable;
  final bool secret;
  final String? units, example;
  final List<RadioHop> hops;
  final Map<String, String> choices;
}

typedef RadioHop = ({String name, double? snr, int? rssi});

abstract interface class RadioSettingsSession {
  Future<List<RadioField>> readSettings();
  Future<void> writeSettings(Map<String, String> values);
}

abstract interface class RadioSettingsCatalog {
  List<RadioFieldSection> get extraSettings;
  Future<List<RadioField>> readSection(RadioFieldSection section);
  Future<void> writeSection(
    RadioFieldSection section,
    Map<String, String> values,
  );
}

abstract interface class RadioRestartSession {
  Future<void> restartRadio();
}

abstract interface class RadioTelemetrySession {
  Future<List<RadioField>> readTelemetry();
}

abstract interface class RadioBatteryReader {
  Future<RadioBattery?> readBattery();
}

enum ChannelAction {
  createPrivate,
  joinPrivate,
  publicChannel,
  hashtag,
  invitation,
}

typedef ChannelRequest = ({
  ChannelAction action,
  String name,
  String secret,
  String invitation,
});

typedef ChannelProvision = ({Peer peer, String? invitation});

abstract interface class RadioChannelSession {
  List<ChannelAction> get channelActions;
  Future<ChannelProvision> addChannel(ChannelRequest request);
}

abstract interface class RadioConversationSession {
  bool canRemovePeer(Peer peer);
  Future<void> removePeer(Peer peer);
  bool canShareChannel(Peer peer);
  Future<String> shareChannel(Peer peer);
}

abstract interface class RadioPositionSession {
  Future<void> setFixedPosition(NodePosition position);
}

typedef RadioSetupStep = ({
  String title,
  String russian,
  List<RadioField> fields,
});

abstract interface class RadioOnboardingSession {
  Future<List<RadioSetupStep>> setupSteps();
}

typedef NodeIdentity = ({String publicKey, int? type, String? shortName});

typedef ContactAttachment = ({
  String network,
  String id,
  String name,
  String publicKey,
  int? type,
  String? shortName,
});

abstract interface class NetworkContactCodes {
  Uri? contactCode(Peer peer, NodeIdentity identity);
  ({String id, String publicKey})? readContactCode(Uri uri);
  ContactAttachment? readContactAttachment(Uri uri);
}

abstract interface class RadioContactSession {
  Future<Peer> importContact(ContactAttachment contact);
}

abstract interface class RemoteAdminSession {
  bool canAdminister(Peer peer);
  bool get adminRequiresPassword;
  Future<RadioSettingsSession> openAdmin(Peer peer, String password);
}

class NodeAdminDenied implements Exception {
  const NodeAdminDenied({this.guest = false});
  final bool guest;
}

abstract interface class RemoteAdminConsole {
  Future<String> runCommand(String command);
}

abstract interface class RemoteNeighborTable {
  bool get canReadNeighbors;
  Future<String> readNeighbors();
}

abstract interface class RemoteNodePower {
  Future<void> setPower({required bool reboot});
}

enum NodeAction {
  trace,
  neighbors,
  position,
  telemetry,
  environment,
  identity,
  savedPath,
  resetPath,
  sensorLogin,
  favorite,
  ignore,
}

abstract interface class NetworkNodeActions {
  Set<NodeAction> nodeActions(Peer peer);
  Future<List<RadioField>> runNodeAction(
    Peer peer,
    NodeAction action, {
    bool enabled = true,
    String? password,
  });
}

abstract interface class NetworkRouteTracing {
  Duration get routeTraceInterval;
  DateTime? get routeTracePendingUntil;
  Future<void> startRouteTrace(Peer peer, int request);
}

List<RadioField> nodePositionFields(NodePosition position) => [
  RadioField(
    'lat',
    'Latitude',
    'Широта',
    position.latitude.toStringAsFixed(6),
    editable: false,
  ),
  RadioField(
    'lon',
    'Longitude',
    'Долгота',
    position.longitude.toStringAsFixed(6),
    editable: false,
  ),
];
