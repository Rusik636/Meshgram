// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';

import 'mesh_sheet_route.dart';

Future<T?> showMeshAttachmentSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool morphFromSource = false,
}) => showMeshBottomSheet<T>(
  context: context,
  builder: builder,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  backgroundColor: Colors.transparent,
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null,
  morphFromSource: morphFromSource,
  useAttachmentDim: true,
);
