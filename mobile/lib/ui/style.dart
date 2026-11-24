// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'ios_control.dart';
import 'macos_glass.dart';
import 'mesh_icon.dart';
import 'mesh_sheet_route.dart';
import 'sheet_control_clip.dart';
import 'sheet_scroll.dart';
import 'tokens.dart';
import 'mesh_scroll_edge.dart';

String tr(BuildContext context, String ru, String en) =>
    Localizations.localeOf(context).languageCode == 'ru' ? ru : en;

EdgeInsets meshScrollPadding(
  BuildContext context, [
  EdgeInsets spacing = EdgeInsets.zero,
]) => MediaQuery.paddingOf(context) + spacing;

class MeshStyle {
  const MeshStyle(this.dark);
  final bool dark;
  static MeshStyle of(BuildContext context) =>
      MeshStyle(Theme.of(context).brightness == Brightness.dark);

  Color get canvas =>
      dark ? const Color(0xff080a0f) : const Color(MeshGrameV2Light.background);
  Color get surface =>
      dark ? const Color(0xff1a1e26) : const Color(MeshGrameV2Light.surface);
  Color get field => dark ? const Color(0xff1c2029) : const Color(0xffeaf0f8);
  Color get searchField => dark
      ? const Color(MeshGrameV2Dark.searchField)
      : const Color(MeshGrameV2Light.searchField);
  Color get text => dark
      ? const Color(MeshGrameV2Dark.text)
      : const Color(MeshGrameV2Light.text);
  Color get secondary =>
      dark ? const Color(0xffa9b1c2) : const Color(MeshGrameV2Light.secondary);
  Color get accent => dark
      ? const Color(MeshGrameV2Dark.accent)
      : const Color(MeshGrameV2Light.accent);
  Color get separator =>
      dark ? const Color(0xff323844) : const Color(MeshGrameV2Light.hairline);
  Color get pill => dark ? const Color(0xbf242932) : const Color(0xeef8fbff);
  Color get selection =>
      dark ? const Color(0xff354661) : const Color(MeshGrameV2Light.selection);
  Color get incoming => dark ? const Color(0xff232838) : Colors.white;
  Color get outgoing =>
      dark ? const Color(0xff3344a5) : const Color(MeshGrameV2Light.outgoing);
  Color get messageTime =>
      dark ? secondary : const Color(MeshGrameV2Light.chatMeta);
  List<Color> get lightChatWallpaper => const [
    Color(MeshGrameV2Light.chatTint),
    Color(MeshGrameV2Light.chatMiddle),
    Color(MeshGrameV2Light.chatFloor),
  ];
  Color get warning => dark
      ? const Color(MeshGrameV2Dark.warning)
      : const Color(MeshGrameV2Light.warning);
  Color get error => dark
      ? const Color(MeshGrameV2Dark.error)
      : const Color(MeshGrameV2Light.error);
  Color get success => const Color(MeshGrameV2Light.success);
  Color get onlineDot => const Color(MeshGrameV2Light.online);
  Color get deliveryWarning => const Color(MeshGrameV2Light.deliveryWarning);

  ThemeData theme() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: accent,
          onSurface: text,
          surface: surface,
          onSurfaceVariant: secondary,
        );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      useMaterial3: true,
      splashFactory: InkSparkle.splashFactory,
      dividerColor: separator,
      textTheme: TextTheme(bodyMedium: TextStyle(color: text, fontSize: 16)),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }
}

class MessageMenuBackdrop extends InheritedWidget {
  const MessageMenuBackdrop({super.key, this.image, required super.child});
  final Uint8List? image;

  @override
  bool updateShouldNotify(MessageMenuBackdrop oldWidget) =>
      image != oldWidget.image;
}

Future<Uint8List?> captureMessageMenuBackdrop(GlobalKey source) async {
  await WidgetsBinding.instance.endOfFrame;
  final boundary = source.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary || boundary.size.isEmpty) return null;
  final image = await boundary.toImage(pixelRatio: 0.125);
  try {
    final data = await image.toByteData(format: ImageByteFormat.png);
    return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

class MessageMenuSurface extends StatelessWidget {
  const MessageMenuSurface({
    super.key,
    required this.radius,
    required this.child,
    this.backdrop,
  });
  final double radius;
  final Widget child;
  final Uint8List? backdrop;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final border = BorderRadius.circular(radius);
    final backdrop =
        this.backdrop ??
        context
            .dependOnInheritedWidgetOfExactType<MessageMenuBackdrop>()
            ?.image;
    if (useIosControls &&
        backdrop != null &&
        !MediaQuery.highContrastOf(context)) {
      return ClipRRect(
        borderRadius: border,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: IosControl(
                  key: ValueKey((radius, style.dark, backdrop)),
                  kind: 'messageGlass',
                  properties: {
                    'radius': radius,
                    'dark': style.dark,
                    'backdrop': backdrop,
                    'dim': messageMenuDim(context).toARGB32(),
                  },
                ),
              ),
            ),
            Material(type: MaterialType.transparency, child: child),
          ],
        ),
      );
    }
    return Material(
      color: style.surface,
      shape: RoundedRectangleBorder(
        borderRadius: border,
        side: BorderSide(color: style.separator),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

Color messageMenuDim(BuildContext context) {
  final color = MeshStyle.of(context).dark
      ? const Color(0x9e070911)
      : const Color(0x570e1b2d);
  return MediaQuery.accessibleNavigationOf(context)
      ? color.withValues(alpha: .85)
      : color;
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 28,
    this.modal = false,
    this.color,
    this.nativeButtonMaterial = false,
    this.nativeDesktopMaterial = false,
  });
  final Widget child;
  final double radius;
  final bool modal;
  final Color? color;
  final bool nativeButtonMaterial;
  final bool nativeDesktopMaterial;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final opaque = MediaQuery.highContrastOf(context);
    final border = BorderRadius.circular(radius);
    if ((nativeDesktopMaterial || nativeButtonMaterial) &&
        MacGlass.enabled(context)) {
      return Stack(
        children: [
          Positioned.fill(
            child: MacGlassBackground(
              radius: radius,
              dark: style.dark,
              tint: color,
            ),
          ),
          Material(type: MaterialType.transparency, child: child),
        ],
      );
    }
    if (nativeButtonMaterial && useIosControls) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: _NativeGlassButton(
                label: '',
                onTap: null,
                primary: false,
                decorative: true,
              ),
            ),
          ),
          // Keep UIKit's glass edge outside the clip for the phrase controls.
          ClipRRect(
            borderRadius: border,
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ],
      );
    }
    if (modal && useIosControls && !opaque) {
      return ClipRRect(
        borderRadius: border,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: IosControl(
                  key: ValueKey((radius, style.dark)),
                  kind: 'modalGlass',
                  properties: {'radius': radius, 'dark': style.dark},
                ),
              ),
            ),
            Material(type: MaterialType.transparency, child: child),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: border,
      child: BackdropFilter(
        enabled: !opaque,
        filter: ImageFilter.blur(sigmaX: 17, sigmaY: 17),
        child: Material(
          color: opaque ? style.surface : color ?? style.pill,
          shape: RoundedRectangleBorder(
            borderRadius: border,
            side: BorderSide(color: style.separator),
          ),
          child: child,
        ),
      ),
    );
  }
}

class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.longPressLabel,
    this.primary = false,
    this.coveredByModal = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap, onLongPress;
  final String? longPressLabel;
  final bool primary, coveredByModal;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final symbol = useIosControls ? meshGlassButtonSymbol(icon) : null;
    if (symbol != null) {
      return SizedBox.square(
        dimension: 48,
        child: _NativeGlassButton(
          symbol: symbol,
          label: label,
          onTap: onTap,
          onLongPress: onLongPress,
          longPressLabel: longPressLabel,
          primary: primary,
          coveredByModal: coveredByModal,
        ),
      );
    }
    final button = Tooltip(
      message: label,
      triggerMode: onLongPress == null ? null : TooltipTriggerMode.manual,
      child: GlassSurface(
        nativeDesktopMaterial: true,
        color: primary ? style.accent : null,
        child: IconButton(
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          padding: EdgeInsets.zero,
          icon: Icon(icon, size: 20),
          color: primary
              ? (style.dark ? const Color(0xff10254b) : Colors.white)
              : style.text,
          disabledColor: style.secondary,
          onPressed: onTap,
        ),
      ),
    );
    final hold = onLongPress;
    if (hold == null) return button;
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: longPressLabel ?? label): hold,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: hold,
        child: button,
      ),
    );
  }
}

class GlassActionButton extends StatelessWidget {
  const GlassActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = true,
    this.symbol,
    this.icon,
    this.width = double.infinity,
    this.height,
    this.wrapLabel = false,
    this.fitContent = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final String? symbol;
  final IconData? icon;
  final double width;
  final double? height;
  final bool wrapLabel;
  final bool fitContent;

  double _contentWidth(BuildContext context, TextScaler textScaler) {
    final measure = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: useIosControls ? 17 : 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final result = (measure.width.ceilToDouble() + 28 + (icon == null ? 0 : 24))
        .clamp(48.0, double.infinity);
    measure.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final buttonWidth = fitContent ? _contentWidth(context, textScaler) : width;
    final defaultHeight = wrapLabel
        ? (textScaler.scale(17) * 2.4 + 8).clamp(48.0, double.infinity)
        : (48 + (textScaler.scale(16) - 16)).clamp(48.0, 80.0);
    if (!useIosControls) {
      final title = Text(
        label,
        textAlign: TextAlign.center,
        maxLines: wrapLabel ? 2 : 1,
        overflow: TextOverflow.ellipsis,
      );
      return SizedBox(
        height: height ?? defaultHeight,
        width: buttonWidth,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: primary ? style.accent : style.pill,
            foregroundColor: primary
                ? (style.dark ? const Color(0xff10254b) : Colors.white)
                : style.text,
            disabledBackgroundColor: primary
                ? Color.lerp(style.surface, style.text, .27)
                : style.pill,
            disabledForegroundColor: style.secondary.withValues(alpha: .58),
            shape: const StadiumBorder(),
            side: primary
                ? BorderSide.none
                : BorderSide(color: style.separator),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: onTap,
          child: icon == null
              ? title
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 5),
                    Flexible(child: title),
                  ],
                ),
        ),
      );
    }
    return SizedBox(
      height: height ?? defaultHeight,
      width: buttonWidth,
      child: _NativeGlassButton(
        label: label,
        primary: primary,
        onTap: onTap,
        symbol: symbol ?? (icon == null ? null : meshGlassButtonSymbol(icon!)),
        stacked: symbol != null,
        inlineSymbol: icon != null,
      ),
    );
  }
}

class _NativeGlassButton extends StatelessWidget {
  const _NativeGlassButton({
    this.symbol,
    required this.label,
    required this.onTap,
    required this.primary,
    this.onLongPress,
    this.longPressLabel,
    this.stacked = false,
    this.inlineSymbol = false,
    this.coveredByModal = false,
    this.decorative = false,
  });

  final String? symbol;
  final String label;
  final VoidCallback? onTap, onLongPress;
  final String? longPressLabel;
  final bool primary;
  final bool stacked, inlineSymbol, coveredByModal, decorative;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return IosControl(
      kind: 'button',
      onSelect: decorative ? null : (_) => onTap?.call(),
      onLongPress: onLongPress,
      properties: {
        'label': label,
        'enabled': decorative || onTap != null,
        if (decorative) 'readOnly': true,
        if (onLongPress != null) 'longPressLabel': longPressLabel ?? label,
        'primary': primary,
        'dark': style.dark,
        'accent': style.accent.toARGB32(),
        'surface': style.surface.toARGB32(),
        'foreground': style.text.toARGB32(),
        'onAccent': (style.dark ? const Color(0xff10254b) : Colors.white)
            .toARGB32(),
        'symbol': ?symbol,
        'stacked': stacked,
        if (inlineSymbol) 'inlineSymbol': true,
        'coveredByModal':
            coveredByModal || ModalRoute.isCurrentOf(context) == false,
      },
    );
  }
}

class MeshAvatar extends StatelessWidget {
  const MeshAvatar(
    this.name, {
    super.key,
    this.size = 48,
    this.channel = false,
    this.online = false,
    this.onTap,
  });
  final String name;
  final double size;
  final bool channel, online;
  final VoidCallback? onTap;

  static (Color, Color) colorsFor(String name) {
    const colors = [
      (Color(0xff578ce1), Color(0xff3053a1)),
      (Color(0xff956dd4), Color(0xff6241a4)),
      (Color(0xff3cb3b5), Color(0xff087d83)),
      (Color(0xffe3975d), Color(0xffae5a3e)),
      (Color(0xffd2759b), Color(0xffa64371)),
    ];
    final hash = name.runes.fold(0, (sum, rune) => sum * 13 + rune).abs();
    return colors[hash % colors.length];
  }

  static String initialsFor(String name) {
    return name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => String.fromCharCode(word.runes.first).toUpperCase())
        .join();
  }

  @override
  Widget build(BuildContext context) {
    final (top, bottom) = colorsFor(name);
    final initials = initialsFor(name);
    final avatar = MeshAvatarPresence(
      size: size,
      online: online && !channel,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [top, bottom],
            ),
          ),
          child: channel
              ? Icon(Icons.tag_rounded, color: Colors.white, size: size * .45)
              : Text(
                  initials.isEmpty ? 'M' : initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: size * .34,
                  ),
                ),
        ),
      ),
    );
    final action = onTap;
    if (action == null) return avatar;
    return Tooltip(
      message: tr(context, 'Профиль $name', '$name profile'),
      child: InkWell(
        customBorder: const CircleBorder(),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        onTap: action,
        child: avatar,
      ),
    );
  }
}

class MeshAvatarPresence extends StatelessWidget {
  const MeshAvatarPresence({
    super.key,
    required this.child,
    required this.size,
    required this.online,
  });

  final Widget child;
  final double size;
  final bool online;

  @override
  Widget build(BuildContext context) {
    if (!online) return child;
    final style = MeshStyle.of(context);
    final diameter = (size * .25).clamp(10.0, 18.0);
    return Stack(
      children: [
        child,
        Positioned(
          right: size * .025,
          bottom: size * .025,
          child: Semantics(
            label: tr(
              context,
              'Активен за последний час',
              'Active in the past hour',
            ),
            child: Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: style.onlineDot,
                border: Border.all(color: style.canvas, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MeshUnreadBadge extends StatelessWidget {
  const MeshUnreadBadge(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Semantics(
      label: tr(context, 'Непрочитанных: $count', 'Unread: $count'),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 23, minHeight: 23),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color.onPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class MeshGroup extends StatelessWidget {
  const MeshGroup({super.key, required this.children, this.inset = 64});
  final List<Widget> children;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return Material(
      color: style.surface,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: .65,
                indent: inset,
                endIndent: 14,
                color: style.separator,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class MeshRowIcon extends StatelessWidget {
  const MeshRowIcon({
    super.key,
    required this.icon,
    required this.tint,
    this.glyphColor = Colors.white,
  });

  final IconData icon;
  final Color tint, glyphColor;

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(9),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.lerp(tint, Colors.white, .20)!, tint],
      ),
    ),
    child: Icon(icon, size: 17, color: glyphColor),
  );
}

class MeshRow extends StatelessWidget {
  const MeshRow({
    super.key,
    required this.title,
    this.icon,
    this.tint,
    this.leading,
    this.subtitle,
    this.titleColor,
    this.detail,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.showChevron = true,
  });
  final String title;
  final String? subtitle, detail;
  final IconData? icon;
  final Color? tint;
  final Widget? leading;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap, onLongPress;
  final bool selected, showChevron;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return Semantics(
      selected: selected ? true : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15),
        minTileHeight: 54,
        leading:
            leading ??
            (icon == null
                ? null
                : MeshRowIcon(icon: icon!, tint: tint ?? style.accent)),
        title: Text(
          title,
          style: TextStyle(color: titleColor ?? style.text, fontSize: 16),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: TextStyle(color: style.secondary, fontSize: 13),
              ),
        trailing:
            trailing ??
            (selected
                ? Icon(Icons.check_rounded, size: 21, color: style.accent)
                : onTap == null || !showChevron
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (detail != null)
                        Text(
                          detail!,
                          style: TextStyle(
                            color: style.secondary,
                            fontSize: 13,
                          ),
                        ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: style.secondary,
                        size: 19,
                      ),
                    ],
                  )),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

class PinnedPageList extends StatelessWidget {
  const PinnedPageList({
    super.key,
    required this.padding,
    required this.header,
    required this.children,
  });

  final EdgeInsets padding;
  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(padding: padding.copyWith(bottom: 0), child: header),
      Expanded(
        child: MeshScrollViewport(
          tint: MeshStyle.of(context).canvas,
          edgeExtent: 14,
          child: ListView(
            padding: padding.copyWith(top: 0),
            children: children,
          ),
        ),
      ),
    ],
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(
    this.title, {
    super.key,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 7, 16, 9),
    this.sideWidth = 48,
    this.titleBackground,
  });

  final String title;
  final Widget? leading, trailing;
  final EdgeInsets padding;
  final double sideWidth;
  final Color? titleBackground;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        SizedBox(
          width: sideWidth,
          child: Align(alignment: Alignment.centerLeft, child: leading),
        ),
        Expanded(
          child: Semantics(
            header: true,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: titleBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: titleBackground == null
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: MeshStyle.of(context).text,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: sideWidth,
          child: Align(alignment: Alignment.centerRight, child: trailing),
        ),
      ],
    ),
  );
}

Future<T?> showMeshDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showGeneralDialog<T>(
  context: context,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierDismissible: true,
  barrierColor: Colors.black54,
  transitionDuration: const Duration(milliseconds: 260),
  pageBuilder: (context, _, _) => SafeArea(child: Builder(builder: builder)),
  transitionBuilder: (context, animation, _, child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: .94, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic,
          ),
        ),
        child: child,
      ),
    );
  },
);

class MeshDialog extends StatelessWidget {
  const MeshDialog({
    super.key,
    required this.title,
    this.content,
    this.actions,
  });

  final Widget title;
  final Widget? content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final buttons = actions?.map((action) {
      if (action is! TextButton ||
          action.child is! Text ||
          action.onLongPress != null ||
          (action.child as Text).data == null) {
        return action;
      }
      final text = (action.child as Text).data!;
      final measure = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = (measure.width + 26).clamp(
        65.0,
        (MediaQuery.sizeOf(context).width - 105).clamp(65.0, 290.0),
      );
      measure.dispose();
      return GlassActionButton(
        label: text,
        width: width.toDouble(),
        height: 44,
        primary: false,
        onTap: action.onPressed,
      );
    }).toList();
    if (useIosControls) {
      return Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassSurface(
            modal: true,
            radius: 26,
            child: MeshScrollViewport(
              edgeExtent: 14,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DefaultTextStyle(
                      style: TextStyle(
                        color: style.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                      child: title,
                    ),
                    if (content != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: content,
                      ),
                    if (buttons != null && buttons.isNotEmpty)
                      Column(
                        spacing: 12,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: buttons,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      scrollable: true,
      backgroundColor: style.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: style.separator),
        borderRadius: BorderRadius.circular(25),
      ),
      title: title,
      titleTextStyle: TextStyle(
        color: style.text,
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
      content: content,
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      actionsOverflowButtonSpacing: 12,
      actions: buttons,
    );
  }
}

Future<T?> showMeshSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double dragArea = 44,
}) {
  final presentingRoute = useIosControls ? ModalRoute.of(context) : null;
  return showMeshBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    enableDrag: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final style = MeshStyle.of(context);
      final sheet = Material(
        key: const ValueKey('mesh-sheet-panel'),
        color: style.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Builder(builder: builder),
      );
      return MeshSheetScrollContent(
        dragArea: dragArea,
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MeshSheetGrip(key: ValueKey('mesh-sheet-grip')),
            Flexible(
              child: useIosControls
                  ? MeshOpaqueSheetRegion(
                      presentingRoute: presentingRoute,
                      child: sheet,
                    )
                  : sheet,
            ),
          ],
        ),
      );
    },
  );
}

class MeshSheetGrip extends StatelessWidget {
  const MeshSheetGrip({super.key});

  static const height = 18.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MeshStyle.of(context).secondary.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const SizedBox(width: 34, height: 4),
      ),
    ),
  );
}

/// Lets the primary list hand a downward drag to its containing sheet on iOS.
class MeshSheetScrollContent extends StatefulWidget {
  const MeshSheetScrollContent({
    super.key,
    required this.builder,
    required this.dragArea,
  });

  final WidgetBuilder builder;
  final double dragArea;

  @override
  State<MeshSheetScrollContent> createState() => _MeshSheetScrollContentState();
}

class _MeshSheetScrollContentState extends State<MeshSheetScrollContent> {
  MeshSheetScrollController? _scroll;
  Drag? _gripDrag;

  Drag? _beginDrag([DragStartDetails? details]) {
    BottomSheet? sheet;
    RenderObject? renderBox;
    context.visitAncestorElements((element) {
      final ancestor = element.widget;
      if (ancestor is! BottomSheet) return true;
      sheet = ancestor;
      renderBox = element.findRenderObject();
      return false;
    });
    final bottomSheet = sheet;
    final animation = sheet?.animationController;
    final box = renderBox;
    if (bottomSheet == null ||
        animation == null ||
        animation.status == AnimationStatus.reverse ||
        box is! RenderBox ||
        !box.hasSize ||
        box.size.height <= 0) {
      return null;
    }

    // The route's drag callbacks keep its own animation in sync with touch.
    bottomSheet.onDragStart?.call(details ?? DragStartDetails());
    return _MeshSheetSurfaceDrag(bottomSheet, animation, box.size.height);
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.iOS) {
      return widget.builder(context);
    }
    return Stack(
      children: [
        PrimaryScrollController(
          controller: _scroll ??= MeshSheetScrollController(_beginDrag),
          child: Builder(builder: widget.builder),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: widget.dragArea,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            excludeFromSemantics: true,
            onVerticalDragStart: (details) => _gripDrag = _beginDrag(details),
            onVerticalDragUpdate: (details) => _gripDrag?.update(details),
            onVerticalDragEnd: (details) {
              _gripDrag?.end(details);
              _gripDrag = null;
            },
            onVerticalDragCancel: () {
              _gripDrag?.cancel();
              _gripDrag = null;
            },
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _MeshSheetSurfaceDrag extends Drag {
  _MeshSheetSurfaceDrag(this._sheet, this._animation, this._height);

  final BottomSheet _sheet;
  final AnimationController _animation;
  final double _height;

  @override
  void update(DragUpdateDetails details) {
    if (_animation.status != AnimationStatus.reverse) {
      _animation.value -= details.delta.dy / _height;
    }
  }

  @override
  void end(DragEndDetails details) {
    if (_animation.status == AnimationStatus.reverse) return;

    // Match the same fling and distance thresholds used by BottomSheet itself.
    final velocity = details.velocity.pixelsPerSecond.dy;
    final didFling = velocity > 700;
    final isClosing = didFling || _animation.value < .5;
    if (isClosing) {
      if (_animation.value > 0) {
        _animation.fling(velocity: didFling ? -velocity / _height : -1);
      }
    } else {
      _animation.forward();
    }
    _sheet.onDragEnd?.call(details, isClosing: isClosing);
    if (isClosing) _sheet.onClosing();
  }

  @override
  void cancel() {
    if (_animation.status == AnimationStatus.reverse) return;
    _animation.forward();
    _sheet.onDragEnd?.call(DragEndDetails(), isClosing: false);
  }
}

class SheetBody extends StatelessWidget {
  const SheetBody({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .66,
        ),
        child: MeshScrollViewport(
          tint:
              Theme.of(context).bottomSheetTheme.backgroundColor ??
              MeshStyle.of(context).canvas,
          edgeExtent: 12,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 7),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 7, 2, 9),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    ),
  );
}
