// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network.dart';
import 'nodes.dart';
import 'route_trace.dart';

class ChatCache {
  final peers = <String, Peer>{};
  final identities = <String, NodeIdentity>{};
  final observations = <String, NodeObservation>{};
  NodePosition? localPosition;
  final messages = <MeshMessage>[];
  final reactions = <MeshReaction>[];
  final routeTraces = <int, RouteTrace>{};
  DateTime? routeTraceCooldownUntil;
  final replies = <String, String>{};
  final unread = <String, int>{};
  final drafts = <String, String>{};
  final muted = <String>{};
  final unmuted = <String>{};
  final hiddenChats = <String>{};
  final keptChats = <String>{};
  final chatOrder = <String>[];
  final searchHistory = <String>[];
  String? radioPublicKey;
  String? radioHardwareId;
  int? radioNodeNumber;
  RadioDeviceInfo? deviceInfo;

  RadioIdentity get radioIdentity => (
    hardwareId: radioHardwareId,
    nodeNumber: radioNodeNumber,
    publicKey: radioPublicKey,
  );

  Map<String, Object> toJson() => {
    'peers': [
      for (final peer in peers.values)
        {
          'id': peer.id,
          'name': peer.name,
          'writable': peer.writable,
          'channel': peer.channel,
        },
    ],
    'identities': {
      for (final entry in identities.entries)
        entry.key: [
          entry.value.publicKey,
          entry.value.type,
          entry.value.shortName,
        ],
    },
    'messages': messages.map((message) => message.toJson()).toList(),
    'nodes': {
      for (final entry in observations.entries) entry.key: entry.value.toJson(),
    },
    if (localPosition case final value?)
      'localPosition': [value.latitude, value.longitude],
    'reactions': reactions.map((reaction) => reaction.toJson()).toList(),
    if (routeTraces.isNotEmpty)
      'routeTraces': routeTraces.values.map((trace) => trace.toJson()).toList(),
    'routeTraceCooldownUntil': ?routeTraceCooldownUntil?.millisecondsSinceEpoch,
    'replies': replies,
    'unread': unread,
    'drafts': drafts,
    'muted': muted.toList(),
    if (unmuted.isNotEmpty) 'unmuted': unmuted.toList(),
    'hiddenChats': hiddenChats.toList(),
    'keptChats': keptChats.toList(),
    'chatOrder': chatOrder,
    'searchHistory': searchHistory,
    'radioPublicKey': ?radioPublicKey,
    'radioHardwareId': ?radioHardwareId,
    'radioNodeNumber': ?radioNodeNumber,
    if (deviceInfo case final info?)
      'deviceInfo': [
        info.firmware,
        info.board,
        info.build,
        info.protocol,
        info.boardModel,
      ],
  };

  factory ChatCache.fromJson(Map<String, dynamic> json) {
    final cache = ChatCache()
      ..radioPublicKey = json['radioPublicKey'] as String?
      ..radioHardwareId = json['radioHardwareId'] as String?
      ..radioNodeNumber = json['radioNodeNumber'] as int?;
    if (json['deviceInfo'] case [
      String? firmware,
      String? board,
      String? build,
      String? protocol,
      ...final extra,
    ]) {
      cache.deviceInfo = (
        firmware: firmware,
        board: board,
        boardModel: extra.firstOrNull as int?,
        build: build,
        protocol: protocol,
      );
    }
    for (final item in json['peers'] as List) {
      final id = item['id'] as String;
      cache.peers[id] = (
        id: id,
        name: item['name'] as String,
        writable: item['writable'] as bool,
        channel: item['channel'] as bool,
      );
    }
    for (final entry in (json['identities'] as Map? ?? const {}).entries) {
      final data = entry.value as List;
      cache.identities[entry.key as String] = (
        publicKey: data[0] as String,
        type: data[1] as int?,
        shortName: data.length > 2 ? data[2] as String? : null,
      );
    }
    for (final item in json['messages'] as List) {
      final message = MeshMessage.fromJson(item as Map<String, dynamic>);
      cache.messages.add(switch (message.delivery) {
        Delivery.queued => message.withDelivery(Delivery.failed),
        Delivery.submitted ||
        Delivery.relayed => message.withDelivery(Delivery.unconfirmed),
        _ => message,
      });
    }
    if (json['nodes'] case final Map nodes) {
      for (final entry in nodes.entries) {
        cache.observations[entry.key as String] = NodeObservation.fromJson(
          entry.value as Map,
        );
      }
    } else {
      final now = DateTime.now();
      for (final message in cache.messages) {
        if (!message.outgoing && cache.peers[message.chat]?.channel == false) {
          cache.observe(
            message.chat,
            NodeObservation(lastSeen: message.time),
            now,
          );
        }
      }
    }
    if (json['localPosition'] case final List xy) {
      cache.localPosition = nodePosition(
        (xy[0] as num).toDouble(),
        (xy[1] as num).toDouble(),
      );
    }
    for (final item in json['reactions'] as List? ?? const []) {
      cache.reactions.add(
        MeshReaction.fromJson((item as Map).cast<String, Object?>()),
      );
    }
    for (final item in json['routeTraces'] as List? ?? const []) {
      final trace = RouteTrace.fromJson(item as Map);
      cache.routeTraces[trace.request] = trace;
    }
    if (json['routeTraceCooldownUntil'] case final int until) {
      cache.routeTraceCooldownUntil = DateTime.fromMillisecondsSinceEpoch(
        until,
      );
    }
    cache.replies.addAll(
      (json['replies'] as Map? ?? const {}).cast<String, String>(),
    );
    cache.unread.addAll((json['unread'] as Map).cast<String, int>());
    cache.drafts.addAll((json['drafts'] as Map).cast<String, String>());
    cache.muted.addAll((json['muted'] as List).cast<String>());
    cache.unmuted.addAll((json['unmuted'] as List? ?? const []).cast<String>());
    cache.hiddenChats.addAll(
      (json['hiddenChats'] as List? ?? const []).cast<String>(),
    );
    cache.keptChats.addAll(
      (json['keptChats'] as List? ?? const []).cast<String>(),
    );
    cache.chatOrder.addAll(
      (json['chatOrder'] as List? ?? const []).cast<String>(),
    );
    cache.searchHistory.addAll(
      (json['searchHistory'] as List? ?? []).cast<String>(),
    );
    return cache;
  }

  ChatCache();

  void mergeHistory(ChatCache other) {
    for (final peer in other.peers.values) {
      peers.putIfAbsent(peer.id, () => peer);
    }
    for (final entry in other.identities.entries) {
      identities.putIfAbsent(entry.key, () => entry.value);
    }
    final now = DateTime.now();
    for (final observation in other.observations.entries) {
      observe(observation.key, observation.value, now);
    }
    final byId = {for (final item in messages) item.id: item};
    for (final item in other.messages) {
      byId.update(item.id, (current) {
        final preferred =
            current.delivery != Delivery.acknowledged &&
                item.delivery == Delivery.acknowledged
            ? item
            : current;
        final supplemental = identical(preferred, current) ? item : current;
        final packet = preferred.packet;
        return preferred.withUpdate(
          packet: packet == null
              ? supplemental.packet
              : supplemental.packet?.merge(packet) ?? packet,
          reference: preferred.remoteId ?? supplemental.remoteId,
        );
      }, ifAbsent: () => item);
    }
    messages
      ..clear()
      ..addAll(byId.values)
      ..sort((a, b) => a.time.compareTo(b.time));
    final reactionsSeen = {
      for (final item in reactions)
        (item.chat, item.target, item.actor, item.emojiKey),
    };
    reactions.addAll(
      other.reactions.where(
        (item) => reactionsSeen.add((
          item.chat,
          item.target,
          item.actor,
          item.emojiKey,
        )),
      ),
    );
    for (final trace in other.routeTraces.values) {
      final existing = routeTraces[trace.request];
      if (existing == null ||
          (existing.receivedAt == null && !trace.pending) ||
          (existing.fields.every((field) => field.hops.isEmpty) &&
              trace.fields.any((field) => field.hops.isNotEmpty))) {
        routeTraces[trace.request] = trace;
      }
    }
    final cooldown = other.routeTraceCooldownUntil;
    if (cooldown != null &&
        (routeTraceCooldownUntil?.isBefore(cooldown) ?? true)) {
      routeTraceCooldownUntil = cooldown;
    }
    for (final entry in other.unread.entries) {
      unread.update(
        entry.key,
        (count) => count >= entry.value ? count : entry.value,
        ifAbsent: () => entry.value,
      );
    }
    for (final entry in other.drafts.entries) {
      drafts.putIfAbsent(entry.key, () => entry.value);
    }
    for (final entry in other.replies.entries) {
      replies.putIfAbsent(entry.key, () => entry.value);
    }
    muted.addAll(other.muted);
    unmuted.addAll(other.unmuted);
    hiddenChats.addAll(other.hiddenChats);
    keptChats.addAll(other.keptChats);
    chatOrder.addAll(
      other.chatOrder.where((id) => !chatOrder.contains(id)).toList(),
    );
    searchHistory.addAll(
      other.searchHistory.where((id) => !searchHistory.contains(id)).toList(),
    );
    localPosition ??= other.localPosition;
    radioHardwareId ??= other.radioHardwareId;
    radioNodeNumber ??= other.radioNodeNumber;
    radioPublicKey ??= other.radioPublicKey;
    deviceInfo ??= other.deviceInfo;
  }

  bool observe(String id, NodeObservation observation, DateTime now) {
    final prior = observations[id] ?? const NodeObservation();
    final next = prior.merge(observation, now);
    if (prior.lastSeen == next.lastSeen &&
        prior.position == next.position &&
        prior.hops == next.hops &&
        prior.channel == next.channel &&
        prior.viaMqtt == next.viaMqtt &&
        prior.favorite == next.favorite &&
        prior.ignored == next.ignored &&
        prior.role == next.role &&
        prior.canMessage == next.canMessage &&
        prior.boardModel == next.boardModel) {
      return false;
    }
    observations[id] = next;
    return true;
  }
}

class MeshStore {
  MeshStore(this.preferences);
  final SharedPreferences preferences;
  static const _key = 'meshgrame.original.v1.';
  static const _secrets = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );

  Future<String?> adminPassword(String id) =>
      _secrets.read(key: '${_key}admin.$id');

  Future<void> setAdminPassword(String id, String? password) => password == null
      ? _secrets.delete(key: '${_key}admin.$id')
      : _secrets.write(key: '${_key}admin.$id', value: password);

  List<Radio> get radios => [for (final record in radioProfiles) record.radio];

  List<({Radio radio, List<String> routes})> get radioProfiles {
    final data = preferences.getStringList('${_key}radios') ?? [];
    return [for (final entry in data) ?_record(entry)];
  }

  ({Radio radio, List<String> routes})? _record(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final Radio radio = (
        name: data['name'] as String,
        device: data['device'] as String,
        network: data['network'] as String,
      );
      final routes = (data['routes'] as List? ?? const [])
          .whereType<String>()
          .where((device) => device.isNotEmpty)
          .toList();
      return (radio: radio, routes: routes.isEmpty ? [radio.device] : routes);
    } on Object {
      return null;
    }
  }

  Future<bool> setRadios(
    List<Radio> radios, {
    Map<String, List<String>> routes = const {},
  }) => preferences.setStringList('${_key}radios', [
    for (final radio in radios)
      jsonEncode({
        'name': radio.name,
        'device': radio.device,
        'network': radio.network,
        'routes': ?routes[radioKey(radio)],
      }),
  ]);
  Set<String> get notificationOverrides =>
      (preferences.getStringList('${_key}notificationSettings') ?? const [])
          .toSet();
  Future<bool> setNotificationOverrides(Set<String> overrides) => preferences
      .setStringList('${_key}notificationSettings', overrides.toList());

  bool get hasConnectedProfiles =>
      preferences.containsKey('${_key}connectedProfiles');
  List<String> get connectedProfiles =>
      preferences.getStringList('${_key}connectedProfiles') ?? const [];
  Future<bool> setConnectedProfiles(Iterable<String> keys) =>
      preferences.setStringList('${_key}connectedProfiles', keys.toList());

  String? get active => preferences.getString('${_key}active');
  Future<bool> setActive(String value) =>
      preferences.setString('${_key}active', value);
  bool get autoConnect =>
      preferences.getBool('${_key}autoConnect') ??
      (active?.isNotEmpty ?? false);
  Future<bool> setAutoConnect(bool value) =>
      preferences.setBool('${_key}autoConnect', value);
  String get name => preferences.getString('${_key}name') ?? '';
  Future<bool> setName(String value) =>
      preferences.setString('${_key}name', value);
  bool get hideSystemNavigation =>
      preferences.getBool('${_key}hideSystemNavigation') ?? false;
  Future<bool> setHideSystemNavigation(bool hidden) =>
      preferences.setBool('${_key}hideSystemNavigation', hidden);

  String get appearance =>
      preferences.getString('${_key}appearance') ?? 'system';
  Future<bool> setAppearance(String value) =>
      preferences.setString('${_key}appearance', value);

  String? nodeSort(String network) =>
      preferences.getString('${_key}nodeSort.$network');
  Future<bool> setNodeSort(String network, NodeSort sort) =>
      preferences.setString('${_key}nodeSort.$network', sort.name);

  ChatCache load(String key) {
    final raw = preferences.getString('${_key}cache.$key');
    if (raw != null) {
      try {
        return ChatCache.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } on Object {
        return ChatCache();
      }
    }
    return ChatCache();
  }

  Future<bool> save(String key, ChatCache cache) =>
      preferences.setString('${_key}cache.$key', jsonEncode(cache.toJson()));
}
