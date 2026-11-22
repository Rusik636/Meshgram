import 'dart:convert';
import 'dart:math';

List<int> createChannelKey(int length) {
  final random = Random.secure();
  return List.generate(length, (_) => random.nextInt(256));
}

List<int> parseChannelKey(String input, Set<int> lengths) {
  final text = input.trim();
  if (text.isEmpty || text.length > 128) {
    throw const FormatException('channel-key');
  }
  try {
    final List<int> key;
    if (lengths.contains(text.length ~/ 2) &&
        text.length.isEven &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(text)) {
      key = [
        for (var i = 0; i < text.length; i += 2)
          int.parse(text.substring(i, i + 2), radix: 16),
      ];
    } else {
      key = base64Url.decode(base64Url.normalize(text));
    }
    if (lengths.contains(key.length) && key.any((byte) => byte != 0)) {
      return key;
    }
  } on FormatException {
    throw const FormatException('channel-key');
  }
  throw const FormatException('channel-key');
}

List<int> channelNameBytes(String name, int maximum) {
  final bytes = utf8.encode(name);
  if (bytes.isEmpty ||
      bytes.length > maximum ||
      name.runes.any((rune) => rune < 32 || rune == 127)) {
    throw const FormatException('channel-name');
  }
  return bytes;
}

bool sameChannelKey(List<int> first, List<int> second) =>
    first.length == second.length &&
    Iterable<int>.generate(first.length).every((i) => first[i] == second[i]);
