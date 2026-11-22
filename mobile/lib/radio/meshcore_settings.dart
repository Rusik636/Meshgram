part of 'meshcore.dart';

class _CoreCliSetting {
  const _CoreCliSetting(
    this.section,
    this.key,
    this.title,
    this.russian, {
    this.kind = RadioFieldKind.text,
    this.toggleOn = 'on',
    this.toggleOff = 'off',
    this.min,
    this.max,
    this.editable = true,
    this.secret = false,
  });

  final RadioFieldSection section;
  final String key, title, russian, toggleOn, toggleOff;
  final RadioFieldKind kind;
  final num? min, max;
  final bool editable, secret;

  String toCommand(String value) {
    final String encoded;
    if (kind == RadioFieldKind.toggle) {
      encoded = switch (value) {
        'true' => toggleOn,
        'false' => toggleOff,
        _ => throw const FormatException('Expected on or off'),
      };
    } else if (min != null && max != null) {
      final number = kind == RadioFieldKind.integer
          ? int.tryParse(value)
          : double.tryParse(value.replaceAll(',', '.'));
      if (number == null ||
          !number.isFinite ||
          number < min! ||
          number > max!) {
        throw const FormatException('Invalid MeshCore setting value');
      }
      encoded = '$number';
    } else {
      final bytes = utf8.encode(value);
      final limit = key == 'wifi.ssid' ? 32 : 63;
      if (bytes.length > limit ||
          bytes.any((byte) => byte < 32 || byte == 127)) {
        throw const FormatException('Invalid MeshCore setting text');
      }
      encoded = value;
    }
    return 'set $key $encoded';
  }

  RadioField? field(String value) {
    final normalized = value.toLowerCase();
    if (kind == RadioFieldKind.toggle &&
        normalized != toggleOn &&
        normalized != toggleOff) {
      return null;
    }
    return RadioField(
      key,
      title,
      russian,
      kind == RadioFieldKind.toggle ? '${normalized == toggleOn}' : value,
      kind: kind,
      section: section,
      editable: editable,
      secret: secret,
    );
  }
}

const _coreCliSettings = [
  _CoreCliSetting(
    RadioFieldSection.connectivity,
    'wifi.enabled',
    'Enable Wi-Fi',
    'Включить Wi-Fi',
    kind: RadioFieldKind.toggle,
    toggleOn: '1',
    toggleOff: '0',
  ),
  _CoreCliSetting(
    RadioFieldSection.connectivity,
    'wifi.ssid',
    'Wi-Fi network',
    'Имя сети Wi-Fi',
  ),
  _CoreCliSetting(
    RadioFieldSection.connectivity,
    'wifi.pwd',
    'Wi-Fi password',
    'Пароль Wi-Fi',
    secret: true,
  ),
  _CoreCliSetting(
    RadioFieldSection.connectivity,
    'wifi.status',
    'Connection status',
    'Состояние Wi-Fi',
    editable: false,
  ),
  _CoreCliSetting(
    RadioFieldSection.connectivity,
    'wifi.ip',
    'IP address',
    'IP-адрес',
    editable: false,
  ),
  _CoreCliSetting(
    RadioFieldSection.notifications,
    'buzzer',
    'Buzzer',
    'Зуммер',
    kind: RadioFieldKind.toggle,
  ),
  _CoreCliSetting(
    RadioFieldSection.position,
    'tz.offset',
    'UTC offset',
    'Смещение от UTC',
    kind: RadioFieldKind.integer,
    min: -12,
    max: 14,
  ),
  _CoreCliSetting(
    RadioFieldSection.routing,
    'cad',
    'Channel activity detection',
    'Детектор активности канала',
    kind: RadioFieldKind.toggle,
  ),
  _CoreCliSetting(
    RadioFieldSection.routing,
    'int.thresh',
    'Interference threshold',
    'Порог помех',
    kind: RadioFieldKind.integer,
    min: 0,
    max: 255,
  ),
  _CoreCliSetting(
    RadioFieldSection.routing,
    'txdelay',
    'Flood transmit delay',
    'Задержка широковещательной передачи',
    kind: RadioFieldKind.decimal,
    min: 0,
    max: 2,
  ),
  _CoreCliSetting(
    RadioFieldSection.routing,
    'direct.txdelay',
    'Direct transmit delay',
    'Задержка прямой передачи',
    kind: RadioFieldKind.decimal,
    min: 0,
    max: 2,
  ),
  _CoreCliSetting(
    RadioFieldSection.routing,
    'agc.reset.interval',
    'AGC reset interval',
    'Интервал сброса АРУ',
    kind: RadioFieldKind.integer,
    min: 0,
    max: 1020,
  ),
  _CoreCliSetting(
    RadioFieldSection.routing,
    'radio.rxgain',
    'Boost receiver gain',
    'Усиление приёмника',
    kind: RadioFieldKind.toggle,
  ),
];

const _coreContactFlags = [
  ('overwrite', 'Replace oldest non-favorite', 'Заменять старые контакты', 1),
  ('chat', 'Automatically add companion radios', 'Автодобавление раций', 2),
  (
    'repeater',
    'Automatically add repeaters',
    'Автодобавление ретрансляторов',
    4,
  ),
  (
    'room',
    'Automatically add room servers',
    'Автодобавление серверов комнат',
    8,
  ),
  ('sensor', 'Automatically add sensors', 'Автодобавление датчиков', 16),
];

extension on _CoreSession {
  Future<Uint8List?> _optionalCommand(List<int> request, int response) async {
    try {
      final frame = await _command(request, {response}, seconds: 2);
      return frame.first == response ? frame : null;
    } on TimeoutException {
      return null;
    }
  }

  Future<void> _requireOk(List<int> command) async {
    if ((await _command(command, {0})).first != 0) {
      throw StateError('MeshCore rejected the setting');
    }
  }

  Future<String?> _readCli(String key) async {
    final frame = await _optionalCommand([66, ...utf8.encode('get $key')], 29);
    if (frame == null) return null;
    final reply = utf8.decode(frame.sublist(1), allowMalformed: true);
    return reply.startsWith('> ') ? reply.substring(2) : null;
  }

  Future<void> _discoverSettings() async {
    if (_catalogProbed || _protocol == 0) return;
    _catalogProbed = true;
    if (_protocol >= 5) {
      _hasCustomSettings = (await _customSettings()).isNotEmpty;
    }
    if (_protocol >= 9) {
      _autoAddSupported = (await _optionalCommand([59], 25))?.length == 3;
    }
    if (_protocol >= 11) {
      _scopeSupported = await _optionalCommand([64], 28) != null;
    }
    if (_protocol < 14) return;
    for (final setting in _coreCliSettings) {
      final value = await _readCli(setting.key);
      if (value != null && setting.field(value) != null) {
        _cliFields.add(setting.key);
      }
    }
  }

  Future<List<RadioField>> _readCliSettings(RadioFieldSection section) async {
    final fields = <RadioField>[];
    for (final setting in _coreCliSettings.where(
      (item) => item.section == section && _cliFields.contains(item.key),
    )) {
      final value = await _readCli(setting.key);
      if (value == null) continue;
      final field = setting.field(value == '(not set)' ? '' : value);
      if (field != null) fields.add(field);
    }
    return fields;
  }

  List<String> _prepareCliWrites(
    RadioFieldSection section,
    Map<String, String> values,
  ) => [
    for (final setting in _coreCliSettings)
      if (setting.section == section && values[setting.key] != null)
        setting.toCommand(values[setting.key]!),
  ];

  Future<bool> _writeCliSettings(List<String> commands) async {
    var needsRestart = false;
    for (final command in commands) {
      final frame = await _command([66, ...utf8.encode(command)], {29});
      if (frame.first != 29) throw StateError('MeshCore rejected the setting');
      final reply = MeshCoreFrames.text(frame.sublist(1)).toLowerCase();
      if (!reply.startsWith('ok') && !reply.startsWith('> ')) {
        throw StateError('MeshCore rejected the setting');
      }
      needsRestart |=
          reply.endsWith('reboot to apply)') || reply.endsWith('then reboot)');
    }
    return needsRestart;
  }

  Future<List<RadioField>> _readContactSettings() async {
    final self = await _selfInfo();
    if (self.length < 48 || self.first != 5) return [];
    final frame = _autoAddSupported ? await _optionalCommand([59], 25) : null;
    return [
      RadioField(
        'manual',
        'Manually add contacts',
        'Добавлять контакты вручную',
        '${self[47] != 0}',
        kind: RadioFieldKind.toggle,
        section: RadioFieldSection.contacts,
      ),
      if (frame != null && frame.length >= 3) ...[
        for (final (id, en, ru, mask) in _coreContactFlags)
          RadioField(
            id,
            en,
            ru,
            '${(frame[1] & mask) != 0}',
            kind: RadioFieldKind.toggle,
            section: RadioFieldSection.contacts,
          ),
        RadioField(
          'maxHops',
          'Automatic import hop limit',
          'Лимит переходов для автодобавления',
          '${frame[2]}',
          kind: RadioFieldKind.integer,
          section: RadioFieldSection.contacts,
        ),
      ],
    ];
  }

  Future<void> _writeContactSettings(Map<String, String> changes) async {
    final manual = switch (changes['manual']) {
      'true' => 1,
      'false' => 0,
      null => null,
      _ => throw const FormatException('Expected on or off'),
    };
    if (changes.keys.any((key) => key != 'manual')) {
      final frame = await _optionalCommand([59], 25);
      if (frame == null || frame.length < 3) {
        throw StateError('MeshCore contact settings unavailable');
      }
      var flags = frame[1];
      for (final (id, _, _, mask) in _coreContactFlags) {
        if (changes[id] case final value?) {
          flags = switch (value) {
            'true' => flags | mask,
            'false' => flags & ~mask,
            _ => throw const FormatException('Expected on or off'),
          };
        }
      }
      final hops = changes['maxHops'] == null
          ? frame[2]
          : _bounded(changes['maxHops']!, 0, 64);
      await _requireOk([58, flags, hops]);
    }
    if (manual != null) await _requireOk([38, manual]);
  }

  Future<Map<String, String>> _customSettings() async {
    final frame = await _optionalCommand([40], 21);
    if (frame == null) return {};
    final fields = <String, String>{};
    for (final item in MeshCoreFrames.text(frame.sublist(1)).split(',')) {
      final separator = item.indexOf(':');
      if (separator < 1) continue;
      final key = item.substring(0, separator);
      if (!RegExp(r'^[a-zA-Z0-9_.-]{1,32}$').hasMatch(key)) continue;
      fields[key] = item.substring(separator + 1);
    }
    return fields;
  }

  Future<List<RadioField>> _readCustomSettings(
    RadioFieldSection section,
  ) async {
    if (!_hasCustomSettings) return [];
    return [
      for (final entry in (await _customSettings()).entries)
        if (entry.key.startsWith('gps') ==
            (section == RadioFieldSection.position))
          RadioField(
            'custom:${entry.key}',
            switch (entry.key) {
              'gps' => 'GPS',
              'gps_interval' => 'GPS interval',
              _ => entry.key,
            },
            switch (entry.key) {
              'gps' => 'GPS',
              'gps_interval' => 'Интервал GPS',
              _ => entry.key,
            },
            entry.key == 'gps' ? '${entry.value != '0'}' : entry.value,
            section: section,
            kind: entry.key == 'gps'
                ? RadioFieldKind.toggle
                : entry.key == 'gps_interval'
                ? RadioFieldKind.integer
                : RadioFieldKind.text,
            units: entry.key == 'gps_interval' ? 's' : null,
          ),
    ];
  }

  List<List<int>> _prepareCustomWrites(Map<String, String> values) {
    final commands = <List<int>>[];
    for (final entry in values.entries) {
      if (!entry.key.startsWith('custom:')) continue;
      final key = entry.key.substring(7);
      final value = switch (key) {
        'gps' => switch (entry.value) {
          'true' => '1',
          'false' => '0',
          _ => throw const FormatException('GPS toggle'),
        },
        'gps_interval' => '${_bounded(entry.value, 0, 86400)}',
        _ => entry.value,
      };
      final bytes = utf8.encode('$key:$value');
      if (bytes.length > 120 || bytes.contains(0) || value.contains(',')) {
        throw const FormatException('Invalid MeshCore device setting');
      }
      commands.add([41, ...bytes]);
    }
    return commands;
  }

  Future<List<RadioField>> _readScope() async {
    final frame = await _optionalCommand([64], 28);
    if (frame == null) return [];
    final active = frame.length >= 48;
    return [
      RadioField(
        'scopeName',
        'Default scope name',
        'Область маршрутизации',
        active ? MeshCoreFrames.text(frame.sublist(1, 32)) : '',
        section: RadioFieldSection.routing,
      ),
      RadioField(
        'scopeKey',
        'Scope key',
        'Ключ области',
        active ? MeshCoreFrames.hex(frame.sublist(32, 48)) : '',
        section: RadioFieldSection.routing,
        secret: true,
      ),
    ];
  }

  List<int> _scopeCommand(String name, String key) {
    if (name.isEmpty && key.isEmpty) return [63];
    final label = utf8.encode(name);
    if (label.isEmpty ||
        label.length > 30 ||
        label.contains(0) ||
        !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(key)) {
      throw const FormatException('Enter a scope name and a 16-byte hex key');
    }
    return [
      63,
      ...label,
      ...List.filled(31 - label.length, 0),
      for (var i = 0; i < key.length; i += 2)
        int.parse(key.substring(i, i + 2), radix: 16),
    ];
  }
}
