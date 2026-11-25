// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../mesh/network.dart';
import '../radio/desktop_usb.dart';
import '../radio/firmware_catalog.dart';
import '../radio/firmware_flasher.dart';
import 'desktop_interaction.dart' show desktopPressedKeys;
import 'firmware_filters.dart';
import 'macos_glass.dart';
import 'page_route.dart';
import 'style.dart';

const firmwareBoardRoute = '/firmware/board';

class FirmwarePage extends StatefulWidget {
  const FirmwarePage({super.key, required this.usb});
  final DesktopUsbTransport usb;

  @override
  State<FirmwarePage> createState() => _FirmwarePageState();
}

class _FirmwarePageState extends State<FirmwarePage> {
  late final Future<FirmwareCatalog> _catalog = FirmwareCatalog.read(
    DefaultAssetBundle.of(context),
  );
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _resultsScroll = ScrollController();
  FirmwareSelection _selection = {};
  bool _filtersOpen = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_findShortcut);
  }

  bool _findShortcut(KeyEvent event) {
    if (event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.keyF &&
            event.physicalKey != PhysicalKeyboardKey.keyF) ||
        ModalRoute.isCurrentOf(context) != true) {
      return false;
    }
    final modifier = Theme.of(context).platform == TargetPlatform.macOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control;
    final keys = desktopPressedKeys(context);
    if (!keys.contains(modifier) ||
        keys.contains(LogicalKeyboardKey.shift) ||
        keys.contains(LogicalKeyboardKey.alt)) {
      return false;
    }
    _searchFocus.requestFocus();
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_findShortcut);
    _search.dispose();
    _searchFocus.dispose();
    _resultsScroll.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  void _openBoard(FirmwareBoard board) => Navigator.of(context).push(
    meshPageRoute<void>(
      context,
      settings: const RouteSettings(name: firmwareBoardRoute),
      builder: (_) =>
          _FlashBoardPage(board: board, tool: FirmwareFlasher(widget.usb)),
    ),
  );

  Widget _searchBox(bool glass, MeshStyle style) {
    final search = TextField(
      controller: _search,
      focusNode: _searchFocus,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: tr(
          context,
          'Модель, чип или протокол',
          'Model, chip or protocol',
        ),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _query.isEmpty
            ? null
            : MeshIconButton(
                label: tr(context, 'Очистить поиск', 'Clear search'),
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: _clearSearch,
              ),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      onChanged: (value) => setState(() => _query = value),
    );
    return glass
        ? GlassSurface(radius: 24, child: search)
        : Material(
            color: style.searchField,
            borderRadius: BorderRadius.circular(16),
            child: search,
          );
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final macGlass = MacGlass.enabled(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: LayoutBuilder(
              builder: (context, bounds) {
                final inset = bounds.maxWidth < 520 ? 16.0 : 24.0;
                final wideToolbar = macGlass && bounds.maxWidth >= 660;
                final title = Row(
                  children: [
                    GlassButton(
                      icon: Icons.arrow_back_rounded,
                      label: tr(context, 'Назад', 'Back'),
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        tr(context, 'Прошивки', 'Firmware'),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        inset,
                        macGlass ? 16 : 10,
                        inset,
                        0,
                      ),
                      child: wideToolbar
                          ? Row(
                              children: [
                                Expanded(child: title),
                                const SizedBox(width: 18),
                                SizedBox(
                                  width: 310,
                                  child: _searchBox(macGlass, style),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                title,
                                const SizedBox(height: 12),
                                _searchBox(macGlass, style),
                              ],
                            ),
                    ),
                    Expanded(
                      child: FutureBuilder(
                        future: _catalog,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                tr(
                                  context,
                                  'Не удалось открыть каталог плат',
                                  'Could not open the board catalog',
                                ),
                              ),
                            );
                          }
                          final catalog = snapshot.data;
                          if (catalog == null) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return _boards(
                            catalog,
                            style,
                            macGlass: macGlass,
                            width: bounds.maxWidth,
                            inset: inset,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _toggleFilter(FirmwareFacet facet, String value) {
    final values = {...?_selection[facet]};
    if (!values.remove(value)) values.add(value);
    setState(() {
      _selection = {..._selection};
      if (values.isEmpty) {
        _selection.remove(facet);
      } else {
        _selection[facet] = values;
      }
    });
  }

  Widget _boards(
    FirmwareCatalog catalog,
    MeshStyle style, {
    required bool macGlass,
    required double width,
    required double inset,
  }) {
    final options = {
      for (final facet in FirmwareFacet.values) facet: facet.options(catalog),
    };
    final boards = catalog.boards
        .where(
          (board) =>
              matchesFirmwareSelection(board, _selection) &&
              board.matches(_query),
        )
        .toList();
    final label = tr(context, 'Фильтры', 'Filters');
    final native = MacGlass.firmwareFiltersAvailable;
    void togglePanel() {
      if (!_filtersOpen && _resultsScroll.hasClients) {
        _resultsScroll.jumpTo(0);
      }
      setState(() => _filtersOpen = !_filtersOpen);
    }

    final icon = _filtersOpen ? Icons.expand_less_rounded : Icons.tune_rounded;
    final button = native
        ? GlassActionButton(
            label: label,
            icon: icon,
            fitContent: true,
            height: 36,
            primary: false,
            onTap: togglePanel,
          )
        : OutlinedButton.icon(
            onPressed: togglePanel,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
    final scaledText = MediaQuery.textScalerOf(context).scale(16);
    final columns =
        ((width - 2 * inset + 12) /
                (math.max(macGlass ? 224 : 194, scaledText * 10) + 12))
            .floor()
            .clamp(1, 5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 10, inset, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: button),
              const SizedBox(width: 12),
              Text(
                tr(
                  context,
                  'Плат: ${boards.length}',
                  'Boards: ${boards.length}',
                ),
                style: TextStyle(color: style.secondary, fontSize: 13),
              ),
            ],
          ),
        ),
        Expanded(
          child: CustomScrollView(
            controller: _resultsScroll,
            slivers: [
              SliverToBoxAdapter(
                key: const ValueKey('firmware-filter-panel'),
                child: AnimatedSize(
                  alignment: Alignment.topCenter,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeInOutCubic,
                  child: _filtersOpen
                      ? Padding(
                          padding: EdgeInsets.fromLTRB(inset, 0, inset, 12),
                          child: native
                              ? Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 420,
                                    ),
                                    child: MacFirmwareFilterPanel(
                                      options: options,
                                      selection: _selection,
                                      dark: style.dark,
                                      onToggle: _toggleFilter,
                                    ),
                                  ),
                                )
                              : FirmwareFilterPanel(
                                  options: options,
                                  selection: _selection,
                                  onToggle: _toggleFilter,
                                ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              if (_selection.isNotEmpty)
                SliverPadding(
                  key: const ValueKey('firmware-filter-tags'),
                  padding: EdgeInsets.fromLTRB(inset, 0, inset, 12),
                  sliver: SliverToBoxAdapter(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final facet in FirmwareFacet.values)
                          for (final value in options[facet]!)
                            if (_selection[facet]?.contains(value) ?? false)
                              FirmwareFilterTag(
                                key: ValueKey((facet, value)),
                                value: value,
                                onRemove: () => _toggleFilter(facet, value),
                              ),
                      ],
                    ),
                  ),
                ),
              if (boards.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(inset),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 32,
                            color: style.secondary,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            tr(context, 'Платы не найдены', 'No boards found'),
                          ),
                          TextButton(
                            onPressed: () {
                              _search.clear();
                              setState(() {
                                _query = '';
                                _selection = {};
                              });
                            },
                            child: Text(
                              tr(
                                context,
                                'Сбросить поиск и фильтры',
                                'Reset search and filters',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  key: const ValueKey('firmware-board-grid'),
                  padding: EdgeInsets.fromLTRB(inset, 0, inset, inset),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: 146 + scaledText * 4.5,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    itemCount: boards.length,
                    itemBuilder: (context, index) {
                      final board = boards[index];
                      return _BoardCard(board, onTap: () => _openBoard(board));
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard(this.board, {required this.onTap});
  final FirmwareBoard board;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final metadata = [
      ...board.chips.map((chip) => chip.label),
      ...board.protocols.where((protocol) => protocol != 'Meshtastic'),
    ];
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: style.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: style.separator.withValues(alpha: .65)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Ink(
                color: Color.lerp(style.surface, style.searchField, .46),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: _BoardArtwork(board),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 9, 10, 11),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          board.manufacturer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: style.secondary,
                          ),
                        ),
                        Text(
                          board.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          metadata.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: style.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: style.secondary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardArtwork extends StatelessWidget {
  const _BoardArtwork(this.board);
  final FirmwareBoard board;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/boards/${board.artwork}.webp',
    fit: BoxFit.contain,
    excludeFromSemantics: true,
    errorBuilder: (_, _, _) => const Icon(Icons.memory_rounded, size: 42),
  );
}

class _FlashBoardPage extends StatefulWidget {
  const _FlashBoardPage({required this.board, required this.tool});
  final FirmwareBoard board;
  final FirmwareFlasher tool;

  @override
  State<_FlashBoardPage> createState() => _FlashBoardPageState();
}

class _FlashBoardPageState extends State<_FlashBoardPage> {
  late FirmwareTarget _target = widget.board.targets.first;
  FirmwareInstallMode _mode = FirmwareInstallMode.update;
  List<FirmwareRelease> _versions = const [];
  FirmwareRelease? _release;
  PreparedFirmware? _prepared;
  String? _port, _volume, _error, _erasedBoard;
  double? _progress;
  List<UsbPort> _ports = const [];
  final List<String> _log = [];
  bool _loading = false, _writing = false, _complete = false;
  bool _versionsLoading = false, _versionsFailed = false;
  bool get _busy => _loading || _writing;
  bool get _changingBlocked => _busy || _erasedBoard != null;
  bool get _canClean => !_target.chip.usesUf2 || _target.eraser != null;
  List<FirmwareTarget> get _variants => [
    for (final target in widget.board.targets)
      if (target.project == _target.project) target,
  ];

  @override
  void initState() {
    super.initState();
    if (!_target.chip.usesUf2) _refreshPorts();
    unawaited(_loadVersions(_target));
  }

  @override
  void dispose() {
    if (_prepared case final prepared? when !_writing) {
      unawaited(prepared.dispose());
    }
    super.dispose();
  }

  Future<void> _loadVersions(FirmwareTarget target) async {
    setState(() {
      _versionsLoading = true;
      _versionsFailed = false;
    });
    try {
      final versions = await widget.tool.versions(target);
      if (!mounted || _target != target) return;
      setState(() {
        _versions = versions;
        _release =
            versions.where((version) => !version.prerelease).firstOrNull ??
            versions.firstOrNull;
      });
    } on Object {
      if (mounted && _target == target) setState(() => _versionsFailed = true);
    } finally {
      if (mounted && _target == target) {
        setState(() => _versionsLoading = false);
      }
    }
  }

  void _refreshPorts() {
    try {
      final ports = widget.tool.usb.ports();
      setState(() {
        _ports = ports;
        if (!ports.any((port) => port.path == _port)) _port = null;
        if (_port == null && ports.length == 1) _port = ports.single.path;
        _error = null;
      });
    } on Object catch (error) {
      setState(() => _error = error.toString());
    }
  }

  void _clearPrepared() {
    final previous = _prepared;
    _prepared = null;
    _complete = false;
    _error = null;
    _progress = null;
    _log.clear();
    if (previous != null) unawaited(previous.dispose());
  }

  void _selectTarget(FirmwareTarget target) {
    if (target == _target || _changingBlocked) return;
    setState(() {
      _target = target;
      if (!_canClean) _mode = FirmwareInstallMode.update;
      _versions = const [];
      _release = null;
      _volume = null;
      _clearPrepared();
    });
    if (!target.chip.usesUf2) _refreshPorts();
    unawaited(_loadVersions(target));
  }

  Future<void> _prepare({bool fromFile = false}) async {
    if (_changingBlocked) return;
    final target = _target, mode = _mode;
    final release = _release;
    if (!fromFile && release == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _progress = null;
      _complete = false;
      _log.clear();
    });
    try {
      final PreparedFirmware ready;
      if (fromFile) {
        final file = await openFile(
          acceptedTypeGroups: [
            XTypeGroup(label: 'Firmware', extensions: [target.chip.extension]),
          ],
        );
        if (file == null || !mounted) return;
        ready = await widget.tool.local(target, File(file.path), mode: mode);
      } else {
        ready = await widget.tool.download(
          target,
          release: release!,
          mode: mode,
          onProgress: (value) {
            if (mounted && (value == 1 || value - (_progress ?? 0) >= .015)) {
              setState(() => _progress = value);
            }
          },
        );
      }
      if (!mounted) {
        await ready.dispose();
        return;
      }
      final previous = _prepared;
      setState(() => _prepared = ready);
      if (previous != null) await previous.dispose();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _flash() async {
    final firmware = _prepared;
    if (_busy || firmware == null) return;
    final uf2 = firmware.target.chip.usesUf2;
    final destination = uf2 ? _volume : _port;
    if (destination == null) return;
    final clean = firmware.mode == FirmwareInstallMode.clean;
    final eraseStage = uf2 && clean && _erasedBoard == null;
    final destructive = clean && (!uf2 || eraseStage);
    final confirm = await showMeshDialog<bool>(
      context: context,
      builder: (context) => MeshDialog(
        title: Text(
          destructive
              ? tr(context, 'Очистить плату?', 'Erase the board?')
              : tr(context, 'Записать прошивку?', 'Write firmware?'),
        ),
        content: Text(
          [
            widget.board.name,
            firmware.name,
            destination,
            if (destructive)
              tr(
                context,
                'Очистка удалит настройки, ключи и сохранённые данные с платы.',
                'Erasing removes settings, keys, and saved data from the board.',
              ),
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              destructive
                  ? tr(context, 'Очистить', 'Erase')
                  : tr(context, 'Записать', 'Write'),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted || firmware != _prepared || _busy) return;
    final assets = DefaultAssetBundle.of(context);
    setState(() {
      _writing = true;
      _complete = false;
      _error = null;
      _log.clear();
    });
    try {
      if (eraseStage) {
        final board = await FirmwareFlasher.eraseUf2(
          firmware,
          Directory(destination),
          assets,
        );
        if (mounted) {
          setState(() {
            _erasedBoard = board;
            _volume = null;
          });
        }
        return;
      }
      if (uf2) {
        await FirmwareFlasher.flashUf2(
          firmware,
          Directory(destination),
          erasedBoard: _erasedBoard,
        );
      } else {
        await widget.tool.flashEsp(
          firmware,
          destination,
          onOutput: (line) {
            if (!mounted || line.trim().isEmpty) return;
            setState(() {
              _log.add(line);
              if (_log.length > 12) _log.removeAt(0);
            });
          },
        );
      }
      if (mounted) {
        setState(() {
          _complete = true;
          _erasedBoard = null;
          if (uf2) _volume = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _writing = false);
      } else {
        await firmware.dispose();
      }
    }
  }

  Future<void> _chooseVolume() async {
    final path = await getDirectoryPath();
    if (path != null && mounted && !_busy) setState(() => _volume = path);
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final protocols = widget.board.protocols;
    final variants = _variants;
    final chip = _target.chip;
    final clean = _mode == FirmwareInstallMode.clean;
    final destinationReady = chip.usesUf2 ? _volume != null : _port != null;
    final downloadReady =
        _release != null && (clean || _release?.update != null);
    final erasing = chip.usesUf2 && clean && _erasedBoard == null;
    final image = _FirmwareSection(
      title: tr(context, 'Образ прошивки', 'Firmware image'),
      icon: Icons.sd_storage_outlined,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _target.project,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: tr(context, 'Протокол', 'Protocol'),
          ),
          items: [
            for (final protocol in protocols)
              DropdownMenuItem(value: protocol, child: Text(protocol)),
          ],
          onChanged: _changingBlocked || protocols.length == 1
              ? null
              : (protocol) {
                  _selectTarget(
                    widget.board.targets.firstWhere(
                      (target) => target.project == protocol,
                    ),
                  );
                },
        ),
        if (variants.length > 1 || _target.releasePrefix != null)
          DropdownButtonFormField<FirmwareTarget>(
            key: ValueKey(_target.project),
            initialValue: _target,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr(context, 'Вариант прошивки', 'Firmware variant'),
            ),
            items: [
              for (final target in variants)
                DropdownMenuItem(
                  value: target,
                  child: Text(target.role, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _changingBlocked || variants.length == 1
                ? null
                : (value) {
                    if (value != null) _selectTarget(value);
                  },
          ),
        if (_target.warning == 't1000e')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr(
                context,
                'Поддерживается T1000‑E для mesh. Версия LoRaWAN несовместима.',
                'Supports the mesh T1000-E only. The LoRaWAN edition is incompatible.',
              ),
              style: TextStyle(color: style.warning),
            ),
          ),
        DropdownButtonFormField<FirmwareRelease>(
          key: ObjectKey(_versions),
          initialValue: _release,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: tr(context, 'Версия прошивки', 'Firmware version'),
            helperText: _versionsLoading
                ? tr(context, 'Загружаем список релизов…', 'Loading releases…')
                : _versions.isEmpty && !_versionsFailed
                ? tr(
                    context,
                    'Для этой платы можно выбрать локальный образ.',
                    'You can choose a local image for this board.',
                  )
                : null,
            suffixIcon: _versionsFailed
                ? MeshIconButton(
                    label: tr(
                      context,
                      'Повторить загрузку релизов',
                      'Retry loading releases',
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _busy
                        ? null
                        : () => unawaited(_loadVersions(_target)),
                  )
                : null,
          ),
          items: [
            for (final release in _versions)
              DropdownMenuItem(
                value: release,
                child: Text(
                  release.prerelease
                      ? '${release.version} · ${tr(context, 'Тестовая', 'Preview')}'
                      : release.version,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _changingBlocked || _versions.isEmpty
              ? null
              : (version) {
                  setState(() {
                    _release = version;
                    _clearPrepared();
                  });
                },
        ),
        if (_versionsFailed)
          Text(
            tr(
              context,
              'Список релизов недоступен.',
              'Releases are unavailable.',
            ),
          ),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              selected: !clean,
              label: Text(tr(context, 'Обновление', 'Update')),
              onSelected: _changingBlocked
                  ? null
                  : (_) => _setMode(FirmwareInstallMode.update),
            ),
            ChoiceChip(
              selected: clean,
              label: Text(
                tr(context, 'Полная установка с очисткой', 'Erase and install'),
              ),
              onSelected: _changingBlocked || !_canClean
                  ? null
                  : (_) => _setMode(FirmwareInstallMode.clean),
            ),
          ],
        ),
        if (_release != null && !downloadReady)
          Text(
            tr(
              context,
              'Для этой версии нет образа обновления.',
              'This version has no update image.',
            ),
          ),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: _changingBlocked || !downloadReady
                  ? null
                  : () => unawaited(_prepare()),
              icon: const Icon(Icons.download_rounded),
              label: Text(tr(context, 'Загрузить образ', 'Download image')),
            ),
            OutlinedButton.icon(
              onPressed: _changingBlocked
                  ? null
                  : () => unawaited(_prepare(fromFile: true)),
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(tr(context, 'Выбрать файл', 'Choose file')),
            ),
          ],
        ),
        if (_prepared case final prepared?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SelectableText(
              prepared.name,
              style: TextStyle(color: style.secondary),
            ),
          ),
      ],
    );
    final device = _FirmwareSection(
      title: tr(context, 'Подключение платы', 'Connect the board'),
      icon: Icons.usb_rounded,
      children: [
        if (chip.usesUf2) ...[
          Text(
            _erasedBoard != null
                ? tr(
                    context,
                    'Дождитесь завершения очистки, снова переведите ту же плату в режим UF2 и выберите диск.',
                    'Wait for erasing to finish, put the same board back into UF2 mode and choose its drive.',
                  )
                : tr(
                    context,
                    'Переведите плату в режим загрузчика UF2 и выберите появившийся диск.',
                    'Enter UF2 bootloader mode and choose the mounted drive.',
                  ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _busy ? null : _chooseVolume,
              child: Text(tr(context, 'Выбрать диск UF2', 'Choose UF2 drive')),
            ),
          ),
          if (_volume case final volume?) SelectableText(volume),
        ] else
          DropdownButtonFormField<String>(
            key: ValueKey((_ports.map((item) => item.path).join(';'), _port)),
            initialValue: _port,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr(
                context,
                'Последовательный порт USB',
                'USB serial port',
              ),
              helperText: _ports.isEmpty
                  ? tr(
                      context,
                      'Подключите плату и обновите список портов.',
                      'Connect the board and refresh the port list.',
                    )
                  : null,
              helperMaxLines: 2,
              suffixIcon: MeshIconButton(
                onPressed: _busy ? null : _refreshPorts,
                icon: const Icon(Icons.refresh_rounded),
                label: tr(context, 'Обновить порты', 'Refresh ports'),
              ),
            ),
            items: [
              for (final port in _ports)
                DropdownMenuItem(
                  value: port.path,
                  child: Text(port.path, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _busy || _ports.isEmpty
                ? null
                : (port) => setState(() => _port = port),
          ),
      ],
    );
    final hasStatus = _busy || _complete || _error != null || _log.isNotEmpty;
    final writeStatus = _FirmwareSection(
      title: tr(context, 'Состояние записи', 'Flash status'),
      icon: Icons.monitor_heart_outlined,
      children: [
        if (_busy)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: LinearProgressIndicator(value: _writing ? null : _progress),
          ),
        if (_complete)
          Text(
            tr(context, 'Прошивка записана', 'Firmware written'),
            style: TextStyle(color: style.success),
          ),
        if (_error case final error?)
          SelectableText(error, style: TextStyle(color: style.error)),
        if (_log.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(tr(context, 'Журнал записи', 'Flash log')),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  _log.join('\n'),
                  style: TextStyle(color: style.secondary, fontSize: 12),
                ),
              ),
            ],
          ),
      ],
    );
    final action = GlassActionButton(
      label: _writing
          ? tr(context, 'Запись…', 'Writing…')
          : erasing
          ? tr(context, 'Очистить плату', 'Erase board')
          : tr(context, 'Прошить', 'Flash'),
      onTap: !_busy && !_complete && _prepared != null && destinationReady
          ? _flash
          : null,
    );
    final macGlass = MacGlass.enabled(context);
    return PopScope(
      canPop: !_writing,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final inset = bounds.maxWidth < 520 ? 16.0 : 24.0;
                  final wide = bounds.maxWidth >= (macGlass ? 660 : 780);
                  final actionHint = _complete || _busy
                      ? null
                      : _prepared == null
                      ? tr(
                          context,
                          'Выберите образ прошивки',
                          'Choose a firmware image',
                        )
                      : !destinationReady
                      ? tr(
                          context,
                          'Выберите подключённую плату',
                          'Select the connected board',
                        )
                      : null;
                  final button = Padding(
                    padding: EdgeInsets.fromLTRB(
                      macGlass ? 12 : inset,
                      8,
                      macGlass ? 12 : inset,
                      10,
                    ),
                    child: bounds.maxWidth >= 520
                        ? Row(
                            children: [
                              Expanded(
                                child: actionHint == null
                                    ? const SizedBox.shrink()
                                    : Text(
                                        actionHint,
                                        style: TextStyle(
                                          color: style.secondary,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(width: 192, child: action),
                            ],
                          )
                        : action,
                  );
                  return Column(
                    children: [
                      _firmwareHeading(
                        context,
                        tr(context, 'Прошивки', 'Firmware'),
                        busy: _writing,
                      ),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(inset, 6, inset, 14),
                          children: [
                            _FirmwareSection(
                              children: [
                                Row(
                                  children: [
                                    SizedBox(
                                      width: wide ? 160 : 98,
                                      height: wide ? 118 : 86,
                                      child: _BoardArtwork(widget.board),
                                    ),
                                    const SizedBox(width: 15),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.board.manufacturer,
                                            style: TextStyle(
                                              color: style.secondary,
                                            ),
                                          ),
                                          Text(
                                            widget.board.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${chip.label} · ${chip.usesUf2 ? 'UF2' : 'USB'}',
                                            style: TextStyle(
                                              color: style.secondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 6, child: image),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    flex: 5,
                                    child: Column(
                                      children: [
                                        device,
                                        if (hasStatus) ...[
                                          const SizedBox(height: 14),
                                          writeStatus,
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            else ...[
                              image,
                              const SizedBox(height: 14),
                              device,
                              if (hasStatus) ...[
                                const SizedBox(height: 14),
                                writeStatus,
                              ],
                            ],
                          ],
                        ),
                      ),
                      if (macGlass)
                        Padding(
                          padding: EdgeInsets.fromLTRB(inset, 2, inset, 10),
                          child: GlassSurface(radius: 20, child: button),
                        )
                      else
                        button,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setMode(FirmwareInstallMode mode) {
    if (mode == _mode || _changingBlocked) return;
    setState(() {
      _mode = mode;
      _clearPrepared();
    });
  }
}

class _FirmwareSection extends StatelessWidget {
  const _FirmwareSection({this.title, this.icon, required this.children});
  final String? title;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return Card(
      color: style.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: style.separator.withValues(alpha: .65)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            if (title case final title?)
              Row(
                children: [
                  Icon(icon, size: 20, color: style.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

Widget _firmwareHeading(
  BuildContext context,
  String title, {
  bool busy = false,
}) => PageHeading(
  title,
  sideWidth: 60,
  leading: GlassButton(
    icon: Icons.arrow_back_rounded,
    label: tr(context, 'Назад', 'Back'),
    onTap: busy ? null : () => Navigator.of(context).maybePop(),
  ),
);
