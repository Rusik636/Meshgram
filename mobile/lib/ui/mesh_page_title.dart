// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ios_control.dart';
import 'style.dart';

/// A centered title using the same native glass control as the chat header.
class MeshPageTitle extends StatelessWidget {
  const MeshPageTitle(this.title, {super.key, this.fallback});

  final String title;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    if (!useIosControls) {
      return fallback ??
          Semantics(
            header: true,
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          );
    }

    final style = MeshStyle.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final measure = TextPainter(
      text: TextSpan(
        text: title,
        style: DefaultTextStyle.of(context).style
            .copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final width = math.max(48.0, measure.width.ceilToDouble() + 28);
    final height = math.max(48.0, measure.height + 8);
    measure.dispose();

    return Center(
      heightFactor: 1,
      child: IgnorePointer(
        child: SizedBox(
          width: width,
          height: height,
          child: IosControl(
            kind: 'chatTitle',
            capsule: true,
            properties: {
              'label': title,
              'titleFontSize': textScaler.scale(16),
              'enabled': true,
              'readOnly': true,
              'coveredByModal': ModalRoute.isCurrentOf(context) == false,
              'dark': style.dark,
              'accent': style.accent.toARGB32(),
              'surface': style.surface.toARGB32(),
              'foreground': style.text.toARGB32(),
            },
          ),
        ),
      ),
    );
  }
}

/// Keeps map titles centered between the back button and a matching inset.
class MeshMapPageHeading extends StatelessWidget {
  const MeshMapPageHeading(this.title, {super.key, this.fallbackBackground});

  final String title;
  final Color? fallbackBackground;

  @override
  Widget build(BuildContext context) {
    final back = GlassButton(
      icon: Icons.arrow_back_ios_new_rounded,
      label: tr(context, 'Назад', 'Back'),
      onTap: () => Navigator.pop(context),
    );
    if (!useIosControls) {
      return PageHeading(
        title,
        titleBackground: fallbackBackground,
        leading: back,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 9),
      child: Row(
        children: [
          back,
          const SizedBox(width: 8),
          Expanded(child: MeshPageTitle(title)),
          const SizedBox(width: 56),
        ],
      ),
    );
  }
}
