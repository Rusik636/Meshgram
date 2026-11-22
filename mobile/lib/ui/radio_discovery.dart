// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Radio;

import '../mesh/controller.dart';
import '../mesh/network.dart';
import 'radio_settings.dart';
import 'style.dart';
import 'page_route.dart';

String bluetoothProblemMessage(
  BuildContext context,
  BluetoothProblem problem,
) => switch (problem) {
  BluetoothProblem.off => tr(
    context,
    'Bluetooth выключен. Включите его для поиска и подключения.',
    'Bluetooth is off. Turn it on to find and connect to radios.',
  ),
  BluetoothProblem.permission =>
    Theme.of(context).platform == TargetPlatform.android
        ? tr(
            context,
            'Разрешите Bluetooth в настройках приложения. На Android 11 и более ранних версиях для поиска нужен доступ к местоположению.',
            'Allow Bluetooth in app settings. On Android 11 and earlier, scanning needs location access.',
          )
        : tr(
            context,
            'Разрешите Bluetooth в настройках приложения.',
            'Allow Bluetooth in app settings.',
          ),
  BluetoothProblem.location => tr(
    context,
    'Включите геолокацию для поиска по Bluetooth на этой версии Android.',
    'Turn on Location services to scan over Bluetooth on this version of Android.',
  ),
  BluetoothProblem.unsupported => tr(
    context,
    'Bluetooth LE недоступен на этом устройстве.',
    'Bluetooth LE is unavailable on this device.',
  ),
  BluetoothProblem.pairing => tr(
    context,
    'Сопряжение не завершено. Выберите рацию снова и подтвердите системный запрос Bluetooth.',
    'Pairing did not finish. Select the radio again and confirm the Bluetooth system request.',
  ),
};

class RadioDiscoveryPage extends StatefulWidget {
  const RadioDiscoveryPage({super.key, required this.controller});
  final MeshController controller;

  @override
  State<RadioDiscoveryPage> createState() => _RadioDiscoveryState();
}

class _RadioDiscoveryState extends State<RadioDiscoveryPage> {
  String? _connecting;
  bool _showPairingHint = false;
  String? _failed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_scan());
    });
  }

  @override
  void dispose() {
    final controller = widget.controller;
    unawaited(Future.microtask(controller.stopDiscovery));
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _failed = null);
    await widget.controller.scan();
  }

  Future<void> _manualLan(Map<String, LanRadioProtocol> protocols) async {
    final form = GlobalKey<FormState>();
    var network = protocols.keys.first;
    var host = '';
    var port = '${protocols[network]!.port}';
    final radio = await showMeshDialog<Radio>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, change) => MeshDialog(
          title: Text(tr(context, 'Подключить по Wi-Fi', 'Connect over Wi-Fi')),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: network,
                  isExpanded: true,
                  items: [
                    for (final id in protocols.keys)
                      DropdownMenuItem(
                        value: id,
                        child: Text(widget.controller.label(id)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    change(() {
                      network = value;
                      port = '${protocols[value]!.port}';
                    });
                  },
                ),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: tr(
                      context,
                      'IP-адрес или имя',
                      'IP address or hostname',
                    ),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (value) => host = value,
                  validator: (_) {
                    try {
                      lanRadio(network, host, protocols[network]!.port);
                      return null;
                    } on FormatException {
                      return tr(
                        context,
                        'Проверьте адрес',
                        'Check the address',
                      );
                    }
                  },
                ),
                TextFormField(
                  key: ValueKey(network),
                  initialValue: port,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Порт', 'Port'),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => port = value,
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    return parsed != null && parsed >= 1 && parsed <= 65535
                        ? null
                        : tr(context, 'Проверьте порт', 'Check the port');
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context, 'Отмена', 'Cancel')),
            ),
            TextButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                Navigator.pop(
                  context,
                  lanRadio(network, host, int.parse(port.trim())),
                );
              },
              child: Text(tr(context, 'Подключить', 'Connect')),
            ),
          ],
        ),
      ),
    );
    if (radio != null && mounted) await _pair(radio);
  }

  Future<void> _pair(Radio radio) async {
    if (_connecting != null) return;
    final controller = widget.controller;
    final key = radioKey(radio);
    final saved = controller.radios.map(radioKey).toSet();
    setState(() {
      _connecting = key;
      _showPairingHint =
          Theme.of(context).platform == TargetPlatform.android &&
          lanEndpoint(radio) == null;
      _failed = null;
    });
    try {
      await controller.connect(radio);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (!controller.isConnectedTo(radio)) {
        setState(() => _failed = 'connection');
        return;
      }
      final profile = controller.active!;
      final steps = !saved.contains(radioKey(profile))
          ? await controller.setupSteps(profile)
          : const <RadioSetupStep>[];
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (steps.isNotEmpty) {
        unawaited(
          Navigator.of(context).pushReplacement<bool, void>(
            meshPageRoute<bool>(
              context,
              builder: (_) => _RadioSetupPage(
                controller: controller,
                radio: profile,
                steps: steps,
              ),
            ),
          ),
        );
      } else {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        if (controller.isConnectedTo(radio)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  context,
                  'Рация подключена. Не удалось прочитать параметры первичной настройки.',
                  'Radio connected. Could not read the initial setup settings.',
                ),
              ),
            ),
          );
          Navigator.of(context).pop();
        } else {
          setState(() => _failed = 'connection');
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _connecting = null;
          _showPairingHint = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final style = MeshStyle.of(context);
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final results = controller.discovered;
            final protocols = controller.lanProtocols;
            final bluetooth = controller.bluetoothProblem;
            final showBluetoothProblem =
                bluetooth != null &&
                (results.isEmpty || _failed == 'connection');
            final status = _connecting != null
                ? tr(context, 'Подключаем рацию…', 'Connecting to radio…')
                : controller.scanning
                ? tr(context, 'Ищем рации поблизости…', 'Scanning for radios…')
                : showBluetoothProblem
                ? bluetoothProblemMessage(context, bluetooth)
                : _failed == 'connection'
                ? tr(
                    context,
                    'Подключение не удалось. Выберите рацию ещё раз.',
                    'Connection failed. Select the radio to retry.',
                  )
                : results.isEmpty && controller.error == 'bluetooth'
                ? tr(
                    context,
                    'Проверьте Bluetooth и разрешение на поиск.',
                    'Check Bluetooth and scanning permission.',
                  )
                : results.isEmpty && controller.error == 'localNetwork'
                ? tr(
                    context,
                    'Поиск по Wi-Fi недоступен. Можно ввести адрес рации.',
                    'Wi-Fi discovery is unavailable. You can enter the radio address.',
                  )
                : results.isEmpty
                ? tr(
                    context,
                    'Рации поблизости пока не найдены.',
                    'No radios found nearby.',
                  )
                : tr(
                    context,
                    'Выберите рацию для подключения',
                    'Select a radio to connect',
                  );
            return PinnedPageList(
              padding: meshScrollPadding(
                context,
                const EdgeInsets.only(bottom: 16),
              ),
              header: PageHeading(
                tr(context, 'Добавить рацию', 'Add a radio'),
                leading: GlassButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  label: tr(context, 'Назад', 'Back'),
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 250),
                    child: _DiscoveryRadar(
                      results: results
                          .where((item) => lanEndpoint(item.radio) == null)
                          .toList(),
                      active: controller.scanning || _connecting != null,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  child: Text(
                    status,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: style.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                  child: Text(
                    _showPairingHint
                        ? tr(
                            context,
                            'При первом подключении подтвердите системный запрос Bluetooth. Если диалог не открылся, проверьте шторку уведомлений.',
                            'Confirm the Bluetooth pairing request on first connection. If no dialog opens, check your notifications.',
                          )
                        : tr(
                            context,
                            'Точки ближе к центру показывают более сильный сигнал Bluetooth.',
                            'Dots closer to the center indicate a stronger Bluetooth signal.',
                          ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: style.secondary, fontSize: 12),
                  ),
                ),
                if (results.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: MeshGroup(
                      children: [
                        for (final item in results)
                          MeshRow(
                            title: item.radio.name,
                            subtitle: switch (lanEndpoint(item.radio)) {
                              final endpoint? =>
                                '${controller.label(item.radio.network)} · ${endpoint.host}:${endpoint.port}',
                              null => controller.label(item.radio.network),
                            },
                            icon: lanEndpoint(item.radio) == null
                                ? Icons.cell_tower_rounded
                                : Icons.wifi_rounded,
                            tint: const Color(0xff168a87),
                            trailing: _connecting == radioKey(item.radio)
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : lanEndpoint(item.radio) == null
                                ? SignalQuality(rssi: item.rssi)
                                : null,
                            onTap: _connecting == null
                                ? () => unawaited(_pair(item.radio))
                                : null,
                          ),
                      ],
                    ),
                  ),
                if (bluetooth == BluetoothProblem.off &&
                    controller.canEnableBluetooth &&
                    Theme.of(context).platform == TargetPlatform.android)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: GlassActionButton(
                      label: tr(
                        context,
                        'Включить Bluetooth',
                        'Turn on Bluetooth',
                      ),
                      onTap: _connecting != null || controller.scanning
                          ? null
                          : () async {
                              if (await controller.enableBluetooth() &&
                                  mounted) {
                                await _scan();
                              }
                            },
                    ),
                  ),
                if (protocols.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: MeshGroup(
                      children: [
                        MeshRow(
                          title: tr(
                            context,
                            'Подключить по Wi-Fi',
                            'Connect over Wi-Fi',
                          ),
                          icon: Icons.wifi_rounded,
                          tint: const Color(0xff3276bd),
                          onTap: _connecting == null
                              ? () => unawaited(_manualLan(protocols))
                              : null,
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: GlassActionButton(
                    label: tr(context, 'Повторить поиск', 'Scan again'),
                    onTap: controller.scanning || _connecting != null
                        ? null
                        : () => unawaited(_scan()),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DiscoveryRadar extends StatefulWidget {
  const _DiscoveryRadar({required this.results, required this.active});

  final List<DiscoveredRadio> results;
  final bool active;

  @override
  State<_DiscoveryRadar> createState() => _DiscoveryRadarState();
}

class _DiscoveryRadarState extends State<_DiscoveryRadar>
    with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );

  void _updateMotion() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!_sweep.isAnimating) _sweep.repeat();
    } else if (_sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didUpdateWidget(_DiscoveryRadar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _updateMotion();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _RadarPainter(
            _sweep,
            widget.results,
            style.accent,
            style.separator,
            style.dark,
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.sweep, this.results, this.accent, this.ring, this.dark)
    : super(repaint: sweep);

  final Animation<double> sweep;
  final List<DiscoveredRadio> results;
  final Color accent, ring;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .46;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: dark ? .15 : .12),
            accent.withValues(alpha: .025),
          ],
        ).createShader(rect),
    );
    final line = Paint()
      ..color = Color.lerp(ring, accent, .33)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75;
    for (final proportion in [.23, .48, .74, 1.0]) {
      canvas.drawCircle(center, radius * proportion, line);
    }
    for (var angle = 0; angle < 8; angle++) {
      final vector = Offset.fromDirection(angle * math.pi / 4, radius);
      canvas.drawLine(center, center + vector, line);
    }
    final rotation = 2 * math.pi * sweep.value;
    if (sweep.value != 0) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = SweepGradient(
            colors: [
              Colors.transparent,
              Colors.transparent,
              accent.withValues(alpha: .34),
            ],
            stops: const [0, .79, 1],
            transform: GradientRotation(rotation),
          ).createShader(rect),
      );
    }
    for (final item in results) {
      final hash = radioKey(item.radio).codeUnits
          .fold(0, (sum, char) => (sum * 31 + char) & 0xffff);
      final distance = ((-item.rssi - 30) / 70).clamp(.16, .93);
      final point =
          center +
          Offset.fromDirection(hash / 65535 * math.pi * 2, radius * distance);
      canvas.drawCircle(
        point,
        8,
        Paint()..color = accent.withValues(alpha: .17),
      );
      canvas.drawCircle(point, 3.2, Paint()..color = accent);
    }
    canvas.drawCircle(center, 3, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.results != results ||
      old.accent != accent ||
      old.ring != ring ||
      old.dark != dark;
}

class _RadioSetupPage extends StatefulWidget {
  const _RadioSetupPage({
    required this.controller,
    required this.radio,
    required this.steps,
  });

  final MeshController controller;
  final Radio radio;
  final List<RadioSetupStep> steps;

  @override
  State<_RadioSetupPage> createState() => _RadioSetupState();
}

class _RadioSetupState extends State<_RadioSetupPage> {
  late final _values = <String, String>{
    for (final step in widget.steps)
      for (final field in step.fields) field.id: field.value,
  };
  final _form = GlobalKey<FormState>();
  int _step = 0;
  bool _saving = false;
  String? _error;

  Future<void> _next() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    if (_step < widget.steps.length - 1) {
      setState(() => _step++);
      return;
    }
    final changed = {
      for (final step in widget.steps)
        for (final field in step.fields)
          if (_values[field.id]!.trim() != field.value)
            field.id: _values[field.id]!.trim(),
    };
    if (changed.isEmpty) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.writeRadioSettings(widget.radio, changed);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException ? 'values' : 'connection',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _input(RadioField field) {
    final title = tr(context, field.russian, field.title);
    final value = _values[field.id];
    String? validate(String? input) => input?.trim().isNotEmpty == true
        ? null
        : tr(context, 'Заполните это поле', 'Complete this field');
    final decoration = InputDecoration(
      labelText: title,
      suffixText: field.units,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
    );
    if (field.kind == RadioFieldKind.choice) {
      return DropdownButtonFormField<String>(
        key: ValueKey(field.id),
        initialValue: field.choices.containsKey(value) ? value : null,
        isExpanded: true,
        decoration: decoration,
        validator: validate,
        items: [
          for (final choice in field.choices.entries)
            DropdownMenuItem(value: choice.key, child: Text(choice.value)),
        ],
        onChanged: _saving ? null : (next) => _values[field.id] = next ?? '',
      );
    }
    return TextFormField(
      key: ValueKey(field.id),
      initialValue: value,
      enabled: !_saving,
      decoration: decoration,
      keyboardType: switch (field.kind) {
        RadioFieldKind.decimal => const TextInputType.numberWithOptions(
          decimal: true,
        ),
        RadioFieldKind.integer => const TextInputType.numberWithOptions(
          signed: true,
        ),
        _ => TextInputType.text,
      },
      validator: validate,
      onChanged: (next) => _values[field.id] = next,
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_step];
    final done = _step == widget.steps.length - 1;
    final style = MeshStyle.of(context);
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Form(
          key: _form,
          child: PinnedPageList(
            padding: meshScrollPadding(
              context,
              const EdgeInsets.only(bottom: 18),
            ),
            header: PageHeading(
              tr(context, 'Настройка рации', 'Radio setup'),
              leading: GlassButton(
                icon: Icons.arrow_back_ios_new_rounded,
                label: tr(context, 'Назад', 'Back'),
                onTap: _saving
                    ? null
                    : () {
                        if (_step == 0) {
                          Navigator.of(context).pop(false);
                        } else {
                          setState(() => _step--);
                        }
                      },
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 15, 20, 4),
                child: Text(
                  tr(
                    context,
                    'Шаг ${_step + 1} из ${widget.steps.length}',
                    'Step ${_step + 1} of ${widget.steps.length}',
                  ),
                  style: TextStyle(
                    color: style.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Text(
                  tr(context, step.russian, step.title),
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final field in step.fields)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: _input(field),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 11),
                  child: Text(
                    _error == 'values'
                        ? tr(
                            context,
                            'Проверьте значения полей.',
                            'Check the field values.',
                          )
                        : tr(
                            context,
                            'Рация не подтвердила сохранение. Если она перезагрузилась, переподключитесь.',
                            'The radio did not confirm settings. Reconnect if it restarted.',
                          ),
                    style: TextStyle(color: style.warning),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 5),
                child: GlassActionButton(
                  label: _saving
                      ? tr(context, 'Сохраняем…', 'Saving…')
                      : done
                      ? tr(context, 'Сохранить на рации', 'Save to radio')
                      : tr(context, 'Продолжить', 'Continue'),
                  onTap: _saving ? null : () => unawaited(_next()),
                ),
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pop(true),
                child: Text(tr(context, 'Настроить позже', 'Set up later')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
