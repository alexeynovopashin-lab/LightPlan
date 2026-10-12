/* Эталон неба при включении «Астро» (шаг 29.9): Fixtures/constellations.json.
   Подключается из generate.js и пишется тем же `write`.

   Что здесь исполняется. Каталог — `window.SKY` из живого `beta/sky.js`.
   Расстановка — САМ `buildAstroSky` беты, вырезанный по якорям и запущенный
   с заглушкой `$` (она ловит `innerHTML`) и подменой «сейчас»: копии формулы
   в нативном проекте нет, а в стенде нет своей. Из разметки, которую бета
   положила бы в слой, читаются числа: какие созвездия, где точки и нити,
   где луна. Рядом — alt/az КАЖДОЙ звезды каталога (`eqToAltAz` беты).

   Часы. Луну бета берёт по часам телефона (`getHours`) и поясу места (`TZ`):
   совпадают они — луна на месте. Стенд считается в UTC, поэтому `TZ = 0`;
   разные пояса телефона и места сдвинули бы луну беты на разницу — это
   особенность беты, а не то, что переносится.

   Сетка. Пять мест (Томск, Москва, нуль широты, Сидней — южное полушарие,
   Лонгйир — у полюса) × шесть моментов (день и ночь, четыре сезона, секунды
   не круглые). */
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const PLACES = [
  { name: "Томск", lat: 56.4847, lon: 84.9482 },
  { name: "Москва", lat: 55.7558, lon: 37.6173 },
  { name: "Нуль широты", lat: 0, lon: 37 },
  { name: "Сидней", lat: -33.8688, lon: 151.2093 },
  { name: "Лонгйир", lat: 78.2232, lon: 15.6267 },
];
const MOMENTS = ["2026-01-15T00:00:00Z", "2026-03-20T12:00:30Z", "2026-06-21T18:30:15Z",
  "2026-09-23T03:17:45Z", "2026-10-12T14:20:00Z", "2026-12-21T21:00:10Z"];

function skyCatalog(X) {
  const file = path.join(X.webRoot(), "beta", "sky.js");
  const win = {};
  vm.runInNewContext(fs.readFileSync(file, "utf8"), { window: win });
  if (!Array.isArray(win.SKY) || !win.SKY.length) throw new Error("beta/sky.js: нет window.SKY");
  return win.SKY;
}

/* buildAstroSky по якорям: от объявления до `showAstroSky`, как у остальных блоков */
function astroBlock(X) {
  const main = X.mainScript();
  const from = "function buildAstroSky() {", to = "function showAstroSky() {";
  const i = main.indexOf(from);
  if (i < 0) throw new Error("блок astroSky: не найдено начало «" + from + "»");
  const j = main.indexOf(to, i);
  if (j < 0) throw new Error("блок astroSky: не найден конец «" + to + "»");
  return main.slice(i, j);
}

function attrs(tag) {
  const o = {};
  tag.replace(/([a-z0-9-]+)="([^"]*)"/g, function (_, k, v) { o[k] = v; return ""; });
  return o;
}

function build(ctxUnused, X) {
  const SKY = skyCatalog(X);
  const block = astroBlock(X);
  const cases = [];
  for (const p of PLACES) {
    for (const iso of MOMENTS) {
      const ms = Date.parse(iso);
      const ctx = X.load(["helpers", "moon", "milkyway"], { lat: p.lat, lon: p.lon, tz: 0 });
      let html = null;
      /* «Сейчас» подменено: `new Date()` без аргументов отдаёт заданный момент */
      class FixedDate extends Date {
        constructor(...a) { if (a.length) super(...a); else super(ms); }
      }
      ctx.Date = FixedDate;
      ctx.SKY = SKY; ctx.window = { SKY: SKY };
      ctx.$ = function () { return { set innerHTML(v) { html = v; } }; };
      vm.runInContext(block, ctx, { filename: "beta/index.html:astroSky" });
      ctx.buildAstroSky();
      if (html === null) throw new Error("buildAstroSky не записал разметку: " + iso);

      const lines = [], stars = [];
      let moon = null;
      (html.match(/<(line|circle|g)\b[^>]*>/g) || []).forEach(function (tag) {
        const a = attrs(tag);
        if (a.class === "as-line") lines.push([+a.x1, +a.y1, +a.x2, +a.y2]);
        else if (a.class === "as-star") stars.push([+a.cx, +a.cy, +a.r, +/animation-delay:([0-9.]+)s/.exec(a.style)[1]]);
        else if (a.class === "as-moon") {
          const m = /translate\(([-0-9.]+),([-0-9.]+)\) scale\(1\.1\)/.exec(a.transform);
          moon = [+m[1] + 13, +m[2] + 13];
        }
      });
      const d = ctx.toDays(new FixedDate());
      const up = SKY.filter(function (c) {
        return c.s.every(function (st) { return ctx.eqToAltAz(st[0] * Math.PI / 12, ctx.rad(st[1]), d).alt > 1; });
      }).map(function (c) { return c.n; });
      const altaz = [];
      SKY.forEach(function (c) {
        c.s.forEach(function (st) {
          const q = ctx.eqToAltAz(st[0] * Math.PI / 12, ctx.rad(st[1]), d);
          altaz.push([q.alt, q.az]);
        });
      });
      cases.push({ place: p.name, lat: p.lat, lon: p.lon, at: iso, ms: ms, d: d,
        up: up, altaz: altaz, stars: stars, lines: lines, moon: moon });
    }
  }
  const catalog = SKY.map(function (c) { return { n: c.n, s: c.s, l: c.l }; });
  return {
    meta: {
      what: "небо при включении «Астро»: каталог созвездий, alt/az каждой звезды, какие созвездия целиком над горизонтом, точки, нити и луна как их кладёт buildAstroSky",
      grid: "5 мест × 6 моментов; каталог — window.SKY из beta/sky.js; TZ места 0 (часы телефона и места совпадают)",
      tolerance: { altaz: "1e-9°", up: "строго", stars: "x, y до 0,1 (toFixed 1), r и задержка до 0,01", lines: "строго", moon: "строго, null — под горизонтом" },
      count: cases.length,
    },
    body: { catalog: catalog, cases: cases },
  };
}

module.exports = { build };
