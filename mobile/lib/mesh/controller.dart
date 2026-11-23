// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'contact_attachment.dart';
import 'network.dart';
import 'nodes.dart';
import 'route_trace.dart';
import 'store.dart';

class _StartupDisconnected implements Exception {
  const _StartupDisconnected();
  @override
  String toString() => "Radio disconnected during startup";
}

class _RadioConnection {
  _RadioConnection(this.radio);

  Radio radio;
  NetworkSession? session;
  StreamSubscription<NetworkEvent>? events;
  Future<void> closing = Future.value();
  Future<void>? connecting;
  LinkState state = LinkState.offline;
  int generation = 0;
  Timer? signalTimer, batteryTimer, restartWindow;
  Completer<void>? restart;
  bool explicitRestart = false;
  int? rssi;
  Duration? latency;
  RadioBattery? battery;

  bool get online => state == LinkState.online;
  bool get restarting =>
      explicitRestart || (restart != null && restartWindow == null);
}

class MeshController extends ChangeNotifier {
  MeshController({
    required this.store,
    required this.transport,
    this.lanTransport,
    required Iterable<NetworkAdapter> adapters,
    this.preview = false,
    this.onIncomingMessage,
    this.onIncomingReaction,
    this.isChatForeground,
  }) : adapters = {for (final adapter in adapters) adapter.id: adapter} {
    if (preview) {
      _seedPreview();
      _selected!
        ..rssi = -59
        ..battery = (percent: 73, powered: false, estimated: false);
    } else {
      _loadRadios();
    }
    _autoConnections.addAll(
      store.connectedProfiles.map((key) {
        final known = _savedRadio(key);
        return known == null ? key : radioKey(known);
      }),
    );
    if (!store.hasConnectedProfiles && store.autoConnect) {
      if (active case final radio?) _autoConnections.add(radioKey(radio));
    }
    _scheduleNodeRefresh();
  }

  final MeshStore store;
  final RadioTransport transport;
  final RadioLanTransport? lanTransport;
  final Map<String, NetworkAdapter> adapters;
  final bool preview;
  final void Function(Radio radio, Peer peer, MeshMessage message)?
  onIncomingMessage;
  final void Function(Radio radio, Peer peer, MeshReaction reaction)?
  onIncomingReaction;
  final bool Function()? isChatForeground;
  final _caches = <String, ChatCache>{};
  final _radioRoutes = <String, List<String>>{};
  Future<void> _radioWrites = Future.value();
  final _random = Random.secure();
  final _connections = <String, _RadioConnection>{};
  final _autoConnections = <String>{};
  _RadioConnection? _selected;
  List<Radio> radios = [];
  Radio? get active => _selected?.radio;
  NetworkSession? get _session => _selected?.session;
  List<DiscoveredRadio> discovered = [];
  int _scanGeneration = 0;
  LinkState get linkState => _selected?.state ?? LinkState.offline;
  String? error, openedChat;
  BluetoothProblem? bluetoothProblem;
  bool scanning = false, _closed = false;
  late String profileName = store.name;
  late String appearance = store.appearance;
  late bool hideSystemNavigation = store.hideSystemNavigation;

  void setHideSystemNavigation(bool hidden) {
    hideSystemNavigation = hidden;
    unawaited(store.setHideSystemNavigation(hidden));
    _changed();
  }

  Timer? _draftTimer;
  Timer? _nodeTimer;
  String? _presenceRadio;
  final _receipts = <String, ({Radio radio, Timer timer})>{};
  final _startingRouteTraces = <String>{};
  int? get signalRssi => _selected?.rssi;
  Duration? get linkLatency => _selected?.latency;
  RadioBattery? get battery => _selected?.battery;
  bool get radioHasSettings => _session is RadioSettingsSession;
  Iterable<Radio> get connectedRadios => _connections.values
      .where((item) => item.online)
      .map((item) => item.radio);
  bool get hasAutoConnections => _autoConnections.isNotEmpty;
  bool get hasOfflineAutoConnection => radios.any(
    (radio) =>
        stateFor(radio) == LinkState.offline &&
        _autoConnections.contains(radioKey(radio)) &&
        (!identical(_connectionFor(radio), _selected) || store.autoConnect),
  );
  LinkState stateFor(Radio radio) =>
      _connectionFor(radio)?.state ?? LinkState.offline;
  int? signalFor(Radio radio) => _connectionFor(radio)?.rssi;
  Duration? latencyFor(Radio radio) => _connectionFor(radio)?.latency;
  RadioBattery? batteryFor(Radio radio) => _connectionFor(radio)?.battery;
  bool canConfigureRadio(Radio radio) =>
      isConnectedTo(radio) &&
      _connectionFor(radio)?.session is RadioSettingsSession;
  int unreadFor(Radio radio) =>
      _cacheFor(radio).unread.values.fold(0, (sum, item) => sum + item);
  int get unreadOnOtherRadios {
    final selected = active;
    final selectedKey = selected == null ? null : radioKey(selected);
    return radios
        .where((radio) => radioKey(radio) != selectedKey)
        .fold(0, (total, radio) => total + unreadFor(radio));
  }

  Iterable<Peer> peersFor(Radio radio) => _cacheFor(radio).peers.values;
  bool isMutedFor(Radio radio, String chat) =>
      _cacheFor(radio).muted.contains(chat);

  ChatCache notificationCache(Radio radio) => _cacheFor(radio);

  bool? notificationException(Radio radio, String chat) {
    final data = _cacheFor(radio);
    if (data.muted.contains(chat)) return false;
    return data.unmuted.contains(chat) ? true : null;
  }

  void setNotificationException(Radio radio, String chat, bool? enabled) {
    final data = _cacheFor(radio);
    data.muted.remove(chat);
    data.unmuted.remove(chat);
    if (enabled == true) data.unmuted.add(chat);
    if (enabled == false) data.muted.add(chat);
    _save(radio);
    _changed();
  }

  void resetNotificationExceptions() {
    for (final radio in radios) {
      _cacheFor(radio)
        ..muted.clear()
        ..unmuted.clear();
      _save(radio);
    }
    _changed();
  }

  _RadioConnection? _connectionFor(Radio radio) =>
      _connections[_profileKey(radio)];
  _RadioConnection _connection(Radio radio) => _connections.putIfAbsent(
    _profileKey(radio),
    () => _RadioConnection(radio),
  );

  String label(String kind) => adapters[kind]?.label ?? kind;
  ChatCache _cacheAt(String key) =>
      _caches.putIfAbsent(key, () => store.load(key));
  ChatCache _cacheFor(Radio radio) => _cacheAt(_profileKey(radio));
  ChatCache? get cache => active == null ? null : _cacheFor(active!);
  bool get connected => linkState == LinkState.online;
  bool get reconnecting => _selected?.restarting ?? false;
  bool isReconnecting(Radio radio) =>
      _connectionFor(radio)?.restarting ?? false;

  String? radioPublicKey(Radio radio) => _cacheFor(radio).radioPublicKey;
  RadioDeviceInfo? radioDeviceInfo(Radio radio) => _cacheFor(radio).deviceInfo;

  List<String> _routes(Radio radio) =>
      _radioRoutes[radioKey(radio)] ?? [radio.device];

  bool _hasRouteKey(Radio radio, String? key) =>
      key == radioKey(radio) ||
      _routes(radio).any((device) => key == '${radio.network}/$device');

  Radio? _savedRadio(String? key) =>
      radios.where((item) => _hasRouteKey(item, key)).firstOrNull;
  String _profileKey(Radio radio) =>
      radioKey(_savedRadio(radioKey(radio)) ?? radio);

  Radio connectionRoute(Radio radio) {
    final profile = _savedRadio(radioKey(radio)) ?? radio;
    return (
      network: profile.network,
      device: _routes(profile).first,
      name: profile.name,
    );
  }

  // Keep the best known address for each transport in successful connection order.
  List<String> _rankRoutes(Iterable<String> routes) {
    final seenLan = <bool>{};
    return [
      for (final device in routes)
        if (seenLan.add(device.startsWith('tcp://'))) device,
    ];
  }

  bool? _sameIdentity(RadioIdentity known, RadioIdentity reported) {
    if (known.hardwareId != null && reported.hardwareId != null) {
      return known.hardwareId == reported.hardwareId;
    }
    if (known.publicKey != null && reported.publicKey != null) {
      return known.publicKey == reported.publicKey;
    }
    if (known.nodeNumber != null && reported.nodeNumber != null) {
      return known.nodeNumber == reported.nodeNumber;
    }
    return null;
  }

  Radio? _matchingRadio(Radio radio, RadioIdentity identity) {
    if (radio.network != 'meshtastic') return null;
    final matches = radios
        .where(
          (item) =>
              item.network == radio.network &&
              radioKey(item) != radioKey(radio) &&
              _sameIdentity(_cacheAt(radioKey(item)).radioIdentity, identity) ==
                  true,
        )
        .take(2)
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  void _loadRadios() {
    final previousActive = store.active;
    final merged = <String>{};
    for (final record in store.radioProfiles) {
      final radio = record.radio;
      if (!adapters.containsKey(radio.network)) continue;
      final key = radioKey(radio);
      _radioRoutes[key] = _rankRoutes(record.routes);
      final other = radio.network == 'meshtastic'
          ? _matchingRadio(radio, _cacheAt(key).radioIdentity)
          : null;
      if (other == null) {
        radios.add(radio);
        continue;
      }
      final otherKey = radioKey(other);
      final keepOther = _hasRouteKey(other, previousActive);
      final preferred = keepOther ? other : radio;
      final secondary = keepOther ? radio : other;
      final data = _cacheAt(radioKey(preferred));
      data.mergeHistory(_cacheAt(radioKey(secondary)));
      _caches[otherKey] = data;
      _radioRoutes[otherKey] = _rankRoutes([
        ..._routes(preferred),
        ..._routes(secondary),
      ]);
      _radioRoutes.remove(key);
      radios[radios.indexOf(other)] = (
        network: other.network,
        device: other.device,
        name: preferred.name,
      );
      merged.add(otherKey);
    }
    final restored = _savedRadio(previousActive);
    if ((restored ?? radios.firstOrNull) case final radio?) {
      _selected = _connection(radio);
    }
    if (merged.isNotEmpty) unawaited(_persistRadios(merged));
  }

  Future<void> _persistRadios([Iterable<String> merged = const []]) {
    final profiles = List<Radio>.of(radios);
    final routes = Map<String, List<String>>.of(_radioRoutes);
    return _radioWrites = _radioWrites
        .then((_) async {
          for (final key in merged) {
            await store.save(key, _cacheAt(key));
          }
          await store.setRadios(profiles, routes: routes);
        })
        .catchError((Object error) {
          debugPrint('MeshGrame radio profiles: $error');
        });
  }

  Map<String, LanRadioProtocol> get lanProtocols => {
    if (lanTransport != null)
      for (final entry in adapters.entries)
        if (entry.value is NetworkLanAdapter)
          entry.key: (entry.value as NetworkLanAdapter).lan,
  };

  Iterable<Peer> get peers => cache?.peers.values ?? [];
  NodeObservation? nodeObservation(String id) => cache?.observations[id];
  bool canOpenChat(Peer peer) {
    if (peer.channel) return true;
    final observation = nodeObservation(peer.id);
    final legacyType = cache?.identities[peer.id]?.type;
    return observation?.canMessage ?? (legacyType == null || legacyType == 1);
  }

  bool canSendTo(Peer peer) => peer.writable && canOpenChat(peer);

  bool isNodeOnline(String id) =>
      nodeIsOnline(nodeObservation(id)?.lastSeen, DateTime.now());

  List<NodeSort> get nodeSorts {
    final adapter = adapters[active?.network];
    return [
      NodeSort.activity,
      NodeSort.name,
      if (adapter is NetworkNodeSorting)
        ...(adapter as NetworkNodeSorting).additionalNodeSorts,
    ];
  }

  NodeSort get nodeSort {
    final network = active?.network;
    final saved = network == null ? null : store.nodeSort(network);
    return nodeSorts.where((sort) => sort.name == saved).firstOrNull ??
        NodeSort.activity;
  }

  Future<void> setNodeSort(NodeSort value) async {
    final network = active?.network;
    if (network == null || !nodeSorts.contains(value)) return;
    await store.setNodeSort(network, value);
    _changed();
  }

  double? nodeDistanceMeters(String id) {
    final from = cache?.localPosition;
    final to = nodeObservation(id)?.position;
    return from == null || to == null ? null : nodeDistance(from, to);
  }

  List<Peer> get nodes {
    final current = cache;
    if (current == null) return [];
    final sort = nodeSort;
    final list = current.peers.values.where((peer) => !peer.channel).toList();
    final messageTimes = <String, int>{};
    if (sort == NodeSort.messages) {
      for (final message in current.messages) {
        final stamp = message.time.millisecondsSinceEpoch;
        if (stamp > (messageTimes[message.chat] ?? 0)) {
          messageTimes[message.chat] = stamp;
        }
      }
    }
    final distance = <String, double?>{
      if (sort == NodeSort.distance)
        for (final node in list) node.id: nodeDistanceMeters(node.id),
    };
    int latest(Peer peer) =>
        current.observations[peer.id]?.lastSeen?.millisecondsSinceEpoch ?? 0;
    return list..sort((a, b) {
      final first = current.observations[a.id];
      final second = current.observations[b.id];
      final order = switch (sort) {
        NodeSort.activity => latest(b).compareTo(latest(a)),
        NodeSort.name => 0,
        NodeSort.messages => (messageTimes[b.id] ?? 0).compareTo(
          messageTimes[a.id] ?? 0,
        ),
        NodeSort.distance => (distance[a.id] ?? double.infinity).compareTo(
          distance[b.id] ?? double.infinity,
        ),
        NodeSort.hops => (first?.hops ?? 999).compareTo(second?.hops ?? 999),
        NodeSort.channel => (first?.channel ?? 999).compareTo(
          second?.channel ?? 999,
        ),
        NodeSort.mqtt => (first?.viaMqtt == true ? 1 : 0).compareTo(
          second?.viaMqtt == true ? 1 : 0,
        ),
        NodeSort.favorite => (second?.favorite == true ? 1 : 0).compareTo(
          first?.favorite == true ? 1 : 0,
        ),
      };
      if (order != 0) return order;
      if (sort != NodeSort.name) {
        final activity = latest(b).compareTo(latest(a));
        if (activity != 0) return activity;
      }
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName == 0 ? a.id.compareTo(b.id) : byName;
    });
  }

  void refreshNodePresence() {
    if (_closed) return;
    _scheduleNodeRefresh();
    _changed();
  }

  void _scheduleNodeRefresh() {
    _nodeTimer?.cancel();
    final radio = active;
    _presenceRadio = radio == null ? null : radioKey(radio);
    final observations = cache?.observations;
    if (observations == null || observations.isEmpty) return;
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day + 1);
    for (final node in observations.values) {
      final lastSeen = node.lastSeen;
      if (lastSeen == null || !nodeIsOnline(lastSeen, now)) continue;
      final expiry = lastSeen.add(nodeOnlineWindow);
      if (expiry.isBefore(next)) next = expiry;
    }
    _nodeTimer = Timer(next.difference(now), refreshNodePresence);
  }

  List<MeshMessage> messages(String peer) =>
      (cache?.messages.where((message) => message.chat == peer).toList() ?? [])
        ..sort((a, b) => a.time.compareTo(b.time));

  List<Peer> get conversations => _conversations(hidden: false);
  List<Peer> get hiddenConversations => _conversations(hidden: true);

  List<Peer> _conversations({required bool hidden}) {
    final current = cache;
    if (current == null) return [];
    final latest = <String, int>{};
    for (final message in current.messages) {
      final stamp = message.time.millisecondsSinceEpoch;
      if (stamp > (latest[message.chat] ?? 0)) latest[message.chat] = stamp;
    }
    final ranks = {
      for (final (index, id) in current.chatOrder.indexed) id: index,
    };
    return current.peers.values
        .where(
          (peer) =>
              current.hiddenChats.contains(peer.id) == hidden &&
              (hidden ||
                  peer.channel ||
                  current.keptChats.contains(peer.id) ||
                  latest.containsKey(peer.id) ||
                  (current.drafts[peer.id]?.isNotEmpty ?? false)),
        )
        .toList()
      ..sort((a, b) {
        final ranked = (ranks[a.id] ?? ranks.length).compareTo(
          ranks[b.id] ?? ranks.length,
        );
        if (ranked != 0) return ranked;
        final order = (latest[b.id] ?? 0).compareTo(latest[a.id] ?? 0);
        return order != 0 ? order : a.name.compareTo(b.name);
      });
  }

  int get unreadTotal {
    final current = cache;
    if (current == null) return 0;
    return current.unread.entries
        .where((entry) => !current.hiddenChats.contains(entry.key))
        .fold<int>(0, (total, entry) => total + entry.value);
  }

  void markChatsRead(Iterable<String> ids) {
    final radio = active;
    if (radio == null) return;
    final current = _cacheFor(radio);
    for (final id in ids) {
      current.unread.remove(id);
    }
    _save(radio);
    _changed();
  }

  void hideChats(Iterable<String> ids, {required bool hidden}) {
    final radio = active;
    if (radio == null) return;
    final current = _cacheFor(radio);
    if (hidden) {
      current.hiddenChats.addAll(ids.where(current.peers.containsKey));
    } else {
      current.hiddenChats.removeAll(ids);
    }
    _save(radio);
    _changed();
  }

  void reorderChats(List<String> reordered, {required bool hidden}) {
    final radio = active;
    if (radio == null) return;
    final changes = reordered.toSet();
    if (changes.length != reordered.length) return;
    final screen = _conversations(hidden: hidden);
    if (!changes.every((id) => screen.any((peer) => peer.id == id))) return;
    var next = 0;
    final all = [...screen, ..._conversations(hidden: !hidden)];
    _cacheFor(radio).chatOrder
      ..clear()
      ..addAll([
        for (final peer in all)
          changes.contains(peer.id) ? reordered[next++] : peer.id,
      ]);
    _save(radio);
    _changed();
  }

  void clearChat(String id) {
    final radio = active;
    if (radio == null) return;
    final current = _cacheFor(radio);
    if (current.peers.containsKey(id)) current.keptChats.add(id);
    _removeHistory(current, id);
    _save(radio);
    _changed();
  }

  void _removeHistory(ChatCache current, String id) {
    current.messages.removeWhere((message) {
      if (message.chat != id) return false;
      _receipts.remove(message.id)?.timer.cancel();
      return true;
    });
    current.reactions.removeWhere((item) => item.chat == id);
    current.replies.remove(id);
    current.unread.remove(id);
  }

  bool canRemovePeer(Peer peer) {
    final session = _session;
    if (!connected) return false;
    if (preview) return !peer.channel || peer.id != 'ch:0';
    return session is RadioConversationSession &&
        (session as RadioConversationSession).canRemovePeer(peer);
  }

  Future<void> removePeer(Peer peer) async {
    final radio = active;
    final session = _session;
    if (radio == null || !canRemovePeer(peer)) {
      throw StateError('peer-remove-unavailable');
    }
    if (!preview) await (session as RadioConversationSession).removePeer(peer);
    final current = _cacheFor(radio);
    final identity = current.identities.remove(peer.id);
    _removeHistory(current, peer.id);
    current.peers.remove(peer.id);
    current.observations.remove(peer.id);
    current.drafts.remove(peer.id);
    current.muted.remove(peer.id);
    current.unmuted.remove(peer.id);
    current.hiddenChats.remove(peer.id);
    current.keptChats.remove(peer.id);
    current.chatOrder.remove(peer.id);
    current.searchHistory.remove(peer.id);
    if (identity != null && radio.network == 'meshcore') {
      try {
        await store.setAdminPassword(identity.publicKey, null);
      } catch (_) {}
    }
    _save(radio);
    _changed();
  }

  bool canShareChannel(Peer peer) {
    final session = _session;
    return connected &&
        session is RadioConversationSession &&
        (session as RadioConversationSession).canShareChannel(peer);
  }

  Future<String> shareChannel(Peer peer) async {
    final session = _session;
    if (!canShareChannel(peer)) throw StateError('channel-share-unavailable');
    final invite = await (session as RadioConversationSession).shareChannel(
      peer,
    );
    if (session != _session || !connected) {
      throw StateError('connection-changed');
    }
    return invite;
  }

  bool canSetFixedPosition(Radio radio, RadioSettingsSession? remote) =>
      isConnectedTo(radio) &&
      (remote ?? _connectionFor(radio)?.session) is RadioPositionSession;

  Future<void> setFixedPosition(
    Radio radio,
    NodePosition position, {
    RadioSettingsSession? remote,
  }) async {
    final session = remote ?? _connectionFor(radio)?.session;
    if (!isConnectedTo(radio) || session is! RadioPositionSession) {
      throw StateError('position-unavailable');
    }
    await (session).setFixedPosition(position);
    if (remote == null) {
      final current = _cacheFor(radio);
      current.localPosition = position;
      _save(radio);
      _changed();
    }
  }

  void _changed() {
    if (_closed) return;
    final radio = active;
    if (_presenceRadio != (radio == null ? null : radioKey(radio))) {
      _scheduleNodeRefresh();
    }
    notifyListeners();
  }

  Future<void> restoreConnection({bool Function(Radio)? eligible}) async {
    if (_closed || preview) return;
    final selected = active;
    final candidates = [
      if (selected != null &&
          store.autoConnect &&
          _hasRouteKey(selected, store.active))
        selected,
      for (final radio in radios)
        if (radioKey(radio) != (selected == null ? null : radioKey(selected)) &&
            _autoConnections.any((key) => _hasRouteKey(radio, key)))
          radio,
    ];
    await Future.wait([
      for (final radio in candidates)
        if (stateFor(radio) == LinkState.offline &&
            (eligible?.call(radio) ?? true))
          _connect(_connection(radio)),
    ]);
  }

  bool get canEnableBluetooth => transport is BluetoothControl;

  Future<bool> enableBluetooth() async {
    final control = transport;
    if (control is! BluetoothControl) return false;
    try {
      await (control as BluetoothControl).enableBluetooth();
      bluetoothProblem = null;
      if (error == 'bluetooth') error = null;
      _changed();
      return true;
    } on BluetoothProblem catch (problem) {
      bluetoothProblem = problem;
      _changed();
      return false;
    }
  }

  Future<void> scan() async {
    if (scanning || linkState == LinkState.connecting) return;
    if (preview) {
      discovered = [
        for (final (index, radio) in radios.indexed)
          (radio: radio, rssi: -59 - index * 10),
        (
          radio: (
            network: 'meshcore',
            device: 'demo-pocket',
            name: 'Pocket Radio',
          ),
          rssi: -83,
        ),
      ];
      _changed();
      return;
    }
    final generation = ++_scanGeneration;
    error = null;
    bluetoothProblem = null;
    scanning = true;
    discovered = [];
    _changed();
    var nearby = <DiscoveredRadio>[], local = <DiscoveredRadio>[];
    void publish() {
      if (_closed || generation != _scanGeneration) return;
      discovered = [
        ...(nearby.toList()..sort((a, b) => b.rssi.compareTo(a.rssi))),
        ...(local.toList()
          ..sort((a, b) => a.radio.name.compareTo(b.radio.name))),
      ];
      _changed();
    }

    Future<void> run(String source, Future<void> Function() scan) async {
      try {
        await scan();
      } catch (exception) {
        if (generation != _scanGeneration) return;
        debugPrint('MeshGrame $source discovery: $exception');
        if (exception is BluetoothProblem) bluetoothProblem = exception;
        error ??= source;
      }
    }

    try {
      final protocols = lanProtocols;
      final services = {
        for (final adapter in adapters.values)
          if (adapter.service.isNotEmpty) adapter.service: adapter.id,
      };
      await Future.wait([
        if (services.isNotEmpty)
          run(
            'bluetooth',
            () => transport.scan(services, (found) {
              nearby = found;
              publish();
            }),
          ),
        if (protocols.isNotEmpty)
          run(
            'localNetwork',
            () => lanTransport!.scan(protocols, (found) {
              local = found;
              publish();
            }),
          ),
      ]);
    } finally {
      if (generation == _scanGeneration) {
        scanning = false;
        _changed();
      }
    }
  }

  Future<void> stopDiscovery() async {
    if (!scanning) return;
    ++_scanGeneration;
    scanning = false;
    _changed();
    await _stopScanners();
  }

  Future<void> _stopScanners() async {
    await Future.wait([
      transport.stopScan().catchError((Object error) {
        debugPrint('MeshGrame Bluetooth discovery stop: $error');
      }),
      if (lanTransport case final local?)
        local.stopScan().catchError((Object error) {
          debugPrint('MeshGrame local discovery stop: $error');
        }),
    ]);
  }

  List<ChannelAction> get channelActions {
    final session = _session;
    if (!connected || session is! RadioChannelSession) return [];
    return (session as RadioChannelSession).channelActions;
  }

  bool isConnectedTo(Radio radio) => _connectionFor(radio)?.online ?? false;

  Future<List<RadioSetupStep>> setupSteps(Radio radio) async {
    if (!isConnectedTo(radio)) throw StateError('Radio is not connected');
    final session = _connectionFor(radio)?.session;
    return session is RadioOnboardingSession
        ? (session as RadioOnboardingSession).setupSteps()
        : [];
  }

  Future<ChannelProvision> addChannel(ChannelRequest request) async {
    final radio = active;
    final session = _session;
    if (radio == null ||
        session is! RadioChannelSession ||
        !channelActions.contains(request.action)) {
      throw StateError('Channel creation is unavailable');
    }
    final result = await _verifyRadioWrite(
      radio,
      () => (session as RadioChannelSession).addChannel(request),
    );
    _cacheFor(radio).peers[result.peer.id] = result.peer;
    _save(radio);
    _changed();
    return result;
  }

  Future<void> connect(Radio radio) async {
    if (_closed || !adapters.containsKey(radio.network)) return;
    final profile = _savedRadio(radioKey(radio)) ?? radio;
    final connection = _connection(profile);
    if (!identical(connection, _selected)) {
      _draftTimer?.cancel();
      if (active case final previous?) _save(previous);
      openedChat = null;
      _selected = connection;
      error = null;
      bluetoothProblem = null;
      if (_savedRadio(radioKey(profile)) != null && !preview) {
        unawaited(store.setActive(radioKey(profile)));
        unawaited(
          store.setAutoConnect(_autoConnections.contains(radioKey(profile))),
        );
      }
      _changed();
    }
    await _connect(connection);
  }

  Future<void> _connect(_RadioConnection connection, {bool retry = false}) {
    final pending = connection.connecting;
    if (connection.state == LinkState.connecting && pending != null) {
      return pending;
    }
    final attempt = _connectOnce(connection, retry: retry);
    connection.connecting = attempt;
    return attempt.whenComplete(() {
      if (identical(connection.connecting, attempt)) {
        connection.connecting = null;
      }
    });
  }

  Future<void> _connectOnce(
    _RadioConnection connection, {
    bool retry = false,
  }) async {
    if (_closed ||
        connection.online ||
        (!retry && connection.state == LinkState.connecting)) {
      return;
    }
    final profile = connection.radio;
    final adapter = adapters[profile.network]!;
    if (!retry) _finishRestart(connection);
    final operation = ++connection.generation;
    if (identical(connection, _selected)) {
      error = null;
      bluetoothProblem = null;
    }
    connection.state = LinkState.connecting;
    _changed();
    try {
      await stopDiscovery();
      if (!_isCurrent(connection, operation)) return;
      await _release(connection);
      if (!_isCurrent(connection, operation)) return;
      if (preview) {
        connection.state = LinkState.online;
        if (_savedRadio(radioKey(profile)) == null) {
          radios = [...radios, profile];
        }
        connection.rssi = profile.network == 'meshcore' ? -72 : -59;
        connection.battery = profile.network == 'meshcore'
            ? (percent: 73, powered: false, estimated: true)
            : (percent: null, powered: true, estimated: false);
        return;
      }
      Object? failure;
      BluetoothProblem? bluetoothFailure;
      final routes = [..._routes(profile)];
      final firstPass = routes.length;
      for (var index = 0; index < routes.length; index++) {
        final device = routes[index];
        if (index == firstPass) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
          if (!_isCurrent(connection, operation)) return;
        }
        final route = (
          network: profile.network,
          device: device,
          name: profile.name,
        );
        try {
          await _connectRoute(connection, profile, route, adapter, operation);
          return;
        } catch (exception) {
          if (!_isCurrent(connection, operation)) return;
          debugPrint(
            'MeshGrame ${route.network} ${lanEndpoint(route) == null ? 'Bluetooth' : 'Wi-Fi'} connection: $exception',
          );
          if (index < firstPass && exception is _StartupDisconnected) {
            routes.add(device);
          }
          failure = exception;
          if (exception is BluetoothProblem) bluetoothFailure = exception;
          await _release(connection);
          if (!_isCurrent(connection, operation)) return;
        }
      }
      final failureCode = switch (bluetoothFailure ?? failure) {
        BluetoothProblem() => 'bluetooth',
        RadioNotNearby() => 'notNearby',
        _ => 'connection',
      };
      if (identical(connection, _selected)) {
        bluetoothProblem = bluetoothFailure;
        error = failureCode;
      }
      if (!retry) connection.state = LinkState.offline;
    } finally {
      _changed();
    }
  }

  bool _isCurrent(_RadioConnection connection, int operation) =>
      !_closed && operation == connection.generation;

  Future<void> _connectRoute(
    _RadioConnection connection,
    Radio profile,
    Radio route,
    NetworkAdapter adapter,
    int operation,
  ) async {
    final endpoint = lanEndpoint(route);
    final protocol = lanProtocols[route.network];
    if (endpoint != null && protocol == null) {
      throw StateError('Local network connection unavailable');
    }
    final link = endpoint == null
        ? await transport.connect(route, adapter.service)
        : await lanTransport!.connect(endpoint, protocol!);
    if (!_isCurrent(connection, operation)) {
      await link.close();
      return;
    }
    final NetworkSession session;
    try {
      session = adapter.createSession(link);
    } catch (_) {
      await link.close();
      rethrow;
    }
    connection.session = session;
    final inbox = <NetworkEvent>[];
    final startupEnded = Completer<void>();
    Radio? established;
    connection.events = session.events.listen((event) {
      if (!_isCurrent(connection, operation)) return;
      if (established != null) {
        _apply(connection.radio, event, connection: connection);
      } else if (event is RadioEnded) {
        if (!startupEnded.isCompleted) startupEnded.complete();
      } else {
        inbox.add(event);
      }
    });
    await Future.any([
      session.start(),
      startupEnded.future.then<void>((_) {
        throw const _StartupDisconnected();
      }),
    ]);
    if (!_isCurrent(connection, operation)) return;
    if (startupEnded.isCompleted) {
      throw const _StartupDisconnected();
    }

    final identity = session is NetworkRadioIdentity
        ? (session as NetworkRadioIdentity).radioIdentity
        : inbox.whereType<DirectoryUpdate>().lastOrNull?.radioIdentity;
    final saved = _savedRadio(radioKey(profile));
    if (profile.network == 'meshtastic' &&
        identity != null &&
        saved != null &&
        _sameIdentity(_cacheFor(saved).radioIdentity, identity) == false) {
      throw StateError('Endpoint belongs to a different radio');
    }
    final selected = _rememberRoute(profile, route, identity);
    final key = radioKey(selected);
    final priorKey = radioKey(profile);
    final prior = _connections[key];
    if (priorKey != key) {
      _connections.remove(priorKey);
      _autoConnections.remove(priorKey);
    }
    _connections[key] = connection;
    connection.radio = selected;
    if (prior != null && !identical(prior, connection)) {
      ++prior.generation;
      prior.state = LinkState.offline;
      _finishRestart(prior);
      if (identical(prior, _selected)) _selected = connection;
      await _release(prior);
      if (!_isCurrent(connection, operation)) return;
    }
    established = selected;
    if (identity != null) {
      final data = _cacheAt(key);
      data.radioHardwareId = identity.hardwareId ?? data.radioHardwareId;
      data.radioNodeNumber = identity.nodeNumber ?? data.radioNodeNumber;
      data.radioPublicKey = identity.publicKey ?? data.radioPublicKey;
    }
    for (final event in inbox) {
      _apply(selected, event, connection: connection);
    }
    inbox.clear();
    connection.state = LinkState.online;
    _scheduleNodeRefresh();
    _save(selected);
    _monitorSignal(connection, link, operation);
    if (session is RadioBatteryReader) {
      _monitorBattery(connection, session as RadioBatteryReader, operation);
    }
    _autoConnections.add(key);
    await Future.wait([
      store.setConnectedProfiles(_autoConnections),
      if (identical(connection, _selected)) ...[
        store.setActive(key),
        store.setAutoConnect(true),
      ],
      _persistRadios([key]),
    ]);
  }

  Radio _rememberRoute(Radio profile, Radio route, RadioIdentity? identity) {
    final saved = _savedRadio(radioKey(profile));
    final match = identity == null ? null : _matchingRadio(profile, identity);
    final selected = match ?? saved ?? profile;
    final key = radioKey(selected);
    if (saved != null && match != null) {
      _cacheAt(key).mergeHistory(_cacheAt(radioKey(saved)));
    } else if (saved == null &&
        match == null &&
        identity != null &&
        profile.network == 'meshtastic' &&
        _sameIdentity(_cacheAt(key).radioIdentity, identity) == false) {
      _caches[key] = ChatCache();
    }
    _radioRoutes[key] = _rankRoutes([
      route.device,
      ..._routes(selected),
      if (saved != null && match != null) ..._routes(saved),
    ]);
    if (saved != null && match != null) _radioRoutes.remove(radioKey(saved));
    radios = [
      for (final item in radios)
        if (saved == null || match == null || radioKey(item) != radioKey(saved))
          item,
      if (saved == null && match == null) selected,
    ];
    return selected;
  }

  RemoteAdminSession? adminFor(Peer peer) {
    final session = _session;
    if (!connected || session is! RemoteAdminSession) return null;
    final admin = session as RemoteAdminSession;
    return admin.canAdminister(peer) ? admin : null;
  }

  Set<NodeAction> nodeActions(Peer peer) {
    final session = _session;
    if (!connected || peer.channel || session is! NetworkNodeActions) {
      return const {};
    }
    return (session as NetworkNodeActions).nodeActions(peer);
  }

  bool canTraceRoute(Peer peer) =>
      _session is NetworkRouteTracing &&
      nodeActions(peer).contains(NodeAction.trace);

  List<RouteTrace> routeTraceHistory(String peer, {Radio? radio}) {
    final current = radio == null ? cache : _cacheFor(radio);
    return (current?.routeTraces.values
              .where((trace) => trace.peer == peer)
              .toList() ??
          <RouteTrace>[])
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
  }

  RouteTrace? routeTrace(Radio radio, int request) =>
      _cacheFor(radio).routeTraces[request];

  bool get startingRouteTrace {
    final radio = active;
    return radio != null && _startingRouteTraces.contains(_profileKey(radio));
  }

  DateTime? get routeTraceBlockedUntil {
    final cooldown = cache?.routeTraceCooldownUntil;
    final session = _session;
    final pending = session is NetworkRouteTracing
        ? (session as NetworkRouteTracing).routeTracePendingUntil
        : null;
    return pending != null && (cooldown == null || pending.isAfter(cooldown))
        ? pending
        : cooldown;
  }

  Future<void> startRouteTrace(Peer peer) async {
    final radio = active;
    final session = _session;
    final now = DateTime.now();
    if (radio == null ||
        session is! NetworkRouteTracing ||
        !canTraceRoute(peer) ||
        routeTraceBlockedUntil?.isAfter(now) == true ||
        !_startingRouteTraces.add(_profileKey(radio))) {
      return;
    }
    final tracing = session as NetworkRouteTracing;
    final profile = _profileKey(radio);
    final current = _cacheFor(radio);
    int request;
    do {
      request = 1 + _random.nextInt(0x7ffffffe);
    } while (current.routeTraces.containsKey(request));
    current.routeTraces[request] = RouteTrace(
      request: request,
      peer: peer.id,
      sentAt: now,
    );
    final interval = tracing.routeTraceInterval;
    if (interval > Duration.zero) {
      current.routeTraceCooldownUntil = now.add(interval);
    }
    _save(radio);
    _changed();
    try {
      await tracing.startRouteTrace(peer, request);
      if (interval > Duration.zero) {
        current.routeTraceCooldownUntil = DateTime.now().add(interval);
      }
    } catch (error) {
      debugPrint('Meshgram route trace: $error');
      final trace = current.routeTraces[request];
      if (trace != null && trace.pending) {
        current.routeTraces[request] = trace.rejected(
          RouteTraceFailure.rejected,
        );
      }
    } finally {
      _startingRouteTraces.remove(profile);
      _save(radio);
      _changed();
    }
  }

  Future<List<RadioField>> runNodeAction(
    Peer peer,
    NodeAction action, {
    bool enabled = true,
    String? password,
  }) async {
    final session = _session;
    if (session is! NetworkNodeActions || !nodeActions(peer).contains(action)) {
      throw StateError('Node action unavailable');
    }
    final result = await (session as NetworkNodeActions).runNodeAction(
      peer,
      action,
      enabled: enabled,
      password: password,
    );
    if (session != _session || !connected) {
      throw StateError('Radio disconnected');
    }
    return result;
  }

  Uri? contactCode(Peer peer) {
    final adapter = adapters[active?.network];
    final identity = cache?.identities[peer.id];
    if (adapter is! NetworkContactCodes || identity == null || peer.channel) {
      return null;
    }
    return (adapter as NetworkContactCodes).contactCode(peer, identity);
  }

  ContactAttachment? contactAttachment(String raw) {
    if (raw.length > 8192) return null;
    final link = raw.trim();
    if (RegExp(r'\s').hasMatch(link)) return null;
    final uri = Uri.tryParse(link);
    if (uri == null || !uri.hasScheme) return null;
    try {
      final compact = readCompactContact(uri);
      if (compact != null) return compact;
      for (final adapter in adapters.values.whereType<NetworkContactCodes>()) {
        final contact = adapter.readContactAttachment(uri);
        if (contact != null) return contact;
      }
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    return null;
  }

  Peer? findContactCode(String raw) {
    final target = contactAttachment(raw);
    final current = cache;
    if (target == null ||
        target.network != active?.network ||
        current == null ||
        current.identities[target.id]?.publicKey != target.publicKey) {
      return null;
    }
    return current.peers[target.id];
  }

  String? shareContactAttachment(Peer peer, int maxBytes) {
    final link = contactCode(peer)?.toString();
    if (link == null) return null;
    if (utf8.encode(link).length <= maxBytes) return link;
    final contact = contactAttachment(link);
    return contact == null ? null : compactContactLink(contact, maxBytes);
  }

  Future<Peer?> importContactAttachment(String raw) async {
    final contact = contactAttachment(raw);
    final radio = active;
    final current = cache;
    final session = _session;
    if (contact == null ||
        radio == null ||
        current == null ||
        contact.network != radio.network ||
        contact.publicKey == current.radioPublicKey ||
        contact.id == 'node:${current.radioNodeNumber}') {
      return null;
    }
    final existing = current.identities[contact.id];
    if (existing != null && existing.publicKey != contact.publicKey) {
      throw StateError('contact-key-conflict');
    }
    if (!connected) return findContactCode(raw);
    final Peer peer;
    if (preview) {
      peer =
          current.peers[contact.id] ??
          (
            id: contact.id,
            name: contact.name,
            writable: contact.type == null || contact.type == 1,
            channel: false,
          );
    } else {
      if (session is! RadioContactSession) return null;
      peer = await (session as RadioContactSession).importContact(contact);
      final selected = active;
      if (_closed ||
          selected == null ||
          radioKey(radio) != radioKey(selected) ||
          session != _session ||
          !connected) {
        return null;
      }
    }
    current.peers[peer.id] = peer;
    current.identities.putIfAbsent(
      peer.id,
      () => (
        publicKey: contact.publicKey,
        type: contact.type,
        shortName: contact.shortName,
      ),
    );
    _save(radio);
    _changed();
    return peer;
  }

  RadioSettingsCatalog? radioSettingsCatalog(Radio radio) {
    final session = _connectionFor(radio)?.session;
    if (!isConnectedTo(radio) || session is! RadioSettingsCatalog) {
      return null;
    }
    return session as RadioSettingsCatalog;
  }

  Future<List<RadioField>> readRadioSettings(Radio radio) async =>
      _settingsFor(radio).readSettings();

  Future<void> writeRadioSettings(Radio radio, Map<String, String> values) =>
      _verifyRadioWrite(radio, () => _settingsFor(radio).writeSettings(values));

  Future<void> writeRadioSection(
    Radio radio,
    RadioFieldSection section,
    Map<String, String> values,
  ) => _verifyRadioWrite(radio, () {
    final catalog = radioSettingsCatalog(radio);
    if (catalog == null) throw StateError('Radio settings unavailable');
    return catalog.writeSection(section, values);
  });

  Future<T> _verifyRadioWrite<T>(
    Radio radio,
    Future<T> Function() write,
  ) async {
    final connection = _connectionFor(radio);
    final previous = connection?.session;
    try {
      final result = await write();
      if (connection?.explicitRestart == true ||
          connection?.restartWindow == null) {
        await connection?.restart?.future;
      }
      if (!isConnectedTo(radio)) throw StateError('Radio connection changed');
      return result;
    } on RadioWriteInterrupted<T> catch (interrupted) {
      await connection?.restart?.future;
      final session = _connectionFor(radio)?.session;
      if (!isConnectedTo(radio) || session == null || session == previous) {
        rethrow;
      }
      return interrupted.verify(session);
    }
  }

  RadioRestartSession? radioRestartSession(Radio radio) {
    final session = _connectionFor(radio)?.session;
    return isConnectedTo(radio) && session is RadioRestartSession
        ? session as RadioRestartSession
        : null;
  }

  Future<List<RadioField>> readRadioTelemetry(Radio radio) async {
    final session = _connectionFor(radio)?.session;
    if (!isConnectedTo(radio)) {
      throw StateError('Radio is not connected');
    }
    return session is RadioTelemetrySession
        ? (session as RadioTelemetrySession).readTelemetry()
        : [];
  }

  RadioSettingsSession _settingsFor(Radio radio) {
    final session = _connectionFor(radio)?.session;
    if (!isConnectedTo(radio) || session is! RadioSettingsSession) {
      throw StateError('Radio is not connected');
    }
    return session as RadioSettingsSession;
  }

  void _monitorSignal(
    _RadioConnection connection,
    RadioLink link,
    int generation,
  ) {
    final signalLink = link is RadioSignalLink ? link as RadioSignalLink : null;
    final latencyLink = link is RadioLatencyLink
        ? link as RadioLatencyLink
        : null;
    if (signalLink == null && latencyLink == null) return;
    var pending = false;
    Future<void> refresh() async {
      if (pending) return;
      pending = true;
      int? rssi;
      Duration? latency;
      try {
        rssi = await signalLink?.readSignalRssi();
        if (rssi == null) latency = await latencyLink?.readLinkLatency();
      } catch (_) {
        // A transient read failure can occur during packet traffic.
      } finally {
        pending = false;
      }
      if (!_closed &&
          generation == connection.generation &&
          connection.online &&
          (connection.rssi != rssi || connection.latency != latency)) {
        connection.rssi = rssi;
        connection.latency = latency;
        _changed();
      }
    }

    connection.signalTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  void _monitorBattery(
    _RadioConnection connection,
    RadioBatteryReader reader,
    int generation,
  ) {
    var pending = false;
    Future<void> refresh() async {
      if (pending) return;
      pending = true;
      try {
        final sample = await reader.readBattery();
        if (!_closed &&
            generation == connection.generation &&
            connection.online) {
          _setBattery(connection, sample);
        }
      } catch (_) {
        // Retain the latest reading when a poll times out.
      } finally {
        pending = false;
      }
    }

    connection.batteryTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  void _setBattery(_RadioConnection connection, RadioBattery? sample) {
    if (sample == connection.battery) return;
    connection.battery = sample;
    if (connection.online) _changed();
  }

  Future<void> forget(Radio radio) async {
    final key = _profileKey(radio);
    if (!radios.any((item) => radioKey(item) == key)) return;
    final current = _connectionFor(radio);
    await disconnectRadio(radio);
    radios = radios.where((item) => radioKey(item) != key).toList();
    _connections.remove(key);
    _radioRoutes.remove(key);
    if (identical(current, _selected)) {
      _draftTimer?.cancel();
      openedChat = null;
      if (radios.firstOrNull case final next?) {
        _selected = _connection(next);
      } else {
        _selected = null;
      }
      final activeKey = active == null ? '' : radioKey(active!);
      await store.setActive(activeKey);
      await store.setAutoConnect(_autoConnections.contains(activeKey));
    }
    await _persistRadios();
    _changed();
  }

  Future<void> disconnect({bool manual = true}) => active == null
      ? Future.value()
      : disconnectRadio(active!, manual: manual);

  Future<void> disconnectRadio(Radio radio, {bool manual = true}) async {
    final connection = _connectionFor(radio);
    final key = _profileKey(radio);
    if (manual && !preview) {
      _autoConnections.remove(key);
      unawaited(store.setConnectedProfiles(_autoConnections));
      if (identical(connection, _selected)) {
        unawaited(store.setAutoConnect(false));
      }
    }
    if (connection == null) return;
    await _disconnectConnection(connection, cancelRestart: manual);
  }

  Future<void> suspendRadioConnections() async {
    await Future.wait([
      for (final connection in _connections.values.toList())
        if (connection.state != LinkState.offline || connection.restart != null)
          _disconnectConnection(connection, cancelRestart: true),
    ]);
  }

  Future<void> _disconnectConnection(
    _RadioConnection connection, {
    required bool cancelRestart,
  }) async {
    if (cancelRestart) _finishRestart(connection);
    ++connection.generation;
    connection.state = LinkState.offline;
    _changed();
    await _release(connection);
  }

  void _expectRestart(_RadioConnection connection, bool explicit) {
    connection.restart ??= Completer<void>();
    connection.explicitRestart |= explicit;
    connection.restartWindow?.cancel();
    connection.restartWindow = Timer(const Duration(seconds: 12), () {
      _finishRestart(connection);
      _changed();
    });
    _changed();
  }

  void _finishRestart(_RadioConnection connection) {
    connection.restartWindow?.cancel();
    connection.restartWindow = null;
    connection.explicitRestart = false;
    final restart = connection.restart;
    connection.restart = null;
    restart?.complete();
  }

  Future<void> _reconnectAfterRestart(_RadioConnection connection) async {
    final restart = connection.restart!;
    connection.restartWindow?.cancel();
    connection.restartWindow = null;
    ++connection.generation;
    connection.state = LinkState.connecting;
    _changed();
    try {
      await _release(connection);
      for (var attempt = 0; attempt < 6; attempt++) {
        if (connection.restart != restart || _closed) return;
        await _connect(connection, retry: true);
        if (connection.online) return;
        if (attempt < 5) {
          await Future<void>.delayed(Duration(seconds: attempt + 1));
        }
      }
    } finally {
      if (connection.restart == restart) {
        if (!connection.online) connection.state = LinkState.offline;
        _finishRestart(connection);
        _changed();
      }
    }
  }

  Future<void> _release(_RadioConnection connection) async {
    connection.signalTimer?.cancel();
    connection.signalTimer = null;
    connection.rssi = null;
    connection.latency = null;
    connection.batteryTimer?.cancel();
    connection.batteryTimer = null;
    connection.battery = null;
    final key = _profileKey(connection.radio);
    for (final pending in _receipts.entries.toList()) {
      if (_profileKey(pending.value.radio) != key) continue;
      pending.value.timer.cancel();
      _apply(
        pending.value.radio,
        DeliveryUpdate(pending.key, Delivery.unconfirmed),
      );
    }
    final events = connection.events;
    final session = connection.session;
    connection.events = null;
    connection.session = null;
    await (connection.closing = connection.closing.then((_) async {
      try {
        await events?.cancel();
        await session?.close();
      } catch (exception) {
        debugPrint('MeshGrame disconnect: $exception');
      }
    }));
  }

  Future<List<String>> importWifiMessages(
    List<({String file, String radio, Uint8List frame, DateTime receivedAt})>
    packets,
  ) async {
    final accepted = <String>[];
    final byRadio = <String, List<String>>{};
    for (final packet in packets) {
      final radio = _savedRadio(packet.radio);
      final adapter = adapters[radio?.network];
      if (radio == null || adapter is! NetworkBufferedMessages) {
        accepted.add(packet.file);
        continue;
      }
      final data = _cacheFor(radio);
      final event = (adapter as NetworkBufferedMessages).bufferedMessage(
        packet.frame,
        data.peers,
        data.radioNodeNumber,
        packet.receivedAt,
      );
      if (event != null) _apply(radio, event, buffered: true);
      byRadio.putIfAbsent(_profileKey(radio), () => []).add(packet.file);
    }
    for (final entry in byRadio.entries) {
      final data = _cacheAt(entry.key);
      _limitHistory(data);
      if (await store.save(entry.key, data)) accepted.addAll(entry.value);
    }
    if (byRadio.isNotEmpty) _changed();
    return accepted;
  }

  void _apply(
    Radio radio,
    NetworkEvent event, {
    bool buffered = false,
    _RadioConnection? connection,
  }) {
    final current = _cacheFor(radio);
    switch (event) {
      case DirectoryUpdate(
        :final peers,
        :final name,
        :final identities,
        :final radioPublicKey,
        :final radioHardwareId,
        :final radioNodeNumber,
        :final deviceInfo,
      ):
        current.identities.addAll(identities);
        if (radioPublicKey != null) current.radioPublicKey = radioPublicKey;
        if (radioHardwareId != null) current.radioHardwareId = radioHardwareId;
        if (radioNodeNumber != null) current.radioNodeNumber = radioNodeNumber;
        if (deviceInfo != null) {
          final previous = current.deviceInfo;
          current.deviceInfo = (
            firmware: deviceInfo.firmware ?? previous?.firmware,
            board: deviceInfo.board ?? previous?.board,
            boardModel: deviceInfo.boardModel ?? previous?.boardModel,
            build: deviceInfo.build ?? previous?.build,
            protocol: deviceInfo.protocol ?? previous?.protocol,
          );
        }
        final available = {for (final peer in peers) peer.id: peer};
        current.peers.updateAll(
          (id, peer) =>
              available[id] ??
              (
                id: peer.id,
                name: peer.name,
                writable: false,
                channel: peer.channel,
              ),
        );
        current.peers.addAll(available);
        if (name != null && name.isNotEmpty && name != radio.name) {
          final refreshed = (
            device: radio.device,
            network: radio.network,
            name: name,
          );
          if (connection != null) connection.radio = refreshed;
          radios = [
            for (final item in radios)
              radioKey(item) == radioKey(radio) ? refreshed : item,
          ];
          if (connection?.online == true) unawaited(_persistRadios());
        }
      case TextReceived(:final message, :final peer):
        final index = current.messages.indexWhere(
          (item) => item.id == message.id,
        );
        if (index >= 0) {
          final stored = current.messages[index];
          if (stored.packet != null || message.packet == null) return;
          current.messages[index] = stored.withUpdate(
            packet: message.packet,
            reference: message.remoteId,
          );
          break;
        }
        current.peers.putIfAbsent(message.chat, () => peer);
        if (!peer.channel &&
            current.observe(
              peer.id,
              NodeObservation(lastSeen: message.time),
              DateTime.now(),
            )) {
          _scheduleNodeRefresh();
        }
        current.messages.add(message);
        if (!identical(connection ?? _connectionFor(radio), _selected) ||
            openedChat != message.chat ||
            isChatForeground?.call() == false) {
          current.unread.update(
            message.chat,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
        if (!buffered &&
            !message.outgoing &&
            !current.muted.contains(message.chat)) {
          onIncomingMessage?.call(
            radio,
            current.peers[peer.id] ?? peer,
            message,
          );
        }
      case NodeObserved(:final id, :final observation, :final peer):
        final added = peer != null && !current.peers.containsKey(id);
        if (added) current.peers[id] = peer;
        final lastSeen = current.observations[id]?.lastSeen;
        final changed = current.observe(id, observation, DateTime.now());
        if (!changed && !added) return;
        // Persist the snapshot together when the radio finishes connecting.
        if (connection?.state == LinkState.connecting) return;
        if (lastSeen != current.observations[id]?.lastSeen) {
          _scheduleNodeRefresh();
        }
      case LocalNodePosition(:final position):
        if (position == current.localPosition) return;
        current.localPosition = position;
      case DeliveryUpdate(:final id, :final delivery, :final packet):
        final index = current.messages.indexWhere((item) => item.id == id);
        if (!delivery.awaitingReceipt) _receipts.remove(id)?.timer.cancel();
        if (index < 0) return;
        final previous = current.messages[index].delivery;
        if (!previous.awaitingReceipt && delivery != Delivery.acknowledged) {
          return;
        }
        current.messages[index] = current.messages[index].withUpdate(
          delivery: delivery,
          packet: packet,
        );
      case MessagePacketUpdated(:final id, :final packet, :final reference):
        final index = current.messages.indexWhere((item) => item.id == id);
        if (index < 0) return;
        current.messages[index] = current.messages[index].withUpdate(
          packet: packet,
          reference: reference,
        );
      case ReactionReceived(:final reaction):
        if (!_addReaction(current, reaction)) return;
        if (!buffered &&
            !reaction.own &&
            !current.muted.contains(reaction.chat) &&
            current.messages.any(
              (message) =>
                  message.outgoing &&
                  message.chat == reaction.chat &&
                  message.remoteId == reaction.target,
            ) &&
            current.peers.containsKey(reaction.chat)) {
          onIncomingReaction?.call(
            radio,
            current.peers[reaction.chat]!,
            reaction,
          );
        }
      case RouteTraceReceived(:final peer, :final request, :final fields):
        final trace = current.routeTraces[request];
        if (trace == null || trace.peer != peer) return;
        // A route may be reported again with signal readings from the probe.
        if (trace.receivedAt != null &&
            fields.every((field) => field.hops.isEmpty)) {
          return;
        }
        current.routeTraces[request] = trace.received(fields, DateTime.now());
      case RouteTraceRejected(:final request, :final failure):
        final trace = current.routeTraces[request];
        if (trace == null || !trace.pending) return;
        current.routeTraces[request] = trace.rejected(failure);
      case RadioBatteryChanged(battery: final sample):
        if (connection != null) _setBattery(connection, sample);
        return;
      case RadioRestartExpected(:final explicit):
        if (connection != null) _expectRestart(connection, explicit);
        return;
      case RadioEnded():
        if (connection?.restartWindow != null) {
          unawaited(_reconnectAfterRestart(connection!));
          return;
        }
        if (identical(connection, _selected)) error = 'lost';
        unawaited(disconnectRadio(radio, manual: false));
    }
    if (!buffered) {
      _save(radio);
      _changed();
    }
  }

  void _save(Radio radio) {
    if (preview) return;
    final data = _cacheFor(radio);
    _limitHistory(data);
    unawaited(store.save(_profileKey(radio), data));
  }

  void _limitHistory(ChatCache data) {
    if (data.messages.length > 1000) {
      data.messages.removeRange(0, data.messages.length - 1000);
    }
  }

  void readChat(String id) {
    openedChat = id;
    if (active case final radio?) {
      _cacheFor(radio).unread.remove(id);
      _save(radio);
    }
    _changed();
  }

  void leaveChat() => openedChat = null;

  String draft(String id) => cache?.drafts[id] ?? '';
  void setDraft(String id, String text) {
    final radio = active;
    if (radio == null) return;
    _cacheFor(radio).drafts[id] = text;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 250), () => _save(radio));
  }

  String? referenceFor(MeshMessage message) {
    final adapter = adapters[active?.network];
    return message.remoteId ??
        (adapter is NetworkMessageReferences
            ? (adapter as NetworkMessageReferences).referenceFor(message)
            : null);
  }

  bool _canTargetMessage(Peer peer, MeshMessage message) =>
      canSendTo(peer) &&
      message.chat == peer.id &&
      message.delivery != Delivery.queued &&
      message.delivery != Delivery.failed &&
      referenceFor(message) != null;

  bool canUseMessageActions(Peer peer, MeshMessage message) =>
      (_session is NetworkMessageActions ||
          (preview && active?.network == 'meshtastic')) &&
      connected &&
      _canTargetMessage(peer, message);

  bool canReact(Peer peer, MeshMessage message) =>
      (_session is NetworkReactions || preview) &&
      connected &&
      _canTargetMessage(peer, message);

  bool canChooseReaction(Peer peer, MeshMessage message) => connected
      ? canReact(peer, message)
      : adapters[active?.network] is NetworkMessageReferences &&
            _canTargetMessage(peer, message);

  MeshMessage? referencedMessage(String chat, String? reference) {
    if (reference == null) return null;
    return cache?.messages
        .where((item) => item.chat == chat && referenceFor(item) == reference)
        .lastOrNull;
  }

  MeshMessage? replyDraft(String chat) =>
      referencedMessage(chat, cache?.replies[chat]);

  void setReplyDraft(String chat, MeshMessage? message) {
    final radio = active;
    if (radio == null) return;
    final data = _cacheFor(radio);
    final ref = message == null ? null : referenceFor(message);
    if (ref == null) {
      data.replies.remove(chat);
    } else {
      data.replies[chat] = ref;
    }
    _save(radio);
    _changed();
  }

  List<MeshReaction> reactionsFor(MeshMessage message) {
    final ref = referenceFor(message);
    return ref == null
        ? []
        : cache?.reactions
                  .where(
                    (reaction) =>
                        reaction.chat == message.chat && reaction.target == ref,
                  )
                  .toList() ??
              [];
  }

  ({String? name, bool hasKey, Peer? peer}) reactionAuthor(
    MeshReaction reaction,
  ) {
    final data = cache;
    if (reaction.own) {
      return (
        name: active?.name,
        hasKey: data?.radioPublicKey?.isNotEmpty == true,
        peer: null,
      );
    }
    final actor = reaction.actor;
    if (actor.startsWith('name:')) {
      final name = actor.substring(5);
      // MeshCore channel text carries a sender name when no node ID is attached.
      final peer = _uniqueNodeNamed(name);
      return (
        name: name,
        hasKey: data?.identities[peer?.id]?.publicKey.isNotEmpty == true,
        peer: peer,
      );
    }
    final id = actor.startsWith('node:') ? actor : 'node:$actor';
    return (
      name: data?.peers[id]?.name,
      hasKey: data?.identities[id]?.publicKey.isNotEmpty == true,
      peer: data?.peers[id],
    );
  }

  Peer? messageAuthor(MeshMessage message) {
    final sender = message.packet?.sender;
    return sender == null
        ? _uniqueNodeNamed(message.author)
        : cache?.peers[sender];
  }

  Peer? _uniqueNodeNamed(String name) {
    if (name.isEmpty) return null;
    final matches = cache?.peers.values
        .where((peer) => !peer.channel && peer.name == name)
        .take(2)
        .toList();
    return matches?.length == 1 ? matches!.single : null;
  }

  String? nodeName(String id) => cache?.peers[id]?.name;

  static const _recentReactionLimit = 3;
  List<String>? _legacyReactionEmojis;

  List<String> get recentReactionEmojis =>
      store.recentReactionEmojis ??
      (_legacyReactionEmojis ??= _previousReactionEmojis());

  List<String> _previousReactionEmojis() {
    // Upgrades can recover the recent choices from the existing radio history.
    final own =
        [
          for (final radio in radios)
            ..._cacheFor(radio).reactions
                .where((reaction) => reaction.own && reaction.emoji.isNotEmpty),
        ]..sort(
          (a, b) => (b.time?.millisecondsSinceEpoch ?? 0).compareTo(
            a.time?.millisecondsSinceEpoch ?? 0,
          ),
        );
    final recent = <String, String>{};
    for (final reaction in own) {
      recent.putIfAbsent(reaction.emojiKey, () => reaction.emoji);
      if (recent.length == _recentReactionLimit) break;
    }
    return recent.values.toList();
  }

  void _rememberReactionEmoji(MeshReaction reaction) {
    final previous = recentReactionEmojis;
    final recent = [
      reaction.emoji,
      for (final emoji in previous)
        if (reactionEmojiKey(emoji) != reaction.emojiKey) emoji,
    ].take(_recentReactionLimit).toList();
    if (listEquals(previous, recent) && store.recentReactionEmojis != null) {
      return;
    }
    unawaited(
      store
          .setRecentReactionEmojis(recent)
          .then<void>(
            (_) {},
            onError: (Object error) =>
                debugPrint('Meshgram recent reactions: $error'),
          ),
    );
  }

  final _pendingReactions = <(String, String, String, String)>{};

  Future<bool> react(Peer peer, MeshMessage message, String emoji) async {
    final radio = active;
    final session = _session;
    final reference = referenceFor(message);
    if (radio == null ||
        reference == null ||
        !canReact(peer, message) ||
        emoji.isEmpty ||
        utf8.encode(emoji).length > (limit(peer) ?? 0)) {
      return false;
    }
    final data = _cacheFor(radio);
    final reaction = MeshReaction(
      peer.id,
      reference,
      'local',
      emoji,
      own: true,
      time: DateTime.now(),
    );
    final key = (radioKey(radio), peer.id, reference, reaction.emojiKey);
    if (data.reactions.any(reaction.matches) || !_pendingReactions.add(key)) {
      return true;
    }
    try {
      if (session is NetworkReactions) {
        await (session as NetworkReactions).react(peer, reference, emoji);
      }
      if (_addReaction(data, reaction)) {
        _rememberReactionEmoji(reaction);
        _save(radio);
        _changed();
      }
      return true;
    } catch (error) {
      debugPrint('MeshGrame reaction: $error');
      return false;
    } finally {
      _pendingReactions.remove(key);
    }
  }

  bool _addReaction(ChatCache data, MeshReaction reaction) {
    if (data.reactions.any(reaction.matches)) return false;
    data.reactions.add(reaction);
    if (data.reactions.length > 1000) data.reactions.removeAt(0);
    return true;
  }

  int? limit(Peer peer) {
    final live = _session?.textLimit(peer);
    if (live != null) return live;
    final radio = active;
    final adapter = adapters[radio?.network];
    if (radio != null && adapter is NetworkMessageBudget) {
      return (adapter as NetworkMessageBudget).messageBytes(peer, radio.name);
    }
    return null;
  }

  Future<bool> send(
    Peer peer,
    String text, {
    MeshMessage? reply,
    bool suppressLinkPreview = false,
  }) async {
    if (reply != null && !canUseMessageActions(peer, reply)) return false;
    return _sendMessage(
      peer,
      text,
      replyTo: reply == null ? null : referenceFor(reply),
      suppressLinkPreview: suppressLinkPreview,
    );
  }

  Future<bool> sendAttachment(Peer peer, String text) =>
      _sendMessage(peer, text, isAttachment: true);

  Future<bool> retryMessage(Peer peer, String messageId) async {
    final failed = cache?.messages
        .where(
          (message) =>
              message.id == messageId &&
              message.chat == peer.id &&
              message.delivery.canRetry,
        )
        .firstOrNull;
    if (failed == null) return false;
    return _sendMessage(
      peer,
      failed.text,
      replyTo: failed.replyTo,
      retryId: messageId,
      isAttachment: failed.isAttachment,
      suppressLinkPreview: failed.suppressLinkPreview,
    );
  }

  Future<bool> _sendMessage(
    Peer peer,
    String text, {
    String? replyTo,
    String? retryId,
    bool isAttachment = false,
    bool suppressLinkPreview = false,
  }) async {
    final radio = active;
    final session = _session;
    if (radio == null ||
        (!preview && session == null) ||
        !connected ||
        !canSendTo(peer) ||
        text.trim().isEmpty ||
        utf8.encode(text).length > (limit(peer) ?? 0)) {
      return false;
    }
    final current = _cacheFor(radio);
    final previousDraft = current.drafts[peer.id];
    final now = DateTime.now();
    final id = 'out:${now.microsecondsSinceEpoch}:${_random.nextInt(1 << 20)}';
    final outgoing = MeshMessage(
      id: id,
      chat: peer.id,
      author: '',
      text: text,
      time: now,
      delivery: Delivery.queued,
      replyTo: replyTo,
      isAttachment: isAttachment,
      suppressLinkPreview: suppressLinkPreview,
      remoteId: session is NetworkMessageActions
          ? (session as NetworkMessageActions).nextMessageReference()
          : preview
          ? 'demo:$id'
          : null,
    );
    if (retryId == null) {
      if (!isAttachment) current.drafts.remove(peer.id);
    } else {
      _receipts.remove(retryId)?.timer.cancel();
      current.messages.removeWhere((message) => message.id == retryId);
    }
    current.messages.add(outgoing);
    _save(radio);
    _changed();
    var result = preview ? Delivery.acknowledged : Delivery.submitted;
    try {
      await session?.send(peer, outgoing);
    } catch (exception) {
      debugPrint('MeshGrame send: $exception');
      result = Delivery.failed;
    }
    final index = current.messages.indexWhere((message) => message.id == id);
    if (index >= 0 && current.messages[index].delivery == Delivery.queued) {
      current.messages[index] = current.messages[index].withDelivery(result);
    }
    if (index >= 0 && current.messages[index].delivery.awaitingReceipt) {
      if (session != _connectionFor(radio)?.session || !isConnectedTo(radio)) {
        current.messages[index] = current.messages[index].withDelivery(
          Delivery.unconfirmed,
        );
      } else {
        _receipts[id] = (
          radio: radio,
          timer: Timer(
            const Duration(seconds: 100),
            () => _apply(radio, DeliveryUpdate(id, Delivery.unconfirmed)),
          ),
        );
      }
    }
    if (index >= 0 &&
        !isAttachment &&
        retryId == null &&
        result == Delivery.failed &&
        (current.drafts[peer.id] ?? '').isEmpty) {
      current.drafts[peer.id] = text;
    }
    if (index >= 0 &&
        !isAttachment &&
        retryId != null &&
        result != Delivery.failed &&
        previousDraft?.trim() == text &&
        current.drafts[peer.id] == previousDraft) {
      current.drafts.remove(peer.id);
    }
    _save(radio);
    _changed();
    return result != Delivery.failed;
  }

  void rememberSearch(String id) {
    final radio = active;
    final current = cache;
    if (radio == null || current == null) return;
    final history = current.searchHistory;
    history.remove(id);
    history.insert(0, id);
    if (history.length > 16) history.removeLast();
    _save(radio);
    _changed();
  }

  void clearSearchHistory() {
    final radio = active;
    if (radio == null) return;
    _cacheFor(radio).searchHistory.clear();
    _save(radio);
    _changed();
  }

  void toggleMute(String id) {
    if (active case final radio?) {
      setNotificationException(radio, id, isMutedFor(radio, id) ? null : false);
    }
  }

  void setName(String name) {
    profileName = name.trim();
    unawaited(store.setName(profileName));
    _changed();
  }

  void setAppearance(String value) {
    appearance = value;
    unawaited(store.setAppearance(value));
    _changed();
  }

  void _seedPreview() {
    radios = [
      (network: 'meshtastic', device: 'demo-tastic', name: 'Heltec V3'),
      (network: 'meshcore', device: 'demo-core', name: 'T-Deck Plus'),
    ];
    _selected = _connection(radios.first)..state = LinkState.online;
    final now = DateTime.now();
    for (final radio in radios) {
      final data = _cacheFor(radio);
      final list = <Peer>[
        (id: 'ch:0', name: 'Тропа', channel: true, writable: true),
        (
          id: 'node:a',
          name: radio.network == 'meshcore' ? 'Антон Белов' : 'Мира Соколова',
          channel: false,
          writable: true,
        ),
        (id: 'ch:1', name: 'Лагерь', channel: true, writable: true),
        (id: 'node:b', name: 'Илья Ветров', channel: false, writable: true),
        (id: 'node:c', name: 'Лена Орлова', channel: false, writable: true),
      ];
      for (final peer in list) {
        data.peers[peer.id] = peer;
      }
      for (final (index, peer) in list.where((peer) => !peer.channel).indexed) {
        data.observe(
          peer.id,
          NodeObservation(
            lastSeen: now.subtract(switch (index) {
              0 => const Duration(minutes: 13),
              1 => const Duration(hours: 2),
              _ => const Duration(days: 2),
            }),
            position: (latitude: 55.76 + index * .02, longitude: 49.14),
            hops: index,
            channel: index % 2,
            favorite: index == 0,
            viaMqtt: index == 2,
          ),
          now,
        );
      }
      data.localPosition = (latitude: 55.75, longitude: 49.14);
      final lines = [
        'Лена: Мы у развилки',
        'Вижу метку. Скоро будем.',
        'На месте, вода есть.',
        'Остаюсь на точке.',
        'Спасибо, принято.',
      ];
      for (var i = 0; i < list.length; i++) {
        data.messages.add(
          MeshMessage(
            id: 'demo:$i',
            remoteId: 'demo:$i',
            chat: list[i].id,
            author: list[i].name,
            text: lines[i],
            time: now.subtract(Duration(minutes: i * 11 + 2)),
            delivery: Delivery.received,
          ),
        );
      }
      final thread = [
        ('Мы вышли к северной тропе. Вы где сейчас?', Delivery.received),
        ('У ручья. До развилки минут десять.', Delivery.acknowledged),
        ('На гребне сигнал лучше. Встретимся там?', Delivery.received),
        ('Да. Отметил точку на карте.', Delivery.acknowledged),
      ];
      for (var i = 0; i < thread.length; i++) {
        data.messages.add(
          MeshMessage(
            id: 'preview:$i',
            remoteId: 'preview:$i',
            chat: list[1].id,
            author: list[1].name,
            text: thread[i].$1,
            time: now.subtract(Duration(minutes: 33 - i * 3)),
            delivery: thread[i].$2,
          ),
        );
      }
      data.unread.addAll({'ch:0': 3, 'node:a': 1, 'ch:1': 2});
      data.muted.add('ch:1');
    }
  }

  @override
  void dispose() {
    _closed = true;
    ++_scanGeneration;
    _draftTimer?.cancel();
    _nodeTimer?.cancel();
    if (active case final radio?) _save(radio);
    unawaited(_stopScanners());
    for (final connection in _connections.values) {
      ++connection.generation;
      _finishRestart(connection);
      unawaited(_release(connection));
    }
    super.dispose();
  }
}
