// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'network.dart';

typedef RadioSettingName = ({String id, String title, String russian});

/// Settings known to the adapter for a section it exposes. Listing names must
/// never send commands to the radio or read the values of private settings.
abstract interface class RadioSettingsIndex {
  Iterable<RadioSettingName> settingNames(RadioFieldSection section);
}
