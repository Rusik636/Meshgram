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
  String? _project;
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
                final project = _project ?? catalog.projects.keys.first;
                final boards = catalog.boards[project]!
                    .where((board) => board.matches(_query))
                    .toList();
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final entry in catalog.projects.entries)
                            ChoiceChip(
                              label: Text(entry.value),
                              selected: project == entry.key,
                              onSelected: (_) =>
                                  setState(() => _project = entry.key),
                            ),
                        ],
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
                                      mainAxisExtent: 146,
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
  PreparedFirmware? _prepared;
  String? _port, _volume, _error, _tool;
  double? _progress;
  List<UsbPort> _ports = const [];
  final List<String> _log = [];
  bool _loading = false, _writing = false, _complete = false;
  bool get _busy => _loading || _writing;

  @override
  void initState() {
    super.initState();
    _tool = FirmwareFlasher.findEsptool();
    if (!_target.chip.usesUf2) _refreshPorts();
  }

  @override
  void dispose() {
    if (_prepared case final prepared? when !_writing) {
      unawaited(prepared.dispose());
    }
    super.dispose();
  }

  void _refreshPorts() {
    try {
      final ports = widget.tool.usb.ports();
      setState(() {
        _ports = ports;
        if (!ports.any((port) => port.path == _port)) _port = null;
        _error = null;
      });
    } on Object catch (error) {
      setState(() => _error = error.toString());
    }
  }

  void _selectTarget(FirmwareTarget target) {
    final old = _prepared;
    setState(() {
      _target = target;
      _prepared = null;
      _complete = false;
      _error = null;
      _log.clear();
    });
    if (old != null) unawaited(old.dispose());
    if (!target.chip.usesUf2) _refreshPorts();
  }

  Future<void> _prepare({bool fromFile = false}) async {
    if (_busy) return;
    final target = _target;
    final XFile? file;
    if (fromFile) {
      file = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(label: 'Firmware', extensions: [target.chip.extension]),
        ],
      );
      if (file == null || !mounted || _target != target) return;
    } else {
      file = null;
    }
    final previous = _prepared;
    setState(() {
      _loading = true;
      _error = null;
      _progress = null;
      _complete = false;
      _log.clear();
    });
    try {
      final ready = file == null
          ? await widget.tool.download(
              target,
              onProgress: (value) {
                if (mounted &&
                    (value == 1 || value - (_progress ?? 0) >= .015)) {
                  setState(() => _progress = value);
                }
              },
            )
          : await widget.tool.local(target, File(file.path));
      if (!mounted) {
        await ready.dispose();
        return;
      }
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
    final port = _port, executable = _tool, volume = _volume;
    if (_busy || firmware == null) return;
    final uf2 = firmware.target.chip.usesUf2;
    if (uf2 ? volume == null : port == null || executable == null) return;
    final destination = uf2 ? volume! : port!;
    final confirm = await showMeshDialog<bool>(
      context: context,
      builder: (context) => MeshDialog(
        title: Text(tr(context, 'Записать прошивку?', 'Write firmware?')),
        content: Text(
          [
            widget.board.name,
            firmware.name,
            destination,
            tr(
              context,
              'Проверьте модель платы. Полный образ может сбросить настройки рации.',
              'Check the board model. A full image may reset the radio configuration.',
            ),
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Записать', 'Write')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted || firmware != _prepared || _busy) return;
    setState(() {
      _writing = true;
      _complete = false;
      _error = null;
      _log.clear();
    });
    try {
      if (uf2) {
        await FirmwareFlasher.flashUf2(firmware, Directory(destination));
      } else {
        await widget.tool.flashEsp(
          firmware,
          destination,
          executable!,
          onOutput: (line) {
            if (!mounted || line.trim().isEmpty) return;
            setState(() {
              _log.add(line);
              if (_log.length > 12) _log.removeAt(0);
            });
          },
        );
      }
      if (mounted) setState(() => _complete = true);
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

  Future<void> _chooseTool() async {
    final file = await openFile();
    if (file != null && mounted && !_busy) setState(() => _tool = file.path);
  }

  @override
  Widget build(BuildContext context) {
    final chip = _target.chip;
    final style = MeshStyle.of(context);
    final destinationReady = chip.usesUf2
        ? _volume != null
        : _port != null && _tool != null;
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
                    if (widget.board.targets.length > 1)
                      DropdownButtonFormField<FirmwareTarget>(
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
                          for (final target in widget.board.targets)
                            DropdownMenuItem(
                              value: target,
                              child: Text(
                                target.role,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy
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
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : () => unawaited(_prepare()),
                          icon: const Icon(Icons.download_rounded),
                          label: Text(
                            tr(
                              context,
                              'Загрузить официальную',
                              'Download official',
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy
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
                        tr(
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
                    ] else ...[
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          _ports.map((item) => item.path).join(';'),
                        ),
                        initialValue: _port,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: tr(
                            context,
                            'Последовательный порт USB',
                            'USB serial port',
                          ),
                          suffixIcon: IconButton(
                            onPressed: _busy ? null : _refreshPorts,
                            icon: const Icon(Icons.refresh_rounded),
                            tooltip: tr(
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
                      if (_tool == null) ...[
                        Text(
                          tr(
                            context,
                            'Для ESP32 нужен установленный esptool 5 или новее.',
                            'ESP32 requires an installed esptool 5 or newer.',
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _busy ? null : _chooseTool,
                            child: Text(
                              tr(context, 'Указать esptool', 'Locate esptool'),
                            ),
                          ),
                        ),
                      ],
                    ],
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
                      : tr(context, 'Прошить', 'Flash'),
                  onTap: !_busy && _prepared != null && destinationReady
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
