// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class MacGlass {
  static const channel = MethodChannel('meshgrame/macos_glass');
  static bool _supported = false;

  static Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      _supported = await channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      _supported = false;
    }
  }

  static bool enabled(BuildContext context) =>
      _supported && !MediaQuery.highContrastOf(context);
}

class MacGlassBackground extends StatelessWidget {
  const MacGlassBackground({
    super.key,
    required this.radius,
    required this.dark,
    this.tint,
  });

  final double radius;
  final bool dark;
  final Color? tint;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: AppKitView(
        key: ValueKey((radius, dark, tint)),
        viewType: 'meshgrame/glass',
        creationParams: {
          'radius': radius,
          'dark': dark,
          'tint': ?tint?.toARGB32(),
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    ),
  );
}
