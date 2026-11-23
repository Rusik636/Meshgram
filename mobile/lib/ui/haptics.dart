// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/services.dart';

enum MeshHaptic { selection, light, medium, success }

/// Plays the platform's standard haptic for an interface action.
Future<void> playMeshHaptic(MeshHaptic effect) => switch (effect) {
  MeshHaptic.selection => HapticFeedback.selectionClick(),
  MeshHaptic.light => HapticFeedback.lightImpact(),
  MeshHaptic.medium => HapticFeedback.mediumImpact(),
  MeshHaptic.success => HapticFeedback.successNotification(),
};
