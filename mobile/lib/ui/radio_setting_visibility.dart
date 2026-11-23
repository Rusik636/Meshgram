// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import '../mesh/network.dart';

/// All clauses must hold, and any setting within a clause can satisfy it.
/// The firmware may omit a controlling field, in which case its dependent
/// settings remain accessible.
List<Map<String, String>> radioSettingConditions(
  String network,
  RadioFieldSection section,
  String id, {
  bool presetRateOverride = true,
}) => switch ((network, section, id)) {
  ('meshtastic', RadioFieldSection.lora, '2') => const [
    {'1': 'true'},
  ],
  ('meshtastic', RadioFieldSection.lora, '3' || '4') => const [
    {'1': 'false'},
  ],
  ('meshtastic', RadioFieldSection.lora, '5') when !presetRateOverride =>
    const [
      {'1': 'false'},
    ],
  ('meshtastic', RadioFieldSection.lora, '10') => const [
    {'9': 'true'},
  ],
  (
    'meshtastic',
    RadioFieldSection.position,
    '5' || '6' || '8' || '9' || '12',
  ) =>
    const [
      {'4': 'true', '13': '1'},
    ],
  ('meshtastic', RadioFieldSection.position, '10' || '11') => const [
    {'2': 'true'},
  ],
  ('meshtastic', RadioFieldSection.connectivity, '3' || '4') => const [
    {'1': 'true'},
  ],
  (
    'meshtastic',
    RadioFieldSection.connectivity,
    '5' || '7' || '9' || '10' || '11',
  ) =>
    const [
      {'1': 'true', '6': 'true'},
    ],
  ('meshtastic', RadioFieldSection.connectivity, final id)
      when id.startsWith('8.') =>
    const [
      {'1': 'true', '6': 'true'},
      {'7': '1'},
    ],
  ('meshtastic', RadioFieldSection.bluetooth, '2') => const [
    {'1': 'true'},
  ],
  ('meshtastic', RadioFieldSection.bluetooth, '3') => const [
    {'1': 'true'},
    {'2': '1'},
  ],
  ('meshtastic', RadioFieldSection.sensors, '1') => const [
    {'14': 'true'},
  ],
  ('meshtastic', RadioFieldSection.sensors, '2' || '4' || '5') => const [
    {'3': 'true'},
  ],
  ('meshtastic', RadioFieldSection.sensors, '7' || '15') => const [
    {'6': 'true'},
  ],
  ('meshtastic', RadioFieldSection.sensors, '9' || '10') => const [
    {'8': 'true'},
  ],
  ('meshtastic', RadioFieldSection.sensors, '12' || '13') => const [
    {'11': 'true'},
  ],
  ('meshtastic', RadioFieldSection.mqtt, final id) when id.startsWith('11.') =>
    const [
      {'1': 'true'},
      {'10': 'true'},
    ],
  (
    'meshtastic',
    RadioFieldSection.mqtt ||
        RadioFieldSection.notifications ||
        RadioFieldSection.serial ||
        RadioFieldSection.storeForward ||
        RadioFieldSection.rangeTest ||
        RadioFieldSection.audio ||
        RadioFieldSection.remoteHardware ||
        RadioFieldSection.neighborInfo ||
        RadioFieldSection.ambientLighting ||
        RadioFieldSection.detectionSensor ||
        RadioFieldSection.paxCounter,
    final id,
  )
      when id != '1' =>
    const [
      {'1': 'true'},
    ],
  ('meshtastic', RadioFieldSection.quickMessages, final id) when id != '9' =>
    const [
      {'9': 'true'},
    ],
  ('meshtastic', RadioFieldSection.deviceUi, '6') => const [
    {'4': 'true', '5': 'true'},
  ],
  ('meshtastic', RadioFieldSection.deviceUi, '10') => const [
    {'8': 'true'},
  ],
  ('meshcore', RadioFieldSection.connectivity, final id)
      when id.startsWith('wifi.') && id != 'wifi.enabled' =>
    const [
      {'wifi.enabled': 'true'},
    ],
  ('meshcore', RadioFieldSection.position, 'custom:gps_interval') => const [
    {'custom:gps': 'true'},
  ],
  (
    'meshcore',
    RadioFieldSection.contacts,
    'chat' || 'repeater' || 'room' || 'sensor',
  ) =>
    const [
      {'manual': 'true'},
    ],
  ('meshcore', RadioFieldSection.contacts, 'maxHops' || 'overwrite') => const [
    {
      'manual': 'false',
      'chat': 'true',
      'repeater': 'true',
      'room': 'true',
      'sensor': 'true',
    },
  ],
  _ => const [],
};

bool radioSettingVisible(
  String network,
  RadioFieldSection section,
  String id,
  Map<String, String> values, {
  bool presetRateOverride = true,
}) =>
    radioSettingConditions(
      network,
      section,
      id,
      presetRateOverride: presetRateOverride,
    ).every((condition) {
      final available = condition.entries.where(
        (item) => values.containsKey(item.key),
      );
      return available.isEmpty ||
          available.any((item) => values[item.key] == item.value);
    });
