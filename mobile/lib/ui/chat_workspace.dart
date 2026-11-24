// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../mesh/store.dart';

import 'macos_glass.dart';
import 'style.dart';

bool meshDesktop(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

const meshDesktopSplitWidth = 800.0;
const meshDesktopWorkspaceInset = 8.0;

void paintChatWorkspaceEdge(Canvas canvas, Size size, Color background) {
  final edge = Rect.fromLTWH(0, 0, math.min(size.width, 42), size.height);
  canvas.drawRect(
    edge,
    Paint()
      ..shader = LinearGradient(
        colors: [background, background.withValues(alpha: 0)],
      ).createShader(edge),
  );
}

/// Carries the workspace geometry through the conversation's own navigator.
class ChatWorkspacePane extends InheritedWidget {
  const ChatWorkspacePane({
    super.key,
    required this.split,
    required this.visible,
    required super.child,
  });

  final bool split;
  final bool visible;

  static ChatWorkspacePane? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatWorkspacePane>();

  static bool desktopSplit(BuildContext context) =>
      meshDesktop(context) && of(context)?.split == true;

  static double toolbarTop(BuildContext context) =>
      desktopSplit(context) ? meshDesktopWorkspaceInset : 6.0;

  @override
  bool updateShouldNotify(ChatWorkspacePane oldWidget) =>
      split != oldWidget.split || visible != oldWidget.visible;
}

class ChatWorkspaceResizeHandle extends StatelessWidget {
  const ChatWorkspaceResizeHandle({super.key, required this.onResize});

  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) => Semantics(
    label: tr(context, 'Ширина списка чатов', 'Chat list width'),
    onIncrease: () => onResize(24),
    onDecrease: () => onResize(-24),
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onResize(details.delta.dx),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class DesktopWorkspacePanel extends StatelessWidget {
  const DesktopWorkspacePanel({super.key, required this.child});

  static const radius = 22.0;
  static const _corners = BorderRadius.all(Radius.circular(radius));

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final outline = Color.lerp(style.desktopPanel, style.secondary, .22)!;
    return ClipRRect(
      borderRadius: _corners,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: _corners,
          border: Border.all(color: outline),
        ),
        child: child,
      ),
    );
  }
}

class ChatFolderRail extends StatelessWidget {
  const ChatFolderRail({
    super.key,
    required this.builtInLabels,
    required this.folders,
    required this.scrollController,
    required this.editing,
    required this.onEdit,
    required this.onDelete,
    required this.onReorder,
    required this.selected,
    required this.unread,
    required this.settingsUnread,
    required this.settingsSelected,
    required this.onFolder,
    required this.onSettings,
  });

  static const width = 86.0;
  final List<String> builtInLabels;
  final List<ChatFolder> folders;
  final ScrollController scrollController;
  final bool editing;
  final ValueChanged<String> onEdit, onDelete;
  final ReorderCallback onReorder;
  final int? selected;
  final List<int> unread;
  final int settingsUnread;
  final bool settingsSelected;
  final ValueChanged<int> onFolder;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final mac = !kIsWeb && Theme.of(context).platform == TargetPlatform.macOS;
    final labelStyle = Theme.of(context).textTheme.labelMedium!;
    final labelSize = labelStyle.fontSize!;
    final row = (47 + MediaQuery.textScalerOf(context).scale(labelSize) * 2.4)
        .clamp(68.0, 132.0);
    const markerHeight = 24.0;
    final builtInCount = builtInLabels.length;
    Widget item(int index) {
      final builtIn = index < builtInCount;
      final folder = builtIn ? null : folders[index - builtInCount];
      return SizedBox(
        key: ValueKey(folder?.id ?? index),
        height: row,
        child: _destination(
          context,
          title: folder?.name ?? builtInLabels[index],
          icon: switch (index) {
            0 => Icons.forum_outlined,
            1 => Icons.person_outline_rounded,
            2 => Icons.tag_rounded,
            _ => Icons.folder_outlined,
          },
          active: index == selected,
          count: unread[index],
          isFolder: true,
          onTap: () => onFolder(index),
          onEdit: editing && folder != null ? () => onEdit(folder.id) : null,
          onDelete: editing && folder != null
              ? () => onDelete(folder.id)
              : null,
        ),
      );
    }

    final content = SafeArea(
      right: false,
      top: !mac,
      child: Padding(
        padding: EdgeInsets.fromLTRB(6, mac ? 0 : 8, 6, 8),
        child: Column(
          children: [
            if (mac) ...[
              const SizedBox(
                height: MacGlass.windowControlsInset,
                width: double.infinity,
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: AppKitView(viewType: 'meshgrame/window_controls'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: editing
                  ? ReorderableListView.builder(
                      scrollController: scrollController,
                      padding: EdgeInsets.zero,
                      buildDefaultDragHandles: false,
                      header: Column(
                        children: [
                          for (var i = 0; i < builtInCount; i++) item(i),
                        ],
                      ),
                      itemCount: folders.length,
                      itemBuilder: (context, index) =>
                          ReorderableDelayedDragStartListener(
                            key: ValueKey(folders[index].id),
                            index: index,
                            child: item(index + builtInCount),
                          ),
                      onReorderItem: onReorder,
                    )
                  : SingleChildScrollView(
                      controller: scrollController,
                      child: Stack(
                        children: [
                          AnimatedPositionedDirectional(
                            key: const ValueKey('folder-rail-indicator'),
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            top:
                                (selected ?? 0) * row +
                                (row - 5 - markerHeight) / 2,
                            start: 0,
                            width: 3,
                            height: markerHeight,
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: selected == null ? 0 : 1,
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 150),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: style.accent,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Column(
                            children: [
                              for (
                                var i = 0;
                                i < builtInCount + folders.length;
                                i++
                              )
                                item(i),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
            SizedBox(
              height: row,
              child: _destination(
                context,
                title: tr(context, 'Настройки', 'Settings'),
                icon: Icons.settings_outlined,
                active: settingsSelected,
                count: settingsUnread,
                fill: settingsSelected,
                onTap: onSettings,
              ),
            ),
          ],
        ),
      ),
    );
    return DesktopWorkspacePanel(
      child: MacGlass.enabled(context)
          ? Stack(
              fit: StackFit.expand,
              children: [
                MacGlassBackground(
                  radius: DesktopWorkspacePanel.radius,
                  dark: style.dark,
                ),
                content,
              ],
            )
          : ColoredBox(color: style.desktopPanel, child: content),
    );
  }

  Widget _destination(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool active,
    required int count,
    bool fill = false,
    bool isFolder = false,
    required VoidCallback onTap,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    final style = MeshStyle.of(context);
    final foreground = active ? style.accent : style.secondary;
    final shape = BorderRadius.circular(14);
    final labelStyle = Theme.of(context).textTheme.labelMedium!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            selected: active,
            button: true,
            customSemanticsActions: onEdit == null
                ? null
                : {
                    CustomSemanticsAction(
                      label: tr(context, 'Изменить папку', 'Edit folder'),
                    ): onEdit,
                  },
            child: Material(
              color: fill ? style.selection : Colors.transparent,
              borderRadius: shape,
              child: InkWell(
                borderRadius: shape,
                hoverColor: Colors.transparent,
                highlightColor: isFolder ? Colors.transparent : null,
                splashFactory: isFolder ? NoSplash.splashFactory : null,
                onTap: onTap,
                onDoubleTap: onEdit,
                onSecondaryTap: onEdit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Badge(
                        isLabelVisible: count > 0,
                        label: Text(count > 99 ? '99+' : '$count'),
                        child: Icon(icon, color: foreground, size: 24),
                      ),
                      const SizedBox(height: 4),
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: labelStyle.copyWith(color: foreground),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onDelete != null)
            PositionedDirectional(
              end: 0,
              top: 0,
              child: MeshIconButton(
                label: tr(
                  context,
                  'Удалить папку $title',
                  'Delete folder $title',
                ),
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                style: IconButton.styleFrom(
                  overlayColor: Colors.transparent,
                  splashFactory: NoSplash.splashFactory,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: style.secondary,
                ),
                onPressed: onDelete,
              ),
            ),
        ],
      ),
    );
  }
}
