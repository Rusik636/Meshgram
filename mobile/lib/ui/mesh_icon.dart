// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ios_control.dart';

const _symbolsChannel = MethodChannel('meshgrame/symbols');
final _symbolMasks = <String, ui.Image>{};
Future<void>? _symbolPreparation;

/// Loads the system masks before the first frame that uses them.
Future<void> prepareMeshIosSymbols() => useIosControls
    ? _symbolPreparation ??= _loadSymbolMasks()
    : Future<void>.value();

Future<void> _loadSymbolMasks() async {
  final Map<String, Uint8List>? masks;
  try {
    masks = await _symbolsChannel.invokeMapMethod<String, Uint8List>(
      'render',
      {for (final (symbol, _) in _glassButtonSymbols.values) symbol}.toList(),
    );
  } on MissingPluginException {
    return;
  } on PlatformException {
    return;
  }
  if (masks == null) return;
  await Future.wait(
    masks.entries.map((entry) async {
      try {
        final codec = await ui.instantiateImageCodec(entry.value);
        try {
          _symbolMasks[entry.key] = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } on Exception {
        // A failed mask leaves this icon's Cupertino fallback available.
      }
    }),
  );
}

/// Supplies the same symbol to UIKit and the Flutter button under a sheet.
String? meshGlassButtonSymbol(IconData icon) => _glassButtonSymbols[icon]?.$1;

class MeshIosButtonGlyph extends StatelessWidget {
  const MeshIosButtonGlyph(
    this.icon, {
    super.key,
    required this.symbol,
    this.size = 31,
  });

  final IconData icon;
  final String symbol;
  final double size;

  @override
  Widget build(BuildContext context) {
    final mask = _symbolMasks[symbol];
    if (mask == null) {
      return Icon(_glassButtonSymbols[icon]?.$2, size: size * 22 / 31);
    }
    final theme = IconTheme.of(context);
    final color = theme.color!;
    return RawImage(
      image: mask,
      width: size,
      height: size,
      color: color.withValues(alpha: color.a * (theme.opacity ?? 1)),
      colorBlendMode: BlendMode.srcIn,
    );
  }
}

final _glassButtonSymbols = <IconData, (String, IconData)>{
  Icons.add_rounded: ('plus', CupertinoIcons.plus),
  Icons.arrow_back_ios_new_rounded: (
    'chevron.left',
    CupertinoIcons.chevron_back,
  ),
  Icons.arrow_upward_rounded: ('arrow.up', CupertinoIcons.arrow_up),
  Icons.attach_file_rounded: ('paperclip', CupertinoIcons.paperclip),
  Icons.check_rounded: ('checkmark', CupertinoIcons.checkmark),
  Icons.close_fullscreen_rounded: (
    'arrow.down.right.and.arrow.up.left',
    CupertinoIcons.arrow_down_right_arrow_up_left,
  ),
  Icons.close_rounded: ('xmark', CupertinoIcons.xmark),
  Icons.copy_rounded: ('doc.on.doc', CupertinoIcons.doc_on_doc),
  Icons.download_rounded: (
    'arrow.down.to.line',
    CupertinoIcons.arrow_down_to_line,
  ),
  Icons.edit_note_rounded: ('square.and.pencil', CupertinoIcons.square_pencil),
  Icons.edit_outlined: ('pencil', CupertinoIcons.pencil),
  Icons.ios_share_rounded: (
    'square.and.arrow.up',
    CupertinoIcons.square_arrow_up,
  ),
  Icons.keyboard_arrow_down_rounded: (
    'chevron.down',
    CupertinoIcons.chevron_down,
  ),
  Icons.map_outlined: ('map', CupertinoIcons.map),
  Icons.my_location_rounded: (
    'location.viewfinder',
    CupertinoIcons.location_circle,
  ),
  Icons.open_in_full_rounded: (
    'arrow.up.left.and.arrow.down.right',
    CupertinoIcons.arrow_up_left_arrow_down_right,
  ),
  Icons.qr_code_2_rounded: ('qrcode', CupertinoIcons.qrcode),
  Icons.qr_code_scanner_rounded: (
    'qrcode.viewfinder',
    CupertinoIcons.qrcode_viewfinder,
  ),
  Icons.refresh_rounded: ('arrow.clockwise', CupertinoIcons.arrow_clockwise),
  Icons.search_rounded: ('magnifyingglass', CupertinoIcons.search),
  Icons.share_outlined: ('square.and.arrow.up', CupertinoIcons.square_arrow_up),
  Icons.sort_rounded: (
    'line.3.horizontal.decrease',
    CupertinoIcons.line_horizontal_3_decrease,
  ),
};
