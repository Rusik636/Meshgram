// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:libserialport_plus/libserialport_plus.dart';

import '../mesh/network.dart';
import 'framed_radio_link.dart';

class DesktopUsbTransport implements RadioUsbTransport {
  static bool get supported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  final _leased = <String>{};

  @override
  List<UsbPort> ports() {
    if (!supported) return const [];
    final result = <UsbPort>[];
    for (final path in SerialPort.getAvailablePorts()) {
      SerialPort? port;
      try {
        port = SerialPort(path);
        final info = port.getInfo();
        if (info.transport == SerialPortTransport.usb ||
            path.startsWith('/dev/ttyACM') ||
            path.startsWith('/dev/ttyUSB') ||
            path.startsWith('/dev/cu.usb') ||
            path.startsWith('/dev/cu.SLAB_USB')) {
          final name = info.usbProduct ?? info.description;
          result.add((path: path, name: name.trim().isNotEmpty ? name : path));
        }
      } on SerialPortException {
        // A device may disappear between listing ports and reading metadata.
        continue;
      } finally {
        port?.dispose();
      }
    }
    return result..sort((a, b) => a.path.compareTo(b.path));
  }

  void _reserve(String path) {
    if (!ports().any((port) => port.path == path)) {
      throw StateError('USB port is unavailable: $path');
    }
    if (!_leased.add(path)) throw StateError('USB port is in use: $path');
  }

  /// The radio and the flasher must never write to the same port concurrently.
  Future<T> withReservedPort<T>(
    String path,
    Future<T> Function() action,
  ) async {
    _reserve(path);
    try {
      return await action();
    } finally {
      _leased.remove(path);
    }
  }

  @override
  Future<RadioLink> connect(String path, UsbRadioProtocol protocol) async {
    _reserve(path);
    SerialPort? port;
    var opened = false;
    try {
      port = SerialPort(path);
      port.open();
      opened = true;
      port.setConfig(
        SerialPortConfig(
          baudRate: protocol.baudRate,
          bits: 8,
          parity: SerialPortParity.none,
          stopBits: 1,
          rts: SerialPortRts.off,
          cts: SerialPortCts.ignore,
          dsr: SerialPortDsr.ignore,
          xonXoff: SerialPortXonXoff.disabled,
        ),
      );
      final io = _SerialPortStream(port, path, () => _leased.remove(path));
      return FramedRadioLink(protocol.framing, io.input, io.write, io.close);
    } catch (_) {
      try {
        if (opened) port!.close();
      } on SerialPortException {
        // Preserve the connection error if the device was unplugged.
      } finally {
        port?.dispose();
        _leased.remove(path);
      }
      rethrow;
    }
  }
}

class _SerialPortStream {
  _SerialPortStream(this.port, this.path, this.release) {
    _poll = Timer.periodic(const Duration(milliseconds: 20), (_) => _read());
    _presence = Timer.periodic(const Duration(seconds: 2), (_) {
      try {
        if (!SerialPort.getAvailablePorts().contains(path)) close();
      } on SerialPortException {
        close();
      }
    });
  }

  final SerialPort port;
  final String path;
  final void Function() release;
  final _input = StreamController<Uint8List>();
  late final Timer _poll, _presence;
  bool _closed = false;
  Stream<Uint8List> get input => _input.stream;

  void _read() {
    try {
      final bytes = port.read(4096, timeout: -1);
      if (bytes.isNotEmpty) _input.add(bytes);
    } on SerialPortException {
      close();
    }
  }

  Future<void> write(List<int> bytes) async {
    final data = Uint8List.fromList(bytes);
    final elapsed = Stopwatch()..start();
    var offset = 0;
    while (offset < data.length) {
      if (_closed) throw StateError('USB port was disconnected');
      final count = port.write(
        Uint8List.sublistView(data, offset),
        timeout: -1,
      );
      offset += count;
      if (offset == data.length) return;
      if (elapsed.elapsed >= const Duration(seconds: 3)) {
        throw TimeoutException('USB write timed out');
      }
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _poll.cancel();
    _presence.cancel();
    try {
      port.close();
    } on SerialPortException {
      // An unplugged serial port can fail to close.
    } finally {
      port.dispose();
      release();
      unawaited(_input.close());
    }
  }
}
