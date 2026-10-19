/* Снимки источников для каталога ярких звёзд → Tools/bright_stars/sources/.

   Нужна сеть. Числа в каталог попадают только из этих снимков (их читает
   build.js), поэтому повторная сборка и проверка идут без сети, а смена
   источника видна в diff снимка.

     v50.tsv          Yale Bright Star Catalogue, 5-е изд. (VizieR V/50), все звёзды V < 2,6
     iau_csn.txt      список имён МАС (WGSN, IAU-CSN): шапка + строки наших HR
     wikidata_ru.json русские метки и заголовки статей ру-Википедии (Wikidata, CC0)
     simbad.json      координаты и V из SIMBAD — независимая сверка, в каталог не идут

   Пример:
     node Tools/bright_stars/fetch.js
*/
"use strict";
const fs = require("fs"), path = require("path"), cp = require("child_process");
const OUT = path.join(__dirname, "sources");
const UA = "LightPlanDataCheck/1.0 (https://github.com/alexeynovopashin-lab/LightPlan)";
const LIMIT = 2.5;

// curl, а не fetch Node: curl сам идёт через прокси окружения и есть на Mac.
function curl(args) {
  return cp.execFileSync("curl", ["-sS", "--fail", "-A", UA].concat(args),
    { encoding: "utf8", maxBuffer: 64 << 20 });
}

fs.mkdirSync(OUT, { recursive: true });

// 1. BSC: исходные столбцы каталога (RA/Dec шестидесятеричные, как в V/50).
const v50 = curl(["-G", "https://vizier.cds.unistra.fr/viz-bin/asu-tsv",
  "--data-urlencode", "-source=V/50/catalog",
  "--data-urlencode", "-out=HR,Name,HD,RAJ2000,DEJ2000,Vmag,n_Vmag,SpType",
  "--data-urlencode", "Vmag=<2.6",
  "--data-urlencode", "-sort=Vmag",
  "--data-urlencode", "-out.max=1000"]);
fs.writeFileSync(path.join(OUT, "v50.tsv"), v50);
const rows = v50.split("\n").filter(function (l) { return /^\s*\d+\t/.test(l); })
  .map(function (l) { return l.split("\t"); })
  .filter(function (c) { return parseFloat(c[5]) <= LIMIT; });
const hrs = new Set(rows.map(function (c) { return +c[0]; }));
const hds = rows.map(function (c) { return +c[2]; });
if (rows.length < 80) throw new Error("V/50: всего " + rows.length + " строк с V ≤ " + LIMIT);

// 2. Имена МАС. Файл WGSN большой; берём шапку (там лицензия) и строки наших HR.
const csn = curl(["https://www.pas.rochester.edu/~emamajek/WGSN/IAU-CSN.txt"]).split("\n");
const firstData = csn.findIndex(function (l) { return l && l[0] !== "#" && l[0] !== "$"; });
const keep = csn.slice(0, firstData).concat(csn.slice(firstData).filter(function (l) {
  const m = /\bHR (\d+)\b/.exec(l);
  return l[0] !== "#" && m && hrs.has(+m[1]);
}));
fs.writeFileSync(path.join(OUT, "iau_csn.txt"), keep.join("\n") + "\n");

// 3. Wikidata: звезда по номеру HD, её метка и статья в ру-Википедии, и то же
//    у «части чего» (P361): у Сириуса A статьи нет, у системы «Сириус» есть.
const values = hds.map(function (n) { return '"HD ' + n + '"'; }).join(" ");
const sparql = "SELECT ?code ?item ?ruLabel ?ruTitle ?sys ?sysRuLabel ?sysRuTitle WHERE {\n" +
  "  VALUES ?code { " + values + " }\n" +
  "  ?item p:P528 ?st . ?st ps:P528 ?code . ?st pq:P972 wd:Q111130 .\n" +
  "  OPTIONAL { ?item rdfs:label ?ruLabel FILTER(lang(?ruLabel) = \"ru\") }\n" +
  "  OPTIONAL { ?a schema:about ?item ; schema:isPartOf <https://ru.wikipedia.org/> ; schema:name ?ruTitle }\n" +
  "  OPTIONAL { ?item wdt:P361 ?sys .\n" +
  "    OPTIONAL { ?sys rdfs:label ?sysRuLabel FILTER(lang(?sysRuLabel) = \"ru\") }\n" +
  "    OPTIONAL { ?b schema:about ?sys ; schema:isPartOf <https://ru.wikipedia.org/> ; schema:name ?sysRuTitle } }\n" +
  "}";
const wd = JSON.parse(curl(["-G", "https://query.wikidata.org/sparql",
  "-H", "Accept: application/sparql-results+json", "--data-urlencode", "query=" + sparql]));
const byHd = {};
for (const b of wd.results.bindings) {
  const g = function (k) { return b[k] ? b[k].value : null; };
  const hd = +g("code").replace(/\D/g, "");
  const item = g("item").split("/").pop();
  const rec = byHd[hd] = byHd[hd] || {};
  const it = rec[item] = rec[item] || { ruLabel: g("ruLabel"), ruTitle: g("ruTitle"), partOf: {} };
  if (g("sys")) it.partOf[g("sys").split("/").pop()] = { ruLabel: g("sysRuLabel"), ruTitle: g("sysRuTitle") };
}
const wdOut = hds.slice().sort(function (a, b) { return a - b; }).map(function (hd) {
  const rec = byHd[hd] || {};
  return { hd: hd, items: Object.keys(rec).sort().map(function (q) {
    const it = rec[q], parts = Object.keys(it.partOf).sort();
    return { item: q, ruLabel: it.ruLabel, ruTitle: it.ruTitle,
      partOf: parts.map(function (p) { return Object.assign({ item: p }, it.partOf[p]); }) };
  }) };
});
fs.writeFileSync(path.join(OUT, "wikidata_ru.json"), JSON.stringify({
  source: "Wikidata Query Service, https://query.wikidata.org/ (CC0)",
  query: sparql, stars: wdOut }, null, 1) + "\n");

// 4. SIMBAD: ICRS, эпоха J2000 — для сверки координат, в каталог не идут.
const adql = "SELECT i.id, b.main_id, b.ra, b.dec, b.coo_bibcode, f.flux AS v " +
  "FROM ident AS i JOIN basic AS b ON i.oidref = b.oid " +
  "LEFT JOIN flux AS f ON f.oidref = b.oid AND f.filter = 'V' " +
  "WHERE i.id IN (" + hds.map(function (n) { return "'HD " + n + "'"; }).join(",") + ")";
const sb = JSON.parse(curl(["https://simbad.cds.unistra.fr/simbad/sim-tap/sync",
  "--data-urlencode", "REQUEST=doQuery", "--data-urlencode", "LANG=ADQL",
  "--data-urlencode", "FORMAT=json", "--data-urlencode", "QUERY=" + adql]));
const sbRows = sb.data.map(function (r) {
  return { hd: +String(r[0]).replace(/\D/g, ""), mainId: r[1], ra: r[2], dec: r[3], cooBibcode: r[4], v: r[5] };
}).sort(function (a, b) { return a.hd - b.hd; });
fs.writeFileSync(path.join(OUT, "simbad.json"), JSON.stringify({
  source: "SIMBAD TAP, https://simbad.cds.unistra.fr/simbad/sim-tap (ICRS, epoch J2000, deg)",
  query: adql, stars: sbRows }, null, 1) + "\n");

console.log("V/50: " + rows.length + " звёзд с V ≤ " + LIMIT + "; МАС: " + (keep.length - firstData) +
  " строк; Wikidata: " + Object.keys(byHd).length + " звёзд; SIMBAD: " + sbRows.length + " звёзд → " +
  path.relative(process.cwd(), OUT));
