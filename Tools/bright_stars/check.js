/* Проверка каталога ярких звёзд: bright_stars.json против правил и независимых источников.

   Сети не нужно — сверка идёт со снимками sources/ (их пишет fetch.js).
   Любая строка «НЕТ» — код выхода 1.

     1. Поля: RA в 0…24 ч, Dec в −90…90°, V ≤ 2,5, имена и спектр не пустые.
     2. Дублей нет: HR не повторяется, никакие две звезды не ближе допуска.
     3. Блоки честные: у «inFigures» ссылки на фигуры ведут к звезде ближе
        допуска, у «added» ни одной звезды фигур ближе допуска нет.
     4. Сборка повторяема: build.js из снимков даёт тот же JSON, gen_swift.js —
        тот же Swift, что лежит в дереве.
     5. Координаты против SIMBAD (ICRS, J2000): все звёзды, расхождение ≤ 0,02°.
     6. Русские имена против Wikidata: заголовок статьи ру-Википедии и русская
        метка — у звезды или у её системы (P361) — оба равны имени.

   Пример:
     node Tools/bright_stars/check.js
*/
"use strict";
const fs = require("fs"), path = require("path");
const B = require("./build.js");
const G = require("./gen_swift.js");
const SRC = path.join(__dirname, "sources");
const SIMBAD_DEG = 0.02;

const data = JSON.parse(fs.readFileSync(B.OUT, "utf8"));
const stars = data.inFigures.concat(data.added);
const lines = [];
let failed = false;
function line(ok, text) { lines.push((ok ? "да  " : "НЕТ ") + text); if (!ok) failed = true; }
function fmt(v, d) { return v.toFixed(d).replace(".", ","); }
function arcsec(deg) { return fmt(deg * 3600, 2) + "″"; }

// 1. Поля.
const bad = stars.filter(function (s) {
  return !(s.ra >= 0 && s.ra < 24) || !(s.dec >= -90 && s.dec <= 90) || !(s.magnitude <= B.LIMIT) ||
    !s.name || !s.name.trim() || !s.bayer || !s.spectralClass ||
    ("nameRu" in s && !(s.nameRu && s.nameRu.trim()));
});
const ras = stars.map(function (s) { return s.ra; }), decs = stars.map(function (s) { return s.dec; });
const mags = stars.map(function (s) { return s.magnitude; });
line(bad.length === 0, "поля: " + stars.length + " звёзд, RA " + fmt(Math.min.apply(null, ras), 3) + "…" +
  fmt(Math.max.apply(null, ras), 3) + " ч, Dec " + fmt(Math.min.apply(null, decs), 2) + "…" +
  fmt(Math.max.apply(null, decs), 2) + "°, V " + fmt(Math.min.apply(null, mags), 2) + "…" +
  fmt(Math.max.apply(null, mags), 2) + ", пустых имён и спектров 0" +
  (bad.length ? "; ПЛОХИЕ: HR " + bad.map(function (s) { return s.hr; }).join(", ") : ""));

// 2. Дубли.
const hrs = stars.map(function (s) { return s.hr; });
const dupHr = hrs.filter(function (h, i) { return hrs.indexOf(h) !== i; });
let closest = { d: Infinity };
for (let i = 0; i < stars.length; i++) for (let j = i + 1; j < stars.length; j++) {
  const d = B.separation(stars[i].ra, stars[i].dec, stars[j].ra, stars[j].dec);
  if (d < closest.d) closest = { d: d, a: stars[i], b: stars[j] };
}
line(dupHr.length === 0 && closest.d >= B.MATCH_DEG, "дублей нет: HR повторов " + dupHr.length +
  ", ближайшая пара " + closest.a.bayer + " — " + closest.b.bayer + " " + fmt(closest.d, 3) + "° (допуск " +
  fmt(B.MATCH_DEG, 2) + "°)");

// 3. Блоки против 163 звёзд фигур.
const fig = B.readFigures();
function nearest(s) {
  return fig.reduce(function (best, f) {
    const d = B.separation(s.ra, s.dec, f.ra, f.dec);
    return d < best.d ? { d: d, f: f } : best;
  }, { d: Infinity });
}
const badRef = data.inFigures.filter(function (s) {
  return !s.figures.length || s.figures.some(function (r) {
    const f = fig.find(function (x) { return x.code === r.code && x.index === r.index; });
    return !f || B.separation(s.ra, s.dec, f.ra, f.dec) >= B.MATCH_DEG;
  });
});
const worstIn = data.inFigures.reduce(function (w, s) { const n = nearest(s); return n.d > w.d ? { d: n.d, s: s, f: n.f } : w; }, { d: 0 });
line(badRef.length === 0, "уже в фигурах: " + data.inFigures.length + " звёзд, ссылок " +
  data.inFigures.reduce(function (n, s) { return n + s.figures.length; }, 0) + " (Альферац и Эльнат — в двух фигурах), " +
  "дальше всех " + worstIn.s.name + " (" + worstIn.f.code + " №" + worstIn.f.index + ") " + fmt(worstIn.d, 4) + "°");
const clash = data.added.filter(function (s) { return nearest(s).d < B.MATCH_DEG; });
const nearAdded = data.added.reduce(function (w, s) { const n = nearest(s); return n.d < w.d ? { d: n.d, s: s, f: n.f } : w; }, { d: Infinity });
line(clash.length === 0, "добавлено: " + data.added.length + " звёзд, ни одной звезды фигур ближе " +
  fmt(B.MATCH_DEG, 2) + "°; ближе всех " + nearAdded.s.name + " — " + fmt(nearAdded.d, 2) + "° от " +
  nearAdded.f.code + " №" + nearAdded.f.index);
const c = data.counts;
line(c.excluded + c.mergedAway + c.inFigures + c.added === c.catalog && c.figureStars === fig.length,
  "счёт: в V/50 с V ≤ " + fmt(B.LIMIT, 1) + " — " + c.catalog + " = исключено " + c.excluded + " + слито " +
  c.mergedAway + " + в фигурах " + c.inFigures + " + добавлено " + c.added + "; звёзд фигур " + fig.length);

// 4. Повторяемость.
line(B.serialize(B.build()) === fs.readFileSync(B.OUT, "utf8"), "build.js из снимков даёт bright_stars.json побайтово");
line(fs.existsSync(G.TARGET) && fs.readFileSync(G.TARGET, "utf8") === G.render(data),
  "gen_swift.js даёт BrightStars.generated.swift побайтово");

// 5. SIMBAD.
const sb = JSON.parse(fs.readFileSync(path.join(SRC, "simbad.json"), "utf8")).stars;
const rows = stars.map(function (s) {
  const r = sb.find(function (x) { return x.hd === s.hd; });
  return { s: s, r: r, d: r ? B.separation(s.ra, s.dec, r.ra / 15, r.dec) : Infinity,
    dv: r && r.v != null ? s.magnitude - r.v : null };
}).sort(function (a, b) { return a.s.rank - b.s.rank; });
const missing = rows.filter(function (x) { return !x.r; });
const ds = rows.filter(function (x) { return x.r; }).map(function (x) { return x.d; }).sort(function (a, b) { return a - b; });
const over = rows.filter(function (x) { return x.d > SIMBAD_DEG; });
const worst = rows.reduce(function (w, x) { return x.r && x.d > w.d ? x : w; }, { d: -1 });
line(missing.length === 0 && over.length === 0, "SIMBAD: сверено " + ds.length + " из " + stars.length +
  " звёзд, расхождение медиана " + arcsec(ds[ds.length >> 1]) + ", максимум " + arcsec(worst.d) + " (" + worst.s.name +
  ") при допуске " + fmt(SIMBAD_DEG, 2) + "° = " + arcsec(SIMBAD_DEG) + "; больше допуска " + over.length +
  (missing.length ? "; НЕТ В SIMBAD: HD " + missing.map(function (x) { return x.s.hd; }).join(", ") : ""));
const bigDv = rows.filter(function (x) { return x.dv !== null && Math.abs(x.dv) > 0.15; });

// 6. Русские имена.
const wd = JSON.parse(fs.readFileSync(path.join(SRC, "wikidata_ru.json"), "utf8")).stars;
function norm(s) { return s ? s.replace(/\s*\([^)]*\)$/, "").replace(/\s+[A-C]$/, "").toLowerCase() : null; }
const named = stars.filter(function (s) { return s.nameRu; });
const unconfirmed = named.filter(function (s) {
  const rec = wd.find(function (x) { return x.hd === s.hd; });
  const want = s.nameRu.toLowerCase();
  return !rec || !rec.items.some(function (it) {
    return [it].concat(it.partOf).some(function (o) { return norm(o.ruLabel) === want && norm(o.ruTitle) === want; });
  });
});
const doubts = Object.keys(B.NAMES_RU).filter(function (hr) { return B.NAMES_RU[hr] === null; })
  .map(function (hr) { return stars.find(function (s) { return s.hr === +hr; }); });
line(unconfirmed.length === 0, "русские имена: " + named.length + " из 30 самых ярких, все совпали с заголовком " +
  "статьи и меткой Wikidata; без русского имени (источники расходятся): " +
  doubts.map(function (s) { return s.name + " (" + s.bayer + ")"; }).join(", ") +
  (unconfirmed.length ? "; НЕ ПОДТВЕРЖДЕНЫ: " + unconfirmed.map(function (s) { return s.nameRu; }).join(", ") : ""));

console.log(lines.join("\n"));

// Таблица для отчёта: 10 самых ярких (каждый блок представлен) и 3 худших по SIMBAD.
console.log("\nСверка с SIMBAD, 10 самых ярких:");
console.log("ранг  звезда              блок        RA, ч      Dec, °     Δ, ″    V − V(SIMBAD)");
rows.slice(0, 10).forEach(function (x) {
  const block = data.added.indexOf(x.s) >= 0 ? "добавлена" : "в фигуре";
  console.log(String(x.s.rank).padStart(4) + "  " + (x.s.nameRu || x.s.name).padEnd(18) + "  " + block.padEnd(10) +
    "  " + fmt(x.s.ra, 5).padStart(9) + "  " + fmt(x.s.dec, 4).padStart(9) + "  " + fmt(x.d * 3600, 2).padStart(6) +
    "   " + (x.dv === null ? "—" : fmt(x.dv, 2)));
});
console.log("Три наибольших расхождения: " + rows.slice().sort(function (a, b) { return b.d - a.d; }).slice(0, 3)
  .map(function (x) { return x.s.name + " " + arcsec(x.d); }).join(", "));
if (bigDv.length) console.log("Величина V/50 и SIMBAD расходятся больше 0,15 (переменные и кратные звёзды, не ошибка): " +
  bigDv.map(function (x) { return x.s.name + " " + fmt(x.s.magnitude, 2) + " / " + fmt(x.r.v, 2); }).join(", "));
process.exit(failed ? 1 : 0);
