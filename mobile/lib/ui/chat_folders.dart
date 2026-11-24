// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../mesh/network.dart';
import '../mesh/store.dart';
import 'haptics.dart';
import 'ios_control.dart';
import 'navigation.dart';
import 'page_route.dart';
import 'style.dart';

typedef ChatFolderEdit = ({String name, Set<String> chats});

Future<String?> nameNewChatFolder(BuildContext context) {
  var name = '';
  return showMeshDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final label = name.trim();
        void save() {
          if (label.isNotEmpty) Navigator.pop(context, label);
        }

        return MeshDialog(
          title: Text(tr(context, 'Новая папка', 'New folder')),
          content: TextFormField(
            autofocus: true,
            maxLength: 36,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: tr(context, 'Название', 'Name'),
              counterText: '',
            ),
            onChanged: (text) => setState(() => name = text),
            onFieldSubmitted: (_) => save(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context, 'Отмена', 'Cancel')),
            ),
            TextButton(
              onPressed: label.isEmpty ? null : save,
              child: Text(tr(context, 'Добавить', 'Add')),
            ),
          ],
        );
      },
    ),
  );
}

class ChatFolderTabs extends StatefulWidget {
  const ChatFolderTabs({
    super.key,
    required this.builtInLabels,
    required this.folders,
    required this.scrollController,
    required this.selected,
    required this.editing,
    required this.onSelect,
    required this.onReorder,
    required this.onEdit,
    required this.onDelete,
  });

  final List<String> builtInLabels;
  final List<ChatFolder> folders;
  final ScrollController scrollController;
  final int selected;
  final bool editing;
  final ValueChanged<int> onSelect;
  final ReorderCallback onReorder;
  final ValueChanged<String> onEdit, onDelete;

  @override
  State<ChatFolderTabs> createState() => _ChatFolderTabsState();
}

class _ChatFolderTabsState extends State<ChatFolderTabs>
    with SingleTickerProviderStateMixin {
  static const _padding = 4.0;
  static const _iosLensInset = 3.0;
  static const _gap = 3.0;
  static const _titleStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  bool _revealSelected = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(ChatFolderTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editing && !widget.editing) _revealSelected = true;
    _syncMotion();
  }

  void _syncMotion() {
    if (widget.editing &&
        widget.folders.isNotEmpty &&
        !MediaQuery.disableAnimationsOf(context)) {
      if (!_shake.isAnimating) _shake.repeat();
    } else if (_shake.isAnimating) {
      _shake.reset();
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  List<double> _tabWidths(List<String> labels, double maxWidth) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    );
    final titleStyle = DefaultTextStyle.of(context).style.merge(_titleStyle);
    final widths = List.generate(labels.length, (index) {
      painter.text = TextSpan(text: labels[index], style: titleStyle);
      painter.layout();
      final extra = widget.editing && index >= widget.builtInLabels.length
          ? 36
          : 0;
      return (painter.width.ceilToDouble() + 30 + extra).clamp(48.0, maxWidth);
    });
    painter.dispose();
    return widths;
  }

  Widget _nativeTabs(double height) {
    final style = MeshStyle.of(context);
    final labels = [
      ...widget.builtInLabels,
      for (final folder in widget.folders) folder.name,
    ];
    final titleSize = MediaQuery.textScalerOf(context).scale(15);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.maxWidth;
          final widths = _tabWidths(labels, math.max(48.0, viewport));
          final contentWidth = widths.fold(0.0, (sum, width) => sum + width);
          final extra = math.max(0.0, viewport - contentWidth) / labels.length;
          final segmentWidths = [for (final width in widths) width + extra];
          final edges = <double>[0];
          for (final width in segmentWidths) {
            edges.add(edges.last + width);
          }
          final scroll = widget.scrollController;
          if (_revealSelected) {
            _revealSelected = false;
            final selected = widget.selected.clamp(0, labels.length - 1);
            final center = (edges[selected] + edges[selected + 1]) / 2;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || widget.editing || !scroll.hasClients) return;
              scroll.jumpTo(
                (center - viewport / 2).clamp(
                  0.0,
                  scroll.position.maxScrollExtent,
                ),
              );
            });
          }
          void select(int index) {
            if (index < 0 || index >= labels.length) return;
            final changed = index != widget.selected;
            widget.onSelect(index);
            if (!changed || !scroll.hasClients) return;
            // Match the tap focus margin in Telegram iOS HorizontalTabsComponent.
            const lookahead = 100.0;
            var offset = scroll.offset;
            if (offset + viewport - lookahead < edges[index + 1]) {
              offset = edges[index + 1] - viewport + lookahead;
            }
            if (offset > edges[index] - lookahead) {
              offset = edges[index] - lookahead;
            }
            final target = offset.clamp(0.0, scroll.position.maxScrollExtent);
            if (target == scroll.offset) return;
            final duration = meshMotion(context);
            if (duration == Duration.zero) {
              scroll.jumpTo(target);
            } else {
              unawaited(
                scroll.animateTo(
                  target,
                  duration: duration,
                  curve: Curves.easeOutCubic,
                ),
              );
            }
          }

          return SingleChildScrollView(
            key: const ValueKey('native-chat-folder-scroll'),
            controller: scroll,
            primary: false,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: SizedBox(
              width: math.max(viewport, contentWidth),
              height: height,
              child: IosControl(
                kind: 'folderTabs',
                tapOnly: true,
                properties: {
                  'titleSize': titleSize,
                  'labels': labels,
                  'widths': segmentWidths,
                  'index': widget.selected,
                  'rtl': Directionality.of(context) == TextDirection.rtl,
                  'dark': style.dark,
                  'text': style.text.toARGB32(),
                  'accent': style.accent.toARGB32(),
                },
                onSelect: select,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tab({
    required int index,
    required double width,
    required String title,
    ChatFolder? folder,
    int? folderIndex,
  }) {
    final style = MeshStyle.of(context);
    final selected = widget.selected == index;
    final rearranging = widget.editing && folder != null;
    Widget content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _titleStyle.copyWith(
              color: selected ? style.accent : style.text,
            ),
          ),
        ),
        if (rearranging)
          SizedBox(
            width: 44,
            child: IconButton(
              tooltip: tr(
                context,
                'Удалить папку $title',
                'Delete folder $title',
              ),
              alignment: AlignmentDirectional.centerStart,
              padding: const EdgeInsetsDirectional.only(start: 8),
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                overlayColor: Colors.transparent,
                splashFactory: NoSplash.splashFactory,
              ),
              icon: const Icon(Icons.close_rounded, size: 17),
              color: style.secondary,
              onPressed: () => widget.onDelete(folder.id),
            ),
          ),
      ],
    );
    if (rearranging && !MediaQuery.disableAnimationsOf(context)) {
      final phase = (folderIndex! % 4) * math.pi / 2;
      content = AnimatedBuilder(
        animation: _shake,
        builder: (_, child) => Transform.rotate(
          angle: math.sin(_shake.value * 2 * math.pi + phase) * .045,
          child: child,
        ),
        child: content,
      );
    }
    final tab = Semantics(
      selected: selected,
      button: true,
      customSemanticsActions: rearranging
          ? {
              CustomSemanticsAction(
                label: tr(context, 'Изменить папку', 'Edit folder'),
              ): () =>
                  widget.onEdit(folder.id),
              if (folderIndex! > 0)
                CustomSemanticsAction(
                  label: tr(context, 'Переместить левее', 'Move earlier'),
                ): () =>
                    widget.onReorder(folderIndex, folderIndex - 1),
              if (folderIndex < widget.folders.length - 1)
                CustomSemanticsAction(
                  label: tr(context, 'Переместить правее', 'Move later'),
                ): () =>
                    widget.onReorder(folderIndex, folderIndex + 1),
            }
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: rearranging && selected
            ? () => widget.onEdit(folder.id)
            : () => widget.onSelect(index),
        onLongPress: folder == null || rearranging
            ? null
            : () => widget.onEdit(folder.id),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: 14,
            end: rearranging ? 0 : 14,
          ),
          child: content,
        ),
      ),
    );
    return Padding(
      key: folder == null ? null : ValueKey(folder.id),
      padding: const EdgeInsetsDirectional.only(end: _gap),
      child: SizedBox(
        width: width,
        child: rearranging
            ? ReorderableDelayedDragStartListener(
                index: folderIndex!,
                child: tab,
              )
            : tab,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = ChatFilters.contentHeight(context);
    final native = useIosControls && !widget.editing;
    // Telegram iOS gives the header panel a 40 pt strip at the default
    // text size, then uses one uniform inset for the lens and its scroll view.
    final barHeight = native
        ? math.min(height, math.max(40.0, height - 8))
        : height - 4;
    final viewportPadding = native
        ? const EdgeInsets.all(_iosLensInset)
        : const EdgeInsets.symmetric(horizontal: _padding);
    final viewportHeight = barHeight - viewportPadding.vertical;
    final viewport = Padding(
      padding: viewportPadding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          native ? viewportHeight / 2 : height / 2 - _padding,
        ),
        child: native
            ? _nativeTabs(viewportHeight)
            : _flutterTabs(viewportHeight),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: (height - barHeight) / 2,
      ),
      child: native
          ? DecoratedBox(
              decoration: ShapeDecoration(
                shape: StadiumBorder(
                  side: BorderSide(color: MeshStyle.of(context).separator),
                ),
              ),
              child: viewport,
            )
          : GlassSurface(modal: true, radius: height / 2, child: viewport),
    );
  }

  Widget _flutterTabs(double height) {
    final style = MeshStyle.of(context);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = widget.builtInLabels.length;
          final labels = [
            ...widget.builtInLabels,
            for (final folder in widget.folders) folder.name,
          ];
          final maxWidth = math.max(48.0, constraints.maxWidth);
          final widths = _tabWidths(labels, maxWidth);
          final selected = widget.selected.clamp(0, labels.length - 1);
          final start = widths
              .take(selected)
              .fold(0.0, (sum, width) => sum + width + _gap);
          Widget folderTab(BuildContext context, int position) {
            final index = count + position;
            return _tab(
              index: index,
              width: widths[index],
              title: labels[index],
              folder: widget.folders[position],
              folderIndex: position,
            );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              if (!widget.editing)
                IgnorePointer(
                  child: ListenableBuilder(
                    listenable: widget.scrollController,
                    builder: (context, indicator) {
                      final scroll = widget.scrollController;
                      final offset = scroll.hasClients ? scroll.offset : 0.0;
                      final rtl =
                          Directionality.of(context) == TextDirection.rtl;
                      return Transform.translate(
                        offset: Offset(rtl ? offset : -offset, 0),
                        child: indicator,
                      );
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedPositionedDirectional(
                          duration: meshMotion(context),
                          curve: Curves.easeOutCubic,
                          start: start,
                          top: 4,
                          bottom: 4,
                          width: widths[selected],
                          child: GlassSurface(
                            key: const ValueKey('chat-folder-indicator'),
                            nativeButtonMaterial: true,
                            radius: height / 2,
                            color: style.field,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              CustomScrollView(
                key: const ValueKey('chat-folder-scroll'),
                controller: widget.scrollController,
                primary: false,
                scrollDirection: Axis.horizontal,
                slivers: [
                  SliverToBoxAdapter(
                    child: Row(
                      children: [
                        for (var index = 0; index < count; index++)
                          _tab(
                            index: index,
                            width: widths[index],
                            title: labels[index],
                          ),
                      ],
                    ),
                  ),
                  if (widget.editing && widget.folders.isNotEmpty)
                    SliverReorderableList(
                      key: const ValueKey('chat-folder-reorder'),
                      itemBuilder: folderTab,
                      itemCount: widget.folders.length,
                      onReorderItem: widget.onReorder,
                      onReorderStart: (_) =>
                          unawaited(playMeshHaptic(MeshHaptic.selection)),
                      proxyDecorator: (child, index, animation) => Material(
                        color: style.surface,
                        borderRadius: BorderRadius.circular(height / 2),
                        child: child,
                      ),
                    )
                  else
                    SliverList.builder(
                      itemCount: widget.folders.length,
                      itemBuilder: folderTab,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<ChatFolderEdit?> editChatFolder(
  BuildContext context, {
  required List<Peer> chats,
  required ChatFolder folder,
}) {
  var name = folder.name;
  final selected = {...folder.chats};
  return Navigator.of(context).push<ChatFolderEdit>(
    meshPageRoute(
      context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                PageHeading(
                  tr(context, 'Изменить папку', 'Edit folder'),
                  sideWidth: 108,
                  leading: GlassButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    label: tr(context, 'Назад', 'Back'),
                    onTap: () => Navigator.pop(context),
                  ),
                  trailing: GlassActionButton(
                    fitContent: true,
                    label: tr(context, 'Готово', 'Save'),
                    onTap: name.trim().isEmpty
                        ? null
                        : () => Navigator.pop(context, (
                            name: name.trim(),
                            chats: selected,
                          )),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextFormField(
                    initialValue: name,
                    maxLength: 36,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: tr(context, 'Название', 'Name'),
                      counterText: '',
                    ),
                    onChanged: (text) => setState(() => name = text),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: chats.length,
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      return CheckboxListTile(
                        secondary: MeshAvatar(
                          chat.name,
                          size: 38,
                          channel: chat.channel,
                        ),
                        title: Text(chat.name),
                        value: selected.contains(chat.id),
                        onChanged: (checked) => setState(() {
                          if (checked == true) {
                            selected.add(chat.id);
                          } else {
                            selected.remove(chat.id);
                          }
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
