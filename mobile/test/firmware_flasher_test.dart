// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/network.dart';
import 'package:meshgrame/radio/desktop_usb.dart';
import 'package:meshgrame/radio/firmware_catalog.dart';
import 'package:meshgrame/radio/firmware_flasher.dart';
import 'package:meshgrame/ui/firmware_page.dart';

const target = FirmwareTarget(
  project: 'MeshCore',
  repository: 'meshcore-dev/MeshCore',
  role: 'Companion USB',
  chip: FirmwareChip.nrf52840,
  releasePrefix: 'companion-v',
  pattern: r'RAK_4631_companion_radio_usb.*\.uf2',
);

Uint8List uf2(int family) {
  final data = ByteData(512);
  void word(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  word(0, 0x0a324655);
  word(4, 0x9e5d5157);
  word(8, 0x2000);
  word(16, 256);
  word(24, 1);
  word(28, family);
  word(508, 0x0ab16f30);
  return data.buffer.asUint8List();
}

class _TestUsb extends DesktopUsbTransport {
  @override
  List<UsbPort> ports() => [(path: 'COM9', name: 'Test board')];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'catalog provides artwork and searchable targets for both networks',
    () async {
      final catalog = await FirmwareCatalog.read(rootBundle);
      expect(catalog.boards['meshtastic']!.length, greaterThan(50));
      final board = catalog.boards['meshcore']!.singleWhere(
        (board) => board.matches('Heltec V3'),
      );
      expect(
        board.targets.any((target) => target.role == 'Companion USB'),
        isTrue,
      );
      expect(
        (await rootBundle.load('assets/boards/${board.artwork}.webp'))
            .lengthInBytes,
        greaterThan(1),
      );
    },
  );

  test('firmware resolves only a unique stable image for the requested role and board', () {
    const image = 'RAK_4631_companion_radio_usb-v1.18.0-81dbae5.uf2';
    Map<String, dynamic> release(
      String tag,
      List<String> names, {
      bool prerelease = false,
    }) => {
      'tag_name': tag,
      'prerelease': prerelease,
      'assets': [
        for (final name in names)
          {
            'name': name,
            'size': 512,
            'browser_download_url':
                'https://github.com/meshcore-dev/MeshCore/releases/download/$tag/$name',
          },
      ],
    };
    final result = selectFirmwareAsset(target, [
      release('companion-v1.20.0', [image], prerelease: true),
      release('room-server-v1.20.0', [image]),
      release('companion-v1.19.0', [image, image]),
      release('companion-v1.18.1', [
        'RAK_4631_companion_radio_ble-v1.18.1.uf2',
      ]),
      release('companion-v1.18.0', [image]),
    ]);
    expect(result?.version, 'companion-v1.18.0');
    expect(result?.name, image);
  });

  test('rejects an image from a different chip', () {
    final esp = ByteData(60)
      ..setUint8(0, 0xe9)
      ..setUint16(12, 9, Endian.little);
    validateFirmwareImage(esp.buffer.asUint8List(), FirmwareChip.esp32s3);
    expect(
      () =>
          validateFirmwareImage(esp.buffer.asUint8List(), FirmwareChip.esp32c3),
      throwsFormatException,
    );
    validateFirmwareImage(uf2(0xada52840), FirmwareChip.nrf52840);
    expect(
      () => validateFirmwareImage(uf2(0xe48bff56), FirmwareChip.nrf52840),
      throwsFormatException,
    );
  });

  test(
    'UF2 is only written to a bootloader folder and is never overwritten',
    () async {
      final temp = await Directory.systemTemp.createTemp('meshgram-uf2-test-');
      addTearDown(() => temp.delete(recursive: true));
      final volume = await Directory.fromUri(temp.uri.resolve('volume/'))
          .create();
      final model = File.fromUri(temp.uri.resolve('firmware.uf2'));
      final bytes = uf2(0xada52840);
      await model.writeAsBytes(bytes);
      final prepared = PreparedFirmware(
        file: model,
        name: 'firmware.uf2',
        version: '',
        target: target,
        temporary: temp,
      );
      await expectLater(
        FirmwareFlasher.flashUf2(prepared, volume),
        throwsFormatException,
      );
      await File.fromUri(volume.uri.resolve('INFO_UF2.TXT'))
          .writeAsString('UF2 Bootloader\nBoard-ID: Test\n');
      await FirmwareFlasher.flashUf2(prepared, volume);
      final copied = await File.fromUri(volume.uri.resolve('MESHGRAM.UF2'))
          .readAsBytes();
      expect(copied, bytes);
      await expectLater(
        FirmwareFlasher.flashUf2(prepared, volume),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'desktop catalogue can search MeshCore and open the pictured board',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: FirmwarePage(usb: _TestUsb())));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 75));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('MeshCore'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Heltec V3');
      await tester.pumpAndSettle();
      final board = find.descendant(
        of: find.byType(Card),
        matching: find.text('Heltec V3'),
      );
      expect(board, findsOneWidget);
      await tester.tap(board);
      await tester.pumpAndSettle();
      expect(find.text('Download official'), findsOneWidget);
      expect(find.text('Choose file'), findsOneWidget);
    },
  );
}
