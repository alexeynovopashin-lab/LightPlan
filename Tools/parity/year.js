/* Эталон для итерации 22 (год и статистика): прибыль года по валютам и
   основа слова поиска. Пишет Fixtures/year.json.

   Отдельным файлом и своим отпечатком, как planner.js. Код не копируется —
   режется из живого `beta/index.html`:
   - счёт года — от строки `var all = sessions.filter(` внутри `renderYear` до
     конца цикла нарастающего итога (`yearProfitCum.push(run);` и `}`);
     строки про разметку (`$("yearSum")`, `$("statsBtn")`, `$("yearStat")`)
     исполняются над пустышками;
   - `PAY` (от `var PAY = {` до `};`), `CURRENCIES`, `sessionCurrency`,
     `sumByCurrency`, `sessionIncome`, `sessionNet`, `isMeet`, `isEvent`,
     `notWork`, `searchStem` — целиком, по имени.

   Данные — «настоящие»: записи посева сезона (`Fixtures/shots/seed_planner.json`,
   тот же посев, что у пар «Съёмок») и их копии с разными валютами, способами
   оплаты, ставками и расходами на 2025–2027 годы: в самом посеве всё в рублях.
   Генератор с постоянным зерном — прогон повторяется побайтово.

   Запуск:  node Tools/parity/year.js [--out Fixtures] [--quiet]
*/
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const crypto = require("crypto");
const X = require("./extract.js");

const args = process.argv.slice(2);
const outDir = args.includes("--out") ? args[args.indexOf("--out") + 1] : path.join(X.ROOT, "Fixtures");
const quiet = args.includes("--quiet");

const main = X.mainScript();

function between(from, toRe) {
  const i = main.indexOf(from);
  if (i < 0) throw new Error("year.js: нет начала «" + from + "» в beta/index.html");
  const rest = main.slice(i);
  const m = toRe.exec(rest);
  if (!m) throw new Error("year.js: нет конца после «" + from + "»");
  return rest.slice(0, m.index + m[0].length);
}

function fn(name) {
  const head = "function " + name + "(";
  const i = main.indexOf(head);
  if (i < 0) throw new Error("year.js: нет функции " + name);
  let depth = 0, j = main.indexOf("{", i);
  for (; j < main.length; j++) {
    if (main[j] === "{") depth++;
    else if (main[j] === "}" && --depth === 0) break;
  }
  return main.slice(i, j + 1);
}

const pieces = [
  between("var PAY = {", /\n\s*\};/),
  between("var CURRENCIES = [", /;/),
  ...["isMeet", "isEvent", "notWork", "sessionCurrency", "sumByCurrency", "sessionIncome", "sessionNet", "searchStem"].map(fn)
].join("\n");
const yearBody = between("var all = sessions.filter(", /yearProfitCum\.push\(run\);\s*\}/);
const digest = crypto.createHash("sha256").update(pieces).update(yearBody).digest("hex").slice(0, 16);

// --- данные ---
const seedFile = path.join(X.ROOT, "Fixtures", "shots", "seed_planner.json");
const seed = JSON.parse(fs.readFileSync(seedFile, "utf8"));
let rs = 22;
const rnd = () => { rs = (rs * 1103515245 + 12345) % 2147483648; return rs / 2147483648; };
const pick = (a) => a[Math.floor(rnd() * a.length)];

/* День записи — «ГГГГ-ММ-ДД» по поясу посева (Барнаул, +7): так его пишет
   `saveAll`, и так его читает натив без оглядки на пояс машины. */
function dayText(v) {
  if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
  const d = new Date(new Date(v).getTime() + 7 * 3600000);
  return d.toISOString().slice(0, 10);
}
const base = seed.sessions.map((s) => Object.assign({}, s, { date: dayText(s.date) }));
const extra = [];
base.forEach((s, i) => {
  for (let k = 0; k < 3; k++) {
    const c = Object.assign({}, s);
    c.id = s.id + "_y" + k;
    const y = 2025 + Math.floor(rnd() * 3), m = 1 + Math.floor(rnd() * 12), d = 1 + Math.floor(rnd() * 28);
    c.date = y + "-" + String(m).padStart(2, "0") + "-" + String(d).padStart(2, "0");
    c.currency = pick(["RUB", "RUB", "USD", "EUR", "JPY", "GBP", "CNY", "XXX", undefined]);
    c.pay = pick(["hourly", "flat", "pack", "object", "item", "", undefined]);
    c.rate = pick([0, 1500, 2500.5, 12000, 95000, null]);
    c.units = pick([0, 1, 3, 12, null]);
    c.expense = pick([0, 500, 6000, 150000, null]);
    c.dur = pick([60, 90, 135, 480, 840]);
    if (rnd() < 0.08) c.kind = "meet";
    extra.push(c);
  }
});
const records = base.concat(extra);

// --- исполнение кода веба ---
const HOME = "RUB";
function runYear(yearShown) {
  const stub = () => ({ innerHTML: "", hidden: false, textContent: "" });
  const ctx = {
    Math, Object,
    currency: HOME,
    sessions: records.map((s) => Object.assign({}, s, { date: new Date(s.date + "T00:00:00") })),
    yearShown,
    now: new Date("2026-09-23T13:00:00"),
    $: stub,
    esc: (x) => String(x),
    LANG: { sep: () => " ", t: () => "" },
    shootWord: () => "",
    genreLine: () => "",
    dMon: () => "",
    repShare: () => 0,
    yearProfitAmt: 0, yearProfitOther: null, yearProfitCum: null
  };
  vm.runInNewContext(pieces + "\n" + yearBody, ctx);
  return {
    year: yearShown,
    amount: ctx.yearProfitAmt,
    cumulative: ctx.yearProfitCum,
    others: ctx.yearProfitOther.map((x) => ({ code: x.code, sum: x.sum }))
  };
}
const years = [2025, 2026, 2027].map(runYear);

const words = ["свадьба", "свадьбу", "ольга", "Ольга", "марк", "портреты", "томск", "новосибирск",
  "аня", "love", "съёмки", "ёлки", "дом невесты", "репортаж", "архитектуры", "кафе"];
const stemCtx = {};
vm.runInNewContext(pieces, stemCtx);
const stems = words.map((w) => ({ q: w, stem: stemCtx.searchStem(w) }));

const out = { source: digest, home: HOME, sessions: records, years, stems };
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, "year.json"), JSON.stringify(out, null, 1) + "\n");
if (!quiet) {
  console.log("year.json: " + records.length + " записей, годы " + years.map((y) => y.year + " (" + y.others.length + " др. валют)").join(", ")
    + ", основ слова " + stems.length + ", отпечаток " + digest);
}
