/* Гоняет вырезанные из беты слои по сетке входов и пишет фикстуры.

   Фикстуры — это эталон, с которым потом сверяется Swift. Поэтому здесь
   не должно быть ничего случайного: ни времени запуска, ни системного
   часового пояса, ни Math.random. Повторный прогон обязан дать побайтово
   тот же файл — это и есть признак годности стенда.

   Сетка входов — § 5.2 плана (`light_plan:Light_Plan/SWIFT_MIGRATION_PLAN.md`).
   Допуски там же: высота и азимут 1e-9°, времена событий 1e-6 минуты,
   коды состояний, полярность и уровень прибора — строгое равенство.

   Пример:
     make parity                     пересобрать и проверить повторяемость
     TZ=UTC node Tools/parity/generate.js --out Fixtures
*/
"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const X = require("./extract.js");

/* ---------- Пояс машины ----------
   computeSun берёт номер дня через локальный `new Date(y, 0, 0)`, и в поясе
   с переводом часов разница дат уезжает на час, а floor — на сутки. Значит
   стенд считается только в UTC, иначе фикстуры зависят от того, на чьём
   ноутбуке их сгенерировали. Россия часы не переводит, поэтому числа
   совпадают с телефоном Алексея; проверка стоит ради всех остальных. */
if (new Date(2026, 0, 1).getTimezoneOffset() !== 0 ||
    new Date(2026, 6, 1).getTimezoneOffset() !== 0) {
  console.error("Стенд считается только в UTC: запускать `TZ=UTC node Tools/parity/generate.js`\n" +
    "или `make parity`. Причина — в комментарии у этой проверки.");
  process.exit(2);
}

/* ============================================================
   СЕТКА ВХОДОВ (§ 5.2)
   ============================================================ */

/* Широты: полярные круги и тропики — границы, где модель меняет поведение;
   55.03 — Барнаул, живое место из продукта. */
const LATS = [-78, -66.6, -45, -23.4, 0, 23.4, 45, 55.03, 66.6, 78];
/* Долготы: антимеридиан с обеих сторон, нуль и его соседи, Москва, ±90. */
const LONS = [-179, -90, -1, 0, 1, 37, 90, 179];

/* Пояс места — явный параметр, а не системный. Для сетки берём ближайший
   целый час к долготе: он не обязан совпадать с политической картой, стенду
   важно лишь, что пояс задан числом и одинаков при каждом прогоне. */
function tzOfLon(lon) {
  return Math.max(-12, Math.min(14, Math.round(lon / 15)));
}

/* Места с некруглым поясом: половинки и четверти часа ломают арифметику,
   если где-то в переносе пояс станет целым Int. */
const ODD = [
  { lat: 27.7172, lon: 85.3240, tz: 5.75, name: "Катманду" },
  { lat: -43.9500, lon: -176.5600, tz: 12.75, name: "Чатем" },
  { lat: 56.4847, lon: 84.9482, tz: 7, name: "Томск" },
];

function places() {
  const out = [];
  for (const lat of LATS) for (const lon of LONS) out.push({ lat: lat, lon: lon, tz: tzOfLon(lon) });
  for (const p of ODD) out.push(p);
  return out;
}

/* Даты. Солнцестояния и равноденствия 2026 года ±1 день — там модель проходит
   крайние склонения; первое число каждого месяца трёх лет — ровная сетка года;
   29 февраля — високосный край; дни перевода часов — Европа и США, чтобы
   увидеть, что модель на них не реагирует вовсе (пояс у неё параметр). */
const SUN_DATES_2026 = ["2026-03-20", "2026-06-21", "2026-09-23", "2026-12-21"];
const DST_DAYS = ["2026-03-08", "2026-03-29", "2026-10-25", "2026-11-01"];
const LEAP_DAY = "2028-02-29";

function shiftDay(iso, delta) {
  const p = iso.split("-").map(Number);
  const d = new Date(p[0], p[1] - 1, p[2] + delta);
  return dayText(d);
}
function dayText(d) {
  return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2);
}
function toDate(iso) {
  const p = iso.split("-").map(Number);
  return new Date(p[0], p[1] - 1, p[2]);
}
function sortedUnique(list) {
  return Array.from(new Set(list)).sort();
}

function datesFull() {
  const out = [];
  for (const d of SUN_DATES_2026) for (const k of [-1, 0, 1]) out.push(shiftDay(d, k));
  for (const y of [2025, 2026, 2027]) for (let m = 1; m <= 12; m++) out.push(y + "-" + ("0" + m).slice(-2) + "-01");
  out.push(LEAP_DAY);
  for (const d of DST_DAYS) out.push(d);
  return sortedUnique(out);
}
/* Сетка минут — дорогая, поэтому дней в ней меньше: края года, оба
   солнцестояния с равноденствиями, високосный день и день перевода часов. */
const DATES_SAMPLE = sortedUnique(SUN_DATES_2026.concat(["2026-01-01", "2026-07-01", LEAP_DAY, "2026-03-29"]));
/* Состояния света сверяются по каждой минуте, поэтому дней ровно 20. */
function datesState() {
  const out = [];
  for (const d of SUN_DATES_2026) for (const k of [-1, 0, 1]) out.push(shiftDay(d, k));
  out.push("2026-01-01", "2026-04-01", "2026-07-01", "2026-10-01", LEAP_DAY,
    "2026-03-29", "2026-10-25", "2026-11-01");
  return sortedUnique(out);
}

/* Все границы состояний: по ним ходит `stateAt`, и на каждой обязан быть
   свой код. 6.05 — намеренный допуск золотого часа (7534), не опечатка. */
const ELEV_MARKS = [-18, -12, -6, -4, -0.833, 0, 6, 6.05, 20, 40];
const STEP_MIN = 10;

/* ============================================================
   СБОРКА ФИКСТУР
   ============================================================ */

const ctx = X.load();

/* Один день одного места: то, что в Swift станет SolarDay */
function solarDay(p, iso) {
  X.setPlace(ctx, p);
  ctx.computeSun(toDate(iso));
  const S = ctx.SUN;
  return {
    lat: p.lat, lon: p.lon, tz: p.tz, date: iso,
    decl: ctx.decl, solarNoon: ctx.solarNoon, mint: ctx.MINT, maxt: ctx.MAXT,
    rise: S.rise, set: S.set,
    goldA: S.goldA, goldB: S.goldB, blueA: S.blueA, blueB: S.blueB,
    civA: S.civA, civB: S.civB, nauA: S.nauA, nauB: S.nauB, astA: S.astA, astB: S.astB,
    maxElev: S.maxElev, polar: S.polar, arcA: S.arcA, arcB: S.arcB,
  };
}

/* Минуты суток: каждые 10 минут шкалы плюс все моменты, где солнце стоит
   ровно на границе состояния. Границы важнее сетки: именно на них
   расходятся переносы. */
function timesOfDay() {
  const out = [];
  for (let t = ctx.MINT; t <= ctx.MAXT + 1e-9; t += STEP_MIN) out.push(t);
  for (const h of ELEV_MARKS) for (const rising of [true, false]) {
    const t = ctx.tAtElev(h, rising);
    if (t !== null) out.push(t);
  }
  return sortedUniqueNums(out);
}
function sortedUniqueNums(list) {
  const s = list.slice().sort(function (a, b) { return a - b; });
  const out = [];
  for (const v of s) if (!out.length || out[out.length - 1] !== v) out.push(v);
  return out;
}

function solarSample(p, iso) {
  X.setPlace(ctx, p);
  ctx.computeSun(toDate(iso));
  const t = timesOfDay();
  const rec = { lat: p.lat, lon: p.lon, tz: p.tz, date: iso, t: t, elev: [], az: [], shadow: [] };
  for (const v of t) {
    rec.elev.push(ctx.elevAt(v));
    rec.az.push(ctx.azAt(v));
    rec.shadow.push(ctx.shadowAt(v));
  }
  return rec;
}

/* Состояние света на каждой минуте. Хранится отрезками: код, уровень, тон и
   зарево внутри состояния постоянны, меняется только цвет неба — он и идёт
   отдельной сеткой. Отрезки короче и читаются глазом, а сверка от этого не
   слабеет: Swift разворачивает их обратно в каждую минуту. */
function lightState(p, iso) {
  X.setPlace(ctx, p);
  ctx.computeSun(toDate(iso));
  const t0 = Math.ceil(ctx.MINT), t1 = Math.floor(ctx.MAXT);
  const runs = [], shadow = [], next = [], sky = [];
  let prev = null, prevWord = null, prevNext = null;
  for (let t = t0; t <= t1; t++) {
    const s = ctx.stateAt(t);
    const key = [s.k, s.level === undefined ? null : s.level, s.tone, s.glow, s.stars === true];
    if (!prev || key.join("|") !== prev.join("|")) {
      runs.push([t, key[0], key[1], key[2], key[3], key[4]]);
      prev = key;
    }
    const w = ctx.shadowWord(t);
    if (w !== prevWord) { shadow.push([t, w]); prevWord = w; }
    const n = ctx.nextLight(t);
    /* Цель события, а не остаток: остаток линейно тает с каждой минутой,
       а цель постоянна внутри отрезка — Swift считает остаток сам и
       сверяет его на любой минуте. */
    const target = n.m === null ? null : t + n.m;
    const nk = n.l + "|" + (target === null ? "-" : target.toFixed(9));
    if (nk !== prevNext) { next.push([t, n.l, target]); prevNext = nk; }
    if ((t - t0) % STEP_MIN === 0) {
      const c = ctx.skyColor(ctx.elevAt(t));
      sky.push([t, c[0], c[1], c[2]]);
    }
  }
  return { lat: p.lat, lon: p.lon, tz: p.tz, date: iso, t0: t0, t1: t1,
    runs: runs, shadow: shadow, next: next, sky: sky };
}

/* Отдельно — сами границы: момент, когда солнце стоит ровно на пороге, и
   состояние в этот момент.

   Замер 20 сентября 2026: обратный ход `tAtElev(h) → elevAt(t)` сходится до
   4e-14°, но порог в коде — строгое «больше», и этих четырнадцати знаков
   хватает, чтобы точка легла по любую сторону. На 6.05° из 346 меток 145
   оказались золотым часом, 201 — уже вечером или утренним теплом. Значит сам
   порог кодом не проверяется: на нём сторону выбирает последний бит.
   Поэтому рядом лежат `guards` — пробы на сотую градуса от порога, где сторона
   определена и не зависит ни от языка, ни от библиотеки синусов. */
function marks(p, iso) {
  X.setPlace(ctx, p);
  ctx.computeSun(toDate(iso));
  const out = [];
  for (const h of ELEV_MARKS) for (const rising of [true, false]) {
    const t = ctx.tAtElev(h, rising);
    if (t === null) continue;
    const s = ctx.stateAt(t);
    out.push({ lat: p.lat, lon: p.lon, tz: p.tz, date: iso, h: h, rising: rising,
      t: t, elev: ctx.elevAt(t), k: s.k,
      level: s.level === undefined ? null : s.level, tone: s.tone, glow: s.glow });
  }
  return out;
}

/* Пробы по обе стороны каждого порога, на сотую градуса от него: там сторона
   определена, и «строгое равенство кодов» из § 5.2 проверяемо. Сетка мельче,
   чем у меток: порог — свойство модели, а не места. */
const GUARD_STEP = 0.01;
function guards(p, iso) {
  X.setPlace(ctx, p);
  ctx.computeSun(toDate(iso));
  const out = [];
  for (const h of ELEV_MARKS) for (const side of [-1, 1]) for (const rising of [true, false]) {
    const at = h + side * GUARD_STEP;
    const t = ctx.tAtElev(at, rising);
    if (t === null) continue;
    const s = ctx.stateAt(t);
    out.push({ lat: p.lat, lon: p.lon, tz: p.tz, date: iso, h: h, side: side, rising: rising,
      t: t, elev: ctx.elevAt(t), k: s.k,
      level: s.level === undefined ? null : s.level, tone: s.tone, glow: s.glow });
  }
  return out;
}

/* Закатный балл: сетка по 10 % на каждый ярус облаков и влажность.
   Порядок обхода задан в meta, поэтому в файле лежат одни баллы —
   14 641 целых чисел вместо 14 641 объектов. */
function sunsetScores() {
  const ax = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
  const scores = [];
  for (const low of ax) for (const mid of ax) for (const high of ax) for (const hum of ax) {
    scores.push(ctx.sunsetScore(low, mid, high, hum, null));
  }
  const air = [];
  const AIR = [null, { aod: 0.05 }, { aod: 0.15 }, { aod: 0.35 }, { aod: 0.6 }, { aod: 1.2, dust: 30 }];
  for (const low of [0, 40, 80]) for (const mid of [20, 45, 80]) for (const high of [20, 50, 80]) {
    for (const hum of [30, 75]) for (const a of AIR) {
      air.push({ low: low, mid: mid, high: high, hum: hum, aod: a ? a.aod : null,
        score: ctx.sunsetScore(low, mid, high, hum, a) });
    }
  }
  return { axis: ax, order: "low,mid,high,hum", scores: scores, air: air };
}

/* Луна: alt, az, dist каждые три часа. Широты — шесть, долгота одна:
   луна от долготы зависит только через часовой угол, и удваивать сетку
   ради этого незачем. */
const MOON_LATS = [-45, 0, 23.4, 45, 56.02, 66.6];
function moonSeries(p, iso) {
  X.setPlace(ctx, p);
  const d = toDate(iso);
  const rec = { lat: p.lat, lon: p.lon, tz: p.tz, date: iso, t: [], alt: [], az: [], dist: [] };
  for (let t = 0; t < 1440; t += 180) {
    const m = ctx.moonAt(d, t);
    rec.t.push(t); rec.alt.push(m.alt); rec.az.push(m.az); rec.dist.push(m.dist);
  }
  return rec;
}

/* ---------- Слияние двух снимков ----------
   Архитектура (§ 7 docs/17) велит сверять `mergeStores` парами снимков:
   веб сливает пару, результат ложится в фикстуру. Пары — не случайные: каждая
   названа правилом, которое она проверяет. Прогон идёт в обе стороны, потому
   что главное свойство слияния — стороны не важны: иначе два устройства
   выберут разные версии и разойдутся навсегда.

   Функция чистая: `Date.now` внутри неё нет (обрезка отметки из будущего живёт
   в месте записи, срок надгробия — в чтении). Поэтому фикстура повторяема. */
const MERGE_PAIRS = [
  { name: "объединение списков",
    a: { dev: "A", sessions: [{ id: "s1", mt: 10, n: "моя" }] },
    b: { dev: "B", sessions: [{ id: "s2", mt: 10, n: "чужая" }] } },
  { name: "позднейшая правка побеждает",
    a: { dev: "A", sessions: [{ id: "s1", mt: 20, n: "новее" }] },
    b: { dev: "B", sessions: [{ id: "s1", mt: 10, n: "старее" }] } },
  { name: "равные отметки разрешаются меткой устройства",
    a: { dev: "A", sessions: [{ id: "s1", mt: 10, n: "от A" }] },
    b: { dev: "B", sessions: [{ id: "s1", mt: 10, n: "от B" }] } },
  { name: "запись без отметки — самая старая",
    a: { dev: "A", sessions: [{ id: "s1", n: "без отметки" }] },
    b: { dev: "B", sessions: [{ id: "s1", mt: 1, n: "с отметкой" }] } },
  { name: "пустое устройство не стирает книгу",
    a: { dev: "A", sessions: [{ id: "s1", mt: 10, n: "моя" }] },
    b: { dev: "B" } },
  { name: "отсутствие записи не значит удаление",
    a: { dev: "A", sessions: [{ id: "s1", mt: 10 }, { id: "s2", mt: 10 }] },
    b: { dev: "B", sessions: [{ id: "s1", mt: 11 }] } },
  { name: "надгробие позже правки — запись уходит",
    a: { dev: "A", sessions: [{ id: "s1", mt: 10, n: "жива" }] },
    b: { dev: "B", graves: [{ id: "s1", del: 20 }] } },
  { name: "правка позже надгробия — запись возвращается",
    a: { dev: "A", sessions: [{ id: "s1", mt: 30, n: "правили после" }] },
    b: { dev: "B", graves: [{ id: "s1", del: 20 }] } },
  { name: "одно надгробие на двух устройствах — позднейшее время",
    a: { dev: "A", graves: [{ id: "s1", del: 10 }] },
    b: { dev: "B", graves: [{ id: "s1", del: 25 }] } },
  { name: "корзина: удалили на одном, вернули на другом",
    a: { dev: "A", trashed: [{ rec: { id: "s1", mt: 5 }, del: 10 }] },
    b: { dev: "B", sessions: [{ id: "s1", mt: 20, n: "вернули" }] } },
  { name: "корзина побеждает старую правку",
    a: { dev: "A", sessions: [{ id: "s1", mt: 5, n: "старая" }] },
    b: { dev: "B", trashed: [{ rec: { id: "s1", mt: 5 }, del: 10 }] } },
  { name: "корзина по убыванию времени удаления",
    a: { dev: "A", trashed: [{ rec: { id: "s1" }, del: 10 }, { rec: { id: "s2" }, del: 30 }] },
    b: { dev: "B", trashed: [{ rec: { id: "s3" }, del: 20 }] } },
  { name: "все шесть списков сливаются одинаково",
    a: { dev: "A", sessions: [{ id: "x1", mt: 1 }], orgs: [{ id: "o1", mt: 1 }], spots: [{ id: "p1", mt: 1 }] },
    b: { dev: "B", blocks: [{ id: "b1", mt: 1 }], shots: [{ id: "h1", mt: 1 }], boards: [{ id: "d1", mt: 1 }] } },
  { name: "настройка с поздней отметкой побеждает",
    a: { dev: "A", theme: "dark", setMt: { theme: 10 } },
    b: { dev: "B", theme: "light", setMt: { theme: 20 } } },
  { name: "настройка есть только у одного — приходит от него",
    a: { dev: "A", lang: "ru", setMt: { lang: 1 } },
    b: { dev: "B", setMt: {} } },
  { name: "списки не считаются настройками",
    a: { dev: "A", sessions: [{ id: "s1", mt: 1 }], setMt: { sessions: 99 } },
    b: { dev: "B", sessions: [{ id: "s2", mt: 1 }] } },
  { name: "цепочка прежних номеров объединяется",
    a: { dev: "A", me: { ids: [{ was: "+79990000001", at: "2026-01-02" }] } },
    b: { dev: "B", me: { ids: [{ was: "+79990000002", at: "2026-01-01" }] } } },
];

function mergePairs() {
  const M = ctx.mergeStores;
  return MERGE_PAIRS.map(function (p) {
    return { name: p.name, a: p.a, b: p.b, ab: M(p.a, p.b), ba: M(p.b, p.a) };
  });
}

/* Млечный Путь: полоса — константа неба, поворот над головой — переменная. */
function milkyWay() {
  const band = ctx.MW_BAND.map(function (p) { return [p.l, p.w, p.c.ra, p.c.dec]; });
  const altaz = [];
  for (const lat of [0, 45, 66.6]) {
    X.setPlace(ctx, { lat: lat, lon: 37, tz: 2 });
    for (const iso of ["2026-03-20", "2026-06-21", "2026-09-23", "2026-12-21"]) {
      for (const t of [0, 360, 720, 1080]) {
        const d = ctx.toDays(ctx.instant(toDate(iso), t));
        const c = ctx.eqToAltAz(ctx.MW_CORE.ra, ctx.MW_CORE.dec, d);
        altaz.push({ lat: lat, lon: 37, tz: 2, date: iso, t: t, d: d, alt: c.alt, az: c.az });
      }
    }
  }
  return { band: band, core: { ra: ctx.MW_CORE.ra, dec: ctx.MW_CORE.dec }, coreAltAz: altaz };
}

/* ============================================================
   САМОПРОВЕРКА
   Известные значения, взятые не из этого же кода: две контрольные точки
   галактики из астрономии, полярные сутки, полдень на экваторе в
   равноденствие, два балла заката, выведенные из описанных правил, и
   намеренный допуск 6.05.
   ============================================================ */
function selfcheck() {
  const rows = [];
  function chk(name, got, want, tol) {
    const ok = typeof want === "number" ? Math.abs(got - want) <= (tol || 0) : got === want;
    rows.push({ ok: ok, name: name, got: got, want: want });
    return ok;
  }
  const degOf = function (r) { return (r * 180 / Math.PI + 360) % 360; };

  const c0 = ctx.galToEq(0, 0), c180 = ctx.galToEq(180, 0);
  chk("галактика l=0 → RA 266.405", degOf(c0.ra), 266.405, 1e-3);
  chk("галактика l=0 → Dec −28.936", c0.dec * 180 / Math.PI, -28.936, 1e-3);
  chk("галактика l=180 → RA 86.405", degOf(c180.ra), 86.405, 1e-3);
  chk("галактика l=180 → Dec +28.936", c180.dec * 180 / Math.PI, 28.936, 1e-3);

  X.setPlace(ctx, { lat: 78, lon: 0, tz: 0 });
  ctx.computeSun(toDate("2026-06-21"));
  chk("78° с. ш., 21 июня → полярный день", ctx.SUN.polar, 1);
  ctx.computeSun(toDate("2026-12-21"));
  chk("78° с. ш., 21 декабря → полярная ночь", ctx.SUN.polar, -1);

  X.setPlace(ctx, { lat: 0, lon: 0, tz: 0 });
  ctx.computeSun(toDate("2026-03-20"));
  chk("экватор в равноденствие → солнце в зените", ctx.SUN.maxElev, 90, 0.6);

  /* Допуск золотого часа: ниже 6.05° ещё золотой час, выше — уже вечер.
     Числа взяты у самой границы, чтобы тест ловил её сдвиг. */
  X.setPlace(ctx, { lat: 55.03, lon: 83.75, tz: 7 });
  ctx.computeSun(toDate("2026-06-21"));
  chk("6.04° вечером → золотой час", ctx.stateAt(ctx.tAtElev(6.04, false)).k, "golden");
  chk("6.06° вечером → вечер", ctx.stateAt(ctx.tAtElev(6.06, false)).k, "evening");

  /* Закатный балл выводится из описанных правил: лучший экран (50 %) и лучшая
     текстура (45 %) дают 30 + 45 + 25 = 100 при открытом горизонте; сплошной
     низкий ярус оставляет от этого 5 %. */
  chk("балл: чистый горизонт, лучшие ярусы", ctx.sunsetScore(0, 45, 50, 0, null), 100);
  chk("балл: сплошной низкий ярус гасит всё", ctx.sunsetScore(100, 45, 50, 0, null), 5);

  const bad = rows.filter(function (r) { return !r.ok; });
  for (const r of rows) {
    console.log((r.ok ? "  ок  " : "  НЕТ ") + r.name +
      (r.ok ? "" : ": получено " + r.got + ", ждали " + r.want));
  }
  console.log("самопроверка: " + rows.length + " значений, расхождений: " + bad.length);
  return bad.length === 0;
}

/* ============================================================
   ЗАПИСЬ
   ============================================================ */

/* Свой вывод вместо JSON.stringify(…, null, 2): числовые ряды остаются в одну
   строку, всё остальное разбито по строкам. Файл и читается глазом, и не
   раздувается втрое. Порядок ключей — порядок вставки, поэтому вывод
   повторяем. */
function ser(v, pad) {
  if (v === null || typeof v !== "object") return JSON.stringify(v);
  const flat = JSON.stringify(v);
  if (flat.length <= 110) return flat;
  if (Array.isArray(v)) {
    if (v.every(function (x) { return typeof x === "number" || x === null; })) return flat;
    return "[\n" + v.map(function (x) { return pad + "  " + ser(x, pad + "  "); }).join(",\n") + "\n" + pad + "]";
  }
  return "{\n" + Object.keys(v).map(function (k) {
    return pad + "  " + JSON.stringify(k) + ": " + ser(v[k], pad + "  ");
  }).join(",\n") + "\n" + pad + "}";
}

const DIGEST = X.sourceDigest();
function write(dir, name, meta, body) {
  const obj = { meta: Object.assign({ source: "beta/index.html", cut: DIGEST }, meta) };
  for (const k of Object.keys(body)) obj[k] = body[k];
  const text = ser(obj, "") + "\n";
  fs.writeFileSync(path.join(dir, name), text);
  return { name: name, bytes: Buffer.byteLength(text),
    sha: crypto.createHash("sha256").update(text).digest("hex").slice(0, 12) };
}

function main() {
  const argOut = process.argv.indexOf("--out");
  const dir = path.resolve(argOut > 0 ? process.argv[argOut + 1] : path.join(X.ROOT, "Fixtures"));
  const quiet = process.argv.indexOf("--quiet") > 0;
  fs.mkdirSync(dir, { recursive: true });

  if (!selfcheck()) {
    console.error("Фикстуры не записаны: генератор не сошёлся на известных значениях.");
    process.exit(1);
  }

  const P = places(), DF = datesFull(), DS = datesState();
  const samplePlaces = LATS.map(function (lat) { return { lat: lat, lon: 37, tz: 2 }; }).concat(ODD);
  const statePlaces = LATS.map(function (lat) { return { lat: lat, lon: 37, tz: 2 }; });
  const out = [];

  const days = [];
  for (const p of P) for (const d of DF) days.push(solarDay(p, d));
  out.push(write(dir, "solar_day.json", {
    what: "день целиком: склонение, полдень, все события по высотам, полярность",
    grid: "широты × долготы × даты § 5.2, плюс места с некруглым поясом",
    tolerance: { times: 1e-6, degrees: 1e-9, polar: "строго" },
    count: days.length,
  }, { days: days }));

  const samples = [];
  for (const p of samplePlaces) for (const d of DATES_SAMPLE) samples.push(solarSample(p, d));
  out.push(write(dir, "solar_sample.json", {
    what: "высота, азимут и длина тени по минутам шкалы",
    grid: "каждые " + STEP_MIN + " минут от MINT до MAXT плюс все моменты границ состояний",
    tolerance: { degrees: 1e-9, shadow: 1e-9, nullIsNull: "строго" },
    count: samples.reduce(function (n, r) { return n + r.t.length; }, 0),
  }, { series: samples }));

  const states = [], markRows = [], guardRows = [];
  for (const p of statePlaces) for (const d of DS) {
    states.push(lightState(p, d));
    for (const m of marks(p, d)) markRows.push(m);
    if (SUN_DATES_2026.indexOf(d) >= 0) for (const g of guards(p, d)) guardRows.push(g);
  }
  out.push(write(dir, "light_state.json", {
    what: "код состояния, уровень прибора, тон, зарево и цвет неба",
    grid: "каждая минута шкалы; цвет неба каждые " + STEP_MIN + " минут; отрезками",
    tolerance: { code: "строго", level: "строго", tone: "строго", glow: "строго", sky: "строго" },
    note: "next хранит цель события, а не остаток: остаток = цель − минута. " +
      "marks — пробы ровно на пороге, там сторону выбирает последний бит; " +
      "сторону порога проверяют guards, на " + GUARD_STEP + "° от него",
    count: states.reduce(function (n, r) { return n + (r.t1 - r.t0 + 1); }, 0),
  }, { days: states, marks: markRows, guards: guardRows }));

  const score = sunsetScores();
  out.push(write(dir, "sunset_score.json", {
    what: "закатный балл по трём ярусам облаков, влажности и аэрозолю",
    grid: "low × mid × high × hum по 10 %, порядок в order; аэрозоль отдельной таблицей",
    tolerance: { score: "строго, целое" },
    count: score.scores.length + score.air.length,
  }, score));

  const moon = [];
  for (const lat of MOON_LATS) for (const d of DF) {
    if (!/-01$/.test(d)) continue;
    moon.push(moonSeries({ lat: lat, lon: 37, tz: 2 }, d));
  }
  out.push(write(dir, "moon.json", {
    what: "высота, азимут и расстояние до луны",
    grid: "6 широт × первое число каждого месяца трёх лет × каждые 3 часа",
    tolerance: { degrees: 1e-7, dist: 1e-7 },
    count: moon.reduce(function (n, r) { return n + r.t.length; }, 0),
  }, { series: moon }));

  const pairs = mergePairs();
  out.push(write(dir, "merge_pairs.json", {
    what: "слияние двух снимков: пара на каждое правило",
    grid: "каждая пара слита в обе стороны — стороны обязаны быть не важны",
    tolerance: { result: "строго, включая порядок записей в списках" },
    count: pairs.length * 2,
  }, { pairs: pairs }));

  const mw = milkyWay();
  out.push(write(dir, "milkyway.json", {
    what: "полоса галактического экватора и поворот ядра над головой",
    grid: "полоса шагом 3° (константа неба); ядро — 3 широты × 4 даты × 4 часа",
    tolerance: { degrees: 1e-9, checkpoints: "l=0 → 266.405 / −28.936, l=180 → 86.405 / +28.936" },
    count: mw.band.length + mw.coreAltAz.length,
  }, mw));

  if (!quiet) {
    console.log("\nвырезка из беты: " + DIGEST + "\nпапка: " + dir);
    let total = 0;
    for (const f of out) {
      total += f.bytes;
      console.log("  " + f.name.padEnd(20) + String(f.bytes).padStart(9) + " байт  " + f.sha);
    }
    console.log("  " + "всего".padEnd(20) + String(total).padStart(9) + " байт");
  }
}

try {
  main();
} catch (e) {
  /* Стек здесь не нужен: обычная причина — уехавший якорь, а не ошибка стенда */
  console.error("\n" + e.message);
  process.exit(1);
}
