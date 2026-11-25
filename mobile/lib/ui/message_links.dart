// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'emoji_text.dart';
import 'message_link_cache.dart';
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

final _nativeMeshLink = RegExp(
  r'(?<![\p{L}\p{N}_@.:/\-])(?:meshgram|meshcore|meshtastic):[^\s<>"“”«»]+',
  caseSensitive: false,
  unicode: true,
);

Iterable<({int start, String source, String link})> meshLinksInMessage(
  String text,
) sync* {
  final matches = [
    for (final match in _nativeMeshLink.allMatches(text))
      (
        start: match.start,
        source: _stripTrailingPunctuation(match[0]!),
        link: _stripTrailingPunctuation(match[0]!),
      ),
    for (final match in _messageLinks(text))
      if (const {
        'meshtastic.org',
        'www.meshtastic.org',
      }.contains(match.uri.host))
        (
          start: match.start,
          source: text.substring(match.start, match.end),
          link: match.uri.toString(),
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  for (final match in matches) {
    yield (start: match.start, source: match.source, link: match.link);
  }
}

Future<void> openMessageLink(BuildContext context, Uri uri) async {
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
    this.highlight,
  });

  final String text;
  final TextStyle style;
  final Color linkColor;
  final TextAlign? textAlign;
  final ({TextRange range, Color color})? highlight;

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
          ..onTap = () => openMessageLink(context, link.uri),
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
    final highlight = widget.highlight;
    if (_links.isEmpty && highlight == null) {
      return EmojiText(text, style: widget.style, textAlign: widget.textAlign);
    }

    final linkStyle = TextStyle(
      color: widget.linkColor,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor,
    );
    final spans = <InlineSpan>[];
    void span(int start, int end, [TapGestureRecognizer? tap]) {
      if (start >= end) return;
      void add(int from, int to, Color? color) {
        if (from >= to) return;
        final content = text.substring(from, to);
        if (tap == null) {
          spans.add(
            emojiTextSpan(content, style: TextStyle(backgroundColor: color)),
          );
        } else {
          spans.add(
            TextSpan(
              text: content,
              style: linkStyle.copyWith(backgroundColor: color),
              recognizer: tap,
              mouseCursor: SystemMouseCursors.click,
            ),
          );
        }
      }

      if (highlight == null ||
          highlight.range.end <= start ||
          highlight.range.start >= end) {
        add(start, end, null);
        return;
      }
      final from = highlight.range.start.clamp(start, end);
      final to = highlight.range.end.clamp(start, end);
      add(start, from, null);
      add(from, to, highlight.color);
      add(to, end, null);
    }

    var start = 0;
    for (final link in _links) {
      span(start, link.start);
      span(link.start, link.end, link.tap);
      start = link.end;
    }
    span(start, text.length);
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
      <Uri, ({MessageLinkMetadata? metadata, DateTime? retryAfter})>{};
  int _active = 0;

  ({MessageLinkMetadata? metadata, DateTime? retryAfter})? lookup(Uri uri) {
    final cached = _completed.remove(uri);
    if (cached == null) return null;
    if (cached.retryAfter?.isBefore(DateTime.now()) == true) return null;
    _completed[uri] = cached;
    return cached;
  }

  Future<MessageLinkMetadata?> request(
    Uri uri,
    _LoadLinkMetadata loader, {
    required Object owner,
    required bool Function() ownerIsVisible,
  }) {
    if (_pending[uri] case final pending?) {
      pending.owners[owner] = ownerIsVisible;
      return pending.result.future;
    }
    if (lookup(uri) case final cached?) return Future.value(cached.metadata);
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
          metadata: metadata,
          retryAfter: metadata?.image == null
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

typedef DraftLinkPreview = ({String title, String text, Uint8List? image});

class MessageLinkPreview extends StatefulWidget {
  const MessageLinkPreview({
    super.key,
    required this.uri,
    this.compact = false,
    this.autoLoad = true,
    this.foreground,
    this.onDismiss,
    this.builder,
    this.draftBuilder,
    this.loadMetadata = loadMessageLinkPreview,
  }) : assert(draftBuilder == null || compact);

  final Uri uri;
  final bool compact;
  final bool autoLoad;
  final Color? foreground;
  final VoidCallback? onDismiss;
  final Widget Function(Widget? card)? builder;
  final Widget Function(DraftLinkPreview?)? draftBuilder;
  final Future<MessageLinkMetadata?> Function(Uri) loadMetadata;

  @override
  State<MessageLinkPreview> createState() => _MessageLinkPreviewState();
}

class _MessageLinkPreviewState extends State<MessageLinkPreview> {
  static const _draftDebounce = Duration(milliseconds: 500);

  Timer? _draftTimer;
  ModalRoute<dynamic>? _route;
  Future<MessageLinkMetadata?>? _preview;
  MessageLinkMetadata? _cached;
  bool _completed = false;
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
    final cached = _previewCache.lookup(key);
    _preview = null;
    _cached = cached?.metadata;
    _completed = cached != null;
    if (_completed || !_canAutoLoad || !canFetchMessageLink(key)) {
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

  Future<MessageLinkMetadata?> _request(Uri key) => _previewCache.request(
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
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MessageLinkMetadata?>(
      key: ValueKey(_cacheKey),
      future: _preview,
      initialData: _cached,
      builder: (context, snapshot) {
        final data = _completed ? _cached : snapshot.data;
        final loading =
            widget.compact &&
            !_completed &&
            snapshot.connectionState != ConnectionState.done &&
            _canAutoLoad &&
            canFetchMessageLink(widget.uri);
        if (widget.draftBuilder case final build?) {
          return build(
            data == null && !loading
                ? null
                : (
                    title: data == null
                        ? tr(context, 'Загрузка превью…', 'Loading preview…')
                        : data.title ?? data.siteName ?? widget.uri.host,
                    text: data?.description ?? widget.uri.toString(),
                    image: data?.image,
                  ),
          );
        }
        final card = data != null || loading
            ? _MessageLinkCard(
                uri: widget.uri,
                metadata: data,
                compact: widget.compact,
                foreground: widget.foreground,
                onDismiss: widget.onDismiss,
              )
            : null;
        return widget.builder?.call(card) ?? card ?? const SizedBox.shrink();
      },
    );
  }
}

class _MessageLinkCard extends StatelessWidget {
  const _MessageLinkCard({
    required this.uri,
    required this.metadata,
    required this.compact,
    required this.foreground,
    required this.onDismiss,
  });

  final Uri uri;
  final MessageLinkMetadata? metadata;
  final bool compact;
  final Color? foreground;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = foreground ?? MeshStyle.of(context).text;
    final site = metadata?.siteName;
    final title = metadata?.title;
    final description = metadata?.description;
    final heading = compact
        ? metadata == null
              ? tr(context, 'Загрузка превью…', 'Loading preview…')
              : title ?? site ?? uri.host
        : site ?? (title == null ? uri.host : null);
    final bodyTitle = compact || title?.toLowerCase() == site?.toLowerCase()
        ? null
        : title;
    final bodyDescription = compact && metadata == null
        ? uri.toString()
        : description;
    final image = metadata?.image;
    final width = metadata?.imageWidth ?? 0;
    final height = metadata?.imageHeight ?? 0;
    final ratio = width > 0 && height > 0 ? width / height : 1.0;
    // Mesh metadata comes from the webpage, so use its preferred size
    // or a suitably wide source image for the large layout.
    final large =
        image != null &&
        !compact &&
        width >= 320 &&
        height >= 160 &&
        ((metadata?.prefersLargeImage ?? false) ||
            (width >= 480 && ratio >= 1.5));

    Widget line(String value, int maxLines, TextStyle style) => Text(
      value,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );

    Widget media({double? side}) => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        image!,
        width: side ?? double.infinity,
        height: side,
        fit: BoxFit.cover,
        cacheWidth: large ? 768 : 144,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );

    return Material(
      color: color.withValues(alpha: .075),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => openMessageLink(context, uri),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (heading != null)
                                line(
                                  heading,
                                  1,
                                  TextStyle(
                                    color: color,
                                    fontSize: 13,
                                    fontWeight: compact
                                        ? FontWeight.w600
                                        : FontWeight.w700,
                                  ),
                                ),
                              if (bodyTitle != null)
                                line(
                                  bodyTitle,
                                  2,
                                  TextStyle(
                                    color: color,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (bodyDescription != null)
                                line(
                                  bodyDescription,
                                  compact ? 1 : 4,
                                  TextStyle(
                                    color: color.withValues(alpha: .85),
                                    fontSize: compact ? 12 : 13,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (image != null && !large) ...[
                          const SizedBox(width: 8),
                          media(side: compact ? 34 : 54),
                        ],
                      ],
                    ),
                    if (large) ...[
                      const SizedBox(height: 8),
                      AspectRatio(
                        aspectRatio: ratio.clamp(1.0, 2.5),
                        child: media(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (onDismiss case final dismiss?)
            MeshIconButton(
              label: tr(context, 'Убрать предпросмотр', 'Remove preview'),
              onPressed: dismiss,
              color: color,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
        ],
      ),
    );
  }
}
