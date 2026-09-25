/* Эталон телефона (итерация 23): режет таблицу стран и разбор номера из
   `beta/index.html` и пишет Fixtures/tel.json — вход, страна, что вернули
   `formatTel`, `telFull`, `telMobile`, `appId`. Swift сверяется с этим.

   Запуск:  node Tools/parity/tel.js [--out Fixtures] [--quiet]
*/
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const X = require("./extract.js");

const src = fs.readFileSync(X.webPath(), "utf8");
function cut(from, to) {
  const a = src.indexOf(from);
  if (a < 0) throw new Error("нет якоря: " + from);
  const b = src.indexOf(to, a);
  if (b < 0) throw new Error("нет конца блока: " + to);
  return src.slice(a, b);
}
const code = [
  cut("var TEL_CC = {", "/* Догадка по часовому поясу"),
  "var telCountry = 'RU'; function telSpec() { return TEL_CC[telCountry] || TEL_CC.RU; }",
  cut("function telNsnOk(sp, n)", "/* ---------- Национальная часть отдельно"),
  cut("function telDigits(v)", "  /* Ключ, по которому две разные записи"),
].join("\n");
const ctx = vm.createContext({});
vm.runInContext(code + "\nthis.__api = { TEL_CC, setCountry: function (c) { telCountry = c; }, formatTel, telFull, telMobile, appId };", ctx);
const api = ctx.__api;

const inputs = [
  "", "+", "8", "8 9", "89234123333", "8 923 412-33-33", "+79161234567", "+7 916 123-45-67",
  "79161234567", "9161234567", "916 123-45-67", "9618878078", "916123456", "00 34 612345678",
  "+34612345678", "34612345678", "612345678", "612 345 678", "+447911123456", "07911123456",
  "7911123456", "+81 90 1234 5678", "09012345678", "9012345678", "030 12345678", "+493012345678",
  "1512345678", "+1 212 555 0123", "2125550123", "12125550123", "+375291234567", "80291234567",
  "291234567", "+380671234567", "0671234567", "+8613812345678", "13812345678", "abc", "(916) 123",
  "8 (916) 123-45-67", "+7", "+7 9", "7", "1234567890123456",
];
const out = { meta: { countries: Object.keys(api.TEL_CC) }, rows: [] };
for (const iso of Object.keys(api.TEL_CC)) {
  api.setCountry(iso);
  const sp = api.TEL_CC[iso];
  const set = inputs.concat(["+" + sp.cc + sp.ex, sp.trunk + sp.ex, sp.ex, sp.cc + sp.ex, sp.ex.slice(0, 5)]);
  for (const v of set) {
    out.rows.push({
      c: iso, v,
      f: api.formatTel(v, false), p: api.formatTel(v, true),
      full: api.telFull(v), mob: !!api.telMobile(v), id: api.appId(v),
    });
  }
}
const o = process.argv.indexOf("--out");
const quiet = process.argv.includes("--quiet");
const dir = o > 0 ? process.argv[o + 1] : "Fixtures";
fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(path.join(dir, "tel.json"), JSON.stringify(out, null, 1) + "\n");
if (!quiet) console.log("tel.json: " + out.rows.length + " строк, " + out.meta.countries.length + " стран");
