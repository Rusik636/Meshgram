// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network.dart';
import 'radio_outbox.dart';
import 'nodes.dart';
import 'route_trace.dart';

class ChatFolder {
  const ChatFolder({
    required this.id,
    required this.name,
    required this.chats,
    this.pinned = const [],
  });

  final String id, name;
  final Set<String> chats;
  final List<String> pinned;

  ChatFolder withChanges({
    String? name,
    Set<String>? chats,
    List<String>? pinned,
  }) => ChatFolder(
    id: id,
    name: name ?? this.name,
    chats: chats ?? this.chats,
    pinned: pinned ?? this.pinned,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'chats': chats.toList(),
    'pinned': pinned,
  };

  static ChatFolder? fromJson(Object? value) {
    if (value is! Map || value['id'] is! String || value['name'] is! String) {
      return null;
    }
    final chats = (value['chats'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    return ChatFolder(
      id: value['id'] as String,
      name: value['name'] as String,
      chats: chats,
      pinned: (value['pinned'] as List? ?? const [])
          .whereType<String>()
          .where(chats.contains)
          .toSet()
          .toList(),
    );
  }
}

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
  final replyExcerpts = <String, MessageExcerpt>{};
  final unread = <String, int>{};
  final _unreadIds = <String, Set<String>>{};
  final markedUnread = <String>{};
  final drafts = <String, String>{};
  final muted = <String>{};
  final unmuted = <String>{};
  final hiddenChats = <String>{};
  bool? _archiveHidden;
  final keptChats = <String>{};
  final chatOrder = <String>[];
  final pinnedChats = <String>[];
  final folders = <String, ChatFolder>{};
  final pinnedMessages = <String, String>{};
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

  bool get archiveHidden => _archiveHidden ?? false;
  set archiveHidden(bool hidden) => _archiveHidden = hidden;

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
    if (replyExcerpts.isNotEmpty)
      'replyExcerpts': replyExcerpts.map(
        (chat, excerpt) => MapEntry(chat, excerpt.toJson()),
      ),
    'unread': unread,
    if (markedUnread.isNotEmpty) 'markedUnread': markedUnread.toList(),
    if (_unreadIds.isNotEmpty)
      'unreadIds': _unreadIds.map((chat, ids) => MapEntry(chat, ids.toList())),
    'drafts': drafts,
    'muted': muted.toList(),
    if (unmuted.isNotEmpty) 'unmuted': unmuted.toList(),
    'hiddenChats': hiddenChats.toList(),
    if (_archiveHidden != null || hiddenChats.isNotEmpty)
      'archiveHidden': archiveHidden,
    'keptChats': keptChats.toList(),
    'chatOrder': chatOrder,
    if (pinnedChats.isNotEmpty) 'pinnedChats': pinnedChats,
    if (folders.isNotEmpty)
      'folders': folders.values.map((folder) => folder.toJson()).toList(),
    if (pinnedMessages.isNotEmpty) 'pinnedMessages': pinnedMessages,
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
    for (final entry in (json['replyExcerpts'] as Map? ?? const {}).entries) {
      if (entry.key case final String chat
          when cache.replies.containsKey(chat)) {
        if (MessageExcerpt.decode(entry.value) case final excerpt?) {
          cache.replyExcerpts[chat] = excerpt;
        }
      }
    }
    cache.unread.addAll((json['unread'] as Map).cast<String, int>());
    for (final entry in (json['unreadIds'] as Map? ?? const {}).entries) {
      if (entry.key case final String chat
          when cache.unread.containsKey(chat)) {
        cache._unreadIds[chat] = (entry.value as List)
            .whereType<String>()
            .toSet();
      }
    }
    cache.markedUnread.addAll(
      (json['markedUnread'] as List? ?? const []).whereType<String>(),
    );
    cache.drafts.addAll((json['drafts'] as Map).cast<String, String>());
    cache.muted.addAll((json['muted'] as List).cast<String>());
    cache.unmuted.addAll((json['unmuted'] as List? ?? const []).cast<String>());
    cache.hiddenChats.addAll(
      (json['hiddenChats'] as List? ?? const []).cast<String>(),
    );
    cache._archiveHidden =
        json['archiveHidden'] as bool? ??
        (cache.hiddenChats.isNotEmpty ? true : null);
    cache.keptChats.addAll(
      (json['keptChats'] as List? ?? const []).cast<String>(),
    );
    cache.chatOrder.addAll(
      (json['chatOrder'] as List? ?? const []).cast<String>(),
    );
    cache.pinnedChats.addAll(
      (json['pinnedChats'] as List? ?? const []).whereType<String>().toSet(),
    );
    for (final entry in (json['folders'] as List? ?? const [])) {
      if (ChatFolder.fromJson(entry) case final folder?) {
        cache.folders[folder.id] = folder;
      }
    }
    for (final entry in (json['pinnedMessages'] as Map? ?? const {}).entries) {
      if (entry.key is String && entry.value is String) {
        cache.pinnedMessages[entry.key as String] = entry.value as String;
      }
    }
    cache.searchHistory.addAll(
      (json['searchHistory'] as List? ?? []).cast<String>(),
    );
    return cache;
  }

  ChatCache();

  List<MeshMessage> history(String chat) =>
      messages.where((item) => item.chat == chat).toList()
        ..sort(compareChatMessages);

  Set<String> unreadIds(String chat) {
    final count = unread[chat] ?? 0;
    if (count <= 0) return const {};
    if (_unreadIds[chat] case final saved?) return saved;
    // Before unread IDs were persisted, the unread count represented a tail
    // of incoming messages. Outgoing messages must not consume that count.
    return _unreadIds[chat] = history(chat).reversed
        .where((message) => !message.outgoing)
        .take(count)
        .map((message) => message.id)
        .toSet();
  }

  void addUnread(MeshMessage message) {
    _unreadIds[message.chat] = {...unreadIds(message.chat), message.id};
    unread.update(message.chat, (count) => count + 1, ifAbsent: () => 1);
  }

  void promoteChat(String id) {
    chatOrder
      ..remove(id)
      ..insert(0, id);
  }

  void markRead(String chat) {
    unread.remove(chat);
    _unreadIds.remove(chat);
    markedUnread.remove(chat);
  }

  bool markReadThrough(String chat, String messageId) {
    if (!unread.containsKey(chat)) return false;
    final messages = history(chat);
    final end = messages.indexWhere((message) => message.id == messageId);
    if (end < 0) return false;
    final ids = unreadIds(chat);
    final remaining = messages
        .skip(end + 1)
        .where((message) => ids.contains(message.id))
        .map((message) => message.id)
        .toSet();
    if (remaining.length == unread[chat] ||
        (remaining.isNotEmpty && remaining.length == ids.length)) {
      return false;
    }
    if (remaining.isEmpty) {
      markRead(chat);
    } else {
      unread[chat] = remaining.length;
      _unreadIds[chat] = remaining;
    }
    return true;
  }

  void trimHistory(int retained) {
    final drop = messages.length - retained;
    if (drop <= 0) return;
    final dropped = messages.take(drop);
    final affected = dropped.map((message) => message.chat).toSet();
    final droppedIds = dropped.map((message) => message.id).toSet();
    for (final chat in affected.where(unread.containsKey)) {
      final ids = unreadIds(chat);
      ids.removeAll(droppedIds);
      if (ids.isEmpty) {
        unread.remove(chat);
        _unreadIds.remove(chat);
      } else {
        unread[chat] = ids.length;
      }
    }
    messages.removeRange(0, drop);
  }

  void mergeHistory(ChatCache other) {
    final currentIds = messages.map((message) => message.id).toSet();
    final pending = <String, Set<String>>{
      for (final chat in {...unread.keys, ...other.unread.keys})
        chat: {
          ...unreadIds(chat),
          ...other.unreadIds(chat).where((id) => !currentIds.contains(id)),
        },
    };
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
      ..sort(compareChatMessages);
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
    for (final entry in pending.entries) {
      final ids = entry.value;
      if (ids.isEmpty) {
        markRead(entry.key);
      } else {
        _unreadIds[entry.key] = ids;
        unread[entry.key] = ids.length;
      }
    }
    for (final entry in other.drafts.entries) {
      drafts.putIfAbsent(entry.key, () => entry.value);
    }
    for (final entry in other.replies.entries) {
      if (replies.containsKey(entry.key)) continue;
      replies[entry.key] = entry.value;
      if (other.replyExcerpts[entry.key] case final excerpt?) {
        replyExcerpts[entry.key] = excerpt;
      }
    }
    markedUnread.addAll(other.markedUnread);
    muted.addAll(other.muted);
    unmuted.addAll(other.unmuted);
    _archiveHidden ??= other._archiveHidden;
    hiddenChats.addAll(other.hiddenChats);
    keptChats.addAll(other.keptChats);
    chatOrder.addAll(
      other.chatOrder.where((id) => !chatOrder.contains(id)).toList(),
    );
    pinnedChats.addAll(
      other.pinnedChats.where((id) => !pinnedChats.contains(id)).toList(),
    );
    for (final entry in other.folders.entries) {
      folders.putIfAbsent(entry.key, () => entry.value);
    }
    for (final entry in other.pinnedMessages.entries) {
      pinnedMessages.putIfAbsent(entry.key, () => entry.value);
    }
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

int compareChatMessages(MeshMessage first, MeshMessage second) {
  final byTime = first.time.compareTo(second.time);
  return byTime != 0 ? byTime : first.id.compareTo(second.id);
}

class SavedMessage {
  SavedMessage({
    required this.message,
    required this.profile,
    required this.radioName,
    required this.chatName,
    required this.author,
    required this.savedAt,
    this.isNote = false,
    Iterable<String> labels = const [],
  }) : labels = List.unmodifiable(labels);

  final MeshMessage message;
  final String profile, radioName, chatName, author;
  final DateTime savedAt;
  final bool isNote;
  final List<String> labels;

  (String, String, String) get key => (profile, message.chat, message.id);

  SavedMessage withLabels(Iterable<String> next) => SavedMessage(
    message: message,
    profile: profile,
    radioName: radioName,
    chatName: chatName,
    author: author,
    savedAt: savedAt,
    isNote: isNote,
    labels: next,
  );

  Map<String, Object> toJson() => {
    'message': message.toJson(),
    'profile': profile,
    'radioName': radioName,
    'chatName': chatName,
    'author': author,
    'savedAt': savedAt.millisecondsSinceEpoch,
    if (isNote) 'isNote': true,
    'labels': labels,
  };

  static SavedMessage? decode(String entry) {
    try {
      final json = jsonDecode(entry) as Map<String, dynamic>;
      return SavedMessage(
        message: MeshMessage.fromJson(json['message'] as Map<String, dynamic>),
        profile: json['profile'] as String,
        radioName: json['radioName'] as String,
        chatName: json['chatName'] as String,
        author: json['author'] as String,
        savedAt: DateTime.fromMillisecondsSinceEpoch(json['savedAt'] as int),
        isNote: json['isNote'] == true,
        labels: (json['labels'] as List? ?? []).whereType<String>(),
      );
    } on Object {
      return null;
    }
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

  List<String>? get recentReactionEmojis =>
      preferences.getStringList('${_key}recentReactionEmojis');
  Future<bool> setRecentReactionEmojis(List<String> emojis) =>
      preferences.setStringList('${_key}recentReactionEmojis', emojis);

  List<String>? get quickPhrases =>
      preferences.getStringList('${_key}quickPhrases');
  Future<bool> setQuickPhrases(List<String> phrases) =>
      preferences.setStringList('${_key}quickPhrases', phrases);

  List<OutboxMessage> loadOutbox() {
    final raw = preferences.getString('${_key}outbox');
    if (raw == null) return [];
    try {
      final values = jsonDecode(raw) as List;
      return [for (final value in values) ?OutboxMessage.decode(value)];
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  Future<bool> saveOutbox(List<OutboxMessage> messages) =>
      preferences.setString(
        '${_key}outbox',
        jsonEncode(messages.map((message) => message.toJson()).toList()),
      );

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

  List<SavedMessage> get savedMessages => [
    for (final entry in preferences.getStringList('${_key}savedMessages') ?? [])
      ?SavedMessage.decode(entry),
  ];

  String get savedChatDraft =>
      preferences.getString('${_key}savedChatDraft') ?? '';

  Future<bool> setSavedChatDraft(String value) =>
      preferences.setString('${_key}savedChatDraft', value);

  Future<bool> setSavedMessages(List<SavedMessage> items) =>
      preferences.setStringList('${_key}savedMessages', [
        for (final item in items) jsonEncode(item.toJson()),
      ]);
}
