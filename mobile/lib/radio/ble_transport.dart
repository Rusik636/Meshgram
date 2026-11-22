// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../mesh/network.dart';

class BleTransport implements RadioTransport, BluetoothControl {
  static const _android = MethodChannel('meshgrame/android');
  StreamSubscription<List<ScanResult>>? _results;
  int _scanGeneration = 0;
  bool _ownsScan = false;

  static Future<void> enableStateRestoration() async {
    if (Platform.isIOS) {
      await FlutterBluePlus.setOptions(restoreState: true);
    }
  }

  @override
  Future<void> scan(
    Map<String, String> services,
    void Function(List<DiscoveredRadio>) update,
  ) async {
    await stopScan();
    final generation = ++_scanGeneration;
    await _requireAdapter(scanning: true);
    if (generation != _scanGeneration) return;
    final discovered = <String, DiscoveredRadio>{};
    final lookup = {
      for (final entry in services.entries) Guid(entry.key): entry.value,
    };
    _results = FlutterBluePlus.onScanResults.listen((results) {
      if (generation != _scanGeneration) return;
      for (final result in results) {
        for (final uuid in result.advertisementData.serviceUuids) {
          final kind = lookup[uuid];
          if (kind == null) continue;
          final radio = (
            network: kind,
            device: result.device.remoteId.str,
            name: result.advertisementData.advName.isNotEmpty
                ? result.advertisementData.advName
                : result.device.platformName.isNotEmpty
                ? result.device.platformName
                : kind,
          );
          discovered[radioKey(radio)] = (radio: radio, rssi: result.rssi);
        }
      }
      update(discovered.values.toList());
    });
    _ownsScan = true;
    try {
      await FlutterBluePlus.startScan(
        withServices: lookup.keys.toList(),
        continuousUpdates: true,
        androidCheckLocationServices: false,
        timeout: const Duration(seconds: 8),
      );
      await FlutterBluePlus.isScanning
          .where((active) => !active)
          .first
          .timeout(const Duration(seconds: 12));
    } on FlutterBluePlusException catch (error) {
      throw _bluetoothProblem(error) ?? error;
    } finally {
      if (generation == _scanGeneration) await stopScan();
    }
  }

  @override
  Future<void> stopScan() async {
    ++_scanGeneration;
    final results = _results;
    _results = null;
    final stop = _ownsScan;
    _ownsScan = false;
    await results?.cancel();
    if (stop && FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
  }

  Future<void> _requireAdapter({bool scanning = false}) async {
    if (Platform.isAndroid) {
      final problem = await _android.invokeMethod<String>(
        'bluetoothProblem',
        scanning,
      );
      if (problem != null) throw BluetoothProblem.values.byName(problem);
      return;
    }
    final state = await FlutterBluePlus.adapterState
        .where(
          (state) =>
              state != BluetoothAdapterState.unknown &&
              state != BluetoothAdapterState.turningOn,
        )
        .first
        .timeout(const Duration(seconds: 5));
    switch (state) {
      case BluetoothAdapterState.on:
        return;
      case BluetoothAdapterState.unauthorized:
        throw BluetoothProblem.permission;
      case BluetoothAdapterState.unavailable:
        throw BluetoothProblem.unsupported;
      default:
        throw BluetoothProblem.off;
    }
  }

  BluetoothProblem? _bluetoothProblem(FlutterBluePlusException error) {
    final description = error.description?.toLowerCase() ?? '';
    if (description.contains('permission')) return BluetoothProblem.permission;
    if (description.contains('location services')) {
      return BluetoothProblem.location;
    }
    if (description.contains('bluetooth must be turned on') ||
        (error.platform == ErrorPlatform.fbp &&
            error.code == FbpErrorCode.adapterIsOff.index)) {
      return BluetoothProblem.off;
    }
    if (error.function == 'createBond') return BluetoothProblem.pairing;
    return null;
  }

  @override
  Future<void> enableBluetooth() async {
    if (!Platform.isAndroid) throw BluetoothProblem.off;
    try {
      await FlutterBluePlus.turnOn();
    } on FlutterBluePlusException catch (error) {
      throw _bluetoothProblem(error) ?? BluetoothProblem.off;
    }
  }

  @override
  Future<RadioLink> connect(Radio radio, String service) {
    // Discovery is shared by the Bluetooth adapter, but established links are independent.
    final result = _pendingConnect.then((_) => _connect(radio, service));
    _pendingConnect = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _pendingConnect = Future.value();

  Future<RadioLink> _connect(Radio radio, String service) async {
    await stopScan();
    await _requireAdapter();
    var device = BluetoothDevice.fromId(radio.device);
    try {
      try {
        await _connectDevice(device);
      } on FlutterBluePlusException catch (error) {
        if (_bluetoothProblem(error) case final problem?) throw problem;
        await _requireAdapter(scanning: true);
        device = await _rediscover(radio.device, Guid(service));
        await _connectDevice(device);
      }
      final uuid = Guid(service);
      final characteristics = await _discoverCharacteristics(device, uuid);
      if (Platform.isAndroid && radio.network == 'meshcore') {
        // MeshCore protects UART writes. Let Android complete PIN pairing
        // before the companion protocol starts its own request timeouts.
        await device.createBond(timeout: 60);
      }
      return _BleLink(device, uuid, characteristics);
    } catch (error) {
      try {
        await device.disconnect();
      } catch (_) {}
      if (error is FlutterBluePlusException) {
        if (_bluetoothProblem(error) case final problem?) throw problem;
      }
      rethrow;
    }
  }

  Future<void> _connectDevice(BluetoothDevice device) => device.connect(
    license: License.nonprofit,
    timeout: const Duration(seconds: 12),
    mtu: 247,
  );

  Future<BluetoothDevice> _rediscover(String id, Guid service) async {
    final known = await FlutterBluePlus.systemDevices([service]);
    final connected = known
        .where(
          (device) => device.remoteId.str.toLowerCase() == id.toLowerCase(),
        )
        .firstOrNull;
    if (connected != null) return connected;
    final found = Completer<BluetoothDevice>();
    final results = FlutterBluePlus.onScanResults.listen((batch) {
      for (final result in batch) {
        if (result.device.remoteId.str.toLowerCase() == id.toLowerCase() &&
            !found.isCompleted) {
          found.complete(result.device);
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withRemoteIds: [id],
        androidCheckLocationServices: false,
        timeout: const Duration(seconds: 6),
      );
      return await found.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => throw const RadioNotNearby(),
      );
    } finally {
      await results.cancel();
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    }
  }
}

Future<Map<Guid, BluetoothCharacteristic>> _discoverCharacteristics(
  BluetoothDevice device,
  Guid service, {
  bool refreshIfMissing = true,
}) async {
  // Android can expose Service Changed even when the GATT server rejects its CCCD.
  Future<List<BluetoothService>> discover() =>
      device.discoverServices(subscribeToServicesChanged: !Platform.isAndroid);
  BluetoothService? findService(List<BluetoothService> services) => services
      .where((item) => item.uuid == service && item.characteristics.isNotEmpty)
      .firstOrNull;

  var services = await discover();
  var target = findService(services);
  if (target == null &&
      Platform.isAndroid &&
      refreshIfMissing &&
      device.isConnected) {
    await device.clearGattCache();
    services = await discover();
    target = findService(services);
  }
  if (target == null) {
    final found = services.map((item) => item.uuid).join(', ');
    throw StateError('BLE service $service unavailable (found: $found)');
  }
  return {for (final item in target.characteristics) item.uuid: item};
}

class _BleSubscription implements StreamSubscriptionHandle {
  _BleSubscription(this.value);
  final StreamSubscription<List<int>> value;
  @override
  Future<void> cancel() => value.cancel();
}

class _BleLink implements RadioLink, RadioSignalLink {
  _BleLink(this.device, this.service, this.characteristics);
  final BluetoothDevice device;
  final Guid service;
  Map<Guid, BluetoothCharacteristic> characteristics;
  bool _rediscovered = false;
  Future<void>? _closed;

  BluetoothCharacteristic _find(String id) =>
      characteristics[Guid(id)] ??
      (throw StateError('Missing BLE characteristic'));

  @override
  bool contains(String characteristic) =>
      characteristics.containsKey(Guid(characteristic));

  @override
  Future<StreamSubscriptionHandle> subscribe(
    String characteristic,
    void Function(Uint8List) onFrame,
  ) async {
    try {
      return await _subscribe(characteristic, onFrame);
    } on FlutterBluePlusException catch (error) {
      if (!Platform.isAndroid ||
          _rediscovered ||
          error.platform != ErrorPlatform.android ||
          error.code != 1 ||
          !device.isConnected) {
        rethrow;
      }
      _rediscovered = true;
      await device.clearGattCache();
      characteristics = await _discoverCharacteristics(
        device,
        service,
        refreshIfMissing: false,
      );
      return _subscribe(characteristic, onFrame);
    }
  }

  Future<StreamSubscriptionHandle> _subscribe(
    String characteristic,
    void Function(Uint8List) onFrame,
  ) async {
    final target = _find(characteristic);
    final sub = target.onValueReceived.listen(
      (data) => onFrame(Uint8List.fromList(data)),
    );
    try {
      await target.setNotifyValue(true);
      return _BleSubscription(sub);
    } catch (_) {
      await sub.cancel();
      rethrow;
    }
  }

  @override
  Stream<void> get disconnected => device.connectionState
      .where((event) => event == BluetoothConnectionState.disconnected)
      .map<void>((_) {});

  @override
  Future<Uint8List> read(String characteristic) async =>
      Uint8List.fromList(await _find(characteristic).read(timeout: 10));

  @override
  Future<void> write(String characteristic, List<int> bytes) {
    final target = _find(characteristic);
    return target.write(
      bytes,
      withoutResponse:
          !target.properties.write && target.properties.writeWithoutResponse,
    );
  }

  @override
  Future<int> readSignalRssi() => device.readRssi(timeout: 3);

  @override
  Future<void> close() => _closed ??= device.disconnect();
}
