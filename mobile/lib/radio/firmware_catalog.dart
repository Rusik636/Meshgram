// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';

import 'package:flutter/services.dart';

enum FirmwareChip {
  esp32('esp32', espId: 0, headerOffset: 0x1000),
  esp32s3('esp32s3', espId: 9),
  esp32c3('esp32c3', espId: 5),
  esp32c6('esp32c6', espId: 13),
  nrf52840('nrf52840', uf2Family: 0xada52840),
  rp2040('rp2040', uf2Family: 0xe48bff56);

  const FirmwareChip(
    this.nameForTool, {
    this.espId,
    this.uf2Family,
    this.headerOffset = 0,
  });
  final String nameForTool;
  final int? espId, uf2Family;
  final int headerOffset;
  bool get usesUf2 => uf2Family != null;
  String get extension => usesUf2 ? 'uf2' : 'bin';
}

class FirmwareTarget {
  const FirmwareTarget({
    required this.project,
    required this.repository,
    required this.role,
    required this.chip,
    required this.pattern,
    this.archive,
    this.releasePrefix,
    this.warning,
    this.eraser,
  });
  final String project, repository, role, pattern;
  final String? archive, releasePrefix, warning, eraser;
  final FirmwareChip chip;

  RegExp filePattern(String version) {
    final fileNamePattern = pattern.replaceAll(
      '{version}',
      RegExp.escape(version),
    );
    return RegExp('^$fileNamePattern\$', caseSensitive: false);
  }
}

class FirmwareBoard {
  const FirmwareBoard({
    required this.name,
    required this.artwork,
    required this.manufacturer,
    required this.aliases,
    required this.targets,
  });
  final String name, artwork, manufacturer;
  final List<String> aliases;
  final List<FirmwareTarget> targets;

  Iterable<String> get protocols =>
      targets.map((target) => target.project).toSet();

  bool matches(String query) {
    final search = [name, manufacturer, ...aliases].join(' ').toLowerCase();
    return query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .every(search.contains);
  }
}

class FirmwareCatalog {
  const FirmwareCatalog(this.boards);
  final List<FirmwareBoard> boards;

  static Future<FirmwareCatalog> read(AssetBundle bundle) async {
    final data = await Future.wait([
      bundle.loadString('assets/boards/catalog.json'),
      bundle.loadString('assets/boards/firmware.json'),
    ]);
    final boards = jsonDecode(data.first) as Map<String, dynamic>;
    final projects = (jsonDecode(data.last) as List)
        .cast<Map<String, dynamic>>();
    final targets = <String, List<FirmwareTarget>>{};
    for (final project in projects) {
      final label = project['name'] as String;
      for (final definition
          in (project['targets'] as List).cast<Map<String, dynamic>>()) {
        targets
            .putIfAbsent(definition['board'] as String, () => [])
            .add(
              FirmwareTarget(
                project: label,
                repository: project['repository'] as String,
                role: definition['role'] as String,
                chip: FirmwareChip.values.byName(definition['chip'] as String),
                pattern: definition['pattern'] as String,
                archive: definition['archive'] as String?,
                releasePrefix: definition['releasePrefix'] as String?,
                warning: definition['warning'] as String?,
                eraser: definition['eraser'] as String?,
              ),
            );
      }
    }
    final supported =
        [
          for (final entry in targets.entries)
            FirmwareBoard(
              name: boards[entry.key]['name'] as String,
              artwork: boards[entry.key]['image'] as String,
              manufacturer: boards[entry.key]['manufacturer'] as String,
              aliases: (boards[entry.key]['aliases'] as List).cast<String>(),
              targets: entry.value,
            ),
        ]..sort((a, b) {
          final vendor = a.manufacturer.toLowerCase().compareTo(
            b.manufacturer.toLowerCase(),
          );
          return vendor != 0
              ? vendor
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    return FirmwareCatalog(supported);
  }
}
