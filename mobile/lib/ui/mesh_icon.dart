// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';

String? meshGlassButtonSymbol(IconData icon) => switch (icon) {
  Icons.add_rounded => 'plus',
  Icons.arrow_back_ios_new_rounded => 'chevron.left',
  Icons.arrow_upward_rounded => 'arrow.up',
  Icons.attach_file_rounded => 'paperclip',
  Icons.bookmark_border_rounded => 'bookmark',
  Icons.check_rounded => 'checkmark',
  Icons.close_fullscreen_rounded => 'arrow.down.right.and.arrow.up.left',
  Icons.close_rounded => 'xmark',
  Icons.copy_rounded => 'doc.on.doc',
  Icons.download_rounded => 'arrow.down.to.line',
  Icons.edit_note_rounded => 'square.and.pencil',
  Icons.edit_outlined => 'pencil',
  Icons.ios_share_rounded => 'square.and.arrow.up',
  Icons.keyboard_arrow_down_rounded => 'chevron.down',
  Icons.map_outlined => 'map',
  Icons.my_location_rounded => 'location.viewfinder',
  Icons.open_in_full_rounded => 'arrow.up.left.and.arrow.down.right',
  Icons.qr_code_2_rounded => 'qrcode',
  Icons.qr_code_scanner_rounded => 'qrcode.viewfinder',
  Icons.refresh_rounded => 'arrow.clockwise',
  Icons.search_rounded => 'magnifyingglass',
  Icons.share_outlined => 'square.and.arrow.up',
  Icons.sort_rounded => 'line.3.horizontal.decrease',
  Icons.delete_outline_rounded => 'trash',
  _ => null,
};
