// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, defaultTargetPlatform;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/network.dart';
import 'package:meshgrame/radio/desktop_usb.dart';
import 'package:meshgrame/radio/firmware_catalog.dart';
import 'package:meshgrame/radio/firmware_flasher.dart';
import 'package:meshgrame/ui/firmware_filters.dart';
import 'package:meshgrame/ui/firmware_page.dart';
import 'package:meshgrame/ui/macos_glass.dart';

class _CatalogAssets extends CachingAssetBundle {
  _CatalogAssets(this.catalog);
  final Map<String, String> catalog;

  @override
  Future<ByteData> load(String key) => rootBundle.load(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    if (catalog[key] case final value?) return Future.value(value);
    return rootBundle.loadString(key, cache: cache);
  }
}

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

class _ReleaseHttp extends HttpOverrides {
  _ReleaseHttp(this.port);
  final int port;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _ReleaseHttpClient(super.createHttpClient(context), port);
}

class _ReleaseHttpClient extends Fake implements HttpClient {
  _ReleaseHttpClient(this.client, this.port);
  final HttpClient client;
  final int port;

  @override
  set connectionTimeout(Duration? value) => client.connectionTimeout = value;

  @override
  set maxConnectionsPerHost(int? value) => client.maxConnectionsPerHost = value;

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      client.getUrl(url.replace(scheme: 'http', host: '127.0.0.1', port: port));

  @override
  void close({bool force = false}) => client.close(force: force);
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

  test(
    'firmware versions use public release pages when the API is limited',
    () async {
      const repository = '/meshcore-dev/MeshCore/releases';
      const tag = 'companion-v1.18.0';
      const asset = 'RAK_4631_companion_radio_usb-v1.18.0.uf2';
      final digest = 'sha256:${List.filled(64, 'a').join()}';
      final requests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final response = request.response;
        final path = request.uri.path;
        requests.add(path);
        switch (path) {
          case '/repos$repository':
            response.statusCode = HttpStatus.forbidden;
            response.headers.set('x-ratelimit-remaining', '0');
          case repository:
            response.write('''
            <section><span class="Label--warning">Pre-release</span>
              <include-fragment src="$repository/expanded_assets/$tag"></include-fragment>
            </section>
            <section><include-fragment src="$repository/expanded_assets/repeater-v1.18.0"></include-fragment></section>
          ''');
          case '$repository/expanded_assets/$tag':
            response.write('''
            <ul><li><a href="$repository/download/$tag/$asset">$asset</a>
              <clipboard-copy value="$digest"></clipboard-copy>
            </li></ul>
          ''');
          default:
            response.statusCode = HttpStatus.notFound;
        }
        await response.close();
      });

      await HttpOverrides.runWithHttpOverrides(() async {
        final tool = FirmwareFlasher(_TestUsb());
        final versions = await tool.versions(target);
        expect(versions.single.version, tag);
        expect(versions.single.prerelease, isTrue);
        expect(versions.single.factory.digest, digest);
        expect(
          versions.single.factory.url.toString(),
          'https://github.com$repository/download/$tag/$asset',
        );
        expect(versions.single.update, versions.single.factory);
        await tool.versions(target);
      }, _ReleaseHttp(server.port));
      expect(requests, [
        '/repos$repository',
        repository,
        '$repository/expanded_assets/$tag',
      ]);
    },
  );

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
    'desktop catalogue combines filters and opens the pictured board',
    (tester) async {
      final mac = defaultTargetPlatform == TargetPlatform.macOS;
      if (mac) {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          MacGlass.channel,
          (_) async => {'glass': true},
        );
        messenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          (_) async => null,
        );
        await MacGlass.initialize();
        addTearDown(() async {
          messenger.setMockMethodCallHandler(MacGlass.channel, null);
          messenger.setMockMethodCallHandler(
            SystemChannels.platform_views,
            null,
          );
          final platform = debugDefaultTargetPlatformOverride;
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            await MacGlass.initialize();
          } finally {
            debugDefaultTargetPlatformOverride = platform;
          }
        });
      }
      final assets = await tester.runAsync(
        () async => _CatalogAssets({
          for (final key in [
            'assets/boards/catalog.json',
            'assets/boards/firmware.json',
          ])
            key: await rootBundle.loadString(key),
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultAssetBundle(
            bundle: assets!,
            child: FirmwarePage(usb: _TestUsb()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byType(TextField);
      final modifier = mac
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      await tester.enterText(search, 'Heltec V3 MeshCore ESP32-S3');
      await tester.pumpAndSettle();
      final filterButton = find.text('Filters');
      final filterControl = find.byKey(
        const ValueKey('firmware-filter-control'),
      );
      final toolbarY = tester.getCenter(filterButton).dy;
      final collapsedSize = tester.getSize(filterControl);
      final anchor = tester.getTopLeft(filterControl);
      final glass = find.descendant(
        of: filterControl,
        matching: find.byType(AppKitView),
      );
      final glassClip = find.descendant(
        of: filterControl,
        matching: find.byWidgetPredicate(
          (widget) => widget is ClipRRect && widget.clipper != null,
        ),
      );
      final glassElement = mac ? tester.element(glass) : null;
      if (mac) {
        final base = tester.getRect(glass);
        expect(
          base,
          tester.getRect(filterControl).inflate(MacGlass.controlEdgeOutset),
        );
        expect(tester.widget<ClipRRect>(glassClip).clipBehavior, Clip.none);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        final away = base.center + const Offset(0, 100);
        await mouse.addPointer(location: away);
        await mouse.moveTo(base.center);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(glass).width,
          closeTo(
            collapsedSize.width * 1.04 + 2 * MacGlass.controlEdgeOutset,
            .1,
          ),
        );
        await mouse.moveTo(away);
        await tester.pumpAndSettle();
        expect(tester.getRect(glass), base);
        await mouse.removePointer();
      }
      final board = find.descendant(
        of: find.byType(Card),
        matching: find.text('Heltec V3'),
      );
      final boardPosition = tester.getTopLeft(board);
      await tester.tap(filterButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(
        tester.getSize(filterControl).width,
        greaterThan(collapsedSize.width),
      );
      expect(tester.getTopLeft(filterControl), anchor);
      expect(tester.getTopLeft(board), boardPosition);
      await tester.pumpAndSettle();
      expect(filterButton, findsNothing);
      final expandedSize = tester.getSize(filterControl);
      expect(expandedSize.height, greaterThan(collapsedSize.height));
      expect(tester.getTopLeft(filterControl), anchor);
      if (mac) {
        final clip = tester.widget<ClipRRect>(glassClip);
        expect(clip.clipBehavior, Clip.antiAlias);
        expect(
          clip.clipper!.getClip(expandedSize).outerRect,
          (Offset.zero & expandedSize).inflate(MacGlass.controlEdgeOutset),
        );
        expect(tester.element(glass), same(glassElement));
      }
      expect(tester.getTopLeft(board), boardPosition);
      await tester.tap(find.text('Boards: 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(
        tester.getSize(filterControl).height,
        lessThan(expandedSize.height),
      );
      expect(tester.getTopLeft(filterControl), anchor);
      await tester.pumpAndSettle();
      expect(tester.getSize(filterControl), collapsedSize);
      expect(tester.getTopLeft(board), boardPosition);
      await tester.tap(filterButton);
      await tester.pumpAndSettle();
      Finder option(String value) => find.descendant(
        of: find.byType(FirmwareFilterPanel),
        matching: find.text(value),
      );
      await tester.tap(option('Heltec'));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byType(FirmwareFilterTag)).dy,
        closeTo(toolbarY, 1),
      );
      expect(
        find.descendant(
          of: find.byType(FirmwareFilterTag),
          matching: find.byIcon(Icons.close_rounded),
        ),
        findsOneWidget,
      );
      await tester.tap(option('Chip'));
      await tester.pumpAndSettle();
      await tester.tap(option('nRF52840'));
      await tester.pumpAndSettle();
      expect(find.text('No boards found'), findsOneWidget);
      await tester.tap(option('ESP32-S3'));
      await tester.pumpAndSettle();
      expect(find.text('Boards: 1'), findsOneWidget);
      await tester.tap(option('Protocol'));
      await tester.pumpAndSettle();
      await tester.tap(option('MeshCore'));
      await tester.pumpAndSettle();
      expect(find.byType(FirmwareFilterTag), findsNWidgets(4));
      final selectedChip = find.descendant(
        of: find.byType(FirmwareFilterTag),
        matching: find.text('nRF52840'),
      );
      await tester.tap(find.text('Boards: 1'));
      await tester.pumpAndSettle();
      await tester.tap(selectedChip);
      await tester.pumpAndSettle();
      expect(find.byType(FirmwareFilterTag), findsNWidgets(3));
      expect(filterButton, findsOneWidget);
      await tester.tap(filterButton);
      await tester.pumpAndSettle();
      await tester.tap(option('Chip'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(
              find.ancestor(
                of: option('nRF52840'),
                matching: find.byType(FilterChip),
              ),
            )
            .selected,
        isFalse,
      );
      final filteredBoardPosition = tester.getTopLeft(board);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(board), filteredBoardPosition);
      expect(board, findsOneWidget);
      expect(find.text('ESP32-S3 · MeshCore'), findsOneWidget);
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
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
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
