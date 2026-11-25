// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'nodes.dart';

const _decimal = r'[-+]?\d{1,3}(?:\.\d+)?';
final _coordinatePair = RegExp('^($_decimal)\\s*[,;]\\s*($_decimal)\$');
final _decimalPair = RegExp(
  r'([-+]?\d{1,3}\.\d+)\s*[,; ]\s*([-+]?\d{1,3}\.\d+)',
);
final _geoPair = RegExp(
  '^geo:($_decimal),($_decimal)(?=\$|[;?])',
  caseSensitive: false,
);
final _webLink = RegExp(r'https?://[^\s<>]+', caseSensitive: false);
final _trailingUrlPunctuation = RegExp(r'[.!?\])}]+$');

({NodePosition point, bool standalone})? chatPosition(String text) {
  final input = text.trim();
  if (input.isEmpty) return null;
  final geo = _geoPair.firstMatch(input);
  if (geo != null && !input.contains(RegExp(r'\s'))) {
    final point = _valid(geo[1], geo[2]);
    return point == null ? null : (point: point, standalone: true);
  }
  final pair = _coordinatePair.firstMatch(input);
  if (pair != null) {
    final point = _valid(pair[1], pair[2]);
    return point == null ? null : (point: point, standalone: true);
  }
  final links = _webLink.allMatches(input).toList();
  for (final link in links) {
    final raw = link[0]!.replaceFirst(_trailingUrlPunctuation, '');
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.userInfo.isNotEmpty) continue;
    final point = _mapLink(uri);
    if (point != null) return (point: point, standalone: false);
  }
  for (final match in _decimalPair.allMatches(input)) {
    if (links.any((link) => match.start < link.end && match.end > link.start)) {
      continue;
    }
    if (match.start > 0 &&
        RegExp(r'[\w.+:/-]').hasMatch(input[match.start - 1])) {
      continue;
    }
    if (match.end < input.length &&
        RegExp(r'[\w.+/-]').hasMatch(input[match.end])) {
      continue;
    }
    final point = _valid(match[1], match[2]);
    if (point != null) return (point: point, standalone: false);
  }
  return null;
}

NodePosition? _mapLink(Uri uri) {
  try {
    final params = uri.queryParameters;
    final String? pair;
    switch (uri.host) {
      case 'maps.apple.com':
        pair = params['ll'] ?? params['coordinate'] ?? params['q'];
      case 'maps.google.com':
      case 'www.google.com':
      case 'google.com':
        if (uri.host != 'maps.google.com' && !uri.path.startsWith('/maps')) {
          return null;
        }
        final at = uri.pathSegments.where((segment) => segment.startsWith('@'));
        pair =
            params['query'] ??
            params['q'] ??
            (at.isEmpty ? null : at.first.substring(1));
      case 'openstreetmap.org':
      case 'www.openstreetmap.org':
        final marker = _valid(params['mlat'], params['mlon']);
        if (marker != null) return marker;
        final parts = uri.fragment.split('/');
        return parts.length == 3 && parts.first.startsWith('map=')
            ? _valid(parts[1], parts[2])
            : null;
      default:
        return null;
    }
    final parts = pair?.split(',');
    return parts == null || parts.length < 2
        ? null
        : _valid(parts[0].trim(), parts[1].trim());
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

NodePosition? _valid(String? lat, String? lon) {
  if (lat == null || lon == null) return null;
  final latitude = double.tryParse(lat);
  final longitude = double.tryParse(lon);
  if (latitude == null ||
      longitude == null ||
      latitude.abs() > 90 ||
      longitude.abs() > 180 ||
      !latitude.isFinite ||
      !longitude.isFinite) {
    return null;
  }
  return (latitude: latitude, longitude: longitude);
}
