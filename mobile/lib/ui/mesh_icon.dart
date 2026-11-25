// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum MeshSvgGlyph {
  quickPhrases(
    'ios/Runner/Assets.xcassets/MeshQuickPhrases.imageset/quick_phrases.svg',
    'MeshQuickPhrases',
  );

  const MeshSvgGlyph(this.asset, this.iosImage);

  final String asset, iosImage;
}

class MeshSvgIcon extends StatelessWidget {
  const MeshSvgIcon(this.glyph, {super.key, this.color});
  final MeshSvgGlyph glyph;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color!;
    return SvgPicture.asset(
      glyph.asset,
      width: 20,
      height: 20,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}

String? meshGlassButtonSymbol(IconData icon) => switch (icon) {
  Icons.add_rounded => 'plus',
  Icons.arrow_back_ios_new_rounded => 'chevron.left',
  Icons.arrow_upward_rounded => 'arrow.up',
  Icons.attach_file_rounded => 'paperclip',
  Icons.bookmark_border_rounded => 'bookmark',
  Icons.calendar_today_rounded => 'calendar',
  Icons.check_rounded => 'checkmark',
  Icons.close_fullscreen_rounded => 'arrow.down.right.and.arrow.up.left',
  Icons.close_rounded => 'xmark',
  Icons.copy_rounded => 'doc.on.doc',
  Icons.create_new_folder_outlined => 'folder.badge.plus',
  Icons.download_rounded => 'arrow.down.to.line',
  Icons.edit_note_rounded => 'square.and.pencil',
  Icons.edit_outlined => 'pencil',
  Icons.ios_share_rounded => 'square.and.arrow.up',
  Icons.keyboard_arrow_down_rounded => 'chevron.down',
  Icons.keyboard_arrow_up_rounded => 'chevron.up',
  Icons.map_outlined => 'map',
  Icons.my_location_rounded => 'location.viewfinder',
  Icons.open_in_full_rounded => 'arrow.up.left.and.arrow.down.right',
  Icons.qr_code_2_rounded => 'qrcode',
  Icons.qr_code_scanner_rounded => 'qrcode.viewfinder',
  Icons.refresh_rounded => 'arrow.clockwise',
  Icons.schedule_rounded => 'clock',
  Icons.search_rounded => 'magnifyingglass',
  Icons.share_outlined => 'square.and.arrow.up',
  Icons.sort_rounded => 'line.3.horizontal.decrease',
  Icons.tune_rounded => 'slider.horizontal.3',
  Icons.delete_outline_rounded => 'trash',
  _ => null,
};
