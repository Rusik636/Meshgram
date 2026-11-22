import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/network.dart';
import 'package:meshgrame/radio/lan_transport.dart';
import 'package:meshgrame/radio/meshcore.dart';
import 'package:meshgrame/radio/meshtastic.dart';

void main() {
  test('Saved TCP endpoints survive round trips and validate the address', () {
    final radio = lanRadio('meshcore', ' [::1] ', 5000);
    expect(lanEndpoint(radio), (host: '::1', port: 5000));
    expect(lanEndpoint(lanRadio('meshtastic', 'Radio.local', 4403)), (
      host: 'radio.local',
      port: 4403,
    ));
    expect(
      () => lanRadio('meshcore', 'a.local/x', 5000),
      throwsFormatException,
    );
    expect(
      () => lanRadio('meshcore', '::not-an-ip', 5000),
      throwsFormatException,
    );
    expect(() => lanRadio('meshcore', 'radio.local', 0), throwsFormatException);
  });

  for (final (name, protocol, outgoing, incoming) in [
    (
      'MeshCore',
      const MeshCoreAdapter().lan,
      [0x3c, 1, 0, 22],
      [0x3e, 1, 0, 13],
    ),
    (
      'Meshtastic',
      const MeshtasticAdapter().lan,
      [0x94, 0xc3, 0, 1, 22],
      [0x94, 0xc3, 0, 1, 13],
    ),
  ]) {
    test(
      '$name carries fragmented and batched radio frames over TCP',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        final accepted = server.first;
        final link = await LanTransport().connect((
          host: server.address.address,
          port: server.port,
        ), protocol);
        addTearDown(link.close);
        final peer = await accepted;
        addTearDown(peer.destroy);
        final wire = <int>[...protocol.wake, ...outgoing];
        final written = Completer<List<int>>();
        final bytes = <int>[];
        peer.listen((chunk) {
          bytes.addAll(chunk);
          if (bytes.length >= wire.length && !written.isCompleted) {
            written.complete(bytes);
          }
        });
        final frames = <Uint8List>[];
        final received = Completer<void>();
        final listener = await link.subscribe(protocol.notice ?? protocol.tx, (
          frame,
        ) async {
          frames.add(
            protocol.notice == null ? frame : await link.read(protocol.tx),
          );
          if (frames.length == 2) received.complete();
        });
        addTearDown(listener.cancel);
        await link.write(protocol.rx, [22]);
        expect(await written.future.timeout(const Duration(seconds: 2)), wire);

        peer.add([7, 2, ...incoming.take(1)]);
        await peer.flush();
        peer.add([
          ...incoming.skip(1),
          ...incoming.take(incoming.length - 1),
          5,
        ]);
        await peer.flush();
        await received.future.timeout(const Duration(seconds: 2));
        expect(frames, [
          [13],
          [5],
        ]);
        if (Platform.isMacOS) {
          final latency = await (link as RadioLatencyLink).readLinkLatency();
          expect(latency, isNotNull);
          expect(latency!.inMilliseconds, greaterThan(0));
        }
        final disconnected = link.disconnected.first;
        peer.destroy();
        await disconnected.timeout(const Duration(seconds: 2));
      },
    );
  }
}
