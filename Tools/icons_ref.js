/* Эталон для визуальной сверки знаков: лист, который рисует Chromium из живой
   `beta/icons.js`. Swift-тест рисует тот же лист и сравнивает клетку с клеткой
   (Packages/LightPlanUI/Tests/LightPlanUITests/IconPixelParityTests.swift).

   Клетка 96×96 (холст 24 × 4), чёрное на белом, линия 1,5, круглые концы —
   так, как рисует лист знаков веба (`tools/icons.html`). Порядок: общий словарь,
   жанры, пожелания, имена по алфавиту — его же строит `IconLibrary` в Swift.

   Playwright берётся из соседней папки веба (`Light_Plan/node_modules`), в
   нативный репозиторий он не ставится.

   Запуск: node Tools/icons_ref.js
*/
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const ROOT = path.resolve(__dirname, "..");
function webRoot() {
  if (process.env.LIGHT_PLAN_WEB) return path.resolve(process.env.LIGHT_PLAN_WEB);
  let dir = ROOT;
  for (let i = 0; i < 8; i++) {
    const c = path.join(dir, "Light_Plan");
    if (fs.existsSync(path.join(c, "beta", "icons.js"))) return c;
    dir = path.dirname(dir);
  }
  throw new Error("не нашёл Light_Plan; задай LIGHT_PLAN_WEB");
}
const web = webRoot();
const { chromium } = require(path.join(web, "node_modules", "playwright"));

const box = {};
vm.runInNewContext(fs.readFileSync(path.join(web, "beta", "icons.js"), "utf8"), { window: box });
const I = box.ICONS;

const CELL = 96, COLS = 16, LINE = 1.5;
const common = {};
for (const g of ["points", "ui", "gear", "weather", "signs", "themes", "places"]) {
  for (const k of Object.keys(I[g])) if (!(k in common)) common[k] = I[g][k];
}
const order = [];
for (const [ns, table] of [["common", common], ["genres", I.genres], ["wishes", I.wishes]]) {
  for (const k of Object.keys(table).sort()) order.push({ ns, name: k, body: table[k] });
}
const rows = Math.ceil(order.length / COLS);

const cells = order.map((o, i) => {
  const x = (i % COLS) * CELL, y = Math.floor(i / COLS) * CELL;
  return `<svg style="position:absolute;left:${x}px;top:${y}px" width="${CELL}" height="${CELL}" viewBox="0 0 24 24">${o.body}</svg>`;
}).join("");
const html = `<!doctype html><meta charset="utf-8"><style>
html,body{margin:0;background:#fff}
svg{fill:none;stroke:#000;stroke-width:${LINE};stroke-linecap:round;stroke-linejoin:round}
</style><body style="width:${COLS * CELL}px;height:${rows * CELL}px;position:relative">${cells}</body>`;

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: COLS * CELL, height: rows * CELL }, deviceScaleFactor: 1 });
  await page.setContent(html);
  const outDir = path.join(ROOT, "Packages/LightPlanUI/Tests/LightPlanUITests");
  await page.screenshot({ path: path.join(outDir, "icons_ref.png") });
  await browser.close();
  fs.writeFileSync(path.join(outDir, "icons_ref.json"),
    JSON.stringify({ cell: CELL, cols: COLS, rows, line: LINE, order: order.map((o) => o.ns + ":" + o.name) }) + "\n");
  console.log("лист: " + order.length + " знаков, " + COLS * CELL + "×" + rows * CELL + " px");
})();
