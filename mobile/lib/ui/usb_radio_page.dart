// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';

import '../mesh/controller.dart';
import '../mesh/network.dart';
import 'style.dart';

class UsbRadioPage extends StatefulWidget {
  const UsbRadioPage({super.key, required this.controller});

  final MeshController controller;

  @override
  State<UsbRadioPage> createState() => _UsbRadioPageState();
}

class _UsbRadioPageState extends State<UsbRadioPage> {
  List<UsbPort> _ports = const [];
  UsbPort? _selected;
  String? _protocol, _error;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    try {
      final ports = widget.controller.usbTransport!.ports();
      setState(() {
        _ports = ports;
        _selected = ports
            .where((port) => port.path == _selected?.path)
            .firstOrNull;
        _error = null;
      });
    } on Object catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _connect() async {
    final port = _selected;
    final protocol = _protocol;
    if (port == null || protocol == null || _connecting) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    final radio = usbRadio(protocol, port);
    try {
      await widget.controller.connect(radio);
      if (!mounted) return;
      if (widget.controller.isConnectedTo(radio)) {
        await Navigator.of(context).maybePop();
        return;
      }
      setState(
        () => _error = tr(
          context,
          'Рация не ответила. Проверьте порт и выбранный тип прошивки.',
          'The radio did not respond. Check the port and firmware type.',
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          PageHeading(
            tr(context, 'Подключение по USB', 'Connect over USB'),
            leading: GlassButton(
              icon: Icons.arrow_back_rounded,
              label: tr(context, 'Назад', 'Back'),
              onTap: () => Navigator.of(context).maybePop(),
            ),
            trailing: GlassButton(
              icon: Icons.refresh_rounded,
              label: tr(context, 'Обновить порты', 'Refresh ports'),
              onTap: _connecting ? null : _refresh,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _protocol,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Прошивка рации', 'Radio firmware'),
                  ),
                  items: [
                    for (final id in widget.controller.usbProtocols.keys)
                      DropdownMenuItem(
                        value: id,
                        child: Text(widget.controller.adapters[id]!.label),
                      ),
                  ],
                  onChanged: _connecting
                      ? null
                      : (value) => setState(() => _protocol = value),
                ),
                const SizedBox(height: 16),
                if (_ports.isEmpty)
                  Text(
                    tr(
                      context,
                      'Подключите рацию кабелем USB и обновите список.',
                      'Plug in a radio with a USB data cable and refresh the list.',
                    ),
                  ),
                for (final port in _ports)
                  ListTile(
                    selected: _selected == port,
                    leading: Icon(
                      _selected == port
                          ? Icons.radio_button_checked
                          : Icons.usb_rounded,
                    ),
                    title: Text(port.name),
                    subtitle: port.name == port.path ? null : Text(port.path),
                    onTap: _connecting
                        ? null
                        : () => setState(() => _selected = port),
                  ),
                if (_error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error,
                      style: TextStyle(color: MeshStyle.of(context).error),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: GlassActionButton(
              label: _connecting
                  ? tr(context, 'Подключение…', 'Connecting…')
                  : tr(context, 'Подключить', 'Connect'),
              onTap: _connecting || _protocol == null || _selected == null
                  ? null
                  : _connect,
            ),
          ),
        ],
      ),
    ),
  );
}
