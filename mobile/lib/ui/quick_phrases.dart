// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart' show HardwareKeyboard;

import '../mesh/store.dart';
import 'desktop_interaction.dart' show meshDesktop, meshDesktopButtonStyle;
import 'haptics.dart';
import 'style.dart';

List<String> _phrases(BuildContext context, MeshStore store) =>
    store.quickPhrases ??
    [
      tr(context, 'На месте', 'I’m here'),
      tr(context, 'Задержусь', 'I’m running late'),
      tr(context, 'Пришли координаты', 'Send me your coordinates'),
    ];

class QuickPhraseStrip extends StatefulWidget {
  const QuickPhraseStrip({
    super.key,
    required this.store,
    required this.onSelect,
    required this.onExpand,
    required this.progress,
  });

  final MeshStore store;
  final ValueChanged<String>? onSelect;
  final VoidCallback? onExpand;
  final double progress;

  static double extent(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(14) + 18).clamp(48.0, 80.0);

  @override
  State<QuickPhraseStrip> createState() => _QuickPhraseStripState();
}

class _QuickPhraseStripState extends State<QuickPhraseStrip> {
  static const _expandThreshold = 46.0;
  final _scroll = ScrollController();
  int? _pointer;
  double _pull = 0;

  void _scrollWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dx != 0 ||
        event.scrollDelta.dy == 0 ||
        HardwareKeyboard.instance.isShiftPressed ||
        !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final delta = position.axisDirection == AxisDirection.left
        ? -event.scrollDelta.dy
        : event.scrollDelta.dy;
    final target = position.pixels + delta;
    if (target.clamp(position.minScrollExtent, position.maxScrollExtent) ==
        position.pixels) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) => position.pointerScroll(delta),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _updatePull(double value) {
    final pull = math.max(0.0, value);
    if (pull == _pull) return;
    final reachedThreshold =
        _pull < _expandThreshold && pull >= _expandThreshold;
    setState(() => _pull = pull);
    if (reachedThreshold) unawaited(playMeshHaptic(MeshHaptic.medium));
  }

  void _finishPull(PointerEvent event, {required bool released}) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final expand = released && _pull >= _expandThreshold;
    _updatePull(0);
    if (expand) widget.onExpand?.call();
  }

  bool _trackPull(ScrollNotification event) {
    if (_pointer == null ||
        widget.onExpand == null ||
        event.depth != 0 ||
        event.metrics.axis != Axis.horizontal) {
      return false;
    }
    if (event is OverscrollNotification && event.dragDetails != null) {
      _updatePull(_pull + event.overscroll);
    } else if (_pull > 0 &&
        event is ScrollUpdateNotification &&
        event.dragDetails != null) {
      _updatePull(_pull + math.min(0, event.scrollDelta ?? 0));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final phrases = _phrases(context, widget.store);
    final select = widget.onSelect;
    final expand = widget.onExpand;
    final height = QuickPhraseStrip.extent(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pulling = _pull > 0;
    final ready = _pull >= _expandThreshold;
    final pullProgress = (_pull / _expandThreshold).clamp(0.0, 1.5);
    final contentOpacity = const Interval(
      .34,
      .88,
      curve: Curves.easeOut,
    ).transform(widget.progress);
    final iconOpacity = 1 - const Interval(0, .38).transform(widget.progress);
    final content = Row(
      children: [
        Expanded(
          child: Listener(
            onPointerDown: (event) => _pointer ??= event.pointer,
            onPointerUp: (event) => _finishPull(event, released: true),
            onPointerCancel: (event) => _finishPull(event, released: false),
            child: NotificationListener<ScrollNotification>(
              onNotification: _trackPull,
              child: ListView.separated(
                key: const ValueKey('quick-phrase-scroll'),
                primary: false,
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: phrases.length,
                separatorBuilder: (_, _) => VerticalDivider(
                  width: 2,
                  thickness: 1,
                  indent: (height - 18) / 2,
                  endIndent: (height - 18) / 2,
                  color: style.secondary.withValues(alpha: .32),
                ),
                itemBuilder: (context, index) {
                  final phrase = phrases[index];
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: TextButton(
                      style: meshDesktopButtonStyle(
                        context,
                        TextButton.styleFrom(
                          foregroundColor: style.text,
                          disabledForegroundColor: style.secondary,
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      onPressed: select == null ? null : () => select(phrase),
                      child: Text(
                        phrase,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        SizedBox.square(
          dimension: 48,
          child: MeshIconButton(
            icon: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 130),
              child: pulling
                  ? Transform.scale(
                      key: const ValueKey('pull-arrow'),
                      scale: reduceMotion ? 1 : 1 + .45 * pullProgress,
                      child: Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 20,
                        color: ready ? style.accent : null,
                      ),
                    )
                  : const Icon(
                      Icons.edit_outlined,
                      key: ValueKey('quick-phrase-pencil'),
                      size: 20,
                    ),
            ),
            color: style.text,
            label: tr(
              context,
              'Развернуть быстрые фразы',
              'Expand quick phrases',
            ),
            onPressed: expand == null
                ? null
                : () {
                    unawaited(playMeshHaptic(MeshHaptic.selection));
                    expand();
                  },
          ),
        ),
      ],
    );
    return GlassSurface(
      nativeButtonMaterial: true,
      radius: height / 2,
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (contentOpacity > 0)
              Opacity(
                opacity: contentOpacity,
                child: Listener(
                  onPointerSignal: meshDesktop(context) ? _scrollWheel : null,
                  child: content,
                ),
              ),
            if (iconOpacity > 0)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Opacity(
                  opacity: iconOpacity,
                  child: SizedBox(
                    width: 48,
                    child: Icon(Icons.short_text_rounded, color: style.text),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> pickQuickPhrase(BuildContext context, MeshStore store) {
  var phrases = _phrases(context, store);
  return showMeshSheet<String>(
    context: context,
    dragArea: MeshSheetGrip.height,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> edit(int? index) async {
          final text = await _editPhrase(
            context,
            index == null ? null : phrases[index],
          );
          if (!context.mounted || text == null) return;
          final next = [...phrases];
          if (index == null) {
            next.add(text);
          } else if (text.isEmpty) {
            next.removeAt(index);
          } else {
            next[index] = text;
          }
          if (await store.setQuickPhrases(next) && context.mounted) {
            setState(() => phrases = next);
          } else if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text(
                  tr(
                    context,
                    'Не удалось сохранить фразы',
                    'Could not save phrases',
                  ),
                ),
              ),
            );
          }
        }

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .56,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 12, 28, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          container: true,
                          header: true,
                          child: Text(
                            tr(context, 'Быстрые фразы', 'Quick phrases'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ),
                      Semantics(
                        container: true,
                        child: GlassButton(
                          icon: Icons.add_rounded,
                          label: tr(context, 'Добавить фразу', 'Add phrase'),
                          onTap: () => edit(null),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    itemCount: phrases.length,
                    separatorBuilder: (context, _) => Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: MeshStyle.of(context).separator,
                    ),
                    itemBuilder: (context, index) {
                      final phrase = phrases[index];
                      void editPhrase() => edit(index);
                      return Semantics(
                        customSemanticsActions: {
                          CustomSemanticsAction(
                            label: tr(context, 'Изменить фразу', 'Edit phrase'),
                          ): editPhrase,
                        },
                        child: ListTile(
                          title: Text(
                            phrase,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, phrase),
                          onLongPress: editPhrase,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<String?> _editPhrase(BuildContext context, String? phrase) {
  var value = phrase ?? '';
  return showMeshDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => MeshDialog(
        title: Text(
          phrase == null
              ? tr(context, 'Добавить фразу', 'Add phrase')
              : tr(context, 'Изменить фразу', 'Edit phrase'),
        ),
        content: TextFormField(
          initialValue: value,
          decoration: InputDecoration(
            labelText: tr(context, 'Текст фразы', 'Phrase text'),
          ),
          textCapitalization: TextCapitalization.sentences,
          maxLength: 280,
          minLines: 2,
          maxLines: 4,
          onChanged: (text) => setState(() => value = text),
        ),
        actions: [
          if (phrase != null)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: Text(tr(context, 'Удалить', 'Delete')),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          FilledButton(
            onPressed: value.trim().isEmpty
                ? null
                : () => Navigator.pop(context, value.trim()),
            child: Text(tr(context, 'Сохранить', 'Save')),
          ),
        ],
      ),
    ),
  );
}
