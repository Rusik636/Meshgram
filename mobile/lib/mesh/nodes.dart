// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:math';

const nodeOnlineWindow = Duration(hours: 1);

enum MeshNodeRole { client, repeater, room, sensor, tracker, router, gateway }

enum NodeSort {
  activity,
  name,
  messages,
  distance,
  hops,
  channel,
  mqtt,
  favorite,
}

abstract interface class NetworkNodeSorting {
  List<NodeSort> get additionalNodeSorts;
}

typedef NodePosition = ({double latitude, double longitude});

NodePosition? nodePosition(double latitude, double longitude) =>
    latitude.abs() <= 90 &&
        longitude.abs() <= 180 &&
        (latitude != 0 || longitude != 0)
    ? (latitude: latitude, longitude: longitude)
    : null;

double nodeDistance(NodePosition from, NodePosition to) {
  const radians = pi / 180;
  final latitude = (to.latitude - from.latitude) * radians / 2;
  final longitude = (to.longitude - from.longitude) * radians / 2;
  final a =
      pow(sin(latitude), 2) +
      cos(from.latitude * radians) *
          cos(to.latitude * radians) *
          pow(sin(longitude), 2);
  return 12742000 * asin(sqrt(a.clamp(0, 1)));
}

DateTime? nodeTimeFromSeconds(int seconds) => seconds > 0
    ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
    : null;

bool nodeIsOnline(DateTime? lastSeen, DateTime now) =>
    lastSeen != null &&
    !lastSeen.isAfter(now) &&
    now.isBefore(lastSeen.add(nodeOnlineWindow));

class NodeObservation {
  const NodeObservation({
    this.lastSeen,
    this.position,
    this.hops,
    this.channel,
    this.viaMqtt,
    this.favorite,
    this.ignored,
    this.role,
    this.canMessage,
    this.boardModel,
  });

  final DateTime? lastSeen;
  final NodePosition? position;
  final int? hops, channel, boardModel;
  final bool? viaMqtt, favorite, ignored;
  final MeshNodeRole? role;
  final bool? canMessage;

  NodeObservation merge(NodeObservation update, DateTime now) {
    final stamp = update.lastSeen;
    // A stale snapshot can fill missing metrics without replacing current data.
    final accepted =
        stamp != null &&
        stamp.year >= 2000 &&
        !stamp.isAfter(now.add(const Duration(minutes: 2)));
    final updatedAt = accepted && stamp.isAfter(now) ? now : stamp;
    final current = lastSeen;
    final newer =
        accepted && (current == null || !updatedAt!.isBefore(current));
    return NodeObservation(
      lastSeen: newer ? updatedAt : current,
      position: newer
          ? update.position ?? position
          : position ?? update.position,
      hops: newer ? update.hops ?? hops : hops ?? update.hops,
      channel: update.channel ?? channel,
      viaMqtt: newer ? update.viaMqtt ?? viaMqtt : viaMqtt ?? update.viaMqtt,
      favorite: update.favorite ?? favorite,
      ignored: update.ignored ?? ignored,
      role: update.role ?? role,
      canMessage: update.canMessage ?? canMessage,
      boardModel: update.boardModel ?? boardModel,
    );
  }

  Map<String, Object> toJson() => {
    'seen': ?lastSeen?.millisecondsSinceEpoch,
    if (position case final value?)
      'position': [value.latitude, value.longitude],
    'hops': ?hops,
    'channel': ?channel,
    'mqtt': ?viaMqtt,
    'favorite': ?favorite,
    'ignored': ?ignored,
    'role': ?role?.name,
    'canMessage': ?canMessage,
    'boardModel': ?boardModel,
  };

  factory NodeObservation.fromJson(Map json) {
    final stamp = json['seen'] as int?;
    final xy = json['position'] as List?;
    return NodeObservation(
      lastSeen: stamp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(stamp, isUtc: true),
      position: xy == null
          ? null
          : nodePosition((xy[0] as num).toDouble(), (xy[1] as num).toDouble()),
      hops: json['hops'] as int?,
      channel: json['channel'] as int?,
      viaMqtt: json['mqtt'] as bool?,
      favorite: json['favorite'] as bool?,
      ignored: json['ignored'] as bool?,
      canMessage: json['canMessage'] as bool?,
      boardModel: json['boardModel'] as int?,
      role: MeshNodeRole.values
          .where((role) => role.name == json['role'])
          .firstOrNull,
    );
  }
}
