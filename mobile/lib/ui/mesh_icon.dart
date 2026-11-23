// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ios_control.dart';

const _symbolsChannel = MethodChannel('meshgrame/symbols');
const _symbolRasterSize = 24.0;
const _defaultSymbolSize = 20.0;
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
      _systemSymbols.values.toSet().toList(growable: false),
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

/// Supplies the same symbol to a UIKit button and its Flutter rendering.
String? meshGlassButtonSymbol(IconData icon) => _glassButtonSymbols[icon];

/// Resolves the platform symbol while preserving iOS and custom icon data.
IconData? meshPlatformIcon(BuildContext context, IconData? icon) {
  if (icon == null ||
      Theme.of(context).platform != TargetPlatform.iOS ||
      icon.fontFamily != 'MaterialIcons' ||
      icon.fontPackage != null) {
    return icon;
  }
  return _iosIcons[icon] ?? CupertinoIcons.question_circle;
}

/// Displays an icon with the platform's glyph and the caller's layout.
class MeshIcon extends StatelessWidget {
  const MeshIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.shadows,
    this.semanticLabel,
    this.textDirection,
    this.applyTextScaling,
    this.systemSymbol,
  });

  final IconData? icon;
  final double? size;
  final Color? color;
  final List<Shadow>? shadows;
  final String? semanticLabel;
  final TextDirection? textDirection;
  final bool? applyTextScaling;
  final String? systemSymbol;

  @override
  Widget build(BuildContext context) {
    final mask = Theme.of(context).platform == TargetPlatform.iOS
        ? _symbolMasks[systemSymbol ?? _systemSymbols[icon]]
        : null;
    if (mask == null) {
      return Icon(
        meshPlatformIcon(context, icon),
        size: size,
        color: color,
        shadows: shadows,
        semanticLabel: semanticLabel,
        textDirection: textDirection,
        applyTextScaling: applyTextScaling,
      );
    }

    final theme = IconTheme.of(context);
    final scaleText = applyTextScaling ?? theme.applyTextScaling ?? false;
    final nominalSize = size ?? theme.size ?? _symbolRasterSize;
    final extent = scaleText
        ? MediaQuery.textScalerOf(context).scale(nominalSize)
        : nominalSize;
    final tint = color ?? theme.color!;
    final direction = textDirection ?? Directionality.of(context);
    return Semantics(
      label: semanticLabel,
      child: CustomPaint(
        size: Size.square(extent),
        painter: _SystemSymbolPainter(
          mask: mask,
          tint: tint.withValues(alpha: tint.a * (theme.opacity ?? 1)),
          shadows: shadows ?? theme.shadows ?? const [],
          flip:
              icon?.matchTextDirection == true &&
              direction == TextDirection.rtl,
          rasterScale: systemSymbol == null
              ? _symbolRasterSize / _defaultSymbolSize
              : 1,
        ),
      ),
    );
  }
}

class _SystemSymbolPainter extends CustomPainter {
  const _SystemSymbolPainter({
    required this.mask,
    required this.tint,
    required this.shadows,
    required this.flip,
    required this.rasterScale,
  });

  final ui.Image mask;
  final Color tint;
  final List<Shadow> shadows;
  final bool flip;
  final double rasterScale;

  @override
  void paint(Canvas canvas, Size size) {
    final extent = size.shortestSide * rasterScale;
    final center = size.center(Offset.zero);
    final bounds = Rect.fromCenter(
      center: center,
      width: extent,
      height: extent,
    );
    final source = Rect.fromLTWH(
      0,
      0,
      mask.width.toDouble(),
      mask.height.toDouble(),
    );
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (flip) {
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    for (final shadow in shadows) {
      paint
        ..colorFilter = ColorFilter.mode(shadow.color, BlendMode.srcIn)
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: shadow.blurSigma,
          sigmaY: shadow.blurSigma,
        );
      canvas.drawImageRect(mask, source, bounds.shift(shadow.offset), paint);
    }
    paint
      ..colorFilter = ColorFilter.mode(tint, BlendMode.srcIn)
      ..imageFilter = null;
    canvas.drawImageRect(mask, source, bounds, paint);
    if (flip) canvas.restore();
  }

  @override
  bool shouldRepaint(_SystemSymbolPainter oldDelegate) =>
      mask != oldDelegate.mask ||
      tint != oldDelegate.tint ||
      shadows != oldDelegate.shadows ||
      flip != oldDelegate.flip ||
      rasterScale != oldDelegate.rasterScale;
}

final _glassButtonSymbols = <IconData, String>{
  Icons.add_rounded: 'plus',
  Icons.arrow_back_ios_new_rounded: 'chevron.left',
  Icons.arrow_upward_rounded: 'arrow.up',
  Icons.attach_file_rounded: 'paperclip',
  Icons.check_rounded: 'checkmark',
  Icons.close_fullscreen_rounded: 'arrow.down.right.and.arrow.up.left',
  Icons.close_rounded: 'xmark',
  Icons.copy_rounded: 'doc.on.doc',
  Icons.download_rounded: 'arrow.down.to.line',
  Icons.edit_note_rounded: 'square.and.pencil',
  Icons.edit_outlined: 'pencil',
  Icons.ios_share_rounded: 'square.and.arrow.up',
  Icons.keyboard_arrow_down_rounded: 'chevron.down',
  Icons.map_outlined: 'map',
  Icons.my_location_rounded: 'location.viewfinder',
  Icons.open_in_full_rounded: 'arrow.up.left.and.arrow.down.right',
  Icons.qr_code_2_rounded: 'qrcode',
  Icons.qr_code_scanner_rounded: 'qrcode.viewfinder',
  Icons.refresh_rounded: 'arrow.clockwise',
  Icons.search_rounded: 'magnifyingglass',
  Icons.share_outlined: 'square.and.arrow.up',
  Icons.sort_rounded: 'line.3.horizontal.decrease',
};

final _systemSymbols = <IconData, String>{
  ..._glassButtonSymbols,
  Icons.add: 'plus',
  Icons.admin_panel_settings_outlined: 'checkmark.shield',
  Icons.alt_route_rounded: 'arrow.triangle.branch',
  Icons.arrow_back: 'arrow.left',
  Icons.arrow_back_rounded: 'arrow.left',
  Icons.arrow_drop_down: 'chevron.down',
  Icons.article_outlined: 'doc.richtext',
  Icons.back_hand_outlined: 'hand.raised',
  Icons.badge_outlined: 'person.crop.rectangle',
  Icons.balance_rounded: 'scalemass',
  Icons.battery_charging_full_rounded: 'battery.100.bolt',
  Icons.block_rounded: 'nosign',
  Icons.bluetooth_rounded: 'bluetooth',
  Icons.calendar_today_outlined: 'calendar',
  Icons.campaign_outlined: 'megaphone',
  Icons.cancel_outlined: 'xmark.circle',
  Icons.cell_tower_rounded: 'antenna.radiowaves.left.and.right',
  Icons.chat_bubble_outline_rounded: 'bubble.left',
  Icons.check_circle_rounded: 'checkmark.circle.fill',
  Icons.chevron_right: 'chevron.forward',
  Icons.chevron_right_rounded: 'chevron.forward',
  Icons.cloud_outlined: 'cloud',
  Icons.contrast_rounded: 'circle.lefthalf.filled',
  Icons.dark_mode_outlined: 'moon',
  Icons.delete_outline_rounded: 'trash',
  Icons.description_outlined: 'doc.text',
  Icons.directions_car_outlined: 'car',
  Icons.display_settings_outlined: 'slider.horizontal.below.rectangle',
  Icons.done_all_rounded: 'checkmark.circle',
  Icons.drag_handle_rounded: 'line.3.horizontal',
  Icons.error_outline_rounded: 'exclamationmark.circle',
  Icons.favorite_border_rounded: 'heart',
  Icons.flag_outlined: 'flag',
  Icons.forum_outlined: 'bubble.left.and.bubble.right',
  Icons.history_rounded: 'clock.arrow.circlepath',
  Icons.hub_outlined: 'point.3.connected.trianglepath.dotted',
  Icons.info_outline_rounded: 'info.circle',
  Icons.key_rounded: 'key',
  Icons.keyboard_arrow_up_rounded: 'chevron.up',
  Icons.language_rounded: 'globe',
  Icons.lightbulb_outline_rounded: 'lightbulb',
  Icons.link_off_rounded: 'link.badge.minus',
  Icons.location_on_outlined: 'mappin.circle',
  Icons.location_searching_rounded: 'scope',
  Icons.lock_outline_rounded: 'lock',
  Icons.login_rounded: 'square.and.arrow.right',
  Icons.memory_rounded: 'cpu',
  Icons.monitor_heart_outlined: 'waveform.path.ecg',
  Icons.near_me_outlined: 'location',
  Icons.notifications_off_outlined: 'bell.slash',
  Icons.notifications_outlined: 'bell',
  Icons.person_outline_rounded: 'person.crop.circle',
  Icons.pets_outlined: 'pawprint',
  Icons.phonelink_ring_outlined: 'iphone.radiowaves.left.and.right',
  Icons.place_outlined: 'mappin.circle',
  Icons.place_rounded: 'mappin.circle.fill',
  Icons.power_settings_new_rounded: 'power',
  Icons.priority_high_rounded: 'exclamationmark',
  Icons.privacy_tip_outlined: 'lock.shield',
  Icons.public_rounded: 'globe',
  Icons.radio_button_unchecked_rounded: 'circle',
  Icons.remove_circle_outline_rounded: 'minus.circle',
  Icons.reply_rounded: 'arrowshape.turn.up.left',
  Icons.restart_alt_rounded: 'arrow.counterclockwise',
  Icons.restaurant_outlined: 'fork.knife',
  Icons.route_outlined: 'point.bottomleft.forward.to.point.topright.scurvepath',
  Icons.route_rounded: 'point.bottomleft.forward.to.point.topright.scurvepath',
  Icons.schedule_rounded: 'clock',
  Icons.sentiment_satisfied_alt: 'face.smiling',
  Icons.settings_ethernet_rounded: 'network',
  Icons.settings_outlined: 'gearshape',
  Icons.sort_by_alpha_rounded: 'textformat.abc',
  Icons.sports_soccer_outlined: 'soccerball',
  Icons.star_outline_rounded: 'star',
  Icons.star_rounded: 'star.fill',
  Icons.swap_vert_rounded: 'arrow.up.arrow.down',
  Icons.system_update_alt_rounded: 'tray.and.arrow.down',
  Icons.tag_rounded: 'number',
  Icons.terminal_rounded: 'terminal',
  Icons.thermostat_rounded: 'thermometer.medium',
  Icons.tune_rounded: 'slider.horizontal.3',
  Icons.visibility_off_outlined: 'eye.slash',
  Icons.visibility_outlined: 'eye',
  Icons.wifi_rounded: 'wifi',
};

final _iosIcons = <IconData, IconData>{
  Icons.add: CupertinoIcons.plus,
  Icons.add_rounded: CupertinoIcons.plus,
  Icons.admin_panel_settings_outlined: CupertinoIcons.checkmark_shield,
  Icons.alt_route_rounded: CupertinoIcons.arrow_branch,
  Icons.arrow_back: CupertinoIcons.arrow_left,
  Icons.arrow_back_ios_new_rounded: CupertinoIcons.chevron_back,
  Icons.arrow_back_rounded: CupertinoIcons.arrow_left,
  Icons.arrow_drop_down: CupertinoIcons.chevron_down,
  Icons.arrow_upward_rounded: CupertinoIcons.arrow_up,
  Icons.article_outlined: CupertinoIcons.doc_richtext,
  Icons.attach_file_rounded: CupertinoIcons.paperclip,
  Icons.back_hand_outlined: CupertinoIcons.hand_raised,
  Icons.badge_outlined: CupertinoIcons.person_crop_rectangle,
  Icons.balance_rounded: CupertinoIcons.equal_circle,
  Icons.battery_charging_full_rounded: CupertinoIcons.battery_charging,
  Icons.block_rounded: CupertinoIcons.nosign,
  Icons.bluetooth_rounded: CupertinoIcons.bluetooth,
  Icons.calendar_today_outlined: CupertinoIcons.calendar,
  Icons.campaign_outlined: CupertinoIcons.speaker_2,
  Icons.cancel_outlined: CupertinoIcons.xmark_circle,
  Icons.cell_tower_rounded: CupertinoIcons.antenna_radiowaves_left_right,
  Icons.chat_bubble_outline_rounded: CupertinoIcons.bubble_left,
  Icons.check_circle_rounded: CupertinoIcons.checkmark_circle_fill,
  Icons.check_rounded: CupertinoIcons.checkmark,
  Icons.chevron_right: CupertinoIcons.chevron_forward,
  Icons.chevron_right_rounded: CupertinoIcons.chevron_forward,
  Icons.close_fullscreen_rounded: CupertinoIcons.arrow_down_right_arrow_up_left,
  Icons.close_rounded: CupertinoIcons.xmark,
  Icons.cloud_outlined: CupertinoIcons.cloud,
  // Icons.copy_rounded is an alias of Icons.content_copy_rounded.
  Icons.content_copy_rounded: CupertinoIcons.doc_on_doc,
  Icons.contrast_rounded: CupertinoIcons.circle_lefthalf_fill,
  Icons.dark_mode_outlined: CupertinoIcons.moon,
  Icons.delete_outline_rounded: CupertinoIcons.trash,
  Icons.description_outlined: CupertinoIcons.doc_text,
  Icons.directions_car_outlined: CupertinoIcons.car,
  Icons.display_settings_outlined:
      CupertinoIcons.slider_horizontal_below_rectangle,
  Icons.done_all_rounded: CupertinoIcons.checkmark_circle,
  Icons.download_rounded: CupertinoIcons.arrow_down_to_line,
  Icons.drag_handle_rounded: CupertinoIcons.line_horizontal_3,
  Icons.edit_note_rounded: CupertinoIcons.square_pencil,
  Icons.edit_outlined: CupertinoIcons.pencil,
  Icons.error_outline_rounded: CupertinoIcons.exclamationmark_circle,
  Icons.favorite_border_rounded: CupertinoIcons.heart,
  Icons.flag_outlined: CupertinoIcons.flag,
  Icons.forum_outlined: CupertinoIcons.bubble_left_bubble_right,
  Icons.history_rounded: CupertinoIcons.clock,
  Icons.hub_outlined: CupertinoIcons.flowchart,
  Icons.info_outline_rounded: CupertinoIcons.info_circle,
  Icons.ios_share_rounded: CupertinoIcons.square_arrow_up,
  Icons.key_rounded: CupertinoIcons.lock_open,
  Icons.keyboard_arrow_down_rounded: CupertinoIcons.chevron_down,
  Icons.keyboard_arrow_up_rounded: CupertinoIcons.chevron_up,
  Icons.language_rounded: CupertinoIcons.globe,
  Icons.lightbulb_outline_rounded: CupertinoIcons.lightbulb,
  Icons.link_off_rounded: CupertinoIcons.link_circle,
  Icons.location_on_outlined: CupertinoIcons.placemark,
  Icons.location_searching_rounded: CupertinoIcons.scope,
  Icons.lock_outline_rounded: CupertinoIcons.lock,
  Icons.login_rounded: CupertinoIcons.square_arrow_right,
  Icons.map_outlined: CupertinoIcons.map,
  Icons.memory_rounded: CupertinoIcons.square_grid_2x2,
  Icons.monitor_heart_outlined: CupertinoIcons.waveform_path_ecg,
  Icons.my_location_rounded: CupertinoIcons.location_circle,
  Icons.near_me_outlined: CupertinoIcons.location,
  Icons.notifications_off_outlined: CupertinoIcons.bell_slash,
  Icons.notifications_outlined: CupertinoIcons.bell,
  Icons.open_in_full_rounded: CupertinoIcons.arrow_up_left_arrow_down_right,
  Icons.person_outline_rounded: CupertinoIcons.person_crop_circle,
  Icons.pets_outlined: CupertinoIcons.paw,
  Icons.phonelink_ring_outlined: CupertinoIcons.device_phone_portrait,
  Icons.place_outlined: CupertinoIcons.placemark,
  Icons.place_rounded: CupertinoIcons.placemark_fill,
  Icons.power_settings_new_rounded: CupertinoIcons.power,
  Icons.priority_high_rounded: CupertinoIcons.exclamationmark,
  Icons.privacy_tip_outlined: CupertinoIcons.lock_shield,
  Icons.public_rounded: CupertinoIcons.globe,
  Icons.qr_code_2_rounded: CupertinoIcons.qrcode,
  Icons.qr_code_scanner_rounded: CupertinoIcons.qrcode_viewfinder,
  Icons.radio_button_unchecked_rounded: CupertinoIcons.circle,
  Icons.refresh_rounded: CupertinoIcons.arrow_clockwise,
  Icons.remove_circle_outline_rounded: CupertinoIcons.minus_circle,
  Icons.reply_rounded: CupertinoIcons.arrowshape_turn_up_left,
  Icons.restart_alt_rounded: CupertinoIcons.arrow_counterclockwise,
  Icons.restaurant_outlined: CupertinoIcons.circle_grid_3x3,
  Icons.route_outlined: CupertinoIcons.arrow_turn_up_right,
  Icons.route_rounded: CupertinoIcons.arrow_turn_up_right,
  Icons.schedule_rounded: CupertinoIcons.clock,
  Icons.search_rounded: CupertinoIcons.search,
  Icons.sentiment_satisfied_alt: CupertinoIcons.smiley,
  Icons.settings_ethernet_rounded: CupertinoIcons.personalhotspot,
  Icons.settings_outlined: CupertinoIcons.gear,
  Icons.share_outlined: CupertinoIcons.square_arrow_up,
  Icons.sort_by_alpha_rounded: CupertinoIcons.textformat_abc,
  Icons.sort_rounded: CupertinoIcons.line_horizontal_3_decrease,
  Icons.sports_soccer_outlined: CupertinoIcons.sportscourt,
  Icons.star_outline_rounded: CupertinoIcons.star,
  Icons.star_rounded: CupertinoIcons.star_fill,
  Icons.swap_vert_rounded: CupertinoIcons.arrow_up_arrow_down,
  Icons.system_update_alt_rounded: CupertinoIcons.tray_arrow_down,
  Icons.tag_rounded: CupertinoIcons.number,
  Icons.terminal_rounded: CupertinoIcons.chevron_left_slash_chevron_right,
  Icons.thermostat_rounded: CupertinoIcons.thermometer,
  Icons.tune_rounded: CupertinoIcons.slider_horizontal_3,
  Icons.visibility_off_outlined: CupertinoIcons.eye_slash,
  Icons.visibility_outlined: CupertinoIcons.eye,
  Icons.wifi_rounded: CupertinoIcons.wifi,
};
