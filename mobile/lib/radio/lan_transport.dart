// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data' show Endian;

import 'package:flutter/services.dart';
import 'package:nsd/nsd.dart' as nsd;

import '../mesh/network.dart';
import 'framed_radio_link.dart';

class LanTransport implements RadioLanTransport {
  final _discoveries = <String, nsd.Discovery>{};
  Completer<void>? _scan;
  int _generation = 0;

  @override
  Future<void> scan(
    Map<String, LanRadioProtocol> protocols,
    void Function(List<DiscoveredRadio>) update,
  ) async {
    // The mDNS plugin has no Linux implementation. Direct TCP still works.
    if (Platform.isLinux) return;
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

class _TcpRadioLink extends FramedRadioLink
    implements RadioSignalLink, RadioLatencyLink {
  static const _wifi = MethodChannel('meshgrame/wifi_signal');

  @override
  Future<int?> readSignalRssi() async =>
      Platform.isAndroid ? _wifi.invokeMethod<int>('readRssi') : null;

  @override
  Future<Duration?> readLinkLatency() async {
    if (isClosed || !(Platform.isIOS || Platform.isMacOS)) return null;
    // Darwin's public tcp_connection_info struct has tcpi_srtt at byte 44.
    const connectionInfo = 0x106; // TCP_CONNECTION_INFO in <netinet/tcp.h>.
    final info = _socket.getRawOption(
      RawSocketOption(RawSocketOption.levelTcp, connectionInfo, Uint8List(112)),
    );
    final smoothedRtt = ByteData.sublistView(info).getUint32(44, Endian.host);
    return smoothedRtt > 0 ? Duration(milliseconds: smoothedRtt) : null;
  }

  _TcpRadioLink(this._socket, LanRadioProtocol protocol)
    : super(protocol, _socket, (bytes) async {
        _socket.add(bytes);
        await _socket.flush();
      }, _socket.destroy) {
    unawaited(_socket.done.then<void>((_) {}, onError: (Object _) => close()));
  }

  final Socket _socket;
}
