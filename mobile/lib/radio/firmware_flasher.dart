// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'desktop_usb.dart';
import 'firmware_catalog.dart';

enum FirmwareInstallMode { update, clean }

typedef FirmwareAsset = ({
  String name,
  String version,
  Uri url,
  String? digest,
  int size,
});

class FirmwareRelease {
  const FirmwareRelease(this.factory, this.update, {required this.prerelease});
  final FirmwareAsset factory;
  final FirmwareAsset? update;
  final bool prerelease;
  String get version => factory.version;
}

FirmwareAsset? _asset(
  FirmwareTarget target,
  String version,
  Iterable<Map<String, dynamic>> assets,
  bool Function(String) matches,
) {
  final entry = assets
      .where((item) => matches(item['name'] as String))
      .singleOrNull;
  if (entry == null) return null;
  final url = Uri.tryParse(entry['browser_download_url'] as String? ?? '');
  final size = entry['size'] as int? ?? 0;
  if (url == null ||
      url.scheme != 'https' ||
      url.host != 'github.com' ||
      !url.path.startsWith('/${target.repository}/releases/download/') ||
      size <= 0 ||
      size > 220 * 1024 * 1024) {
    return null;
  }
  return (
    name: entry['name'] as String,
    version: version,
    url: url,
    digest: entry['digest'] as String?,
    size: size,
  );
}

List<FirmwareRelease> firmwareReleases(
  FirmwareTarget target,
  Iterable<Map<String, dynamic>> releases,
) {
  final candidates = <FirmwareRelease>[];
  for (final release in releases) {
    final version = release['tag_name'] as String?;
    if (version == null ||
        release['draft'] == true ||
        !version.startsWith(target.releasePrefix ?? 'v')) {
      continue;
    }
    final code = _versionCode(version);
    final archive = target.archive?.replaceAll('{version}', code);
    final assets = ((release['assets'] as List?) ?? [])
        .cast<Map<String, dynamic>>();
    final factory = _asset(
      target,
      version,
      assets,
      archive == null
          ? target.filePattern(code).hasMatch
          : (name) => name == archive,
    );
    if (factory == null) continue;
    final update = archive != null || target.chip.usesUf2
        ? factory
        : _asset(target, version, assets, (name) {
            return name ==
                    factory.name.replaceFirst(
                      RegExp(r'-merged\.bin$'),
                      '.bin',
                    ) &&
                name != factory.name;
          });
    candidates.add(
      FirmwareRelease(
        factory,
        update,
        prerelease: release['prerelease'] == true,
      ),
    );
  }
  return candidates;
}

FirmwareAsset? selectFirmwareAsset(
  FirmwareTarget target,
  Iterable<Map<String, dynamic>> releases,
) => firmwareReleases(
  target,
  releases,
).where((release) => !release.prerelease).firstOrNull?.factory;

String _versionCode(String version) =>
    version.startsWith('v') ? version.substring(1) : version;

typedef FlashSegment = ({File file, int address});

class PreparedFirmware {
  const PreparedFirmware({
    required this.file,
    required this.name,
    required this.version,
    required this.target,
    required this.temporary,
    this.mode = FirmwareInstallMode.update,
    this.address = 0x10000,
    this.additional = const [],
  });
  final File file;
  final String name, version;
  final FirmwareTarget target;
  final Directory temporary;
  final FirmwareInstallMode mode;
  final int address;
  final List<FlashSegment> additional;

  Future<void> dispose() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
}

class FirmwareFlasher {
  FirmwareFlasher(this.usb);
  final DesktopUsbTransport usb;
  static const _maxImage = 16 * 1024 * 1024;
  final _releases = <String, Future<List<Map<String, dynamic>>>>{};

  Future<List<FirmwareRelease>> versions(FirmwareTarget target) async {
    try {
      final releases = await _releases.putIfAbsent(
        target.repository,
        () => _loadReleases(target.repository),
      );
      return firmwareReleases(target, releases);
    } catch (_) {
      _releases.remove(target.repository);
      rethrow;
    }
  }

  Future<PreparedFirmware> download(
    FirmwareTarget target, {
    required FirmwareRelease release,
    required FirmwareInstallMode mode,
    required void Function(double progress) onProgress,
  }) async {
    final asset = mode == FirmwareInstallMode.clean
        ? release.factory
        : release.update;
    if (asset == null) throw StateError('This release has no update image');
    final directory = await _temporary();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final raw = File.fromUri(directory.uri.resolve('download'));
      final response = await _request(client, asset.url);
      var loaded = 0;
      final sink = raw.openWrite();
      try {
        await sink.addStream(
          response.timeout(const Duration(seconds: 30)).map((chunk) {
            loaded += chunk.length;
            if (loaded > asset.size) {
              throw const FormatException('Incorrect firmware download size');
            }
            onProgress(loaded / asset.size);
            return chunk;
          }),
        );
      } finally {
        await sink.close();
      }
      if (loaded != asset.size) {
        throw const FormatException('Incomplete firmware download');
      }
      if (asset.digest case final digest? when digest.startsWith('sha256:')) {
        final actual = await sha256.bind(raw.openRead()).first;
        if (actual.toString() != digest.substring(7).toLowerCase()) {
          throw const FormatException('Firmware SHA-256 verification failed');
        }
      }

      if (target.archive != null) {
        final input = raw.path;
        final result = await Isolate.run(
          () => _prepareArchive(
            input,
            directory.path,
            target,
            asset.version,
            mode,
          ),
        );
        await raw.delete();
        return result;
      }
      await _checkImage(raw, target.chip, mode);
      return PreparedFirmware(
        file: raw,
        name: asset.name,
        version: asset.version,
        target: target,
        temporary: directory,
        mode: mode,
        address: mode == FirmwareInstallMode.clean ? 0 : 0x10000,
      );
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<PreparedFirmware> local(
    FirmwareTarget target,
    File source, {
    FirmwareInstallMode mode = FirmwareInstallMode.update,
  }) async {
    final name = source.uri.pathSegments.last;
    final lower = name.toLowerCase();
    final fullImage =
        lower.endsWith('.factory.bin') || lower.endsWith('-merged.bin');
    if (target.chip.usesUf2
        ? !lower.endsWith('.uf2')
        : !lower.endsWith('.bin') ||
              fullImage != (mode == FirmwareInstallMode.clean)) {
      throw const FormatException(
        'Choose the image type for the selected installation mode',
      );
    }
    await _checkImage(source, target.chip, mode);
    final directory = await _temporary();
    try {
      final file = await source.copy(
        directory.uri.resolve('firmware.${target.chip.extension}').toFilePath(),
      );
      await _checkImage(file, target.chip, mode);
      return PreparedFirmware(
        file: file,
        name: name,
        version: '',
        target: target,
        temporary: directory,
        mode: mode,
        address: mode == FirmwareInstallMode.clean ? 0 : 0x10000,
      );
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> flashEsp(
    PreparedFirmware firmware,
    String port, {
    required void Function(String) onOutput,
  }) async {
    if (firmware.target.chip.usesUf2) {
      throw StateError('ESP firmware is required');
    }
    final executable = _bundledEsptool();
    if (!await executable.exists()) {
      throw StateError(
        'The built-in ESP flashing utility is missing from this build',
      );
    }
    await _checkImage(firmware.file, firmware.target.chip, firmware.mode);
    final segments = [
      (address: firmware.address, file: firmware.file),
      ...firmware.additional,
    ];
    await usb.withReservedPort(port, () async {
      Future<void> run(List<String> command) => _runEsptool(
        executable,
        firmware.target.chip,
        port,
        command,
        onOutput,
      );
      if (firmware.mode == FirmwareInstallMode.update) {
        final table = File.fromUri(
          firmware.temporary.uri.resolve('device-partitions.bin'),
        );
        await run([
          '--after',
          'no-reset',
          'read-flash',
          '0x8000',
          '0xc00',
          table.path,
        ]);
        final partitions = _partitions(await table.readAsBytes(), start: 0);
        for (final (index, segment) in segments.indexed) {
          final area = index == 0
              ? partitions[0x0010] ?? partitions[0x0000]
              : partitions[0x0011];
          if (area == null ||
              area.address != segment.address ||
              area.size < await segment.file.length()) {
            throw StateError(
              'This update does not fit the installed ESP partitions',
            );
          }
        }
      }
      await run([
        'write-flash',
        if (firmware.mode == FirmwareInstallMode.clean) '--erase-all',
        for (final segment in segments) ...[
          '0x${segment.address.toRadixString(16)}',
          segment.file.path,
        ],
      ]);
    });
  }

  static Future<void> _runEsptool(
    File executable,
    FirmwareChip chip,
    String port,
    List<String> command,
    void Function(String) onOutput,
  ) async {
    final process = await Process.start(executable.path, [
      '--chip',
      chip.nameForTool,
      '--port',
      port,
      ...command,
    ]);
    final (status, _, _) = await (
      process.exitCode,
      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .forEach(onOutput),
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .forEach(onOutput),
    ).wait;
    if (status != 0) {
      throw StateError('ESP flashing utility exited with status $status');
    }
  }

  static File _bundledEsptool() {
    final executable = File(Platform.resolvedExecutable);
    final base = Platform.isMacOS
        ? executable.parent.parent.uri.resolve('Resources/')
        : executable.parent.uri;
    final platform = switch (Abi.current()) {
      Abi.macosArm64 => 'macos-arm64',
      Abi.macosX64 => 'macos-amd64',
      Abi.linuxArm64 => 'linux-aarch64',
      Abi.linuxX64 => 'linux-amd64',
      Abi.windowsX64 || Abi.windowsArm64 => 'windows-amd64',
      _ => throw UnsupportedError('Unsupported platform for ESP flashing'),
    };
    final name = Platform.isWindows ? 'esptool.exe' : 'esptool';
    return File.fromUri(base.resolve('meshgram-flasher/$platform/$name'));
  }

  static Future<String> eraseUf2(
    PreparedFirmware firmware,
    Directory volume,
    AssetBundle assets,
  ) async {
    final name = firmware.target.eraser;
    if (firmware.mode != FirmwareInstallMode.clean || name == null) {
      throw StateError('There is no erase image for this board');
    }
    await _checkImage(firmware.file, firmware.target.chip, firmware.mode);
    final data = await assets.load('assets/firmware_tools/$name');
    final erase = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    validateFirmwareImage(erase, firmware.target.chip);
    final board = await _volumeBoardId(volume, firmware.target.chip);
    final destination = await _uf2Destination(volume);
    await destination.writeAsBytes(erase, flush: true);
    return board;
  }

  static Future<void> flashUf2(
    PreparedFirmware firmware,
    Directory volume, {
    String? erasedBoard,
  }) async {
    if (!firmware.target.chip.usesUf2) {
      throw StateError('UF2 firmware is required');
    }
    await _checkImage(firmware.file, firmware.target.chip, firmware.mode);
    final board = await _volumeBoardId(volume, firmware.target.chip);
    if (firmware.mode == FirmwareInstallMode.clean && erasedBoard != board) {
      throw const FormatException(
        'Select the same UF2 bootloader after the erase step',
      );
    }
    await firmware.file.copy((await _uf2Destination(volume)).path);
  }

  static Future<String> _volumeBoardId(
    Directory volume,
    FirmwareChip chip,
  ) async {
    final info = File.fromUri(volume.uri.resolve('INFO_UF2.TXT'));
    if (await info.exists() && await info.length() <= 4096) {
      final text = await info.readAsString();
      final board = RegExp(
        r'^Board-ID:\s*([^\r\n]+)',
        multiLine: true,
      ).firstMatch(text)?.group(1)?.trim();
      final rp = board?.toUpperCase().startsWith('RPI-RP2') ?? false;
      if (board != null && rp == (chip == FirmwareChip.rp2040)) return board;
    }
    throw const FormatException(
      'Select a UF2 bootloader drive for the selected chip',
    );
  }

  static Future<File> _uf2Destination(Directory volume) async {
    final destination = File.fromUri(volume.uri.resolve('MESHGRAM.UF2'));
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('A firmware file is already present on this drive');
    }
    return destination;
  }

  static Future<Directory> _temporary() async =>
      (await getTemporaryDirectory()).createTemp('meshgram-firmware-');

  static Future<List<Map<String, dynamic>>> _loadReleases(String slug) async {
    if (!RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(slug)) {
      throw const FormatException('Invalid release repository');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    final releases = <Map<String, dynamic>>[];
    try {
      const pageSize = 5;
      for (var page = 1; page <= 4; page++) {
        final uri = Uri.https('api.github.com', '/repos/$slug/releases', {
          'page': '$page',
          'per_page': '$pageSize',
        });
        final response = await _request(client, uri);
        final bytes = await response
            .fold(BytesBuilder(copy: false), (buffer, chunk) {
              if (buffer.length + chunk.length > 8 * 1024 * 1024) {
                throw const FormatException('Release metadata is too large');
              }
              return buffer..add(chunk);
            })
            .timeout(const Duration(seconds: 25));
        final current = (jsonDecode(utf8.decode(bytes.takeBytes())) as List)
            .cast<Map<String, dynamic>>();
        releases.addAll(current);
        if (current.length < pageSize) break;
      }
      return releases;
    } finally {
      client.close(force: true);
    }
  }

  static Future<HttpClientResponse> _request(HttpClient client, Uri uri) async {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 12));
    request.headers.set(HttpHeaders.userAgentHeader, 'Meshgram Firmware');
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Firmware server returned ${response.statusCode}',
        uri: uri,
      );
    }
    return response;
  }

  static Future<void> _checkImage(
    File file,
    FirmwareChip chip,
    FirmwareInstallMode mode,
  ) async {
    if (await file.length() > _maxImage) {
      throw const FormatException('Firmware image is too large');
    }
    final bytes = await file.readAsBytes();
    validateFirmwareImage(bytes, chip, mode: mode);
    if (!chip.usesUf2 && mode == FirmwareInstallMode.clean) {
      _requireFactoryApp(bytes, chip, _partitions(bytes));
    }
  }
}

Future<PreparedFirmware> _prepareArchive(
  String path,
  String directoryPath,
  FirmwareTarget target,
  String version,
  FirmwareInstallMode mode,
) async {
  final input = InputFileStream(path);
  final directory = Directory(directoryPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    ArchiveFile? match(bool Function(String) test) => archive.files
        .where((file) => file.isFile && test(file.name.split('/').last))
        .singleOrNull;
    Uint8List contents(ArchiveFile? entry) {
      if (entry == null ||
          entry.size <= 0 ||
          entry.size > FirmwareFlasher._maxImage) {
        throw const FormatException(
          'Compatible image is missing from the firmware archive',
        );
      }
      return entry.content;
    }

    Future<File> save(Uint8List bytes, String name) =>
        File.fromUri(directory.uri.resolve(name)).writeAsBytes(bytes);

    final pattern = target.filePattern(_versionCode(version));
    final factory = match(pattern.hasMatch);
    final bytes = contents(factory);
    final chip = target.chip;
    final factoryName = factory!.name.split('/').last;
    if (chip.usesUf2) {
      validateFirmwareImage(bytes, chip);
      return PreparedFirmware(
        file: await save(bytes, 'firmware.uf2'),
        name: factoryName,
        version: version,
        target: target,
        temporary: directory,
        mode: mode,
      );
    }

    validateFirmwareImage(bytes, chip);
    final partitions = _partitions(bytes);
    _requireFactoryApp(bytes, chip, partitions);
    final base = factoryName.replaceFirst(RegExp(r'\.factory\.bin$'), '');
    final update = mode == FirmwareInstallMode.update;
    final appName = '$base.bin';
    final app = update ? contents(match((name) => name == appName)) : bytes;
    if (update) validateFirmwareImage(app, chip, mode: mode);
    final appOffset = update ? partitions[0x0010]?.address : 0;
    if (appOffset == null ||
        appOffset < 0x10000 && update ||
        (update && app.length > partitions[0x0010]!.size)) {
      throw const FormatException('Invalid ESP application partition');
    }
    final extra = <FlashSegment>[];
    Future<void> include(ArchiveFile? image, int partition, String name) async {
      if (image == null) return;
      final area = partitions[partition];
      final section = contents(image);
      if (area == null ||
          section.length > area.size ||
          area.address < appOffset + app.length) {
        throw const FormatException('Invalid ESP firmware partition');
      }
      extra.add((file: await save(section, name), address: area.address));
    }

    final ota =
        match((name) => name == 'mt-${chip.nameForTool}-ota.bin') ??
        match(
          (name) =>
              name ==
              (chip == FirmwareChip.esp32s3 ? 'bleota-s3.bin' : 'bleota.bin'),
        );
    await include(ota, 0x0011, 'ota.bin');
    if (!update) {
      final fileSystemName = base.replaceFirst('firmware-', 'littlefs-');
      final fs =
          match((name) => name == '$fileSystemName.bin') ??
          match(
            (name) =>
                name ==
                '${fileSystemName.replaceFirst('littlefs-', 'littlefswebui-')}.bin',
          );
      await include(fs, 0x0182, 'filesystem.bin');
    }
    return PreparedFirmware(
      file: await save(app, 'firmware.bin'),
      name: update ? appName : factoryName,
      version: version,
      target: target,
      temporary: directory,
      mode: mode,
      address: appOffset,
      additional: extra,
    );
  } finally {
    await input.close();
  }
}

Map<int, ({int address, int size})> _partitions(
  Uint8List merged, {
  int start = 0x8000,
}) {
  final result = <int, ({int address, int size})>{};
  final view = ByteData.sublistView(merged);
  for (
    var offset = start;
    offset + 32 <= merged.length && offset < start + 0xc00;
    offset += 32
  ) {
    if (view.getUint16(offset, Endian.little) != 0x50aa) break;
    final type = view.getUint16(offset + 2, Endian.big);
    final address = view.getUint32(offset + 4, Endian.little);
    final size = view.getUint32(offset + 8, Endian.little);
    if (address < 0x9000 ||
        address % 4096 != 0 ||
        size == 0 ||
        size % 4096 != 0 ||
        address + size > 64 * 1024 * 1024) {
      throw const FormatException('Invalid ESP partition table');
    }
    result[type] = (address: address, size: size);
  }
  return result;
}

void _requireFactoryApp(
  Uint8List image,
  FirmwareChip chip,
  Map<int, ({int address, int size})> partitions,
) {
  final app = partitions[0x0010] ?? partitions[0x0000];
  if (app == null || app.address + 24 >= image.length) {
    throw const FormatException(
      'Factory image has no ESP application partition',
    );
  }
  validateFirmwareImage(
    Uint8List.sublistView(image, app.address),
    chip,
    mode: FirmwareInstallMode.update,
  );
}

void validateFirmwareImage(
  Uint8List image,
  FirmwareChip chip, {
  FirmwareInstallMode mode = FirmwareInstallMode.clean,
}) {
  final data = ByteData.sublistView(image);
  if (chip.uf2Family case final family?) {
    if (data.lengthInBytes == 0 || data.lengthInBytes % 512 != 0) {
      throw const FormatException('Invalid UF2 block size');
    }
    for (var block = 0; block < data.lengthInBytes; block += 512) {
      int field(int offset) => data.getUint32(block + offset, Endian.little);
      if (field(0) != 0x0a324655 ||
          field(4) != 0x9e5d5157 ||
          field(508) != 0x0ab16f30 ||
          field(8) & 0x2000 == 0 ||
          field(28) != family ||
          field(16) > 476) {
        throw const FormatException(
          'UF2 image does not match the selected chip',
        );
      }
    }
    return;
  }
  final update = mode == FirmwareInstallMode.update;
  final offset = update ? 0 : chip.headerOffset;
  if (image.length <= offset + 24 ||
      image[offset] != 0xe9 ||
      data.getUint16(offset + 12, Endian.little) != chip.espId ||
      (update &&
          image.length >= 0x8002 &&
          data.getUint16(0x8000, Endian.little) == 0x50aa)) {
    throw const FormatException(
      'ESP image does not match the selected chip or installation mode',
    );
  }
}
