// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'message_link_metadata.dart';

final _diskCache = MessageLinkDiskCache(getApplicationCacheDirectory);

Future<MessageLinkMetadata?> loadMessageLinkPreview(Uri uri) =>
    _diskCache.load(uri, fetchMessageLinkMetadata);

class MessageLinkDiskCache {
  MessageLinkDiskCache(this._cacheDirectory);

  static const _maxEntries = 24;
  static const _maxImageBytes = 512 * 1024;
  static const _maxEntryBytes = 720 * 1024;

  final Future<Directory> Function() _cacheDirectory;
  Future<Directory?>? _directory;
  Future<void> _writes = Future.value();

  Future<MessageLinkMetadata?> load(
    Uri uri,
    Future<MessageLinkMetadata?> Function(Uri) fetch,
  ) async {
    if (!canFetchMessageLink(uri)) return null;
    final directory = await (_directory ??= _openDirectory());
    if (directory == null) return fetch(uri);
    final key = sha256.convert(utf8.encode(uri.removeFragment().toString()));
    final file = File.fromUri(directory.uri.resolve('$key.json'));
    if (await _read(file) case final cached?) return cached;

    final preview = await fetch(uri);
    if (preview?.image case final image?
        when image.isNotEmpty && image.length <= _maxImageBytes) {
      await (_writes = _writes.then((_) => _store(directory, file, preview!)));
    }
    return preview;
  }

  Future<Directory?> _openDirectory() async {
    try {
      final base = await _cacheDirectory();
      return Directory.fromUri(base.uri.resolve('link-previews/'));
    } on Exception {
      return null;
    }
  }

  Future<MessageLinkMetadata?> _read(File file) async {
    try {
      if (await file.length() > _maxEntryBytes) return null;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final image = base64Decode(data['image'] as String);
      if (image.isEmpty || image.length > _maxImageBytes) return null;
      final metadata = MessageLinkMetadata(
        siteName: data['siteName'] as String?,
        title: data['title'] as String?,
        description: data['description'] as String?,
        image: image,
        imageWidth: data['imageWidth'] as int?,
        imageHeight: data['imageHeight'] as int?,
        prefersLargeImage: data['prefersLargeImage'] == true,
      );
      try {
        await file.setLastModified(DateTime.now());
      } on FileSystemException {
        // The cache entry may have been evicted while it was being read.
      }
      return metadata;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> _store(
    Directory directory,
    File file,
    MessageLinkMetadata preview,
  ) async {
    try {
      await directory.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'siteName': preview.siteName,
          'title': preview.title,
          'description': preview.description,
          'image': base64Encode(preview.image!),
          'imageWidth': preview.imageWidth,
          'imageHeight': preview.imageHeight,
          'prefersLargeImage': preview.prefersLargeImage,
        }),
      );
      await temporary.rename(file.path);

      final entries = <(File, DateTime)>[];
      await for (final item in directory.list(followLinks: false)) {
        if (item is File && item.path.endsWith('.json')) {
          entries.add((item, await item.lastModified()));
        } else if (item is File && item.path.endsWith('.tmp')) {
          await item.delete();
        }
      }
      entries.sort((a, b) => b.$2.compareTo(a.$2));
      for (final (old, _) in entries.skip(_maxEntries)) {
        await old.delete();
      }
    } on FileSystemException {
      // OS cache storage is optional. The downloaded preview can still be used.
    }
  }
}
