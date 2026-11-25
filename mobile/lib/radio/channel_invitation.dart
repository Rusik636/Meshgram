// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';

import 'package:protobuf/protobuf.dart';

import 'channel_keys.dart';

typedef ChannelInvitation = ({String network, String? name, String link});

({String name, List<int> key}) readMeshCoreChannelInvitation(Uri uri) {
  if (uri.scheme != 'meshcore' ||
      uri.host != 'channel' ||
      uri.path != '/add' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasFragment) {
    throw const FormatException('channel-invite');
  }
  final parameters = uri.queryParameters;
  if (parameters['region_scope']?.isNotEmpty == true) {
    throw const FormatException('channel-scope');
  }
  final name = parameters['name']?.trim() ?? '';
  channelNameBytes(name, 31);
  return (name: name, key: parseChannelKey(parameters['secret'] ?? '', {16}));
}

UnknownFieldSet readMeshtasticChannelInvitation(Uri uri) {
  if (uri.scheme != 'https' ||
      !const {'meshtastic.org', 'www.meshtastic.org'}.contains(uri.host) ||
      !const {'/e/', '/e'}.contains(uri.path) ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.fragment.isEmpty ||
      uri.fragment.length > 8000) {
    throw const FormatException('channel-invite');
  }
  return UnknownFieldSet()..mergeFromCodedBufferReader(
    CodedBufferReader(base64Url.decode(base64Url.normalize(uri.fragment))),
  );
}

ChannelInvitation? channelInvitation(String link) {
  if (link.length > 8192) return null;
  final uri = Uri.tryParse(link);
  if (uri == null) return null;
  try {
    if (uri.scheme == 'meshcore' && uri.host == 'channel') {
      final invite = readMeshCoreChannelInvitation(uri);
      return (network: 'meshcore', name: invite.name, link: link);
    }
    if (uri.scheme == 'https' &&
        const {'meshtastic.org', 'www.meshtastic.org'}.contains(uri.host) &&
        const {'/e/', '/e'}.contains(uri.path)) {
      final invite = readMeshtasticChannelInvitation(uri);
      final channels = invite.getField(1)?.lengthDelimited ?? const [];
      if (channels.isEmpty) return null;
      String? name;
      for (final channel in channels) {
        final fields = UnknownFieldSet()
          ..mergeFromCodedBufferReader(CodedBufferReader(channel));
        final keyLength =
            fields.getField(2)?.lengthDelimited.firstOrNull?.length ?? 0;
        if (!const {0, 1, 16, 32}.contains(keyLength)) return null;
        final stored = fields.getField(3)?.lengthDelimited.firstOrNull;
        if (stored != null && stored.isNotEmpty) {
          final title = utf8.decode(stored);
          if (title.toLowerCase() == 'admin') return null;
          channelNameBytes(title, 11);
          name ??= title;
        }
      }
      return (network: 'meshtastic', name: name, link: link);
    }
  } on FormatException {
    return null;
  } on InvalidProtocolBufferException {
    return null;
  }
  return null;
}
