/* Вырезает слои математики прямо из beta/index.html и отдаёт их исполняемыми.

   Приём взят у `light_plan:Light_Plan/tools/datecheck.js`: слой не копируется
   в нативный проект, а каждый раз режется из живого файла беты. Копия
   разъехалась бы с эталоном молча, а разъехавшийся эталон — это сверка,
   которая ничего не доказывает.

   Границы ищутся по якорным строкам, а не по номерам: бета правится
   ежедневно, номера уезжают на сотни строк за неделю. Промах якоря —
   падение с именем блока и самим якорем, а не тихая подмена пустотой.

   Что не вырезается и почему: LAT, LON, TZ объявлены выше всех блоков и
   остаются снаружи. Место задаётся так же, как его задаёт приложение, —
   записью в эти три глобальные (setPlace). Пояс в стенде всегда явный
   параметр, никогда не системный.

   Пример:
     node Tools/parity/extract.js
*/
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const crypto = require("crypto");

/* Корень нативного репозитория: Tools/parity — на два уровня вверх */
const ROOT = path.resolve(__dirname, "..", "..");

/* Веб — соседняя папка запуска (`light_plan:Light_Plan/`). Переопределяется
   переменной окружения, если папки когда-нибудь разъедутся. */
function webRoot() {
  return process.env.LIGHT_PLAN_WEB || path.resolve(ROOT, "..", "Light_Plan");
}
function webPath() {
  return path.join(webRoot(), "beta", "index.html");
}

/* Таблица блоков. from — первая строка блока, to — первая строка того, что
   идёт после него; сам to в вырезку не попадает.
   Порядок в таблице — порядок исполнения: блоки видят друг друга. */
const BLOCKS = {
  helpers: {
    from: "var rad = function (d)",
    to: "/* ---------- Даты: собирает язык",
    why: "rad, deg, clamp — на них стоит вся остальная математика",
  },
  sameDay: {
    from: "function sameDay(a, b)",
    to: "/* День записи хранится строкой",
    why: "sameDay — одна строка, но на ней стоит выбор затмения дня",
  },
  solar: {
    from: "var decl = 0, solarNoon = 720",
    to: "var dirOf = function (az)",
    why: "computeSun, elevAt, azAt, tAtElev, shadowAt — солнечная модель NOAA",
  },
  score: {
    from: "function bell(x, c, w)",
    to: "function airWord(air)",
    why: "sunsetScore и его колокол; слова о воздухе уже из словаря",
  },
  moon: {
    from: "var EPS = rad(23.4397)",
    to: "var GAL_POLE_RA = rad(192.85948)",
    why: "instant, toDays, sunEq, moonEq, moonAt — лунная модель по Меёсу",
  },
  milkyway: {
    from: "var GAL_POLE_RA = rad(192.85948)",
    to: "/* ---------- Облако точек ----------",
    why: "galToEq, eqToAltAz, mwHalfWidth, MW_BAND, MW_CORE; облако точек — свой блок mwDust",
  },
  /* Облако точек прибора карты (итерация 20а). До неё считалось рисунком;
     пара снимков веб / натив сравнивает точки на холсте, и какие точки неба
     стоят в облаке — уже данные. */
  mwDust: {
    from: "/* ---------- Облако точек ----------",
    to: "/* Есть ли этой ночью астрономическая темнота.",
    why: "MW_DUST, MW_HAZE — облако точек прибора карты: свой LCG, ярус и порог угасания",
  },
  eclipse: {
    from: "var ECLIPSES = [",
    to: "/* fraction — какая доля диска освещена",
    why: "ECLIPSES, eclipseOn, nextEclipse — затмения таблицей, расчёт отвергнут трижды",
  },
  moonPhase: {
    from: "function moonPhase(date, t)",
    to: "/* Восход и заход выбранного дня.",
    why: "moonPhase, PHASES, phaseName — доля диска и код фазы (имя фазы — ключ словаря)",
  },
  /* Окна неба (итерация 9а). Лежат в вебе четырьмя кусками, между которыми
     стоят погода над окном (`mwSkyAt`, итерация 10) и облако точек — рисунок.
     Поэтому четыре блока, а не один. */
  skyWindows: {
    from: "/* ---------- Луна против Млечного Пути ----------",
    to: "function mwDateShort(d)",
    why: "moonVsStars и mwWindow — помеха луны и окно Млечного Пути",
  },
  milkyWayAt: {
    from: "function milkyWayAt(date, t)",
    to: "/* ============================================================\n     ЗАТМЕНИЯ",
    why: "milkyWayAt — ядро над головой в момент; стоит отдельно от МЛЕЧНОГО ПУТИ, за погодой",
  },
  moonArc: {
    from: "/* Восход и заход выбранного дня.",
    to: "/* ============================================================\n     ПОГОДА ДНЯ",
    why: "moonArc и moonCross — восход и заход луны; moonCache — оптимизация веба, в Swift её нет",
  },
  mwWork: {
    from: "var MW_WORK_LO = 10, MW_WORK_HI = 15;",
    to: "var TICK_OUT = 154;",
    why: "рабочая высота ядра; лежит в блоке купола, за пять тысяч строк от окна",
  },
  /* Погода и закатный балл (итерация 10). Лежат в вебе россыпью между
     сетью и рисунком; сетевой код (`fetchWeather`, `fetchAir`) в вырезку не
     входит нарочно: он трогает `fetch`, а песочнице `fetch` не дан. */
  astroNight: {
    from: "/* Есть ли этой ночью астрономическая темнота.",
    to: "/* ---------- Луна против Млечного Пути ----------",
    why: "hasAstroNight, nextAstroNight — темнота в произвольную дату и её возвращение",
  },
  mockWx: {
    from: "function mulberry32(a)",
    to: "/* ============================================================\n     ПОГОДА OPEN-METEO",
    why: "мок погоды: mulberry32, QUAL_C, dkey, qualityOf, dayWeather — детерминированный откат офлайн",
  },
  wxState: {
    from: "var wxKey = null, wxLive = false",
    to: "/* ---- Закатный балл по трём ярусам облаков",
    why: "wxByHour — почасовые данные, которые buildWx кладёт и читает окно Млечного Пути",
  },
  airWord: {
    from: "function airWord(air)",
    to: "function scoreCat(s)",
    why: "airWord — слово о воздухе; LANG.t в стенде отдаёт ключ",
  },
  buildWx: {
    from: "function scoreCat(s)",
    to: "function fetchWeather()",
    why: "scoreCat, deriveQ, buildWx — категория дня и сборка дней из почасового ответа",
  },
  airState: {
    from: "var airDay = {}, airKey",
    to: "function fetchAir()",
    why: "airDay, wxRaw — воздух по суткам",
  },
  airAt: {
    from: "function airKeyOf(date)",
    to: "/* ---------- Погода точек маршрута",
    why: "airKeyOf, airAt — воздух по часу",
  },
  mwSky: {
    from: "function nearHour(bh, hr)",
    to: "function milkyWayAt(date, t)",
    why: "nearHour и mwSkyAt — погода над окном Млечного Пути",
  },
  light: {
    from: "var GOLD=[226,164,76]",
    to: "var cx = 195, cy = 196, rx = 163, ry = 148;",
    why: "палитра, skyColor, stateAt, shadowWord, nextLight — 15 состояний света",
  },
  /* Слияние лежит в файле двумя кусками: список настроек, которые не
     сливаются, стоит рядом с их отметками, а сама функция — за тысячу строк
     от него. Поэтому два блока, а не один. */
  mergeSkip: {
    from: "var SET_SKIP = {",
    to: "function stampSettings(data, now)",
    why: "какие ключи настроек не участвуют в слиянии",
  },
  merge: {
    from: "var MERGE_LISTS = [",
    to: "function markBackup()",
    why: "mtOf, mergePick, mergeStores — слияние двух снимков; функция чистая",
  },
  /* Засветка по атласу Лоренца (итерация 20б). Два куска: между ними сеть
     (`gunzipBytes`, `fetchGlow`) — она трогает `fetch` и в вырезку не входит. */
  glow: {
    from: "var GLOW_YEAR = 2025",
    to: "function gunzipBytes(buf)",
    why: "glowIndex, glowRead — ячейка атласа и чтение приращений плитки",
  },
  glowScale: {
    from: "function glowLevel(r)",
    to: "/* При таскании карты moveend",
    why: "glowLevel, glowMag — ступени засветки для камеры и mag/arcsec²",
  },
};

const ALL = Object.keys(BLOCKS);

let _main = null;
/* Самый длинный <script> файла — это приложение. Тот же приём, что в datecheck.js. */
function mainScript() {
  if (_main) return _main;
  const file = webPath();
  if (!fs.existsSync(file)) {
    throw new Error("не найден эталон: " + file +
      "\n(папка веба задаётся переменной LIGHT_PLAN_WEB)");
  }
  const s = fs.readFileSync(file, "utf8");
  const re = /<script>([\s\S]*?)<\/script>/g;
  let m, best = "";
  while ((m = re.exec(s))) if (m[1].length > best.length) best = m[1];
  if (!best) throw new Error("в " + file + " нет ни одного <script> без атрибутов");
  _main = best;
  return _main;
}

function fail(name, which, anchor) {
  return "блок «" + name + "»: не найден " + which + " — якорная строка\n  " + anchor +
    "\nЗначит бета изменилась в этом месте. Смотреть " + webPath() +
    ", чинить якорь в Tools/parity/extract.js, а не подгонять фикстуры.";
}

function cut(name) {
  const b = BLOCKS[name];
  if (!b) throw new Error("нет такого блока: " + name);
  const main = mainScript();
  const i = main.indexOf(b.from);
  if (i < 0) throw new Error(fail(name, "начало", b.from));
  const j = main.indexOf(b.to, i + b.from.length);
  if (j < 0) throw new Error(fail(name, "конец", b.to));
  return main.slice(i, j);
}

/* Отпечаток вырезанного кода. Лежит в фикстурах: по нему видно, каким именно
   состоянием беты они посчитаны, и правка эталона перестаёт быть незаметной. */
function sourceDigest(names) {
  const h = crypto.createHash("sha256");
  for (const n of names || ALL) { h.update(n); h.update(cut(n)); }
  return h.digest("hex").slice(0, 16);
}

/* Исполняет блоки в своей песочнице и отдаёт её как объект: var верхнего
   уровня становятся её свойствами, поэтому ctx.SUN, ctx.solarNoon, ctx.stateAt
   читаются снаружи ровно так же, как их читает приложение.

   Заглушки вместо приложения:
   - LANG.t возвращает сам ключ. Стенд сверяет выбор ключа, а не перевод:
     состояние выбирает высота солнца, и от языка она не зависит.
   - theme нужна только labelColor, которую стенд не зовёт.
   - document не подсовывается намеренно: если в вырезку попадёт кусок,
     трогающий DOM, песочница упадёт, а не притворится, что всё хорошо. */
function load(names, place) {
  const list = names || ALL;
  const ctx = vm.createContext({
    Math: Math, Date: Date, JSON: JSON, isFinite: isFinite, isNaN: isNaN,
    Number: Number, String: String, Array: Array, Object: Object,
    LANG: { t: function (k) { return k; } },
    theme: "dark",
    /* moonVsStars сохраняет выбранный день и возвращает его после подсчёта чужого:
       в приложении он всегда есть. Стенд задаёт его сам и всегда пересчитывает
       солнце нужного дня перед окном. */
    selDate: new Date(2026, 0, 1),
    LAT: 56.02, LON: 37.48, TZ: 3,
  });
  for (const n of list) vm.runInContext(cut(n), ctx, { filename: "beta/index.html:" + n });
  if (place) setPlace(ctx, place);
  return ctx;
}

/* Место задаётся записью в те же глобальные, что пишет приложение. */
function setPlace(ctx, p) {
  ctx.LAT = p.lat; ctx.LON = p.lon; ctx.TZ = p.tz;
  return ctx;
}

module.exports = { BLOCKS, ALL, ROOT, webRoot, webPath, mainScript, cut, sourceDigest, load, setPlace };

/* Запуск напрямую — перечень блоков и их размер: дешёвая проверка якорей. */
if (require.main === module) {
  try {
    console.log("эталон: " + webPath());
    for (const n of ALL) {
      const src = cut(n);
      console.log("  " + n.padEnd(9) +
        String(src.split("\n").length).padStart(4) + " строк, " +
        String(src.length).padStart(6) + " байт — " + BLOCKS[n].why);
    }
    console.log("отпечаток вырезки: " + sourceDigest());
  } catch (e) {
    /* Стек здесь не нужен: ошибка не в коде стенда, а в том, что бета уехала */
    console.error("\n" + e.message);
    process.exit(1);
  }
}
