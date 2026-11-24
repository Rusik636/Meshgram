// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' hide Radio;
import 'package:flutter/services.dart';

import '../mesh/controller.dart';
import '../mesh/network.dart';
import '../mesh/nodes.dart';
import '../mesh/radio_settings_index.dart';
import 'position_picker.dart';
import 'style.dart';
import 'signal.dart';
import 'swipe_actions.dart';
import 'page_route.dart';
import 'radio_avatar.dart';
import 'radio_setting_visibility.dart';
import 'chat_setup.dart';

PageRoute<void> radioSettingsRoute(
  BuildContext context,
  RadioSettingsPage page,
) => meshPageRoute<void>(context, builder: (_) => page);

class RadioSettingsPage extends StatefulWidget {
  const RadioSettingsPage({
    super.key,
    required this.controller,
    required this.radio,
    this.section = RadioFieldSection.device,
    this.remote,
    this.peer,
    this.initialQuery = '',
  }) : assert((remote == null) == (peer == null));

  final MeshController controller;
  final Radio radio;
  final RadioFieldSection section;
  final RadioSettingsSession? remote;
  final Peer? peer;
  final String initialQuery;

  @override
  State<RadioSettingsPage> createState() => _RadioSettingsState();
}

class _RadioSettingsState extends State<RadioSettingsPage> {
  List<RadioField> _fields = [];
  List<RadioField> _profileFields = [];
  late final _search = TextEditingController(text: widget.initialQuery);

  String get _query => _normalizeSearch(_search.text);

  static String _normalizeSearch(String input) => input
      .trim()
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'wi[\s‐‑–—-]*fi'), 'wifi');

  bool _matches(Iterable<String> parts) {
    final label = _normalizeSearch(parts.join(' '));
    return _query.split(RegExp(r'\s+')).every(label.contains);
  }

  final _changed = <String, String>{};
  bool _busy = true;
  bool _saving = false;
  bool _askingToLeave = false;
  double? _backDragStart;
  String? _error;
  bool _saved = false;
  String? _commandResult;
  NodePosition? _anchor;

  bool get _hasUnsavedChanges => _changed.isNotEmpty || _anchor != null;
  bool get _canSave => !_busy && _hasUnsavedChanges;

  NodePosition? get _initialPosition {
    final lat = _fields.where((field) => field.id == 'latitude').firstOrNull;
    final lon = _fields.where((field) => field.id == 'longitude').firstOrNull;
    final a = lat == null ? null : double.tryParse(_value(lat));
    final b = lon == null ? null : double.tryParse(_value(lon));
    if (a != null && b != null) {
      final position = nodePosition(a, b);
      if (position != null) return position;
    }
    final peer = widget.peer;
    return peer == null
        ? widget.controller.cache?.localPosition
        : widget.controller.nodeObservation(peer.id)?.position;
  }

  String? _positionLabel(NodePosition? position) => position == null
      ? null
      : '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';

  Future<void> _pickAnchor() async {
    final result = await pickNodePosition(context, _anchor ?? _initialPosition);
    if (result == null || !mounted) return;
    setState(() {
      _anchor = result;
      _saved = false;
      _changed.remove('latitude');
      _changed.remove('longitude');
      _changed.remove('fixed');
    });
  }

  RadioSettingsCatalog? get _catalog {
    final remote = widget.remote;
    if (remote is RadioSettingsCatalog) return remote as RadioSettingsCatalog;
    if (remote != null) return null;
    return widget.controller.radioSettingsCatalog(widget.radio);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<bool> _load({bool save = false}) async {
    if (save && !_canSave) return false;
    setState(() {
      _busy = true;
      _saving = save;
      _error = null;
      _saved = false;
    });
    try {
      final remote = widget.remote;
      final section = widget.section;
      if (save) {
        final changes = Map<String, String>.of(_changed);
        if (changes.isNotEmpty) {
          final catalog = _catalog;
          if (catalog?.extraSettings.contains(section) ?? false) {
            if (remote == null) {
              await widget.controller.writeRadioSection(
                widget.radio,
                section,
                changes,
              );
            } else {
              await catalog!.writeSection(section, changes);
            }
          } else if (remote == null) {
            await widget.controller.writeRadioSettings(widget.radio, changes);
          } else {
            await remote.writeSettings(changes);
          }
          _changed.removeWhere((id, value) => changes[id] == value);
        }
        if (_anchor case final anchor?) {
          await widget.controller.setFixedPosition(
            widget.radio,
            anchor,
            remote: remote,
          );
          _anchor = null;
        }
      }
      final catalog = _catalog;
      final fields = (catalog?.extraSettings.contains(section) ?? false)
          ? await catalog!.readSection(section)
          : section == RadioFieldSection.telemetry
          ? remote == null
                ? await widget.controller.readRadioTelemetry(widget.radio)
                : remote is RadioTelemetrySession
                ? await (remote as RadioTelemetrySession).readTelemetry()
                : <RadioField>[]
          : remote != null
          ? await remote.readSettings()
          : await widget.controller.readRadioSettings(widget.radio);
      if (!mounted) return false;
      setState(() {
        if (section == RadioFieldSection.device) _profileFields = fields;
        _fields = fields
            .where((field) => field.section == widget.section)
            .toList();
        _changed.clear();
        _saved = save;
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _error = error is FormatException
            ? 'values'
            : save
            ? 'write'
            : 'read';
      });
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
    }
  }

  Future<void> _confirmLeaving() async {
    if (_askingToLeave || _saving || !_hasUnsavedChanges) return;
    _askingToLeave = true;
    try {
      final save = await showMeshDialog<bool>(
        context: context,
        builder: (context) => MeshDialog(
          title: Text(
            tr(context, 'Несохранённые изменения', 'Unsaved changes'),
          ),
          content: SizedBox(
            width: 304,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(
                    context,
                    'Сохранить изменения перед выходом?',
                    'Save your changes before leaving?',
                  ),
                ),
                const SizedBox(height: 20),
                GlassActionButton(
                  label: tr(context, 'Сохранить и выйти', 'Save and leave'),
                  onTap: _canSave ? () => Navigator.pop(context, true) : null,
                  wrapLabel: true,
                ),
                const SizedBox(height: 8),
                GlassActionButton(
                  label: tr(context, 'Выйти без сохранения', 'Discard'),
                  onTap: () => Navigator.pop(context, false),
                  primary: false,
                  wrapLabel: true,
                ),
                const SizedBox(height: 8),
                GlassActionButton(
                  label: tr(context, 'Остаться', 'Stay'),
                  onTap: () => Navigator.pop(context),
                  primary: false,
                  wrapLabel: true,
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || save == null) return;
      if (save && !await _load(save: true)) return;
      if (mounted && ModalRoute.isCurrentOf(context) == true) {
        Navigator.of(context).pop();
      }
    } finally {
      _askingToLeave = false;
    }
  }

  String _label(RadioField field) => tr(context, field.russian, field.title);
  String _value(RadioField field) => _changed[field.id] ?? field.value;
  String _displayValue(RadioField field) {
    final value = _value(field);
    return field.secret && value.isNotEmpty
        ? '••••••••'
        : (field.choices[value] ?? value);
  }

  void _set(RadioField field, String value) => setState(() {
    _saved = false;
    if (field.id == 'latitude' ||
        field.id == 'longitude' ||
        field.id == 'fixed') {
      _anchor = null;
    }
    if (value == field.value) {
      _changed.remove(field.id);
    } else {
      _changed[field.id] = value;
    }
  });

  Future<void> _edit(RadioField field) async {
    if (field.kind == RadioFieldKind.choice) {
      final result = await showMeshSheet<String>(
        context: context,
        builder: (context) => SheetBody(
          title: _label(field),
          children: [
            MeshGroup(
              children: [
                for (final entry in field.choices.entries)
                  MeshRow(
                    title: entry.value,
                    icon: Icons.tune_rounded,
                    tint: const Color(0xff2978d5),
                    selected: entry.key == _value(field),
                    onTap: () => Navigator.pop(context, entry.key),
                  ),
              ],
            ),
          ],
        ),
      );
      if (mounted && result != null) _set(field, result);
      return;
    }

    final result = await showMeshDialog<String>(
      context: context,
      builder: (context) {
        var value = _value(field);
        final multiline = field.kind == RadioFieldKind.multiline;
        void submit() {
          if (field.kind == RadioFieldKind.text ||
              multiline ||
              value.trim().isNotEmpty) {
            Navigator.pop(context, field.secret ? value : value.trim());
          }
        }

        return MeshDialog(
          title: Text(_label(field)),
          content: TextFormField(
            initialValue: value,
            minLines: multiline ? 3 : 1,
            maxLines: multiline ? 8 : 1,
            autofocus: true,
            obscureText: field.secret,
            autocorrect: !field.secret,
            enableSuggestions: !field.secret,
            keyboardType: switch (field.kind) {
              RadioFieldKind.integer => const TextInputType.numberWithOptions(
                signed: true,
              ),
              RadioFieldKind.decimal => const TextInputType.numberWithOptions(
                decimal: true,
              ),
              RadioFieldKind.multiline => TextInputType.multiline,
              _ => TextInputType.text,
            },
            onChanged: (text) => value = text,
            onFieldSubmitted: multiline ? null : (_) => submit(),
            decoration: InputDecoration(
              suffixText: field.units,
              helperText: field.example,
              helperMaxLines: 3,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context, 'Отмена', 'Cancel')),
            ),
            TextButton(
              onPressed: submit,
              child: Text(tr(context, 'Готово', 'Done')),
            ),
          ],
        );
      },
    );
    if (mounted && result != null) _set(field, result);
  }

  String _sectionName(RadioFieldSection section) => switch (section) {
    RadioFieldSection.device =>
      widget.peer == null
          ? tr(context, 'Настройки рации', 'Radio settings')
          : tr(context, 'Управление узлом', 'Manage node'),
    RadioFieldSection.lora => tr(context, 'Настройки LoRa', 'LoRa settings'),
    RadioFieldSection.telemetry => tr(context, 'Телеметрия', 'Telemetry'),
    RadioFieldSection.position => tr(
      context,
      'Позиция и GPS',
      'Position and GPS',
    ),
    RadioFieldSection.connectivity => tr(context, 'Сеть', 'Network'),
    RadioFieldSection.bluetooth => 'Bluetooth',
    RadioFieldSection.power => tr(context, 'Питание', 'Power'),
    RadioFieldSection.display => tr(context, 'Экран рации', 'Radio display'),
    RadioFieldSection.security => tr(context, 'Безопасность', 'Security'),
    RadioFieldSection.routing => tr(context, 'Маршрутизация', 'Routing'),
    RadioFieldSection.mqtt => 'MQTT',
    RadioFieldSection.sensors => tr(
      context,
      'Параметры телеметрии',
      'Telemetry settings',
    ),
    RadioFieldSection.notifications => tr(
      context,
      'Уведомления рации',
      'Radio notifications',
    ),
    RadioFieldSection.contacts => tr(context, 'Контакты', 'Contacts'),
    RadioFieldSection.serial => tr(
      context,
      'Последовательный порт',
      'Serial port',
    ),
    RadioFieldSection.storeForward => tr(
      context,
      'Хранение и пересылка',
      'Store & forward',
    ),
    RadioFieldSection.rangeTest => tr(
      context,
      'Проверка дальности',
      'Range test',
    ),
    RadioFieldSection.quickMessages => tr(
      context,
      'Быстрые сообщения',
      'Quick messages',
    ),
    RadioFieldSection.audio => tr(context, 'Аудио', 'Audio'),
    RadioFieldSection.remoteHardware => tr(
      context,
      'Удалённый GPIO',
      'Remote hardware',
    ),
    RadioFieldSection.neighborInfo => tr(
      context,
      'Информация о соседях',
      'Neighbor info',
    ),
    RadioFieldSection.ambientLighting => tr(
      context,
      'Подсветка',
      'Ambient lighting',
    ),
    RadioFieldSection.detectionSensor => tr(
      context,
      'Датчик обнаружения',
      'Detection sensor',
    ),
    RadioFieldSection.paxCounter => tr(
      context,
      'Счётчик устройств',
      'PAX counter',
    ),
    RadioFieldSection.statusMessage => tr(
      context,
      'Статус узла',
      'Status message',
    ),
    RadioFieldSection.trafficManagement => tr(
      context,
      'Управление трафиком',
      'Traffic management',
    ),
    RadioFieldSection.tak => 'TAK',
    RadioFieldSection.beacon => tr(context, 'Маяк', 'Mesh beacon'),
    RadioFieldSection.deviceUi => tr(
      context,
      'Интерфейс рации',
      'Device interface',
    ),
  };

  IconData _sectionIcon(RadioFieldSection section) => switch (section) {
    RadioFieldSection.position => Icons.location_on_outlined,
    RadioFieldSection.connectivity => Icons.wifi_rounded,
    RadioFieldSection.bluetooth => Icons.bluetooth_rounded,
    RadioFieldSection.power => Icons.battery_charging_full_rounded,
    RadioFieldSection.display => Icons.display_settings_outlined,
    RadioFieldSection.security => Icons.lock_outline_rounded,
    RadioFieldSection.routing => Icons.route_outlined,
    RadioFieldSection.mqtt => Icons.cloud_outlined,
    RadioFieldSection.sensors ||
    RadioFieldSection.telemetry => Icons.monitor_heart_outlined,
    RadioFieldSection.notifications => Icons.notifications_outlined,
    _ => Icons.tune_rounded,
  };

  static const _connectionSections = [
    RadioFieldSection.lora,
    RadioFieldSection.connectivity,
    RadioFieldSection.bluetooth,
    RadioFieldSection.routing,
  ];

  static const _measurementSections = [
    RadioFieldSection.position,
    RadioFieldSection.telemetry,
  ];

  static const _deviceSections = [
    RadioFieldSection.power,
    RadioFieldSection.display,
    RadioFieldSection.deviceUi,
    RadioFieldSection.notifications,
    RadioFieldSection.security,
    RadioFieldSection.contacts,
  ];

  Future<void> _openSection(
    RadioFieldSection section, {
    String initialQuery = '',
  }) async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push<void>(
      radioSettingsRoute(
        context,
        RadioSettingsPage(
          controller: widget.controller,
          radio: widget.radio,
          section: section,
          remote: widget.remote,
          peer: widget.peer,
          initialQuery: initialQuery,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Iterable<RadioSettingName> _settingNames(RadioFieldSection section) {
    final catalog = _catalog;
    if (catalog is RadioSettingsIndex &&
        (catalog?.extraSettings.contains(section) ?? false)) {
      return (catalog as RadioSettingsIndex).settingNames(section);
    }
    return _profileFields
        .where((field) => field.section == section)
        .map(
          (field) => (id: field.id, title: field.title, russian: field.russian),
        );
  }

  bool get _presetRateOverride {
    if (widget.remote != null) return true;
    final firmware = widget.controller.radioDeviceInfo(widget.radio)?.firmware;
    final version = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(firmware ?? '');
    if (version == null) return true;
    final major = int.parse(version[1]!);
    final minor = int.parse(version[2]!);
    final patch = int.parse(version[3]!);
    // Clients support a coding-rate override in preset mode from 2.7.18.
    return major > 2 || major == 2 && (minor > 7 || minor == 7 && patch >= 18);
  }

  List<RadioField> get _shownFields {
    final values = {for (final field in _fields) field.id: _value(field)};
    final network = widget.radio.network;
    final section = widget.section;
    final presetRateOverride =
        network != 'meshtastic' ||
        section != RadioFieldSection.lora ||
        _presetRateOverride;
    final matches = _query.isEmpty
        ? null
        : <String>{
            for (final field in _fields)
              if (_matches([field.title, field.russian, field.id])) ...[
                field.id,
                for (final rule in radioSettingConditions(
                  network,
                  section,
                  field.id,
                  presetRateOverride: presetRateOverride,
                ))
                  ...rule.keys,
              ],
          };
    return [
      for (final field in _fields)
        if ((matches == null || matches.contains(field.id)) &&
            radioSettingVisible(
              network,
              section,
              field.id,
              values,
              presetRateOverride: presetRateOverride,
            ))
          field,
    ];
  }

  Widget _searchField(MeshStyle style) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
    child: TextField(
      key: const ValueKey('radio-settings-search'),
      controller: _search,
      onChanged: (_) => setState(() {}),
      textInputAction: TextInputAction.search,
      autocorrect: false,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(
        hintText: tr(context, 'Поиск настроек', 'Search settings'),
        prefixIcon: const Icon(Icons.search_rounded, size: 21),
        suffixIcon: _query.isEmpty
            ? null
            : MeshIconButton(
                onPressed: () => setState(_search.clear),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: tr(context, 'Очистить поиск', 'Clear search'),
              ),
        filled: true,
        fillColor: style.searchField,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        isDense: true,
      ),
    ),
  );

  Widget _settingsGroup(String? title, List<Widget> rows) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 7),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: TextStyle(
                  color: MeshStyle.of(context).secondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        MeshGroup(children: rows),
      ],
    ),
  );

  Widget _fieldRow(RadioField field, Color tint, bool android) {
    final label = _label(field);
    if (field.kind == RadioFieldKind.toggle) {
      return SwitchListTile.adaptive(
        title: Text(label),
        value: _value(field) == 'true',
        activeTrackColor: android ? const Color(0xff34c759) : null,
        activeThumbColor: android ? Colors.white : null,
        onChanged: !_busy && field.editable
            ? (value) => _set(field, '$value')
            : null,
      );
    }
    final value = _displayValue(field);
    final displayAsDetail =
        !_busy && field.editable && field.units == null && value.length <= 18;
    return MeshRow(
      title: label,
      icon: field.kind == RadioFieldKind.text
          ? Icons.info_outline_rounded
          : Icons.tune_rounded,
      tint: tint,
      detail: displayAsDetail ? value : null,
      subtitle: displayAsDetail
          ? null
          : '$value${field.units == null ? '' : ' ${field.units}'}',
      onTap: !_busy && field.editable ? () => unawaited(_edit(field)) : null,
    );
  }

  Future<void> _runCommand(RemoteAdminConsole console) async {
    var draft = '';
    final command = await showMeshDialog<String>(
      context: context,
      builder: (dialogContext) => MeshDialog(
        title: Text(tr(context, 'Команда для узла', 'Node command')),
        content: TextField(
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (value) => draft = value,
          decoration: const InputDecoration(hintText: 'get radio'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, draft.trim()),
            child: Text(tr(context, 'Отправить', 'Send')),
          ),
        ],
      ),
    );
    if (!mounted || command == null || command.isEmpty) return;
    if (!command.startsWith('get ') && !command.startsWith('stats-')) {
      final confirm = await showMeshDialog<bool>(
        context: context,
        builder: (dialogContext) => MeshDialog(
          title: Text(
            tr(context, 'Выполнить команду на узле?', 'Run command on node?'),
          ),
          content: Text(widget.peer!.name),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr(context, 'Отмена', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr(context, 'Выполнить', 'Run')),
            ),
          ],
        ),
      );
      if (!mounted || confirm != true) return;
    }
    await _runRemote(() => console.runCommand(command));
  }

  Future<void> _power(
    Future<void> Function() command, {
    required bool reboot,
  }) async {
    final confirm = await showMeshDialog<bool>(
      context: context,
      builder: (context) => MeshDialog(
        title: Text(
          reboot
              ? tr(context, 'Перезагрузить узел?', 'Restart the node?')
              : tr(context, 'Выключить узел?', 'Shut down the node?'),
        ),
        content: Text(widget.peer?.name ?? widget.radio.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Подтвердить', 'Confirm')),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    await _runRemote(() async {
      await command();
      return '';
    });
  }

  Future<void> _runRemote(Future<String> Function() command) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _commandResult = null;
    });
    try {
      final response = await command();
      if (!mounted) return;
      _commandResult = response.isEmpty
          ? tr(
              context,
              'Команда передана рации.',
              'Command submitted to the radio.',
            )
          : response;
    } catch (_) {
      if (!mounted) return;
      _commandResult = tr(
        context,
        'Узел не подтвердил команду.',
        'The node did not confirm the command.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final leftToRight = Directionality.of(context) == TextDirection.ltr;
    final direction = leftToRight ? 1 : -1;
    final safe = MediaQuery.paddingOf(context);
    return PopScope<void>(
      canPop: !_hasUnsavedChanges && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeaving());
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.section == RadioFieldSection.device)
            ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) => _buildPage(context),
            )
          else
            _buildPage(context),
          if (_hasUnsavedChanges &&
              !_saving &&
              Theme.of(context).platform == TargetPlatform.iOS)
            // PopScope disables the Cupertino swipe while there are edits.
            // An intentional edge swipe can still open the confirmation.
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              width: math.max(20, leftToRight ? safe.left : safe.right),
              child: Listener(
                onPointerCancel: (_) => _backDragStart = null,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  excludeFromSemantics: true,
                  dragStartBehavior: DragStartBehavior.down,
                  onHorizontalDragStart: (details) =>
                      _backDragStart = details.globalPosition.dx,
                  onHorizontalDragEnd: (details) {
                    final start = _backDragStart;
                    _backDragStart = null;
                    if (start == null) return;
                    final distance =
                        (details.globalPosition.dx - start) * direction;
                    if (distance >= 56 ||
                        (distance >= 24 &&
                            details.velocity.pixelsPerSecond.dx * direction >=
                                550)) {
                      unawaited(_confirmLeaving());
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPage(BuildContext context) {
    final style = MeshStyle.of(context);
    final android = Theme.of(context).platform == TargetPlatform.android;
    final tint = style.dark ? const Color(0xff287795) : const Color(0xff2978d5);
    final extra = _catalog?.extraSettings ?? const <RadioFieldSection>[];
    final hasTelemetrySettings = extra.contains(RadioFieldSection.sensors);
    final sections = {
      RadioFieldSection.lora,
      if (widget.remote == null ||
          widget.remote is RadioTelemetrySession ||
          hasTelemetrySettings)
        RadioFieldSection.telemetry,
      ...extra.where((section) => section != RadioFieldSection.sensors),
    };
    final isProfile = widget.section == RadioFieldSection.device;
    final shownFields = _shownFields;
    final fieldRows = shownFields
        .map((field) => _fieldRow(field, tint, android))
        .toList();

    Widget sectionRow(RadioFieldSection section, {String? detail}) => MeshRow(
      title: _sectionName(section),
      subtitle: detail,
      icon: _sectionIcon(section),
      tint: section == RadioFieldSection.telemetry
          ? const Color(0xff168a87)
          : tint,
      onTap: () => unawaited(
        _openSection(
          section,
          initialQuery: detail == null ? '' : _search.text.trim(),
        ),
      ),
    );
    Iterable<Widget> sectionRows(Iterable<RadioFieldSection> group) sync* {
      for (final section in group.where(sections.contains)) {
        final name = _sectionName(section);
        if (_query.isEmpty || _matches([name, section.name])) {
          yield sectionRow(section);
          continue;
        }
        final results = _settingNames(section)
            .where((field) => _matches([field.title, field.russian, field.id]))
            .map((field) => tr(context, field.russian, field.title))
            .toSet();
        if (results.isNotEmpty) {
          yield sectionRow(section, detail: results.take(2).join(' · '));
        }
      }
    }

    final deviceInfoTitle = tr(
      context,
      'Информация об устройстве',
      'Device information',
    );
    final channelsTitle = tr(context, 'Каналы', 'Channels');
    final consoleTitle = tr(context, 'Консоль команд', 'Command console');
    final neighborsTitle = tr(context, 'Соседние узлы', 'Neighbor table');
    final restart = widget.controller.radioRestartSession(widget.radio);
    final restartTitle = tr(context, 'Перезагрузить рацию', 'Restart radio');
    final restartNodeTitle = tr(context, 'Перезагрузить узел', 'Restart node');
    final shutdownNodeTitle = tr(context, 'Выключить узел', 'Shut down node');
    bool showAction(String title) => _query.isEmpty || _matches([title]);
    final identityRows = [
      ...fieldRows,
      if (widget.remote == null && showAction(deviceInfoTitle))
        MeshRow(
          title: deviceInfoTitle,
          icon: Icons.info_outline_rounded,
          tint: tint,
          onTap: () => unawaited(
            Navigator.of(context).push<void>(
              meshPageRoute(
                context,
                builder: (_) => _RadioInformation(
                  controller: widget.controller,
                  radio: widget.radio,
                ),
              ),
            ),
          ),
        ),
    ];
    final connectionRows = [
      ...sectionRows(_connectionSections),
      if (widget.remote == null &&
          widget.controller.channelActions.isNotEmpty &&
          showAction(channelsTitle))
        MeshRow(
          title: channelsTitle,
          icon: Icons.tag_rounded,
          tint: const Color(0xff168a87),
          onTap: () => unawaited(showRadioChannels(context, widget.controller)),
        ),
    ];
    final measurementRows = [
      ...sectionRows(_measurementSections),
      if (hasTelemetrySettings && _query.isNotEmpty)
        if (_matches([_sectionName(RadioFieldSection.sensors)]) ||
            _settingNames(
              RadioFieldSection.sensors,
            ).any((field) => _matches([field.title, field.russian, field.id])))
          sectionRow(
            RadioFieldSection.sensors,
            detail: _matches([_sectionName(RadioFieldSection.sensors)])
                ? null
                : _sectionName(RadioFieldSection.telemetry),
          ),
    ];
    final deviceRows = sectionRows(_deviceSections).toList();
    final moduleRows = sectionRows(
      sections.where(
        (section) =>
            !_connectionSections.contains(section) &&
            !_measurementSections.contains(section) &&
            !_deviceSections.contains(section),
      ),
    ).toList();
    final serviceRows = [
      if (restart != null && showAction(restartTitle) && widget.remote == null)
        MeshRow(
          title: restartTitle,
          icon: Icons.restart_alt_rounded,
          tint: tint,
          onTap: _busy
              ? null
              : () => unawaited(_power(restart.restartRadio, reboot: true)),
        ),
      if (widget.remote case final RemoteAdminConsole console
          when showAction(consoleTitle))
        MeshRow(
          title: consoleTitle,
          icon: Icons.terminal_rounded,
          tint: const Color(0xff6851ab),
          onTap: _busy ? null : () => unawaited(_runCommand(console)),
        ),
      if (widget.remote case final RemoteNeighborTable node
          when node.canReadNeighbors && showAction(neighborsTitle))
        MeshRow(
          title: neighborsTitle,
          icon: Icons.hub_outlined,
          tint: const Color(0xff168a87),
          onTap: _busy ? null : () => unawaited(_runRemote(node.readNeighbors)),
        ),
      if (widget.remote case final RemoteNodePower node
          when showAction(restartNodeTitle))
        MeshRow(
          title: restartNodeTitle,
          icon: Icons.restart_alt_rounded,
          tint: tint,
          onTap: _busy
              ? null
              : () => unawaited(
                  _power(() => node.setPower(reboot: true), reboot: true),
                ),
        ),
      if (widget.remote case final RemoteNodePower node
          when showAction(shutdownNodeTitle))
        MeshRow(
          title: shutdownNodeTitle,
          icon: Icons.power_settings_new_rounded,
          tint: const Color(0xffa95361),
          onTap: _busy
              ? null
              : () => unawaited(
                  _power(() => node.setPower(reboot: false), reboot: false),
                ),
        ),
    ];
    final groups = [
      (tr(context, 'Профиль узла', 'Node profile'), identityRows),
      (tr(context, 'Связь', 'Connections'), connectionRows),
      (
        tr(context, 'Позиция и измерения', 'Location and readings'),
        measurementRows,
      ),
      (tr(context, 'Устройство', 'Device'), deviceRows),
      (tr(context, 'Модули', 'Modules'), moduleRows),
      (tr(context, 'Обслуживание', 'Maintenance'), serviceRows),
    ];
    final peer = widget.peer;
    final info = isProfile && peer == null
        ? widget.controller.radioDeviceInfo(widget.radio)
        : null;
    final remoteModel = isProfile && peer != null
        ? widget.controller.nodeObservation(peer.id)?.boardModel
        : null;
    final profileKey = peer == null
        ? widget.controller.radioPublicKey(widget.radio)
        : widget.controller.cache?.identities[peer.id]?.publicKey;
    final profileSeed = 'radio:${radioKey(widget.radio)}:${peer?.id ?? ''}';
    final heading = _sectionName(widget.section);
    final padding = meshScrollPadding(
      context,
      const EdgeInsets.only(bottom: 20),
    );
    final back = GlassButton(
      icon: Icons.arrow_back_ios_new_rounded,
      label: tr(context, 'Назад', 'Back'),
      onTap: _saving ? null : () => unawaited(Navigator.of(context).maybePop()),
    );
    final save = widget.section == RadioFieldSection.telemetry
        ? null
        : GlassButton(
            icon: Icons.check_rounded,
            label: widget.remote == null
                ? tr(context, 'Сохранить на рации', 'Save to radio')
                : tr(context, 'Сохранить на узле', 'Save to node'),
            primary: _canSave,
            onTap: _canSave ? () => unawaited(_load(save: true)) : null,
          );
    final children = <Widget>[
      if (isProfile ||
          widget.section != RadioFieldSection.telemetry &&
              (_fields.isNotEmpty || widget.initialQuery.isNotEmpty))
        _searchField(style),
      if (_query.isNotEmpty &&
          !_busy &&
          _error == null &&
          (isProfile
              ? groups.every((group) => group.$2.isEmpty)
              : shownFields.isEmpty))
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Text(
            tr(context, 'Настройки не найдены', 'No matching settings'),
            style: TextStyle(color: style.secondary),
          ),
        ),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(18),
          child: Text(switch (_error) {
            'values' => tr(
              context,
              'Проверьте допустимые значения параметров.',
              'Check the parameter values.',
            ),
            'write' => tr(
              context,
              'Рация не подтвердила изменения. Переподключитесь и проверьте значения.',
              'The radio did not confirm the changes. Reconnect and check the values.',
            ),
            _ =>
              widget.remote == null
                  ? tr(
                      context,
                      'Не удалось прочитать настройки. Проверьте подключение к рации.',
                      'Could not read settings. Check the radio connection.',
                    )
                  : tr(
                      context,
                      'Не удалось получить настройки узла. Проверьте радиосвязь.',
                      'Could not read node settings. Check the radio link.',
                    ),
          }, style: TextStyle(color: style.warning)),
        ),
      if (_saved)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Text(
            tr(context, 'Настройки сохранены', 'Settings saved'),
            style: TextStyle(color: style.success),
          ),
        ),
      if (_error != null && _fields.isEmpty && !_busy)
        TextButton(
          onPressed: _load,
          child: Text(tr(context, 'Повторить', 'Retry')),
        ),
      if (isProfile)
        for (final (title, rows) in groups)
          if (rows.isNotEmpty) _settingsGroup(title, rows),
      if (!isProfile && fieldRows.isNotEmpty) _settingsGroup(null, fieldRows),
      if (widget.section == RadioFieldSection.connectivity &&
          widget.radio.network == 'meshcore' &&
          widget.remote == null &&
          serviceRows.isNotEmpty)
        _settingsGroup(null, serviceRows),
      if (widget.section == RadioFieldSection.telemetry) ...[
        if (hasTelemetrySettings)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 5, 16, 10),
            child: MeshGroup(children: [sectionRow(RadioFieldSection.sensors)]),
          ),
        if (widget.remote == null)
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final signal = widget.controller.signalRssi;
              final latency = widget.controller.linkLatency;
              if (signal == null && latency == null) {
                return const SizedBox.shrink();
              }
              if (!widget.controller.isConnectedTo(widget.radio)) {
                return const SizedBox.shrink();
              }
              final local =
                  lanEndpoint(
                    widget.controller.connectionRoute(widget.radio),
                  ) !=
                  null;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 5, 16, 10),
                child: MeshGroup(
                  children: [
                    MeshRow(
                      title: latency != null
                          ? tr(
                              context,
                              'Задержка до рации',
                              'Radio link latency',
                            )
                          : !local
                          ? tr(context, 'Сигнал Bluetooth', 'Bluetooth signal')
                          : tr(
                              context,
                              'Сигнал сети Wi-Fi',
                              'Wi-Fi network signal',
                            ),
                      icon: local
                          ? Icons.wifi_rounded
                          : Icons.bluetooth_rounded,
                      tint: tint,
                      subtitle: _signalValue(context, signal, latency),
                    ),
                  ],
                ),
              );
            },
          ),
        if (!_busy && _error == null && _fields.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(23, 5, 23, 8),
            child: Text(
              tr(
                context,
                'Рация пока не передала показания.',
                'The radio has not reported any readings yet.',
              ),
              style: TextStyle(color: style.secondary),
            ),
          ),
      ],
      if (_commandResult case final result?)
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 2),
          child: SelectableText(
            result,
            style: TextStyle(color: style.secondary),
          ),
        ),
      if (widget.section == RadioFieldSection.position &&
          showAction(tr(context, 'Выбрать на карте', 'Choose on map')) &&
          widget.controller.canSetFixedPosition(widget.radio, widget.remote))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: MeshGroup(
            children: [
              MeshRow(
                title: tr(context, 'Выбрать на карте', 'Choose on map'),
                subtitle: _positionLabel(_anchor ?? _initialPosition),
                icon: Icons.location_on_outlined,
                tint: tint,
                onTap: _busy ? null : () => unawaited(_pickAnchor()),
              ),
            ],
          ),
        ),
      if (widget.section == RadioFieldSection.telemetry)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 0),
          child: GlassActionButton(
            label: tr(context, 'Обновить', 'Refresh'),
            onTap: _busy ? null : _load,
          ),
        ),
    ];
    return Scaffold(
      body: isProfile
          ? RadioProfilePage(
              heading: heading,
              leading: back,
              trailing: save,
              padding: padding,
              boardName:
                  info?.board ?? (remoteModel == null ? null : '#$remoteModel'),
              boardModel: info?.boardModel ?? remoteModel,
              publicKey: profileKey,
              wallpaperSeed: profileSeed,
              protocol: widget.controller.label(widget.radio.network),
              online: peer != null && widget.controller.isNodeOnline(peer.id),
              children: children,
            )
          : PinnedPageList(
              padding: padding,
              header: PageHeading(heading, leading: back, trailing: save),
              children: children,
            ),
    );
  }
}

class RadioSwipeRow extends StatelessWidget {
  const RadioSwipeRow({
    super.key,
    required this.revealed,
    required this.onReveal,
    required this.child,
    this.onDisconnect,
    required this.onRemove,
  });

  final bool revealed;
  final ValueChanged<bool> onReveal;
  final Widget child;
  final VoidCallback? onDisconnect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return SwipeActionsRow(
      revealed: revealed,
      onReveal: onReveal,
      background: style.canvas,
      surface: style.surface,
      actions: [
        if (onDisconnect case final disconnect?)
          (
            label: tr(context, 'Отключить', 'Disconnect'),
            icon: Icons.link_off_rounded,
            color: const Color(0xff1978ca),
            onTap: disconnect,
          ),
        (
          label: tr(context, 'Удалить', 'Remove'),
          icon: Icons.delete_outline_rounded,
          color: const Color(0xffd73d50),
          onTap: onRemove,
        ),
      ],
      child: child,
    );
  }
}

class SignalQuality extends StatelessWidget {
  const SignalQuality({super.key, required this.rssi});
  final int? rssi;

  @override
  Widget build(BuildContext context) {
    final reading = _signalReading(context, rssi);
    return Semantics(
      label: reading.label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [reading.icon, const SizedBox(width: 5), reading.value],
      ),
    );
  }
}

class RadioConnectionStatus extends StatelessWidget {
  const RadioConnectionStatus({
    super.key,
    required this.rssi,
    required this.battery,
    this.latency,
    this.wifi = false,
  });
  final int? rssi;
  final Duration? latency;
  final RadioBattery? battery;
  final bool wifi;

  @override
  Widget build(BuildContext context) {
    final signal = _signalReading(
      context,
      rssi,
      wifi: wifi,
      latency: latency,
      approximate: true,
    );
    final charge = _batteryReading(context);
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(SignalBars.glyphWidth),
        1: FixedColumnWidth(5),
        2: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (final (index, reading) in [signal, charge].indexed) ...[
          if (index > 0)
            const TableRow(
              children: [SizedBox(height: 4), SizedBox(), SizedBox()],
            ),
          TableRow(
            children: [
              Center(child: reading.icon),
              const SizedBox(),
              Semantics(
                label: reading.label,
                excludeSemantics: true,
                child: reading.value,
              ),
            ],
          ),
        ],
      ],
    );
  }

  _RadioReading _batteryReading(BuildContext context) {
    final style = MeshStyle.of(context);
    final color = style.secondary;
    final percent = battery?.percent;
    final estimated = battery?.estimated ?? false;
    final powered = battery?.powered ?? false;
    final reading = powered
        ? tr(context, 'Заряд', 'Charging')
        : percent == null
        ? '—'
        : '${estimated ? '≈' : ''}$percent%';
    final label = switch ((powered, percent, estimated)) {
      (true, _, _) => tr(context, 'Зарядка рации', 'Radio charging'),
      (_, null, _) => tr(
        context,
        'Заряд неизвестен',
        'Battery level unavailable',
      ),
      (_, final level?, true) => tr(
        context,
        'Заряд около $level%',
        'Battery about $level%',
      ),
      (_, final level?, false) => tr(
        context,
        'Заряд $level%',
        'Battery $level%',
      ),
    };
    return (
      label: label,
      icon: CustomPaint(
        size: const Size(SignalBars.glyphWidth, 12),
        painter: _BatteryGlyph(
          percent: percent,
          powered: powered,
          color: color,
          background: style.surface,
        ),
      ),
      value: Text(reading, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

typedef _RadioReading = ({Widget icon, Widget value, String label});

_RadioReading _signalReading(
  BuildContext context,
  int? rssi, {
  bool wifi = false,
  Duration? latency,
  bool approximate = false,
}) {
  final reading = _signalValue(context, rssi, latency);
  final showApproximation = approximate && (rssi != null || latency != null);
  final label = latency != null
      ? tr(context, 'Задержка до рации', 'Radio link latency')
      : wifi
      ? tr(context, 'Сигнал сети Wi-Fi', 'Wi-Fi network signal')
      : tr(context, 'Сигнал Bluetooth', 'Bluetooth signal');
  return (
    label: showApproximation
        ? tr(context, '$label около $reading', '$label about $reading')
        : '$label $reading',
    icon: SignalBars(
      level: latency == null
          ? SignalBars.bluetooth(rssi)
          : SignalBars.latency(
              latency,
              ios: wifi && Theme.of(context).platform == TargetPlatform.iOS,
            ),
      wifi: wifi,
    ),
    value: Text(
      showApproximation ? '≈$reading' : reading,
      style: TextStyle(color: MeshStyle.of(context).secondary, fontSize: 12),
    ),
  );
}

String _signalValue(BuildContext context, int? rssi, Duration? latency) {
  if (latency != null) {
    final unit = tr(context, 'мс', 'ms');
    return '${latency.inMilliseconds} $unit';
  }
  return rssi == null ? '—' : '$rssi dBm';
}

class _BatteryGlyph extends CustomPainter {
  const _BatteryGlyph({
    required this.percent,
    required this.powered,
    required this.color,
    required this.background,
  });

  final int? percent;
  final bool powered;
  final Color color, background;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = color.withValues(alpha: .6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const body = Rect.fromLTWH(.5, 1, 21, 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(3)),
      outline,
    );
    final fill = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(22.5, 4.5, 1.5, 3),
        const Radius.circular(1),
      ),
      fill,
    );
    if (percent case final level? when level > 0) {
      const track = Rect.fromLTWH(2, 2.5, 18, 7);
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(track, const Radius.circular(1.5)),
      );
      canvas.drawRect(
        Rect.fromLTWH(
          track.left,
          track.top,
          track.width * level / 100,
          track.height,
        ),
        fill,
      );
      canvas.restore();
    }
    if (powered) {
      final bolt = Path()
        ..moveTo(11.9, 3)
        ..lineTo(8.6, 6.45)
        ..lineTo(10.6, 6.45)
        ..lineTo(10.05, 9)
        ..lineTo(13.4, 5.55)
        ..lineTo(11.35, 5.55)
        ..close();
      canvas.drawPath(
        bolt,
        Paint()..color = (percent ?? 0) >= 90 ? background : color,
      );
    }
  }

  @override
  bool shouldRepaint(_BatteryGlyph oldDelegate) =>
      percent != oldDelegate.percent ||
      powered != oldDelegate.powered ||
      color != oldDelegate.color ||
      background != oldDelegate.background;
}

class _RadioInformation extends StatelessWidget {
  const _RadioInformation({required this.controller, required this.radio});

  final MeshController controller;
  final Radio radio;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final info = controller.radioDeviceInfo(radio);
        final current = controller.radios
            .where((item) => radioKey(item) == radioKey(radio))
            .firstOrNull;
        final key = controller.radioPublicKey(radio);
        final endpoint = lanEndpoint(controller.connectionRoute(radio));
        final unknown = tr(context, 'Нет данных', 'Unavailable');
        final items = [
          (
            Icons.badge_outlined,
            tr(context, 'Название', 'Name'),
            current?.name ?? radio.name,
          ),
          (
            Icons.hub_outlined,
            tr(context, 'Технология', 'Technology'),
            controller.label(radio.network),
          ),
          (
            Icons.system_update_alt_rounded,
            tr(context, 'Версия прошивки', 'Firmware version'),
            info?.firmware,
          ),
          (Icons.memory_rounded, tr(context, 'Плата', 'Board'), info?.board),
          if (info?.build case final build?)
            (
              Icons.calendar_today_outlined,
              tr(context, 'Сборка прошивки', 'Firmware build'),
              build,
            ),
          if (info?.protocol case final number?)
            (
              Icons.settings_ethernet_rounded,
              tr(context, 'Версия протокола', 'Protocol version'),
              number,
            ),
          (
            endpoint == null ? Icons.bluetooth_rounded : Icons.wifi_rounded,
            tr(context, 'Подключение', 'Connection'),
            endpoint == null ? 'Bluetooth' : 'Wi-Fi',
          ),
          if (endpoint != null)
            (
              Icons.language_rounded,
              tr(context, 'Адрес', 'Address'),
              Uri(
                scheme: 'tcp',
                host: endpoint.host,
                port: endpoint.port,
              ).authority,
            ),
        ];
        return PinnedPageList(
          padding: meshScrollPadding(
            context,
            const EdgeInsets.only(bottom: 20),
          ),
          header: PageHeading(
            tr(context, 'Информация об устройстве', 'Device information'),
            leading: GlassButton(
              icon: Icons.arrow_back_ios_new_rounded,
              label: tr(context, 'Назад', 'Back'),
              onTap: () => Navigator.pop(context),
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: MeshGroup(
                children: [
                  for (final (icon, label, value) in items)
                    _DeviceInfoRow(
                      icon: icon,
                      label: label,
                      value: value ?? unknown,
                    ),
                  _DeviceInfoRow(
                    icon: Icons.key_rounded,
                    label: tr(context, 'Публичный ключ', 'Public key'),
                    value: key == null ? unknown : _keyPreview(key),
                    copy: key,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

String _keyPreview(String key) {
  final prefix = key.length > 16 ? key.substring(0, 16) : key;
  final blocks = RegExp(r'.{1,4}')
      .allMatches(prefix)
      .map((block) => block.group(0));
  return '${blocks.join(' ')}${key.length > 16 ? '...' : ''}';
}

class _DeviceInfoRow extends StatelessWidget {
  const _DeviceInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.copy,
  });

  final IconData icon;
  final String label, value;
  final String? copy;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final key = copy;
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 10, 14, 10),
        child: Row(
          children: [
            MeshRowIcon(
              icon: icon,
              tint: style.dark
                  ? const Color(0xff287795)
                  : const Color(0xff2978d5),
            ),
            const SizedBox(width: 19),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(color: style.secondary, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  if (key == null)
                    SelectableText(value)
                  else
                    Text(value, style: TextStyle(color: style.text)),
                ],
              ),
            ),
            if (key != null)
              MeshIconButton(
                label: tr(
                  context,
                  'Скопировать публичный ключ',
                  'Copy public key',
                ),
                icon: Icon(Icons.content_copy_rounded, color: style.accent),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: key));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          tr(
                            context,
                            'Публичный ключ скопирован',
                            'Public key copied',
                          ),
                        ),
                      ),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
