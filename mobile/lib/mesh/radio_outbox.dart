// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'network.dart';

enum OutboxStatus { waiting, sending, uncertain }

class OutboxMessage {
  const OutboxMessage({
    required this.id,
    required this.profile,
    required this.chat,
    required this.text,
    this.createdAt,
    this.status = OutboxStatus.waiting,
    this.attemptId,
    this.replyTo,
    this.replyExcerpt,
    this.suppressLinkPreview = false,
  });

  final String id, profile, chat, text;
  final DateTime? createdAt;
  final OutboxStatus status;
  final String? attemptId, replyTo;
  final MessageExcerpt? replyExcerpt;
  final bool suppressLinkPreview;

  OutboxMessage withChanges({
    String? text,
    OutboxStatus? status,
    String? attemptId,
  }) => OutboxMessage(
    id: id,
    profile: profile,
    chat: chat,
    text: text ?? this.text,
    createdAt: createdAt,
    status: status ?? this.status,
    attemptId: attemptId ?? this.attemptId,
    replyTo: replyTo,
    replyExcerpt: replyExcerpt,
    suppressLinkPreview: suppressLinkPreview,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'profile': profile,
    'chat': chat,
    'text': text,
    'createdAt': ?createdAt?.millisecondsSinceEpoch,
    'status': status.name,
    'attemptId': ?attemptId,
    'replyTo': ?replyTo,
    'replyExcerpt': ?replyExcerpt?.toJson(),
    if (suppressLinkPreview) 'suppressLinkPreview': true,
  };

  static OutboxMessage? decode(Object? json) {
    if (json is! Map) return null;
    if (json case {
      'id': final String id,
      'profile': final String profile,
      'chat': final String chat,
      'text': final String text,
      'status': final String status,
    }) {
      final state = OutboxStatus.values
          .where((value) => value.name == status)
          .firstOrNull;
      return OutboxMessage(
        id: id,
        profile: profile,
        chat: chat,
        text: text,
        createdAt: switch (json['createdAt']) {
          final int timestamp => DateTime.fromMillisecondsSinceEpoch(timestamp),
          _ => null,
        },
        status: state == OutboxStatus.waiting
            ? OutboxStatus.waiting
            : OutboxStatus.uncertain,
        attemptId: json['attemptId'] as String?,
        replyTo: json['replyTo'] as String?,
        replyExcerpt: MessageExcerpt.decode(json['replyExcerpt']),
        suppressLinkPreview: json['suppressLinkPreview'] == true,
      );
    }
    return null;
  }
}
