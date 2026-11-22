// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

part of 'meshtastic.dart';

enum _TasticFormat {
  integer,
  signed,
  wide,
  toggle,
  text,
  decimal,
  choice,
  bytes,
  keys,
  numbers,
  fixed,
  ipv4,
  gpioPins,
  beaconTargets,
}

class _TasticSection {
  const _TasticSection(
    this.type,
    this.field,
    this.items, {
    this.module = false,
    this.since,
  });
  final int type, field;
  final List<_TasticSetting> items;
  final bool module;
  final String? since;
}

class _TasticSetting {
  const _TasticSetting(
    this.tag,
    this.en,
    this.ru, {
    this.format = _TasticFormat.integer,
    this.units,
    this.choices = const {},
    this.parent = const [],
    this.since,
    this.before,
    this.secret = false,
    this.maxBytes,
  });

  final int tag;
  final String en, ru;
  final _TasticFormat format;
  final Map<int, String> choices;
  final List<int> parent;
  final String? units, since, before;
  final bool secret;
  final int? maxBytes;
  String get id => [...parent, tag].join('.');
}

// Wire IDs and firmware annotations follow the upstream config and module schemas.
const _tasticSections = <RadioFieldSection, _TasticSection>{
  RadioFieldSection.position: _TasticSection(1, 2, [
    _TasticSetting(
      1,
      "Broadcast Interval",
      "Интервал отправки позиции",
      units: "s",
    ),
    _TasticSetting(
      2,
      "Smart Position",
      "Отправка при перемещении",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      3,
      "Fixed Position",
      "Фиксированная позиция",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      4,
      "GPS enabled",
      "Включить GPS",
      format: _TasticFormat.toggle,
      before: "2.2.21",
    ),
    _TasticSetting(5, "Update Interval", "Интервал обновления GPS"),
    _TasticSetting(
      6,
      'GPS attempt time',
      'Время поиска GPS',
      units: 's',
      before: '2.2.18',
    ),
    _TasticSetting(7, "Position Flags", "Маска полей позиции"),
    _TasticSetting(8, "GPS Receive GPIO", "GPIO RX"),
    _TasticSetting(9, "GPS Transmit GPIO", "GPIO TX"),
    _TasticSetting(
      10,
      "Minimum Distance",
      "Минимальное перемещение",
      units: "m",
    ),
    _TasticSetting(
      11,
      "Minimum Interval",
      "Минимальный интервал отправки",
      units: "s",
    ),
    _TasticSetting(12, "GPS Enable GPIO", "GPIO питания GPS"),
    _TasticSetting(
      13,
      "GPS Mode",
      "Режим GPS",
      format: _TasticFormat.choice,
      choices: {0: "Disabled", 1: "Enabled", 2: "Not Present"},
      since: "2.2.21",
    ),
  ]),
  RadioFieldSection.routing: _TasticSection(0, 1, [
    _TasticSetting(
      2,
      'Serial Console',
      'Последовательный порт',
      format: _TasticFormat.toggle,
      before: '2.5.0',
    ),
    _TasticSetting(4, "Button GPIO", "GPIO кнопки"),
    _TasticSetting(5, "Buzzer GPIO", "GPIO зуммера"),
    _TasticSetting(
      6,
      "Rebroadcast Mode",
      "Режим ретрансляции",
      format: _TasticFormat.choice,
      choices: {
        0: "All",
        1: "All Skip Decoding",
        2: "Local Only",
        3: "Known Only",
        4: "None",
        5: "Core Portnums Only",
      },
    ),
    _TasticSetting(
      7,
      "Node Info Broadcast Interval",
      "Интервал объявления узла",
      units: "s",
    ),
    _TasticSetting(
      8,
      "Double Tap as Button",
      "Двойное нажатие как кнопка",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      9,
      'Managed Device',
      'Управляемый узел',
      format: _TasticFormat.toggle,
      before: '2.5.0',
    ),
    _TasticSetting(
      10,
      "Disable Triple Click",
      "Отключить тройное нажатие",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      11,
      "POSIX time zone",
      "Часовой пояс POSIX",
      format: _TasticFormat.text,
      maxBytes: 64,
    ),
    _TasticSetting(
      12,
      "Disable status LED",
      "Отключить мигание индикатора",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      13,
      "Buzzer mode",
      "Режим зуммера",
      format: _TasticFormat.choice,
      choices: {
        0: "All enabled",
        1: "Disabled",
        2: "Notifications only",
        3: "System only",
        4: "Direct msg only",
      },
      since: "2.7.0",
    ),
  ]),
  RadioFieldSection.power: _TasticSection(2, 3, [
    _TasticSetting(
      1,
      "Power Saving",
      "Энергосбережение",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      2,
      "Shutdown on Power Loss",
      "Автоотключение от батареи",
      units: "s",
    ),
    _TasticSetting(
      3,
      "ADC Override",
      "Множитель АЦП",
      format: _TasticFormat.decimal,
    ),
    _TasticSetting(
      4,
      "Wait for Bluetooth Duration",
      "Ожидание Bluetooth",
      units: "s",
    ),
    _TasticSetting(6, "Super Deep Sleep Duration", "Глубокий сон", units: "s"),
    _TasticSetting(7, "Ls secs", "Лёгкий сон", units: "s"),
    _TasticSetting(
      8,
      "Minimum Wake Time",
      "Минимальное время пробуждения",
      units: "s",
    ),
    _TasticSetting(
      9,
      "Battery INA_2XX I2C Address",
      "Адрес датчика питания INA",
    ),
    _TasticSetting(
      32,
      "Powermon enables",
      "Маска мониторинга питания",
      format: _TasticFormat.wide,
    ),
  ]),
  RadioFieldSection.connectivity: _TasticSection(3, 4, [
    _TasticSetting(
      1,
      "WiFi Enabled",
      "Включить Wi-Fi",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      3,
      "SSID",
      "Имя сети Wi-Fi",
      format: _TasticFormat.text,
      maxBytes: 32,
    ),
    _TasticSetting(
      4,
      "Password",
      "Пароль Wi-Fi",
      format: _TasticFormat.text,
      secret: true,
      maxBytes: 64,
    ),
    _TasticSetting(
      5,
      "NTP Server",
      "Сервер NTP",
      format: _TasticFormat.text,
      maxBytes: 32,
    ),
    _TasticSetting(
      6,
      "Ethernet Enabled",
      "Включить Ethernet",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      7,
      "Address Mode",
      "Получение IP-адреса",
      format: _TasticFormat.choice,
      choices: {0: "DHCP", 1: "Static"},
    ),
    _TasticSetting(
      1,
      "IP",
      "IP-адрес",
      format: _TasticFormat.ipv4,
      parent: [8],
    ),
    _TasticSetting(
      2,
      "Gateway",
      "Шлюз",
      format: _TasticFormat.ipv4,
      parent: [8],
    ),
    _TasticSetting(
      3,
      "Subnet",
      "Маска подсети",
      format: _TasticFormat.ipv4,
      parent: [8],
    ),
    _TasticSetting(
      4,
      "DNS",
      "DNS-сервер",
      format: _TasticFormat.ipv4,
      parent: [8],
    ),
    _TasticSetting(
      9,
      "Rsyslog Server",
      "Сервер Rsyslog",
      format: _TasticFormat.text,
      maxBytes: 32,
    ),
    _TasticSetting(
      10,
      "Enabled Protocols",
      "Протоколы локальной сети",
      format: _TasticFormat.choice,
      choices: {0: "None", 1: "UDP Broadcast"},
      since: "2.6.0",
    ),
    _TasticSetting(
      11,
      "IPV6 enabled",
      "Включить IPv6",
      format: _TasticFormat.toggle,
      since: "2.7.16",
    ),
  ]),
  RadioFieldSection.display: _TasticSection(4, 5, [
    _TasticSetting(1, "Screen on for", "Время работы экрана", units: "s"),
    _TasticSetting(
      3,
      "Carousel Interval",
      "Интервал смены экранов",
      units: "s",
    ),
    _TasticSetting(
      4,
      "Always point north",
      "Север сверху",
      format: _TasticFormat.toggle,
      before: "2.7.1",
    ),
    _TasticSetting(
      5,
      "Flip Screen",
      "Перевернуть экран",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      6,
      "Display Units",
      "Единицы измерения",
      format: _TasticFormat.choice,
      choices: {0: "Metric", 1: "Imperial"},
    ),
    _TasticSetting(
      7,
      "OLED Type",
      "Тип OLED",
      format: _TasticFormat.choice,
      choices: {
        0: "Detect Automatically",
        1: "SSD1306",
        2: "SH1106",
        3: "SH1107",
        4: "SH1107 128x128",
        5: "SH1107 Rotated",
      },
    ),
    _TasticSetting(
      8,
      "Display Mode",
      "Режим экрана",
      format: _TasticFormat.choice,
      choices: {
        0: "Default 128x64 screen layout",
        1: "Optimized for 2 color displays",
        2: "Inverted top bar for 2 color displays",
        3: "TFT Full Color Displays",
      },
    ),
    _TasticSetting(
      9,
      "Bold Heading",
      "Жирные заголовки",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      10,
      "Wake Screen on tap or motion",
      "Пробуждение касанием или движением",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      11,
      "Compass Orientation",
      "Ориентация компаса",
      format: _TasticFormat.choice,
      choices: {
        0: "0°",
        1: "90°",
        2: "180°",
        3: "270°",
        4: "0° Inverted",
        5: "90° Inverted",
        6: "180° Inverted",
        7: "270° Inverted",
      },
      since: "2.7.1",
    ),
    _TasticSetting(
      12,
      "12 Hour Clock",
      "12-часовой формат",
      format: _TasticFormat.toggle,
      since: "2.5.22",
    ),
    _TasticSetting(
      13,
      "Long Node Names",
      "Показывать длинные имена",
      format: _TasticFormat.toggle,
      since: "2.7.13",
    ),
    _TasticSetting(
      14,
      "Message Bubbles",
      "Пузырьки сообщений",
      format: _TasticFormat.toggle,
      since: "2.7.19",
    ),
  ]),
  RadioFieldSection.lora: _TasticSection(5, 6, [
    _TasticSetting(
      1,
      "Use Preset",
      "Использовать пресет",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      2,
      "Presets",
      "Режим модуляции",
      format: _TasticFormat.choice,
      choices: {
        0: "Long Range - Fast",
        1: "Long Range - Slow",
        2: "Very Long Range - Slow",
        3: "Medium Range - Slow",
        4: "Medium Range - Fast",
        5: "Short Range - Slow",
        6: "Short Range - Fast",
        7: "Long Range - Moderate",
        8: "Short Range - Turbo",
        9: "Long Range - Turbo",
        10: "Lite - Fast",
        11: "Lite - Slow",
        12: "Narrow - Fast",
        13: "Narrow - Slow",
        14: "Tiny - Fast",
        15: "Tiny - Slow",
        16: "Medium Range - Turbo",
      },
    ),
    _TasticSetting(3, "Bandwidth", "Ширина полосы", units: "kHz"),
    _TasticSetting(4, "Spread Factor", "Коэффициент расширения"),
    _TasticSetting(5, "Coding Rate", "Скорость кодирования"),
    _TasticSetting(
      6,
      "Frequency offset",
      "Смещение частоты",
      format: _TasticFormat.decimal,
      units: "MHz",
    ),
    _TasticSetting(
      7,
      "Region",
      "Регион LoRa",
      format: _TasticFormat.choice,
      choices: {
        0: "Please set a region",
        1: "United States",
        2: "European Union 433MHz",
        3: "European Union 868MHz",
        4: "China",
        5: "Japan",
        6: "Australia / Brazil / New Zealand",
        7: "Korea",
        8: "Taiwan",
        9: "Russia",
        10: "India",
        11: "New Zealand 865MHz",
        12: "Thailand",
        13: "2.4 GHz",
        14: "Ukraine 433MHz",
        15: "Ukraine 868MHz",
        16: "Malaysia 433MHz",
        17: "Malaysia 919MHz",
        18: "Singapore 923MHz",
        19: "Philippines 433MHz",
        20: "Philippines 868MHz",
        21: "Philippines 915MHz",
        22: "Australia / New Zealand 433MHz",
        23: "Kazakhstan 433MHz",
        24: "Kazakhstan 863MHz",
        25: "Nepal 865MHz",
        26: "Brazil 902MHz",
        27: "ITU Region 1 / Amateur 2m",
        28: "ITU Region 2 / Amateur 2m",
        29: "European Union 866MHz",
        30: "European Union 874MHz",
        31: "European Union 917MHz",
        32: "European Union 868MHz (Narrow)",
        33: "ITU Region 3 / Amateur 2m",
        34: "ITU Region 1 / Amateur 70cm",
        35: "ITU Region 2 / Amateur 70cm",
        36: "ITU Region 3 / Amateur 70cm",
        37: "ITU Region 2 / Amateur 1.25m",
      },
    ),
    _TasticSetting(8, "Hop Limit", "Лимит переходов"),
    _TasticSetting(
      9,
      "Transmit Enabled",
      "Разрешить передачу",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      10,
      "Transmit Power",
      "Мощность передачи",
      format: _TasticFormat.signed,
      units: "dBm",
    ),
    _TasticSetting(11, "Frequency Slot", "Номер частотного канала"),
    _TasticSetting(
      12,
      "Override Duty Cycle",
      "Переопределить ограничение эфирного времени",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      13,
      "RX Boosted Gain",
      "Усиление приёмника SX126x",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      14,
      "Frequency Override",
      "Пользовательская частота",
      format: _TasticFormat.decimal,
      units: "MHz",
    ),
    _TasticSetting(
      15,
      "PA Fan Disabled",
      "Отключить вентилятор усилителя",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      103,
      "Ignore Incoming",
      "Игнорируемые номера портов",
      format: _TasticFormat.numbers,
    ),
    _TasticSetting(
      104,
      "Ignore MQTT",
      "Игнорировать MQTT",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      105,
      "OK to MQTT",
      "Узел может отправлять данные в MQTT",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      106,
      "Fem lna mode",
      "Режим усилителя FEM LNA",
      format: _TasticFormat.choice,
      choices: {0: "Disabled", 1: "Enabled", 2: "Not present", 3: "Auto"},
      since: "2.7.20",
    ),
    _TasticSetting(
      107,
      "Serial hal only",
      "Только Serial HAL",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      108,
      "Transparent mode",
      "Прозрачный режим",
      format: _TasticFormat.toggle,
    ),
  ]),
  RadioFieldSection.bluetooth: _TasticSection(6, 7, [
    _TasticSetting(
      1,
      "Bluetooth Enabled",
      "Bluetooth включён",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      2,
      "Pairing Mode",
      "Режим",
      format: _TasticFormat.choice,
      choices: {0: "Random PIN", 1: "Fixed PIN", 2: "No PIN (Just Works)"},
    ),
    _TasticSetting(3, "Fixed Pin", "Фиксированный PIN", secret: true),
  ]),
  RadioFieldSection.security: _TasticSection(7, 8, [
    _TasticSetting(
      3,
      "Admin Key",
      "Публичные ключи администраторов",
      format: _TasticFormat.keys,
    ),
    _TasticSetting(
      4,
      "Managed Device",
      "Управляемый узел",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      5,
      "Serial Console",
      "Последовательный порт",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      6,
      "Debug Logs",
      "Отладочный журнал через API",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      8,
      "Admin channel enabled",
      "Устаревший канал управления",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      9,
      "Packet signature policy",
      "Политика подписи пакетов",
      format: _TasticFormat.choice,
      choices: {
        0: "Compatible - No Signing",
        1: "Balanced - Sign, Accept Unsigned",
        2: "Strict - Require Signatures",
      },
      since: "2.8.0",
    ),
  ]),
  RadioFieldSection.mqtt: _TasticSection(0, 1, [
    _TasticSetting(1, "MQTT Enabled", "Включено", format: _TasticFormat.toggle),
    _TasticSetting(
      2,
      "Address",
      "Адрес сервера",
      format: _TasticFormat.text,
      maxBytes: 63,
    ),
    _TasticSetting(
      3,
      "Username",
      "Имя пользователя",
      format: _TasticFormat.text,
      maxBytes: 63,
    ),
    _TasticSetting(
      4,
      "Password",
      "Пароль",
      format: _TasticFormat.text,
      secret: true,
      maxBytes: 31,
    ),
    _TasticSetting(
      5,
      "Encryption Enabled",
      "Шифрование",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      6,
      "JSON Output Enabled",
      "Публикация JSON",
      format: _TasticFormat.toggle,
      before: "2.8.0",
    ),
    _TasticSetting(
      7,
      "TLS Enabled",
      "Использовать TLS",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      8,
      "Root Topic",
      "Корневой топик",
      format: _TasticFormat.text,
      maxBytes: 31,
    ),
    _TasticSetting(
      9,
      "MQTT Client Proxy",
      "Прокси через приложение",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      10,
      "Map Reporting",
      "Публиковать на карте",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      1,
      "Map Publish Interval",
      "Интервал публикации на карте",
      units: "s",
      parent: [11],
    ),
    _TasticSetting(2, "Position precision", "Точность позиции", parent: [11]),
    _TasticSetting(
      3,
      "Share on Map",
      "Передавать местоположение",
      format: _TasticFormat.toggle,
      since: "2.6.8",
      parent: [11],
    ),
  ], module: true),
  RadioFieldSection.sensors: _TasticSection(5, 6, [
    _TasticSetting(1, "Device Metrics Interval", "Интервал телеметрии рации"),
    _TasticSetting(
      2,
      "Environment Metrics Interval",
      "Интервал измерений среды",
    ),
    _TasticSetting(
      3,
      "Environment Metrics Enabled",
      "Измерения окружающей среды",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      4,
      "Show environment on device screen",
      "Экран измерений среды",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      5,
      "Display Fahrenheit",
      "Температура по Фаренгейту",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      6,
      "Air Quality Metrics Enabled",
      "Измерять качество воздуха",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      7,
      "Air Quality Metrics Interval",
      "Интервал измерений воздуха",
    ),
    _TasticSetting(
      8,
      "Power Measurement Enabled",
      "Измерения питания",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(9, "Power Metrics Interval", "Интервал измерений питания"),
    _TasticSetting(
      10,
      "Power Screen",
      "Экран питания",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      11,
      "Health measurement enabled",
      "Измерения здоровья",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(12, "Health update interval", "Интервал измерений здоровья"),
    _TasticSetting(
      13,
      "Health screen enabled",
      "Экран здоровья",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      14,
      "Broadcast Device Metrics",
      "Телеметрия рации",
      format: _TasticFormat.toggle,
      since: "2.7.13",
    ),
    _TasticSetting(
      15,
      "Show air quality on device screen",
      "Экран качества воздуха",
      format: _TasticFormat.toggle,
      since: "2.7.18",
    ),
  ], module: true),
  RadioFieldSection.notifications: _TasticSection(2, 3, [
    _TasticSetting(
      1,
      "External Notification Enabled",
      "Включено",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      2,
      "GPIO Output Duration",
      "Длительность сигнала",
      units: "ms",
    ),
    _TasticSetting(3, "Output pin GPIO", "GPIO выхода"),
    _TasticSetting(8, "Output pin vibra GPIO", "GPIO вибрации"),
    _TasticSetting(9, "Output pin buzzer GPIO", "GPIO зуммера"),
    _TasticSetting(
      4,
      "Active",
      "Активный уровень",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      5,
      "Alert when receiving a message",
      "Оповещать о сообщениях",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      10,
      "Vibra Motor Alert",
      "Вибрация при сообщении",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      11,
      "Alert GPIO buzzer when receiving a message",
      "Зуммер при сообщении",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      6,
      "Alert when receiving a bell",
      "Оповещать по сигналу",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      12,
      "Alert GPIO vibra motor when receiving a bell",
      "Вибрация по сигналу",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      13,
      "Alert GPIO buzzer when receiving a bell",
      "Зуммер по сигналу",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      7,
      "Use PWM Buzzer",
      "Использовать PWM",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(14, "Nag Timeout", "Время повтора"),
    _TasticSetting(
      15,
      "Use I2S As Buzzer",
      "Использовать I2S как зуммер",
      format: _TasticFormat.toggle,
    ),
  ], module: true),
  RadioFieldSection.serial: _TasticSection(1, 2, [
    _TasticSetting(
      1,
      "Serial Enabled",
      "Включено",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(2, "Echo", "Эхо", format: _TasticFormat.toggle),
    _TasticSetting(3, "Receive data (rxd) GPIO pin", "GPIO RX"),
    _TasticSetting(4, "Transmit data (txd) GPIO pin", "GPIO TX"),
    _TasticSetting(
      5,
      "Baud",
      "Скорость порта",
      format: _TasticFormat.choice,
      choices: {
        0: "Default",
        1: "110 Baud",
        2: "300 Baud",
        3: "600 Baud",
        4: "1200 Baud",
        5: "2400 Baud",
        6: "4800 Baud",
        7: "9600 Baud",
        8: "19200 Baud",
        9: "38400 Baud",
        10: "57600 Baud",
        11: "115200 Baud",
        12: "230400 Baud",
        13: "460800 Baud",
        14: "576000 Baud",
        15: "921600 Baud",
      },
    ),
    _TasticSetting(6, "Timeout", "Время ожидания"),
    _TasticSetting(
      7,
      "Mode",
      "Режим",
      format: _TasticFormat.choice,
      choices: {
        0: "Default",
        1: "Simple",
        2: "Protobufs",
        3: "Text Message",
        4: "NMEA Positions",
        5: "CalTopo",
        6: "Ws85",
        7: "Ve direct",
        8: "Ms config",
        9: "Log",
        10: "Logtext",
        11: "Modbus",
      },
    ),
    _TasticSetting(
      8,
      "Override Console Serial Port",
      "Override Console Serial Port",
      format: _TasticFormat.toggle,
    ),
  ], module: true),
  RadioFieldSection.storeForward: _TasticSection(3, 4, [
    _TasticSetting(
      1,
      "Store and Forward Enabled",
      "Включено",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      2,
      "Send Heartbeat",
      "Сигнал присутствия",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(3, "Number of records", "Число записей"),
    _TasticSetting(4, "History Return Max", "Максимум записей истории"),
    _TasticSetting(5, "History Return Window", "Глубина истории"),
    _TasticSetting(6, "Server", "Режим сервера", format: _TasticFormat.toggle),
  ], module: true),
  RadioFieldSection.rangeTest: _TasticSection(4, 5, [
    _TasticSetting(
      1,
      "Range Test Enabled",
      "Включено",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(2, "Sender Interval", "Интервал отправки"),
    _TasticSetting(
      3,
      "Save",
      "Сохранять результаты",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      4,
      "Clear on reboot",
      "Очищать при перезапуске",
      format: _TasticFormat.toggle,
      since: "2.7.11",
    ),
  ], module: true),
  RadioFieldSection.quickMessages: _TasticSection(6, 7, [
    _TasticSetting(
      1,
      "Rotary Encoder",
      "Rotary Encoder",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(2, "Pin A", "Pin A"),
    _TasticSetting(3, "Pin B", "Pin B"),
    _TasticSetting(4, "Press Pin", "Press Pin"),
    _TasticSetting(
      5,
      "Clockwise Rotary Event",
      "Clockwise Rotary Event",
      format: _TasticFormat.choice,
      choices: {
        0: "None",
        17: "Up",
        18: "Down",
        19: "Left",
        20: "Right",
        10: "Select",
        27: "Back",
        24: "Cancel",
      },
    ),
    _TasticSetting(
      6,
      "Counterclockwise Rotary Event",
      "Counterclockwise Rotary Event",
      format: _TasticFormat.choice,
      choices: {
        0: "None",
        17: "Up",
        18: "Down",
        19: "Left",
        20: "Right",
        10: "Select",
        27: "Back",
        24: "Cancel",
      },
    ),
    _TasticSetting(
      7,
      "Encoder Press Event",
      "Encoder Press Event",
      format: _TasticFormat.choice,
      choices: {
        0: "None",
        17: "Up",
        18: "Down",
        19: "Left",
        20: "Right",
        10: "Select",
        27: "Back",
        24: "Cancel",
      },
    ),
    _TasticSetting(
      8,
      "Up/Down/Select Input",
      "Up/Down/Select Input",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      9,
      "Enabled",
      "Включено",
      format: _TasticFormat.toggle,
      before: "2.7.0",
    ),
    _TasticSetting(
      10,
      "Allow input source",
      "Allow input source",
      format: _TasticFormat.text,
      maxBytes: 15,
      before: "2.7.0",
    ),
    _TasticSetting(
      11,
      "Send Bell",
      "Добавлять звуковой сигнал",
      format: _TasticFormat.toggle,
    ),
  ], module: true),
  RadioFieldSection.audio: _TasticSection(7, 8, [
    _TasticSetting(
      1,
      "Codec2 Enabled",
      "Codec2 Enabled",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(2, "PTT Pin", "PTT Pin"),
    _TasticSetting(
      3,
      "Bitrate",
      "Bitrate",
      format: _TasticFormat.choice,
      choices: {
        0: "Default",
        1: "3200 bps",
        2: "2400 bps",
        3: "1600 bps",
        4: "1400 bps",
        5: "1300 bps",
        6: "1200 bps",
        7: "Codec2 700",
        8: "Codec2 700b",
        9: "700 bps (700C)",
        10: "450 bps",
      },
    ),
    _TasticSetting(4, "I2S Word Select Pin", "I2S Word Select Pin"),
    _TasticSetting(5, "I2S Data In Pin", "I2S Data In Pin"),
    _TasticSetting(6, "I2S Data Out Pin", "I2S Data Out Pin"),
    _TasticSetting(7, "I2S Clock Pin", "I2S Clock Pin"),
  ], module: true),
  RadioFieldSection.remoteHardware: _TasticSection(8, 9, [
    _TasticSetting(1, "Enabled", "Включено", format: _TasticFormat.toggle),
    _TasticSetting(
      2,
      "Allow undefined pin access",
      "Доступ к ненастроенным GPIO",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      3,
      'Remote GPIO pins',
      'Удалённые GPIO',
      format: _TasticFormat.gpioPins,
    ),
  ], module: true),
  RadioFieldSection.neighborInfo: _TasticSection(9, 10, [
    _TasticSetting(
      1,
      "Neighbor Info Enabled",
      "Включено",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(2, "Update Interval", "Интервал обновления"),
    _TasticSetting(
      3,
      "Transmit over LoRa",
      "Передача по LoRa",
      format: _TasticFormat.toggle,
    ),
  ], module: true),
  RadioFieldSection.ambientLighting: _TasticSection(10, 11, [
    _TasticSetting(
      1,
      "LED State",
      "Светодиод включён",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(2, "Current", "Ток"),
    _TasticSetting(3, "Red", "Красный"),
    _TasticSetting(4, "Green", "Зелёный"),
    _TasticSetting(5, "Blue", "Синий"),
  ], module: true),
  RadioFieldSection.detectionSensor: _TasticSection(11, 12, [
    _TasticSetting(
      1,
      "Detection Sensor Enabled",
      "Включено",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      2,
      "Minimum time between detection broadcasts",
      "Минимальный интервал отправки",
      units: "s",
    ),
    _TasticSetting(
      3,
      "State Broadcast Interval",
      "Интервал отправки состояния",
      units: "s",
    ),
    _TasticSetting(
      4,
      "Send Bell",
      "Добавлять звуковой сигнал",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(5, "Name", "Имя", format: _TasticFormat.text),
    _TasticSetting(6, "GPIO Pin to monitor", "GPIO датчика"),
    _TasticSetting(
      7,
      "Trigger Type",
      "Условие срабатывания",
      format: _TasticFormat.choice,
      choices: {
        0: "Low",
        1: "High",
        2: "Falling Edge",
        3: "Rising Edge",
        4: "Either Edge Low",
        5: "Either Edge High",
      },
    ),
    _TasticSetting(
      8,
      "Use Internal Pull-up",
      "Подтяжка входа",
      format: _TasticFormat.toggle,
    ),
  ], module: true),
  RadioFieldSection.paxCounter: _TasticSection(12, 13, [
    _TasticSetting(
      1,
      "PAX Counter Enabled",
      "Включено",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(2, "Update Interval", "Интервал подсчёта"),
    _TasticSetting(
      3,
      "WiFi Threshold",
      "Порог сигнала Wi-Fi",
      format: _TasticFormat.signed,
      units: "dBm",
    ),
    _TasticSetting(
      4,
      "BLE Threshold",
      "Порог сигнала Bluetooth",
      format: _TasticFormat.signed,
      units: "dBm",
    ),
  ], module: true),
  RadioFieldSection.statusMessage: _TasticSection(
    13,
    14,
    [
      _TasticSetting(
        1,
        "Node status",
        "Текст статуса",
        format: _TasticFormat.text,
        maxBytes: 79,
      ),
    ],
    module: true,
    since: "2.7.20",
  ),
  RadioFieldSection.trafficManagement: _TasticSection(
    14,
    15,
    [
      _TasticSetting(
        4,
        "Minimum Position Interval",
        "Минимальный интервал позиции",
        units: "s",
      ),
      _TasticSetting(6, "Direct NodeInfo Max Hops", "Direct NodeInfo Max Hops"),
      _TasticSetting(
        8,
        "Rate Limit Window",
        "Окно ограничения частоты",
        units: "s",
      ),
      _TasticSetting(9, "Rate Limit Max Packets", "Максимум пакетов"),
      _TasticSetting(
        11,
        "Unknown Packet Threshold",
        "Порог неизвестных пакетов",
      ),
    ],
    module: true,
    since: "2.8.0",
  ),
  RadioFieldSection.tak: _TasticSection(
    15,
    16,
    [
      _TasticSetting(
        1,
        "Team",
        "Команда",
        format: _TasticFormat.choice,
        choices: {
          0: "Default (Cyan)",
          1: "White",
          2: "Yellow",
          3: "Orange",
          4: "Magenta",
          5: "Red",
          6: "Maroon",
          7: "Purple",
          8: "Dark Blue",
          9: "Blue",
          10: "Cyan",
          11: "Teal",
          12: "Green",
          13: "Dark Green",
          14: "Brown",
        },
      ),
      _TasticSetting(
        2,
        "Role",
        "Роль рации",
        format: _TasticFormat.choice,
        choices: {
          0: "Default (Team Member)",
          1: "Team Member",
          2: "Team Lead",
          3: "HQ",
          4: "Sniper",
          5: "Medic",
          6: "Forward Observer",
          7: "RTO",
          8: "K9",
        },
      ),
    ],
    module: true,
    since: "2.8.0",
  ),
  RadioFieldSection.beacon: _TasticSection(
    16,
    17,
    [
      _TasticSetting(1, "Flags", "Маска параметров"),
      _TasticSetting(
        2,
        "Broadcast offer frequency slot",
        "Broadcast offer frequency slot",
      ),
      _TasticSetting(
        4,
        "Message",
        "Текст маяка",
        format: _TasticFormat.text,
        maxBytes: 60,
      ),
      _TasticSetting(1, "Channel num", "Номер частотного канала", parent: [5]),
      _TasticSetting(
        2,
        "PSK",
        "PSK",
        format: _TasticFormat.bytes,
        secret: true,
        parent: [5],
      ),
      _TasticSetting(
        3,
        "Name",
        "Имя",
        format: _TasticFormat.text,
        parent: [5],
        maxBytes: 11,
      ),
      _TasticSetting(4, "Id", "Id", format: _TasticFormat.fixed, parent: [5]),
      _TasticSetting(
        5,
        "Uplink enabled",
        "Uplink enabled",
        format: _TasticFormat.toggle,
        parent: [5],
      ),
      _TasticSetting(
        6,
        "Downlink enabled",
        "Downlink enabled",
        format: _TasticFormat.toggle,
        parent: [5],
      ),
      _TasticSetting(
        1,
        "Position precision",
        "Точность позиции",
        parent: [5, 7],
      ),
      _TasticSetting(
        2,
        "Is muted",
        "Is muted",
        format: _TasticFormat.toggle,
        parent: [5, 7],
      ),
      _TasticSetting(
        8,
        "Use aead",
        "Use aead",
        format: _TasticFormat.toggle,
        parent: [5],
      ),
      _TasticSetting(
        6,
        "Broadcast offer region",
        "Broadcast offer region",
        format: _TasticFormat.choice,
        choices: {
          0: "Please set a region",
          1: "United States",
          2: "European Union 433MHz",
          3: "European Union 868MHz",
          4: "China",
          5: "Japan",
          6: "Australia / Brazil / New Zealand",
          7: "Korea",
          8: "Taiwan",
          9: "Russia",
          10: "India",
          11: "New Zealand 865MHz",
          12: "Thailand",
          13: "2.4 GHz",
          14: "Ukraine 433MHz",
          15: "Ukraine 868MHz",
          16: "Malaysia 433MHz",
          17: "Malaysia 919MHz",
          18: "Singapore 923MHz",
          19: "Philippines 433MHz",
          20: "Philippines 868MHz",
          21: "Philippines 915MHz",
          22: "Australia / New Zealand 433MHz",
          23: "Kazakhstan 433MHz",
          24: "Kazakhstan 863MHz",
          25: "Nepal 865MHz",
          26: "Brazil 902MHz",
          27: "ITU Region 1 / Amateur 2m",
          28: "ITU Region 2 / Amateur 2m",
          29: "European Union 866MHz",
          30: "European Union 874MHz",
          31: "European Union 917MHz",
          32: "European Union 868MHz (Narrow)",
          33: "ITU Region 3 / Amateur 2m",
          34: "ITU Region 1 / Amateur 70cm",
          35: "ITU Region 2 / Amateur 70cm",
          36: "ITU Region 3 / Amateur 70cm",
          37: "ITU Region 2 / Amateur 1.25m",
        },
      ),
      _TasticSetting(
        7,
        "Broadcast offer preset",
        "Broadcast offer preset",
        format: _TasticFormat.choice,
        choices: {
          0: "Long Range - Fast",
          1: "Long Range - Slow",
          2: "Very Long Range - Slow",
          3: "Medium Range - Slow",
          4: "Medium Range - Fast",
          5: "Short Range - Slow",
          6: "Short Range - Fast",
          7: "Long Range - Moderate",
          8: "Short Range - Turbo",
          9: "Long Range - Turbo",
          10: "Lite - Fast",
          11: "Lite - Slow",
          12: "Narrow - Fast",
          13: "Narrow - Slow",
          14: "Tiny - Fast",
          15: "Tiny - Slow",
          16: "Medium Range - Turbo",
        },
      ),
      _TasticSetting(11, "Interval", "Интервал маяка", units: "s"),
      _TasticSetting(
        13,
        'Broadcast destinations',
        'Направления отправки маяка',
        format: _TasticFormat.beaconTargets,
      ),
    ],
    module: true,
    since: "2.8.0",
  ),
  RadioFieldSection.deviceUi: _TasticSection(9, 10, [
    _TasticSetting(2, "Screen brightness", "Яркость"),
    _TasticSetting(3, "Screen timeout", "Время работы экрана"),
    _TasticSetting(
      4,
      "Screen lock",
      "Блокировка экрана",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      5,
      "Settings lock",
      "Блокировка настроек",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(6, "Pin code", "Pin code", secret: true),
    _TasticSetting(
      7,
      "Theme",
      "Тема",
      format: _TasticFormat.choice,
      choices: {0: "Dark", 1: "Light", 2: "Red"},
    ),
    _TasticSetting(
      8,
      "Alert enabled",
      "Звук уведомлений",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      9,
      "Banner enabled",
      "Баннеры",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(10, "Ring tone id", "Мелодия"),
    _TasticSetting(
      11,
      "Language",
      "Язык",
      format: _TasticFormat.choice,
      choices: {
        0: "English",
        1: "French",
        2: "German",
        3: "Italian",
        4: "Portuguese",
        5: "Spanish",
        6: "Swedish",
        7: "Finnish",
        8: "Polish",
        9: "Turkish",
        10: "Serbian",
        11: "Russian",
        12: "Dutch",
        13: "Greek",
        14: "Norwegian",
        15: "Slovenian",
        16: "Ukrainian",
        17: "Bulgarian",
        18: "Czech",
        19: "Danish",
        20: "Hungarian",
        21: "Azerbaijani",
        30: "Simplified chinese",
        31: "Traditional chinese",
      },
    ),
    _TasticSetting(
      1,
      "Unknown switch",
      "Unknown switch",
      format: _TasticFormat.toggle,
      parent: [12],
    ),
    _TasticSetting(
      2,
      "Offline switch",
      "Offline switch",
      format: _TasticFormat.toggle,
      parent: [12],
    ),
    _TasticSetting(
      3,
      "Public key switch",
      "Public key switch",
      format: _TasticFormat.toggle,
      parent: [12],
    ),
    _TasticSetting(
      4,
      "Hops away",
      "Hops away",
      format: _TasticFormat.signed,
      parent: [12],
    ),
    _TasticSetting(
      5,
      "Position switch",
      "Position switch",
      format: _TasticFormat.toggle,
      parent: [12],
    ),
    _TasticSetting(
      6,
      "Node name",
      "Node name",
      format: _TasticFormat.text,
      parent: [12],
    ),
    _TasticSetting(
      7,
      "Channel",
      "Channel",
      format: _TasticFormat.signed,
      parent: [12],
    ),
    _TasticSetting(
      1,
      "Chat switch",
      "Chat switch",
      format: _TasticFormat.toggle,
      parent: [13],
    ),
    _TasticSetting(
      2,
      "Position switch",
      "Position switch",
      format: _TasticFormat.toggle,
      parent: [13],
    ),
    _TasticSetting(
      3,
      "Telemetry switch",
      "Telemetry switch",
      format: _TasticFormat.toggle,
      parent: [13],
    ),
    _TasticSetting(
      4,
      "Iaq switch",
      "Iaq switch",
      format: _TasticFormat.toggle,
      parent: [13],
    ),
    _TasticSetting(
      5,
      "Node name",
      "Node name",
      format: _TasticFormat.text,
      parent: [13],
    ),
    _TasticSetting(
      1,
      "Zoom",
      "Zoom",
      format: _TasticFormat.signed,
      parent: [15, 1],
    ),
    _TasticSetting(
      2,
      "Latitude",
      "Latitude",
      format: _TasticFormat.signed,
      parent: [15, 1],
    ),
    _TasticSetting(
      3,
      "Longitude",
      "Longitude",
      format: _TasticFormat.signed,
      parent: [15, 1],
    ),
    _TasticSetting(
      2,
      "Style",
      "Style",
      format: _TasticFormat.text,
      parent: [15],
    ),
    _TasticSetting(
      3,
      "Follow GPS",
      "Follow GPS",
      format: _TasticFormat.toggle,
      parent: [15],
    ),
    _TasticSetting(
      16,
      "Compass mode",
      "Compass mode",
      format: _TasticFormat.choice,
      choices: {0: "Dynamic", 1: "Fixed ring", 2: "Freeze heading"},
    ),
    _TasticSetting(17, "Screen RGB color", "Screen RGB color"),
    _TasticSetting(
      18,
      "Is clockface analog",
      "Аналоговые часы",
      format: _TasticFormat.toggle,
    ),
    _TasticSetting(
      19,
      "GPS format",
      "Формат координат",
      format: _TasticFormat.choice,
      choices: {
        0: "Dec",
        1: "DMS",
        2: "UTM",
        3: "MGRS",
        4: "Olc",
        5: "Osgr",
        6: "Mls",
      },
    ),
  ]),
};

const _tasticHardwareModels = <int, String>{
  1: "Tlora v2",
  2: "Tlora v1",
  3: "Tlora v2 1 1p6",
  4: "Tbeam",
  5: "Heltec v2 0",
  6: "Tbeam v0p7",
  7: "T echo",
  8: "Tlora v1 1p3",
  9: "Rak4631",
  10: "Heltec v2 1",
  11: "Heltec v1",
  12: "Lilygo tbeam s3 core",
  13: "Rak11200",
  14: "Nano g1",
  15: "Tlora v2 1 1p8",
  16: "Tlora t3 s3",
  17: "Nano g1 explorer",
  18: "Nano g2 ultra",
  19: "LORA type",
  20: "Wiphone",
  21: "Wio wm1110",
  22: "Rak2560",
  23: "Heltec hru 3601",
  24: "Heltec wireless bridge",
  25: "Station g1",
  26: "Rak11310",
  27: "Makerfabs tracker",
  28: "Makerfabs reserved",
  29: "Canaryone",
  30: "Rp2040 LORA",
  31: "Station g2",
  32: "LORA relay v1",
  33: "T echo plus",
  34: "Ppr",
  35: "Genieblocks",
  36: "Nrf52 unknown",
  37: "Portduino",
  38: "Android sim",
  39: "Diy v1",
  40: "Nrf52840 pca10059",
  41: "Dr dev",
  42: "M5stack",
  43: "Heltec v3",
  44: "Heltec wsl v3",
  45: "Betafpv 2400 TX",
  46: "Betafpv 900 nano TX",
  47: "Rpi pico",
  48: "Heltec wireless tracker",
  49: "Heltec wireless paper",
  50: "T deck",
  51: "T watch s3",
  52: "Picomputer s3",
  53: "Heltec ht62",
  54: "Ebyte esp32 s3",
  55: "Esp32 s3 pico",
  56: "Chatter 2",
  57: "Heltec wireless paper v1 0",
  58: "Heltec wireless tracker v1 0",
  59: "Unphone",
  60: "Td lorac",
  61: "Cdebyte eora s3",
  62: "Twc mesh v4",
  63: "Nrf52 promicro diy",
  64: "Radiomaster 900 bandit nano",
  65: "Heltec capsule sensor v3",
  66: "Heltec vision master t190",
  67: "Heltec vision master e213",
  68: "Heltec vision master e290",
  69: "Heltec mesh node t114",
  70: "Sensecap indicator",
  71: "Tracker t1000 e",
  72: "Rak3172",
  73: "Wio e5",
  74: "Radiomaster 900 bandit",
  75: "Me25ls01 4y10td",
  76: "Rp2040 feather rfm95",
  77: "M5stack corebasic",
  78: "M5stack core2",
  79: "Rpi pico2",
  80: "M5stack cores3",
  81: "Seeed xiao s3",
  82: "Ms24sf1",
  83: "Tlora c6",
  84: "Wismesh tap",
  85: "Routastic",
  86: "Mesh tab",
  87: "Meshlink",
  88: "Xiao nrf52 kit",
  89: "Thinknode m1",
  90: "Thinknode m2",
  91: "T eth elite",
  92: "Heltec sensor hub",
  93: "Muzi base",
  94: "Heltec mesh pocket",
  95: "Seeed solar node",
  96: "Nomadstar meteor pro",
  97: "Crowpanel",
  98: "Link 32",
  99: "Seeed wio tracker l1",
  100: "Seeed wio tracker l1 eink",
  101: "Muzi r1 neo",
  102: "T deck pro",
  103: "T LORA pager",
  104: "M5stack reserved",
  105: "Wismesh tag",
  106: "Rak3312",
  107: "Thinknode m5",
  108: "Heltec mesh solar",
  109: "T echo lite",
  110: "Heltec v4",
  111: "M5stack c6l",
  112: "M5stack cardputer adv",
  113: "Heltec wireless tracker v2",
  114: "T watch ultra",
  115: "Thinknode m3",
  116: "Wismesh tap v2",
  117: "Rak3401",
  118: "Rak6421",
  119: "Thinknode m4",
  120: "Thinknode m6",
  121: "Meshstick 1262",
  122: "Tbeam 1 watt",
  123: "T5 s3 epaper pro",
  124: "Tbeam bpf",
  125: "Mini epaper s3",
  126: "Tdisplay s3 pro",
  127: "Heltec mesh node t096",
  128: "Mesh tracker x1",
  129: "Thinknode m7",
  130: "Thinknode m8",
  131: "Thinknode m9",
  132: "Heltec v4 r8",
  133: "Heltec mesh node t1",
  134: "Station g3",
  135: "T impulse plus",
  136: "T echo card",
  137: "Seeed wio tracker l2",
  138: "Crowpanel p4",
  139: "Heltec mesh tower v2",
  140: "Meshnology w10",
  141: "Heltec rc32",
  142: "Heltec rc52",
  143: "Heltec rcc6",
  144: "Seeed wio tracker l1 pro 1w",
  145: "Meshnology w12",
  146: "Meshpager x2",
  147: "T connect pro",
  148: "Axiometa genesis mini",
  149: "Makerfabs nomad terminal",
  150: "Thinknode mx",
  151: "Nodara",
  152: "Heltec mesh pocket v2",
  254: "Virtual node",
  255: "Private hw",
};

UnknownFieldSet _settingsFields(List<int> bytes) =>
    UnknownFieldSet()..mergeFromCodedBufferReader(CodedBufferReader(bytes));

List<int> _settingsBytes(UnknownFieldSet fields) {
  final output = CodedBufferWriter();
  fields.writeToCodedBufferWriter(output);
  return output.toBuffer();
}

extension on _TasticSetting {
  RadioField toField(RadioFieldSection section, UnknownFieldSet config) =>
      RadioField(
        id,
        en,
        ru,
        read(config),
        kind: switch (format) {
          _TasticFormat.toggle => RadioFieldKind.toggle,
          _TasticFormat.choice => RadioFieldKind.choice,
          _TasticFormat.decimal => RadioFieldKind.decimal,
          _TasticFormat.integer ||
          _TasticFormat.signed ||
          _TasticFormat.wide => RadioFieldKind.integer,
          _TasticFormat.gpioPins ||
          _TasticFormat.beaconTargets => RadioFieldKind.multiline,
          _ => RadioFieldKind.text,
        },
        choices: choices.map((key, value) => MapEntry('$key', value)),
        section: section,
        secret: secret,
        units: units,
        example: switch (format) {
          _TasticFormat.gpioPins => '[{"gpio": 12, "name": "A", "access": 1}]',
          _TasticFormat.beaconTargets =>
            '[{"region": 0, "preset": 0, "channel": 0, "slot": 1}]',
          _ => null,
        },
      );

  String read(UnknownFieldSet config) {
    for (final field in parent) {
      config = _settingsFields(
        config.getField(field)?.lengthDelimited.lastOrNull ?? const [],
      );
    }
    final field = config.getField(tag);
    final number = field?.varints.lastOrNull?.toInt() ?? 0;
    final fixed = field?.fixed32s.lastOrNull ?? 0;
    return switch (format) {
      _TasticFormat.toggle => '${number != 0}',
      _TasticFormat.text => utf8.decode(
        field?.lengthDelimited.lastOrNull ?? const [],
        allowMalformed: true,
      ),
      _TasticFormat.signed => '${number.toSigned(32)}',
      _TasticFormat.decimal =>
        '${(ByteData(4)..setUint32(0, fixed.toUnsigned(32))).getFloat32(0)}',
      _TasticFormat.ipv4 => List.generate(
        4,
        (i) => (fixed >> (i * 8)) & 255,
      ).join('.'),
      _TasticFormat.fixed => '${fixed.toUnsigned(32)}',
      _TasticFormat.wide =>
        (field?.varints.lastOrNull ?? Int64.ZERO).toStringUnsigned(),
      _TasticFormat.bytes => _hexKey(
        field?.lengthDelimited.lastOrNull ?? const [],
      ),
      _TasticFormat.keys =>
        (field?.lengthDelimited ?? const []).map(_hexKey).join(', '),
      _TasticFormat.numbers => _repeatedNumbers(field).join(', '),
      _TasticFormat.gpioPins ||
      _TasticFormat.beaconTargets => _readSettingsRecords(field, format),
      _ => '${number.toUnsigned(32)}',
    };
  }

  void write(UnknownFieldSet config, String value, [int depth = 0]) {
    if (depth < parent.length) {
      final field = parent[depth];
      final bytes =
          config.getField(field)?.lengthDelimited.lastOrNull ?? const [];
      final nested = _settingsFields(bytes);
      write(nested, value, depth + 1);
      config
        ..clearField(field)
        ..mergeLengthDelimitedField(field, _settingsBytes(nested));
      return;
    }

    final existing = config.getField(tag);
    config.clearField(tag);
    switch (format) {
      case _TasticFormat.toggle:
        if (value != 'true' && value != 'false') {
          throw const FormatException('Toggle');
        }
        config.mergeVarintField(tag, value == 'true' ? Int64.ONE : Int64.ZERO);
      case _TasticFormat.text:
        final bytes = utf8.encode(value);
        if (bytes.contains(0) || bytes.length > (maxBytes ?? 255)) {
          throw const FormatException('Invalid setting text');
        }
        config.mergeLengthDelimitedField(tag, bytes);
      case _TasticFormat.decimal:
        final number = double.tryParse(value.replaceAll(',', '.'));
        if (number == null || !number.isFinite || number.abs() > 3.4e38) {
          throw const FormatException('Decimal setting');
        }
        config.mergeFixed32Field(
          tag,
          (ByteData(4)..setFloat32(0, number)).getUint32(0),
        );
      case _TasticFormat.ipv4:
        final octets = value.split('.');
        if (octets.length != 4) throw const FormatException('IPv4 address');
        var address = 0;
        for (final (i, octet) in octets.indexed) {
          address |= _integer(octet, 0, 255) << (i * 8);
        }
        config.mergeFixed32Field(tag, address);
      case _TasticFormat.fixed:
        config.mergeFixed32Field(tag, _integer(value, 0, 0xffffffff));
      case _TasticFormat.wide:
        if (!RegExp(r'^\d{1,20}$').hasMatch(value)) {
          throw const FormatException('Integer setting');
        }
        final parsed = Int64.parseInt(value);
        if (parsed.toStringUnsigned() !=
            value.replaceFirst(RegExp(r'^0+(?=\d)'), '')) {
          throw const FormatException('Integer setting');
        }
        config.mergeVarintField(tag, parsed);
      case _TasticFormat.keys:
        final keys = _parts(value);
        if (keys.length > 3) throw const FormatException('Admin keys');
        for (final key in keys) {
          final bytes = _bytesFromHex(key);
          if (bytes.length != 32) {
            throw const FormatException('Admin key length');
          }
          config.mergeLengthDelimitedField(tag, bytes);
        }
      case _TasticFormat.bytes:
        config.mergeLengthDelimitedField(tag, _bytesFromHex(value));
      case _TasticFormat.numbers:
        final items = _parts(value);
        if (items.length > 3) throw const FormatException('Ignored node limit');
        for (final item in items) {
          config.mergeVarintField(tag, Int64(_integer(item, 0, 0xffffffff)));
        }
      case _TasticFormat.gpioPins:
      case _TasticFormat.beaconTargets:
        for (final record in _writeSettingsRecords(existing, format, value)) {
          config.mergeLengthDelimitedField(tag, record);
        }
      case _TasticFormat.choice:
        final choice = int.tryParse(value);
        if (choice == null || !choices.containsKey(choice)) {
          throw const FormatException('Unknown choice');
        }
        config.mergeVarintField(tag, Int64(choice));
      case _TasticFormat.signed:
        config.mergeVarintField(
          tag,
          Int64(_integer(value, -0x80000000, 0x7fffffff)),
        );
      case _TasticFormat.integer:
        config.mergeVarintField(tag, Int64(_integer(value, 0, 0xffffffff)));
    }
  }
}

const _gpioColumns = {'gpio': (1, 0, 255), 'access': (3, 0, 2)};
const _beaconColumns = {
  'region': (2, 0, 37),
  'preset': (1, 0, 16),
  'channel': (4, 0, 7),
  'slot': (5, 1, 0xffffffff),
};

String _readSettingsRecords(UnknownFieldSetField? field, _TasticFormat format) {
  final gpio = format == _TasticFormat.gpioPins;
  final columns = gpio ? _gpioColumns : _beaconColumns;
  final records = field?.lengthDelimited.map(_settingsFields) ?? const [];
  return '[${records.map((record) {
    return jsonEncode({for (final MapEntry(key: name, value: (tag, _, _)) in columns.entries)
      if (record.getField(tag)?.varints.lastOrNull case final value?) name: value.toInt().toUnsigned(32) else if (name == 'gpio' || name == 'access' || name == 'region') name: 0, if (gpio) 'name': utf8.decode(record.getField(2)?.lengthDelimited.lastOrNull ?? const [], allowMalformed: true)});
  }).join(',\n ')}]';
}

Iterable<List<int>> _writeSettingsRecords(
  UnknownFieldSetField? previous,
  _TasticFormat format,
  String value,
) sync* {
  final gpio = format == _TasticFormat.gpioPins;
  final columns = gpio ? _gpioColumns : _beaconColumns;
  final input = value.isEmpty ? const [] : jsonDecode(value);
  if (input is! List || input.length > 4) {
    throw const FormatException('Expected up to four entries');
  }
  final existing = previous?.lengthDelimited ?? const <List<int>>[];
  for (final (index, item) in input.indexed) {
    if (item is! Map<String, dynamic> ||
        item.keys.any(
          (key) => !columns.containsKey(key) && !(gpio && key == 'name'),
        ) ||
        (gpio && !item.containsKey('gpio'))) {
      throw const FormatException('Unknown setting entry');
    }
    final record = _settingsFields(
      index < existing.length ? existing[index] : const [],
    );
    for (final MapEntry(key: name, value: (tag, low, high))
        in columns.entries) {
      record.clearField(tag);
      if (!item.containsKey(name)) continue;
      final number = item[name];
      if (number is! int || number < low || number > high) {
        throw const FormatException('Invalid value in setting entry');
      }
      record.mergeVarintField(tag, Int64(number));
    }
    if (gpio) {
      final name = item['name'] ?? '';
      if (name is! String) throw const FormatException('Invalid GPIO name');
      final bytes = utf8.encode(name);
      if (bytes.length > 14 || bytes.contains(0)) {
        throw const FormatException('Invalid GPIO name');
      }
      record
        ..clearField(2)
        ..mergeLengthDelimitedField(2, bytes);
    }
    yield _settingsBytes(record);
  }
}

Iterable<int> _repeatedNumbers(UnknownFieldSetField? field) sync* {
  if (field == null) return;
  yield* field.varints.map((value) => value.toInt().toUnsigned(32));
  for (final packed in field.lengthDelimited) {
    final reader = CodedBufferReader(packed);
    while (!reader.isAtEnd()) {
      yield reader.readUint32();
    }
  }
}

List<String> _parts(String value) => value.trim().isEmpty
    ? []
    : value.split(',').map((item) => item.trim()).toList();

Uint8List _bytesFromHex(String value) {
  if (value.length.isOdd || !RegExp(r'^[\da-fA-F]*$').hasMatch(value)) {
    throw const FormatException('Expected a hexadecimal value');
  }
  return Uint8List.fromList([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}

int _integer(String raw, int minimum, int maximum) {
  final value = int.tryParse(raw);
  if (value == null || value < minimum || value > maximum) {
    throw const FormatException('Integer setting');
  }
  return value;
}

bool _firmwareAtLeast(String version, String minimum) {
  final release = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
  if (release == null) return false;
  final required = minimum.split('.').map(int.parse).toList();
  for (var i = 0; i < required.length; i++) {
    final order = int.parse(release[i + 1]!).compareTo(required[i]);
    if (order != 0) return order > 0;
  }
  return true;
}

final class _TasticConfigUnavailable implements Exception {
  const _TasticConfigUnavailable();
}

typedef _TasticAuxiliary = ({
  int get,
  int response,
  int set,
  int limit,
  String en,
  String ru,
});

const _auxiliarySettings = <RadioFieldSection, _TasticAuxiliary>{
  RadioFieldSection.quickMessages: (
    get: 10,
    response: 11,
    set: 36,
    limit: 200,
    en: 'Messages separated by |',
    ru: 'Сообщения через |',
  ),
  RadioFieldSection.notifications: (
    get: 14,
    response: 15,
    set: 37,
    limit: 228,
    en: 'RTTTL ringtone',
    ru: 'Мелодия RTTTL',
  ),
};
