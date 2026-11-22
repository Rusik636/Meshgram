// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

"use strict";

const libraryRoot = document.documentElement;
const materialControl = document.getElementById("material-control");
const materialMode = new URLSearchParams(location.search).get("material");
materialControl.checked = materialMode === "opaque";
function applyMaterial() {
  libraryRoot.dataset.material = materialControl.checked ? "opaque" : "glass";
}
applyMaterial();
materialControl.addEventListener("change",applyMaterial);

for (const demoProfile of Object.values(state.stores)) demoProfile.unread.camp = 2;
renderAll();

const paletteItems = [["surface","Поверхность"],["accent","Действие"],["outgoing","Исходящее"],
  ["online-surface","Подключено"],["warning-surface","Внимание"],["error-surface","Ошибка"]];
document.getElementById("palette").innerHTML = '<h3>Палитра</h3><div class="swatches">' + paletteItems
  .map(([key,label]) => `<div class="swatch"><span style="--sample:var(--mg-color-${key})"></span>${label}</div>`).join("") + "</div>";
document.getElementById("radio-catalog").innerHTML = [["Meshtastic","На связи","online"],["MeshCore","Нет связи","offline"]]
  .map(([name,label,kind]) => `<div class="radio-sample ${kind}">${icon("radio")}<strong>${name}</strong><span class="radio-state">${label}</span></div>`).join("");
document.getElementById("status-catalog").innerHTML = ["queued","sent","verified","mesh","relayOnly","failed"]
  .map(status => `<p data-status="${status}">${icon(statusInfo[status][0])}${statusInfo[status][1]}</p>`).join("");
document.getElementById("bubble-catalog").innerHTML = [
  {text:"Слышу тебя.",time:"12:30"}, {text:"Вижу северный склон.",time:"12:31"},
  {text:"Жду у развилки.",time:"12:33",own:true}
].map((message, index, list) => bubble(message,index,list[index-1],list[index+1])).join("");
