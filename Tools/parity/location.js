/* Эталон для итерации 13 (локация): режет чистые правила места из беты и пишет
   Fixtures/location.json.

   Отдельным файлом и отдельным отпечатком, а не блоками общего стенда: общий
   `BLOCKS` меняет отпечаток всех фикстур разом, а итерации 9а/14/15 идут
   параллельно и правят те же файлы. Приём тот же — код не копируется, а
   режется из живого `beta/index.html` по якорным строкам (см. extract.js).

   Что режется: cleanPlace (чистка имени), sameSpot и uniqueSpotName
   (закладки), coordText (подпись координатами), tzFor и zoneKey (оценка пояса
   по долготе, ключ кэша зон). Что не режется и не переносится: settlement и
   isCity — они читают ответ BigDataCloud, а натив спрашивает CLGeocoder;
   разбор его ответа проверяется записанными замерами, а не веб-кодом.

   Запуск:  node Tools/parity/location.js [--out Fixtures] [--quiet]
*/
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const crypto = require("crypto");
const { mainScript, webPath, ROOT } = require("./extract.js");

const BLOCKS = {
  home:       { from: "var HOME_LON = 37.48, HOME_TZ = 3;", to: "\n" },
  tzFor:      { from: "function tzFor(lon) {", to: "\n" },
  zoneKey:    { from: "function zoneKey(lat, lon) {", to: "function zoneOf(lat, lon, onReady) {" },
  coordText:  { from: "function coordText(lat, lon) {", to: "/* Имя места — обратное геокодирование" },
  cleanPlace: { from: "function cleanPlace(n) {", to: "/* Совпадение имени города с именем региона" },
  uniqueSpot: { from: "function uniqueSpotName(base) {", to: "/* Две точки считаем одной" },
  sameSpot:   { from: "function sameSpot(a, lat, lon) {", to: "function spotHere() {" },
};

function cut(name) {
  const b = BLOCKS[name], main = mainScript();
  const i = main.indexOf(b.from);
  if (i < 0) throw new Error("блок «" + name + "»: не найдено начало — якорь\n  " + b.from +
    "\nБета изменилась здесь: чинить якорь в Tools/parity/location.js, не фикстуры (" + webPath() + ")");
  const j = main.indexOf(b.to, i + b.from.length);
  if (j < 0) throw new Error("блок «" + name + "»: не найден конец — якорь\n  " + b.to);
  return main.slice(i, j);
}

const NAMES = Object.keys(BLOCKS);
const digest = (() => {
  const h = crypto.createHash("sha256");
  for (const n of NAMES) { h.update(n); h.update(cut(n)); }
  return h.digest("hex").slice(0, 16);
})();

function load() {
  const ctx = vm.createContext({ Math, Number, String, Array, Object, JSON, spots: [] });
  for (const n of NAMES) vm.runInContext(cut(n), ctx, { filename: "beta/index.html:" + n });
  return ctx;
}

/* ---------- Входы ---------- */

/* Строки: то, что отдают геокодеры, и то, что отдал CLGeocoder 21.09.2026
   (замер на десяти точках, см. DECISIONS «Локация»). */
const CLEAN = [
  "", " ", "Москва", "Лобня", "  Лобня  ", "Санкт-Петербург", "Нью-Дели", "Nevşehir Merkez", "Берлин", "Барселона",
  "Томск", "Казань", "Севастополь",
  "Городской округ город Томск", "Городской округ Томск", "Городской Округ Томск", "Городской Округ Город Казань",
  "Городской Округ Лобня", "Дмитровский городской округ", "Зольский район", "Московская область",
  "Московская Область", "Томская область", "Татарстан", "Республика Татарстан", "Чувашская Республика",
  "Красноярский край", "Ханты-Мансийский автономный округ — Югра", "Якутия улус", "Мегино-Кангаласский улус",
  "Место не определено", "Неизвестно", "неизвестное место", "Unknown", "UNKNOWN place",
  "город Томск", "посёлок Листвянка", "поселок Листвянка", "село Иваново", "деревня Ивановка",
  "станица Вёшенская", "хутор Ленина", "аул Кызыл", "слобода Большая",
  "город томск", "город Санкт-Петербург, Россия", "Округ город Томск", "Городское поселение Лобня",
  "Лобня, Московская область", "сельсовет Ивановский", "муниципальное образование Лобня",
  "Город Казань", "Нью-Йорк", "New York", "İstanbul", "東京都", "Ürgüp",
  "посёлок  Листвянка", "посёлок Листвянка\n", "\tМосква\t", "деревня ", "город Ё", "село ёлки",
];

const FIXED = [
  [0, 0], [-0, -0], [56.011, 37.483], [56.489, 84.952], [-33.8688, 151.2093], [59.9343, -30.3351],
  [0.0625, 0.1875], [0.0005, -0.0005], [1.0005, -1.0005], [0.3125, 0.4375], [89.9999, 179.9999],
  [-89.9995, -179.9995], [-0.0004, 0.0004], [56.0114999, 37.4835001], [12.3455, 12.3445], [55.7558, 37.6173],
  [28.6139, 77.209], [41.3874, 2.1686], [38.6431, 34.8289], [-0.0006, 0.0006], [10, 20], [-10, -20],
  [2.0005, 2.0015], [0.0015, 0.0025], [1.005, 1.015], [8.5, -8.5], [0.0000001, -0.0000001],
];

function grid(lo, hi, step) { const a = []; for (let v = lo; v <= hi + 1e-9; v += step) a.push(+v.toFixed(6)); return a; }

const SAME = (() => {
  const out = [], base = [56.011, 37.483];
  const d = [0, 0.0001, 0.0005, 0.00059, 0.0006, 0.00061, 0.001, -0.0001, -0.0005, -0.0006, -0.00061, 0.0005999999, 0.0006000001];
  for (const dl of d) for (const dn of d) out.push([base[0], base[1], base[0] + dl, base[1] + dn]);
  out.push([0, 0, 0.0006, 0], [0, 0, 0, 0.0006], [-45.5, -120.25, -45.5006, -120.2506], [89.9995, 179.9995, 89.9999, -179.9999]);
  return out;
})();

const ZONE_POINTS = [
  [0, 0], [-0.25, -0.25], [-0.5, -0.5], [-0.75, -0.75], [-1.25, -1.25], [-1.5, -1.5], [0.25, 0.25], [0.75, 0.75],
  [56.011, 37.483], [56.489, 84.952], [56.25, 84.75], [-33.8688, 151.2093], [59.9343, -30.3351], [28.6139, 77.209],
  [-89.999, -179.999], [89.999, 179.999], [12.24999, 12.25], [12.25001, -12.25001], [41.3874, 2.1686],
];

const LONS = (() => {
  const a = grid(-180, 180, 0.37);
  for (const k of [-12, -11, -1, 0, 1, 5, 6, 12]) a.push(37.48 + 15 * k + 7.5, 37.48 + 15 * k + 7.4999, 37.48 + 15 * k - 7.5, 37.48 + 15 * k - 7.5001);
  a.push(-180, 180, 0, 37.48, 84.952, 151.2093, 2.1686);
  return a;
})();

const UNIQUE = [
  { base: "Лобня", names: [] },
  { base: "Лобня", names: ["Лобня"] },
  { base: "Лобня", names: ["Лобня", "Лобня 2"] },
  { base: "Лобня", names: ["Лобня", "Лобня 2", "Лобня 7", "Лобня 3"] },
  { base: "Лобня", names: ["Лобня 2"] },
  { base: "Лобня", names: ["Лобня Центр", "Лобня 2x", "Лобня  2", "Лобня 02"] },
  { base: "Лобня", names: ["Лобня 02"] },
  { base: "Лобня", names: ["Лобня 1"] },
  { base: "Лобня", names: ["лобня"] },
  { base: "Лобня", names: [""] },
  { base: "", names: ["", "Лобня"] },
  { base: "Томск", names: ["Томск", "Томск 10", "Томск 9"] },
  { base: "Дели", names: ["Нью-Дели", "Дели 2"] },
  { base: "Дели", names: ["Дели ", "Дели 4 "] },
  { base: "Sao Paulo", names: ["Sao Paulo", "Sao Paulo 12"] },
];

function build() {
  const c = load();
  const one = (f, ...a) => f.apply(null, a);
  const out = {};
  out.home = { lon: c.HOME_LON, tz: c.HOME_TZ };
  out.clean = CLEAN.map(s => ({ in: s, out: one(c.cleanPlace, s) }));
  out.cleanNull = [null, undefined].map((v, i) => ({ in: i === 0 ? "null" : "undefined", out: one(c.cleanPlace, v) }));
  out.fixed = FIXED.map(([la, lo]) => ({ lat: la, lon: lo, text: one(c.coordText, la, lo),
    key3: la.toFixed(3) + "," + lo.toFixed(3) }));
  out.same = SAME.map(([a, b, la, lo]) => ({ a: [a, b], b: [la, lo], same: !!one(c.sameSpot, { lat: a, lon: b }, la, lo) }));
  out.zoneKey = ZONE_POINTS.map(([la, lo]) => ({ lat: la, lon: lo, key: one(c.zoneKey, la, lo) }));
  out.tzFor = LONS.map(lo => ({ lon: lo, tz: one(c.tzFor, lo) }));
  out.unique = UNIQUE.map(u => {
    c.spots = u.names.map(n => ({ name: n }));
    return { base: u.base, names: u.names, out: one(c.uniqueSpotName, u.base) };
  });
  /* Сторож самого эталона: значения, выведенные из описанных правил руками */
  const must = (cond, msg) => { if (!cond) throw new Error("самопроверка эталона: " + msg); };
  must(c.cleanPlace("Городской округ город Томск") === "Томск", "«Городской округ город Томск» → Томск");
  must(c.cleanPlace("Зольский район") === "", "район — не место");
  must(c.cleanPlace("Место не определено") === "", "заглушка геокодера — не место");
  must(c.coordText(56.011, 37.483) === "56.011 N · 37.483 E", "подпись координатами");
  must(c.tzFor(84.952) === 6, "оценка по долготе для Томска — +6 (веб про этот промах знает, реальный пояс +7)");
  must(c.sameSpot({ lat: 1, lon: 1 }, 1.0005, 1) && !c.sameSpot({ lat: 1, lon: 1 }, 1.0007, 1), "допуск 60 м");
  return out;
}

const argv = process.argv.slice(2);
const outDir = path.resolve(ROOT, argv.includes("--out") ? argv[argv.indexOf("--out") + 1] : "Fixtures");
const body = build();
const file = {
  meta: {
    source: "beta/index.html", cut: digest,
    what: "чистка имени места, закладки (60 м, нумерация), подпись координатами, оценка пояса, ключ кэша зон",
    blocks: NAMES, count: Object.keys(body).reduce((n, k) => n + (Array.isArray(body[k]) ? body[k].length : 1), 0),
  },
  ...body,
};
const text = JSON.stringify(file, null, 1) + "\n";
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, "location.json"), text);
if (!argv.includes("--quiet")) {
  console.log("эталон: " + webPath());
  console.log("  location.json  " + file.meta.count + " проб, отпечаток " + digest + ", " + text.length + " байт");
}
