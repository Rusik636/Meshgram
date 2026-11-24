// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder findControl(Pattern label) => find.byWidgetPredicate((widget) {
  final value = switch (widget) {
    Semantics() => widget.properties.label,
    RawTooltip() => widget.semanticsTooltip,
    _ => null,
  };
  return value != null &&
      (label is RegExp ? label.hasMatch(value) : value == label);
});
