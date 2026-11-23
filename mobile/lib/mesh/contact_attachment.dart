// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';

import 'package:characters/characters.dart';

import 'network.dart';

final _controlCharacters = RegExp(r'[\x00-\x1F\x7F]+');
final _publicKey = RegExp(r'^[0-9a-f]{64}$');

bool validContactKey(String value) =>
    _publicKey.hasMatch(value) && value != '0' * 64;

String fitContactName(String input, int maxBytes) {
  final name = StringBuffer();
  var remaining = maxBytes;
  for (final character
      in input.replaceAll(_controlCharacters, ' ').trim().characters) {
    remaining -= utf8.encode(character).length;
    if (remaining < 0) break;
    name.write(character);
  }
  return name.toString().trimRight();
}

String _compactBytes(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

List<int> contactKeyBytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

String? compactContactLink(ContactAttachment contact, int maxBytes) {
  final networkPath = switch (contact.network) {
    'meshcore' when contact.type != null => 'c/${contact.type}',
    'meshtastic' => 't/${int.parse(contact.id.substring(5)).toRadixString(16)}',
    _ => null,
  };
  if (networkPath == null) return null;
  final link =
      'meshgram://contact/$networkPath/${_compactBytes(contactKeyBytes(contact.publicKey))}';
  if (link.length > maxBytes) return null;
  final remaining = maxBytes - link.length - 1;
  final name = fitContactName(contact.name, remaining * 3 ~/ 4);
  return name.isEmpty ? link : '$link/${_compactBytes(utf8.encode(name))}';
}

ContactAttachment? readCompactContact(Uri uri) {
  if (uri.scheme != 'meshgram' ||
      uri.host != 'contact' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final parts = uri.pathSegments;
  if (parts.length < 3 || parts.length > 4 || parts[2].length != 43) {
    return null;
  }
  try {
    final key = base64Url.decode(base64Url.normalize(parts[2]));
    if (key.length != 32 || key.every((byte) => byte == 0)) return null;
    final publicKey = key
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final name = parts.length == 4
        ? utf8.decode(base64Url.decode(base64Url.normalize(parts.last)))
        : '';
    switch (parts.first) {
      case 'c':
        final type = int.tryParse(parts[1]);
        if (type == null || type < 1 || type > 4) return null;
        final prefix = publicKey.substring(0, 12);
        return (
          network: 'meshcore',
          id: 'node:$prefix',
          name: _nameOr(name, prefix, 31),
          publicKey: publicKey,
          type: type,
          shortName: null,
        );
      case 't':
        final number = int.tryParse(parts[1], radix: 16);
        if (number == null || number <= 0 || number >= 0xffffffff) return null;
        final label = '!${number.toRadixString(16).padLeft(8, '0')}';
        return (
          network: 'meshtastic',
          id: 'node:$number',
          name: _nameOr(name, label, 39),
          publicKey: publicKey,
          type: null,
          shortName: null,
        );
      default:
        return null;
    }
  } on FormatException {
    return null;
  }
}

String _nameOr(String name, String fallback, int maxBytes) {
  final sanitized = fitContactName(name, maxBytes);
  return sanitized.isEmpty ? fallback : sanitized;
}
