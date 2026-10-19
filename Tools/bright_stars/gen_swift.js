/* Яркие звёзды вне фигур созвездий → Swift.

   Источник правды — `Tools/bright_stars/bright_stars.json` (его собирает
   build.js из снимков каталогов); в `BrightStars.generated.swift` уходит
   только блок «added»: звёзды, которых нет среди 163 звёзд фигур
   `ConstellationCatalog`, — чтобы одна звезда не рисовалась дважды.

   Пример:
     node Tools/bright_stars/gen_swift.js           # пишет Swift
     node Tools/bright_stars/gen_swift.js --check   # файл совпадает с JSON? (код 1 — нет)
*/
"use strict";
const fs = require("fs"), path = require("path");
const ROOT = path.resolve(__dirname, "../..");
const JSON_FILE = path.join(__dirname, "bright_stars.json");
const TARGET = path.join(ROOT, "Packages/LightPlanCore/Sources/LightPlanCore/Sky/BrightStars.generated.swift");

/** Строковый литерал Swift: кавычки и обратная косая экранируются, управляющих символов быть не должно. */
function swiftString(s) {
  if (typeof s !== "string" || /[\u0000-\u001f\u007f]/.test(s)) throw new Error("не строка для Swift: " + JSON.stringify(s));
  return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}

/** Число как литерал Double: конечное, без экспоненты. */
function swiftDouble(v) {
  if (typeof v !== "number" || !isFinite(v) || /e/i.test(String(v))) throw new Error("не число для Swift: " + v);
  return String(v);
}

function render(data) {
  const out = [];
  out.push("// Сгенерировано `Tools/bright_stars/gen_swift.js` из `Tools/bright_stars/bright_stars.json` — не править руками.");
  out.push("// Экваториальные координаты эпохи J2000: RA в часах, Dec в градусах, видимая величина V.");
  out.push("// Источник: Yale Bright Star Catalogue, 5-е изд. (VizieR V/50); имена — IAU WGSN. Подробно — Tools/bright_stars/README.md.");
  out.push("");
  out.push("/// Яркая звезда (V ≤ " + data.rules.magnitudeLimit + ") вне фигур созвездий: координаты как у `CatalogStar`, плюс имя и спектр.");
  out.push("public struct BrightStar: Sendable, Equatable {");
  out.push("    /// Имя по-английски: принятое МАС, иначе обозначение Байера латиницей («Gamma Centauri»).");
  out.push("    public let name: String");
  out.push("    /// Русское имя — только у " + data.rules.namedRu + " самых ярких звёзд неба; `nil` — показывать `name`.");
  out.push("    public let nameRu: String?");
  out.push("    /// Обозначение Байера: «α Car».");
  out.push("    public let bayer: String");
  out.push("    /// Прямое восхождение, **часы**.");
  out.push("    public let ra: Double");
  out.push("    /// Склонение, градусы.");
  out.push("    public let dec: Double");
  out.push("    /// Видимая величина V; у слитой пары (α Cen, α Cru) — суммарная.");
  out.push("    public let magnitude: Double");
  out.push("    /// Спектральный класс по V/50 («B1III»); у слитой пары — через «+».");
  out.push("    public let spectralClass: String");
  out.push("    /// Номер в Yale Bright Star Catalogue (HR) — по нему звезда ищется в источнике.");
  out.push("    public let hr: Int");
  out.push("}");
  out.push("");
  out.push("/// Яркие звёзды, которых нет среди звёзд `ConstellationCatalog` (сверка по месту, допуск " +
    data.rules.matchToleranceDeg + "°): " + data.added.length + " шт., от яркой к слабой.");
  out.push("public enum BrightStarCatalog {");
  out.push("    public static let all: [BrightStar] = [");
  for (const s of data.added) {
    out.push("        BrightStar(name: " + swiftString(s.name) + ", nameRu: " + (s.nameRu ? swiftString(s.nameRu) : "nil") +
      ", bayer: " + swiftString(s.bayer) + ",");
    out.push("                   ra: " + swiftDouble(s.ra) + ", dec: " + swiftDouble(s.dec) + ", magnitude: " + swiftDouble(s.magnitude) +
      ", spectralClass: " + swiftString(s.spectralClass) + ", hr: " + s.hr + "),");
  }
  out.push("    ]");
  out.push("}");
  return out.join("\n") + "\n";
}

module.exports = { render: render, TARGET: TARGET };

if (require.main === module) {
  const data = JSON.parse(fs.readFileSync(JSON_FILE, "utf8"));
  const text = render(data);
  if (process.argv.includes("--check")) {
    const ok = fs.existsSync(TARGET) && fs.readFileSync(TARGET, "utf8") === text;
    console.log(ok ? "BrightStars.generated.swift совпадает с bright_stars.json" :
      "BrightStars.generated.swift РАСХОДИТСЯ с bright_stars.json — запустите gen_swift.js");
    process.exit(ok ? 0 : 1);
  }
  fs.writeFileSync(TARGET, text);
  console.log(data.added.length + " звёзд → " + path.relative(process.cwd(), TARGET));
}
