// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'network.dart';

const routeTraceNoticeDelay = Duration(seconds: 30);

class RouteTrace {
  const RouteTrace({
    required this.request,
    required this.peer,
    required this.sentAt,
    this.receivedAt,
    this.fields = const [],
    this.failure,
  });

  final int request;
  final String peer;
  final DateTime sentAt;
  final DateTime? receivedAt;
  final List<RadioField> fields;
  final RouteTraceFailure? failure;

  bool get pending => receivedAt == null && failure == null;
  bool isWaitingAt(DateTime now) =>
      pending && now.isBefore(sentAt.add(routeTraceNoticeDelay));
  bool get arrivedLate =>
      receivedAt?.isBefore(sentAt.add(routeTraceNoticeDelay)) == false;

  RouteTrace received(List<RadioField> fields, DateTime now) => RouteTrace(
    request: request,
    peer: peer,
    sentAt: sentAt,
    receivedAt: receivedAt ?? now,
    fields: fields,
  );

  RouteTrace rejected(RouteTraceFailure failure) => RouteTrace(
    request: request,
    peer: peer,
    sentAt: sentAt,
    failure: failure,
  );

  Map<String, Object> toJson() => {
    'request': request,
    'peer': peer,
    'sentAt': sentAt.millisecondsSinceEpoch,
    'receivedAt': ?receivedAt?.millisecondsSinceEpoch,
    'failure': ?failure?.name,
    'fields': [
      for (final field in fields)
        [
          field.id,
          field.title,
          field.russian,
          field.value,
          [
            for (final hop in field.hops) [hop.name, hop.snr, hop.rssi],
          ],
        ],
    ],
  };

  factory RouteTrace.fromJson(Map json) => RouteTrace(
    request: json['request'] as int,
    peer: json['peer'] as String,
    sentAt: DateTime.fromMillisecondsSinceEpoch(json['sentAt'] as int),
    receivedAt: json['receivedAt'] is int
        ? DateTime.fromMillisecondsSinceEpoch(json['receivedAt'] as int)
        : null,
    failure: RouteTraceFailure.values.asNameMap()[json['failure']],
    fields: [
      for (final field in json['fields'] as List)
        RadioField(
          field[0] as String,
          field[1] as String,
          field[2] as String,
          field[3] as String,
          hops: [
            for (final hop in field[4] as List)
              (
                name: hop[0] as String,
                snr: (hop[1] as num?)?.toDouble(),
                rssi: hop[2] as int?,
              ),
          ],
          editable: false,
        ),
    ],
  );
}
