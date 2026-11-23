// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'emoji_text.dart';
import 'message_link_metadata.dart';
import 'style.dart';

final _webLink = RegExp(
  // Explicit HTTP(S) and bare domains. Exclude URLs inside emails/other schemes.
  // ignore: valid_regexps
  r'(?<![\p{L}\p{N}_@.:/\-])(?:https?://[^\s<>"“”«»]+|(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:[a-z]{2,63}|xn--[a-z0-9-]+)(?::[0-9]{1,5})?(?:[/?#][^\s<>"“”«»]*)?(?![a-z0-9_-]))',
  caseSensitive: false,
  unicode: true,
);

final _trailingPunctuation = RegExp(r'''[.!?,;:'’…。！？]''');
const _closingPunctuation = {')': '(', ']': '[', '}': '{'};

String _stripTrailingPunctuation(String text) {
  var end = text.length;
  while (end > 0) {
    final last = text[end - 1];
    if (_trailingPunctuation.hasMatch(last)) {
      end--;
      continue;
    }
    final opening = _closingPunctuation[last];
    if (opening != null) {
      var depth = 0;
      for (var i = 0; i < end; i++) {
        if (text[i] == opening) depth++;
        if (text[i] == last) depth--;
      }
      if (depth < 0) {
        end--;
        continue;
      }
    }
    break;
  }
  return text.substring(0, end);
}

Iterable<({int start, int end, Uri uri})> _messageLinks(String text) sync* {
  for (final match in _webLink.allMatches(text)) {
    final display = _stripTrailingPunctuation(match[0]!);
    if (display.isEmpty) continue;
    final candidate = display.contains('://') ? display : 'https://$display';
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port <= 0 ||
        uri.port > 65535) {
      continue;
    }
    yield (start: match.start, end: match.start + display.length, uri: uri);
  }
}

Uri? firstMessageLink(String text) => _messageLinks(text).firstOrNull?.uri;

Future<void> _openMessageLink(BuildContext context, Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } on PlatformException {
    // On a device without a compatible handler, leave the message in place.
  }
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        tr(context, 'Не удалось открыть ссылку', 'Could not open the link'),
      ),
    ),
  );
}

class MessageLinkifiedText extends StatefulWidget {
  const MessageLinkifiedText({
    super.key,
    required this.text,
    required this.style,
    required this.linkColor,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final Color linkColor;
  final TextAlign? textAlign;

  @override
  State<MessageLinkifiedText> createState() => _MessageLinkifiedTextState();
}

class _MessageLinkifiedTextState extends State<MessageLinkifiedText> {
  final _links = <({int start, int end, TapGestureRecognizer tap})>[];

  @override
  void initState() {
    super.initState();
    _updateLinks();
  }

  @override
  void didUpdateWidget(MessageLinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _updateLinks();
  }

  void _disposeLinks() {
    for (final link in _links) {
      link.tap.dispose();
    }
    _links.clear();
  }

  void _updateLinks() {
    _disposeLinks();
    for (final link in _messageLinks(widget.text)) {
      _links.add((
        start: link.start,
        end: link.end,
        tap: TapGestureRecognizer()
          ..onTap = () => _openMessageLink(context, link.uri),
      ));
    }
  }

  @override
  void dispose() {
    _disposeLinks();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (_links.isEmpty) {
      return EmojiText(text, style: widget.style, textAlign: widget.textAlign);
    }

    final linkStyle = TextStyle(
      color: widget.linkColor,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor,
    );
    final spans = <InlineSpan>[];
    var start = 0;
    for (final link in _links) {
      if (link.start > start) {
        spans.add(emojiTextSpan(text.substring(start, link.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(link.start, link.end),
          style: linkStyle,
          recognizer: link.tap,
          mouseCursor: SystemMouseCursors.click,
        ),
      );
      start = link.end;
    }
    if (start < text.length) spans.add(emojiTextSpan(text.substring(start)));
    return Text.rich(
      TextSpan(children: spans),
      style: widget.style,
      textAlign: widget.textAlign,
    );
  }
}

/// Fetched content is shared with the message after sending and kept in memory.
final _previewCache = <Uri, Future<MessageLinkMetadata?>>{};

class MessageLinkPreview extends StatefulWidget {
  const MessageLinkPreview({
    super.key,
    required this.uri,
    this.compact = false,
    this.foreground,
    this.onDismiss,
  });

  final Uri uri;
  final bool compact;
  final Color? foreground;
  final VoidCallback? onDismiss;

  @override
  State<MessageLinkPreview> createState() => _MessageLinkPreviewState();
}

class _MessageLinkPreviewState extends State<MessageLinkPreview> {
  Uri get _cacheKey => widget.uri.removeFragment();

  void _requestPreview() {
    final key = _cacheKey;
    setState(() {
      final future = fetchMessageLinkMetadata(key);
      _previewCache.remove(key);
      _previewCache[key] = future;
      if (_previewCache.length > 24) {
        _previewCache.remove(_previewCache.keys.first);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MessageLinkMetadata?>(
      key: ValueKey(_cacheKey),
      future: _previewCache[_cacheKey],
      builder: (context, snapshot) => _card(context, snapshot),
    );
  }

  Widget _card(
    BuildContext context,
    AsyncSnapshot<MessageLinkMetadata?> snapshot,
  ) {
    final theme = MeshStyle.of(context);
    final foreground = widget.foreground ?? theme.text;
    final metadata = snapshot.data;
    final compact = widget.compact;
    final uri = widget.uri;
    final fetching = snapshot.connectionState == ConnectionState.waiting;
    final mayFetch = canFetchMessageLink(uri);
    final failed =
        snapshot.connectionState == ConnectionState.done && metadata == null;
    final title = metadata?.title ?? uri.host;
    final subtitle =
        metadata?.description ??
        (failed
            ? tr(context, 'Сайт не предоставил описание', 'Preview unavailable')
            : uri.toString());
    final radius = BorderRadius.circular(12);

    return Material(
      color: foreground.withValues(alpha: .075),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _openMessageLink(context, uri),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compact) ...[
                      if (metadata?.image case final image?)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: Image.memory(
                            image,
                            width: 43,
                            height: 43,
                            fit: BoxFit.cover,
                            cacheWidth: 128,
                            cacheHeight: 128,
                            errorBuilder: (_, _, _) =>
                                Icon(Icons.language_rounded, color: foreground),
                          ),
                        )
                      else
                        Icon(
                          Icons.language_rounded,
                          color: foreground,
                          size: 22,
                        ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (metadata?.title != null && !compact)
                            Text(
                              uri.host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground.withValues(alpha: .8),
                                fontSize: 11,
                              ),
                            ),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (subtitle != title)
                            Text(
                              subtitle,
                              maxLines: compact ? 1 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground.withValues(alpha: .85),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (fetching)
            Padding(
              padding: const EdgeInsets.all(10),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              ),
            )
          else if (mayFetch && metadata == null)
            IconButton(
              tooltip: failed
                  ? tr(context, 'Повторить загрузку с сайта', 'Retry from site')
                  : tr(
                      context,
                      'Загрузить предпросмотр с сайта',
                      'Load preview from site',
                    ),
              onPressed: _requestPreview,
              color: foreground,
              icon: Icon(
                failed ? Icons.refresh_rounded : Icons.cloud_download_outlined,
              ),
            ),
          if (widget.onDismiss case final dismiss?)
            IconButton(
              tooltip: tr(context, 'Убрать предпросмотр', 'Remove preview'),
              onPressed: dismiss,
              color: foreground,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
        ],
      ),
    );
  }
}
