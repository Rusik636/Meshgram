import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const emojiFontFamily = 'MeshgramNotoColorEmoji';
const _emojiFont = TextStyle(fontFamily: emojiFontFamily);

// Include keycaps, explicit emoji presentation, and unqualified ZWJ sequences.
final _emojiPresentation = RegExp(
  // The Dart VM supports Unicode property escapes.
  // ignore: valid_regexps
  r'\p{Emoji_Presentation}|\u20e3|\p{Emoji}\uFE0F|\p{Extended_Pictographic}\u200D',
  unicode: true,
);

bool get _useBundledEmoji =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

TextStyle emojiGlyphStyle(TextStyle style) =>
    _useBundledEmoji ? style.copyWith(fontFamily: emojiFontFamily) : style;

TextSpan emojiTextSpan(String text, {TextStyle? style}) {
  if (!_useBundledEmoji || !_emojiPresentation.hasMatch(text)) {
    return TextSpan(text: text, style: style);
  }

  final spans = <TextSpan>[];
  var start = 0;
  var end = 0;
  for (final cluster in text.characters) {
    end += cluster.length;
    // Keep the entire sequence in one font, including its ZWJ and modifiers.
    if (!_emojiPresentation.hasMatch(cluster) || cluster.contains('\ufe0e')) {
      continue;
    }
    final offset = end - cluster.length;
    if (offset > start) {
      spans.add(TextSpan(text: text.substring(start, offset)));
    }
    spans.add(TextSpan(text: cluster, style: _emojiFont));
    start = end;
  }
  if (spans.isEmpty) return TextSpan(text: text, style: style);
  if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
  return TextSpan(style: style, children: spans);
}

class EmojiText extends StatelessWidget {
  const EmojiText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final span = emojiTextSpan(text);
    return span.children == null
        ? Text(
            text,
            style: style,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: overflow,
          )
        : Text.rich(
            span,
            style: style,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: overflow,
          );
  }
}

class EmojiEditingController extends TextEditingController {
  EmojiEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final span = super.buildTextSpan(
      context: context,
      style: style,
      withComposing: withComposing,
    );
    if (!_useBundledEmoji) return span;
    final composing = span.children;
    if (composing == null) {
      return emojiTextSpan(span.text ?? '', style: span.style);
    }
    return TextSpan(
      style: span.style,
      children: [
        for (final part in composing)
          if (part is TextSpan && part.text != null)
            emojiTextSpan(part.text!, style: part.style)
          else
            part,
      ],
    );
  }
}
