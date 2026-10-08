/* Эталон правила «свет в окнах зала» (шаг 31в): сетка входов для
   Fixtures/window_light.json. Подключается из generate.js и пишется тем же
   `write` — с тем же отпечатком вырезки из беты.

   Чьё это правило. Хозяин — Light Plan; BroniOS и сайт студии берут копию
   файла `light_plan:Light_Plan/tools/window_light.js` (самодостаточный, без
   DOM). Эта копия — единственное место, где правило написано на JS, поэтому
   стенд сверяет её с двух сторон:
   - солнце: каждая строка сетки пересчитывается блоками, вырезанными из живой
     беты (`computeSun`, `elevAt`, `azAt`), и расходится с копией не больше
     чем на 1e-9° — иначе стенд падает с просьбой поправить копию;
   - правило: Swift (`WindowLight.swift`) сверяется с этой фикстурой, а пороги
     в Swift и в JS заданы независимо друг от друга — разойдутся, упадёт тест.

   Что в сетке. Восемь мест (Томск, Москва, Сочи, нуль широты и долготы,
   Мурманск, Лонгйир — полярный день и ночь, Сидней — южное полушарие, Катманду
   — некруглый пояс) × восемь дат (оба солнцестояния и равноденствия, оба
   перевода часов Европы, перевод Сиднея, 29 февраля) × моменты: каждый час
   от местной полуночи на 25 часов вперёд (переход через полночь и сдвиг
   часов) плюс по полминуты с обеих сторон от каждого прохождения солнца
   через 2° и 6°. Азимутов окон пять: 0, 90, 180, 270 и произвольный 137.5.
   Отдельно — пробы порога угла (±84.99 / ±85.01 от азимута солнца, в том числе
   с обёрткой через 360) и случаи «нет данных». */
"use strict";

const path = require("path");

/* Коды ответа в рядах — числами, чтобы ряд лёг в одну строку. */
const CODE = { diffuse: 0, direct: 1, sunrise: 2, sunset: 3, none: 4, unknown: 5 };
function codeOf(r) {
  /* Золотой час несёт и половину суток: рассветный — только утром, закатный — только вечером */
  if ((r.kind === "sunrise") !== (r.half === "morning") && r.half !== null) throw new Error("half не сходится с видом: " + JSON.stringify(r));
  if (r.kind !== "sunrise" && r.kind !== "sunset" && r.half !== null) throw new Error("half вне золотого часа: " + JSON.stringify(r));
  return CODE[r.kind];
}

const AZIMUTHS = [0, 90, 180, 270, 137.5];

const PLACES = [
  { name: "Томск", lat: 56.4847, lon: 84.9482, zone: "Asia/Tomsk" },
  { name: "Москва", lat: 55.7558, lon: 37.6173, zone: "Europe/Moscow" },
  { name: "Сочи", lat: 43.6028, lon: 39.7342, zone: "Europe/Moscow" },
  { name: "Нуль", lat: 0, lon: 0, zone: "Africa/Abidjan" },
  { name: "Мурманск", lat: 68.9585, lon: 33.0827, zone: "Europe/Moscow" },
  { name: "Лонгйир", lat: 78.2232, lon: 15.6267, zone: "Arctic/Longyearbyen" },
  { name: "Сидней", lat: -33.8688, lon: 151.2093, zone: "Australia/Sydney" },
  { name: "Катманду", lat: 27.7172, lon: 85.324, zone: "Asia/Kathmandu" },
];

/* Солнцестояния и равноденствия 2026; переходы часов Европы (29 марта,
   25 октября) и Сиднея (4 октября, его лето начинается); високосный день. */
const DATES = ["2026-03-20", "2026-06-21", "2026-09-23", "2026-12-21",
  "2026-03-29", "2026-10-25", "2026-10-04", "2028-02-29"];
/* Даты без перевода часов: только на них миг пересечения 2° / 6° ставится
   от полуночи без поправки. */
const SEASON_DATES = ["2026-03-20", "2026-06-21", "2026-09-23", "2026-12-21"];

function parseDay(iso) { const p = iso.split("-").map(Number); return { y: p[0], m: p[1], d: p[2] }; }

function build(ctx, X) {
  /* Копия правила для BroniOS — из соседней папки веба */
  const libPath = path.join(X.webRoot(), "tools", "window_light.js");
  let WL;
  try { WL = require(libPath); } catch (e) {
    throw new Error("не найден файл правила: " + libPath +
      "\n(папка веба — LIGHT_PLAN_WEB; файл — Light_Plan/tools/window_light.js)");
  }
  const TH = WL.THRESHOLDS;
  const RANGE = WL.INSTANT_RANGE_MS;

  /* Эталон солнца — блоки беты. Момент → {el, az} по часам зала. */
  function oracle(place, ms) {
    const offMs = WL._zoneOffsetMs(ms, place.zone);
    const local = new Date(ms + offMs);               // UTC-поля = часы зала
    X.setPlace(ctx, { lat: place.lat, lon: place.lon, tz: offMs / 3600000 });
    ctx.computeSun(new Date(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()));
    const t = local.getUTCHours() * 60 + local.getUTCMinutes() + local.getUTCSeconds() / 60 +
      local.getUTCMilliseconds() / 60000;
    return { offMs: offMs, el: ctx.elevAt(t), az: ctx.azAt(t) };
  }

  function ask(place, ms, wa) {
    return WL.at({ instant: ms, lat: place.lat, lon: place.lon, timezone: place.zone,
      windowsAzimuth: wa, hasWindows: true });
  }

  /* Копия и бета видят одно солнце */
  let sunWorst = 0;
  function checkSun(place, ms, r) {
    const o = oracle(place, ms);
    const dEl = Math.abs(o.el - r.sunElevation);
    let dAz = Math.abs(o.az - r.sunAzimuth); if (dAz > 180) dAz = 360 - dAz;
    sunWorst = Math.max(sunWorst, dEl, dAz);
    if (dEl > 1e-9 || dAz > 1e-9) {
      throw new Error("копия солнца в Light_Plan/tools/window_light.js разошлась с бетой: " +
        place.name + " " + new Date(ms).toISOString() + " высота " + r.sunElevation + " против " + o.el +
        ", азимут " + r.sunAzimuth + " против " + o.az +
        "\nБета — эталон: поправить копию, не фикстуры.");
    }
  }

  /* Полночь зала в миллисекундах: на датах без перевода сдвиг полуночи — тот же,
     что в полдень; на датах с переводом он берётся на саму полночь. */
  function midnightMs(place, iso) {
    const p = parseDay(iso);
    const wall = Date.UTC(p.y, p.m - 1, p.d);
    let off = WL._zoneOffsetMs(wall, place.zone);       // приближение
    off = WL._zoneOffsetMs(wall - off, place.zone);     // уточнение на саму полночь
    return wall - off;
  }

  const days = [];
  let rowsTotal = 0;
  const kinds = {};
  for (const place of PLACES) for (const iso of DATES) {
    const base = midnightMs(place, iso);
    const rows = [];
    const stamps = [];
    for (let k = 0; k <= 25; k++) stamps.push(base + k * 3600000);
    /* Прохождения 2° и 6° — только на сезонных датах, где полночь без перевода */
    if (SEASON_DATES.indexOf(iso) >= 0) {
      const p = parseDay(iso);
      const off = WL._zoneOffsetMs(base, place.zone);
      X.setPlace(ctx, { lat: place.lat, lon: place.lon, tz: off / 3600000 });
      ctx.computeSun(new Date(p.y, p.m - 1, p.d));
      for (const h of [TH.minElevation, TH.goldElevation]) for (const rising of [true, false]) {
        const t = ctx.tAtElev(h, rising);
        if (t === null) continue;
        const ms = base + Math.round(t * 60000);
        stamps.push(ms - 30000, ms + 30000);
      }
    }
    stamps.sort(function (a, b) { return a - b; });
    for (const ms of stamps) {
      const answers = AZIMUTHS.map(function (wa) { return ask(place, ms, wa); });
      checkSun(place, ms, answers[0]);
      const row = [ms, answers[0].sunElevation === null ? null : WL._zoneOffsetMs(ms, place.zone),
        answers[0].sunElevation, answers[0].sunAzimuth];
      for (const a of answers) {
        row.push(codeOf(a));
        kinds[a.kind] = (kinds[a.kind] || 0) + 1;
      }
      rows.push(row);
      rowsTotal++;
    }
    days.push({ place: place.name, lat: place.lat, lon: place.lon, zone: place.zone, date: iso, rows: rows });
  }

  /* Пробы порога угла: окно ровно на краю конуса, по обе стороны, в обе
     стороны круга (азимут окна за 360 и ниже нуля приводится правилом). */
  const edge = [];
  for (const place of PLACES) for (const iso of SEASON_DATES) {
    const base = midnightMs(place, iso);
    /* Момент с самой высокой точкой дня, чтобы высота не мешала порогу угла */
    let bestMs = base, bestEl = -91;
    for (let k = 0; k < 96; k++) {
      const ms = base + k * 15 * 60000, e = oracle(place, ms).el;
      if (e > bestEl) { bestEl = e; bestMs = ms; }
    }
    if (bestEl <= TH.goldElevation + 1) continue;       // полярная ночь — угла проверять не на чем
    const sunAz = oracle(place, bestMs).az;
    for (const delta of [84.99, 85.01, -84.99, -85.01]) {
      const wa = sunAz + delta;                           // может выйти за 0…360 — так и задумано
      const r = ask(place, bestMs, wa);
      checkSun(place, bestMs, r);
      edge.push({ place: place.name, lat: place.lat, lon: place.lon, zone: place.zone, ms: bestMs,
        windowsAzimuth: wa, code: codeOf(r), offset: r.offsetFromWindow, why: "угол " + delta + "° от солнца" });
    }
  }

  /* Приведение азимута: 360 = 0, −90 = 270, 450 = 90 дают тот же ответ.
     Проверяется здесь же, в генераторе, по парам. */
  const norm = [];
  const np = PLACES[0], nms = midnightMs(np, "2026-06-21") + 14 * 3600000;
  for (const [raw, twin] of [[360, 0], [-90, 270], [450, 90], [-360, 0], [720.5, 0.5]]) {
    const a = ask(np, nms, raw), b = ask(np, nms, twin);
    if (a.kind !== b.kind || a.half !== b.half || Math.abs(a.offsetFromWindow - b.offsetFromWindow) > 1e-9) {
      throw new Error("азимут " + raw + " не равен " + twin + ": " + JSON.stringify(a) + " / " + JSON.stringify(b));
    }
    norm.push({ place: np.name, lat: np.lat, lon: np.lon, zone: np.zone, ms: nms,
      windowsAzimuth: raw, code: codeOf(a), offset: a.offsetFromWindow, why: "азимут " + raw + " = " + twin });
  }

  /* Края диапазона принимаемых моментов: первый и последний миг внутри считаются
     (в Томске и Сиднее), миг за краем — «нет данных» (ниже, в gaps) */
  const far = [];
  for (const [place, ms, why] of [
    [PLACES[0], RANGE.from, "первый миг диапазона, 1970-01-01T00:00Z"],
    [PLACES[6], RANGE.from, "первый миг диапазона, Сидней"],
    [PLACES[0], RANGE.to - 1, "последняя миллисекунда диапазона, 2099-12-31T23:59:59.999Z"],
    [PLACES[6], RANGE.to - 3600000, "час до конца диапазона, Сидней"],
    [PLACES[1], Date.UTC(2099, 11, 30, 9, 0, 0), "30 декабря 2099, 12:00 в Москве"],
  ]) {
    const r = ask(place, ms, 180);
    if (r.kind === "unknown") throw new Error("край диапазона отвергнут: " + why + " " + JSON.stringify(r));
    checkSun(place, ms, r);
    far.push({ place: place.name, lat: place.lat, lon: place.lon, zone: place.zone, ms: ms,
      windowsAzimuth: 180, code: codeOf(r), offset: r.offsetFromWindow, why: why });
  }

  /* «Нет данных» и «нет окон»: ответ записан руками здесь и сверен с копией, а
     не взят из неё. `null` — поля нет. */
  const m0 = midnightMs(np, "2026-06-21") + 12 * 3600000;
  const full = { lat: np.lat, lon: np.lon, zone: np.zone, ms: m0, windowsAzimuth: 180, hasWindows: true };
  const gapCases = [
    ["окон нет, остальное полно", Object.assign({}, full, { hasWindows: false }), "none", null],
    ["окон нет, ничего больше", { lat: null, lon: null, zone: null, ms: null, windowsAzimuth: null, hasWindows: false }, "none", null],
    ["нет признака окон", Object.assign({}, full, { hasWindows: null }), "unknown", "no_windows_flag"],
    ["нет азимута окон", Object.assign({}, full, { windowsAzimuth: null }), "unknown", "no_azimuth"],
    ["нет широты", Object.assign({}, full, { lat: null }), "unknown", "no_coordinates"],
    ["нет долготы", Object.assign({}, full, { lon: null }), "unknown", "no_coordinates"],
    ["широта вне диапазона", Object.assign({}, full, { lat: 90.5 }), "unknown", "no_coordinates"],
    ["долгота вне диапазона", Object.assign({}, full, { lon: -181 }), "unknown", "no_coordinates"],
    ["нет пояса", Object.assign({}, full, { zone: null }), "unknown", "no_zone"],
    ["пустой пояс", Object.assign({}, full, { zone: "" }), "unknown", "no_zone"],
    ["пояса нет в базе", Object.assign({}, full, { zone: "Mars/Olympus" }), "unknown", "bad_zone"],
    ["нет момента", Object.assign({}, full, { ms: null }), "unknown", "bad_moment"],
    ["миг до диапазона (1969-12-31T23:59:59.999Z)", Object.assign({}, full, { ms: RANGE.from - 1 }), "unknown", "moment_out_of_range"],
    ["первый миг за диапазоном (2100-01-01T00:00Z)", Object.assign({}, full, { ms: RANGE.to }), "unknown", "moment_out_of_range"],
    ["год ≈ 275000 (самая поздняя Date, 8.64e15 мс)", Object.assign({}, full, { ms: 8.64e15 }), "unknown", "moment_out_of_range"],
    ["год ≈ 275000 до н. э. (−8.64e15 мс)", Object.assign({}, full, { ms: -8.64e15 }), "unknown", "moment_out_of_range"],
    ["момент за пределами Date (8.64e18 мс)", Object.assign({}, full, { ms: 8.64e18 }), "unknown", "moment_out_of_range"],
    ["окон нет, момент за диапазоном", Object.assign({}, full, { hasWindows: false, ms: 8.64e18 }), "none", null],
  ];
  const gaps = gapCases.map(function (c) {
    const i = c[1];
    const r = WL.at({ instant: i.ms, lat: i.lat, lon: i.lon, timezone: i.zone,
      windowsAzimuth: i.windowsAzimuth, hasWindows: i.hasWindows });
    if (r.kind !== c[2] || r.reason !== c[3]) {
      throw new Error("«" + c[0] + "»: ждали " + c[2] + "/" + c[3] + ", получили " + r.kind + "/" + r.reason);
    }
    if (r.sunElevation !== null || r.sunAzimuth !== null || r.offsetFromWindow !== null) {
      throw new Error("«" + c[0] + "»: при отсутствии данных числа обязаны быть null");
    }
    return { why: c[0], input: i, kind: c[2], reason: c[3] };
  });

  /* Известные значения: на них стенд обязан сойтись, иначе фикстур не будет */
  const known = [];
  function expect(name, got, want) {
    known.push({ name: name, ok: got === want, got: got, want: want });
  }
  const eq0 = { name: "Нуль", lat: 0, lon: 0, zone: "Africa/Abidjan" };
  const eqNoon = midnightMs(eq0, "2026-03-20") + 12 * 3600000;
  /* Уравнение времени в день равноденствия ≈ −7,5 мин: в 12:00 до полудня ещё ≈ 7,5 мин = 1,9° часового угла, склонение ≈ −0,1° → высота ≈ 88° */
  const eqEl = ask(eq0, eqNoon, 180).sunElevation;
  expect("экватор, равноденствие, 12:00: высота солнца 87–89° (зенит минус 1,9° часового угла)", eqEl > 87 && eqEl < 89, true);
  expect("экватор, равноденствие, около полудня: окно на юг получает прямой", ask(eq0, eqNoon, 180).kind, "direct");
  const tomskNoon = midnightMs(PLACES[0], "2026-06-21") + 13 * 3600000;
  expect("Томск, 21 июня, 13:00: юг — прямой", ask(PLACES[0], tomskNoon, 180).kind, "direct");
  expect("Томск, 21 июня, 13:00: окно на север — рассеянный", ask(PLACES[0], tomskNoon, 0).kind, "diffuse");
  const tomskNight = midnightMs(PLACES[0], "2026-12-21") + 1 * 3600000;
  expect("Томск, 21 декабря, 01:00: ночью любой азимут — рассеянный",
    [0, 90, 180, 270].every(function (a) { return ask(PLACES[0], tomskNight, a).kind === "diffuse"; }), true);
  const sydneyEve = days.find(function (d) { return d.place === "Сидней" && d.date === "2026-12-21"; });
  expect("Сидней, 21 декабря: вечером бывает закатный",
    sydneyEve.rows.some(function (r) { return r.slice(4).indexOf(CODE.sunset) >= 0; }), true);
  const kx = days.find(function (d) { return d.place === "Лонгйир" && d.date === "2026-06-21"; });
  /* Полярный день на 78,2° с. ш.: низшая точка солнца 78,2 + 23,4 − 90 ≈ 11,6° — выше золотого часа,
     так что в полночь окно на север получает прямой, а ниже 2° солнце не уходит */
  expect("Лонгйир, 21 июня: в полночь зала окно на север — прямой", kx.rows[0][4], CODE.direct);
  expect("Лонгйир, 21 июня: солнце за сутки не опускается ниже 2°", kx.rows.every(function (r) { return r[2] > TH.minElevation; }), true);
  for (const k of known) if (!k.ok) throw new Error("самопроверка правила: " + k.name + " — получено " + k.got + ", ждали " + k.want);

  return {
    meta: {
      what: "свет в окнах зала («прямой» / «рассветный» / «закатный» / «рассеянный»): правило по солнцу, без погоды",
      grid: PLACES.length + " мест × " + DATES.length + " дат × моменты (каждый час 25 часов от полуночи зала плюс по полминуты " +
        "вокруг прохождений " + TH.minElevation + "° и " + TH.goldElevation + "°) × 5 азимутов окон; пробы порога угла; края диапазона моментов (1970…2100); случаи «нет данных»",
      tolerance: { degrees: 1e-9, code: "строго", offsetMs: "строго" },
      thresholds: { minElevation: TH.minElevation, goldElevation: TH.goldElevation, maxOffset: TH.maxOffset },
      azimuths: AZIMUTHS,
      codes: CODE,
      rowLayout: "[мс, сдвиг пояса мс, высота солнца, азимут солнца, код ответа на каждый азимут из azimuths]",
      note: "по солнцу, без погоды; размер окна и преграды не учитываются. Высота и азимут солнца сверены " +
        "с блоками беты (худшее расхождение копии " + sunWorst.toExponential(1) + "°); ответы — копией light_plan:Light_Plan/tools/window_light.js",
      range: { from: RANGE.from, to: RANGE.to },
      count: rowsTotal * AZIMUTHS.length + edge.length + norm.length + far.length + gaps.length,
    },
    body: { days: days, edge: edge, norm: norm, far: far, gaps: gaps },
    stats: { rows: rowsTotal, kinds: kinds, sunWorst: sunWorst },
  };
}

module.exports = { build, CODE };
