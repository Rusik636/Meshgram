// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class MacGlass {
  static const channel = MethodChannel('meshgrame/macos_glass');
  static const windowControlsInset = 30.0;
  static const controlEdgeOutset = 2.0;
  static bool _supported = false;
  static bool firmwareFiltersAvailable = false;
  static double _regularFontSize = 13;
  static double _smallFontSize = 11;

  static Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      final configuration = await channel.invokeMapMethod<String, Object?>(
        'configuration',
      );
      _supported = configuration?['glass'] == true;
      firmwareFiltersAvailable = configuration?['firmwareFilters'] == true;
      _regularFontSize =
          (configuration?['regularFontSize'] as num?)?.toDouble() ?? 13;
      _smallFontSize =
          (configuration?['smallFontSize'] as num?)?.toDouble() ?? 11;
    } on MissingPluginException {
      _supported = false;
      firmwareFiltersAvailable = false;
    }
  }

  static bool enabled(BuildContext context) =>
      _supported && !MediaQuery.highContrastOf(context);

  static TextScaler textScaler(TextScaler platform) =>
      _MacTextScaler(platform, _regularFontSize, _smallFontSize);
}

class _MacTextScaler extends TextScaler {
  const _MacTextScaler(this.platform, this.regular, this.small);

  final TextScaler platform;
  final double regular, small;

  @override
  double scale(double fontSize) {
    // Preserve the app's hierarchy around Flutter's 16 pt body baseline and
    // keep compact labels at or above the AppKit small size when possible.
    final size = math.min(fontSize, math.max(small, fontSize * regular / 16));
    return platform.scale(size);
  }

  @override
  double get textScaleFactor => scale(16) / 16;

  @override
  bool operator ==(Object other) =>
      other is _MacTextScaler &&
      other.platform == platform &&
      other.regular == regular &&
      other.small == small;

  @override
  int get hashCode => Object.hash(platform, regular, small);
}

class MacGlassBackground extends StatelessWidget {
  const MacGlassBackground({
    super.key,
    required this.radius,
    required this.dark,
    this.tint,
    this.edgeOutset = 0,
    this.clear = false,
  });

  final double radius;
  final bool dark;
  final Color? tint;
  final double edgeOutset;
  final bool clear;

  @override
  Widget build(BuildContext context) {
    final background = IgnorePointer(
      child: ExcludeSemantics(
        child: AppKitView(
          key: ValueKey((radius, dark, tint, edgeOutset, clear)),
          viewType: 'meshgrame/glass',
          creationParams: {
            'radius': radius,
            'dark': dark,
            'tint': ?tint?.toARGB32(),
            'edgeOutset': edgeOutset,
            'clear': clear,
          },
          creationParamsCodec: const StandardMessageCodec(),
        ),
      ),
    );
    if (edgeOutset == 0) return background;
    // Keep the native bevel and its antialiasing inside the platform view.
    return LayoutBuilder(
      builder: (context, bounds) {
        final width = bounds.maxWidth + 2 * edgeOutset;
        final height = bounds.maxHeight + 2 * edgeOutset;
        return OverflowBox(
          minWidth: width,
          maxWidth: width,
          minHeight: height,
          maxHeight: height,
          child: background,
        );
      },
    );
  }
}
