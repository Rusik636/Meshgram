// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'desktop_usb.dart';
import 'firmware_catalog.dart';

typedef FirmwareAsset = ({
  String name,
  String version,
  Uri url,
  String? digest,
  int size,
});

FirmwareAsset? selectFirmwareAsset(
  FirmwareTarget target,
  Iterable<Map<String, dynamic>> releases,
) {
  for (final release in releases) {
    final version = release['tag_name'] as String?;
    if (version == null ||
        release['draft'] == true ||
        release['prerelease'] == true ||
        !version.startsWith(target.releasePrefix ?? 'v')) {
      continue;
    }
    final code = version.startsWith('v') ? version.substring(1) : version;
    final zip = target.archive?.replaceAll('{version}', code);
    final rx = target.filePattern(code);
    final assets = ((release['assets'] as List?) ?? [])
        .cast<Map<String, dynamic>>();
    final asset = assets.where((item) {
      final name = item['name'] as String?;
      return name != null && (zip == null ? rx.hasMatch(name) : name == zip);
    }).singleOrNull;
    if (asset == null) continue;
    final url = Uri.tryParse(asset['browser_download_url'] as String? ?? '');
    final size = asset['size'] as int? ?? 0;
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        !url.path.startsWith('/${target.repository}/releases/download/') ||
        size <= 0 ||
        size > 220 * 1024 * 1024) {
      continue;
    }
    return (
      name: asset['name'] as String,
      version: version,
      url: url,
      digest: asset['digest'] as String?,
      size: size,
    );
  }
  return null;
}

class PreparedFirmware {
  const PreparedFirmware({
    required this.file,
    required this.name,
    required this.version,
    required this.target,
    required this.temporary,
  });
  final File file;
  final String name, version;
  final FirmwareTarget target;
  final Directory temporary;

  Future<void> dispose() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
}

class FirmwareFlasher {
  const FirmwareFlasher(this.usb);
  final DesktopUsbTransport usb;
  static const _maxImage = 16 * 1024 * 1024;

  Future<PreparedFirmware> download(
    FirmwareTarget target, {
    required void Function(double progress) onProgress,
  }) async {
    final directory = await (await getTemporaryDirectory()).createTemp(
      'meshgram-firmware-',
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final slug = target.repository;
      if (!RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(slug)) {
        throw const FormatException('Invalid release repository');
      }
      final asset = await _findFirmwareAsset(client, target);
      if (asset == null) {
        throw StateError('No compatible stable firmware release found');
      }

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

      final image = File.fromUri(
        directory.uri.resolve('firmware.${target.chip.extension}'),
      );
      var displayName = asset.name;
      if (target.archive == null) {
        await raw.rename(image.path);
      } else {
        final code = asset.version.startsWith('v')
            ? asset.version.substring(1)
            : asset.version;
        final pattern = target.filePattern(code);
        final input = raw.path, output = image.path;
        displayName = await Isolate.run(
          () => _extractImage(input, output, pattern),
        );
        await raw.delete();
      }
      await _checkImage(image, target.chip);
      return PreparedFirmware(
        file: image,
        name: displayName,
        version: asset.version,
        target: target,
        temporary: directory,
      );
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<PreparedFirmware> local(FirmwareTarget target, File source) async {
    final name = source.uri.pathSegments.last;
    final lower = name.toLowerCase();
    if (target.chip.usesUf2
        ? !lower.endsWith('.uf2')
        : !lower.endsWith('factory.bin') && !lower.endsWith('merged.bin')) {
      throw const FormatException(
        'Choose a complete factory or merged image for this board',
      );
    }
    await _checkImage(source, target.chip);
    final directory = await (await getTemporaryDirectory()).createTemp(
      'meshgram-firmware-',
    );
    try {
      final image = await source.copy(
        directory.uri.resolve('firmware.${target.chip.extension}').toFilePath(),
      );
      await _checkImage(image, target.chip);
      return PreparedFirmware(
        file: image,
        name: name,
        version: '',
        target: target,
        temporary: directory,
      );
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> flashEsp(
    PreparedFirmware firmware,
    String port,
    String executable, {
    required void Function(String) onOutput,
  }) async {
    if (firmware.target.chip.usesUf2) {
      throw StateError('ESP firmware is required');
    }
    await _checkImage(firmware.file, firmware.target.chip);
    await usb.withReservedPort(port, () async {
      final process = await Process.start(executable, [
        '--chip',
        firmware.target.chip.nameForTool,
        '--port',
        port,
        'write-flash',
        '0x0',
        firmware.file.path,
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
        throw StateError('esptool exited with status $status');
      }
    });
  }

  static Future<void> flashUf2(
    PreparedFirmware firmware,
    Directory volume,
  ) async {
    if (!firmware.target.chip.usesUf2) {
      throw StateError('UF2 firmware is required');
    }
    await _checkImage(firmware.file, firmware.target.chip);
    final info = File.fromUri(volume.uri.resolve('INFO_UF2.TXT'));
    if (!await info.exists() ||
        await info.length() > 4096 ||
        !(await info.readAsString()).contains('Board-ID:')) {
      throw const FormatException(
        'Select the root of a mounted UF2 bootloader drive',
      );
    }
    final destination = File.fromUri(volume.uri.resolve('MESHGRAM.UF2'));
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('A firmware file is already present on this drive');
    }
    await firmware.file.copy(destination.path);
  }

  static String? findEsptool() {
    final path = Platform.environment['PATH'] ?? '';
    final home = Platform.environment['HOME'];
    final locations = [
      ...path.split(Platform.isWindows ? ';' : ':'),
      if (Platform.isMacOS) ...['/opt/homebrew/bin', '/usr/local/bin'],
      if (!Platform.isWindows && home != null) '$home/.local/bin',
    ];
    final name = Platform.isWindows ? 'esptool.exe' : 'esptool';
    for (final location in locations.where((value) => value.isNotEmpty)) {
      final candidate = File.fromUri(
        Directory(location).absolute.uri.resolve(name),
      );
      if (candidate.existsSync()) return candidate.path;
    }
    return null;
  }

  static Future<FirmwareAsset?> _findFirmwareAsset(
    HttpClient client,
    FirmwareTarget target,
  ) async {
    const pageSize = 5;
    final latestOnly = target.releasePrefix == null;
    final path = '/repos/${target.repository}/releases';
    for (var page = 1; page <= (latestOnly ? 1 : 10); page++) {
      final uri = latestOnly
          ? Uri.https('api.github.com', '$path/latest')
          : Uri.https('api.github.com', path, {
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
      final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      final releases = decoded is List ? decoded : [decoded];
      final asset = selectFirmwareAsset(
        target,
        releases.cast<Map<String, dynamic>>(),
      );
      if (asset != null || releases.length < pageSize) return asset;
    }
    return null;
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

  static Future<void> _checkImage(File file, FirmwareChip chip) async {
    final size = await file.length();
    if (size < 24 || size > _maxImage) {
      throw const FormatException('Invalid firmware image size');
    }
    validateFirmwareImage(await file.readAsBytes(), chip);
  }
}

Future<String> _extractImage(
  String path,
  String destination,
  RegExp pattern,
) async {
  final input = InputFileStream(path);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final entry = archive.files
        .where(
          (file) => file.isFile && pattern.hasMatch(file.name.split('/').last),
        )
        .singleOrNull;
    if (entry == null ||
        entry.size <= 0 ||
        entry.size > FirmwareFlasher._maxImage) {
      throw const FormatException(
        'Compatible image is missing from the firmware archive',
      );
    }
    final writer = OutputFileStream(destination);
    try {
      entry.writeContent(writer);
    } finally {
      await writer.close();
    }
    return entry.name.split('/').last;
  } finally {
    await input.close();
  }
}

void validateFirmwareImage(Uint8List image, FirmwareChip chip) {
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
  final offset = chip.headerOffset;
  if (image.length <= offset + 24 ||
      image[offset] != 0xe9 ||
      data.getUint16(offset + 12, Endian.little) != chip.espId) {
    throw const FormatException(
      'Factory image does not match the selected ESP chip',
    );
  }
}
