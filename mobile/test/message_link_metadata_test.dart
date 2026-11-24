// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/message_link_cache.dart';
import 'package:meshgrame/ui/message_link_metadata.dart';

void main() {
  test('reuses downloaded preview images after reopening the cache', () async {
    final directory = await Directory.systemTemp.createTemp('mesh-link-cache');
    addTearDown(() => directory.delete(recursive: true));
    final url = Uri.parse('https://paper.example/article');
    MessageLinkDiskCache openCache() =>
        MessageLinkDiskCache(() async => directory);
    final cache = openCache();

    final partial = await cache.load(
      url,
      (_) async => const MessageLinkMetadata(title: 'Field notes'),
    );
    expect(partial?.image, isNull);
    await cache.load(
      url,
      (_) async => MessageLinkMetadata(
        title: 'Field notes',
        image: _png,
        imageWidth: 3,
        imageHeight: 2,
        prefersLargeImage: true,
      ),
    );
    final cached = await openCache().load(
      url.replace(fragment: 'release-notes'),
      (_) => throw StateError('Image should be available offline'),
    );
    expect(cached?.image, _png);
    expect(cached?.title, 'Field notes');
    expect(cached?.imageWidth, 3);
    expect(cached?.imageHeight, 2);
    expect(cached?.prefersLargeImage, isTrue);
  });

  test('loads a CDN image and follows its public HTTPS redirect', () async {
    final page = Uri.parse('https://paper.example/article');
    final image = Uri.parse('https://images.example/cover');
    final redirect = Uri.parse('https://cdn.example/cover.png');
    final client = _PreviewClient({
      page: _PreviewResponse.html('''
        <meta property="og:site_name" content="  Radio   Notes  ">
        <meta property="og:title" content="A weekend on the air">
        <meta property="og:description" content="Field notes">
        <meta name="twitter:card" content="summary_large_image">
        <meta property="og:image" content="$image#unused">
      '''),
      image: _PreviewResponse.redirect(redirect),
      redirect: _PreviewResponse.image(),
    });

    final preview = await _load(page, client);

    expect(client.requests.keys, [page, image, redirect]);
    expect(preview?.siteName, 'Radio Notes');
    expect(preview?.title, 'A weekend on the air');
    expect(preview?.description, 'Field notes');
    expect(preview?.image, _png);
    expect(preview?.imageWidth, 3);
    expect(preview?.imageHeight, 2);
    expect(preview?.prefersLargeImage, isTrue);
    for (final request in client.requests.values) {
      expect(request.followRedirects, isFalse);
      expect(request.headers.values.keys, [HttpHeaders.acceptHeader]);
    }
  });

  test(
    'skips invalid image candidates and keeps the first valid HTTPS image',
    () {
      final metadata = parseMessageLinkMetadata(
        _bytes('''
        <meta property="og:type" content="video.other">
        <meta property="og:image:secure_url" content="https://router.local/a">
        <meta property="og:image" content="http://image.example/a.png">
        <meta property="og:image" content="https://image.example:8443/a.png">
        <meta property="og:image" content="https://user:secret@image.example/a.png">
        <meta property="og:image" content="https://127.0.0.1/a.png">
        <meta property="og:image:url" content="//cdn.example/first.png">
        <meta name="twitter:image" content="https://cdn.example/second.png">
      '''),
        Uri.parse('https://paper.example/article'),
      );

      expect(metadata.image, Uri.parse('https://cdn.example/first.png'));
      expect(metadata.prefersLargeImage, isTrue);
    },
  );

  test(
    'validates every image redirect and preserves the text preview',
    () async {
      final page = Uri.parse('https://paper.example/article');
      final image = Uri.parse('https://images.example/cover');
      final client = _PreviewClient({
        page: _PreviewResponse.html('''
        <meta property="og:site_name" content="Radio Notes">
        <meta property="og:image" content="$image">
      '''),
        image: _PreviewResponse.redirect(
          Uri.parse('https://192.168.1.1/cover'),
        ),
      });

      final preview = await _load(page, client);

      expect(client.requests.keys, [page, image]);
      expect(preview?.siteName, 'Radio Notes');
      expect(preview?.image, isNull);
      expect(preview?.imageWidth, isNull);
      expect(preview?.imageHeight, isNull);
      expect(preview?.prefersLargeImage, isFalse);
    },
  );
}

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAD0lEQVR4nGNgqP8PRXAWAFOiCPWI9KCNAAAAAElFTkSuQmCC',
);

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

Future<MessageLinkMetadata?> _load(Uri uri, _PreviewClient client) =>
    HttpOverrides.runZoned(
      () => fetchMessageLinkMetadata(uri),
      createHttpClient: (_) => client,
    );

class _PreviewClient extends Fake implements HttpClient {
  _PreviewClient(this.responses);

  final Map<Uri, _PreviewResponse> responses;
  final requests = <Uri, _PreviewRequest>{};

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return requests[url] = _PreviewRequest(responses[url]!);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _PreviewRequest extends Fake implements HttpClientRequest {
  _PreviewRequest(this.response);

  final _PreviewResponse response;

  @override
  bool followRedirects = true;

  @override
  final _PreviewHeaders headers = _PreviewHeaders();

  @override
  Future<HttpClientResponse> close() async => response;
}

class _PreviewResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _PreviewResponse._(List<int> bytes, this.statusCode, this.headers)
    : contentLength = bytes.length,
      super(Stream.value(bytes));

  _PreviewResponse.html(String html)
    : this._(
        _bytes(html),
        HttpStatus.ok,
        _PreviewHeaders(contentType: ContentType.html),
      );

  _PreviewResponse.image()
    : this._(
        _png,
        HttpStatus.ok,
        _PreviewHeaders(contentType: ContentType('image', 'png')),
      );

  _PreviewResponse.redirect(Uri location)
    : this._(
        const [],
        HttpStatus.found,
        _PreviewHeaders()..set(HttpHeaders.locationHeader, location.toString()),
      );

  @override
  final int statusCode, contentLength;

  @override
  final _PreviewHeaders headers;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewHeaders extends Fake implements HttpHeaders {
  _PreviewHeaders({this.contentType});

  @override
  final ContentType? contentType;

  final values = <String, String>{};

  @override
  String? value(String name) => values[name];

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value.toString();
  }
}
