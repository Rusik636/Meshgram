import 'dart:async';

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter/services.dart';

import '../mesh/controller.dart';
import '../mesh/network.dart';
import '../mesh/nodes.dart';
import '../mesh/route_trace.dart';
import 'style.dart';
import 'signal.dart';

String nodeRoleLabel(BuildContext context, MeshNodeRole? role) =>
    switch (role) {
      MeshNodeRole.client => tr(context, 'Клиент', 'Client'),
      MeshNodeRole.repeater => tr(context, 'Ретранслятор', 'Repeater'),
      MeshNodeRole.room => tr(context, 'Сервер комнаты', 'Room server'),
      MeshNodeRole.sensor => tr(context, 'Датчик', 'Sensor'),
      MeshNodeRole.tracker => tr(context, 'Трекер', 'Tracker'),
      MeshNodeRole.router => tr(context, 'Маршрутизатор', 'Router'),
      MeshNodeRole.gateway => tr(context, 'Шлюз', 'Gateway'),
      null => tr(context, 'Узел', 'Node'),
    };

class NodeActionsPanel extends StatefulWidget {
  const NodeActionsPanel({
    super.key,
    required this.controller,
    required this.peer,
    this.openAdmin,
  });

  final MeshController controller;
  final Peer peer;
  final VoidCallback? openAdmin;

  @override
  State<NodeActionsPanel> createState() => _NodeActionsPanelState();
}

class _NodeActionsPanelState extends State<NodeActionsPanel> {
  bool _busy = false;
  Timer? _traceTick;
  final _traceClock = ValueNotifier(0);

  @override
  void dispose() {
    _traceTick?.cancel();
    _traceClock.dispose();
    super.dispose();
  }

  Future<void> _run(NodeAction action, bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (action == NodeAction.sensorLogin) {
        await showMeshDialog<void>(
          context: context,
          builder: (_) => _SensorLogin(
            name: widget.peer.name,
            login: (password) => widget.controller.runNodeAction(
              widget.peer,
              action,
              password: password,
            ),
          ),
        );
        return;
      }
      if (action == NodeAction.resetPath ||
          (action == NodeAction.ignore && enabled)) {
        final reset = action == NodeAction.resetPath;
        final confirmed = await showMeshDialog<bool>(
          context: context,
          builder: (context) => MeshDialog(
            title: Text(_label(context, action, enabled)),
            content: Text(
              reset
                  ? tr(
                      context,
                      'Рация забудет сохранённый маршрут до этого узла.',
                      'The radio will clear its saved path to this node.',
                    )
                  : tr(
                      context,
                      'Ваша рация будет игнорировать пакеты этого узла. Прошивка может удалить его сообщения из памяти рации.',
                      'Your radio will ignore packets from this node. Its firmware may clear messages from the radio itself.',
                    ),
            ),
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
        if (confirmed != true || !mounted) return;
      }
      final result = widget.controller.runNodeAction(
        widget.peer,
        action,
        enabled: enabled,
      );
      if (action == NodeAction.favorite ||
          action == NodeAction.ignore ||
          action == NodeAction.resetPath) {
        await result;
        if (mounted) {
          _notify(
            tr(context, 'Команда передана рации', 'Command sent to the radio'),
          );
        }
      } else {
        final completion = result.then<void>((_) {}, onError: (Object _) {});
        await showMeshSheet<void>(
          context: context,
          builder: (context) => _ResponseSheet(
            title: _label(context, action, enabled),
            result: result,
            waiting: action == NodeAction.savedPath
                ? tr(
                    context,
                    'Читаем данные с рации…',
                    'Reading from the radio…',
                  )
                : tr(context, 'Ждём ответ узла…', 'Waiting for the node…'),
          ),
        );
        await completion;
      }
    } catch (error) {
      if (mounted) _notify(_failure(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notify(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final peer = widget.peer;
    final actions = controller.nodeActions(peer);
    final observation = controller.nodeObservation(peer.id);
    final history = controller.routeTraceHistory(peer.id);
    final canTrace = controller.canTraceRoute(peer);
    final now = DateTime.now();
    final remaining =
        controller.routeTraceBlockedUntil?.difference(now) ?? Duration.zero;
    final coolingDown = canTrace && remaining > Duration.zero;
    final enabledTrace =
        canTrace && !coolingDown && !controller.startingRouteTrace && !_busy;
    if (coolingDown || history.any((trace) => trace.isWaitingAt(now))) {
      _traceTick ??= Timer(const Duration(seconds: 1), () {
        _traceTick = null;
        if (!mounted) return;
        _traceClock.value++;
        setState(() {});
      });
    }
    Widget? action(NodeAction id) {
      if (!actions.contains(id)) return null;
      final enabled = switch (id) {
        NodeAction.favorite => observation?.favorite != true,
        NodeAction.ignore => observation?.ignored != true,
        _ => true,
      };
      return MeshRow(
        title: _label(context, id, enabled),
        icon: _icon(id, enabled),
        tint: switch (id) {
          NodeAction.telemetry ||
          NodeAction.environment => const Color(0xff168a87),
          NodeAction.sensorLogin => const Color(0xff6851ab),
          NodeAction.favorite => const Color(0xffa36b22),
          _ => const Color(0xff2978d5),
        },
        onTap: _busy ? null : () => unawaited(_run(id, enabled)),
      );
    }

    if (actions.isEmpty &&
        history.isEmpty &&
        widget.openAdmin == null &&
        observation?.position == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          context,
          tr(context, 'Связь и маршрут', 'Connection and route'),
          [
            if (canTrace || history.isNotEmpty) ...[
              MeshRow(
                title: _label(context, NodeAction.trace, true),
                titleColor: enabledTrace
                    ? null
                    : MeshStyle.of(context).secondary,
                icon: _icon(NodeAction.trace, true),
                tint: const Color(0xff2978d5),
                showChevron: false,
                subtitle: history.isEmpty
                    ? null
                    : _traceStatus(context, history.first, now, inline: true),
                trailing: coolingDown
                    ? Text(
                        tr(
                          context,
                          '${(remaining.inMilliseconds + 999) ~/ 1000} с',
                          '${(remaining.inMilliseconds + 999) ~/ 1000} s',
                        ),
                        style: TextStyle(
                          color: MeshStyle.of(context).secondary,
                        ),
                      )
                    : null,
                onTap: enabledTrace
                    ? () => unawaited(controller.startRouteTrace(peer))
                    : null,
              ),
              MeshRow(
                title: tr(context, 'История трассировок', 'Trace history'),
                icon: Icons.history_rounded,
                tint: const Color(0xff2978d5),
                onTap: () => unawaited(_showTraceHistory()),
              ),
            ],
            ?action(NodeAction.neighbors),
            ?action(NodeAction.savedPath),
            ?action(NodeAction.resetPath),
          ],
        ),
        _section(
          context,
          tr(context, 'Телеметрия и координаты', 'Telemetry and position'),
          [
            ?action(NodeAction.telemetry),
            ?action(NodeAction.environment),
            ?action(NodeAction.position),
            if (observation?.position case final position?)
              MeshRow(
                title: tr(
                  context,
                  'Последние координаты',
                  'Last known position',
                ),
                subtitle:
                    '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
                icon: Icons.location_on_outlined,
                tint: const Color(0xff168a87),
                showChevron: false,
                onTap: () => unawaited(_copyPosition(position)),
              ),
          ],
        ),
        _section(context, tr(context, 'Управление', 'Administration'), [
          if (widget.openAdmin != null)
            MeshRow(
              title: tr(context, 'Управление узлом', 'Manage node'),
              icon: Icons.admin_panel_settings_outlined,
              tint: const Color(0xff6851ab),
              onTap: _busy ? null : widget.openAdmin,
            ),
          ?action(NodeAction.sensorLogin),
        ]),
        _section(context, tr(context, 'Контакт', 'Contact'), [
          ?action(NodeAction.identity),
          ?action(NodeAction.favorite),
          ?action(NodeAction.ignore),
        ]),
      ],
    );
  }

  Future<void> _showTraceHistory() async {
    final controller = widget.controller;
    final radio = controller.active;
    if (radio == null) return;
    final peer = widget.peer.id;
    final updates = Listenable.merge([controller, _traceClock]);
    await showMeshSheet<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: updates,
        builder: (context, _) {
          final history = controller.routeTraceHistory(peer, radio: radio);
          final now = DateTime.now();
          return SheetBody(
            title: tr(context, 'История трассировок', 'Trace history'),
            children: [
              if (history.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Text(
                    tr(context, 'Пока нет трассировок', 'No traces yet'),
                  ),
                )
              else
                MeshGroup(
                  children: [
                    for (final trace in history)
                      MeshRow(
                        title: _traceTime(context, trace.sentAt),
                        subtitle: _traceStatus(context, trace, now),
                        icon: Icons.route_rounded,
                        tint: const Color(0xff2978d5),
                        onTap: trace.receivedAt == null
                            ? null
                            : () =>
                                  unawaited(_showTrace(context, radio, trace)),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showTrace(
    BuildContext context,
    Radio radio,
    RouteTrace initial,
  ) {
    final controller = widget.controller;
    return showMeshSheet<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final trace =
              controller.routeTrace(radio, initial.request) ?? initial;
          return SheetBody(
            title: _traceTime(context, trace.sentAt),
            children: [
              Padding(
                padding: const EdgeInsets.all(15),
                child: Text(
                  tr(
                    context,
                    'Ответ получен ${_traceTime(context, trace.receivedAt!)}',
                    'Reply received ${_traceTime(context, trace.receivedAt!)}',
                  ),
                ),
              ),
              _responseFields(context, trace.fields),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }

  Future<void> _copyPosition(NodePosition position) async {
    await Clipboard.setData(
      ClipboardData(text: '${position.latitude}, ${position.longitude}'),
    );
    if (mounted) {
      _notify(tr(context, 'Координаты скопированы', 'Coordinates copied'));
    }
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 8, 7),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: MeshStyle.of(context).secondary,
                ),
              ),
            ),
          ),
          MeshGroup(children: rows),
        ],
      ),
    );
  }
}

String _traceTime(BuildContext context, DateTime time) {
  final locale = MaterialLocalizations.of(context);
  final local = time.toLocal();
  final clock = locale.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return '${locale.formatCompactDate(local)}, $clock';
}

String _traceStatus(
  BuildContext context,
  RouteTrace trace,
  DateTime now, {
  bool inline = false,
}) {
  if (trace.receivedAt != null) {
    return trace.arrivedLate
        ? tr(context, 'Ответ получен с задержкой', 'Reply received late')
        : tr(context, 'Маршрут получен', 'Route received');
  }
  return switch (trace.failure) {
    RouteTraceFailure.rateLimited => tr(
      context,
      'Рация ограничила частоту трассировок',
      'The radio rate-limited trace requests',
    ),
    RouteTraceFailure.rejected => tr(
      context,
      'Трассировку не удалось отправить',
      'Could not send the trace',
    ),
    null when trace.isWaitingAt(now) => tr(
      context,
      'Ждём ответ узла…',
      'Waiting for the node…',
    ),
    null =>
      inline
          ? tr(
              context,
              'Ответ не пришёл за 30 секунд. Проверьте историю трассировок.',
              'No reply after 30 seconds. Check the trace history.',
            )
          : tr(context, 'Пока без ответа', 'No reply yet'),
  };
}

class _ResponseSheet extends StatelessWidget {
  const _ResponseSheet({
    required this.title,
    required this.result,
    required this.waiting,
  });
  final String title, waiting;
  final Future<List<RadioField>> result;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return FutureBuilder<List<RadioField>>(
      future: result,
      builder: (context, snapshot) {
        return SheetBody(
          title: title,
          children: [
            if (snapshot.connectionState != ConnectionState.done)
              Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(waiting)),
                  ],
                ),
              )
            else if (snapshot.hasError)
              Padding(
                padding: const EdgeInsets.all(15),
                child: Text(
                  _failure(context, snapshot.error!),
                  style: TextStyle(color: style.secondary),
                ),
              )
            else if (snapshot.data?.isEmpty == true)
              Padding(
                padding: const EdgeInsets.all(15),
                child: Text(
                  tr(
                    context,
                    'Узел вернул пустой список',
                    'The node returned an empty list',
                  ),
                ),
              )
            else if (snapshot.data case final fields?)
              _responseFields(context, fields),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

Widget _responseFields(BuildContext context, List<RadioField> fields) {
  final style = MeshStyle.of(context);
  return MeshGroup(
    inset: 15,
    children: [
      for (final field in fields)
        if (field.hops.isNotEmpty &&
            field.hops.any((hop) => hop.snr != null || hop.rssi != null))
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(context, field.russian, field.title),
                  style: TextStyle(
                    color: style.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                for (final hop in field.hops)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(child: SelectableText(hop.name)),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hop.snr case final snr?)
                              _SignalMetric(
                                SignalBars.snr(snr),
                                'SNR ${snr.toStringAsFixed(1)} dB',
                              ),
                            if (hop.rssi case final rssi?)
                              _SignalMetric(
                                SignalBars.lora(rssi),
                                'RSSI $rssi dBm',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          )
        else
          ListTile(
            title: Text(tr(context, field.russian, field.title)),
            subtitle: SelectableText(_fieldValue(context, field)),
          ),
    ],
  );
}

String _fieldValue(BuildContext context, RadioField field) {
  if (field.id == 'route' || field.id == 'return') {
    if (field.value == '0') return tr(context, 'Напрямую', 'Direct');
    if (field.value == 'Flood') return tr(context, 'Через сеть', 'Flood');
  }
  final units = field.units;
  return units == null ? field.value : '${field.value} $units';
}

class _SignalMetric extends StatelessWidget {
  const _SignalMetric(this.level, this.value);
  final int level;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SignalBars(level: level),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            color: MeshStyle.of(context).secondary,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class _SensorLogin extends StatefulWidget {
  const _SensorLogin({required this.name, required this.login});
  final String name;
  final Future<void> Function(String password) login;

  @override
  State<_SensorLogin> createState() => _SensorLoginState();
}

class _SensorLoginState extends State<_SensorLogin> {
  final _password = TextEditingController();
  bool _working = false;
  Object? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working || _password.text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.login(_password.text);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(context, 'Датчик подтвердил вход', 'Sensor accepted the login'),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _working = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => MeshDialog(
    title: Text(_label(context, NodeAction.sensorLogin, true)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.name),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          autofocus: true,
          enabled: !_working,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: tr(context, 'Пароль датчика', 'Sensor password'),
          ),
          onSubmitted: (_) => unawaited(_submit()),
        ),
        if (_working) const LinearProgressIndicator(minHeight: 2),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_failure(context, error)),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, 'Отмена', 'Cancel')),
      ),
      TextButton(
        onPressed: _working ? null : () => unawaited(_submit()),
        child: Text(tr(context, 'Войти', 'Sign in')),
      ),
    ],
  );
}

String _failure(BuildContext context, Object error) => switch (error) {
  TimeoutException() => tr(
    context,
    'Узел не ответил. Проверьте связь и доступ.',
    'No reply. Check the link and permissions.',
  ),
  FormatException() => tr(context, 'Нет подходящих данных.', 'No usable data.'),
  _ => tr(
    context,
    'Не удалось выполнить команду. Проверьте связь и доступ.',
    'Command failed. Check the connection and permissions.',
  ),
};

String _label(BuildContext context, NodeAction action, bool enabled) =>
    switch (action) {
      NodeAction.trace => tr(context, 'Проверить маршрут', 'Trace route'),
      NodeAction.neighbors => tr(
        context,
        'Запросить соседние узлы',
        'Request neighbors',
      ),
      NodeAction.savedPath => tr(context, 'Сохранённый маршрут', 'Saved route'),
      NodeAction.resetPath => tr(context, 'Сбросить маршрут', 'Reset route'),
      NodeAction.position => tr(
        context,
        'Запросить координаты',
        'Request position',
      ),
      NodeAction.telemetry => tr(
        context,
        'Запросить телеметрию',
        'Request telemetry',
      ),
      NodeAction.environment => tr(
        context,
        'Запросить показания датчика',
        'Request sensor readings',
      ),
      NodeAction.identity => tr(
        context,
        'Обновить данные узла',
        'Request node info',
      ),
      NodeAction.sensorLogin => tr(
        context,
        'Войти на датчик',
        'Sign in to sensor',
      ),
      NodeAction.favorite =>
        enabled
            ? tr(context, 'Добавить в избранное', 'Add to favorites')
            : tr(context, 'Убрать из избранного', 'Remove from favorites'),
      NodeAction.ignore =>
        enabled
            ? tr(context, 'Игнорировать на рации', 'Ignore on radio')
            : tr(context, 'Снять игнорирование', 'Stop ignoring'),
    };

IconData _icon(NodeAction action, bool enabled) => switch (action) {
  NodeAction.trace => Icons.route_rounded,
  NodeAction.neighbors => Icons.hub_outlined,
  NodeAction.savedPath => Icons.alt_route_rounded,
  NodeAction.resetPath => Icons.restart_alt_rounded,
  NodeAction.position => Icons.location_searching_rounded,
  NodeAction.telemetry => Icons.monitor_heart_outlined,
  NodeAction.environment => Icons.thermostat_rounded,
  NodeAction.identity => Icons.badge_outlined,
  NodeAction.sensorLogin => Icons.login_rounded,
  NodeAction.favorite =>
    enabled ? Icons.star_outline_rounded : Icons.star_rounded,
  NodeAction.ignore =>
    enabled ? Icons.block_rounded : Icons.remove_circle_outline_rounded,
};
