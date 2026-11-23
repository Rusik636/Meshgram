// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';

import 'package:flutter/material.dart';

import 'emoji_text.dart';
import 'mesh_scroll_edge.dart';
import 'style.dart';

const quickReactions = [
  '👍',
  '❤️',
  '🔥',
  '😂',
  '🙏',
  '🎉',
  '🤝',
  '👌',
  '🤔',
  '👀',
  '😮',
  '👏',
  '💯',
  '🫡',
  '👎',
  '💔',
];

class _Emoji {
  _Emoji(List<dynamic> values)
    : glyph = values[0] as String,
      english = values[1] as String,
      russian = values[2] as String,
      search = values.join(' ').toLowerCase();

  final String glyph, english, russian, search;

  String label(BuildContext context) =>
      russian.isEmpty ? english : tr(context, russian, english);
}

class _EmojiCategory {
  const _EmojiCategory(this.id, this.russian, this.icon);

  final String id, russian;
  final IconData icon;
  String title(BuildContext context) => tr(context, russian, id);
}

const _categories = [
  _EmojiCategory('Smileys & Emotion', 'Эмоции', Icons.sentiment_satisfied_alt),
  _EmojiCategory('People & Body', 'Люди и жесты', Icons.back_hand_outlined),
  _EmojiCategory('Animals & Nature', 'Животные и природа', Icons.pets_outlined),
  _EmojiCategory('Food & Drink', 'Еда и напитки', Icons.restaurant_outlined),
  _EmojiCategory(
    'Travel & Places',
    'Путешествия',
    Icons.directions_car_outlined,
  ),
  _EmojiCategory('Activities', 'Спорт и занятия', Icons.sports_soccer_outlined),
  _EmojiCategory('Objects', 'Предметы', Icons.lightbulb_outline_rounded),
  _EmojiCategory('Symbols', 'Символы', Icons.favorite_border_rounded),
  _EmojiCategory('Flags', 'Флаги', Icons.flag_outlined),
];

const _catalogAsset = 'assets/emoji/unicode17.json';

final _skinTone = RegExp(r'[\u{1F3FB}-\u{1F3FF}]', unicode: true);

// Unicode uses a different sequence for some pairs with independent tones.
const _compoundBases = {
  '🫱‍🫲': '🤝',
  '🧑‍🐰‍🧑': '👯',
  '👨‍🐰‍👨': '👯‍♂',
  '👩‍🐰‍👩': '👯‍♀',
  '🧑‍🫯‍🧑': '🤼',
  '👨‍🫯‍👨': '🤼‍♂',
  '👩‍🫯‍👩': '🤼‍♀',
  '👩‍🤝‍👩': '👭',
  '👩‍🤝‍👨': '👫',
  '👨‍🤝‍👨': '👬',
  '🧑‍❤‍💋‍🧑': '💏',
  '🧑‍❤‍🧑': '💑',
};

class EmojiCatalog {
  EmojiCatalog._(Map<String, List<_Emoji>> groups) {
    for (final entry in groups.entries) {
      final bases = <String, _Emoji>{};
      final variants = <_Emoji>[];
      for (final emoji in entry.value) {
        final key = _emojiKey(emoji.glyph);
        _qualifiedGlyphs[key] = emoji.glyph;
        if (_skinTone.hasMatch(key)) {
          variants.add(emoji);
        } else {
          bases[key] = emoji;
        }
      }
      for (final emoji in variants) {
        final stem = _emojiKey(emoji.glyph).replaceAll(_skinTone, '');
        final base = bases[_compoundBases[stem] ?? stem];
        if (base == null) {
          // Keep additional sequences available if the catalog gains new pairs.
          bases.putIfAbsent(stem, () => emoji);
        } else {
          (_variants[base] ??= []).add(emoji);
        }
      }
      _groups[entry.key] = bases.values.toList();
    }
  }

  final _groups = <String, List<_Emoji>>{};
  final _qualifiedGlyphs = <String, String>{};
  final _variants = <_Emoji, List<_Emoji>>{};

  static String _emojiKey(String glyph) => glyph.replaceAll('\ufe0f', '');

  static Future<EmojiCatalog> load(AssetBundle bundle) =>
      bundle.loadStructuredData(_catalogAsset, (raw) async {
        final groups = (jsonDecode(raw) as Map)['groups'] as Map;
        return EmojiCatalog._({
          for (final entry in groups.entries)
            entry.key as String: [
              for (final row in entry.value as List)
                _Emoji(row as List<dynamic>),
            ],
        });
      });

  String? singleEmoji(String text) => _qualifiedGlyphs[_emojiKey(text.trim())];

  bool _matches(_Emoji emoji, String query) =>
      emoji.search.contains(query) ||
      (_variants[emoji]?.any((variant) => variant.search.contains(query)) ??
          false);
}

class EmojiPicker extends StatefulWidget {
  const EmojiPicker({
    super.key,
    required this.gridHeight,
    required this.onSelect,
    required this.onCollapse,
  });

  final double gridHeight;
  final ValueChanged<String> onSelect;
  final VoidCallback onCollapse;

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  AssetBundle? _bundle;
  late Future<EmojiCatalog> _data;
  var _category = _categories.first;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bundle = DefaultAssetBundle.of(context);
    if (_bundle != bundle) {
      _bundle = bundle;
      _data = EmojiCatalog.load(bundle);
    }
  }

  void _retry() {
    final bundle = _bundle!;
    bundle.evict(_catalogAsset);
    setState(() => _data = EmojiCatalog.load(bundle));
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _startAtTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _showTones(
    BuildContext anchor,
    _Emoji emoji,
    List<_Emoji> variants,
  ) async {
    final navigator = Navigator.of(anchor);
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    final target = anchor.findRenderObject()! as RenderBox;
    final bounds =
        target.localToGlobal(Offset.zero, ancestor: overlay) & target.size;
    final above = bounds.top - (variants.length > 5 ? 236 : 60);
    final style = MeshStyle.of(anchor);
    final selected = await showMenu<String>(
      context: anchor,
      position: RelativeRect.fromSize(
        bounds.shift(Offset(0, above > 0 ? above - bounds.top : bounds.height)),
        overlay.size,
      ),
      color: style.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      menuPadding: const EdgeInsets.all(6),
      semanticLabel: tr(anchor, 'Оттенки кожи', 'Skin tones'),
      popUpAnimationStyle: MediaQuery.disableAnimationsOf(anchor)
          ? AnimationStyle.noAnimation
          : null,
      items: [
        _ToneMenu([emoji, ...variants]),
      ],
    );
    if (mounted && selected != null) widget.onSelect(selected);
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final query = _search.text.trim().toLowerCase();
    return MessageMenuSurface(
      radius: 26,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 9, 6, 3),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) {
                      _startAtTop();
                      setState(() {});
                    },
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      hintText: tr(context, 'Поиск эмодзи', 'Search emoji'),
                      prefixIcon: const Icon(Icons.search_rounded, size: 19),
                      filled: true,
                      fillColor: style.field,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr(context, 'Свернуть эмодзи', 'Collapse emoji'),
                  onPressed: widget.onCollapse,
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
              ],
            ),
          ),
          if (query.isEmpty)
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final category in _categories)
                    IconButton(
                      tooltip: category.title(context),
                      isSelected: category == _category,
                      style: IconButton.styleFrom(
                        foregroundColor: category == _category
                            ? style.accent
                            : style.secondary,
                        backgroundColor: category == _category
                            ? style.selection
                            : Colors.transparent,
                      ),
                      onPressed: () {
                        _startAtTop();
                        setState(() => _category = category);
                      },
                      icon: Icon(category.icon, size: 20),
                    ),
                ],
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(17, 5, 12, 4),
              child: Text(
                query.isEmpty
                    ? _category.title(context)
                    : tr(context, 'Результаты', 'Results'),
                style: TextStyle(
                  color: style.secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SizedBox(
            height: widget.gridHeight,
            child: FutureBuilder(
              future: _data,
              builder: (context, snapshot) {
                final catalog = snapshot.data;
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: _retry,
                      child: Text(
                        tr(context, 'Повторить загрузку', 'Retry loading'),
                      ),
                    ),
                  );
                }
                if (catalog == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = catalog._groups;
                final emoji = query.isEmpty
                    ? (data[_category.id] ?? <_Emoji>[])
                    : [
                        for (final item in data.values.expand((items) => items))
                          if (catalog._matches(item, query)) item,
                      ];
                if (emoji.isEmpty) {
                  return Center(
                    child: Text(
                      tr(context, 'Эмодзи не найдены', 'No emoji found'),
                    ),
                  );
                }
                return MeshScrollViewport(
                  tint: style.surface,
                  edgeExtent: 12,
                  child: GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(9, 0, 9, 9),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 49,
                        ),
                    itemCount: emoji.length,
                    itemBuilder: (context, index) {
                      final entry = emoji[index];
                      final variants = catalog._variants[entry];
                      return Builder(
                        builder: (context) => IconButton(
                          tooltip: entry.label(context),
                          onPressed: () => widget.onSelect(entry.glyph),
                          onLongPress: variants == null
                              ? null
                              : () => _showTones(context, entry, variants),
                          icon: Text(
                            entry.glyph,
                            style: emojiGlyphStyle(
                              const TextStyle(fontSize: 24),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ToneMenu extends PopupMenuEntry<String> {
  const _ToneMenu(this.choices);

  final List<_Emoji> choices;

  @override
  double get height => 44;

  @override
  bool represents(String? value) => false;

  @override
  State<_ToneMenu> createState() => _ToneMenuState();
}

class _ToneMenuState extends State<_ToneMenu> {
  @override
  Widget build(BuildContext context) => Wrap(
    children: [
      for (final emoji in widget.choices)
        IconButton(
          tooltip: emoji.label(context),
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          onPressed: () => Navigator.of(context).pop(emoji.glyph),
          icon: Text(
            emoji.glyph,
            style: emojiGlyphStyle(const TextStyle(fontSize: 24)),
          ),
        ),
    ],
  );
}
