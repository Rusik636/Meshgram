// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:html/parser.dart' as html;

class MessageLinkMetadata {
  const MessageLinkMetadata({
    this.siteName,
    this.title,
    this.description,
    this.image,
    this.imageWidth,
    this.imageHeight,
    this.prefersLargeImage = false,
  });

  final String? siteName, title, description;
  final Uint8List? image;
  final int? imageWidth, imageHeight;
  final bool prefersLargeImage;
}

bool canFetchMessageLink(Uri uri) =>
    uri.scheme == 'https' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    uri.host.contains('.') &&
    InternetAddress.tryParse(uri.host) == null &&
    !uri.host.endsWith('.local') &&
    !uri.host.endsWith('.localhost');

/// Read only Open Graph and HTML metadata. The page is never rendered.
({
  String? siteName,
  String? title,
  String? description,
  Uri? image,
  bool prefersLargeImage,
})
parseMessageLinkMetadata(Uint8List body, Uri page, {String? encoding}) {
  final head = html.parse(body, encoding: encoding).head;

  String? clean(String? value, int limit) {
    final collapsed = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed == null || collapsed.isEmpty) return null;
    final characters = collapsed.runes.take(limit).toList();
    return String.fromCharCodes(characters);
  }

  final tags = head?.querySelectorAll('meta') ?? const [];
  Iterable<String> metaValues(String key) sync* {
    for (final tag in tags) {
      if (tag.attributes['property']?.toLowerCase() == key ||
          tag.attributes['name']?.toLowerCase() == key) {
        final value = tag.attributes['content'];
        if (value != null && value.trim().isNotEmpty) yield value.trim();
      }
    }
  }

  String? meta(String key) => metaValues(key).firstOrNull;

  // Publishers can host their advertised image on another public HTTPS origin.
  final images = [
    for (final key in [
      'og:image:secure_url',
      'og:image',
      'og:image:url',
      'twitter:image',
      'twitter:image:src',
    ])
      for (final value in metaValues(key))
        if (Uri.tryParse(value) case final reference?)
          page.resolveUri(reference),
  ];
  final type = meta('og:type')?.toLowerCase();
  return (
    siteName: clean(meta('og:site_name'), 80),
    title: clean(
      meta('og:title') ??
          meta('twitter:title') ??
          head?.querySelector('title')?.text,
      160,
    ),
    description: clean(
      meta('og:description') ??
          meta('twitter:description') ??
          meta('description'),
      360,
    ),
    image: images.where(canFetchMessageLink).firstOrNull,
    prefersLargeImage:
        meta('twitter:card')?.toLowerCase() == 'summary_large_image' ||
        type == 'article' ||
        type == 'video' ||
        type?.startsWith('video.') == true,
  );
}

const _timeout = Duration(seconds: 6);

bool _publicAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  final a = bytes[0], b = bytes[1], c = bytes[2];
  if (address.type == InternetAddressType.IPv4) {
    return a != 0 &&
        a != 10 &&
        a != 127 &&
        a < 224 &&
        !(a == 100 && b >= 64 && b <= 127) &&
        !(a == 169 && b == 254) &&
        !(a == 172 && b >= 16 && b <= 31) &&
        !(a == 192 && (b == 168 || (b == 0 && (c == 0 || c == 2)))) &&
        !(a == 192 && b == 88 && c == 99) &&
        !(a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100))) &&
        !(a == 203 && b == 0 && c == 113);
  }
  // Global unicast, excluding protocol assignments, documentation, and 6to4.
  return a >= 0x20 &&
      a <= 0x3f &&
      !(a == 0x20 &&
          (b == 2 || (b == 1 && (c < 2 || (c == 0x0d && bytes[3] == 0xb8))))) &&
      !(a == 0x3f && b == 0xff && c < 0x10);
}

Future<ConnectionTask<Socket>> _connect(
  Uri uri,
  String? proxyHost,
  int? proxyPort,
) async {
  if (proxyHost != null || !canFetchMessageLink(uri)) {
    throw const SocketException('Unsupported preview destination');
  }
  final addresses = await InternetAddress.lookup(uri.host).timeout(_timeout);
  // Connect to the validated address directly, so DNS is not consulted again.
  final address = addresses.where(_publicAddress).firstOrNull;
  if (address == null) {
    throw const SocketException('No public preview destination');
  }
  return SecureSocket.startConnect(address, uri.port);
}

typedef _Download = ({Uri uri, Uint8List body, String? encoding});

Future<_Download?> _download(
  HttpClient client,
  Uri uri, {
  required String accept,
  required Set<String> contentTypes,
  required int limit,
  bool readPrefix = false,
}) async {
  for (var redirects = 0; redirects <= 3; redirects++) {
    if (!canFetchMessageLink(uri)) return null;
    final request = await client.getUrl(uri.removeFragment()).timeout(_timeout);
    request
      ..followRedirects = false
      ..headers.set(HttpHeaders.acceptHeader, accept);
    final response = await request.close().timeout(_timeout);
    if (switch (response.statusCode) {
      301 || 302 || 303 || 307 || 308 => true,
      _ => false,
    }) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      final target = location == null ? null : Uri.tryParse(location);
      // Release the response stream without reading an unbounded redirect body.
      await response.listen(null).cancel();
      if (target == null) return null;
      uri = uri.resolveUri(target);
      continue;
    }
    final type = response.headers.contentType;
    if (response.statusCode != HttpStatus.ok ||
        !contentTypes.contains(type?.mimeType) ||
        (!readPrefix && response.contentLength > limit)) {
      await response.listen(null).cancel();
      return null;
    }
    final bytes = BytesBuilder();
    await for (final chunk in response.timeout(_timeout)) {
      final remaining = limit - bytes.length;
      if (chunk.length > remaining && !readPrefix) return null;
      if (readPrefix && chunk.length >= remaining) {
        bytes.add(chunk.sublist(0, remaining));
        break;
      }
      bytes.add(chunk);
    }
    return (uri: uri, body: bytes.takeBytes(), encoding: type?.charset);
  }
  return null;
}

Future<MessageLinkMetadata?> fetchMessageLinkMetadata(Uri uri) async {
  if (!canFetchMessageLink(uri)) return null;
  final client = HttpClient()
    ..connectionFactory = _connect
    ..connectionTimeout = _timeout
    ..userAgent = 'Meshgram Link Preview'
    ..findProxy = ((_) => 'DIRECT');
  try {
    return await _fetchPreview(
      client,
      uri,
    ).timeout(const Duration(seconds: 12));
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<MessageLinkMetadata?> _fetchPreview(HttpClient client, Uri uri) async {
  const htmlTypes = {'text/html', 'application/xhtml+xml'};
  final download = await _download(
    client,
    uri,
    accept: htmlTypes.join(', '),
    contentTypes: htmlTypes,
    limit: 384 * 1024,
    readPrefix: true,
  ).timeout(const Duration(seconds: 8));
  if (download == null) return null;
  final metadata = parseMessageLinkMetadata(
    download.body,
    download.uri,
    encoding: download.encoding,
  );
  final image = switch (metadata.image) {
    final url? => await _previewImage(
      client,
      url,
    ).timeout(const Duration(seconds: 3), onTimeout: () => null),
    null => null,
  };
  if (metadata.siteName == null &&
      metadata.title == null &&
      metadata.description == null &&
      image == null) {
    return null;
  }
  return MessageLinkMetadata(
    siteName: metadata.siteName,
    title: metadata.title,
    description: metadata.description,
    image: image?.bytes,
    imageWidth: image?.width,
    imageHeight: image?.height,
    prefersLargeImage: metadata.prefersLargeImage,
  );
}

Future<({Uint8List bytes, int width, int height})?> _previewImage(
  HttpClient client,
  Uri uri,
) async {
  try {
    const imageTypes = {'image/jpeg', 'image/png', 'image/webp'};
    final download = await _download(
      client,
      uri,
      accept: imageTypes.join(', '),
      contentTypes: imageTypes,
      limit: 512 * 1024,
    );
    if (download == null) return null;
    final buffer = await ui.ImmutableBuffer.fromUint8List(download.body);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        // Wide preview banners can exceed 2048 px on one side.
        final width = descriptor.width, height = descriptor.height;
        if (width > 4096 || height > 4096 || width * height > 2048 * 2048) {
          return null;
        }
        return (bytes: download.body, width: width, height: height);
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  } catch (_) {
    // The text card remains usable if the optional image cannot be decoded.
    return null;
  }
}
