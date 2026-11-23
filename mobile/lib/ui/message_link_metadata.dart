// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:html/parser.dart' as html;

class MessageLinkMetadata {
  const MessageLinkMetadata({this.title, this.description, this.image});

  final String? title;
  final String? description;
  final Uint8List? image;
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
({String? title, String? description, Uri? image}) parseMessageLinkMetadata(
  Uint8List body,
  Uri page, {
  String? encoding,
}) {
  final head = html.parse(body, encoding: encoding).head;

  String? clean(String? value, int limit) {
    final collapsed = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed == null || collapsed.isEmpty) return null;
    final characters = collapsed.runes.take(limit).toList();
    return String.fromCharCodes(characters);
  }

  String? meta(String key) {
    for (final tag in head?.querySelectorAll('meta') ?? const []) {
      if (tag.attributes['property']?.toLowerCase() == key ||
          tag.attributes['name']?.toLowerCase() == key) {
        final value = tag.attributes['content'];
        if (value != null && value.trim().isNotEmpty) return value.trim();
      }
    }
    return null;
  }

  final image = meta('og:image:secure_url') ?? meta('og:image');
  final reference = image == null ? null : Uri.tryParse(image);
  final resolved = reference == null ? null : page.resolveUri(reference);
  return (
    title: clean(meta('og:title') ?? head?.querySelector('title')?.text, 160),
    description: clean(meta('og:description') ?? meta('description'), 360),
    image: resolved != null && _sameOrigin(page, resolved) ? resolved : null,
  );
}

const _timeout = Duration(seconds: 6);

bool _sameOrigin(Uri a, Uri b) =>
    a.scheme == b.scheme && a.host == b.host && a.port == b.port;

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
  Uri? origin,
}) async {
  for (var redirects = 0; redirects <= 3; redirects++) {
    if (!canFetchMessageLink(uri) ||
        (origin != null && !_sameOrigin(origin, uri))) {
      return null;
    }
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
        response.contentLength > limit) {
      await response.listen(null).cancel();
      return null;
    }
    final bytes = BytesBuilder();
    await for (final chunk in response.timeout(_timeout)) {
      if (bytes.length + chunk.length > limit) return null;
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
  );
  if (download == null) return null;
  final metadata = parseMessageLinkMetadata(
    download.body,
    download.uri,
    encoding: download.encoding,
  );
  final image = switch (metadata.image) {
    final url? => await _previewImage(client, url, download.uri),
    null => null,
  };
  if (metadata.title == null && metadata.description == null && image == null) {
    return null;
  }
  return MessageLinkMetadata(
    title: metadata.title,
    description: metadata.description,
    image: image,
  );
}

Future<Uint8List?> _previewImage(HttpClient client, Uri uri, Uri origin) async {
  try {
    const imageTypes = {'image/jpeg', 'image/png', 'image/webp'};
    final download = await _download(
      client,
      uri,
      accept: imageTypes.join(', '),
      contentTypes: imageTypes,
      limit: 512 * 1024,
      origin: origin,
    );
    if (download == null) return null;
    final buffer = await ui.ImmutableBuffer.fromUint8List(download.body);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width > 2048 || descriptor.height > 2048) return null;
        return download.body;
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
