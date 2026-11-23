// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/mesh/network.dart';
import 'package:meshgrame/ui/radio_setting_visibility.dart';

void main() {
  test('Meshtastic presets and smart position reveal their own parameters', () {
    bool lora(String id, String usePreset) => radioSettingVisible(
      'meshtastic',
      RadioFieldSection.lora,
      id,
      {'1': usePreset},
    );
    expect(lora('2', 'true'), isTrue);
    expect(lora('3', 'true'), isFalse);
    expect(lora('2', 'false'), isFalse);
    expect(lora('3', 'false'), isTrue);
    expect(lora('5', 'true'), isTrue); // Recent firmware supports CR overrides.
    expect(
      radioSettingVisible('meshtastic', RadioFieldSection.lora, '5', {
        '1': 'true',
      }, presetRateOverride: false),
      isFalse,
    );

    final gps = {'2': 'false', '13': '2'};
    bool position(String id) =>
        radioSettingVisible('meshtastic', RadioFieldSection.position, id, gps);
    expect(position('5'), isFalse);
    expect(position('10'), isFalse);
    gps['2'] = 'true';
    expect(position('10'), isTrue);
    gps['13'] = '1';
    expect(position('5'), isTrue);
  });

  test(
    'Meshtastic static IP and MQTT map publication respect nested controls',
    () {
      bool ip(Map<String, String> values) => radioSettingVisible(
        'meshtastic',
        RadioFieldSection.connectivity,
        '8.1',
        values,
      );
      expect(ip({'1': 'false', '6': 'true', '7': '1'}), isTrue);
      expect(ip({'1': 'true', '7': '0'}), isFalse);
      expect(ip({'1': 'false', '6': 'false', '7': '1'}), isFalse);
      expect(ip({'7': '1'}), isTrue); // A radio can omit an unsupported gate.

      bool publication(Map<String, String> values) => radioSettingVisible(
        'meshtastic',
        RadioFieldSection.mqtt,
        '11.1',
        values,
      );
      expect(publication({'1': 'false', '10': 'true'}), isFalse);
      expect(publication({'1': 'true', '10': 'false'}), isFalse);
      expect(publication({'1': 'true', '10': 'true'}), isTrue);
    },
  );

  test('MeshCore manual contact mode enables optional type filters', () {
    bool contact(String id, Map<String, String> values) =>
        radioSettingVisible('meshcore', RadioFieldSection.contacts, id, values);
    expect(contact('sensor', {'manual': 'false'}), isFalse);
    expect(contact('sensor', {'manual': 'true'}), isTrue);
    expect(contact('maxHops', {'manual': 'true', 'sensor': 'false'}), isFalse);
    expect(contact('maxHops', {'manual': 'true', 'sensor': 'true'}), isTrue);
    expect(contact('maxHops', {'manual': 'false', 'sensor': 'false'}), isTrue);
    expect(
      radioSettingVisible(
        'meshcore',
        RadioFieldSection.position,
        'custom:gps_interval',
        {'custom:gps': 'false'},
      ),
      isFalse,
    );
  });
}
