// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../radio/firmware_catalog.dart';
import 'macos_glass.dart';
import 'style.dart';

enum FirmwareFacet {
  manufacturer,
  chip,
  protocol;

  String label(BuildContext context) => switch (this) {
    manufacturer => tr(context, 'Производитель', 'Manufacturer'),
    chip => tr(context, 'Чип', 'Chip'),
    protocol => tr(context, 'Протокол', 'Protocol'),
  };

  List<String> options(FirmwareCatalog catalog) {
    final values = switch (this) {
      manufacturer => catalog.boards.map((board) => board.manufacturer),
      chip => catalog.boards.expand(
        (board) => board.chips.map((chip) => chip.label),
      ),
      protocol => catalog.boards.expand((board) => board.protocols),
    };
    return values.toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}

typedef FirmwareSelection = Map<FirmwareFacet, Set<String>>;
typedef FirmwareFilterToggle = void Function(FirmwareFacet, String);

bool matchesFirmwareSelection(FirmwareBoard board, FirmwareSelection filters) {
  bool includes(FirmwareFacet facet, String value) =>
      filters[facet]?.contains(value) ?? true;
  return includes(FirmwareFacet.manufacturer, board.manufacturer) &&
      board.targets.any(
        (target) =>
            includes(FirmwareFacet.chip, target.chip.label) &&
            includes(FirmwareFacet.protocol, target.project),
      );
}

class FirmwareFilterPanel extends StatefulWidget {
  const FirmwareFilterPanel({
    super.key,
    required this.options,
    required this.selection,
    required this.onToggle,
    required this.onClose,
  });

  final Map<FirmwareFacet, List<String>> options;
  final FirmwareSelection selection;
  final FirmwareFilterToggle onToggle;
  final VoidCallback onClose;

  @override
  State<FirmwareFilterPanel> createState() => _FirmwareFilterPanelState();
}

class _FirmwareFilterPanelState extends State<FirmwareFilterPanel> {
  FirmwareFacet _facet = FirmwareFacet.manufacturer;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final facet in FirmwareFacet.values)
                      ChoiceChip(
                        label: Text(facet.label(context)),
                        showCheckmark: false,
                        selected: facet == _facet,
                        onSelected: (_) => setState(() => _facet = facet),
                      ),
                  ],
                ),
              ),
              MeshIconButton(
                label: tr(context, 'Свернуть фильтры', 'Close filters'),
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final value in widget.options[_facet]!)
                FilterChip(
                  label: Text(value),
                  selected: widget.selection[_facet]?.contains(value) ?? false,
                  onSelected: (_) => widget.onToggle(_facet, value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class FirmwareFilterTag extends StatelessWidget {
  const FirmwareFilterTag({
    super.key,
    required this.value,
    required this.onRemove,
  });

  final String value;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final radius = BorderRadius.circular(24);
    final content = InkWell(
      borderRadius: radius,
      hoverColor: Colors.transparent,
      mouseCursor: SystemMouseCursors.click,
      onTap: onRemove,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 8, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(value)),
            const SizedBox(width: 6),
            Icon(Icons.close_rounded, size: 16, color: style.text),
          ],
        ),
      ),
    );
    return Semantics(
      label: tr(
        context,
        'Удалить фильтр «$value»',
        'Remove filter: $value',
      ),
      button: true,
      onTap: onRemove,
      excludeSemantics: true,
      child: MacGlass.enabled(context)
          ? GlassSurface(radius: 24, child: content)
          : Material(
              color: style.searchField,
              borderRadius: radius,
              child: content,
            ),
    );
  }
}

class MacFirmwareFilterPanel extends StatefulWidget {
  const MacFirmwareFilterPanel({
    super.key,
    required this.options,
    required this.selection,
    required this.dark,
    required this.onToggle,
    required this.onClose,
  });

  final Map<FirmwareFacet, List<String>> options;
  final FirmwareSelection selection;
  final bool dark;
  final FirmwareFilterToggle onToggle;
  final VoidCallback onClose;

  @override
  State<MacFirmwareFilterPanel> createState() => _MacFirmwareFilterPanelState();
}

class _MacFirmwareFilterPanelState extends State<MacFirmwareFilterPanel> {
  MethodChannel? _channel;

  Map<String, Object> get _state => {
    'dark': widget.dark,
    'selection': {
      for (final entry in widget.selection.entries)
        entry.key.name: entry.value.toList(),
    },
  };

  @override
  void didUpdateWidget(covariant MacFirmwareFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection ||
        oldWidget.dark != widget.dark) {
      _channel?.invokeMethod<void>('update', _state);
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _connect(int id) {
    if (!mounted) return;
    _channel?.setMethodCallHandler(null);
    final channel = MethodChannel('meshgrame/firmware_filters/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'close') {
        widget.onClose();
        return;
      }
      if (call.method != 'toggle') return;
      final args = Map<String, String>.from(call.arguments as Map);
      final facet = FirmwareFacet.values.byName(args['facet']!);
      final value = args['value']!;
      if (widget.options[facet]!.contains(value)) widget.onToggle(facet, value);
    });
    channel.invokeMethod<void>('update', _state);
  }

  @override
  Widget build(BuildContext context) => AppKitView(
    viewType: 'meshgrame/firmware_filters',
    creationParamsCodec: const StandardMessageCodec(),
    creationParams: {
      'closeLabel': tr(context, 'Свернуть фильтры', 'Close filters'),
      'facets': [
        for (final facet in FirmwareFacet.values)
          {
            'id': facet.name,
            'title': facet.label(context),
            'options': widget.options[facet],
          },
      ],
      ..._state,
    },
    onPlatformViewCreated: _connect,
  );
}
