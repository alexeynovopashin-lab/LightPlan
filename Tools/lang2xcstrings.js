/* Словарь беты → String Catalog (`Localizable.xcstrings`).

   Источник один — `beta/lang.js` веба. Каталог не правится руками: его
   пересобирают этим скриптом, а не редактируют в Xcode. Правка слова идёт в
   вебе, сюда приезжает заново (SWIFT_MIGRATION_PLAN, итерация 14).

   Что переезжает и как:

   - Ключи один к одному, значения слово в слово. Подстановка по имени
     `{name}` остаётся как есть: каталог её не разбирает, разбирает
     `Lexicon.t` тем же способом, что `LANG.t` в вебе. Знак `%` в значении —
     обычный знак (замерено: сборка каталога его не трогает).
   - Ключ-массив — это слово по формам числа (`unit.shoot`). В каталог оно
     уходит как plural-вариация по правилам CLDR, форма → категория:
       ru  [0, 1, 2]  → one, few, many (и other = many)
       en, es [0, 1]  → one, other
       ja, zh [0]     → other
     Ключ, что в одном языке массив, а в другом строка (zh не склоняет), в
     каталоге склоняется везде, а строка идёт в `other`.
   - Каталог требует, чтобы форма ссылалась на число (замерено 21.09.2026:
     «Plural variation requires referencing the number in the string»). Веб
     отдаёт слово без числа, поэтому форма пишется как `%lld` + метка + слово,
     где метка — `U+2063`. `Lexicon.word` берёт то, что после метки;
     `Lexicon.count` собирает число, разделитель языка и слово.
   - Язык `en` в каталоге — основа (британская, как в вебе); `en-US` хранит
     только пять отличий, `en-GB` пуст и в каталог не попадает: цепочка
     `en-GB → en` сама приводит к основе.
   - Пустой словарь (заготовка `ja` до перевода) в каталог не пишется вовсе:
     ключа в языке нет — цепочка падает в английский.

   Пример:
     node Tools/lang2xcstrings.js            собрать каталог
     node Tools/lang2xcstrings.js --check    доказать, что лежащий каталог свежий
*/
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(ROOT, "Packages", "LightPlanUI", "Sources", "LightPlanUI",
  "Resources", "Localizable.xcstrings");

/* Метка между числом и словом в форме множественного числа. Невидимый
   разделитель: в слове её не бывает, а если бы упала на экран, не видна. */
const MARK = "\u2063";

/* Форма → категория CLDR. Порядок форм — порядок правила языка в lang.js
   (`RULES`), номер формы отдаёт правило. */
const CATEGORIES = {
  ru: ["one", "few", "many"],
  en: ["one", "other"],
  es: ["one", "other"],
  ja: ["other"],
  zh: ["other"],
};

function webRoot() {
  return process.env.LIGHT_PLAN_WEB || path.resolve(ROOT, "..", "Light_Plan");
}

function loadDict() {
  const file = path.join(webRoot(), "beta", "lang.js");
  if (!fs.existsSync(file)) {
    throw new Error("не найден словарь: " + file + "\n(папка веба задаётся переменной LIGHT_PLAN_WEB)");
  }
  /* Те же заглушки окружения, что в `tools/langcheck.js` веба */
  const g = vm.createContext({
    navigator: { language: "ru-RU" },
    document: { documentElement: {} },
    localStorage: { getItem: () => null, setItem: () => {} },
  });
  vm.runInContext(fs.readFileSync(file, "utf8"), g, { filename: file });
  return g.LANG.dict;
}

const baseOf = (code) => code.split("-")[0];

function unit(value) {
  return { stringUnit: { state: "translated", value: value } };
}

/* Значение языка → запись каталога. isPlural — ключ склоняется в каком-то
   языке, а значит склоняется везде. */
function localization(code, key, value, isPlural) {
  if (!isPlural) {
    if (typeof value !== "string") throw new Error(code + " · " + key + ": ожидалась строка");
    return unit(value);
  }
  const cats = CATEGORIES[baseOf(code)];
  if (!cats) throw new Error(code + ": нет таблицы форм для языка");
  const forms = Array.isArray(value) ? value : [value];
  if (Array.isArray(value) && forms.length !== cats.length) {
    throw new Error(code + " · " + key + ": форм " + forms.length + ", а у языка " + cats.length);
  }
  const plural = {};
  cats.forEach((cat, i) => { plural[cat] = unit("%lld" + MARK + forms[i]); });
  /* other обязателен всегда: русское many берёт и дроби, и «прочее» */
  if (!plural.other) plural.other = unit("%lld" + MARK + forms[forms.length - 1]);
  return { variations: { plural: plural } };
}

function build(dict) {
  const codes = Object.keys(dict).filter((c) => Object.keys(dict[c]).length > 0);
  const keys = new Set();
  codes.forEach((c) => Object.keys(dict[c]).forEach((k) => keys.add(k)));

  const strings = {};
  let plural = 0;
  for (const key of [...keys].sort()) {
    const isPlural = codes.some((c) => Array.isArray(dict[c][key]));
    if (isPlural) plural++;
    const localizations = {};
    for (const c of codes) {
      if (dict[c][key] == null) continue;
      localizations[c] = localization(c, key, dict[c][key], isPlural);
    }
    strings[key] = { extractionState: "manual", localizations: localizations };
  }
  return { catalog: { sourceLanguage: "en", strings: strings, version: "1.1" }, codes, plural };
}

/* Печать в манере Xcode: два пробела и « : » с пробелом до двоеточия. Чтобы
   Xcode, открыв каталог, не переписал его целиком, и в git виден настоящий
   diff, а не смена формата. Ключи объекта — как пришли (в `strings` уже
   отсортированы), кроме `sourceLanguage` и `version`, которые Xcode тоже держит
   в алфавитном порядке. */
function print(v, indent) {
  const pad = "  ".repeat(indent);
  if (v === null || typeof v !== "object") return JSON.stringify(v);
  const ks = Object.keys(v);
  if (!ks.length) return "{\n" + pad + "}";
  const body = ks.map((k) => pad + "  " + JSON.stringify(k) + " : " + print(v[k], indent + 1));
  return "{\n" + body.join(",\n") + "\n" + pad + "}";
}

function main() {
  const check = process.argv.includes("--check");
  const { catalog, codes, plural } = build(loadDict());
  const text = print(catalog, 0) + "\n";
  const keyCount = Object.keys(catalog.strings).length;
  if (check) {
    const have = fs.existsSync(OUT) ? fs.readFileSync(OUT, "utf8") : "";
    if (have !== text) {
      console.error("каталог устарел или правился руками: node Tools/lang2xcstrings.js");
      process.exit(1);
    }
    console.log("каталог свежий: " + keyCount + " ключей, языки " + codes.join(" "));
    return;
  }
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, text);
  console.log(keyCount + " ключей (из них склоняемых " + plural + "), языки: " + codes.join(" "));
  console.log("→ " + path.relative(ROOT, OUT) + " (" + text.length + " байт)");
}

try { main(); } catch (e) { console.error(e.message); process.exit(1); }
