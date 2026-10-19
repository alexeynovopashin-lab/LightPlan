/* Каталог ярких звёзд для слоя звёзд AR: снимки sources/ → bright_stars.json.

   Сети не нужно: числа берутся из снимков, которые пишет fetch.js. Руками в
   bright_stars.json не правят — правило меняется здесь, файл пересобирается,
   повторная сборка обязана дать тот же файл (это проверяет check.js).

   Что делается:
     1. Все звёзды V/50 с V ≤ 2,5 (координаты J2000 из самого каталога,
        шестидесятеричные → RA в часах, Dec в градусах).
     2. EXCLUDE — звёзды, которых глазом там нет (причина записана рядом).
     3. Пары ближе MERGE_DEG сливаются в одну точку: глаз их не делит, а две
        точки друг на друге — дубль. Величина — суммарный блеск, место и HR —
        яркой компоненты.
     4. Имя: МАС (WGSN) по HR, иначе латинское обозначение Байера. Русское —
        для 30 самых ярких, из NAMES_RU (сверка с Wikidata — в check.js).
     5. Сверка с каталогом созвездий приложения: звезда ближе MATCH_DEG к одной
        из 163 звёзд фигур уже есть («inFigures»), остальные — «added», только
        они уходят в BrightStars.generated.swift.

   Пример:
     node Tools/bright_stars/build.js
*/
"use strict";
const fs = require("fs"), path = require("path");
const ROOT = path.resolve(__dirname, "../..");
const SRC = path.join(__dirname, "sources");
const OUT = path.join(__dirname, "bright_stars.json");
const FIGURES = path.join(ROOT, "Packages/LightPlanCore/Sources/LightPlanCore/Sky/ConstellationCatalog.generated.swift");

const LIMIT = 2.5;       // видимая величина, включительно
const MATCH_DEG = 0.05;  // «та же звезда», что в фигуре созвездия
const MERGE_DEG = 0.05;  // ближе — одна точка (тот же допуск: дубль есть дубль)
const NAMED_RU = 30;     // русские имена — у стольких самых ярких

const EXCLUDE = {
  5958: "T Северной Короны — повторная новая: V/50 даёт 2,00 (блеск вспышки), " +
    "в покое она около 10m и глазу не видна (SIMBAD V = 10,25)",
};

// Имена МАС, принятые после даты файла IAU-CSN (2022-04-04): WGSN публикует их
// на exopla.net. Сверено 19.10.2026.
const IAU_LATER = {
  264: { name: "Tiansi", source: "https://exopla.net/news-in-2025/ (WGSN, принято в 2025)" },
  5469: { name: "Uridim", source: "https://exopla.net/new-star-names-2024/ (WGSN, принято в 2024)" },
};

// Русские имена 30 самых ярких (ранг после слияния пар). Справочник — русская
// Википедия и Wikidata: имя должно совпасть и с заголовком статьи, и с русской
// меткой звезды или её системы (check.js сверяет со снимком). null — источники
// расходятся: русского имени нет, остаётся латинское.
const NAMES_RU = {
  2491: "Сириус", 2326: "Канопус", 5459: "Альфа Центавра", 5340: "Арктур", 7001: "Вега",
  1708: "Капелла", 1713: "Ригель", 2943: "Процион", 472: "Ахернар", 2061: "Бетельгейзе",
  5267: "Хадар", 4730: "Акрукс", 7557: "Альтаир", 1457: "Альдебаран", 6134: "Антарес",
  5056: "Спика", 2990: "Поллукс", 8728: "Фомальгаут", 4853: "Бекрукс", 7924: "Денеб",
  3982: "Регул", 2618: "Адара", 4763: "Гакрукс", 6527: "Шаула", 1790: "Беллатрикс",
  1791: null, // β Tau: метка Wikidata «Нат», статья «Бета Тельца», в ходу и «Эльнат»
  3685: "Бета Киля", 1903: "Альнилам", 8425: "Альнаир", 4905: "Алиот",
};

const GREEK = {
  Alp: ["α", "Alpha"], Bet: ["β", "Beta"], Gam: ["γ", "Gamma"], Del: ["δ", "Delta"],
  Eps: ["ε", "Epsilon"], Zet: ["ζ", "Zeta"], Eta: ["η", "Eta"], The: ["θ", "Theta"],
  Iot: ["ι", "Iota"], Kap: ["κ", "Kappa"], Lam: ["λ", "Lambda"], Mu: ["μ", "Mu"],
  Nu: ["ν", "Nu"], Xi: ["ξ", "Xi"], Omi: ["ο", "Omicron"], Pi: ["π", "Pi"],
  Rho: ["ρ", "Rho"], Sig: ["σ", "Sigma"], Tau: ["τ", "Tau"], Ups: ["υ", "Upsilon"],
  Phi: ["φ", "Phi"], Chi: ["χ", "Chi"], Psi: ["ψ", "Psi"], Ome: ["ω", "Omega"],
};
const SUP = { 1: "¹", 2: "²", 3: "³" };
// Родительный падеж созвездий — для латинского имени звезды без имени МАС.
const GENITIVE = {
  And: "Andromedae", Aql: "Aquilae", Ari: "Arietis", Aur: "Aurigae", Boo: "Bootis",
  Car: "Carinae", Cas: "Cassiopeiae", Cen: "Centauri", Cep: "Cephei", Cet: "Ceti",
  CMa: "Canis Majoris", CMi: "Canis Minoris", CrB: "Coronae Borealis", Cru: "Crucis",
  Cyg: "Cygni", Dra: "Draconis", Eri: "Eridani", Gem: "Geminorum", Gru: "Gruis",
  Hya: "Hydrae", Leo: "Leonis", Lup: "Lupi", Lyr: "Lyrae", Oph: "Ophiuchi",
  Ori: "Orionis", Pav: "Pavonis", Peg: "Pegasi", Per: "Persei", Phe: "Phoenicis",
  PsA: "Piscis Austrini", Pup: "Puppis", Sco: "Scorpii", Sgr: "Sagittarii", Tau: "Tauri",
  TrA: "Trianguli Australis", UMa: "Ursae Majoris", UMi: "Ursae Minoris",
  Vel: "Velorum", Vir: "Virginis",
};

function rad(d) { return d * Math.PI / 180; }

/** Угол между двумя точками неба, градусы; RA в часах, Dec в градусах. */
function separation(ra1, dec1, ra2, dec2) {
  const a1 = rad(ra1 * 15), a2 = rad(ra2 * 15), d1 = rad(dec1), d2 = rad(dec2);
  const h = Math.pow(Math.sin((d2 - d1) / 2), 2) +
    Math.cos(d1) * Math.cos(d2) * Math.pow(Math.sin((a2 - a1) / 2), 2);
  return 2 * Math.asin(Math.min(1, Math.sqrt(h))) * 180 / Math.PI;
}

function round(v, digits) { return Number(v.toFixed(digits)); }

function sexagesimal(s) {
  const m = /^\s*([+-]?)(\d+) (\d+) ([\d.]+)\s*$/.exec(s);
  if (!m) throw new Error("не координата: «" + s + "»");
  const v = +m[2] + m[3] / 60 + m[4] / 3600;
  return m[1] === "-" ? -v : v;
}

/** Строки V/50 с V ≤ LIMIT: HR, имя Байера/Флемстида, HD, J2000, V, спектр. */
function readV50(file) {
  const text = fs.readFileSync(file || path.join(SRC, "v50.tsv"), "utf8");
  return text.split("\n").filter(function (l) { return /^\s*\d+\t/.test(l); }).map(function (l) {
    const c = l.split("\t");
    return { hr: +c[0], bscName: c[1].trim(), hd: +c[2], ra: sexagesimal(c[3]) , dec: sexagesimal(c[4]),
      magnitude: +c[5], spectralClass: c[7].trim() };
  }).filter(function (s) { return s.magnitude <= LIMIT; });
}

/** «57Gam1And» → { greek: "Gam", sup: "1", con: "And" }; null, если буквы Байера нет. */
function bayerParts(bscName) {
  const m = /^\d*\s*([A-Z][a-z]{1,2})(\d?)\s*([A-Z][A-Za-z]{2})$/.exec(bscName);
  return m && GREEK[m[1]] ? { greek: m[1], sup: m[2], con: m[3] } : null;
}

/** Имена МАС из снимка IAU-CSN: HR → имя с диакритикой (столбец 2). */
function readIau(file) {
  const out = {};
  for (const l of fs.readFileSync(file || path.join(SRC, "iau_csn.txt"), "utf8").split("\n")) {
    if (!l || l[0] === "#" || l[0] === "$") continue;
    const m = /^(.{18})(.{18})HR (\d+)\b/.exec(l);
    if (m) out[+m[3]] = m[2].trim();
  }
  return out;
}

/** 163 звезды фигур из ConstellationCatalog.generated.swift: код, номер, RA, Dec, величина. */
function readFigures(file) {
  const text = fs.readFileSync(file || FIGURES, "utf8");
  const out = [];
  let code = null, index = 0;
  const re = /code: "([^"]+)"|CatalogStar\(ra: ([-\d.]+), dec: ([-\d.]+), magnitude: ([-\d.]+)\)/g;
  let m;
  while ((m = re.exec(text))) {
    if (m[1]) { code = m[1]; index = 0; continue; }
    out.push({ code: code, index: index++, ra: +m[2], dec: +m[3], magnitude: +m[4] });
  }
  return out;
}

function build() {
  const raw = readV50();
  const iau = readIau();
  const figures = readFigures();

  const excluded = raw.filter(function (s) { return EXCLUDE[s.hr]; }).map(function (s) {
    return { hr: s.hr, hd: s.hd, bsc: s.bscName || "—", magnitude: s.magnitude, reason: EXCLUDE[s.hr] };
  });
  let stars = raw.filter(function (s) { return !EXCLUDE[s.hr]; })
    .sort(function (a, b) { return a.magnitude - b.magnitude || a.hr - b.hr; });

  // Слияние: к каждой звезде — все, кто слабее и ближе MERGE_DEG.
  const merged = [], gone = new Set();
  for (const s of stars) {
    if (gone.has(s.hr)) continue;
    const near = stars.filter(function (o) {
      return o !== s && !gone.has(o.hr) && separation(s.ra, s.dec, o.ra, o.dec) < MERGE_DEG;
    });
    if (!near.length) continue;
    const parts = [s].concat(near);
    const flux = parts.reduce(function (f, p) { return f + Math.pow(10, -0.4 * p.magnitude); }, 0);
    s.components = parts.map(function (p) {
      return { hr: p.hr, bsc: p.bscName, magnitude: p.magnitude, spectralClass: p.spectralClass,
        separationDeg: round(separation(s.ra, s.dec, p.ra, p.dec), 4) };
    });
    s.magnitude = round(-2.5 * Math.log10(flux), 2);
    s.spectralClass = parts.map(function (p) { return p.spectralClass; }).join("+");
    near.forEach(function (o) { gone.add(o.hr); });
    merged.push(s.hr);
  }
  stars = stars.filter(function (s) { return !gone.has(s.hr); })
    .sort(function (a, b) { return a.magnitude - b.magnitude || a.hr - b.hr; });

  const top = stars.slice(0, NAMED_RU).map(function (s) { return s.hr; });
  const table = Object.keys(NAMES_RU).map(Number);
  const extraRu = table.filter(function (hr) { return top.indexOf(hr) < 0; });
  const missingRu = top.filter(function (hr) { return !(hr in NAMES_RU); });
  if (extraRu.length || missingRu.length)
    throw new Error("NAMES_RU не совпадает с " + NAMED_RU + " самыми яркими: лишние HR " + extraRu +
      ", нет HR " + missingRu);

  const records = stars.map(function (s, i) {
    const b = bayerParts(s.bscName);
    // У слитой пары α¹ + α² — одна точка, и обозначение без номера: «α Cen».
    if (b && s.components && s.components.every(function (c) {
      const p = bayerParts(c.bsc);
      return p && p.greek === b.greek && p.con === b.con;
    })) b.sup = "";
    const bayer = b ? GREEK[b.greek][0] + (SUP[b.sup] || "") + " " + b.con : null;
    let name = (IAU_LATER[s.hr] && IAU_LATER[s.hr].name) || iau[s.hr];
    if (!name) {
      if (!b || !GENITIVE[b.con]) throw new Error("HR " + s.hr + ": нет имени МАС и не собрать латинское из «" + s.bscName + "»");
      name = GREEK[b.greek][1] + (SUP[b.sup] || "") + " " + GENITIVE[b.con];
    }
    const r = { rank: i + 1, hr: s.hr, hd: s.hd, name: name };
    if (NAMES_RU[s.hr]) r.nameRu = NAMES_RU[s.hr];
    r.bayer = bayer || s.bscName;
    r.ra = round(s.ra, 5);
    r.dec = round(s.dec, 4);
    r.magnitude = s.magnitude;
    r.spectralClass = s.spectralClass;
    if (s.components) r.components = s.components;
    const hits = figures.map(function (f) {
      return { code: f.code, index: f.index, magnitude: f.magnitude,
        separationDeg: round(separation(r.ra, r.dec, f.ra, f.dec), 4) };
    }).filter(function (f) { return f.separationDeg < MATCH_DEG; });
    if (hits.length) r.figures = hits;
    return r;
  });

  const inFigures = records.filter(function (r) { return r.figures; });
  const added = records.filter(function (r) { return !r.figures; });
  const mergedAway = raw.length - excluded.length - records.length;
  return {
    about: "Яркие звёзды (V ≤ " + LIMIT + ") для слоя звёзд AR. Собрано Tools/bright_stars/build.js " +
      "из снимков Tools/bright_stars/sources/, руками не править. В BrightStars.generated.swift уходит " +
      "только «added»: «inFigures» уже есть в фигурах созвездий (ConstellationCatalog), здесь — запись сверки.",
    units: "ra — прямое восхождение, часы; dec — склонение, градусы; эпоха и равноденствие J2000; " +
      "magnitude — видимая величина V; separationDeg — угол до звезды фигуры, градусы",
    source: "Yale Bright Star Catalogue, 5th Revised Ed. (Hoffleit & Warren 1991), VizieR V/50; " +
      "имена — IAU WGSN (IAU-CSN 2022-04-04 + позднейшие решения WGSN); русские — ру-Википедия / Wikidata",
    rules: { magnitudeLimit: LIMIT, matchToleranceDeg: MATCH_DEG, mergeToleranceDeg: MERGE_DEG, namedRu: NAMED_RU },
    counts: { catalog: raw.length, excluded: excluded.length, mergedAway: mergedAway, stars: records.length,
      inFigures: inFigures.length, added: added.length, figureStars: figures.length },
    excluded: excluded,
    inFigures: inFigures,
    added: added,
  };
}

/** JSON с одной звездой на строку: читается глазами и даёт короткий diff. */
function serialize(obj) {
  const lines = ["{"];
  const keys = Object.keys(obj);
  keys.forEach(function (k, i) {
    const v = obj[k], comma = i < keys.length - 1 ? "," : "";
    if (Array.isArray(v)) {
      lines.push("  " + JSON.stringify(k) + ": [");
      v.forEach(function (e, j) { lines.push("    " + JSON.stringify(e) + (j < v.length - 1 ? "," : "")); });
      lines.push("  ]" + comma);
    } else {
      lines.push("  " + JSON.stringify(k) + ": " + JSON.stringify(v) + comma);
    }
  });
  lines.push("}");
  return lines.join("\n") + "\n";
}

module.exports = { build: build, serialize: serialize, separation: separation, readFigures: readFigures,
  readV50: readV50, OUT: OUT, LIMIT: LIMIT, MATCH_DEG: MATCH_DEG, NAMES_RU: NAMES_RU };

if (require.main === module) {
  const data = build();
  fs.writeFileSync(OUT, serialize(data));
  const c = data.counts;
  console.log("V/50 с V ≤ " + LIMIT + ": " + c.catalog + "; исключено " + c.excluded + ", слито пар " +
    c.mergedAway + " → " + c.stars + " звёзд: уже в фигурах " + c.inFigures + ", добавлено " + c.added +
    " → " + path.relative(process.cwd(), OUT));
}
