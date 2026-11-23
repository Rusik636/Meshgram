// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/message_link_metadata.dart';
import 'package:meshgrame/ui/message_links.dart';

void main() {
  test('detects web links in mesh text and trims prose punctuation', () {
    expect(
      firstMessageLink('На сайте (example.org/help).'),
      Uri.parse('https://example.org/help'),
    );
    expect(
      firstMessageLink('📻 (https://example.org/Page_(radio)), проверь'),
      Uri.parse('https://example.org/Page_(radio)'),
    );
    expect(
      firstMessageLink('http://192.168.1.1:8080'),
      Uri.parse('http://192.168.1.1:8080'),
    );
  });

  test('does not turn an address or custom scheme into a web link', () {
    for (final text in [
      'user@example.org',
      'geo:55.7,49.2',
      'meshgram://example.org/contact',
      'https://example.org@other.example/',
      'https://example.org:99999/',
      'https://',
    ]) {
      expect(firstMessageLink(text), isNull, reason: text);
    }
  });

  test('normalizes missing, mistyped and duplicate protocols', () {
    const normalized = 'https://rustore.ru/apps/Page?source=Mesh#screens';
    for (final value in [
      'RuStore.RU/apps/Page?source=Mesh#screens',
      '//RuStore.RU/apps/Page?source=Mesh#screens',
      'https//RuStore.RU/apps/Page?source=Mesh#screens',
      'https:/RuStore.RU/apps/Page?source=Mesh#screens',
      'htps://RuStore.RU/apps/Page?source=Mesh#screens',
      'https://HTTPS://RuStore.RU/apps/Page?source=Mesh#screens',
    ]) {
      expect(firstMessageLink(value).toString(), normalized, reason: value);
    }
    expect(
      firstMessageLink('http//RuStore.RU'),
      Uri.parse('http://rustore.ru'),
    );
    expect(firstMessageLink('ftp://rustore.ru'), isNull);
  });

  test('site metadata reads only from public HTTPS destinations', () {
    expect(canFetchMessageLink(Uri.parse('https://example.org')), isTrue);
    for (final text in [
      'http://example.org',
      'https://192.168.1.1',
      'https://[2001:db8::1]/',
      'https://router.local',
      'https://example.org:8443',
      'https://user:password@example.org/',
    ]) {
      expect(canFetchMessageLink(Uri.parse(text)), isFalse, reason: text);
    }
  });

  test('preview extracts title, description and a same-origin image', () {
    final site = Uri.parse('https://example.org/message');
    final data = parseMessageLinkMetadata(
      _bytes('''
        <!doctype html><head>
        <title>Unused title</title>
        <meta content="Radio &amp; maps" property="og:title">
        <meta name="description" content="Send   without the Internet.">
        <meta property="og:image" content="/preview.png">
        </head><body>This is not preview content.</body>
      '''),
      site,
    );
    expect(data.title, 'Radio & maps');
    expect(data.description, 'Send without the Internet.');
    expect(data.image, Uri.parse('https://example.org/preview.png'));

    final externalImage = parseMessageLinkMetadata(
      _bytes('<meta property="og:image" content="https://other.example/p">'),
      site,
    );
    expect(externalImage.image, isNull);
  });

  test(
    'RuStore media uses its first-party CDN and supports Twitter metadata',
    () {
      final data = parseMessageLinkMetadata(
        _bytes('''
        <meta name="twitter:title" content="Приложения">
        <meta name="twitter:description" content="Посмотрите каталог">
        <meta name="twitter:image" content="//static.rustore.ru/image/logo.jpg">
      '''),
        Uri.parse('https://www.rustore.ru/'),
      );
      expect(data.title, 'Приложения');
      expect(data.description, 'Посмотрите каталог');
      expect(data.image, Uri.parse('https://static.rustore.ru/image/logo.jpg'));
    },
  );

  test('keeps the HTML metadata when the rest of the page exceeds the limit', () async {
    final page = Uri.parse('https://example.net/large-page');
    final head = _bytes(
      '<title>Large page</title><meta name="description" content="Radio maps">',
    );
    final body = Uint8List(512 * 1024)..fillRange(0, 512 * 1024, 0x20);
    final client = _FixtureHttpClient(
      _FixtureResponse([head, body], head.length + body.length),
    );
    final result = await HttpOverrides.runZoned(
      () => fetchMessageLinkMetadata(page),
      createHttpClient: (_) => client,
    );
    expect(result?.title, 'Large page');
    expect(result?.description, 'Radio maps');
  });

  testWidgets(
    'previews a settled draft automatically and reuses it when sent',
    (tester) async {
      final requested = <Uri>[];
      final result = Completer<MessageLinkMetadata?>();
      Future<MessageLinkMetadata?> load(Uri uri) {
        requested.add(uri);
        return result.future;
      }

      Widget card(String text, {required bool compact}) => MaterialApp(
        home: Scaffold(
          body: MessageLinkPreview(
            uri: firstMessageLink(text)!,
            compact: compact,
            loadMetadata: load,
          ),
        ),
      );

      await tester.pumpWidget(card('example.net/unfinished', compact: true));
      await tester.pump(const Duration(milliseconds: 450));
      expect(requested, isEmpty);
      await tester.pumpWidget(
        card('https//Example.net/finished?q=radio', compact: true),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final uri = Uri.parse('https://example.net/finished?q=radio');
      expect(requested, [uri]);
      await tester.pumpWidget(
        card('example.net/finished?q=radio#part', compact: false),
      );
      expect(requested, [uri]);
      result.complete(const MessageLinkMetadata(title: 'Радиометки'));
      await tester.pumpAndSettle();
      expect(find.text('Радиометки'), findsOneWidget);
      expect(find.byTooltip('Load preview from site'), findsNothing);
    },
  );

  testWidgets('only loads HTTPS previews whose card is visible', (
    tester,
  ) async {
    final requested = <Uri>[];
    Future<MessageLinkMetadata?> load(Uri uri) async {
      requested.add(uri);
      return null;
    }

    Future<void> show(Uri uri, {required bool visible}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageLinkPreview(
            uri: uri,
            autoLoad: visible,
            loadMetadata: load,
          ),
        ),
      ),
    );

    final url = Uri.parse('https://example.net/received');
    await show(url, visible: false);
    expect(requested, isEmpty);
    await show(url, visible: true);
    await tester.pumpAndSettle();
    expect(requested, [url]);
    await tester.tap(find.byTooltip('Retry from site'));
    await tester.pumpAndSettle();
    expect(requested, [url, url]);
    await show(Uri.parse('http://example.net/received'), visible: true);
    await tester.pumpAndSettle();
    expect(requested, [url, url]);
  });

  testWidgets('drops queued previews when they leave the visible chat', (
    tester,
  ) async {
    final requested = <String>[];
    final running = Completer<MessageLinkMetadata?>();
    Future<MessageLinkMetadata?> load(Uri uri) {
      requested.add(uri.path);
      return running.future;
    }

    Future<void> show({required bool lastVisible}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (var i = 0; i < 4; i++)
                MessageLinkPreview(
                  uri: Uri.parse('https://example.net/queue/$i'),
                  autoLoad: i < 3 || lastVisible,
                  loadMetadata: load,
                ),
            ],
          ),
        ),
      ),
    );

    await show(lastVisible: true);
    expect(requested, ['/queue/0', '/queue/1', '/queue/2']);
    await show(lastVisible: false);
    running.complete(const MessageLinkMetadata(title: 'Radio'));
    await tester.pumpAndSettle();
    expect(requested, ['/queue/0', '/queue/1', '/queue/2']);
  });
}

Uint8List _bytes(String html) => Uint8List.fromList(utf8.encode(html));

class _FixtureHttpClient extends Fake implements HttpClient {
  _FixtureHttpClient(this.response);

  final HttpClientResponse response;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FixtureRequest(response);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _FixtureRequest extends Fake implements HttpClientRequest {
  _FixtureRequest(this.response);

  final HttpClientResponse response;

  @override
  final HttpHeaders headers = _FixtureHeaders();

  @override
  set followRedirects(bool value) {}

  @override
  Future<HttpClientResponse> close() async => response;
}

class _FixtureResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _FixtureResponse(List<List<int>> chunks, this.contentLength)
    : super(Stream.fromIterable(chunks));

  @override
  final int contentLength;

  @override
  final HttpHeaders headers = _FixtureHeaders();

  @override
  int get statusCode => HttpStatus.ok;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureHeaders extends Fake implements HttpHeaders {
  @override
  ContentType get contentType => ContentType.html;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}
