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
   55.03 — Барнаул, живое место из продукта; ±90 — сами полюса, где
   cos(широты) в double не нуль, а 6e-17 (добавлено итерацией 7). */
const LATS = [-90, -78, -66.6, -45, -23.4, 0, 23.4, 45, 55.03, 66.6, 78, 90];
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
  const rec = { lat: p.lat, lon: p.lon, tz: p.tz, date: iso, t: [], alt: [], az: [], dist: [],
    frac: [], phase: [], name: [] };
  for (let t = 0; t < 1440; t += 180) moonPoint(rec, d, t);
  return rec;
}
/* Одна точка луны: положение, доля диска и код фазы (LANG.t в стенде отдаёт
   сам ключ, поэтому phaseName возвращает код). */
function moonPoint(rec, d, t) {
  const m = ctx.moonAt(d, t), ph = ctx.moonPhase(d, t);
  rec.t.push(t); rec.alt.push(m.alt); rec.az.push(m.az); rec.dist.push(m.dist);
  rec.frac.push(ph.fraction); rec.phase.push(ph.phase); rec.name.push(ctx.phaseName(ph.phase));
}

/* Пробы со «страшным» временем. Ползунок таймбара даёт дробные минуты, а веб
   собирает момент через `new Date(мс)`, и та обрезает дробные миллисекунды. Луна
   уходит за это на 4e-6° в миллисекунду — больше допуска 1e-7, — поэтому Swift
   обязан обрезать так же. Здесь t, дающие дробные миллисекунды, отрицательные
   минуты и минуты за пределом суток (`moonArc` ходит от −720 до +2900). Места —
   с дробным поясом и по обе стороны антимеридиана. */
const MOON_PROBE_PLACES = [
  { lat: 55.03, lon: 83.0, tz: 7 },
  { lat: 27.7172, lon: 85.3240, tz: 5.75 },
  { lat: -43.95, lon: -176.56, tz: 12.75 },
  { lat: 66.6, lon: 179, tz: -11 },
];
const MOON_PROBE_DATES = ["2026-03-20", "2026-09-23", "2028-02-29"];
const MOON_PROBE_T = [0.3333333333333333, 100.0004, 359.99999, 723.3333333333334,
  1439.9999, -37.5, -719.7, 1500.25, 2899.9, 61.0000001];
function moonProbes() {
  const out = [];
  for (const p of MOON_PROBE_PLACES) for (const iso of MOON_PROBE_DATES) {
    X.setPlace(ctx, p);
    const d = toDate(iso);
    const rec = { lat: p.lat, lon: p.lon, tz: p.tz, date: iso, t: [], alt: [], az: [], dist: [],
      frac: [], phase: [], name: [] };
    for (const t of MOON_PROBE_T) moonPoint(rec, d, t);
    out.push(rec);
  }
  return out;
}

/* Фаза по трём годам: четыре отсчёта в сутки. От места не зависит (доля диска
   и фаза — это Солнце и Луна, а не горизонт), поэтому одно место. Коды — как
   индексы в `codes`, чтобы строки не повторялись четыре тысячи раз. */
function phaseSweep() {
  X.setPlace(ctx, { lat: 56.02, lon: 37.48, tz: 3 });
  const codes = [], out = { tz: 3, y: [], m: [], d: [], t: [], frac: [], phase: [], code: [] };
  for (let day = new Date(2026, 0, 1); day.getFullYear() < 2029; day = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1)) {
    for (const t of [0, 360, 720, 1080]) {
      const ph = ctx.moonPhase(day, t), name = ctx.phaseName(ph.phase);
      if (codes.indexOf(name) < 0) codes.push(name);
      out.y.push(day.getFullYear()); out.m.push(day.getMonth() + 1); out.d.push(day.getDate());
      out.t.push(t); out.frac.push(ph.fraction); out.phase.push(ph.phase); out.code.push(codes.indexOf(name));
    }
  }
  out.codes = codes;
  return out;
}

/* Затмения: сама таблица и ответы `eclipseOn` / `nextEclipse` на каждые сутки
   с середины 2025 до начала 2031 — за край таблицы тоже, где «ближайшего»
   уже нет. Ответ — индекс строки в таблице, −1 значит «нет». */
function eclipseSweep() {
  const table = ctx.ECLIPSES.map(function (e) { return { d: e.d, kind: e.kind, where: e.where }; });
  const idx = function (e) { return e ? ctx.ECLIPSES.indexOf(e) : -1; };
  const out = { from: "2025-06-01", on: [], next: [] };
  let n = 0;
  for (let day = toDate(out.from); dayText(day) !== "2031-03-01"; day = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1)) {
    out.on.push(idx(ctx.eclipseOn(day)));
    out.next.push(idx(ctx.nextEclipse(day)));
    n++;
  }
  return { table: table, sweep: out, days: n };
}

/* ============================================================
   ИТЕРАЦИЯ 10 — ПОГОДА И ЗАКАТНЫЙ БАЛЛ
   ============================================================ */

/* Темнота в произвольную дату: сетка широт § 5.2 (долгота и пояс — как у
   statePlaces, 37/2) на солнцестояния/равноденствия и их соседей — там модель
   проходит крайние склонения. `next` — только на четырёх датах 2026 года:
   190 шагов на комбинацию, дороже, чем `has`. */
function astroNightSweep() {
  const hasRows = [], nextRows = [];
  for (const lat of LATS) {
    X.setPlace(ctx, { lat: lat, lon: 37, tz: 2 });
    for (const iso of datesFull()) {
      hasRows.push({ lat: lat, date: iso, has: ctx.hasAstroNight(toDate(iso)) });
    }
    for (const iso of SUN_DATES_2026) {
      const n = ctx.nextAstroNight(toDate(iso));
      nextRows.push({ lat: lat, date: iso, next: n ? dayText(n) : null });
    }
  }
  return { has: hasRows, next: nextRows };
}

/* Мок офлайн: чистая функция даты, широта ни при чём. Сетка — все сутки
   2026 года плюс несколько дат на границах года и семян с несовпадающей
   разрядностью (29 февраля, стык годов), чтобы поймать порчу семени. */
function mockSweep() {
  const dates = daysOf2026().concat(["2025-12-31", "2027-01-01", LEAP_DAY]);
  const rows = [];
  for (const iso of dates) {
    const d = toDate(iso);
    const w = ctx.dayWeather(d);
    rows.push({ date: iso, q: ctx.qualityOf(d), cloud: w.cloud, tempBase: w.tempBase, wind: w.wind, trend: w.trend });
  }
  return rows;
}

/* Синтетический почасовой ответ Open-Meteo — детерминированный, без сети и
   без Math.random: `buildWx` считается только из чисел, которые сам стенд и
   придумал. `withOptional=false` опускает необязательные ряды целиком —
   проверка запасных значений (`has(k)`) на весь ряд, а не на час. */
function syntheticHourly(startIso, days, opts) {
  opts = opts || {};
  const time = [], cloud = [], low = [], mid = [], high = [], hum = [], temp = [], wind = [],
    wdir = [], gust = [], precip = [], code = [];
  const start = toDate(startIso);
  for (let dd = 0; dd < days; dd++) {
    const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + dd);
    const iso = dayText(day);
    for (let hh = 0; hh < 24; hh++) {
      time.push(iso + "T" + String(hh).padStart(2, "0") + ":00");
      const c = opts.cloud !== undefined ? opts.cloud : (30 + dd * 5 + hh) % 101;
      cloud.push(c);
      low.push(opts.low !== undefined ? opts.low : Math.max(0, c - 20));
      mid.push(opts.mid !== undefined ? opts.mid : c);
      high.push(opts.high !== undefined ? opts.high : Math.min(100, c + 10));
      hum.push(opts.hum !== undefined ? opts.hum : 40 + (hh % 12) * 3);
      temp.push(opts.temp !== undefined ? opts.temp : 10 + Math.sin(hh / 24 * Math.PI * 2) * 8);
      wind.push(opts.wind !== undefined ? opts.wind : 2 + (hh % 5));
      wdir.push(opts.wdir !== undefined ? opts.wdir : (hh * 37) % 360);
      gust.push(opts.gust !== undefined ? opts.gust : 3 + (hh % 4));
      precip.push(opts.precipAt && opts.precipAt(dd, hh) !== undefined ? opts.precipAt(dd, hh) : 0);
      code.push(opts.codeAt ? opts.codeAt(dd, hh) : 0);
    }
  }
  const h = { time: time, cloud_cover: cloud, temperature_2m: temp, wind_speed_10m: wind,
    precipitation: precip, weather_code: code };
  if (opts.withOptional !== false) {
    h.cloud_cover_low = low; h.cloud_cover_mid = mid; h.cloud_cover_high = high;
    h.relative_humidity_2m = hum; h.wind_direction_10m = wdir; h.wind_gusts_10m = gust;
  }
  return h;
}

/* `buildWx` по нескольким сценариям: обычный день, ряды без необязательных
   полей, туман поутру, дождь перебивает категорию, полярный день (часа заката
   нет вовсе), дробный пояс (Катманду), поправка на аэрозоль в час заката. */
function weatherDaySweep() {
  const cases = [
    { name: "обычный, все поля", place: { lat: 56.02, lon: 37.48, tz: 3 }, startIso: "2026-06-10", days: 2 },
    { name: "только обязательные поля", place: { lat: 56.02, lon: 37.48, tz: 3 }, startIso: "2026-06-10", days: 1,
      opts: { withOptional: false } },
    { name: "туман поутру", place: { lat: 45, lon: 37, tz: 2 }, startIso: "2026-10-05", days: 1,
      opts: { codeAt: function (dd, hh) { return hh >= 6 && hh <= 8 ? 45 : 0; } } },
    { name: "дождь перебивает категорию", place: { lat: 45, lon: 37, tz: 2 }, startIso: "2026-10-06", days: 1,
      opts: { cloud: 10, low: 5, mid: 5, high: 5, codeAt: function () { return 61; }, precipAt: function () { return 1.2; } } },
    { name: "полярный день — часа заката нет", place: { lat: 78, lon: 0, tz: 0 }, startIso: "2026-06-21", days: 1 },
    { name: "дробный пояс — Катманду", place: { lat: 27.7172, lon: 85.324, tz: 5.75 }, startIso: "2026-03-13", days: 1 },
    { name: "южное полушарие, высокая влажность", place: { lat: -33.45, lon: -70.66, tz: -4 }, startIso: "2026-07-15", days: 1,
      opts: { hum: 88 } },
    { name: "аэрозоль поправляет закатный балл", place: { lat: 45, lon: 37, tz: 2 }, startIso: "2026-10-07", days: 1,
      air: { aod: 0.55, dust: 30 } },
  ];
  const airBySpec = function (spec) {
    const byHour = {};
    for (let hh = 0; hh < 24; hh++) byHour[hh] = { aod: spec.aod, dust: spec.dust };
    return byHour;
  };
  const out = [];
  for (const c of cases) {
    X.setPlace(ctx, c.place);
    const h = syntheticHourly(c.startIso, c.days, c.opts || {});
    const airInput = {};
    if (c.air) {
      const start = toDate(c.startIso);
      for (let dd = 0; dd < c.days; dd++) {
        const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + dd);
        airInput[dayText(day)] = airBySpec(c.air);
      }
    }
    ctx.airDay = {};
    for (const k in airInput) ctx.airDay[k] = { byHour: airInput[k] };
    const days = ctx.buildWx(h);
    const hourly = ctx.wxByHour;
    const dayKeys = Object.keys(days).sort();
    out.push({
      name: c.name, lat: c.place.lat, lon: c.place.lon, tz: c.place.tz,
      // Вход — то же, чем кормили buildWx: без сети и без выдумки на лету,
      // Swift обязан прийти к тому же результату на этих же числах.
      input: h, airInput: airInput,
      days: dayKeys.map(function (k) { return { key: k, v: days[k] }; }),
      hourly: dayKeys.map(function (k) { return { key: k, hours: hourly[k] }; }),
    });
  }
  return out;
}

/* `mwSkyAt`: погода над окном Млечного Пути. Место и дата взяты так, чтобы
   окно было не пустым (проверено 22 сентября 2026 стендом вручную) — 45°
   с. ш. даёт окно каждую ночь марта, а 10 мая даёт отрезок, переходящий через
   солнечную полночь в обе стороны (`from < 0`), — сама функция дню не верит,
   а спрашивает соседние сутки по `dayOffset`. Облачность, влажность и
   аэрозоль перебираются сеткой, чтобы пройти все ветви `look`/`word`. */
function mwSkySweep() {
  const place = { lat: 45, lon: 37, tz: 2 };
  const cases = [
    { iso: "2026-03-15", cloud: 80, hum: 50, air: null, why: "cloud≥70 → poor" },
    { iso: "2026-03-15", cloud: 50, hum: 50, air: null, why: "35≤cloud<70 → good" },
    { iso: "2026-03-15", cloud: 20, hum: 50, air: null, why: "низкая облачность, высокий балл → excellent" },
    { iso: "2026-03-15", cloud: 20, hum: 85, air: null, why: "влажность топит балл ниже 75 → plain" },
    { iso: "2026-03-15", cloud: 10, hum: 50, air: { aod: 0.5, dust: 0 }, why: "дымка — aod даёт слово и plain" },
    { iso: "2026-03-15", cloud: 10, hum: 50, air: { aod: 0.1, dust: 25 }, why: "пыль — своё слово и штраф 15" },
    { iso: "2026-05-10", cloud: 30, hum: 60, air: null, why: "отрезок через солнечную полночь в обе стороны" },
  ];
  const out = [];
  for (const c of cases) {
    X.setPlace(ctx, place);
    const d = toDate(c.iso);
    ctx.computeSun(d);
    const w = ctx.mwWindow(d);
    // Синтетика на все сутки окна плюс соседей — окно у 10 мая цепляет и
    // предыдущий, и следующий день.
    const spanStartIso = dayText(new Date(d.getFullYear(), d.getMonth(), d.getDate() - 1));
    const h = syntheticHourly(spanStartIso, 3,
      { cloud: c.cloud, low: c.cloud, mid: c.cloud, high: c.cloud, hum: c.hum });
    ctx.buildWx(h);
    ctx.airDay = {};
    const airInput = {};
    if (c.air) {
      const byHour = {};
      for (let hh = 0; hh < 24; hh++) byHour[hh] = { aod: c.air.aod, dust: c.air.dust };
      for (let off = -1; off <= 1; off++) {
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate() + off);
        ctx.airDay[dayText(day)] = { byHour: byHour };
        airInput[dayText(day)] = byHour;
      }
    }
    const sky = ctx.mwSkyAt(d, w);
    out.push({
      date: c.iso, lat: place.lat, lon: place.lon, tz: place.tz, why: c.why,
      cloud: c.cloud, hum: c.hum, air: c.air || null,
      window: { spans: w.spans, dark: w.dark },
      // Вход, из которого посчитаны почасовые записи и воздух — без него
      // сверка не смогла бы повторить `buildWx`/`mwSkyAt` в Swift.
      input: h, spanStartIso: spanStartIso, airInput: airInput,
      sky: sky,
    });
  }
  return out;
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

/* Окна неба (итерация 9а): восход и заход луны, окно Млечного Пути, помеха
   луны звёздам. Одна запись — один день одного места, все три ответа рядом.

   Сетка: 12 широт × 3 долготы плюс три места с некруглым поясом × те же даты,
   что у солнца; плюс «сплошная» развёртка — каждые сутки 2026 года в четырёх
   местах, чтобы луна прошла все фазы и все положения относительно ночи. Полюса
   и полярные круги — в широтах: там луна не всходит, а тёмной части нет. */
const SKY_LONS = [-179, 37, 179];
const SKY_SWEEP_PLACES = [
  { lat: 56.02, lon: 37.48, tz: 3 },
  { lat: 45, lon: 37, tz: 2 },
  { lat: -45, lon: 170, tz: 12 },
  { lat: 69.65, lon: 18.96, tz: 1 },
];
/* Облако точек Млечного Пути (итерация 20а): экваториальные координаты,
   ярус, порог угасания — в порядке генерации. */
function mwDust() {
  return { haze: ctx.MW_HAZE, points: ctx.MW_DUST.map(function (p) { return [p.eq.ra, p.eq.dec, p.tier, p.fade]; }) };
}

/* Засветка (итерация 20б). Настоящих плиток в фикстуре нет: у атласа нет
   лицензии, и класть его данные в публичный репозиторий незачем. Плитка —
   синтетическая, из формулы, которую Swift-тест повторяет байт в байт;
   сверяется то, что и переносилось: ячейка, знак байта, ход приращений,
   развёртка сжатия, ступени и звёздные величины. */
/* Приращения −10…+10 (половина — знаковые байты больше 127), первая точка
   поднята до 128: иначе случайный ход уходит в минус и всё читается нулём. */
function glowTileByte(i) {
  if (i === 0) return 1;
  return (((Math.imul(i + 1, 2654435761) >>> 24) % 21) - 10) & 255;
}
function glowSweep() {
  const raw = new Uint8Array(ctx.GLOW_SIZE);
  for (let i = 0; i < raw.length; i++) raw[i] = glowTileByte(i);
  const pts = [];
  for (let lat = -70; lat <= 80; lat += 7.3) for (let lon = -180; lon <= 180; lon += 13.7) pts.push([lat, lon]);
  /* Швы и края: граница атласа, линия перемены дат, нулевой меридиан, ровная
     граница плиток, половина ячейки (215.2 у веба — DECISIONS) и места замеров
     при подключении. */
  pts.push([-65, 0], [-65.0001, 0], [74.9999, 10], [75, 10], [55, 180], [55, -180], [55, 0], [55, -0.0001],
    [60, 35], [59.99999, 35], [56.02, 35.2], [56.853, 35.2], [-24.627, -70.404], [50.0, 88.7],
    [69.17, 35.14], [38.64, 34.83], [56.01, 37.48], [59.94, 30.31], [55.75, 37.62], [36.5, -112.1]);
  const cells = pts.map(function (p) {
    const ix = ctx.glowIndex(p[0], p[1]);
    return { lat: p[0], lon: p[1], at: ix ? [ix.tx, ix.ty, ix.ix, ix.iy] : null,
      v: ix ? ctx.glowRead(raw, ix.ix, ix.iy) : null };
  });
  const ratios = [0, 0.009, 0.59, 0.999, 1, 7.99, 8, 26.99, 27, 35.5, 166, 1000];
  return { cells: cells, scale: ratios.map(function (r) { return { r: r, level: ctx.glowLevel(r), mag: ctx.glowMag(r) }; }),
    none: ctx.glowLevel(null) };
}

function skyPlaces() {
  const out = [];
  for (const lat of LATS) for (const lon of SKY_LONS) out.push({ lat: lat, lon: lon, tz: tzOfLon(lon) });
  for (const p of ODD) out.push(p);
  return out;
}
function daysOf2026() {
  const out = [];
  for (let d = new Date(2026, 0, 1); d.getFullYear() === 2026; d = new Date(2026, d.getMonth(), d.getDate() + 1)) {
    out.push(dayText(d));
  }
  return out;
}
/* Моменты, о которых спрашиваем `moonArc`: сетка сквозь сутки и за их край,
   а вокруг каждой найденной дуги — минута до восхода, сам восход, заход и
   минута после: там сравнение `>=` / `<=` меняет ответ. */
const ARC_ASK = [-720, -360, 0, 360, 720, 1080, 1439, 1440, 2000, 2900, 3600];

function skyRecord(p, iso) {
  X.setPlace(ctx, p);
  const d = toDate(iso);
  ctx.computeSun(d);
  /* Кэш веба ключуется датой и местом, но не поясом, — чистим перед каждой
     записью, чтобы два места с одной широтой не делили дуги. */
  ctx.moonCache = {};
  ctx.moonArc(d, 0);
  const cached = Object.keys(ctx.moonCache).map(function (k) { return ctx.moonCache[k]; })[0];
  const arcs = cached.map(function (a) { return [a.rise, a.set]; });
  const ask = ARC_ASK.slice();
  for (const a of arcs) ask.push(a[0] - 1, a[0], a[1], a[1] + 1);
  const qr = [], qs = [];
  for (const t of ask) {
    const a = ctx.moonArc(d, t);
    qr.push(a.none ? null : a.rise);
    qs.push(a.none ? null : a.set);
  }
  /* mwWindow берёт солнце выбранного дня из глобальных — оно уже посчитано
     computeSun(d); moonVsStars считает его сама и возвращает выбранный день,
     поэтому идёт последней. */
  const w = ctx.mwWindow(d);
  const v = ctx.moonVsStars(d);
  return {
    lat: p.lat, lon: p.lon, tz: p.tz, date: iso,
    arcs: arcs, qt: ask, qr: qr, qs: qs,
    win: {
      bestAlt: w.best.alt, bestT: w.best.t, from: w.from, to: w.to,
      spans: w.spans.map(function (s) { return [s.from, s.to]; }),
      dark: w.dark, moonBlocks: w.moonBlocks,
    },
    vs: {
      dark: v.dark, lit: v.lit, share: v.share,
      pct: v.pct === undefined ? null : v.pct,
      level: v.level === undefined ? null : v.level,
    },
  };
}
function skyWindows() {
  const grid = [], sweep = [];
  const DF = datesFull();
  for (const p of skyPlaces()) for (const d of DF) grid.push(skyRecord(p, d));
  const days = daysOf2026();
  for (const p of SKY_SWEEP_PLACES) for (const d of days) sweep.push(skyRecord(p, d));
  return { grid: grid, sweep: sweep };
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

  /* Луна и затмения: факты неба, а не этого кода. Солнечное затмение бывает
     только в новолуние, а лунное 3 марта 2026 — только в полнолуние. */
  X.setPlace(ctx, { lat: 56.02, lon: 37.48, tz: 3 });
  chk("12 августа 2026, день затмения → новолуние",
    ctx.phaseName(ctx.moonPhase(toDate("2026-08-12"), 1080).phase), "moon.new");
  chk("3 марта 2026 → полнолуние",
    ctx.phaseName(ctx.moonPhase(toDate("2026-03-03"), 720).phase), "moon.full");
  chk("затмение 12 августа 2026 → в таблице, полное",
    (ctx.eclipseOn(toDate("2026-08-12")) || {}).kind, "ecl.total");
  chk("13 августа 2026 → затмения нет", ctx.eclipseOn(toDate("2026-08-13")), null);
  chk("после 2030-11-25 ближайшего нет", ctx.nextEclipse(toDate("2030-11-26")), null);

  /* Окна неба: факты неба, а не этого кода. В полнолуние луна всходит
     около заката, в новолуние она ночью не мешает, а полнолунная ночь мешает
     вся. Ядро на широте −45° в кульминации стоит на 90° − |−45° − (−28.936°)|,
     то есть чуть выше 73.9° — склонение из контрольных точек галактики. */
  X.setPlace(ctx, { lat: 56.02, lon: 37.48, tz: 3 });
  const full = toDate("2026-03-03");
  ctx.computeSun(full);
  const fullArc = ctx.moonArc(full, ctx.SUN.set);
  chk("полнолуние 3 марта 2026 → луна всходит в пределах двух часов от заката",
    Math.abs(fullArc.rise - ctx.SUN.set) <= 120, true);
  const vsFull = ctx.moonVsStars(full);
  chk("полнолуние 3 марта 2026 → помеха «Пути не будет»", vsFull.level, 2);
  const vsNew = ctx.moonVsStars(toDate("2026-08-12"));
  chk("новолуние 12 августа 2026 → тёмная часть есть", vsNew.dark, true);
  chk("новолуние 12 августа 2026 → луна не мешает", vsNew.level, 0);
  ctx.computeSun(toDate("2026-06-21"));
  const wJune = ctx.mwWindow(toDate("2026-06-21"));
  chk("56° с. ш., 21 июня → астрономической темноты нет", wJune.dark, false);
  chk("56° с. ш., 21 июня → окна нет", wJune.from, null);
  X.setPlace(ctx, { lat: -45, lon: 170, tz: 12 });
  const south = toDate("2026-06-21");
  ctx.computeSun(south);
  chk("45° ю. ш., 21 июня → ядро в кульминации на 73.9°", ctx.mwWindow(south).best.alt, 73.94, 0.3);
  X.setPlace(ctx, { lat: 90, lon: 0, tz: 0 });
  let poleNone = 0;
  for (const iso of daysOf2026()) {
    const d = toDate(iso);
    ctx.moonCache = {};
    if (ctx.moonArc(d, 720).none) poleNone++;
  }
  /* Замер 21 сентября 2026: на полюсе высота луны равна её склонению и за
     двое с половиной суток окна почти не движется, поэтому пары «восход и
     заход» в окне не бывает никогда — 365 суток из 365. Веб отвечает «не
     всходит» и тогда, когда луна две недели стоит над горизонтом; это его
     поведение, а не ошибка переноса (DECISIONS, «Окна неба»). */
  chk("90° с. ш.: дуги луны в окне ±3.5 суток нет ни в одни из 365 суток", poleNone, 365);

  /* Итерация 10: темнота в произвольную дату — известное с солнечной модели,
     не с этого же кода. 56° с. ш. видели в белые ночи (§ 8, итерация 9а):
     темноты 21 июня нет, а 21 декабря длинная полярная ночь — тем более есть. */
  X.setPlace(ctx, { lat: 56.02, lon: 37.48, tz: 3 });
  chk("56.02° с. ш., 21 июня → hasAstroNight ложь", ctx.hasAstroNight(toDate("2026-06-21")), false);
  chk("56.02° с. ш., 21 декабря → hasAstroNight истина", ctx.hasAstroNight(toDate("2026-12-21")), true);

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
  const probes = moonProbes(), sweep = phaseSweep();
  const pointsOf = function (list) { return list.reduce(function (n, r) { return n + r.t.length; }, 0); };
  out.push(write(dir, "moon.json", {
    what: "высота, азимут и расстояние до луны; доля диска и код фазы",
    grid: "series — 6 широт × первое число каждого месяца трёх лет × каждые 3 часа; " +
      "probes — 4 места (дробный пояс, антимеридиан) × 3 даты × 10 «страшных» минут; " +
      "phaseSweep — фаза каждые 6 часов 2026–2028, одно место",
    tolerance: { degrees: 1e-7, dist: 1e-7, frac: 1e-9, phase: 1e-9, name: "строго" },
    note: "probes — минуты с дробными миллисекундами: веб обрезает их в new Date(), Swift обязан так же",
    count: pointsOf(moon) + pointsOf(probes) + sweep.t.length,
  }, { series: moon, probes: probes, phaseSweep: sweep }));

  const ecl = eclipseSweep();
  out.push(write(dir, "eclipse.json", {
    what: "таблица затмений и ответы eclipseOn / nextEclipse на каждые сутки",
    grid: "сутки с 2025-06-01 по 2031-02-28, индекс строки таблицы, −1 — нет",
    tolerance: { table: "строго", answers: "строго" },
    note: "таблица не считается, а хранится — расчёт отвергнут трижды (DECISIONS, 7130)",
    count: ecl.days,
  }, { table: ecl.table, sweep: ecl.sweep }));

  const sky = skyWindows();
  out.push(write(dir, "sky_windows.json", {
    what: "восход и заход луны, окно Млечного Пути, помеха луны звёздам",
    grid: "grid — 12 широт × 3 долготы плюс 3 места с некруглым поясом × даты § 5.2; " +
      "sweep — 4 места × каждые сутки 2026. Запись: arcs — дуги луны, qt/qr/qs — ответы moonArc " +
      "на моменты вокруг дуг (null — не всходит), win — mwWindow, vs — moonVsStars",
    tolerance: { minutes: "строго, целые", bestAlt: 1e-9, lit: 1e-9, share: "строго", level: "строго" },
    note: "moonCache веба чистится перед каждой записью; moonVsStars зовётся после mwWindow: " +
      "она пересчитывает солнце и возвращает выбранный день",
    count: sky.grid.length + sky.sweep.length,
  }, sky));

  const pairs = mergePairs();
  out.push(write(dir, "merge_pairs.json", {
    what: "слияние двух снимков: пара на каждое правило",
    grid: "каждая пара слита в обе стороны — стороны обязаны быть не важны",
    tolerance: { result: "строго, включая порядок записей в списках" },
    count: pairs.length * 2,
  }, { pairs: pairs }));

  const dust = mwDust();
  out.push(write(dir, "mw_dust.json", {
    what: "облако точек Млечного Пути на приборе карты (MW_DUST, MW_HAZE)",
    grid: "все точки в порядке генерации: ra, dec (радианы), ярус, порог угасания",
    tolerance: { radians: 1e-12, tier: "строго", fade: "строго" },
    count: dust.points.length,
  }, dust));

  const glow = glowSweep();
  out.push(write(dir, "glow.json", {
    what: "засветка по атласу Лоренца: ячейка плитки, чтение приращений, ступени, mag/arcsec²",
    grid: "широты −70…80 шагом 7,3 × долготы −180…180 шагом 13,7, плюс швы и места замеров; " +
      "плитка синтетическая: байт 0 — 1, байт i — ((imul(i + 1, 2654435761) >>> 24) % 21 − 10) & 255",
    tolerance: { at: "строго", v: "относительно 1e-12", level: "строго", mag: 1e-12 },
    count: glow.cells.length + glow.scale.length,
  }, glow));

  const mw = milkyWay();
  out.push(write(dir, "milkyway.json", {
    what: "полоса галактического экватора и поворот ядра над головой",
    grid: "полоса шагом 3° (константа неба); ядро — 3 широты × 4 даты × 4 часа",
    tolerance: { degrees: 1e-9, checkpoints: "l=0 → 266.405 / −28.936, l=180 → 86.405 / +28.936" },
    count: mw.band.length + mw.coreAltAz.length,
  }, mw));

  const astro = astroNightSweep();
  out.push(write(dir, "astro_night.json", {
    what: "темнота в произвольную дату (hasAstroNight) и её возвращение (nextAstroNight)",
    grid: "has — широты § 5.2 × datesFull(); next — те же широты × четыре даты 2026 года",
    tolerance: { has: "строго", next: "строго, null — не вернулась за 190 суток" },
    count: astro.has.length + astro.next.length,
  }, astro));

  const mock = mockSweep();
  out.push(write(dir, "mock_weather.json", {
    what: "выдумка офлайн: qualityOf и dayWeather — чистая функция даты",
    grid: "все сутки 2026 года плюс стык годов и 29 февраля",
    tolerance: { q: "строго", cloud: "строго", tempBase: "строго", wind: "строго", trend: "строго" },
    count: mock.length,
  }, { days: mock }));

  const weatherDay = weatherDaySweep();
  out.push(write(dir, "weather_day.json", {
    what: "сборка дня из почасового ответа (buildWx): категория, закатный балл, температура, ветер, тренд",
    grid: "семь сценариев: обычный, без необязательных рядов, туман, дождь, полярный день, дробный пояс, южное полушарие",
    tolerance: { q: "строго", cloud: "строго", sunset: "строго", tempBase: "строго", wind: "строго",
      windDir: "строго, null — направления нет", gust: "строго", trend: "строго, не округляется" },
    note: "синтетический почасовой ответ — без сети и без Math.random, см. Tools/parity/generate.js syntheticHourly",
    count: weatherDay.reduce(function (n, c) { return n + c.days.length; }, 0),
  }, { cases: weatherDay }));

  const mwSky = mwSkySweep();
  out.push(write(dir, "mwsky.json", {
    what: "погода над окном Млечного Пути (mwSkyAt): балл, взгляд, слово о воздухе",
    grid: "семь сценариев на 45° с. ш.: границы look, дымка и пыль, отрезок через солнечную полночь",
    tolerance: { score: "строго", look: "строго", word: "строго", cloud: "строго", hum: "строго" },
    count: mwSky.length,
  }, { cases: mwSky }));

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
