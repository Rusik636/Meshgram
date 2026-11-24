// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../mesh/store.dart';
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
  });

  final MeshStore store;
  final ValueChanged<String>? onSelect;
  final VoidCallback? onExpand;

  @override
  State<QuickPhraseStrip> createState() => _QuickPhraseStripState();
}

class _QuickPhraseStripState extends State<QuickPhraseStrip> {
  double _pull = 0;
  bool _openedByDrag = false;

  bool _trackPull(ScrollNotification event) {
    if (event.depth != 0 || event.metrics.axis != Axis.horizontal) return false;
    if (event is ScrollStartNotification || event is ScrollEndNotification) {
      _openedByDrag = false;
      _pull = 0;
    } else if (event is ScrollUpdateNotification) {
      _pull = 0;
    } else if (event is OverscrollNotification &&
        event.dragDetails != null &&
        event.overscroll > 0 &&
        !_openedByDrag &&
        widget.onExpand != null) {
      _pull += event.overscroll;
      if (_pull >= 46) {
        _openedByDrag = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onExpand?.call();
        });
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final phrases = _phrases(context, widget.store);
    final select = widget.onSelect;
    final height = (MediaQuery.textScalerOf(context).scale(14) + 18).clamp(
      48.0,
      80.0,
    );
    return Row(
      children: [
        Expanded(
          child: GlassSurface(
            modal: true,
            radius: height / 2,
            child: SizedBox(
              height: height,
              child: NotificationListener<ScrollNotification>(
                onNotification: _trackPull,
                child: ListView.separated(
                  key: const ValueKey('quick-phrase-scroll'),
                  primary: false,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: phrases.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 2),
                  itemBuilder: (context, index) {
                    final phrase = phrases[index];
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: style.text,
                          disabledForegroundColor: style.secondary,
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
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
        ),
        const SizedBox(width: 4),
        GlassButton(
          icon: Icons.keyboard_arrow_up_rounded,
          label: tr(
            context,
            'Развернуть быстрые фразы',
            'Expand quick phrases',
          ),
          onTap: widget.onExpand,
        ),
      ],
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
