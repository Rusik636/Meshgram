// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../mesh/network.dart';
import '../radio/desktop_usb.dart';
import '../radio/firmware_catalog.dart';
import '../radio/firmware_flasher.dart';
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
  String _manufacturer = '';
  String _query = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          _firmwareHeading(context, tr(context, 'Прошивки', 'Firmware')),
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
                  return const Center(child: CircularProgressIndicator());
                }
                final manufacturers = catalog.boards
                    .map((board) => board.manufacturer)
                    .toSet();
                final boards = catalog.boards
                    .where(
                      (board) =>
                          (_manufacturer.isEmpty ||
                              board.manufacturer == _manufacturer) &&
                          board.matches(_query),
                    )
                    .toList();
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _manufacturer,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: tr(
                            context,
                            'Производитель',
                            'Manufacturer',
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(
                              tr(
                                context,
                                'Все производители',
                                'All manufacturers',
                              ),
                            ),
                          ),
                          for (final manufacturer in manufacturers)
                            DropdownMenuItem(
                              value: manufacturer,
                              child: Text(manufacturer),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _manufacturer = value ?? ''),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          labelText: tr(
                            context,
                            'Название платы',
                            'Board name',
                          ),
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: boards.isEmpty
                            ? Center(
                                child: Text(
                                  tr(
                                    context,
                                    'Платы не найдены',
                                    'No boards found',
                                  ),
                                ),
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.only(bottom: 14),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 225,
                                      mainAxisExtent: 166,
                                      mainAxisSpacing: 8,
                                      crossAxisSpacing: 8,
                                    ),
                                itemCount: boards.length,
                                itemBuilder: (context, index) {
                                  final board = boards[index];
                                  return Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () => Navigator.of(context).push(
                                        meshPageRoute<void>(
                                          context,
                                          settings: const RouteSettings(
                                            name: firmwareBoardRoute,
                                          ),
                                          builder: (_) => _FlashBoardPage(
                                            board: board,
                                            tool: FirmwareFlasher(widget.usb),
                                          ),
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(9),
                                        child: Column(
                                          children: [
                                            Expanded(
                                              child: _BoardArtwork(board),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              board.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                            ),
                                            Text(
                                              board.manufacturer,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
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
    return PopScope(
      canPop: !_writing,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _firmwareHeading(context, widget.board.name, busy: _writing),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 7, 18, 15),
                  children: [
                    SizedBox(height: 105, child: _BoardArtwork(widget.board)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _target.project,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: tr(context, 'Протокол', 'Protocol'),
                      ),
                      items: [
                        for (final protocol in protocols)
                          DropdownMenuItem(
                            value: protocol,
                            child: Text(protocol),
                          ),
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
                          labelText: tr(
                            context,
                            'Вариант прошивки',
                            'Firmware variant',
                          ),
                        ),
                        items: [
                          for (final target in variants)
                            DropdownMenuItem(
                              value: target,
                              child: Text(
                                target.role,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                        labelText: tr(
                          context,
                          'Версия прошивки',
                          'Firmware version',
                        ),
                        helperText: _versionsLoading
                            ? tr(
                                context,
                                'Загружаем список релизов…',
                                'Loading releases…',
                              )
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
                    const SizedBox(height: 14),
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
                            tr(
                              context,
                              'Полная установка с очисткой',
                              'Erase and install',
                            ),
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
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _changingBlocked || !downloadReady
                              ? null
                              : () => unawaited(_prepare()),
                          icon: const Icon(Icons.download_rounded),
                          label: Text(
                            tr(context, 'Загрузить образ', 'Download image'),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _changingBlocked
                              ? null
                              : () => unawaited(_prepare(fromFile: true)),
                          icon: const Icon(Icons.folder_open_rounded),
                          label: Text(
                            tr(context, 'Выбрать файл', 'Choose file'),
                          ),
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
                    const Divider(height: 22),
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
                          child: Text(
                            tr(context, 'Выбрать диск UF2', 'Choose UF2 drive'),
                          ),
                        ),
                      ),
                      if (_volume case final volume?) SelectableText(volume),
                    ] else
                      DropdownButtonFormField<String>(
                        key: ValueKey((
                          _ports.map((item) => item.path).join(';'),
                          _port,
                        )),
                        initialValue: _port,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: tr(
                            context,
                            'Последовательный порт USB',
                            'USB serial port',
                          ),
                          suffixIcon: MeshIconButton(
                            onPressed: _busy ? null : _refreshPorts,
                            icon: const Icon(Icons.refresh_rounded),
                            label: tr(
                              context,
                              'Обновить порты',
                              'Refresh ports',
                            ),
                          ),
                        ),
                        items: [
                          for (final port in _ports)
                            DropdownMenuItem(
                              value: port.path,
                              child: Text(
                                port.path,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy || _ports.isEmpty
                            ? null
                            : (port) => setState(() => _port = port),
                      ),
                    if (_busy)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: LinearProgressIndicator(
                          value: _writing ? null : _progress,
                        ),
                      ),
                    if (_complete)
                      Text(
                        tr(context, 'Прошивка записана', 'Firmware written'),
                        style: TextStyle(color: style.success),
                      ),
                    if (_error case final error?)
                      SelectableText(
                        error,
                        style: TextStyle(color: style.error),
                      ),
                    if (_log.isNotEmpty)
                      SelectableText(
                        _log.join('\n'),
                        style: TextStyle(color: style.secondary, fontSize: 12),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: GlassActionButton(
                  label: _writing
                      ? tr(context, 'Запись…', 'Writing…')
                      : erasing
                      ? tr(context, 'Очистить плату', 'Erase board')
                      : tr(context, 'Прошить', 'Flash'),
                  onTap:
                      !_busy &&
                          !_complete &&
                          _prepared != null &&
                          destinationReady
                      ? _flash
                      : null,
                ),
              ),
            ],
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
