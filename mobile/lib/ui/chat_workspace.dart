// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';

import 'style.dart';

bool meshDesktop(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

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
        child: Center(
          child: ColoredBox(
            color: MeshStyle.of(context).separator,
            child: const SizedBox(width: 1, height: double.infinity),
          ),
        ),
      ),
    ),
  );
}

class ChatFolderRail extends StatelessWidget {
  const ChatFolderRail({
    super.key,
    required this.labels,
    required this.selected,
    required this.unread,
    required this.settingsUnread,
    required this.settingsSelected,
    required this.onFolder,
    required this.onSettings,
  });

  static const width = 86.0;
  final List<String> labels;
  final int? selected;
  final List<int> unread;
  final int settingsUnread;
  final bool settingsSelected;
  final ValueChanged<int> onFolder;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final row = (53 + MediaQuery.textScalerOf(context).scale(11) * 2.4).clamp(
      68.0,
      132.0,
    );
    return ColoredBox(
      color: style.surface,
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        key: const ValueKey('folder-rail-indicator'),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        top: (selected ?? 0) * row,
                        left: 0,
                        right: 0,
                        height: row - 5,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: style.selection,
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          for (var index = 0; index < labels.length; index++)
                            SizedBox(
                              height: row,
                              child: _destination(
                                context,
                                title: labels[index],
                                icon: switch (index) {
                                  0 => Icons.forum_outlined,
                                  1 => Icons.person_outline_rounded,
                                  2 => Icons.tag_rounded,
                                  _ => Icons.folder_outlined,
                                },
                                active: index == selected,
                                count: unread[index],
                                onTap: () => onFolder(index),
                              ),
                            ),
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
      ),
    );
  }

  Widget _destination(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool active,
    required int count,
    bool fill = false,
    required VoidCallback onTap,
  }) {
    final style = MeshStyle.of(context);
    final foreground = active ? style.accent : style.secondary;
    final shape = BorderRadius.circular(14);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Semantics(
        selected: active,
        button: true,
        child: Material(
          color: fill ? style.selection : Colors.transparent,
          borderRadius: shape,
          child: InkWell(
            borderRadius: shape,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: foreground, fontSize: 11),
                    ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
