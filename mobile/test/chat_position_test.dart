// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/chat_position.dart';

void main() {
  const point = (latitude: 55.725, longitude: 52.401);

  test('geo URI is a standalone location message', () {
    for (final message in [
      'geo:55.725,52.401',
      ' Geo:55.725,52.401;u=10 ',
      'geo:55.725,52.401?q=meeting',
    ]) {
      expect(chatPosition(message), (
        point: point,
        standalone: true,
      ), reason: message);
    }
  });

  test('text containing coordinates keeps the original message', () {
    expect(chatPosition('Встречаемся у 55.725, 52.401'), (
      point: point,
      standalone: false,
    ));
  });

  test('a bare coordinate pair is a standalone location message', () {
    expect(chatPosition('51.5, -0.12'), (
      point: (latitude: 51.5, longitude: -.12),
      standalone: true,
    ));
    expect(chatPosition('55.725; -52.401'), (
      point: (latitude: 55.725, longitude: -52.401),
      standalone: true,
    ));
  });

  test('recognizes coordinate URLs from common map providers', () {
    for (final url in [
      'https://maps.apple.com/?ll=55.725%2C52.401',
      'https://maps.google.com/?q=55.725,52.401',
      'https://www.google.com/maps/search/?api=1&query=55.725%2C52.401',
      'https://www.google.com/maps/@55.725,52.401,16z',
      'https://www.openstreetmap.org/?mlat=55.725&mlon=52.401',
      'https://www.openstreetmap.org/#map=16/55.725/52.401',
    ]) {
      expect(chatPosition('Точка встречи ($url).'), (
        point: point,
        standalone: false,
      ), reason: url);
    }
  });

  test('preserves legitimate zero and boundary coordinates', () {
    const zero = (latitude: 0.0, longitude: 0.0);
    expect(chatPosition('geo:0,0'), (point: zero, standalone: true));
    expect(chatPosition('0, 0'), (point: zero, standalone: true));
    expect(chatPosition('geo:-90,180'), (
      point: (latitude: -90.0, longitude: 180.0),
      standalone: true,
    ));
  });

  test('rejects incomplete, non-finite and out-of-range coordinates', () {
    for (final input in [
      '',
      'geo:NaN,52.401',
      'geo:55.725,Infinity',
      'geo:55.725,',
      'geo:91,52.401',
      'geo:55.725,181',
      '91.123; 52.401',
      '55.725, -181.00',
      'Coordinates will follow.',
      'https://www.google.com/search?q=meeting',
      'https://example.org/?value=55.725,52.401',
    ]) {
      expect(chatPosition(input), isNull, reason: input);
    }
  });
}
