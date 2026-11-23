// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';
import 'dart:typed_data';

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
}

Uint8List _bytes(String html) => Uint8List.fromList(utf8.encode(html));
