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
  eraser: 'FLASH_ERASE_nrf52_softdevice_v6.uf2',
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
      expect(catalog.boards.length, greaterThan(50));
      final board = catalog.boards.singleWhere(
        (board) => board.name == 'Heltec V3',
      );
      expect(board.manufacturer, 'Heltec');
      expect(board.matches('heltec v3'), isTrue);
      expect(board.protocols, containsAll(['Meshtastic', 'MeshCore']));
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

  test('update selects the application asset from the same release', () {
    const target = FirmwareTarget(
      project: 'MeshCore',
      repository: 'meshcore-dev/MeshCore',
      role: 'Companion USB',
      chip: FirmwareChip.esp32s3,
      releasePrefix: 'companion-v',
      pattern: r'Heltec_v3_companion_radio_usb.*-merged\.bin',
    );
    const tag = 'companion-v1.18.0';
    const stem = 'Heltec_v3_companion_radio_usb-v1.18.0';
    final releases = firmwareReleases(target, [
      {
        'tag_name': tag,
        'assets': [
          for (final name in [
            '$stem-merged.bin',
            '$stem.bin',
            '$stem-bootloader.bin',
          ])
            {
              'name': name,
              'size': 512,
              'browser_download_url':
                  'https://github.com/meshcore-dev/MeshCore/releases/download/$tag/$name',
            },
        ],
      },
    ]);
    expect(releases.single.factory.name, '$stem-merged.bin');
    expect(releases.single.update?.name, '$stem.bin');
  });

  test(
    'bundled UF2 erase images match the chip for every supported target',
    () async {
      final catalog = await FirmwareCatalog.read(rootBundle);
      final erasers = {
        for (final board in catalog.boards)
          for (final target in board.targets) ?target.eraser: target.chip,
      };
      expect(erasers.length, 7);
      for (final MapEntry(key: name, value: chip) in erasers.entries) {
        final data = await rootBundle.load('assets/firmware_tools/$name');
        validateFirmwareImage(data.buffer.asUint8List(), chip);
      }
    },
  );

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
      await tester.enterText(find.byType(TextField), 'Heltec V3');
      await tester.pumpAndSettle();
      final board = find.descendant(
        of: find.byType(Card),
        matching: find.text('Heltec V3'),
      );
      expect(board, findsOneWidget);
      await tester.tap(board);
      await tester.pumpAndSettle();
      expect(find.text('Protocol'), findsOneWidget);
      await tester.tap(find.text('Meshtastic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MeshCore').last);
      await tester.pumpAndSettle();
      expect(find.text('Firmware variant'), findsOneWidget);
      expect(find.text('Firmware version'), findsOneWidget);
      expect(find.text('Download image'), findsOneWidget);
      expect(find.text('Choose file'), findsOneWidget);
    },
  );

  test(
    'clean UF2 install resumes on the same board after the erase stage',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'meshgram-clean-uf2-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final volume = await Directory.fromUri(temporary.uri.resolve('drive/'))
          .create();
      final marker = File.fromUri(volume.uri.resolve('INFO_UF2.TXT'));
      final image = await File.fromUri(temporary.uri.resolve('firmware.uf2'))
          .writeAsBytes(uf2(0xada52840));
      final prepared = PreparedFirmware(
        file: image,
        name: 'firmware.uf2',
        version: '',
        target: target,
        temporary: temporary,
        mode: FirmwareInstallMode.clean,
      );
      await marker.writeAsString('Board-ID: Test-RAK\n');
      await expectLater(
        FirmwareFlasher.flashUf2(prepared, volume),
        throwsFormatException,
      );
      final erased = await FirmwareFlasher.eraseUf2(
        prepared,
        volume,
        rootBundle,
      );
      expect(erased, 'Test-RAK');
      final written = File.fromUri(volume.uri.resolve('MESHGRAM.UF2'));
      expect(await written.length(), greaterThan(await image.length()));
      await written.delete();
      await marker.writeAsString('Board-ID: Other\n');
      await expectLater(
        FirmwareFlasher.flashUf2(prepared, volume, erasedBoard: erased),
        throwsFormatException,
      );
      expect(await written.exists(), isFalse);
      await marker.writeAsString('Board-ID: Test-RAK\n');
      await FirmwareFlasher.flashUf2(prepared, volume, erasedBoard: erased);
      expect(await written.readAsBytes(), await image.readAsBytes());
    },
  );
}
