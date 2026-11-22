const profiles = {
  meshtastic: {
    protocol: "Meshtastic", radio: "Heltec V3", firmware: "2.8.1", band: "EU_868", modem: "LongFast",
    chats: [
      { id: "trail", name: "Тропа", type: "channel", color: "mint", icon: "hash", mode: "Основной канал", protection: "Общий ключ", preview: "Лена: Мы у развилки", time: "12:42", unread: 3 },
      { id: "mira", name: "Мира Соколова", initials: "МС", color: "lavender", preview: "Вижу метку. Скоро будем.", time: "12:39", unread: 1 },
      { id: "camp", name: "Лагерь", type: "channel", color: "blue", icon: "lock", mode: "Дополнительный канал", protection: "Частный ключ", preview: "Илья: Вода есть", time: "12:18", muted: true },
      { id: "ilya", name: "Илья Ветров", initials: "ИВ", color: "sand", preview: "Принял, остаюсь на точке.", time: "11:56" },
      { id: "lena", name: "Лена Орлова", initials: "ЛО", color: "rose", preview: "Фото посмотрим в лагере.", time: "11:28" },
      { id: "base", name: "База", type: "channel", color: "slate", icon: "hash", mode: "Дополнительный канал", protection: "Общий ключ", preview: "Антон: Рация заряжена", time: "Вчера" }
    ],
    nodes: [
      { id: "mira", name: "Мира Соколова", initials: "МС", color: "lavender", role: "Клиент", seen: "2 мин назад", signal: "−7,5 дБ", rssi: "−96 дБм", key: "!a1b2c317", at: [61, 34] },
      { id: "ridge", name: "Северный гребень", icon: "tower", color: "mint", role: "Маршрутизатор", seen: "4 мин назад", signal: "−5,0 дБ", rssi: "−91 дБм", key: "!e94b2c01", at: [72, 50] },
      { id: "ilya", name: "Илья Ветров", initials: "ИВ", color: "sand", role: "Клиент", seen: "18 мин назад", signal: "−10,0 дБ", key: "!a108cf2c", at: [31, 62] },
      { id: "lena", name: "Лена Орлова", initials: "ЛО", color: "rose", role: "Клиент", seen: "26 мин назад", signal: "−8,5 дБ", key: "!11b852ca", at: [42, 43] },
      { id: "unknown", name: "Узел 2604", icon: "user", color: "slate", role: "Клиент", seen: "1 ч назад", key: "!a88b2604", noKey: true }
    ],
    direct: "mira"
  },
  meshcore: {
    protocol: "MeshCore", radio: "T-Deck Plus", firmware: "Companion", band: "EU Narrow", modem: "62,5 кГц · SF8",
    chats: [
      { id: "trail", name: "Тропа", type: "channel", color: "mint", icon: "hash", mode: "Хэштег-канал", protection: "Ключ по имени канала", preview: "Антон: Вышли к просеке", time: "12:21", unread: 2 },
      { id: "anton", name: "Антон Белов", initials: "АБ", color: "blue", preview: "Дошло. Я у просеки.", time: "12:18" },
      { id: "camp", name: "Лагерь", type: "channel", icon: "lock", color: "sand", mode: "Приватный канал", protection: "Частный ключ", preview: "Ника: Возвращаемся", time: "12:04", muted: true },
      { id: "nika", name: "Ника Полевая", initials: "НП", color: "rose", preview: "Подожди у входа на тропу.", time: "11:31" },
      { id: "base", name: "Public", type: "channel", icon: "globe", color: "slate", mode: "Публичный канал", protection: "Общедоступный ключ", preview: "Роман: Слышу хорошо", time: "10:52" }
    ],
    nodes: [
      { id: "anton", name: "Антон Белов", initials: "АБ", color: "blue", role: "Контакт", seen: "3 мин назад", signal: "−6,0 дБ", key: "a81c3f", at: [58, 42] },
      { id: "ridge", name: "Перевал Relay", icon: "tower", color: "mint", role: "Ретранслятор", seen: "5 мин назад", signal: "−4,0 дБ", key: "42f954", at: [70, 49] },
      { id: "nika", name: "Ника Полевая", initials: "НП", color: "rose", role: "Контакт", seen: "17 мин назад", signal: "−9,0 дБ", key: "7a2d01", at: [33, 57] },
      { id: "room", name: "Полевой штаб", icon: "users", color: "sand", role: "Комната", seen: "28 мин назад", key: "19bc8e" },
      { id: "sensor", name: "Метеопост", icon: "activity", color: "slate", role: "Датчик", seen: "41 мин назад", key: "a03b21", discovered: true }
    ],
    direct: "anton"
  }
};

const stories = {
  meshtastic: {
    mira: [
      { text: "Мы вышли к северной тропе. Вы где сейчас?", time: "12:31" },
      { text: "У ручья. До развилки минут десять.", time: "12:33", own: true, status: "confirmed" },
      { text: "На гребне сигнал лучше. Встретимся там?", time: "12:34" },
      { text: "Да. Отметил точку на карте.", time: "12:38", own: true, status: "verified" },
      { text: "Вижу метку. Скоро будем.", time: "12:39" }
    ],
    trail: [
      { text: "У ручья скользко, лучше идти правее.", time: "12:27", author: "Илья" },
      { text: "Принял, передам остальным.", time: "12:30", own: true, status: "mesh" },
      { text: "Мы у развилки", time: "12:42", author: "Лена" }
    ]
  },
  meshcore: {
    anton: [
      { text: "Вышел к просеке. Проверишь связь?", time: "12:10" },
      { text: "Слышу. Иду по тропе от ручья.", time: "12:12", own: true, status: "confirmed" },
      { text: "Подожду у старого указателя.", time: "12:14" },
      { text: "Буду через десять минут.", time: "12:16", own: true, status: "confirmed" },
      { text: "Дошло. Я у просеки.", time: "12:18" }
    ],
    trail: [
      { text: "По низу можно пройти в обход.", time: "12:02", author: "Ника" },
      { text: "Будем у ручья в 12:30.", time: "12:06", own: true, status: "relay" },
      { text: "Вышли к просеке", time: "12:21", author: "Антон" }
    ]
  }
};

const statusInfo = {
  queued: ["clock", "В очереди", "Сообщение ждёт передачи своей рации."],
  sent: ["arrowUp", "Отправляется", "Сообщение передано своей рации. Ожидаем сведения о передаче."],
  confirmed: ["doubleCheck", "Подтверждено адресатом", "Получено подтверждение приёма от узла адресата."],
  verified: ["shieldCheck", "Приём подтверждён", "Получено проверяемое подтверждение от узла адресата."],
  mesh: ["network", "Подтверждено сетью", "Услышана ретрансляция сообщения канала. Получатели по отдельности не подтверждают приём."],
  relay: ["radio", "Ретрансляция услышана", "Своя рация услышала повтор пакета другим узлом."],
  relayOnly: ["radio", "Ретрансляция без ответа", "Пакет повторён другим узлом. Адресат пока не подтвердил приём."],
  failed: ["alert", "Нет подтверждения", "Время ожидания истекло. Можно повторить отправку."]
};
