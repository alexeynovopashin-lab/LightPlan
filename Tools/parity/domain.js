/* Эталон для итерации 11 (домен): режет таблицы и правила съёмки из беты и
   пишет Fixtures/domain.json.

   Отдельным файлом и отдельным отпечатком, как location.js и lang.js: общий
   `BLOCKS` стенда неба меняет отпечаток всех фикстур разом, а итерация 10 идёт
   параллельно и правит те же файлы. Приём тот же — код не копируется, а
   режется из живого `beta/index.html` по якорным строкам (см. extract.js).

   Что режется. Таблицы: жанры, группы, способы оплаты, уточнения, пары, папки
   референсов, сроки сдачи, виды занятости, пожелания, блоки карточки, практики
   ведения дел, виды документов, валюты. Правила: состав формы, сроки сдачи,
   доход и расход (с долей месяца у повтора), цепочка сделки, порядок блоков,
   фаза события, съёмка в своих сутках, матрёшка (`nestSpan`), место съёмки,
   наложения, свет. Солнце для правила света — блоками общего стенда
   (`helpers`, `solar`), тем же кодом, с которым сверена итерация 7.

   Чем подменено то, что в приложении зовёт сеть, часы, экран или словарь
   (Swift подставляет те же заглушки, сверяется правило, а не заглушка):
   - пояс места `tzAt` — долгота / 15 по `Math.round`, у долготы 85.3 — 5.75;
   - дорога `travelMinutes` — таблица по месту назначения: минуты, `null`
     (сеть не ответила) или «ждём» (ответа ещё нет, в JS `undefined`);
   - погода `qualityOf` — «плохо» в дни, кратные 5, «туман» — кратные 7;
   - «сейчас» — `nowAt` и `Date.now` отдают заданный момент;
   - слова — `LANG.t` отдаёт ключ и подстановки строкой JSON, `range` и
     `durLabel` — голые числа: так из готовой фразы вынимаются минуты.

   Запуск:  TZ=UTC node Tools/parity/domain.js [--out Fixtures] [--quiet]
*/
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const crypto = require("crypto");
const X = require("./extract.js");

const BLOCKS = {
  allGenres:   { from: "var ALL_GENRES = [", to: "\n" },
  genres:      { from: "var PAY = {", to: "/* ---------- Уточнение жанра" },
  subGenres:   { from: "var SUBGENRE = {", to: "/* ---------- Кого снимаем" },
  persons:     { from: "var GENRE_PERSONS = {", to: "/* ---------- Страна номеров" },
  genreSpec:   { from: "function groupOf(type) {", to: "/* Правка внутри жанра запоминается" },
  refTags:     { from: "var GENRE_TAGS = {", to: "function rememberGenre(key, val)" },
  prefs:       { from: "function prefOf(g, key) {", to: "/* Показываем только то, что этому жанру нужно */" },
  form:        { from: "var formKind = \"shoot\";", to: "/* Разделитель рисуется поверху строки" },
  tagCode:     { from: "var TAG_CODE = {", to: "/* ---------- Практика ведения дел" },
  practice:    { from: "var PRACTICE = {", to: "function guessPractice()" },
  practiceSpec:{ from: "function practiceSpec() {", to: "\n" },
  currencies:  { from: "var CURRENCIES = [", to: "\n" },
  money:       { from: "function sessionCurrency(s) {", to: "/* ---------- Сдача материала ---------- */" },
  deadline:    { from: "var GENRE_DEADLINE = {", to: "/* Непрерывная шкала срочности." },
  urgency:     { from: "function urgencyCalm() {", to: "/* За сколько дней сдан материал" },
  delivery:    { from: "function deliveryDays(s) {", to: "/* ---------- Съёмка длиннее суток" },
  daySpan:     { from: "function partOfDay(s, d) {", to: "function dayMark(d) {" },
  blocks:      { from: "var BLOCK_KINDS = [", to: "/* ---------- Сохранённые точки съёмки" },
  lookups:     { from: "function newStudioId() {", to: "/* ---------- Черновик маршрута" },
  moment:      { from: "function momentOf(date, min, lat, lon) {", to: "/* Ответ о зоне приходит позже" },
  dayText:     { from: "function dayText(d) {", to: "var decl = 0, solarNoon = 720" },
  addDays:     { from: "function addDays(d, n) {", to: "\n" },
  dayDiff:     { from: "function dayDiff(a, b) {", to: "function endDayOff()" },
  shootEnd:    { from: "function shootEnd(s) {", to: "/* ---------- Честная дорога между точками дня" },
  clashes:     { from: "var FAR_MIN = 180;", to: "/* Наложения съёмки, уже лежащей в записях" },
  clashesOf:   { from: "function clashesOf(idx) {", to: "/* Ответ OSRM пришёл позже" },
  cardSun:     { from: "function cardSun(s, day) {", to: "/* ---------- Маршрут дня ----------" },
  stops:       { from: "function hasRoute(type) {", to: "/* Свет на каждом этапе" },
  sun:         { from: "var GOLD_EARLY = 10;", to: "/* Карточка события целиком" },
  phaseLight:  { from: "function eventPhase(s) {", to: "/* ---------- Порядок блоков" },
  cardOrder:   { from: "var CARD_BLOCKS = [", to: "/* Плавное сворачивание блока с полями" },
  shootMin:    { from: "function shootMin(s, now) {", to: "/* Ответ студии приходит человеком" },
  deal:        { from: "function dealName(k, inPhrase) {", to: "/* ---------- Заказ в карточке" },
  docGuess:    { from: "var DOC_GUESS = [", to: "function renderDocKinds()" },
  repeat:      { from: "function repPeriodIndex(start, date) {", to: "/* Все смены суммы группы" },
  wishes:      { from: "var WISHES = [\"any\"", to: "\n" },
  placeText:   { from: "function placeText(s) {", to: "\n" },
};
/* Блоки общего стенда: солнце для правила света и `sameDay` для наложений.
   Режутся его же `cut`, в отпечаток входят вместе со своими. */
const SKY = ["helpers", "sameDay", "solar"];

function cut(name) {
  const b = BLOCKS[name], main = X.mainScript();
  const i = main.indexOf(b.from);
  if (i < 0) throw new Error("блок «" + name + "»: не найдено начало — якорь\n  " + b.from +
    "\nБета изменилась здесь: чинить якорь в Tools/parity/domain.js, не фикстуры (" + X.webPath() + ")");
  if (main.indexOf(b.from, i + 1) >= 0) throw new Error("блок «" + name + "»: начало встречается дважды — якорь\n  " + b.from);
  const j = main.indexOf(b.to, i + b.from.length);
  if (j < 0) throw new Error("блок «" + name + "»: не найден конец — якорь\n  " + b.to);
  return main.slice(i, j);
}

const NAMES = Object.keys(BLOCKS);
const digest = (() => {
  const h = crypto.createHash("sha256");
  for (const n of SKY) { h.update("sky:" + n); h.update(X.cut(n)); }
  for (const n of NAMES) { h.update(n); h.update(cut(n)); }
  return h.digest("hex").slice(0, 16);
})();

/* ---------- Заглушки ---------- */

const APP = { lat: 56.02, lon: 37.48, tz: 3 };   // место приложения: `LAT`, `LON`, `TZ` стенда неба

function zoneStub(lat, lon) {
  return lon === 85.3 ? 5.75 : Math.max(-12, Math.min(14, Math.round(lon / 15)));
}

/* Дорога — по месту назначения. «wait» в фикстуре — это `undefined` в JS */
const TRAVEL = [
  [55.7558, 37.6173, 5],      // дом
  [55.76, 37.64, 15],         // рядом
  [55.9, 37.5, 45],           // пригород
  [56.3, 38.1, 200],          // дальше FAR_MIN
  [56.4846, 84.9482, 3000],   // Томск: дальше FLY_MIN
  [27.7172, 85.3, 600],       // Катманду
  [55.8, 37.7, null],         // сеть не ответила
  [55.7, 37.4, "wait"],       // ответа ещё нет
  [55.72, 37.58, "wait"],     // ответа ещё нет, пояс тот же, что у дома
  [55.95, 37.9, 180],         // ровно FAR_MIN
  [55.96, 37.9, 181],
  [57.0, 39.0, 480],          // ровно FLY_MIN
  [57.01, 39.0, 481],
];
function travelStub(aLat, aLon, bLat, bLon) {
  for (const t of TRAVEL) if (t[0] === bLat && t[1] === bLon) return t[2] === "wait" ? undefined : t[2];
  return undefined;
}

function weatherStub(d) {
  const n = d.getDate();
  return n % 5 === 0 ? "poor" : n % 7 === 0 ? "fog" : "good";
}

function jsonT(k, p) { return JSON.stringify(p === undefined ? { k: k } : { k: k, p: p }); }

function domStub() {
  const els = {};
  const $ = function (id) {
    if (!els[id]) {
      els[id] = {
        id: id, hidden: false, innerHTML: "", dataset: {}, children: [],
        appendChild: function (el) {
          const i = this.children.indexOf(el);
          if (i >= 0) this.children.splice(i, 1);
          this.children.push(el);
        },
      };
    }
    return els[id];
  };
  return $;
}

function load() {
  if (new Date(2026, 0, 1).getTimezoneOffset() !== 0) {
    throw new Error("стенд считает в UTC: запускать с TZ=UTC (make domain делает это сам)");
  }
  const ctx = vm.createContext({
    Math: Math, Date: Date, JSON: JSON, isFinite: isFinite, isNaN: isNaN,
    Number: Number, String: String, Array: Array, Object: Object, RegExp: RegExp,
    LANG: { t: jsonT, count: function (k, n) { return "#" + n; }, word: function (k, n) { return k + ":" + n; }, code: "ru" },
    theme: "dark", saved: null,
    selDate: new Date(2026, 0, 1), LAT: APP.lat, LON: APP.lon, TZ: APP.tz,
    sessions: [], blocks: [], spots: [], studios: [], orgs: [], genrePrefs: {}, defaultRate: 0,
    currency: "RUB", practice: "ru", manualEnd: false, icsLayer: true, travelMin: 40,
    shootType: "portrait",
  });
  for (const n of SKY) vm.runInContext(X.cut(n), ctx, { filename: "beta/index.html:" + n });
  for (const n of NAMES) vm.runInContext(cut(n), ctx, { filename: "beta/index.html:" + n });
  ctx.tzAt = zoneStub;
  ctx.travelMinutes = travelStub;
  ctx.clashesRefresh = function () {};
  ctx.clientName = function (s) { return s.id; };
  ctx.typeName = function (s) { return "type:" + (s && s.type); };
  ctx.range = function (a, b) { return [a, b]; };
  ctx.durLabel = function (m) { return m; };
  ctx.roughDur = function (m) { return m; };
  ctx.rgb = function (c) { return c; };
  ctx.rgba = function (c) { return c; };
  ctx.urgencyRGB = function (p) { return { p: p }; };
  ctx.qualityOf = weatherStub;
  ctx.dayWeather = function (d) { return { cloud: 40 + d.getDate() }; };
  ctx.QUAL = { poor: { cond: "POOR" }, fog: { cond: "FOG" }, good: { cond: "GOOD" } };
  ctx.stateAt = function () { return {}; };
  ctx.shadowWord = function () { return ""; };
  ctx.esc = function (t) { return String(t); };
  ctx.$ = domStub();
  return ctx;
}

/* ---------- Входы ---------- */

function day(y, m, d) { return new Date(y, m - 1, d); }
function shift(d, k) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + k); }
const D0 = day(2026, 9, 10);

/* Запись в виде снимка: день строкой, `undefined` не пишется, `null` остаётся —
   у `deadlineChoice` это разные вещи (ключа нет — «по жанру», null — «без срока») */
function webRec(ctx, s) {
  const o = {};
  for (const k of Object.keys(s)) {
    const v = s[k];
    if (v === undefined) continue;
    o[k] = (k === "date" || k === "from") && v instanceof Date ? ctx.dayText(v) : v;
  }
  return o;
}
/* Короче в фикстуре: поля, которые веб читает умолчанием (`|| false`,
   `|| []`, `|| ""`, `!= null`), не пишутся вовсе;
   `deadlineChoice` остаётся всегда: у него null и «нет ключа» различны */
const LEAN_KEEP = { min: 1, end: 1, dur: 1, date: 1, from: 1, id: 1, deadlineChoice: 1 };
function lean(o) {
  const out = {};
  for (const k of Object.keys(o)) {
    const v = o[k];
    if (!LEAN_KEEP[k] && (v === false || v === "" || v === null || (Array.isArray(v) && !v.length))) continue;
    if (k === "kind" && v === "shoot") continue;
    out[k] = v;
  }
  return out;
}
function parseT(text) { return JSON.parse(text); }
function clone(v) { return JSON.parse(JSON.stringify(v)); }
function pairs(o) { return Object.keys(o).map(function (k) { return [k, o[k]]; }); }

/* ---------- Таблицы ---------- */

function tables(ctx) {
  /* Снимок до первого `genreSpec`: он дописывает жанру `route` и `routeOpt` */
  const t = {
    allGenres: clone(ctx.ALL_GENRES),
    genre: clone(pairs(ctx.GENRE)),
    genreGroup: clone(pairs(ctx.GENRE_GROUP)),
    group: clone(pairs(ctx.GROUP)),
    pay: clone(pairs(ctx.PAY)),
    subGenre: pairs(ctx.SUBGENRE).map(function (p) { return [p[0], pairs(p[1])]; }),
    persons: clone(pairs(ctx.GENRE_PERSONS)),
    refTags: clone(pairs(ctx.GENRE_TAGS)),
    refTagsDefault: clone(ctx.REF_TAGS_DEFAULT),
    tagCode: clone(pairs(ctx.TAG_CODE)),
    deadline: clone(pairs(ctx.GENRE_DEADLINE)),
    delvDays: clone(ctx.DELV_DAYS),
    blockKinds: clone(ctx.BLOCK_KINDS),
    wishes: clone(ctx.WISHES),
    lightWish: Object.keys(ctx.LIGHT_WISH),
    cardBlocks: clone(ctx.CARD_BLOCKS),
    groupOrder: clone(pairs(ctx.GROUP_ORDER)),
    afterFirst: clone(ctx.AFTER_FIRST),
    practice: clone(pairs(ctx.PRACTICE)),
    practices: clone(ctx.PRACTICES),
    currencies: clone(ctx.CURRENCIES),
    docGuess: ctx.DOC_GUESS.map(function (p) { return [p[0].source, p[0].flags, p[1]]; }),
    formFields: ctx.FORM_FIELDS.map(function (f) { return clone(f.els); }),
    constants: { farMin: ctx.FAR_MIN, flyMin: ctx.FLY_MIN, goldEarly: ctx.GOLD_EARLY,
                 defaultDelivery: clone(ctx.delivery) },
  };
  t.genreSpec = ctx.ALL_GENRES.concat(["x"]).map(function (g) {
    const sp = ctx.genreSpec(g);
    return [g, clone(sp), ctx.groupOf(g), clone(ctx.groupSpec(g)), ctx.hasRoute(g)];
  });
  return t;
}

/* ---------- Состав формы ---------- */

function form(ctx) {
  const out = [];
  for (const g of ctx.ALL_GENRES.concat(["x"])) {
    for (const mode of ["shoot", "meet"]) {
      ctx.shootType = g; ctx.formKind = mode;
      const sp = ctx.genreSpec(g), gr = ctx.groupSpec(g);
      out.push({ genre: g, mode: mode, on: ctx.FORM_FIELDS.map(function (f) { return !!f.on(sp, gr); }) });
    }
  }
  ctx.formKind = "shoot";
  return out;
}

/* ---------- Сроки сдачи ---------- */

function deadlines(ctx) {
  const out = [];
  const choices = [["absent"], ["auto", "auto"], ["null", null], ["zero", 0], ["three", 3], ["long", 45]];
  const modes = [{ mode: "genre", days: 7 }, { mode: "single", days: 5 }, { mode: "none", days: 7 }, { mode: "weird", days: 9 }];
  const genres = ctx.ALL_GENRES.concat(["x", null]);
  for (const g of genres) for (const c of choices) for (const dm of modes) for (const pref of [null, 21, 0]) {
    /* Свой срок есть только у настоящего жанра: у незнакомого кода в нативе
       нет ключа, под которым его хранить */
    if (pref !== null && (g === null || g === "x" || c[0] === "null")) continue;
    ctx.delivery = dm;
    ctx.genrePrefs = pref === null ? {} : { [g]: { delvDays: pref } };
    const s = { id: "d", kind: "shoot", date: D0, min: 600, dur: 60, end: 660 };
    if (g !== null) s.type = g;
    if (c.length > 1) s.deadlineChoice = c[1];
    const days = ctx.resolveDeadlineDays(s), date = ctx.deadlineDate(s);
    out.push({ s: lean(webRec(ctx, s)), delivery: dm, pref: pref, days: days, date: date ? ctx.dayText(date) : null });
  }
  ctx.delivery = { mode: "genre", days: 7 };
  ctx.genrePrefs = {};
  return out;
}

function deliveryDays(ctx) {
  const at = [null, "2026-09-18T10:00:00.000Z", "2026-09-10T23:59:59.000Z", "2026-09-09T12:00:00.000Z",
              "garbage", "2026-12-01T00:00:00.000Z", "2026-09-10T00:00:00.000Z"];
  const out = [];
  for (const delivered of [false, true]) for (const a of at) {
    const s = { id: "v", kind: "shoot", date: D0, min: 600, dur: 60, end: 660, type: "portrait", delivered: delivered, deliveredAt: a };
    out.push({ s: webRec(ctx, s), days: ctx.deliveryDays(s) });
  }
  return out;
}

function deliveryStates(ctx) {
  const out = [];
  const base = D0.getTime(), H = 3600000, DAY = 86400000;
  const nows = [base - 2 * DAY + 12 * H, base, base + 1, base + 12 * H, base + 7 * DAY - 60000, base + 7 * DAY,
                base + 7 * DAY + 1, base + 8 * DAY + 12 * H, base + 89 * DAY, base + 90 * DAY, base + 120 * DAY];
  const kinds = [["wedding", "auto"], ["portrait", "auto"], ["portrait", null], ["portrait", 0], ["landscape", "auto"], ["portrait", 10]];
  const realNow = Date.now;
  try {
    for (const kind of ["shoot", "meet", "event"]) for (const delivered of [false, true]) for (const k of kinds) for (const now of nows) {
      if (kind !== "shoot" && (delivered || k[0] !== "portrait" || k[1] !== "auto")) continue;
      const s = { id: "st", kind: kind, date: D0, min: 600, dur: 60, end: 660, type: k[0], deadlineChoice: k[1], delivered: delivered };
      Date.now = function () { return now; };
      const r = ctx.deliveryState(s);
      const label = r.label ? parseT(r.label) : null;
      out.push({ s: lean(webRec(ctx, s)), now: now, rank: r.rank,
                 label: label ? label.k : null,
                 count: label && label.p ? Number(String(label.p.days).slice(1)) : null,
                 p: r.c && typeof r.c.p === "number" ? (isNaN(r.c.p) ? "NaN" : r.c.p) : null });
    }
  } finally { Date.now = realNow; }
  return out;
}

/* ---------- Деньги ---------- */

function money(ctx) {
  const out = { income: [], monthly: [], byCurrency: [] };
  const pays = [undefined, "", "hourly", "flat", "pack", "object", "item", "monthly"];
  const rates = [0, null, 1500, 1234.5, 99999.99];
  const durs = [null, 0, 50, 90, 480, 1440];
  const units = [0, 1, 3, 2.5];
  const exps = [0, 700.25];
  ctx.sessions = [];
  let n = 0;
  /* Длительность спрашивает только почасовая, количество — только поштучная:
     остальные сочетания повторяли бы одну и ту же сумму */
  for (const pay of pays) for (const rate of rates) for (const dur of (pay === "hourly" ? durs : [90])) for (const u of (pay === "object" || pay === "item" ? units : [1])) for (const e of exps) {
    const s = { id: "i" + (++n), kind: "shoot", date: D0, min: 600, dur: dur, end: dur == null ? null : 600 + dur,
                type: "portrait", pay: pay, rate: rate, units: u, expense: e };
    out.income.push({ s: lean(webRec(ctx, s)), income: ctx.sessionIncome(s), net: ctx.sessionNet(s) });
  }
  for (const kind of ["meet", "event"]) {
    const s = { id: "i" + (++n), kind: kind, date: D0, min: 600, dur: 90, end: 690, type: "portrait", pay: "hourly", rate: 1500, units: 1, expense: 300 };
    out.income.push({ s: webRec(ctx, s), income: ctx.sessionIncome(s), net: ctx.sessionNet(s) });
  }

  /* Повтор с помесячной оплатой: доля месяца, смены суммы, свой гонорар */
  function M(id, y, m, d, extra, rep) {
    return Object.assign({ id: id, kind: "shoot", date: day(y, m, d), min: 600, dur: 60, end: 660, type: "portrait",
      pay: "monthly", rate: null, units: 1, expense: 0 }, extra, { rep: Object.assign({ g: "g1", rule: "week", i: 1, n: 12, monthly: 40000, start: "2026-01-31" }, rep) });
  }
  const group = [
    M("m1", 2026, 1, 31, {}, {}),
    M("m2", 2026, 2, 7, {}, { sums: [{ k: 1, sum: 45000, at: 100 }] }),
    M("m3", 2026, 2, 27, {}, {}),
    M("m4", 2026, 2, 28, { expense: 1200 }, {}),
    M("m5", 2026, 3, 1, {}, {}),
    M("m6", 2026, 3, 14, { rate: 5000 }, {}),
    M("m7", 2026, 3, 31, {}, { sums: [{ k: 0, sum: 38000, at: 50 }] }),
    M("m8", 2026, 4, 15, { pay: "flat", rate: 3000 }, {}),
    M("m9", 2026, 4, 30, {}, { sums: [{ k: 2, sum: 50000, at: 200 }, { k: 1, sum: 47000, at: 300 }] }),
    M("m10", 2026, 5, 31, {}, {}),
    M("n1", 2026, 3, 15, {}, { g: "g2", start: "2026-03-15", monthly: 0 }),
    M("n2", 2026, 3, 20, {}, { g: "g2", start: "2026-03-15", monthly: 0, sums: [{ k: 0, sum: 9000, at: 10 }] }),
    M("r1", 2026, 3, 16, {}, { g: "g3", rule: "day", start: undefined, monthly: undefined }),
    M("r2", 2026, 2, 29 - 1, { kind: "meet" }, { g: "g4", start: "2026-02-28", monthly: 1000 }),
    M("z1", 2027, 1, 31, {}, { g: "g5", start: "2026-12-31", monthly: 70000 }),
    M("z2", 2027, 2, 28, {}, { g: "g5", start: "2026-12-31", monthly: 70000 }),
    M("z3", 2027, 2, 28, {}, { g: "g5", start: "2026-12-31", monthly: 70000 }),
  ];
  ctx.sessions = group;
  for (const s of group) {
    out.monthly.push({ income: ctx.sessionIncome(s), net: ctx.sessionNet(s),
      period: s.rep && s.rep.start ? ctx.repPeriodIndex(s.rep.start, s.date) : null });
  }
  out.monthlySessions = group.map(function (s) { return webRec(ctx, s); });
  ctx.sessions = [];

  /* Суммы по валютам: без пересчёта курса, домашняя первой */
  function C(id, cur, rate, extra) {
    return Object.assign({ id: id, kind: "shoot", date: D0, min: 600, dur: 60, end: 660, type: "portrait",
      pay: "flat", rate: rate, units: 1, expense: 0, currency: cur }, extra);
  }
  const lists = [
    [C("c1", "RUB", 1000), C("c2", "USD", 50), C("c3", "RUB", 500), C("c4", "EUR", 70), C("c5", undefined, 300), C("c6", "XXX", 20)],
    [C("c7", "USD", 100), C("c8", "EUR", 100), C("c9", "GBP", 100), C("c10", "JPY", 100)],
    [C("c11", "USD", 100, { expense: 100 }), C("c12", "EUR", 40, { prepay: 10 }), C("c13", "CNY", 0), C("c14", "RUB", 10, { kind: "meet" })],
    [],
  ];
  const fns = { income: ctx.sessionIncome, net: ctx.sessionNet, prepay: function (s) { return +s.prepay || 0; } };
  lists.forEach(function (list, li) {
    for (const home of ["RUB", "USD", "EUR"]) for (const fn of Object.keys(fns)) {
      ctx.currency = home;
      out.byCurrency.push({ list: li, home: home, amount: fn,
        sums: ctx.sumByCurrency(list, fns[fn]).map(function (x) { return [x.code, x.sum]; }) });
    }
  });
  ctx.currency = "RUB";
  out.currencyLists = lists.map(function (l) { return l.map(function (s) { return webRec(ctx, s); }); });
  return out;
}

/* ---------- Цепочка сделки ---------- */

function deal(ctx) {
  const out = { chains: [], shown: [] };
  const docsets = [[], ["contract"], ["contract", "invoice"], ["contract", "invoice", "act"], ["brief"],
                   ["release", "acceptance"], ["receipt"], ["weird"], ["contract", "invoice", "act", "release", "acceptance", "brief"]];
  const moneyCases = [[0, 0], [10000, 0], [10000, 3000], [10000, 10000], [10000, 12000], [0, 500]];
  /* Сдача закрывает звено только у британской практики, ТЗ строкой — только звено «ТЗ» */
  for (const pr of ctx.PRACTICES) for (const docs of docsets) for (const brief of (docs.length < 2 ? ["", "ТЗ"] : [""])) for (const mc of moneyCases) for (const delivered of (pr === "uk" ? [false, true] : [false])) {
    ctx.practice = pr;
    const s = { id: "dl", kind: "shoot", date: D0, min: 600, dur: 60, end: 660, type: "product", pay: "flat",
                rate: mc[0], prepay: mc[1], units: 1, expense: 0, brief: brief, delivered: delivered,
                docs: docs.map(function (k) { return { k: "link", kind: k, url: "https://x/" + k, name: k }; }) };
    const chain = ctx.dealChain(s).map(function (l) { return [l.k, l.done, l.half === undefined ? null : l.half]; });
    out.chains.push({ practice: pr, s: lean(webRec(ctx, s)), chain: chain });
  }
  for (const pr of ctx.PRACTICES) for (const g of ctx.ALL_GENRES.concat(["x"])) {
    ctx.practice = pr;
    const s = { id: "sh", kind: "shoot", date: D0, min: 600, dur: 60, end: 660, type: g, pay: "flat", rate: 0, prepay: 0, docs: [] };
    ctx.renderDeal(s);
    out.shown.push({ practice: pr, genre: g, shown: !ctx.$("cdDeal").hidden });
  }
  ctx.practice = "ru";
  return out;
}

/* ---------- Порядок блоков ---------- */

function order(ctx) {
  const out = { orders: [], off: [] };
  const saved = [null, ["money", "deal"], ["zzz", "notes", "day"], ["refs", "day", "refs"], ctx.DEFAULT_ORDER.slice().reverse()];
  for (const g of ctx.ALL_GENRES.concat(["x"])) for (const sv of saved) for (const phase of ["before", "during", "after"]) {
    ctx.cardOrder = sv ? { [ctx.groupOf(g)]: sv } : {};
    const host = ctx.$("cdEventBlocks");
    host.children = [];
    ctx.applyOrder(g, phase);
    const byEl = {};
    ctx.CARD_BLOCKS.forEach(function (b) { byEl[b.el] = b.k; });
    out.orders.push({ genre: g, saved: sv, phase: phase,
      orderFor: clone(ctx.orderFor(g)), shown: host.children.map(function (el) { return byEl[el.id]; }) });
  }
  const offs = [[], ["money"], ["weather", "light", "zzz"]];
  for (const g of ctx.ALL_GENRES.concat(["x"])) for (const off of offs) {
    ctx.cardOff = { [ctx.groupOf(g)]: off };
    out.off.push({ genre: g, off: off, blocks: ctx.CARD_BLOCKS.filter(function (b) { return ctx.blockOff(g, b.k); }).map(function (b) { return b.k; }) });
  }
  ctx.cardOrder = {}; ctx.cardOff = {};
  return out;
}

/* ---------- Фаза, сутки, матрёшка ---------- */

const PHASE_SESSIONS = [
  { id: "p1", min: 600, dur: 120 },
  { id: "p2", min: 1320, dur: 240 },
  { id: "p3", min: 600, dur: null, end: null },
  { id: "p4", min: 600, dur: 120, doneAt: 650 },
  { id: "p5", min: 1320, dur: 240, doneAt: 60 },
  { id: "p6", min: 1320, dur: 240, doneAt: 1400 },
  { id: "p7", min: 480, dur: 2880 },
  { id: "p8", min: 0, dur: 1440 },
  { id: "p9", min: 600, dur: 0, end: 600 },
];
function phaseRec(p) {
  const s = { id: p.id, kind: "shoot", date: D0, min: p.min, type: "portrait", dur: p.dur };
  s.end = p.end !== undefined ? p.end : (p.dur == null ? null : p.min + p.dur);
  if (p.doneAt !== undefined) s.doneAt = p.doneAt;
  return s;
}

function phases(ctx) {
  const out = [];
  for (const p of PHASE_SESSIONS) {
    const s = phaseRec(p);
    const end = ctx.shootEnd(s);
    const marks = [-1441, -1, 0, s.min - 1, s.min, s.min + 1, end - 1, end, end + 1, 1439, 1440, 1441, 2880, 3359, 3360, 4320, 4321];
    for (const manual of [false, true]) for (const m of marks) {
      const now = new Date(D0.getTime() + m * 60000);
      ctx.nowAt = function () { return now; };
      ctx.manualEnd = manual;
      out.push({ s: lean(webRec(ctx, s)), now: [ctx.dayText(now), now.getHours() * 60 + now.getMinutes()], manual: manual,
                 phase: ctx.eventPhase(s), shootMin: ctx.shootMin(s, now) });
    }
  }
  ctx.manualEnd = false;
  return out;
}

function daySpans(ctx) {
  const out = [];
  for (const p of PHASE_SESSIONS) {
    const s = phaseRec(p);
    for (let k = -3; k <= 3; k++) {
      const d = shift(D0, k), r = ctx.partOfDay(s, d);
      out.push({ s: webRec(ctx, s), day: ctx.dayText(d), part: r ? [r.a, r.b, r.tail, r.cut] : null });
    }
  }
  return out;
}

function nests(ctx) {
  const cases = [
    { route: [] },
    { route: [{ t: null, n: "Сборы" }] },
    { route: [{ t: 600, n: "ЗАГС" }] },
    { route: [{ t: 600, t2: 660, n: "ЗАГС" }, { t: 900, n: "Прогулка" }] },
    { route: [{ t: 900, t2: 800, n: "конец раньше начала" }] },
    { route: [{ t: 1500, t2: 1600, n: "второй день" }, { t: 700, n: "утро" }] },
    { route: [{ t: 0, n: "полночь" }] },
    { route: [{ t: null, t2: 700, n: "без начала" }] },
    { route: [], studioId: "st1", rentFrom: 600, rentTo: 720 },
    { route: [], studioId: "st1", rentFrom: 600, rentTo: null },
    { route: [], studioId: null, rentFrom: 600, rentTo: 720 },
    { route: [{ t: 800, n: "x" }], studioId: "st1", rentFrom: 500, rentTo: 900 },
    { route: [{ t: 600, t2: 600, n: "" }] },
    { route: [{ t: 1000, n: "a" }, { t: 400, t2: 1200, n: "b" }], studioId: "st1", rentFrom: 1300, rentTo: 1250 },
  ];
  return cases.map(function (c) {
    const s = Object.assign({ id: "n", kind: "shoot", date: D0, min: 600, dur: 60, end: 660, type: "wedding" }, c);
    const r = ctx.nestSpan(s);
    return { s: webRec(ctx, s), span: r ? [r.a, r.b] : null };
  });
}

/* ---------- Места: маршрут, точки, где спрашивать небо ---------- */

const SPOTS = [
  { id: "sp_park", name: "Лагерный сад", address: "Томск, Лагерный сад", town: "Томск", lat: 55.76, lon: 37.64 },
  { id: "sp_far", name: "Набережная", address: "Сочи", town: "Сочи", lat: 43.585, lon: 39.72 },
  { id: "sp_nocoord", name: "Без точки", address: "", town: "", lat: null, lon: null },
  { id: "sp_sub", name: "Дом", address: "ул. Ленина, 1", town: "Лобня", sub: "подъезд 2", lat: 56.011, lon: 37.483 },
];
const STUDIOS = [
  { id: "st_a", name: "Томсон", address: "Красноармейская, 101", tel: "+7 961", town: "Томск", lat: 55.75, lon: 37.6,
    halls: [{ id: "h1", name: "Эдисон" }] },
  { id: "st_nocoord", name: "Студия без точки", address: "", tel: "", town: "", lat: null, lon: null, halls: [] },
];

function stops(ctx) {
  ctx.spots = SPOTS; ctx.studios = STUDIOS;
  const cases = [
    { place: "", placeLat: null, placeLon: null, route: [] },
    { place: "Парк", placeLat: 55.7558, placeLon: 37.6173, route: [] },
    { place: "", placeAddr: "Адрес", placeLat: 55.7558, placeLon: 37.6173, route: [] },
    { place: "Студия", placeLat: 55.75, placeLon: 37.6, studioId: "st_a", route: [] },
    { place: "Студия", placeLat: 55.75, placeLon: 37.6, studioId: "st_a",
      route: [{ t: 600, n: "Студия", studioId: "st_a", p: "Томсон, зал Эдисон" }, { t: 700, n: "Парк", placeId: "sp_park" }] },
    { place: "", placeLat: null, placeLon: null,
      route: [{ t: 600, n: "Студия", studioId: "st_a" }, { t: 700, n: "Студия 2", studioId: "st_nocoord" }] },
    { place: "", placeLat: null, placeLon: null, route: [{ t: 600, n: "Без точки", placeId: "sp_nocoord" }, { t: 650, n: "Дом", placeId: "sp_sub" }] },
    { place: "Площадь", placeLat: 55.9, placeLon: 37.5,
      route: [{ t: 900, n: "b" }, { t: 600, n: "a" }, { t: 600, n: "a2" }, { t: null, n: "без часа" }, { t: 700, n: "" }, { t: 800, n: "Сад", placeId: "sp_park", p: "Сад у реки" }] },
    { place: "", placeLat: 43.585, placeLon: 39.72, route: [{ t: 600, n: "x", placeId: "missing" }, { t: 610, n: "y", studioId: "missing" }] },
  ];
  const out = cases.map(function (c, i) {
    const s = Object.assign({ id: "sp" + i, kind: "shoot", date: D0, min: 600, dur: 60, end: 660, type: "wedding", placeAddr: "" }, c);
    const at = ctx.shootAt(s);
    return { s: webRec(ctx, s),
      routeOf: ctx.routeOf(s).map(function (r) { return s.route.indexOf(r); }),
      stops: ctx.recStops(s).map(function (p) { return [p.name, p.addr, p.lat, p.lon, p.sub, p.studio]; }),
      shootAt: [at.lat, at.lon], placeKey: ctx.placeKey(s), placeText: ctx.placeText(s) };
  });
  ctx.spots = []; ctx.studios = [];
  return out;
}

/* ---------- Свет — условие ---------- */

function lights(ctx) {
  ctx.spots = SPOTS; ctx.studios = STUDIOS;
  const out = [];
  const places = [[55.7558, 37.6173], [27.7172, 85.3], [56.4846, 84.9482], [68.97, 33.07], [null, null]];
  const days = [day(2026, 9, 11), day(2026, 9, 10), day(2026, 9, 14), day(2026, 6, 22), day(2026, 12, 22), day(2026, 6, 21)];
  const wishes = [[], ["sunset"], ["stars"], ["moon", "clear"], ["clear"]];
  const spans = [[360, 480], [900, 1080], [1080, 1200], [1200, 1380], [1320, 1560], [0, 1440], [1140, 1150]];
  const routes = [
    [{ t: 600, n: "ЗАГС" }, { t: 1080, n: "Прогулка" }, { t: 1230, n: "Банкет" }],
    [{ t: 1000, n: "Парк", placeId: "sp_park" }, { t: 1150, n: "Набережная", placeId: "sp_far" }, { t: 1300, n: "Студия", studioId: "st_a" }],
    [{ t: 1200, n: "Вечер" }, { t: 1500, n: "Ночь" }, { t: 2600, n: "Утро второго дня" }],
    [{ t: 1100, n: "Без точки", placeId: "sp_nocoord" }, { t: null, n: "без часа" }],
  ];
  let n = 0;
  for (const pl of places) for (const d of days) for (const w of wishes) {
    if (!w.length && pl[0] !== 55.7558) continue;
    const variants = spans.map(function (sp) { return { min: sp[0], end: sp[1], route: [] }; })
      .concat(routes.map(function (r) { return { min: 600, end: 1400, route: r }; }));
    for (const v of variants) {
      const s = { id: "l" + (++n), kind: "shoot", date: d, min: v.min, end: v.end, dur: v.end - v.min, type: "wedding",
                  wish: w, place: pl[0] == null ? "" : "Место", placeLat: pl[0], placeLon: pl[1], route: v.route };
      const route = ctx.notWork(s) ? [] : ctx.routeOf(s);
      const sun = ctx.cardSun(s);
      const r = ctx.lightCase(s, route, sun);
      let res = null;
      if (r) {
        const t = parseT(r.text), p = t.p || {};
        /* «Съёмка» вместо имени точки — строка словаря, в Swift это `nil` */
        const shootPoint = jsonT("card.shootPoint");
        res = { k: t.k, bad: r.bad, name: p.name === undefined || p.name === shootPoint ? null : p.name,
                range: p.range || null, gap: p.gap === undefined ? null : p.gap };
      }
      const rec = lean(webRec(ctx, s)); delete rec.type;
      out.push({ s: rec, sun: [sun.goldB, sun.blueB], light: res });
    }
  }
  ctx.spots = []; ctx.studios = [];
  return out;
}

/* ---------- Виды документов по имени файла ---------- */

function docGuess(ctx) {
  const names = ["", "dogovor-romashka.pdf", "Договор аренды.docx", "ДОГОВОР", "contract_2026.pdf", "akt-vypolnennyh.pdf",
    "Акт.pdf", "акта сверки", "AKT 12", "act.pdf", "impact.pdf", "factor.pdf", "Счёт 15.pdf", "счет", "invoice_12.pdf",
    "schet-3", "schyot", "chek-2214.jpg", "Чек", "receipt.png", "cheque", "kassa.jpg", "check list", "ТЗ.pdf", "тз-свадьба",
    "brief.pdf", "task list.txt", "tz.docx", "tzar.docx", "release form.pdf", "Релиз модели", "согласие модели.pdf",
    "согласия  модели", "acceptance.pdf", "протокол приёмки", "Протокол", "приемки", "приёмка", "photo.jpg", "IMG_0001.HEIC",
    "Договор и акт", "akt", "aktor", "ЧЕКИ", "ТЗБ"];
  return names.map(function (nm) { return { name: nm, kind: ctx.guessDocKind(nm) }; });
}

/* ---------- Наложения ---------- */

const PL = {
  home:  { lat: 55.7558, lon: 37.6173, place: "Лобня" },
  near:  { lat: 55.76, lon: 37.64, place: "Москва" },
  mid:   { lat: 55.9, lon: 37.5, place: "Мытищи" },
  far:   { lat: 56.3, lon: 38.1, place: "Сергиев Посад" },
  fly:   { lat: 56.4846, lon: 84.9482, place: "Томск" },
  kath:  { lat: 27.7172, lon: 85.3, place: "Катманду" },
  dead:  { lat: 55.8, lon: 37.7, place: "Химки" },
  wait:  { lat: 55.7, lon: 37.4, place: "Одинцово" },
  tight: { lat: 55.72, lon: 37.58, place: "Реутов" },
  e180:  { lat: 55.95, lon: 37.9, place: "Королёв" },
  e181:  { lat: 55.96, lon: 37.9, place: "Щёлково" },
  e480:  { lat: 57.0, lon: 39.0, place: "Ярославль" },
  e481:  { lat: 57.01, lon: 39.0, place: "Рыбинск" },
};

function sess(id, at, min, dur, extra) {
  return Object.assign({ id: id, kind: "shoot", date: D0, min: min, dur: dur, end: min + dur, type: "portrait",
    place: at ? at.place : "", placeTown: "", placeLat: at ? at.lat : null, placeLon: at ? at.lon : null,
    wish: [], trip: false, tripManual: false }, extra);
}
function blk(id, from, extra) {
  return Object.assign({ id: id, k: "busy", note: id, from: from, allDay: false, days: 1, min: 600, dur: 60, tzFrom: null, tzTo: null }, extra);
}

function clashScenarios() {
  const sc = [];
  /* 1. Полный перебор взаимных положений двух съёмок одного дня: начало второй
     от −600 до +720 минут шагом 30, по две длины у первой и четыре у второй,
     с тремя наборами мест и пожеланий. */
  const aDurs = [60, 600], bDurs = [30, 90, 240, 720];
  const sets = [
    { a: { at: PL.home, wish: ["sunset"] }, b: { at: PL.mid, wish: ["sunset"] } },
    { a: { at: PL.home, wish: [] }, b: { at: PL.wait, wish: ["sunset"] } },
    { a: { at: PL.home, wish: ["sunset"] }, b: { at: PL.home, wish: ["sunset", "clear"] } },
  ];
  for (const set of sets) for (const ad of aDurs) for (const bd of bDurs) for (let off = -600; off <= 720; off += 30) {
    sc.push({ tag: "pos", sessions: [sess("sA", set.a.at, 600, ad, { wish: set.a.wish }), sess("sB", set.b.at, 600 + off, bd, { wish: set.b.wish })], blocks: [] });
  }
  /* 2. Места и дорога: одно и то же место под разными словами, пустое место,
     каждый ответ дороги, выезд у каждой стороны и снятый руками выезд. */
  const places = [
    { a: PL.home, b: Object.assign({}, PL.home, { place: "Лобня, Московская область" }) },
    { a: PL.home, b: Object.assign({}, PL.near, { place: "  ЛОБНЯ " }) },
    { a: PL.home, b: Object.assign({}, PL.near, { place: "" }) },
    { a: Object.assign({}, PL.home, { place: "" }), b: PL.near },
    { a: PL.home, b: Object.assign({}, PL.near, { place: "", placeTown: "Москва" }) },
    { a: PL.home, b: PL.near }, { a: PL.home, b: PL.mid }, { a: PL.home, b: PL.far }, { a: PL.home, b: PL.fly },
    { a: PL.home, b: PL.kath }, { a: PL.home, b: PL.dead }, { a: PL.home, b: PL.wait },
    { a: PL.home, b: Object.assign({}, PL.mid, { lat: null, lon: null }) },
  ];
  const trips = [
    { a: {}, b: {} }, { a: { trip: true }, b: {} }, { a: {}, b: { trip: true } },
    { a: { tripManual: true }, b: {} }, { a: {}, b: { tripManual: true } }, { a: { tripManual: true, trip: true }, b: {} },
  ];
  const starts = [300, 480, 660, 840, 1020, 1250];
  for (const p of places) for (const t of trips) for (const bMin of starts) for (const sun of [false, true]) {
    const a = sess("sA", p.a, 600, 120, Object.assign({ wish: sun ? ["sunset"] : [] }, t.a));
    const b = sess("sB", p.b, bMin, 120, Object.assign({ wish: ["sunset"] }, t.b));
    if (p.a.place === "") a.place = "";
    if (p.b.placeTown) { b.placeTown = p.b.placeTown; }
    sc.push({ tag: "place", sessions: [a, b], blocks: [] });
  }
  /* 3. Пояса: одни и те же настенные часы в разных поясах и без точки. */
  for (const other of [PL.kath, PL.fly, null]) for (let bMin = 0; bMin <= 1380; bMin += 60) {
    sc.push({ tag: "zone", sessions: [sess("sA", PL.home, 600, 180), sess("sB", other, bMin, 120)], blocks: [] });
  }
  /* 4. Занятость: весь день вокруг, по часам в своих, соседних сутках и с
     поясом вылета; съёмка через полночь. */
  const blockSets = [];
  blockSets.push([blk("bOffPrev", shift(D0, -1), { k: "off", allDay: true, days: 1, min: null, dur: null })]);
  blockSets.push([blk("bOffSpan", shift(D0, -1), { k: "off", allDay: true, days: 2, min: null, dur: null })]);
  blockSets.push([blk("bOffDay", D0, { k: "off", allDay: true, days: 1, min: null, dur: null })]);
  blockSets.push([blk("bOffNext", shift(D0, 1), { k: "off", allDay: true, days: 3, min: null, dur: null })]);
  blockSets.push([blk("bOffZero", D0, { k: "off", allDay: true, days: 0, min: null, dur: null })]);
  for (let m = 0; m <= 1380; m += 60) blockSets.push([blk("bBusy" + m, D0, { min: m, dur: 90 })]);
  for (let m = 1260; m <= 1380; m += 60) blockSets.push([blk("bPrev" + m, shift(D0, -1), { k: "road", min: m, dur: 240 })]);
  for (let m = 0; m <= 180; m += 60) blockSets.push([blk("bNext" + m, shift(D0, 1), { k: "road", min: m, dur: 60 })]);
  for (let m = 180; m <= 900; m += 60) blockSets.push([blk("bFly" + m, D0, { k: "flight", min: m, dur: 240, tzFrom: 7, tzTo: 3 })]);
  blockSets.push([blk("bFlyPrev", shift(D0, -1), { k: "flight", min: 1380, dur: 300, tzFrom: 7, tzTo: 3 })]);
  blockSets.push([blk("bNoNote", D0, { note: "", k: "weird", min: 650, dur: 30 })]);
  for (const bs of blockSets) {
    sc.push({ tag: "block", sessions: [sess("sA", PL.home, 600, 180)], blocks: bs });
    sc.push({ tag: "block", sessions: [sess("sN", PL.home, 1320, 240)], blocks: bs });
  }
  /* 5. Порядок и род записей: тяжёлое первым, чужие события при выключенном
     слое, встреча, другая дата. */
  const mix = [
    sess("sA", PL.home, 600, 240, { wish: ["sunset"] }),
    sess("sB", PL.mid, 870, 60, { wish: ["sunset"] }),
    sess("sC", PL.home, 700, 60, { wish: ["sunset"] }),
    sess("sD", PL.home, 1200, 60, { wish: ["sunset"] }),
    sess("sE", PL.home, 650, 60, { kind: "event" }),
    sess("sF", PL.home, 660, 60, { kind: "meet" }),
    sess("sG", PL.home, 600, 60, { date: shift(D0, 1) }),
  ];
  for (const ics of [true, false]) {
    sc.push({ tag: "mix", icsLayer: ics, sessions: mix, blocks: [blk("bMix", D0, { min: 500, dur: 150 }), blk("bMixDay", D0, { allDay: true, k: "off", min: null, dur: null })] });
  }
  /* 6. Границы: запас ровно равен дороге и на минуту больше или меньше; порог
     без дороги; дорога ровно FAR_MIN и FLY_MIN — со снятым руками выездом и без. */
  for (const d of [-1, 0, 1]) {
    const edges = [
      [PL.mid, 720 + 45 + d, 60, {}], [PL.mid, 600 - 45 - d - 60, 60, {}], [PL.tight, 720 + 40 + d, 60, {}],
      [PL.e180, 720 + 180 + d, 60, {}], [PL.e181, 720 + 180 + d, 60, {}],
      [PL.e180, 720 + 100 + d, 60, { tripManual: true }], [PL.e181, 720 + 100 + d, 60, { tripManual: true }],
      [PL.e480, 720 + 480 + d, 60, {}], [PL.e481, 720 + 100 + d, 60, {}],
    ];
    for (const e of edges) {
      sc.push({ tag: "edge", sessions: [sess("sA", PL.home, 600, 120), sess("sB", e[0], e[1], e[2], e[3])], blocks: [] });
    }
  }
  sc.push({ tag: "mix", travelMin: 90, sessions: [sess("sA", PL.home, 600, 60), sess("sB", PL.wait, 700, 60), sess("sC", PL.dead, 400, 60)], blocks: [] });
  return sc;
}

function clashes(ctx) {
  const out = [];
  for (const sc of clashScenarios()) {
    ctx.sessions = sc.sessions; ctx.blocks = sc.blocks;
    ctx.icsLayer = sc.icsLayer !== undefined ? sc.icsLayer : true;
    ctx.travelMin = sc.travelMin !== undefined ? sc.travelMin : 40;
    const res = sc.sessions.map(function (s, i) {
      return ctx.clashesOf(i).map(function (c) {
        const m = parseT(c.m), p = m.p || {};
        const kind = parseT(c.t).k.replace(/^clash\./, "").replace(/T$/, "");
        return [kind, c.w, c.n, p.when ? p.when[0] : null, p.when ? p.when[1] : null,
                p.need === undefined ? null : p.need, p.have === undefined ? (p.gap === undefined ? null : p.gap) : p.have];
      });
    });
    out.push({ tag: sc.tag, icsLayer: ctx.icsLayer, travelMin: ctx.travelMin,
      sessions: sc.sessions.map(function (s) { const o = lean(webRec(ctx, s)); delete o.type; return o; }),
      blocks: sc.blocks.map(function (b) { return lean(webRec(ctx, b)); }),
      clashes: res });
  }
  ctx.sessions = []; ctx.blocks = []; ctx.icsLayer = true; ctx.travelMin = 40;
  return out;
}

/* ---------- Самопроверка ---------- */

function selfCheck(ctx) {
  const fails = [];
  function eq(name, got, want) { if (JSON.stringify(got) !== JSON.stringify(want)) fails.push(name + ": " + JSON.stringify(got) + " вместо " + JSON.stringify(want)); }
  const base = { id: "c", kind: "shoot", date: D0, min: 600, dur: 90, end: 690 };
  eq("почасовая 1500 × 90 мин", ctx.sessionIncome(Object.assign({}, base, { pay: "hourly", rate: 1500 })), 2250);
  eq("за предмет 700 × 3", ctx.sessionIncome(Object.assign({}, base, { pay: "item", rate: 700, units: 3 })), 2100);
  eq("встреча без денег", ctx.sessionIncome(Object.assign({}, base, { kind: "meet", pay: "flat", rate: 900 })), 0);
  eq("срок свадьбы по жанру", ctx.resolveDeadlineDays(Object.assign({}, base, { type: "wedding" })), 90);
  eq("у пейзажа срока нет", ctx.resolveDeadlineDays(Object.assign({}, base, { type: "landscape" })), null);
  eq("свой срок сильнее жанра", ctx.resolveDeadlineDays(Object.assign({}, base, { type: "wedding", deadlineChoice: 3 })), 3);
  eq("матрёшка", ctx.nestSpan({ route: [{ t: 700, t2: 760 }, { t: 650 }] }), { a: 650, b: 760 });
  eq("съёмка через полночь во вторых сутках", ctx.partOfDay({ date: D0, min: 1320, end: 1560 }, shift(D0, 1)), { a: 0, b: 120, tail: true, cut: false });
  ctx.nowAt = function () { return new Date(D0.getTime() + 600 * 60000); };
  eq("фаза на самом начале", ctx.eventPhase(Object.assign({}, base)), "during");
  ctx.sessions = [sess("sA", PL.home, 600, 60), sess("sB", PL.home, 630, 60)];
  eq("пересечение времени", parseT(ctx.clashesOf(0)[0].t).k, "clash.overlapT");
  ctx.sessions = [];
  if (fails.length) throw new Error("самопроверка эталона не прошла, фикстура не записана:\n  " + fails.join("\n  "));
}

/* ---------- Запуск ---------- */

function main() {
  const args = process.argv.slice(2);
  const outDir = args.indexOf("--out") >= 0 ? args[args.indexOf("--out") + 1] : path.join(X.ROOT, "Fixtures");
  const quiet = args.indexOf("--quiet") >= 0;
  const ctx = load();
  const t = tables(ctx);
  selfCheck(ctx);
  const data = {
    meta: {
      what: "таблицы и правила съёмки из beta/index.html (итерация 11), см. Tools/parity/domain.js",
      cut: digest, app: APP,
      travel: TRAVEL, zones: "долгота / 15 по Math.round, у долготы 85.3 — 5.75",
      weather: "плохо в дни, кратные 5 (poor), туман — кратные 7 (fog), иначе good",
      spots: SPOTS, studios: STUDIOS,
    },
    tables: t,
    form: form(ctx),
    deadlines: deadlines(ctx),
    deliveryDays: deliveryDays(ctx),
    deliveryStates: deliveryStates(ctx),
    money: money(ctx),
    deal: deal(ctx),
    order: order(ctx),
    phases: phases(ctx),
    daySpans: daySpans(ctx),
    nests: nests(ctx),
    stops: stops(ctx),
    lights: lights(ctx),
    docGuess: docGuess(ctx),
    clashes: clashes(ctx),
  };
  const text = JSON.stringify(data);
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, "domain.json"), text + "\n");
  if (!quiet) {
    const cl = data.clashes.reduce(function (n, c) { return n + c.clashes.reduce(function (m, l) { return m + l.length; }, 0); }, 0);
    console.log("  domain.json: " + (text.length / 1024).toFixed(0) + " КБ, отпечаток " + digest);
    console.log("  форма " + data.form.length + ", сроки " + data.deadlines.length + "+" + data.deliveryDays.length + "+" + data.deliveryStates.length +
      ", доход " + data.money.income.length + "+" + data.money.monthly.length + "+" + data.money.byCurrency.length +
      ", сделка " + data.deal.chains.length + "+" + data.deal.shown.length + ", порядок " + data.order.orders.length + "+" + data.order.off.length);
    console.log("  фаза " + data.phases.length + ", сутки " + data.daySpans.length + ", матрёшка " + data.nests.length +
      ", места " + data.stops.length + ", свет " + data.lights.length + " (сказано " + data.lights.filter(function (l) { return l.light; }).length + ")" +
      ", документы " + data.docGuess.length + ", наложения " + data.clashes.length + " сценариев, " + cl + " предупреждений");
  }
}

main();
