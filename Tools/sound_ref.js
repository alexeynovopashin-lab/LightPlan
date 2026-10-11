/* Эталон звуков беты (29.6). Берёт из живой `beta/index.html` по якорям:
   `CLICK_B64`, таблицу `PI_D`, функции `tickClick()` и `swoosh()` — и ПРОГОНЯЕТ их
   настоящий код на заглушке Web Audio, записывая `playbackRate` и `gain` каждого
   щелчка (все 96 шагов таблицы π и круг по новой) и `gain` затвора.

   Результат — Packages/LightPlanUI/Tests/LightPlanUITests/sound_ref.json:
   SoundTests сверяет с ним `SoundCenter` и хэш `click.wav` из ресурсов.
   `--check` ничего не пишет: сверяет файл-эталон с живой бетой и ресурс с
   декодированием `CLICK_B64` побайтно (exit 1 на расхождении).

   Запуск: node Tools/sound_ref.js [--check]   (из ворктри: LIGHT_PLAN_WEB=<Light_Plan>)
*/
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const crypto = require("crypto");

const ROOT = path.resolve(__dirname, "..");
function webRoot() {
  if (process.env.LIGHT_PLAN_WEB) return path.resolve(process.env.LIGHT_PLAN_WEB);
  let dir = ROOT;
  for (let i = 0; i < 8; i++) {
    const c = path.join(dir, "Light_Plan");
    if (fs.existsSync(path.join(c, "beta", "index.html"))) return c;
    dir = path.dirname(dir);
  }
  throw new Error("не нашёл Light_Plan; задай LIGHT_PLAN_WEB");
}
const html = fs.readFileSync(path.join(webRoot(), "beta", "index.html"), "utf8");
const check = process.argv.includes("--check");

function between(from, to) {
  const a = html.indexOf(from);
  if (a < 0) throw new Error("якорь не найден: " + from);
  const b = html.indexOf(to, a);
  if (b < 0) throw new Error("якорь не найден: " + to);
  return html.slice(a, b);
}

const b64 = /var CLICK_B64 = "([A-Za-z0-9+/=]+)"/.exec(html)[1];
const wav = Buffer.from(b64, "base64");
const sha = crypto.createHash("sha256").update(wav).digest("hex");

// Настоящий код беты: таблица π, initAudio, tickClick, swoosh — на заглушке Web Audio.
const code = between("var PI_D =", "/* Корзина звучала спуском");
const played = [];
const ctx = {
  navigator: {},
  $: () => ({ classList: { contains: () => true } }),
  audioCtx: null, clickBuf: null, shutterBuf: null,
  lastTick: null, viewMin: 0, TICK_MIN: 60,
};
vm.createContext(ctx);
vm.runInContext(code, ctx);
ctx.audioCtx = {
  state: "running", destination: {},
  createBufferSource() {
    const s = { buffer: null, playbackRate: { value: 1 }, connect() {}, start() { played.push(s); } };
    return s;
  },
  createGain() { const g = { gain: { value: 1 }, connect() {} }; return g; },
};
// Заглушки узлов: перехватываем `gain` по цепочке source → gain.
const gains = [];
const origGain = ctx.audioCtx.createGain;
ctx.audioCtx.createGain = function () { const g = origGain(); gains.push(g); return g; };
ctx.clickBuf = {}; ctx.shutterBuf = {};

const piDigits = vm.runInContext("PI_D", ctx);
const steps = [];
const N = piDigits.length / 2;
for (let i = 0; i < N + 2; i++) {            // круг и два шага по новой — проверка оборота
  const before = vm.runInContext("piTick", ctx);
  played.length = 0; gains.length = 0;
  vm.runInContext("tickClick()", ctx);
  steps.push({
    at: before,
    pa: piDigits.charCodeAt(before) - 48,
    pb: piDigits.charCodeAt(before + 1) - 48,
    rate: played[0].playbackRate.value,
    gain: gains[0].gain.value,
  });
}
played.length = 0; gains.length = 0;
vm.runInContext("swoosh()", ctx);
const shutterGain = gains[0].gain.value;

// Смятие бумаги (`trashSound`, 29.7): записанный `TRASH_B64` и громкость — тем же способом, настоящим кодом беты.
const tb64 = /var TRASH_B64 = "([A-Za-z0-9+/=]+)"/.exec(html)[1];
const trashWav = Buffer.from(tb64, "base64");
const trashSha = crypto.createHash("sha256").update(trashWav).digest("hex");
const trashCtx = {
  navigator: {}, $: () => ({ classList: { contains: () => true } }), trashBuf: {},
  audioCtx: null,
};
vm.createContext(trashCtx);
vm.runInContext(between("function trashSound()", "/* Копия данных"), trashCtx);
const trashGains = [];
trashCtx.audioCtx = {
  state: "running", destination: {},
  createBufferSource() { return { buffer: null, connect() {}, start() {} }; },
  createGain() { const g = { gain: { value: 1 }, connect() {} }; trashGains.push(g); return g; },
};
vm.runInContext("trashSound()", trashCtx);
const trashGain = trashGains[0].gain.value;

const ref = { clickSha256: sha, clickBytes: wav.length, piDigits, steps, shutterGain,
  trashSha256: trashSha, trashBytes: trashWav.length, trashGain };
const out = path.join(ROOT, "Packages/LightPlanUI/Tests/LightPlanUITests/sound_ref.json");
const res = path.join(ROOT, "Packages/LightPlanUI/Sources/LightPlanUI/Resources/Sound/click.wav");
const json = JSON.stringify(ref, null, 1) + "\n";

if (check) {
  let bad = 0;
  if (fs.readFileSync(out, "utf8") !== json) { console.log("sound_ref.json расходится с бетой"); bad++; }
  if (!fs.readFileSync(res).equals(wav)) { console.log("click.wav не равен CLICK_B64 побайтно"); bad++; }
  const tres = path.join(path.dirname(res), "trash.wav");
  if (!fs.existsSync(tres) || !fs.readFileSync(tres).equals(trashWav)) { console.log("trash.wav не равен TRASH_B64 побайтно"); bad++; }
  console.log(bad ? "FAIL" : `ok: click.wav ${wav.length} байт, sha256 ${sha.slice(0, 16)}…, шагов ${steps.length}, затвор ${shutterGain}, смятие ${trashWav.length} байт, gain ${trashGain}`);
  process.exit(bad ? 1 : 0);
}
fs.writeFileSync(out, json);
console.log(`записал ${path.relative(ROOT, out)}: шагов ${steps.length}, затвор ${shutterGain}, sha256 ${sha.slice(0, 16)}…`);
