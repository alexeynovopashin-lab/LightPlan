/* Эталон для итерации 21 (планировщик): колонки ленты дня и шкала срочности
   сдачи. Пишет Fixtures/planner.json.

   Отдельным файлом и своим отпечатком, как domain.js: общий `BLOCKS` стенда
   не трогается, параллельные итерации не перебивают друг другу фикстуры.
   Код не копируется — режется из живого `beta/index.html`:
   - раскладка колонок — от строки `var LANE_GAP = 4;` до конца её
     самовызова `})();` внутри `renderDayPanel`; исполняется над `items`
     и `topOf`, как в приложении (`HOUR_H` — из той же функции);
   - `urgencyRGB`, `lerp` — функции целиком, по имени, `clamp` — строкой
     `var clamp = function`; `theme`
     подставляется тёмной и светлой темой.

   Случаи колонок — 400 дней по 1–7 блоков на сетке 15 минут, длительность
   5–80 минут (короткие проверяют нижнюю высоту блока), занятость на весь
   день — фоном. Генератор псевдослучайный с постоянным зерном: прогон
   повторяется побайтово.

   Запуск:  node Tools/parity/planner.js [--out Fixtures] [--quiet]
*/
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const crypto = require("crypto");
const X = require("./extract.js");

const args = process.argv.slice(2);
const outDir = args.includes("--out") ? args[args.indexOf("--out") + 1] : path.join(X.ROOT, "Fixtures");
const quiet = args.includes("--quiet");

const main = X.mainScript();

function between(from, toRe) {
  const i = main.indexOf(from);
  if (i < 0) throw new Error("planner.js: нет начала «" + from + "» в beta/index.html");
  const rest = main.slice(i);
  const m = toRe.exec(rest);
  if (!m) throw new Error("planner.js: нет конца после «" + from + "»");
  return rest.slice(0, m.index + m[0].length);
}

/* Функция целиком по имени: от `function имя(` до парной скобки. */
function fn(name) {
  const head = "function " + name + "(";
  const i = main.indexOf(head);
  if (i < 0) throw new Error("planner.js: нет функции " + name);
  let depth = 0, j = main.indexOf("{", i);
  for (; j < main.length; j++) {
    if (main[j] === "{") depth++;
    else if (main[j] === "}" && --depth === 0) break;
  }
  return main.slice(i, j + 1);
}

const lanes = between("var LANE_GAP = 4;", /\n\s*\}\)\(\);/);
const hourH = /var HOUR_H = (\d+);/.exec(main);
if (!hourH) throw new Error("planner.js: нет HOUR_H");
const urgency = [between("var clamp = function", /;\n/), fn("lerp"), fn("urgencyRGB")].join("\n");
const digest = crypto.createHash("sha256").update(lanes).update(hourH[0]).update(urgency)
  .digest("hex").slice(0, 16);

// --- колонки ---
let seed = 7;
const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
const layLanes = new vm.Script(lanes);
const cases = [];
for (let c = 0; c < 400; c++) {
  const n = 1 + Math.floor(rnd() * 7), items = [];
  for (let i = 0; i < n; i++) {
    const kind = rnd() < 0.15 ? "busy" : "shoot";
    const all = kind === "busy" && rnd() < 0.3;
    const a = all ? 0 : Math.floor(rnd() * 96) * 15;
    const d = all ? 1440 : (1 + Math.floor(rnd() * 16)) * 5;
    items.push({ kind, a, b: Math.min(1440, a + d), blk: kind === "busy" ? { allDay: all } : undefined });
  }
  items.sort((x, y) => x.a - y.a || x.b - y.b);
  const H = +hourH[1];
  layLanes.runInNewContext({ items, topOf: (m) => (m / 60) * H, Math });
  cases.push({
    items: items.map((x) => ({ kind: x.kind, a: x.a, b: x.b, all: !!(x.blk && x.blk.allDay) })),
    col: items.map((x) => (x.col === undefined ? -1 : x.col)),
    cols: items.map((x) => (x.cols === undefined ? -1 : x.cols)),
  });
}

// --- шкала срочности ---
const scale = [];
for (const theme of ["dark", "light"]) {
  const ctx = { theme, Math };
  vm.runInNewContext(urgency, ctx);
  for (let k = -2; k <= 22; k++) {
    const p = k / 20;
    scale.push({ theme, p, rgb: ctx.urgencyRGB(p) });
  }
}

const out = { source: digest, hourHeight: +hourH[1], lanes: cases, urgency: scale };
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, "planner.json"), JSON.stringify(out) + "\n");
if (!quiet) console.log("  planner.json: колонок " + cases.length + ", шкала " + scale.length + ", отпечаток " + digest);
