/* Каталог созвездий беты (`beta/sky.js`, пасхалка «Астро») → Swift.

   Числа не вводятся руками: `window.SKY` исполняется из живого файла, и в
   `ConstellationCatalog.generated.swift` уходят те же литералы, что видит
   браузер. Дрейф ловит стенд паритета (`Fixtures/constellations.json` несёт
   каталог целиком, `ConstellationParityTests` сверяет его строго).

   Пример:
     LIGHT_PLAN_WEB=<путь к Light_Plan> node Tools/sky2swift.js
*/
"use strict";
const fs = require("fs"), path = require("path"), vm = require("vm");
const ROOT = path.resolve(__dirname, "..");
const web = process.env.LIGHT_PLAN_WEB || path.resolve(ROOT, "..", "Light_Plan");
const src = fs.readFileSync(path.join(web, "beta", "sky.js"), "utf8");
const win = {};
vm.runInNewContext(src, { window: win });
const SKY = win.SKY;
if (!Array.isArray(SKY) || !SKY.length) { console.error("sky.js: нет window.SKY"); process.exit(1); }

const out = [];
out.push("// Сгенерировано `Tools/sky2swift.js` из `beta/sky.js` — не править руками.");
out.push("// Экваториальные координаты эпохи J2000: RA в часах, Dec в градусах, величина.");
out.push("");
out.push("extension ConstellationCatalog {");
out.push("    public static let all: [Constellation] = [");
for (const c of SKY) {
  out.push("        Constellation(");
  out.push("            code: " + JSON.stringify(c.n) + ",");
  out.push("            stars: [");
  for (const s of c.s) out.push("                CatalogStar(ra: " + s[0] + ", dec: " + s[1] + ", magnitude: " + s[2] + "),");
  out.push("            ],");
  out.push("            lines: [" + c.l.map(function (p) { return "[" + p[0] + ", " + p[1] + "]"; }).join(", ") + "]),");
}
out.push("    ]");
out.push("}");
const target = path.join(ROOT, "Packages/LightPlanCore/Sources/LightPlanCore/Sky/ConstellationCatalog.generated.swift");
fs.writeFileSync(target, out.join("\n") + "\n");
console.log(SKY.length + " созвездий, " + SKY.reduce(function (n, c) { return n + c.s.length; }, 0) + " звёзд, " +
  SKY.reduce(function (n, c) { return n + c.l.length; }, 0) + " линий → " + path.relative(ROOT, target));
