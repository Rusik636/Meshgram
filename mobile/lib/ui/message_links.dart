// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'emoji_text.dart';
import 'message_link_metadata.dart';
import 'style.dart';

const _webProtocol = r'(https?|htps?|ttps?|httpps?)(?::[\\/]*|[\\/]+)';
const _bareDomain =
    r'(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:[a-z]{2,63}|xn--[a-z0-9-]+)(?::[0-9]{1,5})?(?:[/?#][^\s<>"“”«»]*)?(?![a-z0-9_-])';
final _leadingProtocol = RegExp('(?:$_webProtocol)+', caseSensitive: false);
final _webLink = RegExp(
  // Exclude URLs inside emails or other schemes. Recover common HTTP typos.
  // ignore: valid_regexps
  r'(?<![\p{L}\p{N}_@.:/\\\-])'
  '(?:'
  '(?:$_webProtocol)+'
  r'[^\s<>"“”«»]+|'
  '(?://)?$_bareDomain)',
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
    final prefix = _leadingProtocol.matchAsPrefix(display);
    final scheme = prefix?.group(1)?.toLowerCase().endsWith('s') == false
        ? 'http'
        : 'https';
    final start = prefix?.end ?? (display.startsWith('//') ? 2 : 0);
    final uri = Uri.tryParse('$scheme://${display.substring(start)}');
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

typedef _LoadLinkMetadata = Future<MessageLinkMetadata?> Function(Uri);

/// Drafts and their sent messages share results. Keep scrolling multiple
/// messages from opening an unbounded number of connections at once.
final _previewCache = _MessageLinkPreviewCache();

class _PendingLinkPreview {
  final result = Completer<MessageLinkMetadata?>();
  final owners = <Object, bool Function()>{};
}

class _MessageLinkPreviewCache {
  final _queue = Queue<Future<void> Function()>();
  final _pending = <Uri, _PendingLinkPreview>{};
  final _completed =
      <Uri, ({Future<MessageLinkMetadata?> preview, DateTime? retryAfter})>{};
  int _active = 0;

  Future<MessageLinkMetadata?>? lookup(Uri uri) {
    final cached = _completed.remove(uri);
    if (cached == null) return null;
    if (cached.retryAfter?.isBefore(DateTime.now()) == true) return null;
    _completed[uri] = cached;
    return cached.preview;
  }

  Future<MessageLinkMetadata?> request(
    Uri uri,
    _LoadLinkMetadata loader, {
    required Object owner,
    required bool Function() ownerIsVisible,
    bool retry = false,
  }) {
    if (_pending[uri] case final pending?) {
      pending.owners[owner] = ownerIsVisible;
      return pending.result.future;
    }
    if (!retry) {
      if (lookup(uri) case final cached?) return cached;
    }
    final pending = _PendingLinkPreview()..owners[owner] = ownerIsVisible;
    _pending[uri] = pending;
    _queue.add(() async {
      final visible = pending.owners.values.any((isVisible) => isVisible());
      pending.owners.clear();
      if (!visible) {
        _pending.remove(uri);
        pending.result.complete(null);
        return;
      }
      MessageLinkMetadata? metadata;
      try {
        metadata = await loader(uri);
      } on Exception {
        // An unavailable preview leaves the link itself usable.
      } finally {
        _pending.remove(uri);
        _completed.remove(uri);
        _completed[uri] = (
          preview: pending.result.future,
          retryAfter: metadata == null
              ? DateTime.now().add(const Duration(minutes: 1))
              : null,
        );
        if (_completed.length > 24) {
          _completed.remove(_completed.keys.first);
        }
        pending.result.complete(metadata);
      }
    });
    _startQueued();
    return pending.result.future;
  }

  void _startQueued() {
    while (_active < 3 && _queue.isNotEmpty) {
      _active++;
      unawaited(
        _queue.removeFirst()().whenComplete(() {
          _active--;
          _startQueued();
        }),
      );
    }
  }
}

class MessageLinkPreview extends StatefulWidget {
  const MessageLinkPreview({
    super.key,
    required this.uri,
    this.compact = false,
    this.autoLoad = true,
    this.foreground,
    this.onDismiss,
    this.loadMetadata = fetchMessageLinkMetadata,
  });

  final Uri uri;
  final bool compact;
  final bool autoLoad;
  final Color? foreground;
  final VoidCallback? onDismiss;
  final Future<MessageLinkMetadata?> Function(Uri) loadMetadata;

  @override
  State<MessageLinkPreview> createState() => _MessageLinkPreviewState();
}

class _MessageLinkPreviewState extends State<MessageLinkPreview> {
  static const _draftDebounce = Duration(milliseconds: 500);

  Timer? _draftTimer;
  ModalRoute<dynamic>? _route;
  Future<MessageLinkMetadata?>? _preview;
  bool get _canAutoLoad => widget.autoLoad && (_route?.isCurrent ?? true);

  Uri get _cacheKey {
    final uri = widget.uri.removeFragment();
    return uri.path.isEmpty ? uri.replace(path: '/') : uri;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _loadPreview();
  }

  @override
  void didUpdateWidget(MessageLinkPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        oldWidget.compact != widget.compact ||
        oldWidget.autoLoad != widget.autoLoad) {
      _loadPreview();
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    super.dispose();
  }

  void _loadPreview() {
    _draftTimer?.cancel();
    final key = _cacheKey;
    _preview = _previewCache.lookup(key);
    if (_preview != null || !_canAutoLoad || !canFetchMessageLink(key)) {
      return;
    }
    if (widget.compact) {
      _draftTimer = Timer(_draftDebounce, () {
        final preview = _request(key);
        setState(() {
          _preview = preview;
        });
      });
    } else {
      _preview = _request(key);
    }
  }

  Future<MessageLinkMetadata?> _request(Uri key, {bool retry = false}) =>
      _previewCache.request(
        key,
        widget.loadMetadata,
        owner: this,
        ownerIsVisible: () {
          final lifecycle = WidgetsBinding.instance.lifecycleState;
          return mounted &&
              _cacheKey == key &&
              _canAutoLoad &&
              (lifecycle == null || lifecycle == AppLifecycleState.resumed);
        },
        retry: retry,
      );

  void _retryPreview() {
    final preview = _request(_cacheKey, retry: true);
    setState(() {
      _preview = preview;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MessageLinkMetadata?>(
      key: ValueKey(_cacheKey),
      future: _preview,
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
          else if (mayFetch && failed && _canAutoLoad)
            IconButton(
              tooltip: tr(
                context,
                'Повторить загрузку с сайта',
                'Retry from site',
              ),
              onPressed: _retryPreview,
              color: foreground,
              icon: const Icon(Icons.refresh_rounded),
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
