// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../radio/firmware_catalog.dart';
import 'desktop_interaction.dart';
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
  });

  final Map<FirmwareFacet, List<String>> options;
  final FirmwareSelection selection;
  final FirmwareFilterToggle onToggle;

  @override
  State<FirmwareFilterPanel> createState() => _FirmwareFilterPanelState();
}

class _FirmwareFilterPanelState extends State<FirmwareFilterPanel> {
  FirmwareFacet _facet = FirmwareFacet.manufacturer;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return Material(
      borderRadius: BorderRadius.circular(16),
      color: style.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
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
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 146),
              child: SingleChildScrollView(
                key: ValueKey(_facet),
                primary: false,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final value in widget.options[_facet]!)
                      FilterChip(
                        label: Text(value),
                        selected:
                            widget.selection[_facet]?.contains(value) ?? false,
                        onSelected: (_) => widget.onToggle(_facet, value),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FirmwareFilterTag extends StatefulWidget {
  const FirmwareFilterTag({
    super.key,
    required this.value,
    required this.onRemove,
  });

  final String value;
  final VoidCallback onRemove;

  @override
  State<FirmwareFilterTag> createState() => _FirmwareFilterTagState();
}

class _FirmwareFilterTagState extends State<FirmwareFilterTag> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final radius = BorderRadius.circular(24);
    final showRemove = _hovered || _focused || !meshDesktop(context);
    final content = InkWell(
      borderRadius: radius,
      hoverColor: Colors.transparent,
      mouseCursor: SystemMouseCursors.click,
      onHover: (value) => setState(() => _hovered = value),
      onFocusChange: (value) => setState(() => _focused = value),
      onTap: widget.onRemove,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 8, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(widget.value)),
            const SizedBox(width: 6),
            Opacity(
              opacity: showRemove ? 1 : 0,
              child: Icon(Icons.close_rounded, size: 16, color: style.text),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      label: tr(
        context,
        'Удалить фильтр «${widget.value}»',
        'Remove filter: ${widget.value}',
      ),
      button: true,
      onTap: widget.onRemove,
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
  });

  final Map<FirmwareFacet, List<String>> options;
  final FirmwareSelection selection;
  final bool dark;
  final FirmwareFilterToggle onToggle;

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
      if (call.method != 'toggle' || !mounted) return;
      final args = Map<String, String>.from(call.arguments as Map);
      final facet = FirmwareFacet.values.byName(args['facet']!);
      final value = args['value']!;
      if (widget.options[facet]!.contains(value)) widget.onToggle(facet, value);
    });
    channel.invokeMethod<void>('update', _state);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 224,
    child: AppKitView(
      key: ValueKey(MacGlass.enabled(context)),
      viewType: 'meshgrame/firmware_filters',
      creationParamsCodec: const StandardMessageCodec(),
      creationParams: {
        'glass': MacGlass.enabled(context),
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
    ),
  );
}
