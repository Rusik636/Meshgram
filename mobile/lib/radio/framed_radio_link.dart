// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../mesh/network.dart';

/// Adapts a framed stream (TCP or serial) to the radio session interface.
class FramedRadioLink implements RadioLink {
  FramedRadioLink(
    this._protocol,
    Stream<Uint8List> input,
    this._writeBytes,
    this._closeTransport,
  ) {
    _listening = input.listen(_receive, onError: _finish, onDone: _finish);
    if (_protocol.wake.isNotEmpty) {
      unawaited(_send(_protocol.wake).catchError((Object _) {}));
    }
    if (_protocol.heartbeat.isNotEmpty) {
      _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(
          write(_protocol.rx, _protocol.heartbeat).catchError((Object _) {}),
        );
      });
    }
  }

  final LanRadioProtocol _protocol;
  final Future<void> Function(List<int>) _writeBytes;
  final void Function() _closeTransport;
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
      return _FrameSubscription(_notices.stream.listen(onFrame));
    }
    if (characteristic == _protocol.tx && _protocol.notice == null) {
      return _FrameSubscription(_frames.stream.listen(onFrame));
    }
    throw StateError('Unsupported companion subscription');
  }

  @override
  Future<Uint8List> read(String characteristic) async {
    if (_protocol.notice == null || characteristic != _protocol.tx) {
      throw StateError('Unsupported companion read');
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
    return _send(frame);
  }

  Future<void> _send(List<int> frame) {
    final write = _writes.then((_) async {
      if (_closed) throw StateError('Companion connection closed');
      await _writeBytes(frame);
    });
    _writes = write.then<void>((_) {}, onError: (Object _) => _finish());
    return write;
  }

  @override
  Stream<void> get disconnected => _closed ? Stream.value(null) : _ended.stream;

  bool get isClosed => _closed;

  void _finish([Object? _]) {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    _closeTransport();
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

class _FrameSubscription implements StreamSubscriptionHandle {
  const _FrameSubscription(this.subscription);
  final StreamSubscription<Uint8List> subscription;

  @override
  Future<void> cancel() => subscription.cancel();
}
