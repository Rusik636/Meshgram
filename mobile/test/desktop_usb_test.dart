// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/network.dart';
import 'package:meshgrame/radio/framed_radio_link.dart';
import 'package:meshgrame/radio/meshcore.dart';
import 'package:meshgrame/radio/meshtastic.dart';

void main() {
  test('USB endpoints preserve Windows COM and Unix device paths', () {
    for (final port in ['COM10', '/dev/cu.usbserial-0123', '/dev/ttyACM0']) {
      final radio = usbRadio('meshcore', (path: port, name: 'Radio'));
      expect(usbPortOf(radio), port);
      expect(lanEndpoint(radio), isNull);
    }
  });

  for (final (name, usb, sent, received) in [
    (
      'MeshCore',
      const MeshCoreAdapter().usb,
      [0x3c, 1, 0, 22],
      [0x3e, 1, 0, 13],
    ),
    (
      'Meshtastic',
      const MeshtasticAdapter().usb,
      [0x94, 0xc3, 0, 1, 22],
      [0x94, 0xc3, 0, 1, 13],
    ),
  ]) {
    test('$name USB initializes and handles a fragmented response', () async {
      expect(usb.baudRate, 115200);
      final frames = StreamController<Uint8List>();
      final bytes = <int>[];
      var closed = false;
      final protocol = usb.framing;
      final link = FramedRadioLink(
        protocol,
        frames.stream,
        (frame) async => bytes.addAll(frame),
        () => closed = true,
      );
      addTearDown(link.close);

      final decoded = Completer<Uint8List>();
      await link.subscribe(protocol.notice ?? protocol.tx, (frame) async {
        decoded.complete(
          protocol.notice == null ? frame : await link.read(protocol.tx),
        );
      });
      await link.write(protocol.rx, [22]);
      expect(bytes, [...protocol.wake, ...sent]);
      frames.add(Uint8List.fromList([0xff, received.first]));
      frames.add(Uint8List.fromList(received.skip(1).toList()));
      expect(await decoded.future, [13]);

      final disconnected = link.disconnected.first;
      await frames.close();
      await disconnected;
      expect(closed, isTrue);
    });
  }
}
