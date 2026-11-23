// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';

import 'package:flutter/material.dart';

import 'mesh_icon.dart';
import 'profile_page.dart';
import 'profile_wallpaper.dart';
import 'style.dart';

typedef _Board = ({String name, String image});

class _BoardCatalog {
  final byModel = <int, _Board>{};
  final byName = <String, _Board>{};

  static String _normalize(String name) => name.toLowerCase().replaceAll(
    RegExp(r'lilygo|heltecautomation|seeedstudio|[^a-z0-9]'),
    '',
  );

  static Future<_BoardCatalog> read(AssetBundle bundle) async {
    final catalog = _BoardCatalog();
    final rows = jsonDecode(
      await bundle.loadString('assets/boards/catalog.json'),
    ) as Map<String, dynamic>;
    for (final entry in rows.entries) {
      final value = entry.value as Map<String, dynamic>;
      final board = (
        name: value['name'] as String,
        image: value['image'] as String,
      );
      catalog.byModel[int.parse(entry.key)] = board;
      for (final name in (value['aliases'] as List).cast<String>()) {
        if (name.isNotEmpty) catalog.byName[_normalize(name)] = board;
      }
    }
    return catalog;
  }

  _Board? find(int? model, String? name) =>
      byModel[model] ?? (name == null ? null : byName[_normalize(name)]);
}

class RadioProfilePage extends StatefulWidget {
  const RadioProfilePage({
    super.key,
    required this.publicKey,
    required this.boardName,
    this.boardModel,
    this.wallpaperSeed,
    required this.protocol,
    required this.heading,
    required this.padding,
    required this.children,
    this.leading,
    this.trailing,
    this.online = false,
  });

  final String? publicKey, boardName, wallpaperSeed;
  final int? boardModel;
  final String protocol, heading;
  final EdgeInsets padding;
  final List<Widget> children;
  final Widget? leading, trailing;
  final bool online;

  @override
  State<RadioProfilePage> createState() => _RadioProfilePageState();
}

class _RadioProfilePageState extends State<RadioProfilePage> {
  AssetBundle? _bundle;
  Future<_BoardCatalog>? _catalog;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bundle = DefaultAssetBundle.of(context);
    if (bundle != _bundle) {
      _bundle = bundle;
      _catalog = _BoardCatalog.read(bundle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final palette = ProfilePalette(
      widget.publicKey ?? widget.wallpaperSeed ?? 'radio',
    );
    return FutureBuilder<_BoardCatalog>(
      future: _catalog,
      builder: (context, snapshot) {
        final board = snapshot.data?.find(widget.boardModel, widget.boardName);
        final fallback = MeshIcon(
          Icons.memory_rounded,
          size: 46,
          color: style.text,
        );
        return ProfilePage(
          identity: widget.publicKey ?? widget.wallpaperSeed ?? 'radio',
          heading: widget.heading,
          title:
              board?.name ??
              widget.boardName ??
              tr(context, 'Модель платы неизвестна', 'Unknown board'),
          subtitle: widget.protocol,
          avatarSize: 104,
          padding: widget.padding,
          leading: widget.leading,
          trailing: widget.trailing,
          avatar: MeshAvatarPresence(
            size: 104,
            online: widget.online,
            child: ClipOval(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      palette.base(style),
                      palette.tone(19, style.dark ? .30 : .72),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: board == null
                      ? Center(child: fallback)
                      : Image.asset(
                          'assets/boards/${board.image}.webp',
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Center(child: fallback),
                        ),
                ),
              ),
            ),
          ),
          children: widget.children,
        );
      },
    );
  }
}
