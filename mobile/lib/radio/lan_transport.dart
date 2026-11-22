// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data' show Endian;

import 'package:flutter/services.dart';
import 'package:nsd/nsd.dart' as nsd;

import '../mesh/network.dart';

class LanTransport implements RadioLanTransport {
  final _discoveries = <String, nsd.Discovery>{};
  Completer<void>? _scan;
  int _generation = 0;

  @override
  Future<void> scan(
    Map<String, LanRadioProtocol> protocols,
    void Function(List<DiscoveredRadio>) update,
  ) async {
    final generation = ++_generation;
    await _endScan();
    if (generation != _generation) return;
    final scan = _scan = Completer<void>();
    Object? discoveryError;
    final radios = <(String, nsd.Service), DiscoveredRadio>{};
    void publish() {
      if (generation != _generation) return;
      update(
        {for (final found in radios.values) radioKey(found.radio): found}.values
            .toList(),
      );
    }

    Future<void> resolve(
      String network,
      nsd.Discovery discovery,
      nsd.Service found,
    ) async {
      try {
        final service = await nsd
            .resolve(found)
            .timeout(const Duration(seconds: 5));
        if (generation != _generation || !discovery.services.contains(found)) {
          return;
        }
        final address = service.addresses?.firstOrNull?.address;
        final host = Platform.isAndroid
            ? address ?? service.host
            : service.host ?? address;
        final port = service.port;
        if (host == null || port == null) return;
        final radio = lanRadio(network, host, port, name: service.name);
        radios[(network, found)] = (radio: radio, rssi: 0);
        publish();
      } on nsd.NsdError {
        // An advertisement can disappear while the OS is resolving it.
      } on Exception {
        // Ignore incomplete advertisements and service resolution timeouts.
      }
    }

    try {
      await Future.wait([
        for (final entry in protocols.entries)
          if (entry.value.bonjourService case final service?)
            () async {
              try {
                final discovery = await nsd.startDiscovery(
                  service,
                  autoResolve: false,
                );
                if (generation != _generation) {
                  await nsd.stopDiscovery(discovery);
                  return;
                }
                _discoveries[entry.key] = discovery;
                discovery.addServiceListener((found, status) {
                  if (status == nsd.ServiceStatus.found) {
                    unawaited(resolve(entry.key, discovery, found));
                  } else {
                    radios.remove((entry.key, found));
                    publish();
                  }
                });
                for (final found in discovery.services) {
                  unawaited(resolve(entry.key, discovery, found));
                }
              } catch (error) {
                discoveryError ??= error;
              }
            }(),
      ]);
      if (_discoveries.isNotEmpty && generation == _generation) {
        await scan.future.timeout(const Duration(seconds: 8), onTimeout: () {});
      }
      if (generation == _generation && discoveryError != null) {
        throw discoveryError!;
      }
    } finally {
      if (generation == _generation) await stopScan();
    }
  }

  @override
  Future<void> stopScan() async {
    _generation++;
    await _endScan();
  }

  Future<void> _endScan() async {
    _scan?.complete();
    _scan = null;
    final discoveries = _discoveries.values.toList();
    _discoveries.clear();
    await Future.wait(discoveries.map(nsd.stopDiscovery));
  }

  @override
  Future<RadioLink> connect(
    LanEndpoint endpoint,
    LanRadioProtocol protocol,
  ) async {
    final socket = await Socket.connect(
      endpoint.host,
      endpoint.port,
      timeout: const Duration(seconds: 6),
    );
    return _TcpRadioLink(socket, protocol);
  }
}

class _TcpRadioLink implements RadioLink, RadioSignalLink, RadioLatencyLink {
  static const _wifi = MethodChannel('meshgrame/wifi_signal');

  @override
  Future<int?> readSignalRssi() async =>
      Platform.isAndroid ? _wifi.invokeMethod<int>('readRssi') : null;

  @override
  Future<Duration?> readLinkLatency() async {
    if (_closed || !(Platform.isIOS || Platform.isMacOS)) return null;
    // Darwin's public tcp_connection_info struct has tcpi_srtt at byte 44.
    const connectionInfo = 0x106; // TCP_CONNECTION_INFO in <netinet/tcp.h>.
    final info = _socket.getRawOption(
      RawSocketOption(RawSocketOption.levelTcp, connectionInfo, Uint8List(112)),
    );
    final smoothedRtt = ByteData.sublistView(info).getUint32(44, Endian.host);
    return smoothedRtt > 0 ? Duration(milliseconds: smoothedRtt) : null;
  }

  _TcpRadioLink(this._socket, this._protocol) {
    _listening = _socket.listen(_receive, onError: _finish, onDone: _finish);
    unawaited(_socket.done.then<void>((_) {}, onError: _finish));
    if (_protocol.wake.isNotEmpty) _socket.add(_protocol.wake);
    if (_protocol.heartbeat.isNotEmpty) {
      _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(
          write(
            _protocol.rx,
            _protocol.heartbeat,
          ).catchError((Object _) => _finish()),
        );
      });
    }
  }

  final Socket _socket;
  final LanRadioProtocol _protocol;
  final _frames = StreamController<Uint8List>();
  final _notices = StreamController<Uint8List>.broadcast();
  final _ended = StreamController<void>.broadcast();
  final _inbox = ListQueue<Uint8List>();
  Uint8List _pending = Uint8List(0);
  late final StreamSubscription<Uint8List> _listening;
  Future<void> _writes = Future.value();
  Timer? _heartbeat;
  var _closed = false;

  void _receive(Uint8List chunk) {
    final prefix = _protocol.inputPrefix;
    final header = prefix.length + 2;
    final data = _pending.isEmpty
        ? chunk
        : Uint8List.fromList([..._pending, ...chunk]);
    final words = ByteData.sublistView(data);
    var offset = 0;
    while (offset + header <= data.length) {
      var matches = true;
      for (var i = 0; i < prefix.length; i++) {
        if (data[offset + i] != prefix[i]) {
          matches = false;
          break;
        }
      }
      if (!matches) {
        offset++;
        continue;
      }
      final size = words.getUint16(offset + prefix.length, _protocol.endian);
      if (size == 0 || size > _protocol.maxPayload) {
        offset++;
        continue;
      }
      final end = offset + header + size;
      if (end > data.length) break;
      final frame = data.sublist(offset + header, end);
      if (_protocol.notice == null) {
        _frames.add(frame);
      } else {
        if (_inbox.length >= 8192) {
          _finish();
          return;
        }
        _inbox.add(frame);
        _notices.add(Uint8List(0));
      }
      offset = end;
    }
    _pending = data.sublist(offset);
  }

  @override
  bool contains(String characteristic) =>
      characteristic == _protocol.rx ||
      characteristic == _protocol.tx ||
      characteristic == _protocol.notice;

  @override
  Future<StreamSubscriptionHandle> subscribe(
    String characteristic,
    void Function(Uint8List) onFrame,
  ) async {
    if (characteristic == _protocol.notice) {
      return _LanSubscription(_notices.stream.listen(onFrame));
    }
    if (characteristic == _protocol.tx && _protocol.notice == null) {
      return _LanSubscription(_frames.stream.listen(onFrame));
    }
    throw StateError('Unsupported TCP subscription');
  }

  @override
  Future<Uint8List> read(String characteristic) async {
    if (_protocol.notice == null || characteristic != _protocol.tx) {
      throw StateError('Unsupported TCP read');
    }
    return _inbox.isEmpty ? Uint8List(0) : _inbox.removeFirst();
  }

  @override
  Future<void> write(String characteristic, List<int> bytes) {
    if (characteristic != _protocol.rx ||
        bytes.isEmpty ||
        bytes.length > _protocol.maxPayload) {
      throw const FormatException('Invalid companion frame');
    }
    final prefix = _protocol.outputPrefix;
    final header = prefix.length + 2;
    final frame = Uint8List(header + bytes.length)
      ..setAll(0, prefix)
      ..setAll(header, bytes);
    ByteData.sublistView(frame)
        .setUint16(prefix.length, bytes.length, _protocol.endian);
    final write = _writes.then((_) async {
      if (_closed) throw StateError('TCP connection closed');
      _socket.add(frame);
      await _socket.flush();
    });
    _writes = write.then<void>((_) {}, onError: (Object _) => _finish());
    return write;
  }

  @override
  Stream<void> get disconnected => _ended.stream;

  void _finish([Object? _]) {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    _socket.destroy();
    _ended.add(null);
    unawaited(_ended.close());
    unawaited(_frames.close());
    unawaited(_notices.close());
  }

  @override
  Future<void> close() async {
    _finish();
    await _listening.cancel();
  }
}

class _LanSubscription implements StreamSubscriptionHandle {
  const _LanSubscription(this.subscription);
  final StreamSubscription<Uint8List> subscription;

  @override
  Future<void> cancel() => subscription.cancel();
}
