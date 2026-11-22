// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';

// MeshCore One reaction interoperability format. Channel references also
// include the original author to distinguish identical messages in one slot.
const _base32 = '0123456789abcdefghjkmnpqrstvwxyz';
final _hashPattern = RegExp(r'^[0-9a-hjkmnp-tv-z]{8}$');
final _senderPattern = RegExp(r'^[^\[\]\r\n]+$');
final _emojiPattern = RegExp(
  // Unicode mode supports these binary properties in the Dart VM.
  // ignore: valid_regexps
  r'\p{Extended_Pictographic}|\p{Regional_Indicator}|\u20e3',
  unicode: true,
);

bool _isEmoji(String text) =>
    text.characters.length == 1 && _emojiPattern.hasMatch(text);

String? meshCoreMessageReference(String body, int stamp, {String? sender}) {
  if (sender != null && !_senderPattern.hasMatch(sender)) return null;
  final timestamp = ByteData(4)..setUint32(0, stamp, Endian.little);
  final hash = sha256.convert([
    ...utf8.encode(body),
    ...timestamp.buffer.asUint8List(),
  ]);
  var prefix = 0;
  for (final byte in hash.bytes.take(5)) {
    prefix = (prefix << 8) | byte;
  }
  final token = String.fromCharCodes([
    for (var shift = 35; shift >= 0; shift -= 5)
      _base32.codeUnitAt((prefix >> shift) & 31),
  ]);
  return sender == null ? 'mc:$token' : 'mc:$token:$sender';
}

final _channelReaction = RegExp(r'^@\[([^\[\]\r\n]+)\](.+)$');
final _legacyChannelReaction = RegExp(r'^(.+)@\[([^\[\]\r\n]+)\]$');

({String target, String emoji})? readMeshCoreReaction(
  String body, {
  required bool channel,
}) {
  final lines = body.split('\n');
  if (lines.length != 2) return null;
  final hash = lines[1]
      .toLowerCase()
      .replaceAll('o', '0')
      .replaceAll(RegExp('[il]'), '1');
  if (!_hashPattern.hasMatch(hash)) return null;
  final line = lines[0];
  if (!channel) {
    return _isEmoji(line) ? (target: 'mc:$hash', emoji: line) : null;
  }
  final current = _channelReaction.firstMatch(line);
  final legacy = current == null
      ? _legacyChannelReaction.firstMatch(line)
      : null;
  final name = current?[1] ?? legacy?[2];
  final emoji = current?[2] ?? legacy?[1];
  if (name == null || emoji == null || !_isEmoji(emoji)) return null;
  return (target: 'mc:$hash:$name', emoji: emoji);
}

String meshCoreReactionText(
  String reference,
  String emoji, {
  required bool channel,
}) {
  if (!reference.startsWith('mc:') || !_isEmoji(emoji)) {
    throw const FormatException('Invalid MeshCore reaction');
  }
  final separator = reference.indexOf(':', 3);
  final hash = reference.substring(3, separator < 0 ? null : separator);
  final name = separator < 0 ? null : reference.substring(separator + 1);
  if (!_hashPattern.hasMatch(hash) ||
      channel != (name != null) ||
      (name != null && !_senderPattern.hasMatch(name))) {
    throw const FormatException('Invalid MeshCore reaction target');
  }
  return name == null ? '$emoji\n$hash' : '@[$name]$emoji\n$hash';
}
