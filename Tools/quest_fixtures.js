// Итерация 28, шаг 8: ссылки опросника для тестов разбора. Код собирает ТА ЖЕ функция `encode`, что на
// странице `quest/wedding.html` (берётся из её текста), а ожидаемый ответ считает ТА ЖЕ `questDecode`, что в
// бете (берётся из `beta/index.html`) — эталон не мой, а веба.
//   node Tools/quest_fixtures.js <корень Light_Plan> > Packages/LightPlanDomain/Tests/LightPlanDomainTests/QuestFixtures.swift
const fs = require("fs");
const root = process.argv[2];
const page = fs.readFileSync(root + "/quest/wedding.html", "utf8");
const beta = fs.readFileSync(root + "/beta/index.html", "utf8");
const cut = (src, from, to) => { const a = src.indexOf(from), b = src.indexOf(to, a); if (a < 0 || b < 0) throw new Error(from); return src.slice(a, b); };
const encode = eval("(" + cut(page, "function encode(obj)", "/* Обратный адрес").trim() + ")");
const keys = cut(beta, "var QUEST_KEYS", "function questDecode");
const dec = cut(beta, "function questDecode", "/* Дата приходит машинной");
const questDecode = new Function(keys + dec + "; return questDecode;")();

const long = "Хочется живых кадров без постановки, ".repeat(20).trim(); // > 600 знаков
const full = { b: "Екатерина Соколова", bt: "8 913 111-22-33", bs: "@katya.sokolova", bm: "Telegram", g: "Вячеслав Орлов",
  gt: "+7 913 000-44-55", d: "2027-06-15", z: "Дворец бракосочетания, ул. Ленина, 10, 12:30", vn: "Храм Покрова, 14:00",
  vy: "Парк «Нагорный», 13:15", q: "Ресторан «Белый», Красноармейский 45, с 17:00", n: "48",
  pr: "Мама невесты — Ольга, +7 913 222-33-44\nОтец жениха — Сергей", sv: "Анна и Дмитрий", vd: "Игорь, +7 913 555-66-77",
  au: "Белый Мерседес, к 11:00", ko: "Тёмно-синий, бабочка", pl: "Молочное, шлейф", mu: "Скрипка и саксофон",
  fi: "Фейерверк во дворе", zh: "Собака Бублик на прогулке", re: "Выкуп, каравай; без алкоголя на площадке",
  ms: "Набережная, старый мост, ботанический сад", w: "Больше живых кадров, меньше постановки. Без «фильтров».",
  pin: "https://pin.it/3xYzAbC" };
const cases = [
  ["full25", "полная анкета, кириллица, 25 полей", full],
  ["pairOnly", "только имена и телефоны, номер с восьмёркой", { b: "Лена", bt: "8 913 343 53 63", g: "Тимур", gt: "+7 913 000-00-00" }],
  ["offsiteYes", "выездная — голое «да», дата и заметка", { vy: "да", d: "2027-02-30", w: "Х" }],
  ["cut601", "пожелание длиннее 600 — обрезается, и ещё ровно 600", { w: long + "!".repeat(0), re: "я".repeat(600), ms: "я".repeat(601), pr: "  " + "б".repeat(605) + "  " }],
  ["multiline", "перевод строки и значки вне BMP", { pr: "Мама\nПапа\n\nБабушка", zh: "Кот 🐈 Барсик", w: "  с пробелами по краям  " }],
  ["foreign", "чужие ключи и не строки", { b: "Катя", x: "чужое", n: 12, g: ["a"], d: null, vy: true, w: "   " }],
  ["textOnly", "только знакомое из чужого", { x: "1", y: "2" }],
];
const swift = s => JSON.stringify(s).replace(/\\u([0-9a-fA-F]{4})/g, "\\u{$1}");
const url = code => "https://example.org/light_plan/beta/?ans=" + code;
let out = "// СГЕНЕРИРОВАНО Tools/quest_fixtures.js (итерация 28, шаг 8) — не править руками.\n";
out += "// Код — функция `encode` страницы опросника, ожидаемое — `questDecode` беты.\n\n";
out += "enum QuestFixtures {\n    struct Link { let name: String; let note: String; let url: String; let expected: [String: String]; let truncated: Set<String> }\n\n    static let links: [Link] = [\n";
for (const [name, note, obj] of cases) {
  const code = encode(obj);
  let exp = {}; try { exp = questDecode(code); } catch (e) { exp = null; }
  const tr = Object.keys(obj).filter(k => typeof obj[k] === "string" && obj[k].trim().length > 600).sort();
  const pairs = Object.keys(exp).sort().map(k => swift(k) + ": " + swift(exp[k])).join(", ");
  out += `        Link(name: ${swift(name)}, note: ${swift(note)}, url: ${swift(url(code))},\n             expected: [${pairs || ":"}], truncated: [${tr.map(swift).join(", ")}]),\n`;
}
out += "    ]\n\n    /// Битые коды: разбор обязан вернуть состояние, а не упасть.\n    static let broken: [(name: String, code: String)] = [\n";
const b64 = s => Buffer.from(s, "utf8").toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
for (const [n, c] of [["notBase64", "!!!"], ["truncatedCode", encode(full).slice(0, 37)], ["notJSON", b64("это не json")],
                      ["array", b64('["b","Катя"]')], ["scalar", b64("42")], ["emptyObject", b64("{}")], ["nullJSON", b64("null")]]) {
  let ok = "throws"; try { const r = questDecode(c); ok = Object.keys(r).length ? "answer" : "empty"; } catch (e) {}
  out += `        (${swift(n + " /* web: " + ok + " */")}, ${swift(c)}),\n`;
}
out += "    ]\n}\n";
process.stdout.write(out);
