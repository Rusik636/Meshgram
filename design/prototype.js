// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

"use strict";

const paths = {
  radio:'<path d="M4 9a12 12 0 0 1 16 0M7 12a7.5 7.5 0 0 1 10 0m-7 3a3 3 0 0 1 4 0"/><circle cx="12" cy="18" r="1" fill="currentColor" stroke="none"/>',
  mark:'<path d="M3.5 15.5 8 6l4.2 7 3.1-4.5 5.2 7"/><path d="M4 19h16"/><circle cx="17.5" cy="5" r="1.4" fill="currentColor" stroke="none"/>',
  chat:'<path d="M20 11.5a7.5 7.5 0 0 1-7.5 7.5H5l1.5-3A7.5 7.5 0 1 1 20 11.5Z"/><path d="M9 11.5h6"/>',
  users:'<circle cx="9" cy="8" r="3"/><path d="M3 20v-2a5 5 0 0 1 5-5h2a5 5 0 0 1 5 5v2m2-14a3 3 0 0 1 0 6m1 2a4 4 0 0 1 3 4v2"/>',
  user:'<circle cx="12" cy="7.5" r="3.5"/><path d="M5 20v-1.5A5 5 0 0 1 10 14h4a5 5 0 0 1 5 4.5V20"/>',
  map:'<path d="m3 6 6-2 6 2 6-2v14l-6 2-6-2-6 2V6Zm6-2v14m6-12v14"/>',
  settings:'<circle cx="12" cy="12" r="3"/><path d="m10 3-.6 2.5-2 .9-2.3-1-2.2 3.8 1.9 1.7v2.2l-1.9 1.7 2.2 3.8 2.3-1 2 .9L10 21h4l.6-2.5 2-.9 2.3 1 2.2-3.8-1.9-1.7v-2.2l1.9-1.7-2.2-3.8-2.3 1-2-.9L14 3Z"/>',
  search:'<circle cx="10.5" cy="10.5" r="5.5"/><path d="m15 15 4.5 4.5"/>',
  plus:'<path d="M12 5v14M5 12h14"/>', minus:'<path d="M5 12h14"/>',
  compose:'<path d="M12 5H6a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2v-6m-8 1.5 1-3L18 4l2 2-6.5 6.5Z"/>',
  down:'<path d="m6 9 6 6 6-6"/>', right:'<path d="m9 6 6 6-6 6"/>', back:'<path d="m14 5-7 7 7 7"/>',
  more:'<circle cx="5" cy="12" r="1" fill="currentColor"/><circle cx="12" cy="12" r="1" fill="currentColor"/><circle cx="19" cy="12" r="1" fill="currentColor"/>',
  close:'<path d="m6 6 12 12M18 6 6 18"/>',
  hash:'<path d="m10 4-3 16m10-16-3 16M5 9h15M4 15h15"/>',
  lock:'<rect x="6" y="10" width="12" height="10" rx="2"/><path d="M8 10V8a4 4 0 0 1 8 0v2m-4 4v2"/>',
  globe:'<circle cx="12" cy="12" r="8"/><path d="M4 12h16m-8-8c-3 3-3 13 0 16m0-16c3 3 3 13 0 16"/>',
  mute:'<path d="M10 6a4 4 0 0 1 6 3v3m-6 7a2 2 0 0 0 4 0M5 5l14 14m-5-3H6l1.5-3v-3"/>',
  bell:'<path d="M6 16h12l-1.5-3V9a4.5 4.5 0 0 0-9 0v4ZM10 19a2 2 0 0 0 4 0"/>',
  send:'<path d="m3 11 17-7-5.5 16-3.5-6-8-3Zm8 3 4-4"/>',
  sun:'<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/>',
  moon:'<path d="M20 15a8.5 8.5 0 0 1-11-11 8.5 8.5 0 1 0 11 11Z"/>',
  external:'<path d="M12 5h7v7m0-7-9 9m7 0v5H5V7h5"/>',
  bluetooth:'<path d="m7 7 10 10-5 4V3l5 4L7 17"/>',
  usb:'<path d="M12 20V4m-3 3 3-3 3 3m-3 9 5-3v-3m-5 7-5-3v-3"/><circle cx="12" cy="20" r="1.5"/><path d="M16 8h2v2h-2zm-10 1h2v2H6z"/>',
  network:'<circle cx="12" cy="5" r="2"/><circle cx="5" cy="18" r="2"/><circle cx="19" cy="18" r="2"/><path d="M12 7v5m0 0-7 4m7-4 7 4"/>',
  tower:'<path d="m8 21 4-10 4 10m-7-3h6M12 4v2M5 6a10 10 0 0 0 0 6m14-6a10 10 0 0 1 0 6M8 7a6 6 0 0 0 0 4m8-4a6 6 0 0 1 0 4"/>',
  activity:'<path d="M3 12h4l3-7 4 14 3-7h4"/>',
  clock:'<circle cx="12" cy="12" r="8"/><path d="M12 7v5l3 2"/>',
  check:'<path d="m5 12 4 4L19 6"/>', doubleCheck:'<path d="m2 12 4 4L16 6m-5 10L21 6"/>',
  shieldCheck:'<path d="m12 3 7 3v5c0 4-2.5 7-7 10-4.5-3-7-6-7-10V6l7-3Zm-3 9 2 2 4-4"/>',
  arrowUp:'<path d="M12 19V5m-6 6 6-6 6 6"/>',
  alert:'<circle cx="12" cy="12" r="8"/><path d="M12 8v4m0 4h.01"/>',
  signal:'<path d="M4 19v-3m5 3v-6m5 6V9m5 10V5" stroke-width="2.6"/>',
  battery:'<rect x="2" y="7" width="18" height="10" rx="2"/><path d="M22 10v4"/><rect x="4" y="9" width="13" height="6" rx=".5" fill="currentColor" stroke="none"/>',
  layers:'<path d="m3 9 9-5 9 5-9 5-9-5Zm0 4 9 5 9-5m-18 4 9 5 9-5"/>',
  pin:'<path d="M19 10c0 5-7 10-7 10s-7-5-7-10a7 7 0 1 1 14 0Z"/><circle cx="12" cy="10" r="2"/>',
  qr:'<path d="M4 4h6v6H4zm10 0h6v6h-6zM4 14h6v6H4zm10 0h2v2h-2zm4 2h2v4h-4m-2 0v-2"/>',
  link:'<path d="m10 14 4-4m-7 6-1 1a3.5 3.5 0 0 0 5 5l4-4a3.5 3.5 0 0 0 0-5m2-5 1-1a3.5 3.5 0 0 0-5-5L9 6a3.5 3.5 0 0 0 0 5" transform="translate(1 1) scale(.9)"/>',
  refresh:'<path d="M19 10a7.5 7.5 0 0 0-13-4L4 8m0-5v5h5m-4 6a7.5 7.5 0 0 0 13 4l2-2m0 5v-5h-5"/>',
  power:'<path d="M12 3v8M7 6a8 8 0 1 0 10 0"/>'
};

function icon(name) {
  return `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name] || ""}</svg>`;
}
function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, char => ({
    "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;"
  })[char]);
}
const e = escapeHtml;
const designV2 = document.documentElement.dataset.design === "v2";
const sceneLayouts = {
  overview: ["chats", "chat", "map"],
  connect: ["connect", "radios", "chat"],
  channels: ["channels", "channel", "addChannel"],
  nodes: ["nodes", "node", "map"],
  settings: ["settings", "radioSettings", "radios"]
};
const sceneNames = {overview:"Обзор", connect:"Подключение", channels:"Каналы", nodes:"Узлы", settings:"Настройки"};
const screenNames = {chats:"Список чатов", chat:"Личный чат", channel:"Чат канала", map:"Карта сети", connect:"Подключение рации", radios:"Смена рации", channels:"Список каналов", addChannel:"Добавление канала", nodes:"Список узлов", node:"Карточка узла", settings:"Настройки", radioSettings:"Настройки рации"};
const scenarios = {
  normal:"Обычная работа", first:"Первый запуск", empty:"Рации не найдены", denied:"Нет разрешения Bluetooth",
  incompatible:"Прошивка не поддерживается", offline:"Связь потеряна", failure:"Отправка без подтверждения",
  relay:"Ретрансляция без ответа", noKey:"Нет публичного ключа", noTiles:"Карта без тайлов"
};

const initial = new URLSearchParams(location.search);
const state = {
  network: initial.get("network") === "meshcore" ? "meshcore" : "meshtastic",
  theme: initial.get("theme") === "dark" ? "dark" : "light",
  scene: "overview", scenario: "normal", connected: true, hasProfile: true,
  stores: Object.fromEntries(Object.entries(profiles).map(([id, profile]) => [id, {
    chats: structuredClone(profile.chats), messages: structuredClone(stories[id]), drafts: {},
    unread: Object.fromEntries(profile.chats.map(chat => [chat.id, chat.unread || 0])), muted: {}
  }])),
  slots: []
};
let generation = 0;
let toastTimer;
const composerObservers = new WeakMap();
const mq = matchMedia(designV2 ? "(max-width:720px), (max-height:540px) and (pointer:coarse)" : "(max-width:720px)");
const byId = id => document.getElementById(id);
const profile = () => profiles[state.network];
const store = () => state.stores[state.network];

function makeSlot(screen) {
  return {screen, filter: screen === "channels" ? "channel" : "all", chatId: screen === "channel" ? "trail" : profile().direct,
    nodeId: profile().direct, mapScale: 1, transport: "ble", protocol: "auto", scan: "idle", search: null,
    sheet: null, toast: "", importText:"", importError:"", returnTo: "chats"};
}
function selectScene(scene) {
  state.scene = scene;
  state.slots = sceneLayouts[scene].map(makeSlot);
}
function setNetwork(network, fromSlot = null) {
  if (!profiles[network]) return;
  generation++;
  state.network = network;
  state.connected = true;
  state.hasProfile = true;
  state.scenario = "normal";
  state.slots.forEach(slot => {
    slot.chatId = slot.screen === "channel" ? "trail" : profile().direct;
    slot.nodeId = profile().direct;
    slot.sheet = null;
    slot.search = null;
    slot.toast = "";
  });
  if (fromSlot !== null) state.slots[fromSlot] = makeSlot("chats");
}
function setScenario(scenario) {
  generation++;
  state.scenario = scenario;
  state.connected = !["first","empty","denied","incompatible","offline"].includes(scenario);
  state.hasProfile = !["first","empty","denied","incompatible"].includes(scenario);
  const scenes = {first:"connect", empty:"connect", denied:"connect", incompatible:"connect", noTiles:"overview", noKey:"overview", offline:"overview", failure:"overview", relay:"overview"};
  selectScene(scenes[scenario] || "overview");
  if (scenario === "first") state.slots[0].scan = "idle";
  if (["empty","denied","incompatible"].includes(scenario)) state.slots[0].scan = scenario;
  if (scenario === "noKey") state.slots[mq.matches ? 0 : 1].chatId = "unknown";
  if (["offline","failure","relay","noKey"].includes(scenario) && mq.matches) state.slots[0].screen = "chat";
  if (scenario === "noTiles" && mq.matches) state.slots[0].screen = "map";
  if (scenario === "failure" || (scenario === "relay" && state.network === "meshtastic")) {
    const thread = messagesFor(profile().direct);
    const status = scenario === "failure" ? "failed" : "relayOnly";
    if (!thread.some(message => message.example === status)) {
      thread.push({text:"Подтверди, что видишь точку.", time:"12:43", own:true, status, example:status});
    }
  }
}
function getChat(id) {
  return store().chats.find(chat => chat.id === id) || profile().nodes.find(node => node.id === id) || store().chats[0];
}
function getNode(id) {
  return profile().nodes.find(node => node.id === id) || profile().nodes[0];
}
function messagesFor(id) {
  const existing = store().messages[id];
  if (existing) return existing;
  const chat = getChat(id);
  store().messages[id] = chat.preview ? [{text:chat.preview, time:chat.time}] : [];
  return store().messages[id];
}
function avatar(item, size = "") {
  return `<span class="avatar ${item.color || "slate"} ${size}" aria-hidden="true">${item.icon ? icon(item.icon) : e(item.initials || "#")}</span>`;
}
function actionButton(symbol, label, action, value = "", extra = "") {
  return `<button type="button" class="icon-button" data-action="${action}" data-value="${e(value)}" aria-label="${e(label)}" ${extra}>${icon(symbol)}</button>`;
}
function button(label, action, value = "", style = "primary full", symbol = "") {
  return `<button type="button" class="${style}" data-action="${action}" data-value="${e(value)}">${symbol ? icon(symbol) : ""}${label}</button>`;
}
function option(symbol, label, subtitle, action, value = "", end = "right", className = "sheet-option", active = false) {
  return `<button type="button" class="${className}" data-action="${action}" data-value="${e(value)}" ${active ? 'aria-current="true"' : ""}>
    <span class="device-icon">${icon(symbol)}</span><span><strong>${e(label)}</strong>${subtitle ? `<small>${e(subtitle)}</small>` : ""}</span>${icon(end)}</button>`;
}
function title(text, controls = "", back = "") {
  return `<header class="titlebar ${back ? "compact" : ""}">${back ? actionButton("back","Назад","navigate",back) : ""}<h3>${text}</h3><span class="spacer"></span>${controls}</header>`;
}
function radioStrip() {
  return `<button class="radio-strip ${state.connected ? "" : "offline"}" data-action="sheet" data-value="radios" aria-label="Выбрать рацию">
    <span class="radio-icon">${icon("radio")}</span><div><strong>${profile().protocol}</strong><small class="ellipsis">${profile().radio}</small></div>
    <span class="radio-state">${state.connected ? "На связи" : "Нет связи"}</span>${icon("down")}</button>`;
}
const tabs = {chats:["chat","Чаты"], nodes:["users","Узлы"], map:["map","Карта"], settings:["settings","Настройки"]};
function nav(active) {
  return `<nav class="tabs" aria-label="Разделы">${Object.entries(tabs).map(([id,[symbol,label]]) =>
    `<button class="nav-item" data-action="navigate" data-value="${id}" ${id === active ? 'aria-current="page"' : ""}><span class="nav-icon">${icon(symbol)}</span>${label}</button>`).join("")}</nav>`;
}
function filters(entries, current, action = "filter") {
  return `<div class="filters" role="group" aria-label="Фильтр">${entries.map(([key,label]) =>
    `<button data-action="${action}" data-value="${key}" aria-pressed="${key === current}">${label}</button>`).join("")}</div>`;
}
function empty(symbol, heading, detail, controls = "") {
  return `<div class="empty">${icon(symbol)}<strong>${heading}</strong><p>${detail}</p>${controls}</div>`;
}
function chatRow(chat) {
  const unread = store().unread[chat.id];
  const draft = store().drafts[chat.id];
  const muted = store().muted[chat.id] ?? chat.muted;
  return `<button class="row" data-action="openChat" data-value="${e(chat.id)}">${avatar(chat)}<span class="row-inner"><span class="row-copy">
    <span class="row-name"><span class="ellipsis">${e(chat.name)}</span>${muted ? icon("mute") : ""}</span>
    <span class="row-preview ellipsis">${draft ? `<span class="draft">Черновик</span> · ${e(draft)}` : e(chat.preview || chat.mode)}</span></span>
    <span class="row-meta"><span>${e(chat.time)}</span>${unread ? `<span class="badge${designV2 && muted ? " badge-muted" : ""}" aria-label="Непрочитанных: ${unread}${designV2 && muted ? ", уведомления отключены" : ""}">${unread}</span>` : ""}</span></span></button>`;
}
function chatList(slot) {
  const query = (slot.search || "").toLocaleLowerCase("ru").trim();
  const visible = store().chats.filter(chat => {
    const type = chat.type || "direct";
    return (slot.filter === "all" || type === slot.filter) && (!query || `${chat.name} ${chat.preview || ""}`.toLocaleLowerCase("ru").includes(query));
  });
  return visible.map(chatRow).join("") || empty("search", "Чаты не найдены", "Попробуйте изменить запрос.");
}
function searchField(slot) {
  return slot.search !== null || ["chats","channels","radios","addChannel"].includes(slot.screen)
    ? `<label class="search-box">${icon("search")}<input type="search" data-input="search" value="${e(slot.search)}" aria-label="Поиск" placeholder="Поиск по чатам"></label>` : "";
}
function chatsScreen(slot) {
  const isChannels = slot.screen === "channels";
  return title(isChannels ? "Каналы" : "Чаты", actionButton(isChannels ? "plus" : "compose",isChannels ? "Добавить канал" : "Новый чат","sheet",isChannels ? "addChannel" : "compose")) + searchField(slot) + radioStrip()
    + filters([["all","Все"],["direct","Личные"],["channel","Каналы"]], slot.filter)
    + `<div class="scroll list-with-tabs" data-results>${chatList(slot)}</div>` + nav("chats");
}
function adjacentMessages(first, second) {
  if (!first || !second || Boolean(first.own) !== Boolean(second.own) || first.author !== second.author || first.date !== second.date) return false;
  const minute = time => time.split(":").reduce((total,part) => total * 60 + Number(part),0);
  const gap = minute(second.time) - minute(first.time);
  return gap >= 0 && gap <= 5;
}
function bubble(message, index, previous, next) {
  const info = statusInfo[message.status];
  const grouped = designV2 ? adjacentMessages(previous,message) : previous && previous.own === message.own && previous.author === message.author;
  const joinsNext = designV2 && adjacentMessages(message,next);
  return `<article class="bubble ${message.own ? "own" : ""} ${grouped ? "grouped" : ""} ${joinsNext ? "joins-next" : ""}">
    ${message.author && !grouped ? `<b>${e(message.author)}</b>` : ""}<span>${e(message.text)}</span>
    <div class="bubble-meta"><time>${e(message.time)}</time>${info ? `<button class="message-status ${message.status}" data-action="messageStatus" data-value="${index}" aria-label="${e(info[1])}" title="${e(info[1])}">${icon(info[0])}</button>` : ""}</div>
  </article>`;
}
function messageLimit(chat) {
  if (state.network === "meshtastic") return 200;
  if (chat.type !== "channel") return 156;
  return 160 - Math.min(new TextEncoder().encode("Алекс").length, 31) - 2;
}
function chatScreen(slot) {
  const chat = getChat(slot.chatId);
  const isChannel = chat.type === "channel";
  const node = profile().nodes.find(item => item.id === chat.id);
  const messages = messagesFor(chat.id);
  const blocked = !state.connected || node?.noKey;
  const max = messageLimit(chat);
  const draft = store().drafts[chat.id] || "";
  const bytes = new TextEncoder().encode(draft).length;
  const subtitle = isChannel ? chat.mode : node?.seen ? `В эфире ${node.seen}` : "Личный чат";
  const context = state.connected ? `${profile().protocol} · ${profile().radio}` : "Нет связи с рацией";
  return `<header class="titlebar compact conversation-heading">${actionButton("back","Назад","navigate",slot.returnTo)}
    <button class="chat-heading" data-action="${isChannel || !node ? "sheet" : "node"}" data-value="${isChannel || !node ? "chatMenu" : e(chat.id)}"><h3 class="ellipsis">${e(chat.name)}</h3><small class="ellipsis">${e(subtitle)}</small></button>
    ${actionButton("more","Действия чата","sheet","chatMenu")}</header>
    <button class="chat-link ${state.connected ? "" : "warning"}" data-action="sheet" data-value="radios">${icon(state.connected ? "radio" : "alert")}<span class="ellipsis">${context}</span>${state.connected ? icon("down") : "<b>Подключить</b>"}</button>
    <div class="scroll chat-scroll" data-chat-scroll>${wallpaper}<div class="messages">
      ${messages.length ? '<span class="date-chip">Сегодня</span>' : empty("chat","Сообщений пока нет","Напишите первым.")}
      ${messages.map((message,index) => bubble(message,index,messages[index-1],messages[index+1])).join("")}</div></div>
    <form class="composer" data-composer><div class="composer-row">
      ${actionButton("plus","Действия при вводе","sheet","composer")}<div class="composer-box">
      <textarea data-input="draft" rows="1" aria-label="Сообщение" placeholder="Сообщение">${e(draft)}</textarea></div>
      <button type="submit" class="send-button" aria-label="Отправить" ${blocked || bytes > max || !draft.trim() ? "disabled" : ""}>${icon("send")}</button>
    </div><div class="composer-note ${bytes > max ? "over" : ""}" aria-live="polite" data-counter>${node?.noKey ? "Ожидаем публичный ключ узла" : !state.connected ? "Черновик сохраняется в этой рации" : bytes > max ? `Лимит превышен · ${bytes} / ${max} байт` : ""}</div></form>`;
}

function contour(x, y, radius, ratio, phase = 0) {
  const points = Array.from({length:81}, (_, index) => {
    const angle = index / 80 * Math.PI * 2;
    const warp = 1 + .13 * Math.sin(angle * 3 + phase) + .075 * Math.cos(angle * 5 - phase) + .04 * Math.sin(angle * 7);
    return `${(x + Math.cos(angle) * radius * warp).toFixed(1)},${(y + Math.sin(angle) * radius * warp * ratio).toFixed(1)}`;
  });
  return `M${points.join("L")}Z`;
}
const wallpaper = `<svg class="wallpaper" viewBox="0 0 360 410" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width=".65">
  ${Array.from({length:12}, (_,i) => `<path d="${contour(330,90,19+i*13,1.0,1.2)}"/><path d="${contour(40,383,20+i*14,.68,2.1)}"/>`).join("")}</g></svg>`;
const mapArt = `<svg class="map-art" viewBox="0 0 360 470" preserveAspectRatio="none" aria-label="Схема местности с северной тропой и ручьём" role="img">
  <path fill="var(--map-forest)" d="M0 0h185l9 36-22 62 16 58-25 65-76 17-36-30-51 16Zm360 175-53 24-39 55-14 58 30 36-15 50-20 72h111Z" opacity=".72"/>
  <g class="contours">${Array.from({length:14}, (_,i) => `<path d="${contour(72,103,17+i*10,1.05,1.2)}"/><path d="${contour(330,291,15+i*9,1.32,2.0)}"/><path d="${contour(75,444,16+i*10,.65,2.3)}"/>`).join("")}</g>
  <path class="river" d="M193-20c-12 58 20 74 11 111-9 34-29 62-21 98 7 30 61 50 55 81-5 41-72 50-85 91-10 32 33 68 27 129"/>
  <path class="road" d="M-20 363c73-32 97-62 124-108 24-40 60-52 72-87 15-41-14-90 15-128 15-18 29-29 43-51"/>
  <path class="track" d="M53 319c24-29 47-70 86-96 40-26 63-55 78-67 31-13 51 22 69 70 11 29 53 39 82 39"/>
  <text x="71" y="121" transform="rotate(-12 71 121)">Северный склон</text><text x="193" y="132" transform="rotate(75 193 132)">Ручей</text>
  <text x="196" y="198" transform="rotate(18 196 198)">Северная тропа</text><text x="56" y="339">К лагерю</text>
</svg>`;
function nodeRow(node) {
  return `<button class="row" data-action="node" data-value="${e(node.id)}">${avatar(node)}<span class="row-inner"><span class="row-copy">
    <span class="row-name ellipsis">${e(node.name)}</span><span class="row-preview ellipsis">${node.role} · ${node.seen}</span></span>
    <span class="row-meta">${e(node.signal || "")}${icon("right")}</span></span></button>`;
}
function mapScreen(slot) {
  const node = getNode(slot.nodeId);
  const noTiles = state.scenario === "noTiles";
  return `<div class="map-header">${title("Карта",actionButton("layers","Слои карты","sheet","map"))}</div>
    <div class="map-view"><div class="map-canvas" style="--map-scale:${slot.mapScale}">
    ${noTiles ? "" : mapArt}
    ${profile().nodes.filter(item => item.at).map(item => `<button class="pin ${node.id === item.id ? "active" : ""}" data-action="mapPin" data-value="${e(item.id)}" style="--x:${item.at[0]}%;--y:${item.at[1]}%" aria-label="${e(item.name)}"><span>${icon(item.icon || "user")}</span></button>`).join("")}</div>
    <button class="map-mode" data-action="sheet" data-value="map">${icon("layers")}${noTiles ? "Без подложки" : "Офлайн-карта"}</button>
    <div class="map-zoom">${actionButton("plus","Приблизить","zoom",1)}${actionButton("minus","Отдалить","zoom",-1)}</div>
    ${noTiles ? `<div class="map-empty">${empty("map","Нет сохранённой карты","Метки с известными координатами доступны поверх пустой подложки.")}</div>` : ""}
    <div class="map-card">${nodeRow(node)}</div></div>${nav("map")}`;
}
function nodeList(slot) {
  const query = (slot.search || "").toLowerCase().trim();
  const matching = {
    all: () => true,
    clients: node => ["Клиент","Контакт"].includes(node.role),
    other: node => !["Клиент","Контакт"].includes(node.role),
    discovered: node => node.discovered
  };
  return profile().nodes.filter(node => (!query || `${node.name} ${node.key}`.toLowerCase().includes(query)) && matching[slot.filter](node))
    .map(nodeRow).join("") || empty("search","Узлы не найдены","Попробуйте другой запрос или фильтр.");
}
function nodesScreen(slot) {
  const entries = [["all","Все"],["clients","Контакты"],["other","Другие"]];
  if (state.network === "meshcore") entries.push(["discovered","Обнаружены"]);
  return title("Узлы", actionButton("search","Поиск узлов","search")) + radioStrip() + searchField(slot)
    + filters(entries,slot.filter)
    + `<div class="scroll list-with-tabs" data-results>${nodeList(slot)}</div>` + nav("nodes");
}
function nodeScreen(slot) {
  const node = getNode(slot.nodeId);
  const canChat = ["Клиент","Контакт"].includes(node.role);
  return `<header class="titlebar compact">${actionButton("back","Назад","nodeBack")}<h3>Узел</h3></header><div class="scroll settings-list">
    <div class="settings-group"><div class="node-intro">${avatar(node,"large")}<h3>${e(node.name)}</h3><p>${node.role} · ${profile().protocol}<br>В эфире ${node.seen}</p></div>
    ${canChat ? button("Открыть чат","openChat",node.id,"primary full","chat") : ""}
    ${node.role === "Ретранслятор" ? button("Управление ретранслятором","sheet","repeater","primary full","tower") : ""}
    ${node.at ? button("Показать на карте","navigate","map","secondary full","pin") : ""}</div>
    <div class="settings-group"><p class="subheading">Последний пакет</p>${node.signal || node.rssi ? `<div class="metrics">
    ${[["SNR",node.signal],["RSSI",node.rssi]].filter(([,value])=>value).map(([key,value])=>`<div class="metric"><small>${key}</small><strong>${value}</strong></div>`).join("")}</div>` : '<p class="sheet-text">Метрики сигнала не получены.</p>'}
    ${option("network","Идентификатор узла",node.key,"sheet","nodeId","right","setting")}</div>
    ${node.noKey ? empty("lock","Публичного ключа пока нет","Личное сообщение станет доступно после получения ключа узла.") : ""}
    </div>`;
}
const transports = {ble:["bluetooth","Bluetooth"],usb:["usb","USB"],tcp:["network","TCP"]};

function connectScreen(slot) {
  const selected = slot.protocol === "auto" ? Object.entries(profiles) : [[slot.protocol,profiles[slot.protocol]]];
  const symbol = transports[slot.transport][0];
  const result = {
    idle:empty(symbol,"Поиск поблизости","Включите рацию и держите её рядом с телефоном."),
    scanning:empty("radio","Ищем рации…","Bluetooth запущен."),
    pairing:empty("lock","Сопряжение…","Если рация попросит PIN, введите его в системном окне."),
    syncing:empty("refresh","Синхронизируем рацию…","Загружаем конфигурацию и список узлов."),
    empty:empty("search","Рации не найдены","Проверьте питание и Bluetooth на рации, затем повторите поиск."),
    denied:empty("lock","Нет доступа к Bluetooth","Разрешите доступ к Bluetooth в настройках телефона.",button("Разрешить в демо","scan","","secondary")),
    incompatible:empty("alert","Прошивка не поддерживается","Устройство должно работать на Meshtastic или MeshCore Companion.")
  }[slot.scan];
  const connectButton = ["scanning","pairing","syncing"].includes(slot.scan) ? ""
    : button(slot.transport === "ble" ? "Искать устройства" : "Подключить",slot.transport === "ble" ? "scan" : "transportConnect","","primary full",symbol);
  return title("Подключение",actionButton("settings","Выбрать протокол","sheet","protocol"),state.hasProfile ? "chats" : "") +
    `<div class="scroll"><div class="connect-intro"><span class="device-icon">${icon("radio")}</span><h3>Подключите рацию</h3>
    <p>Выберите, как телефон подключится к рации.</p></div>
    ${filters(Object.entries(transports).map(([id,[,label]])=>[id,label]),slot.transport,"transport")}
    ${slot.protocol !== "auto" ? `<p class="subheading">${profiles[slot.protocol].protocol}</p>` : ""}
    ${slot.transport === "tcp" ? '<label class="field"><input data-input="host" placeholder="IP-адрес и порт" aria-label="IP-адрес и порт"></label>' : ""}
    ${slot.transport === "usb" ? '<p class="sheet-text">Доступность USB зависит от ОС, кабеля и прошивки.</p>' : ""}
    ${slot.scan === "results" ? `<p class="subheading">Найденные устройства</p>${selected.map(([id,item])=>option(symbol,item.radio,`${item.protocol} · BLE`,"pair",id)).join("")}` : result}
    ${connectButton}</div>`;
}
function settingsScreen() {
  return title("Настройки") + radioStrip() + `<div class="scroll settings-list list-with-tabs">
    <div class="settings-group"><p class="subheading">Приложение</p>
    ${option("sun","Оформление",state.theme === "dark" ? "Тёмная тема" : "Светлая тема","sheet","theme","right","setting")}
    ${option("bell","Уведомления","Личные сообщения и каналы","sheet","notifications","right","setting")}</div>
    <div class="settings-group"><p class="subheading">Рация</p>
    ${option("radio","Мои рации",profile().radio,"sheet","radios","right","setting")}
    ${option("settings","Настройки рации",profile().protocol,"navigate","radioSettings","right","setting")}
    ${option("hash","Каналы","Управление каналами","navigate","channels","right","setting")}</div></div>` + nav("settings");
}
function radioSettingsScreen() {
  const p = profile();
  const rows = [["radio","Прошивка",p.firmware],["globe","Регион и профиль",p.band],["activity","Радиопараметры",p.modem]];
  return title("Настройки рации","","settings") + radioStrip() + `<div class="scroll settings-list"><div class="settings-group">
    <p class="subheading">Применяется к ${p.radio}</p>
    ${rows.map(([symbol,label,value])=>option(symbol,label,value,"detail",label,"right","setting")).join("")}
    ${p.protocol === "Meshtastic" ? option("network","Роль устройства","Клиент","detail","Роль устройства","right","setting")
    : option("tower","Управление ретрансляторами","Доступно из карточки совместимого узла","navigate","nodes","right","setting")}</div></div>`;
}
function sceneScreen(slot) {
  if (["chats","channels","radios","addChannel"].includes(slot.screen)) return chatsScreen(slot);
  if (["chat","channel"].includes(slot.screen)) return chatScreen(slot);
  if (slot.screen === "connect") return connectScreen(slot);
  if (slot.screen === "map") return mapScreen(slot);
  if (slot.screen === "nodes") return nodesScreen(slot);
  if (slot.screen === "node") return nodeScreen(slot);
  if (slot.screen === "settings") return settingsScreen();
  return radioSettingsScreen();
}
function activeSheet(slot) {
  return slot.sheet || (slot.screen === "radios" ? "radios" : slot.screen === "addChannel" ? "addChannel" : null);
}
function channelChoices() {
  const meshtastic = state.network === "meshtastic";
  const types = meshtastic ? [["hash","Дополнительный канал"],["lock","Канал с частным ключом"]]
    : [["globe","Публичный канал"],["hash","Хэштег-канал"],["lock","Приватный канал"],["users","Сообщество"]];
  return types.map(([symbol,label])=>option(symbol,label,"","createChannel",label))
    .join("") + option("qr","Импорт из QR или ссылки","Выбрать совместимую рацию","sheet","import");
}
function sheetContents(kind, slot) {
  const chat = getChat(slot.chatId);
  if (kind === "radios") return ["Мои рации",
    Object.entries(profiles).map(([id,item]) => option("radio",item.radio,
      `${item.protocol} · ${state.network === id && state.connected ? "Подключена" : "Сохранена"}`,
      "switchRadio",id,state.network === id && state.connected ? "check" : "right","sheet-option",state.network === id && state.connected)).join("")
    + '<div class="sheet-divider"></div>'
    + option("plus","Добавить рацию","","navigate","connect")
    + (state.connected ? option("power","Отключиться",profile().radio,"disconnect") : "")];
  if (kind === "protocol") return ["Протокол",
    [["auto","Определить автоматически"],["meshtastic","Meshtastic"],["meshcore","MeshCore"]].map(([id,label]) =>
      option("radio",label,"","chooseProtocol",id,slot.protocol === id ? "check" : "right")).join("")];
  if (kind === "compose") return ["Новый чат",option("user","Личное сообщение","Выбрать узел","navigate","nodes") + option("hash","Добавить канал","","sheet","addChannel")];
  if (kind === "addChannel") return ["Добавить канал",`<p class="sheet-text">${profile().protocol} · ${profile().radio}</p>${channelChoices()}`];
  if (kind === "channelForm") return [e(slot.channelType),`<form data-channel-form><label class="field"><input name="channel" aria-label="Название канала" placeholder="Название канала" required></label>
    <button class="primary full" type="submit">Добавить в демо</button></form>`];
  if (kind === "import") return ["Импорт канала",`<p class="sheet-text">Вставьте ссылку из QR-кода или выберите демоссылку.</p>
    <form data-import-form><label class="field"><input name="link" data-input="import" placeholder="Ссылка на канал" aria-label="Ссылка на канал" value="${e(slot.importText)}"></label>
    ${slot.importError ? `<p class="sheet-error" role="alert">${e(slot.importError)}</p>` : ""}<button class="primary full" type="submit">Проверить ссылку</button></form>
    ${option("link","Демо Meshtastic","","fillImport","meshtastic")}${option("link","Демо MeshCore","","fillImport","meshcore")}`];
  if (kind === "importSwitch") return ["Сменить рацию?",`<p class="sheet-text">Эта ссылка относится к ${profiles[slot.importNetwork].protocol}. Выберите ${profiles[slot.importNetwork].radio}, чтобы продолжить импорт.</p>
    ${button(`Выбрать ${profiles[slot.importNetwork].radio}`,"finishImport",slot.importNetwork)}`];
  if (kind === "messageStatus") {
    const message = messagesFor(chat.id)[slot.messageIndex];
    const info = statusInfo[message.status];
    const canRetry = ["failed","relayOnly"].includes(message.status);
    const canTrace = ["confirmed","verified","relay","mesh","relayOnly"].includes(message.status);
    return [info[1],`<p class="sheet-text">${info[2]}</p>${canRetry ? button("Повторить отправку","retry",slot.messageIndex) : ""}
      ${canTrace ? option("network","Детали маршрута",profile().protocol,"sheet","route") : ""}`];
  }
  if (kind === "chatMenu") {
    const muted = store().muted[chat.id] ?? chat.muted;
    return [chat.name,`${chat.type === "channel" ? `<p class="sheet-text">${chat.mode} · ${chat.protection || profile().protocol}</p>` : ""}
      ${option(muted ? "bell" : "mute",muted ? "Включить уведомления" : "Выключить уведомления","","mute")}
      ${option("network","Детали маршрута",profile().protocol,"sheet","route")}`];
  }
  if (kind === "composer") return ["Действия",option("map","Открыть карту","","navigate","map") + option("network","Детали маршрута","","sheet","route")];
  if (kind === "route") return ["Детали маршрута",`<p class="sheet-text">${profile().protocol} · ${profile().radio}</p>
    ${state.network === "meshcore"
      ? '<p class="sheet-text">Последний известный путь пакета · 1 переход, 42f954. Маршрут может измениться.</p>'
      : '<p class="sheet-text">Для этого пакета нет записанного маршрута. Трассировка узла — отдельный запрос к сети.</p>'}`];
  if (kind === "map") return ["Слои карты",
    option("layers",state.scenario === "noTiles" ? "Без подложки" : "Офлайн-карта","Схема местности","toggleMap","tiles","check")
    + option("pin","Узлы выбранного профиля",profile().protocol,"close")];
  if (kind === "theme") return ["Оформление",
    option("sun","Светлая тема","","theme","light",state.theme === "light" ? "check" : "right")
    + option("moon","Тёмная тема","","theme","dark",state.theme === "dark" ? "check" : "right")];
  if (kind === "notifications") return ["Уведомления",'<p class="sheet-text">Включайте и отключайте уведомления отдельно в меню каждого чата.</p>'];
  if (kind === "nodeId") return ["Идентификатор узла",`<p class="sheet-text">${e(getNode(slot.nodeId).key)} · ${profile().protocol}</p>`];
  if (kind === "repeater") return ["Управление ретранслятором",`<p class="sheet-text">${e(getNode(slot.nodeId).name)} · ${profile().protocol}. Для управления нужен пароль узла.</p>
    <label class="field"><input type="password" placeholder="Пароль узла" aria-label="Пароль узла" autocomplete="off"></label>
    ${button("Посмотреть демонастройки","sheet","repeaterSettings")}`];
  if (kind === "repeaterSettings") return ["Настройки ретранслятора",`<p class="sheet-text">${e(getNode(slot.nodeId).name)} · Демоданные</p>
    ${option("activity","Телеметрия","Напряжение 4,1 В","close")}
    ${option("radio","Параметры LoRa",profile().modem,"close")}`];
  return [slot.detail || "Настройка",`<p class="sheet-text">${profile().protocol} · ${profile().radio}</p><p class="sheet-text">Параметр показан в режиме просмотра.</p>`];
}
function sheet(slot,index) {
  const kind = activeSheet(slot);
  if (!kind) return "";
  const [heading, contents] = sheetContents(kind,slot);
  return `<div class="sheet-shade"><button class="sheet-bg" data-action="close" aria-hidden="true" tabindex="-1"></button>
    <section class="sheet" role="dialog" aria-modal="true" aria-labelledby="sheet-${index}">
      <div class="sheet-head"><h3 id="sheet-${index}">${heading}</h3>${actionButton("close","Закрыть","close")}</div>${contents}
    </section></div>`;
}

function getPhone(index) { return document.querySelector(`[data-slot="${index}"] .phone`); }
function fitComposer(unit, scroll) {
  composerObservers.get(unit)?.disconnect();
  const composer = unit.querySelector(".composer");
  if (!composer) return;
  const update = () => {
    if (!composer.offsetHeight) return;
    const nearEnd = scroll.scrollHeight - scroll.clientHeight - scroll.scrollTop < 40;
    scroll.style.setProperty("--composer-clearance", `${composer.offsetHeight + 10}px`);
    if (nearEnd) scroll.scrollTop = scroll.scrollHeight;
  };
  const observer = new ResizeObserver(update);
  observer.observe(composer);
  composerObservers.set(unit,observer);
  update();
}
function renderPhone(index) {
  const slot = state.slots[index];
  const unit = getPhone(index);
  const scroll = unit.querySelector(".scroll");
  const previousScroll = scroll?.scrollTop || 0;
  const stickToBottom = !scroll || slot.scrollToEnd || scroll.scrollHeight - scroll.clientHeight - previousScroll < 45;
  const selected = unit.contains(document.activeElement) && document.activeElement.dataset.input
    ? [document.activeElement.dataset.input,document.activeElement.selectionStart,document.activeElement.selectionEnd] : null;
  const content = sceneScreen(slot);
  const overlay = sheet(slot,index);
  unit.previousElementSibling.textContent = screenNames[slot.screen];
  unit.innerHTML = `<div class="statusbar" aria-hidden="true"><span>12:42</span><i></i><span>${icon("signal")}${icon("battery")}</span></div>
    <div class="screen screen-${slot.screen}" ${overlay ? "inert" : ""}>${content}</div><div class="home-line" aria-hidden="true"></div>${overlay}
    ${slot.toast ? `<p class="toast" role="status">${e(slot.toast)}</p>` : ""}`;
  if (slot.focusSheet && overlay) unit.querySelector(".sheet button")?.focus({preventScroll:true});
  if (slot.focusReturn && !overlay) {
    const {action,value} = slot.focusReturn;
    [...unit.querySelectorAll("[data-action]")].find(item => item.dataset.action === action && item.dataset.value === value)?.focus({preventScroll:true});
    slot.focusReturn = null;
  }
  slot.focusSheet = false;
  if (selected && !slot.scrollToEnd && (!overlay || activeSheet(slot) === "import")) {
    const input = unit.querySelector(`[data-input="${selected[0]}"]`);
    if (input) {
      input.focus({preventScroll:true});
      if (selected[1] !== null) input.setSelectionRange(selected[1], selected[2]);
    }
  }
  const currentScroll = unit.querySelector(".scroll");
  fitComposer(unit,currentScroll);
  if (currentScroll && unit.querySelector("[data-chat-scroll]")) {
    currentScroll.scrollTop = stickToBottom ? currentScroll.scrollHeight : previousScroll;
  } else if (currentScroll && !slot.scrollToEnd) {
    currentScroll.scrollTop = previousScroll;
  }
  slot.scrollToEnd = false;
}
function renderStudio() {
  document.documentElement.dataset.theme = state.theme;
  byId("theme-control").innerHTML = [["light","sun","Светлая тема"],["dark","moon","Тёмная тема"]].map(([value,symbol,label])=>
    `<button data-action="theme" data-value="${value}" aria-label="${label}" aria-pressed="${state.theme === value}">${icon(symbol)}</button>`).join("");
  byId("protocol-control").innerHTML = Object.entries(profiles).map(([id,item]) =>
    `<button data-action="studioNetwork" data-value="${id}" aria-pressed="${state.network === id}">${item.protocol}</button>`).join("");
  byId("scenes").innerHTML = Object.entries(sceneNames).map(([key,label]) =>
    `<button data-action="scene" data-value="${key}" aria-pressed="${state.scene === key}">${label}</button>`).join("");
  const menu = byId("demo-state");
  if (!menu.options.length) menu.innerHTML = Object.entries(scenarios).map(([id,label])=>`<option value="${id}">${label}</option>`).join("");
  menu.querySelector('[value="noKey"]').hidden = state.network !== "meshtastic";
  menu.querySelector('[value="relay"]').hidden = state.network !== "meshtastic";
  menu.value = state.scenario;
}
function renderAll() {
  renderStudio();
  state.slots.forEach((_,index) => renderPhone(index));
}
function openSheet(slot,kind) {
  slot.sheet = kind;
  slot.focusSheet = true;
}
function closeSheet(slot) {
  if (slot.screen === "radios") slot.screen = "chats";
  if (slot.screen === "addChannel") slot.screen = "channels";
  slot.sheet = null;
  slot.focusReturn = slot.sheetTrigger || null;
  slot.sheetTrigger = null;
}
function navigate(slot,screen) {
  const mapId = slot.nodeId;
  const replacement = makeSlot(screen);
  if (screen === "map") replacement.nodeId = mapId;
  Object.assign(slot,replacement,{scrollToEnd:true});
}
function notify(slot,message) {
  slot.toast = message;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    state.slots.forEach(item => { item.toast = ""; });
    document.querySelectorAll(".toast").forEach(element => element.remove());
  },2400);
}
function simulateScan(slot,index) {
  slot.scan = "scanning";
  const captured = generation;
  setTimeout(() => {
    if (state.slots[index] !== slot || generation !== captured || slot.screen !== "connect" || slot.scan !== "scanning") return;
    slot.scan = "results";
    renderPhone(index);
  },540);
}
function pair(slot,index,network) {
  slot.scan = "pairing";
  const token = ++generation;
  setTimeout(() => {
    if (state.slots[index] !== slot || generation !== token || slot.screen !== "connect") return;
    slot.scan = "syncing";
    renderPhone(index);
    setTimeout(() => {
      if (state.slots[index] !== slot || generation !== token || slot.screen !== "connect") return;
      setNetwork(network,index);
      renderAll();
    },390);
  },420);
}
function currentTime() {
  return new Intl.DateTimeFormat("ru",{hour:"2-digit",minute:"2-digit"}).format(new Date());
}
function dispatchMessage(chat,message, retry = false) {
  const origin = state.network;
  const token = generation;
  const disposition = retry ? "normal" : state.scenario;
  message.status = "queued";
  const refresh = () => {
    if (state.network !== origin) return;
    state.slots.forEach((slot,index) => {
      if ((["chat","channel"].includes(slot.screen) && slot.chatId === chat.id) || ["chats","channels"].includes(slot.screen)) renderPhone(index);
    });
  };
  setTimeout(() => {
    if (generation !== token || !state.connected) {
      message.status = "failed";
      refresh();
      return;
    }
    message.status = "sent";
    refresh();
    setTimeout(() => {
      if (generation !== token || !state.connected) message.status = "failed";
      else if (disposition === "failure") message.status = "failed";
      else if (chat.type === "channel") message.status = origin === "meshtastic" ? "mesh" : "relay";
      else if (disposition === "relay" && origin === "meshtastic") message.status = "relayOnly";
      else message.status = origin === "meshtastic" ? "verified" : "confirmed";
      refresh();
    },660);
  },360);
}
function submitMessage(slot) {
  const chat = getChat(slot.chatId);
  const text = (store().drafts[chat.id] || "").trim();
  if (!text || !state.connected || chat.noKey || new TextEncoder().encode(text).length > messageLimit(chat)) return;
  const message = {text,time:currentTime(),own:true,status:"queued"};
  messagesFor(chat.id).push(message);
  const listEntry = store().chats.find(item => item.id === chat.id);
  if (listEntry) Object.assign(listEntry,{preview:text,time:message.time});
  store().drafts[chat.id] = "";
  slot.scrollToEnd = true;
  dispatchMessage(chat,message);
}
function openChat(slot,id) {
  const from = slot.screen;
  const chat = getChat(id);
  slot.screen = chat.type === "channel" ? "channel" : "chat";
  slot.chatId = chat.id;
  slot.returnTo = ["chats","channels","nodes","map"].includes(from) ? from : "chats";
  slot.sheet = null;
  slot.scrollToEnd = true;
  store().unread[chat.id] = 0;
}
function createChannel(slot,name,type = "") {
  const id = `demo-${Date.now()}`;
  store().chats.unshift({id,name,type:"channel",icon:"hash",color:"mint",mode:type || (state.network === "meshtastic" ? "Дополнительный канал" : "Хэштег-канал"),preview:"Канал добавлен",time:currentTime()});
  store().messages[id] = [];
  openChat(slot,id);
}

document.addEventListener("click",event => {
  const control = event.target.closest("[data-action]");
  if (!control) return;
  const {action,value} = control.dataset;
  const card = control.closest("[data-slot]");
  if (!card) {
    const groupId = control.parentElement.id;
    if (action === "theme") state.theme = value;
    if (action === "studioNetwork") { setNetwork(value); selectScene(state.scene); }
    if (action === "scene") selectScene(value);
    renderAll();
    const group = groupId && byId(groupId);
    group && [...group.querySelectorAll("button")].find(button => button.dataset.value === value)?.focus({preventScroll:true});
    return;
  }
  const index = Number(card.dataset.slot);
  const slot = state.slots[index];
  const previousSheet = activeSheet(slot);
  switch (action) {
    case "sheet":
      if (!previousSheet) slot.sheetTrigger = {action,value};
      openSheet(slot,value);
      break;
    case "close": closeSheet(slot); break;
    case "navigate": navigate(slot,value); break;
    case "filter": slot.filter = value; break;
    case "transport": slot.transport = value; slot.scan = "idle"; break;
    case "chooseProtocol": slot.protocol = value; closeSheet(slot); break;
    case "search": slot.search = slot.search === null ? "" : null; break;
    case "openChat": openChat(slot,value); break;
    case "node":
      slot.nodeFrom = slot.screen;
      slot.screen = "node";
      slot.nodeId = value;
      slot.sheet = null;
      break;
    case "nodeBack":
      slot.screen = slot.nodeFrom || "nodes";
      slot.scrollToEnd = slot.screen === "chat";
      break;
    case "mapPin": slot.nodeId = value; break;
    case "zoom": slot.mapScale = Math.min(1.6,Math.max(.85,slot.mapScale + Number(value)*.15)); break;
    case "toggleMap": state.scenario = state.scenario === "noTiles" ? "normal" : "noTiles"; closeSheet(slot); renderAll(); return;
    case "scan": simulateScan(slot,index); break;
    case "pair": pair(slot,index,value); break;
    case "transportConnect": {
      const host = card.querySelector('[data-input="host"]');
      if (host && !host.value.trim()) { notify(slot,"Укажите IP-адрес рации и порт."); break; }
      pair(slot,index,slot.protocol === "auto" ? state.network : slot.protocol);
      break;
    }
    case "switchRadio": setNetwork(value,index); renderAll(); return;
    case "disconnect":
      generation++;
      state.connected = false;
      state.scenario = "offline";
      closeSheet(slot);
      renderAll();
      return;
    case "messageStatus":
      slot.messageIndex = Number(value);
      slot.sheetTrigger = {action,value};
      openSheet(slot,"messageStatus");
      break;
    case "retry": {
      if (!state.connected) { openSheet(slot,"radios"); break; }
      const chat = getChat(slot.chatId);
      dispatchMessage(chat,messagesFor(chat.id)[Number(value)],true);
      closeSheet(slot);
      break;
    }
    case "mute": {
      const chat = getChat(slot.chatId);
      const muted = store().muted[chat.id] ?? chat.muted;
      store().muted[chat.id] = !muted;
      closeSheet(slot);
      notify(slot,muted ? "Уведомления включены" : "Уведомления выключены");
      renderAll();
      return;
    }
    case "theme":
      state.theme = value;
      closeSheet(slot);
      renderAll();
      return;
    case "detail": slot.detail = value; openSheet(slot,"detail"); break;
    case "createChannel": slot.channelType = value; openSheet(slot,"channelForm"); break;
    case "fillImport":
      slot.importText = value === "meshcore" ? "meshcore://channel/add?name=Тропа&demo=1" : "https://meshtastic.org/e/#demo-meshgrame";
      slot.importError = "";
      break;
    case "finishImport":
      setNetwork(value,index);
      createChannel(state.slots[index],"Импортированный канал");
      renderAll();
      return;
    default: return;
  }
  renderPhone(index);
  if (action === "search" && slot.search !== null) card.querySelector('[data-input="search"]')?.focus();
});
document.addEventListener("change",event => {
  if (event.target.id === "demo-state") {
    setScenario(event.target.value);
    renderAll();
  }
});
document.addEventListener("input",event => {
  const input = event.target;
  const index = Number(input.closest("[data-slot]")?.dataset.slot);
  const slot = state.slots[index];
  if (!slot) return;
  if (input.dataset.input === "search") {
    slot.search = input.value;
    getPhone(index).querySelector("[data-results]").innerHTML = slot.screen === "nodes" ? nodeList(slot) : chatList(slot);
  }
  if (input.dataset.input === "import") slot.importText = input.value;
  if (input.dataset.input === "draft") {
    const chat = getChat(slot.chatId);
    store().drafts[chat.id] = input.value;
    const bytes = new TextEncoder().encode(input.value).length;
    const max = messageLimit(chat);
    const counter = getPhone(index).querySelector("[data-counter]");
    counter.classList.toggle("over",bytes > max);
    counter.textContent = chat.noKey ? "Ожидаем публичный ключ узла" : !state.connected ? "Черновик сохраняется в этой рации"
      : bytes > max ? `Лимит превышен · ${bytes} / ${max} байт` : bytes > max * .72 ? `${bytes} / ${max} байт` : "";
    getPhone(index).querySelector(".send-button").disabled = !state.connected || Boolean(chat.noKey) || bytes > max || !input.value.trim();
  }
});
document.addEventListener("submit",event => {
  const form = event.target;
  const index = Number(form.closest("[data-slot]")?.dataset.slot);
  const slot = state.slots[index];
  if (!slot) return;
  event.preventDefault();
  if (form.matches("[data-composer]")) {
    submitMessage(slot);
    renderAll();
    getPhone(index).querySelector('[data-input="draft"]')?.focus({preventScroll:true});
  }
  if (form.matches("[data-channel-form]")) {
    const name = new FormData(form).get("channel").trim();
    if (!name) return;
    createChannel(slot,name,slot.channelType);
    renderAll();
  }
  if (form.matches("[data-import-form]")) {
    const link = slot.importText.trim();
    const network = /^meshcore:\/\/channel\/add\?/i.test(link) ? "meshcore" : /^https:\/\/meshtastic\.org\/e\/#/i.test(link) ? "meshtastic" : "";
    if (!network) slot.importError = "Формат ссылки не распознан.";
    else if (network !== state.network) {
      slot.importNetwork = network;
      openSheet(slot,"importSwitch");
    } else createChannel(slot,"Импортированный канал");
    renderAll();
  }
});
document.addEventListener("keydown",event => {
  const index = Number(event.target.closest("[data-slot]")?.dataset.slot);
  const slot = state.slots[index];
  if (!slot || !activeSheet(slot)) return;
  if (event.key === "Escape") {
    event.preventDefault();
    closeSheet(slot);
    renderPhone(index);
  }
  if (event.key === "Tab") {
    const items = [...getPhone(index).querySelectorAll(".sheet :is(button,input,select,a):not([disabled])")];
    if (event.shiftKey && event.target === items[0]) { event.preventDefault(); items.at(-1)?.focus(); }
    if (!event.shiftKey && event.target === items.at(-1)) { event.preventDefault(); items[0]?.focus(); }
  }
});

byId("brand-icon").innerHTML = icon("mark");
byId("spec-icon").innerHTML = icon("external");
selectScene("overview");
if (scenarios[initial.get("state")] && initial.get("state") !== "normal") setScenario(initial.get("state"));
if (initial.get("first") === "1") setScenario("first");
renderAll();
