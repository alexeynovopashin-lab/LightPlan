/* Эталон для итерации 14: строки словаря и форматы даты, часов, денег.

   Пишет два файла рядом с остальными фикстурами:
     Fixtures/lang.json    — что `LANG.t`, `word`, `count`, `sep` отдают по каждому
                             ключу и языку (читает `lang.js` веба целиком);
     Fixtures/format.json  — что отдают даты, часы, число, деньги и градусы
                             (слой режется из `beta/index.html`, как у соседей).

   Отдельный файл от `generate.js` намеренно: у слоя текста своя сетка, свои
   якоря и ни одного общего блока с математикой неба. Сшивать их значило бы
   дёргать чужой стенд каждой правкой словаря.

   Что считает эталон. `Intl` узла (ICU из его сборки), а не «правильный»
   ответ: цель — русский экран и экраны остальных языков, какими их видит веб.
   Расхождение Swift с этим эталоном — не приговор ни одной из сторон, а
   строка в таблице расхождений (DECISIONS, «Форматы текста в нативе»).

   Язык узла: ICU в Node полный (`full-icu`) начиная с 13-й версии. Проверка
   ниже падает, если это не так.

   Пример:
     make lang
     TZ=UTC node Tools/parity/lang.js --out Fixtures
*/
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const crypto = require("crypto");
const X = require("./extract.js");

if (new Date(2026, 0, 1).getTimezoneOffset() !== 0 ||
    new Date(2026, 6, 1).getTimezoneOffset() !== 0) {
  console.error("Запускать только в UTC: `TZ=UTC node Tools/parity/lang.js` или `make lang`.\n" +
    "Даты берутся местными, и в другом поясе фикстура зависела бы от машины.");
  process.exit(2);
}

const argv = process.argv.slice(2);
const OUT = argv.includes("--out") ? argv[argv.indexOf("--out") + 1] : "Fixtures";
const QUIET = argv.includes("--quiet");
const log = (s) => { if (!QUIET) console.log(s); };

/* Языки экрана: коды `LANG.code`, как их видит `Intl` в вебе. */
const LANGS = ["ru", "en-GB", "en-US", "es", "ja", "zh"];
/* Плюс «en» без говора — есть в словаре, но на экран не попадает: сохранённый
   выбор «en» веб превращает в «en-GB». Для строк берём все семь словарей. */
const DICT_CODES = ["ru", "en", "en-GB", "en-US", "es", "ja", "zh"];

/* ---------- Словарь ---------- */

function loadLang() {
  const file = path.join(X.webRoot(), "beta", "lang.js");
  const text = fs.readFileSync(file, "utf8");
  const g = vm.createContext({
    navigator: { language: "ru-RU" },
    document: { documentElement: {} },
    localStorage: { getItem: () => null, setItem: () => {} },
  });
  vm.runInContext(text, g, { filename: file });
  return { LANG: g.LANG, digest: crypto.createHash("sha256").update(text).digest("hex").slice(0, 16) };
}

/* Значения для подстановки: имя в угловых скобках. Так видно, что подставилось
   именно оно и на своё место, а порядок слов в языке не сбивает проверку. */
function varsOf(str) {
  const v = {};
  (str.match(/\{(\w+)\}/g) || []).forEach((m) => { const n = m.slice(1, -1); v[n] = "<" + n + ">"; });
  return v;
}

/* Числа для проверки склонения: границы всех правил (0, 1, 2–4, 5, 11–14,
   21, 22, 25, 100, 101, 111–114, 1000, 1001) и большое. */
const N = [0, 1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 14, 15, 20, 21, 22, 24, 25, 100, 101, 102, 111, 112, 113, 114, 121, 1000, 1001, 1002, 1011];

function buildLang() {
  const { LANG, digest } = loadLang();
  const dict = LANG.dict;
  const keys = [...new Set([...Object.keys(dict.ru), ...Object.keys(dict.en)])].sort();
  const plural = keys.filter((k) => DICT_CODES.some((c) => Array.isArray(dict[c][k])));

  const withVars = keys.filter((k) => Object.keys(varsOf(String(
    Array.isArray(dict.ru[k]) ? dict.ru[k][0] : dict.ru[k]))).length > 0);
  const subst = {};
  withVars.forEach((k) => {
    const src = DICT_CODES.map((c) => dict[c][k]).filter((x) => x != null).map((x) => Array.isArray(x) ? x[0] : x);
    const v = {};
    src.forEach((s) => Object.assign(v, varsOf(s)));
    subst[k] = v;
  });

  const langs = {};
  for (const code of DICT_CODES) {
    if (!LANG.set(code)) throw new Error("веб не принимает язык " + code);
    const t = keys.map((k) => LANG.t(k));
    const forms = {};
    plural.forEach((k) => {
      forms[k] = {
        word: N.map((n) => LANG.word(k, n)),
        count: N.map((n) => LANG.count(k, n)),
        sep: LANG.sep(k),
        index: N.map((n) => LANG.index(n)),
      };
    });
    const sub = {};
    Object.keys(subst).forEach((k) => { sub[k] = LANG.t(k, subst[k]); });
    langs[code] = { t: t, plural: forms, subst: sub, has: LANG.has(code), known: LANG.known(code) };
  }
  return {
    meta: { source: "beta/lang.js", sha: digest, keys: keys.length, plural: plural.length, n: N },
    keys: keys, pluralKeys: plural, substVars: subst, langs: langs,
  };
}

/* ---------- Форматы ---------- */

/* Слой дат и часов: от первого `dtfCache` до `sameDay`. Внутри — и `fmt` с
   `range`, и `fmtHTML`; вне — только `esc` и `LANG.code`. */
const FORMAT_BLOCKS = {
  dates: { from: "var dtfCache = {};", to: "function sameDay(a, b)" },
  money: { from: "function num(n, digits)", to: "/* Валюта съёмки, а не приложения." },
  temp: { from: "function tempShow(c)", to: "function unitLabel()" },
};

function cutFormat(name) {
  const b = FORMAT_BLOCKS[name];
  const main = X.mainScript();
  const i = main.indexOf(b.from);
  if (i < 0) throw new Error("блок «" + name + "»: не найдено начало\n  " + b.from + "\nчинить якорь в Tools/parity/lang.js");
  const j = main.indexOf(b.to, i + b.from.length);
  if (j < 0) throw new Error("блок «" + name + "»: не найден конец\n  " + b.to + "\nчинить якорь в Tools/parity/lang.js");
  return main.slice(i, j);
}

function currencies() {
  const m = /var CURRENCIES = (\[[^\]]*\]);/.exec(X.mainScript());
  if (!m) throw new Error("не найден список валют `var CURRENCIES = [...]` в бете");
  return JSON.parse(m[1]);
}

function sandbox(code) {
  const ctx = vm.createContext({
    Intl: Intl, Date: Date, Math: Math, JSON: JSON, String: String, Number: Number,
    RegExp: RegExp, isNaN: isNaN, parseInt: parseInt,
    LANG: { code: code },
    esc: (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"),
    CURRENCIES: currencies(), currency: "RUB", tempUnit: "c",
  });
  for (const n of Object.keys(FORMAT_BLOCKS)) vm.runInContext(cutFormat(n), ctx, { filename: "beta/index.html:" + n });
  return ctx;
}

function isoDay(d) {
  return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2);
}

/* Все дни 2026-го плюс два «страшных»: 29 февраля и последний день года. */
function dayList() {
  const out = [];
  for (let d = new Date(2026, 0, 1); d.getFullYear() === 2026; d = new Date(2026, d.getMonth(), d.getDate() + 1)) {
    out.push(new Date(d));
  }
  out.push(new Date(2028, 1, 29), new Date(2031, 11, 31));
  return out;
}

const MINUTES = [0, 1, 9, 59, 60, 61, 599, 600, 719, 720, 721, 779, 780, 781, 1000, 1259, 1260, 1439,
  0.4, 0.5, 719.5, 1439.5, 1440, 1441, -1, -30, 2881, null];
const RANGE_ENDS = [0, 59, 420, 719, 720, 779, 780, 1000, 1439, null];

const NUM_IN = [0, 1, 999, 1000, 12345.678, 1234567, -1500, 0.5, 1e9];
/* -0.4 и -0.5: `Math.round` даёт -0, и `Intl` пишет «-0 ₽» — запись веба, не наша */
const MONEY_IN = [0, 1, 999, 1000, 14000, 1234567, -500, 1234.5, 0.4, 0.5, -0.4, -0.5, -1234.5];
const TEMP_IN = [];
for (let c = -40; c <= 50; c += 0.5) TEMP_IN.push(c);

function buildFormat() {
  const days = dayList();
  const CUR = currencies();
  const langs = {};
  for (const code of LANGS) {
    const c = sandbox(code);
    const dates = {};
    const fields = ["dNum", "dMon", "dMonShort", "dMonYear", "dMonShortYear", "monthTitle",
      "monthOfDate", "wdShort", "wdFull", "monShortOfDate"];
    fields.forEach((f) => { dates[f] = days.map((d) => c[f](d)); });

    const months = { title: [], abbr: [] };
    for (let m = 0; m < 12; m++) { months.title.push(c.monthTitleN(m)); months.abbr.push(c.monAbbrUpperN(m)); }

    const clock = {};
    for (const pref of ["auto", "24", "12"]) {
      c.clockPref = pref;
      const fmt = MINUTES.map((m) => c.fmt(m));
      const html = MINUTES.map((m) => c.fmtHTML(m));
      const hm = MINUTES.map((m) => c.hm24(m));
      const rng = [];
      RANGE_ENDS.forEach((a) => RANGE_ENDS.forEach((b) => rng.push(c.range(a, b))));
      clock[pref] = { is12: c.is12(), fmt: fmt, hm24: hm, fmtHTML: html, range: rng };
    }
    c.clockPref = "auto";

    const number = { plain: NUM_IN.map((n) => c.num(n)), d0: NUM_IN.map((n) => c.num(n, 0)),
      d2: NUM_IN.map((n) => c.num(n, 2)) };

    const money = {}, sign = {};
    CUR.forEach((cur) => {
      money[cur] = MONEY_IN.map((n) => c.money(n, cur));
      sign[cur] = c.currencySign(cur);
    });

    langs[code] = { dates: dates, months: months, wdRow: c.wdRowCells(), clock: clock,
      number: number, money: money, sign: sign };
  }

  const c = sandbox("ru");
  const temp = { c: [], f: [] };
  for (const u of ["c", "f"]) { c.tempUnit = u; temp[u] = TEMP_IN.map((x) => c.tempShow(x)); }

  const h = crypto.createHash("sha256");
  Object.keys(FORMAT_BLOCKS).forEach((n) => { h.update(n); h.update(cutFormat(n)); });

  return {
    meta: { source: "beta/index.html", cut: h.digest("hex").slice(0, 16), node: process.version,
      icu: process.versions.icu, cldr: process.versions.cldr, unicode: process.versions.unicode,
      tz: "UTC" },
    days: days.map(isoDay), minutes: MINUTES, rangeEnds: RANGE_ENDS,
    numIn: NUM_IN, moneyIn: MONEY_IN, tempIn: TEMP_IN, currencies: CUR,
    langs: langs, temp: temp,
  };
}

/* ---------- Самопроверка эталона ----------
   Прежде чем писать: узел обязан знать все шесть языков, иначе `Intl` молча
   откатится на английский, и фикстура окажется английской во всех строках. */
function selfCheck(fmt) {
  const probe = { ru: "августа", "en-GB": "August", "en-US": "August", es: "agosto", ja: "8月", zh: "8月" };
  const bad = [];
  for (const code of LANGS) {
    const i = fmt.days.indexOf("2026-08-21");
    const got = fmt.langs[code].dates.dMon[i];
    if (got.indexOf(probe[code]) < 0) bad.push(code + ": «" + got + "» без «" + probe[code] + "»");
  }
  if (bad.length) throw new Error("ICU узла не знает язык, эталон негоден:\n  " + bad.join("\n  "));
  /* Русский «21 августа» до символа — так стоит на экране Алексея */
  const ru = fmt.langs.ru.dates;
  const i = fmt.days.indexOf("2026-08-21");
  const want = { dMon: "21 августа", dMonShort: "21 авг", dMonYear: "21 августа 2026", dMonShortYear: "21 авг 2026",
    monthTitle: "Август", monthOfDate: "августа", wdShort: "ПТ", wdFull: "пятница", monShortOfDate: "авг" };
  Object.keys(want).forEach((f) => {
    if (ru[f][i] !== want[f]) throw new Error("русская дата разошлась с экраном: " + f + " «" + ru[f][i] + "» вместо «" + want[f] + "»");
  });
}

function write(name, obj) {
  fs.mkdirSync(OUT, { recursive: true });
  const file = path.join(OUT, name);
  fs.writeFileSync(file, JSON.stringify(obj) + "\n");
  log("  " + name.padEnd(13) + String(fs.statSync(file).size).padStart(9) + " байт");
}

try {
  const lang = buildLang();
  const format = buildFormat();
  selfCheck(format);
  log("язык: " + lang.meta.keys + " ключей, склоняемых " + lang.meta.plural + ", словарей " + DICT_CODES.length);
  log("форматы: узел " + format.meta.node + ", ICU " + format.meta.icu + ", CLDR " + format.meta.cldr);
  write("lang.json", lang);
  write("format.json", format);
} catch (e) {
  console.error("\n" + e.message);
  process.exit(1);
}
