import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'mesh/controller.dart';
import 'mesh/network.dart';

enum NotificationPermission { prompt, enabled, disabled }

enum NotificationSetting {
  allRadios,
  direct,
  channels,
  reactions,
  directPreview,
  channelPreview,
  directSound,
  channelSound,
  preview,
  names,
  inAppSound,
  vibration,
  badgeChannels,
  badgeMessages,
  badge,
}

class LocalMessageNotifications extends ChangeNotifier {
  static const _channel = MethodChannel('meshgrame/notifications');
  static const _wifi = MethodChannel('meshgrame/wifi_push');
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  late final MeshController _controller;
  late final AppLifecycleListener _lifecycle;
  NotificationPermission? _permission;
  bool _asked = false;
  bool _requesting = false;
  bool _serviceRunning = false;
  bool _backgroundStopped = false;
  bool _androidWasBackground = false;
  Future<void>? _suspendingRadios;
  bool _syncingService = false;
  bool _syncPending = false;
  bool _disposed = false;
  Timer? _reconnect;
  Future<void> _wifiHandoff = Future.value();
  bool wifiPushAvailable = false;
  bool wifiPushActive = false;
  String wifiPushSsid = '';

  final _overrides = <String>{};
  int? _lastBadge;
  bool option(NotificationSetting setting) {
    final enabledByDefault =
        setting != NotificationSetting.reactions &&
        setting != NotificationSetting.inAppSound &&
        setting != NotificationSetting.vibration &&
        setting != NotificationSetting.badge;
    return enabledByDefault != _overrides.contains(setting.name);
  }

  void setOption(NotificationSetting setting, bool value) {
    if (value == option(setting)) return;
    if (!_overrides.remove(setting.name)) _overrides.add(setting.name);
    unawaited(_controller.store.setNotificationOverrides(_overrides));
    if (setting == NotificationSetting.badge && value && _ios) {
      unawaited(
        _invoke<void>('requestBadge').whenComplete(() {
          _lastBadge = null;
          _scheduleSync();
        }),
      );
    }
    _scheduleSync();
    notifyListeners();
  }

  void resetPreferences() {
    _overrides.clear();
    unawaited(_controller.store.setNotificationOverrides(_overrides));
    _controller.resetNotificationExceptions();
    _scheduleSync();
    notifyListeners();
  }

  bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;
  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  AppLifecycleState? get _state => WidgetsBinding.instance.lifecycleState;
  bool get _resumed => _state == AppLifecycleState.resumed;
  bool get isForeground => _resumed || _state == AppLifecycleState.inactive;
  NotificationPermission? get permission => _permission;

  Future<void> start(MeshController controller) async {
    _controller = controller;
    _overrides.addAll(controller.store.notificationOverrides);
    if (!supported || controller.preview) return;
    if (_android) {
      _channel.setMethodCallHandler(_handleAndroidEvent);
    }
    _lifecycle = AppLifecycleListener(
      onStateChange: (_) {
        if (_android && !isForeground) _androidWasBackground = true;
        _scheduleSync();
      },
      onResume: () {
        unawaited(_refreshPermission());
        if (_android) {
          final fromBackground = _androidWasBackground;
          _androidWasBackground = false;
          unawaited(_resumeAndroid(fromBackground: fromBackground));
        } else if (_ios) {
          _queueWifiWork(_returnToApp);
        }
      },
      onPause: () {
        if (_android && _backgroundStopped) unawaited(_suspendRadios());
        if (_ios && wifiPushSsid.isNotEmpty) {
          _queueWifiWork(() async {
            try {
              await _handOffWifi();
            } finally {
              await _wifi.invokeMethod<void>('finishHandoff');
            }
          });
        }
      },
    );
    controller.addListener(_scheduleSync);
    await _refreshPermission();
    if (_ios) {
      await _refreshWifiStatus();
      if (isForeground) await _queueWifiWork(_takeBackWifi);
    }
  }

  Future<void> _handleAndroidEvent(MethodCall call) async {
    if (call.method != 'backgroundStopped') throw MissingPluginException();
    if (_disposed || _backgroundStopped) return;
    _backgroundStopped = true;
    _serviceRunning = false;
    _reconnect?.cancel();
    _reconnect = null;
    await _suspendRadios();
  }

  Future<void> _suspendRadios() => _suspendingRadios ??= _controller
      .suspendRadioConnections()
      .whenComplete(() {
        _suspendingRadios = null;
      });

  Future<void> _resumeAndroid({required bool fromBackground}) async {
    if (_suspendingRadios case final stopping?) await stopping;
    if (_disposed || !_resumed) return;
    if (_backgroundStopped) {
      if (!fromBackground) return;
      await _invoke<void>('resumeConnectionService');
      if (_disposed || !_resumed) return;
      _backgroundStopped = false;
    }
    unawaited(_controller.restoreConnection());
    _scheduleSync();
  }

  bool supportsRadio(Radio radio) =>
      supported &&
      (_android || lanEndpoint(_controller.connectionRoute(radio)) == null);

  bool _accepts(Radio radio, Peer peer) {
    if (_disposed ||
        (!option(NotificationSetting.allRadios) &&
            _controller.active != null &&
            radioKey(_controller.active!) != radioKey(radio))) {
      return false;
    }
    return _controller.notificationException(radio, peer.id) ??
        option(
          peer.channel
              ? NotificationSetting.channels
              : NotificationSetting.direct,
        );
  }

  void received(Radio radio, Peer peer, MeshMessage message) {
    if (!_accepts(radio, peer)) return;
    final showText =
        option(NotificationSetting.preview) &&
        option(
          peer.channel
              ? NotificationSetting.channelPreview
              : NotificationSetting.directPreview,
        );
    final author = message.author.trim();
    final body =
        peer.channel && author.isNotEmpty && option(NotificationSetting.names)
        ? '$author: ${message.text}'
        : message.text;
    _publish(
      radio,
      peer,
      showText ? body : _localized('Новое сообщение', 'New message'),
    );
  }

  void receivedReaction(Radio radio, Peer peer, MeshReaction reaction) {
    if (!option(NotificationSetting.reactions) || !_accepts(radio, peer)) {
      return;
    }
    _publish(
      radio,
      peer,
      _localized('Реакция на сообщение', 'Reaction to your message'),
    );
  }

  String _localized(String ru, String en) =>
      PlatformDispatcher.instance.locale.languageCode == 'ru' ? ru : en;

  void _publish(Radio radio, Peer peer, String body) {
    if (isForeground) {
      if (radioKey(radio) ==
              (_controller.active == null
                  ? null
                  : radioKey(_controller.active!)) &&
          _controller.openedChat == peer.id) {
        return;
      }
      if (option(NotificationSetting.inAppSound)) {
        unawaited(_invoke<void>('playInAppSound'));
      }
      if (option(NotificationSetting.vibration)) {
        unawaited(HapticFeedback.vibrate());
      }
      return;
    }
    if (_backgroundStopped ||
        _permission != NotificationPermission.enabled ||
        !supportsRadio(radio)) {
      return;
    }
    final title = option(NotificationSetting.names)
        ? (peer.name.isEmpty ? radio.name : peer.name)
        : 'Meshgram';
    unawaited(
      _invoke<void>('publish', {
        'chat': '${radioKey(radio)}/${peer.id}',
        'title': title,
        'body': body,
        'sound': option(
          peer.channel
              ? NotificationSetting.channelSound
              : NotificationSetting.directSound,
        ),
      }),
    );
  }

  void _syncBadge() {
    if (!_ios || _permission != NotificationPermission.enabled) return;
    if (!option(NotificationSetting.badge) && _lastBadge == null) return;
    var count = 0;
    if (option(NotificationSetting.badge)) {
      final source = option(NotificationSetting.allRadios)
          ? _controller.radios
          : [_controller.active].whereType<Radio>();
      for (final radio in source) {
        final data = _controller.notificationCache(radio);
        for (final unread in data.unread.entries) {
          if (unread.value <= 0) continue;
          if (!option(NotificationSetting.badgeChannels) &&
              data.peers[unread.key]?.channel == true) {
            continue;
          }
          count += option(NotificationSetting.badgeMessages) ? unread.value : 1;
        }
      }
    }
    if (count != _lastBadge) {
      _lastBadge = count;
      unawaited(_invoke<void>('badge', count));
    }
  }

  Future<void> managePermission() async {
    if (_permission == NotificationPermission.prompt) {
      await _requestPermission();
    } else {
      await _invoke<void>('openSettings');
    }
  }

  Future<bool> configureWifiPush(String ssid) async {
    if (ssid.isNotEmpty && _permission == NotificationPermission.prompt) {
      await _requestPermission();
    }
    try {
      final applied = await _wifi.invokeMethod<bool>('configure', ssid);
      await _refreshWifiStatus();
      return applied == true;
    } on PlatformException catch (error) {
      debugPrint('Meshgram Wi-Fi notifications: ${error.code}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> _refreshWifiStatus() async {
    try {
      final values = await _wifi.invokeMapMethod<String, Object?>('status');
      if (_disposed || values == null) return;
      wifiPushAvailable = values['available'] == true;
      wifiPushSsid = values['ssid'] as String? ?? '';
      wifiPushActive = values['active'] == true;
      notifyListeners();
    } on PlatformException catch (error) {
      debugPrint('Meshgram Wi-Fi notifications: ${error.code}');
    } on MissingPluginException {
      // Ordinary and test builds can omit the Wi-Fi push extension.
    }
  }

  Future<void> _queueWifiWork(Future<void> Function() work) {
    return _wifiHandoff = _wifiHandoff
        .then((_) async {
          if (!_disposed) await work();
        })
        .catchError((Object error) {
          debugPrint('Meshgram Wi-Fi handoff: $error');
        });
  }

  Future<void> _handOffWifi() async {
    if (isForeground || _permission != NotificationPermission.enabled) return;
    final sockets = <(Radio, LanEndpoint)>[];
    for (final radio in _controller.connectedRadios) {
      final endpoint = lanEndpoint(_controller.connectionRoute(radio));
      if (endpoint == null || _controller.isReconnecting(radio)) continue;
      final cache = _controller.notificationCache(radio);
      if ((radio.network == 'meshcore' && cache.radioPublicKey != null) ||
          (radio.network == 'meshtastic' && cache.radioNodeNumber != null)) {
        sockets.add((radio, endpoint));
      }
    }
    if (sockets.isEmpty) return;

    // Give each PhoneAPI TCP connection to the extension once its foreground
    // session has closed. The Bluetooth sessions can keep running.
    await Future.wait([
      for (final (radio, _) in sockets)
        _controller.disconnectRadio(radio, manual: false),
    ]);
    if (isForeground) return;
    await _wifi.invokeMethod<bool>('stage', [
      for (final (radio, endpoint) in sockets) _wifiSnapshot(radio, endpoint),
    ]);
  }

  Map<String, Object?> _wifiSnapshot(Radio radio, LanEndpoint endpoint) {
    final cache = _controller.notificationCache(radio);
    final ownMessages = <String, List<String>>{};
    if (option(NotificationSetting.reactions)) {
      for (final message in cache.messages.where(
        (message) => message.outgoing,
      )) {
        if (message.remoteId case final reference?) {
          ownMessages.putIfAbsent(message.chat, () => []).add(reference);
        }
      }
    }
    return {
      'key': radioKey(radio),
      'network': radio.network,
      'name': radio.name,
      'host': endpoint.host,
      'port': endpoint.port,
      'selfNode': cache.radioNodeNumber,
      'publicKey': cache.radioPublicKey,
      'hardwareID': cache.radioHardwareId,
      'muted': cache.muted.toList(),
      'unmuted': cache.unmuted.toList(),
      'ownMessages': ownMessages,
      'peers': cache.peers.map((id, peer) => MapEntry(id, peer.name)),
      'knownMessages': cache.messages.map((message) => message.id).toList(),
      'alerts': {
        'enabled':
            option(NotificationSetting.allRadios) ||
            radioKey(radio) ==
                (_controller.active == null
                    ? null
                    : radioKey(_controller.active!)),
        'direct': option(NotificationSetting.direct),
        'channels': option(NotificationSetting.channels),
        'directPreview':
            option(NotificationSetting.preview) &&
            option(NotificationSetting.directPreview),
        'channelPreview':
            option(NotificationSetting.preview) &&
            option(NotificationSetting.channelPreview),
        'directSound': option(NotificationSetting.directSound),
        'channelSound': option(NotificationSetting.channelSound),
        'names': option(NotificationSetting.names),
        'newMessage': _localized('Новое сообщение', 'New message'),
        'reactionMessage': _localized(
          'Реакция на сообщение',
          'Reaction to your message',
        ),
      },
    };
  }

  Future<void> _returnToApp() async {
    if (!isForeground) return;
    await _takeBackWifi();
    if (!isForeground) return;
    unawaited(_refreshWifiStatus());
    unawaited(_controller.restoreConnection());
  }

  Future<void> _takeBackWifi() async {
    if (!wifiPushAvailable) return;
    final values = await _wifi.invokeListMethod<Map<Object?, Object?>>(
      'resume',
    );
    final accepted = await _controller.importWifiMessages([
      for (final packet in values ?? const <Map<Object?, Object?>>[])
        if (packet['file'] case final String file)
          if (packet['radio'] case final String radio)
            if (packet['frame'] case final Uint8List frame)
              if (packet['receivedAt'] case final int stamp)
                (
                  file: file,
                  radio: radio,
                  frame: frame,
                  receivedAt: DateTime.fromMillisecondsSinceEpoch(stamp),
                ),
    ]);
    if (accepted.isNotEmpty) {
      await _wifi.invokeMethod<void>('acknowledge', accepted);
    }
  }

  Future<void> _refreshPermission() async {
    await _updatePermission('permission');
  }

  Future<void> _updatePermission(String method) async {
    final state = await _invoke<String>(method);
    if (_disposed) return;
    final next = NotificationPermission.values.asNameMap()[state];
    if (next != _permission) {
      _permission = next;
      notifyListeners();
    }
    _scheduleSync();
  }

  Future<void> _requestPermission() async {
    if (_requesting) return;
    _asked = _requesting = true;
    try {
      await _updatePermission('requestPermission');
    } finally {
      _requesting = false;
    }
  }

  void _scheduleSync() {
    if (_disposed || _syncPending) return;
    _syncPending = true;
    scheduleMicrotask(() {
      _syncPending = false;
      if (!_disposed) _sync();
    });
  }

  void _sync() {
    _syncBadge();
    final eligible = _controller.connectedRadios.any(supportsRadio);
    if ((eligible || (_ios && wifiPushSsid.isNotEmpty)) &&
        _controller.connectedRadios.isNotEmpty &&
        _resumed &&
        !_asked &&
        _permission == NotificationPermission.prompt) {
      unawaited(_requestPermission());
    }
    if (!_android) return;
    final keepConnection =
        !_backgroundStopped &&
        _permission == NotificationPermission.enabled &&
        (eligible || (_serviceRunning && _controller.hasAutoConnections));
    if (!_syncingService &&
        keepConnection != _serviceRunning &&
        (!keepConnection || _resumed)) {
      unawaited(_setService(keepConnection));
    }

    if (keepConnection &&
        _serviceRunning &&
        !isForeground &&
        _controller.hasOfflineAutoConnection &&
        !_controller.scanning) {
      _reconnect ??= Timer(const Duration(seconds: 15), () {
        _reconnect = null;
        unawaited(_controller.restoreConnection().whenComplete(_scheduleSync));
      });
    } else {
      _reconnect?.cancel();
      _reconnect = null;
    }
  }

  Future<void> _setService(bool enabled) async {
    _syncingService = true;
    final applied = await _invoke<bool>('connectionService', enabled);
    _syncingService = false;
    if (applied == true && !_disposed) {
      _serviceRunning = enabled && !_backgroundStopped;
      _scheduleSync();
    }
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      debugPrint('Meshgram notifications: ${error.code}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    if (supported && !_controller.preview) {
      if (_android) _channel.setMethodCallHandler(null);
      _lifecycle.dispose();
      _controller.removeListener(_scheduleSync);
    }
    super.dispose();
  }
}
