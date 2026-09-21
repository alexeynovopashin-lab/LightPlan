/* Разворачивает библиотеку знаков веба в нативные ресурсы.

   Итерация 15 плана (`light_plan:Light_Plan/SWIFT_MIGRATION_PLAN.md`, § 4.10).
   Источник — `beta/icons.js`, ровно тот файл, что правят руками. Знаки не
   переносятся и не перерисовываются: каждый раз они читаются из живой
   библиотеки и переводятся механически. Ручного шага между вебом и Swift нет.

   Что делает:
     1. Читает `beta/icons.js` и сверяет его со слепком внутри `beta/index.html`.
        Слепок вклеен руками (см. комментарий в бете), и если он разошёлся с
        файлом, эталоном является то, что запускается на телефоне, — то есть
        слепок. Расхождение — остановка, а не предупреждение.
     2. Раскладывает каждое тело знака (`<circle>`, `<rect>`, `<path>`, `<g
        class>`) на части и переводит каждую в абсолютные команды пути:
        M, L, C, Q, Z. Дуги, `H`, `V`, `S`, относительные команды и примитивы
        сведены к этому же набору здесь, в JS, а не в Swift: Swift проигрывает
        готовые команды и не разбирает SVG.
     3. Пишет `IconLibrary.generated.swift` — знаки, правила подбора знака точки
        по слову (`POINT_WORDS`) и состав наборов для контрольного листа.
     4. Пишет `point_sign.json` — ответы веба на корпус названий: по нему Swift
        доказывает, что подбирает тот же знак.

   Правила регулярок при переводе в ICU (NSRegularExpression): `\b`, `\w`, `\d`
   в JS ASCII-шные, в ICU понимают весь Юникод, и «\bbus\b» рядом с кириллицей
   вело бы себя иначе. Они переписываются на явные классы. Всё остальное
   проверяется корпусом, а не догадкой.

   Запуск (из корня нативного репозитория):
     node Tools/icons2assets.js          — записать
     node Tools/icons2assets.js --check  — сравнить с лежащим: разошлось —
                                           код выхода 1, ничего не пишется
*/
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const ROOT = path.resolve(__dirname, "..");

/* Веб — соседняя папка `Light_Plan`. Из worktree корень нативного репозитория
   лежит глубже, поэтому ищем вверх по дереву, а не на один шаг. Путь можно
   задать переменной окружения. */
function webRoot() {
  if (process.env.LIGHT_PLAN_WEB) return path.resolve(process.env.LIGHT_PLAN_WEB);
  let dir = ROOT;
  for (let i = 0; i < 8; i++) {
    const cand = path.join(dir, "Light_Plan");
    if (fs.existsSync(path.join(cand, "beta", "icons.js"))) return cand;
    const up = path.dirname(dir);
    if (up === dir) break;
    dir = up;
  }
  throw new Error("не нашёл соседнюю папку Light_Plan/beta/icons.js; задай LIGHT_PLAN_WEB");
}

const OUT_SWIFT = path.join(ROOT, "Packages/LightPlanUI/Sources/LightPlanUI/Icons/IconLibrary.generated.swift");
const OUT_POINTS = path.join(ROOT, "Packages/LightPlanUI/Tests/LightPlanUITests/point_sign.json");

/* ------------------------------------------------------------------ */
/* Источник                                                             */
/* ------------------------------------------------------------------ */

function loadLibrary() {
  const web = webRoot();
  const file = path.join(web, "beta", "icons.js");
  const src = fs.readFileSync(file, "utf8");

  /* Слепок в бете: от `(function (root) {` до `</script>` после `root.ICONS`. */
  const html = fs.readFileSync(path.join(web, "beta", "index.html"), "utf8");
  const tail = html.indexOf("root.ICONS = ICONS;");
  if (tail < 0) throw new Error("в beta/index.html нет слепка библиотеки знаков (якорь `root.ICONS = ICONS;`)");
  const head = html.lastIndexOf("(function (root) {", tail);
  const snap = html.slice(head, html.indexOf("</script>", tail)).trim();
  const own = src.slice(src.indexOf("(function (root) {")).trim();
  if (snap !== own) {
    throw new Error("слепок в beta/index.html разошёлся с beta/icons.js — сначала синхронизировать их в вебе. "
      + "Длины: слепок " + snap.length + ", файл " + own.length);
  }

  const box = {};
  vm.runInNewContext(src, { window: box });
  return { ICONS: box.ICONS, src, srcBytes: Buffer.byteLength(src) };
}

/* Порядок слияния — тот же, что у `merge` в icons.js: первое имя побеждает. */
const COMMON_ORDER = ["points", "ui", "gear", "weather", "signs", "themes", "places"];
const SHEET_ORDER = ["signs", "points", "ui", "gear", "themes", "weather", "genres", "wishes", "places"];

/* ------------------------------------------------------------------ */
/* Разбор тела знака                                                    */
/* ------------------------------------------------------------------ */

const KNOWN_ATTRS = ["d", "cx", "cy", "r", "rx", "ry", "x", "y", "width", "height", "points",
  "stroke-width", "stroke-linecap", "class"];

/* Тела — простая разметка без вложенных цитат: сканируем теги подряд. */
function parseBody(body) {
  const parts = [];
  const stack = [];
  const re = /<(\/?)([a-zA-Z]+)([^>]*?)(\/?)>/g;
  let m;
  let last = 0;
  while ((m = re.exec(body))) {
    if (body.slice(last, m.index).trim()) throw new Error("текст между тегами: " + body.slice(last, m.index));
    last = re.lastIndex;
    const [, closing, tag, attrText] = m;
    if (closing) {
      if (tag !== "g") throw new Error("закрывающий </" + tag + ">");
      stack.pop();
      continue;
    }
    const attrs = {};
    for (const a of attrText.matchAll(/([\w:-]+)="([^"]*)"/g)) attrs[a[1]] = a[2];
    for (const k of Object.keys(attrs)) if (!KNOWN_ATTRS.includes(k)) throw new Error("неизвестный атрибут " + k);
    if (tag === "g") {
      const cls = attrs.class || "";
      const role = cls === "i-sun" ? "sun" : cls === "i-cloud" ? "cloud" : cls === "i-rain" ? "rain" : "";
      if (cls && !role) throw new Error("неизвестный класс группы: " + cls);
      stack.push(role || (stack.length ? stack[stack.length - 1] : ""));
      continue;
    }
    const role = stack.length ? stack[stack.length - 1] : "";
    let cmds;
    switch (tag) {
      case "path": cmds = parsePath(attrs.d); break;
      case "circle": cmds = ellipseCmds(+attrs.cx, +attrs.cy, +attrs.r, +attrs.r); break;
      case "ellipse": cmds = ellipseCmds(+attrs.cx, +attrs.cy, +attrs.rx, +attrs.ry); break;
      case "rect": cmds = rectCmds(attrs); break;
      case "polyline": cmds = polyCmds(attrs.points); break;
      default: throw new Error("неизвестный тег <" + tag + ">");
    }
    if (attrs["stroke-linecap"] && attrs["stroke-linecap"] !== "butt") {
      throw new Error("stroke-linecap=" + attrs["stroke-linecap"] + ": знаю только butt");
    }
    parts.push({
      role,
      width: attrs["stroke-width"] !== undefined ? +attrs["stroke-width"] : null,
      butt: attrs["stroke-linecap"] === "butt",
      cmds,
    });
  }
  if (body.slice(last).trim()) throw new Error("хвост после тегов: " + body.slice(last));
  if (stack.length) throw new Error("не закрыта <g>");

  /* Соседние части одного стиля сливаем: путь один, кистей меньше. */
  const merged = [];
  for (const p of parts) {
    const prev = merged[merged.length - 1];
    if (prev && prev.role === p.role && prev.width === p.width && prev.butt === p.butt) {
      prev.cmds = prev.cmds.concat(p.cmds);
    } else {
      merged.push({ role: p.role, width: p.width, butt: p.butt, cmds: p.cmds.slice() });
    }
  }
  return merged;
}

/* ------------------------------------------------------------------ */
/* Геометрия: всё в M L C Q Z                                           */
/* ------------------------------------------------------------------ */

/* Сканер данных пути. Флаги дуг читаются одним символом: SVG разрешает
   писать их слитно («a2 2 0 011 1»). В библиотеке таких нет (замерено), но
   сканер устроен по стандарту, а не по этому наблюдению. */
function parsePath(d) {
  const out = [];
  let i = 0;
  const n = d.length;
  const skip = () => { while (i < n && /[\s,]/.test(d[i])) i++; };
  const num = () => {
    skip();
    const m = /^[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/.exec(d.slice(i));
    if (!m) throw new Error("ждал число в «" + d.slice(i, i + 12) + "»");
    i += m[0].length;
    return parseFloat(m[0]);
  };
  const flag = () => {
    skip();
    const c = d[i];
    if (c !== "0" && c !== "1") throw new Error("ждал флаг дуги в «" + d.slice(i, i + 12) + "»");
    i++;
    return c === "1";
  };

  let cx = 0, cy = 0, sx = 0, sy = 0;
  let prevC = null; // опорная точка предыдущего кубика или квадрата — для S и T
  let cmd = "";
  while (true) {
    skip();
    if (i >= n) break;
    if (/[A-Za-z]/.test(d[i])) cmd = d[i++];
    else if (!cmd) throw new Error("путь не начинается с команды: " + d.slice(0, 12));
    else if (cmd === "M") cmd = "L";
    else if (cmd === "m") cmd = "l";
    const rel = cmd === cmd.toLowerCase();
    const C = cmd.toUpperCase();
    const ox = rel ? cx : 0, oy = rel ? cy : 0;
    let nextPrev = null;
    switch (C) {
      case "M": { cx = ox + num(); cy = oy + num(); sx = cx; sy = cy; out.push(["M", cx, cy]); break; }
      case "L": { cx = ox + num(); cy = oy + num(); out.push(["L", cx, cy]); break; }
      case "H": { cx = ox + num(); out.push(["L", cx, cy]); break; }
      case "V": { cy = oy + num(); out.push(["L", cx, cy]); break; }
      case "C": {
        const x1 = ox + num(), y1 = oy + num(), x2 = ox + num(), y2 = oy + num(), x = ox + num(), y = oy + num();
        out.push(["C", x1, y1, x2, y2, x, y]);
        nextPrev = { k: "C", x: x2, y: y2 }; cx = x; cy = y;
        break;
      }
      case "S": {
        const x2 = ox + num(), y2 = oy + num(), x = ox + num(), y = oy + num();
        const x1 = prevC && prevC.k === "C" ? 2 * cx - prevC.x : cx;
        const y1 = prevC && prevC.k === "C" ? 2 * cy - prevC.y : cy;
        out.push(["C", x1, y1, x2, y2, x, y]);
        nextPrev = { k: "C", x: x2, y: y2 }; cx = x; cy = y;
        break;
      }
      case "Q": {
        const x1 = ox + num(), y1 = oy + num(), x = ox + num(), y = oy + num();
        out.push(["Q", x1, y1, x, y]);
        nextPrev = { k: "Q", x: x1, y: y1 }; cx = x; cy = y;
        break;
      }
      case "T": {
        const x = ox + num(), y = oy + num();
        const x1 = prevC && prevC.k === "Q" ? 2 * cx - prevC.x : cx;
        const y1 = prevC && prevC.k === "Q" ? 2 * cy - prevC.y : cy;
        out.push(["Q", x1, y1, x, y]);
        nextPrev = { k: "Q", x: x1, y: y1 }; cx = x; cy = y;
        break;
      }
      case "A": {
        const rx = num(), ry = num(), rot = num(), fa = flag(), fs = flag();
        const x = ox + num(), y = oy + num();
        for (const seg of arcToCubics(cx, cy, rx, ry, rot, fa, fs, x, y)) out.push(seg);
        cx = x; cy = y;
        break;
      }
      case "Z": { out.push(["Z"]); cx = sx; cy = sy; cmd = ""; break; }
      default: throw new Error("команда пути «" + cmd + "» не поддержана");
    }
    prevC = nextPrev;
  }
  return out;
}

/* Дуга: конечные точки → центр (SVG 1.1, F.6.5) → кубики не больше четверти круга. */
function arcToCubics(x1, y1, rx, ry, phiDeg, fa, fs, x2, y2) {
  if (x1 === x2 && y1 === y2) return [];
  rx = Math.abs(rx); ry = Math.abs(ry);
  if (rx === 0 || ry === 0) return [["L", x2, y2]];
  const phi = (phiDeg % 360) * Math.PI / 180;
  const cp = Math.cos(phi), sp = Math.sin(phi);
  const dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
  const x1p = cp * dx + sp * dy, y1p = -sp * dx + cp * dy;
  const lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
  if (lam > 1) { const s = Math.sqrt(lam); rx *= s; ry *= s; }
  const rx2 = rx * rx, ry2 = ry * ry;
  let num = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p;
  const den = rx2 * y1p * y1p + ry2 * x1p * x1p;
  if (num < 0) num = 0;
  const coef = (fa === fs ? -1 : 1) * Math.sqrt(num / den);
  const cxp = coef * (rx * y1p / ry), cyp = coef * -(ry * x1p / rx);
  const cx = cp * cxp - sp * cyp + (x1 + x2) / 2;
  const cy = sp * cxp + cp * cyp + (y1 + y2) / 2;
  const ang = (ux, uy, vx, vy) => Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
  const th1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
  let dth = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
  if (!fs && dth > 0) dth -= 2 * Math.PI;
  else if (fs && dth < 0) dth += 2 * Math.PI;
  const segs = Math.max(1, Math.ceil(Math.abs(dth) / (Math.PI / 2) - 1e-9));
  const step = dth / segs;
  const t = (4 / 3) * Math.tan(step / 4);
  const out = [];
  const pos = (a) => [rx * Math.cos(a), ry * Math.sin(a)];
  const der = (a) => [-rx * Math.sin(a), ry * Math.cos(a)];
  const map = (px, py) => [cp * px - sp * py + cx, sp * px + cp * py + cy];
  let a = th1;
  for (let k = 0; k < segs; k++) {
    const b = a + step;
    const [p1x, p1y] = pos(a), [d1x, d1y] = der(a);
    const [p2x, p2y] = pos(b), [d2x, d2y] = der(b);
    const c1 = map(p1x + t * d1x, p1y + t * d1y);
    const c2 = map(p2x - t * d2x, p2y - t * d2y);
    const e = k === segs - 1 ? [x2, y2] : map(p2x, p2y);
    out.push(["C", c1[0], c1[1], c2[0], c2[1], e[0], e[1]]);
    a = b;
  }
  return out;
}

/* Круг и эллипс по стандарту: старт справа, по часовой (sweep=1). */
function ellipseCmds(cx, cy, rx, ry) {
  const cmds = [["M", cx + rx, cy]];
  for (const s of arcToCubics(cx + rx, cy, rx, ry, 0, false, true, cx - rx, cy)) cmds.push(s);
  for (const s of arcToCubics(cx - rx, cy, rx, ry, 0, false, true, cx + rx, cy)) cmds.push(s);
  cmds.push(["Z"]);
  return cmds;
}

function rectCmds(a) {
  const x = +(a.x || 0), y = +(a.y || 0), w = +a.width, h = +a.height;
  let rx = a.rx !== undefined ? +a.rx : (a.ry !== undefined ? +a.ry : 0);
  let ry = a.ry !== undefined ? +a.ry : rx;
  rx = Math.min(rx, w / 2); ry = Math.min(ry, h / 2);
  if (!rx || !ry) return [["M", x, y], ["L", x + w, y], ["L", x + w, y + h], ["L", x, y + h], ["Z"]];
  const c = [["M", x + rx, y], ["L", x + w - rx, y]];
  for (const s of arcToCubics(x + w - rx, y, rx, ry, 0, false, true, x + w, y + ry)) c.push(s);
  c.push(["L", x + w, y + h - ry]);
  for (const s of arcToCubics(x + w, y + h - ry, rx, ry, 0, false, true, x + w - rx, y + h)) c.push(s);
  c.push(["L", x + rx, y + h]);
  for (const s of arcToCubics(x + rx, y + h, rx, ry, 0, false, true, x, y + h - ry)) c.push(s);
  c.push(["L", x, y + ry]);
  for (const s of arcToCubics(x, y + ry, rx, ry, 0, false, true, x + rx, y)) c.push(s);
  c.push(["Z"]);
  return c;
}

function polyCmds(points) {
  const v = points.trim().split(/[\s,]+/).map(Number);
  const c = [];
  for (let i = 0; i + 1 < v.length; i += 2) c.push([i ? "L" : "M", v[i], v[i + 1]]);
  return c;
}

/* Число: четыре знака после запятой достаточно для холста 24×24 (шаг 1/10000
   единицы — доли тысячной пикселя даже на 1024 pt) и держит файл небольшим. */
function fmt(v) {
  const s = (Math.round(v * 1e4) / 1e4).toString();
  return s === "-0" ? "0" : s;
}
function serialize(cmds) {
  return cmds.map((c) => c[0] + c.slice(1).map(fmt).join(" ")).join("");
}

/* ------------------------------------------------------------------ */
/* Правила подбора знака по слову: JS → ICU                             */
/* ------------------------------------------------------------------ */

const WORD_B = "(?:(?<![A-Za-z0-9_])(?=[A-Za-z0-9_])|(?<=[A-Za-z0-9_])(?![A-Za-z0-9_]))";

/* Переписывает исходник JS-регулярки так, чтобы ICU понял его так же, как JS.
   Идёт по строке, помня, внутри ли класса `[...]` и не экранирован ли символ. */
function jsToIcu(src) {
  let out = "";
  let inClass = false;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (c === "\\") {
      const e = src[i + 1];
      i++;
      if (!inClass && e === "b") out += WORD_B;
      else if (e === "B") throw new Error("\\B в правиле: переписать вручную");
      else if (e === "w") out += inClass ? "A-Za-z0-9_" : "[A-Za-z0-9_]";
      else if (e === "W") { if (inClass) throw new Error("\\W в классе"); out += "[^A-Za-z0-9_]"; }
      else if (e === "d") out += inClass ? "0-9" : "[0-9]";
      else if (e === "D") { if (inClass) throw new Error("\\D в классе"); out += "[^0-9]"; }
      else out += "\\" + e;
      continue;
    }
    if (c === "[" && !inClass) inClass = true;
    else if (c === "]" && inClass) inClass = false;
    out += c;
  }
  return out;
}

/* ------------------------------------------------------------------ */
/* Корпус названий для сверки подбора знака                             */
/* ------------------------------------------------------------------ */

/* Из каждой альтернативы регулярки вытаскиваем «живой» пример: выбрасываем
   синтаксис, оставляем буквы. Это не доказательство покрытия, а способ
   заставить каждое правило сработать хотя бы раз — с окружением, ломающим
   границы слов. */
function literalFrom(alt) {
  return alt
    .replace(/\(\?:\^\|\[\^[^\]]*\]\)/g, " ")
    .replace(/\(\?[:=!][^)]*\)/g, (m) => (m.startsWith("(?:") ? m.slice(3, -1).split("|")[0] : ""))
    .replace(/\\b/g, "")
    .replace(/\\S[*+]?/g, "а")
    .replace(/\\s\*?/g, " ")
    .replace(/\.\{0,\d+\}/g, " ")
    .replace(/\.\?/g, "")
    .replace(/\\(.)/g, "$1")
    .replace(/\[([^\]^]{1,2})[^\]]*\]/g, "$1")
    .replace(/[()?*+^$|]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function splitTop(src) {
  const parts = [];
  let depth = 0, cur = "", inClass = false;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (c === "\\") { cur += c + src[i + 1]; i++; continue; }
    if (c === "[") inClass = true;
    else if (c === "]") inClass = false;
    else if (!inClass && c === "(") depth++;
    else if (!inClass && c === ")") depth--;
    if (c === "|" && depth === 0 && !inClass) { parts.push(cur); cur = ""; continue; }
    cur += c;
  }
  parts.push(cur);
  return parts;
}

function buildCorpus(I) {
  const names = new Set();
  const add = (s) => { if (s && s.length < 80) names.add(s); };
  for (const r of I.pointWords) {
    for (const alt of splitTop(r[0].source)) {
      const w = literalFrom(alt);
      if (!w) continue;
      add(w);
      add(w.toUpperCase());
      add("Съёмка: " + w + " сегодня");
      add("The " + w + " at dawn");
      add(w + "я");   // продолжение слова: граница справа
      add("до" + w);  // приставка: граница слева
      add(w[0].toUpperCase() + w.slice(1));
    }
  }
  /* Руками: то, что регулярки отбирают по границам и диакритикам. */
  [
    " ", "Malecón", "Malecon", "Château de Chenonceau", "Chateau", "köprü", "Köprü",
    "усадьба", "подарки", "смотровая площадка", "площадь", "сад", "Сад", "Роспись хной", "Мехенди",
    "Getting ready", "getting ready", "Сборы невесты", "Сборы жениха", "Съёмка на крыше",
    "Прогулка", "Портреты", "Первый взгляд", "First look", "Ceremony", "Церемония на пляже",
    "Тадж-Махал", "Альгамбра", "Прага", "Тоскана", "Дубай", "Фотосессия", "Гости", "гости",
    "接亲", "迎亲", "换装", "ЗАГС", "Дворец бракосочетания", "Венчание", "Никях", "Nikah",
    "Wedding day", "Пляж", "Мост", "Отель", "Студия", "Кафе", "Ресторан", "Банкет", "Танцы",
    "Sport match", "Матч", "Финиш", "Уборка площадки", "Тост", "Champagne toast", "Автобус гостей",
  ].forEach((s) => names.add(s));

  const places = ["Пляж Ипанема", "Отель Ритц", "Gardens by the Bay", "Крыша", "Бали, Убуд", "Malecón"];
  const sorted = [...names].sort();
  const cases = [["", "", false]];
  for (const name of sorted) cases.push([name, "", false]);
  /* Место и студия — на срезе названий, иначе корпус раздувается зря. */
  sorted.filter((_, i) => i % 7 === 0).forEach((name) => {
    for (const place of places) cases.push([name, place, false]);
    cases.push([name, "", true]);
    cases.push([name, "Пляж Ипанема", true]);
  });
  for (const place of places) cases.push(["", place, false], ["Фотосессия", place, false]);
  return cases;
}

/* ------------------------------------------------------------------ */
/* Вывод                                                                */
/* ------------------------------------------------------------------ */

function swiftString(s) {
  return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\t/g, "\\t") + '"';
}

/* Часть знака в строку: `роль ⇥ ширина ⇥ концы ⇥ команды`. Роль пуста для
   обычной части; ширина пуста, если её задаёт вызывающий. */
function encodeBody(parts) {
  return parts.map((p) => [p.role, p.width === null ? "" : fmt(p.width), p.butt ? "b" : "", serialize(p.cmds)].join("\t")).join("\n");
}

function build() {
  const { ICONS: I, src, srcBytes } = loadLibrary();

  /* Общее пространство имён — как `ALL` в icons.js */
  const common = {};
  const owner = {};
  for (const g of COMMON_ORDER) {
    for (const k of Object.keys(I[g])) if (!(k in common)) { common[k] = I[g][k]; owner[k] = g; }
  }
  const namespaces = { common, genres: I.genres, wishes: I.wishes };

  const encoded = {};
  const stats = { bodies: 0, parts: 0, commands: 0, roles: {}, widths: {}, butt: 0 };
  for (const ns of Object.keys(namespaces)) {
    encoded[ns] = {};
    for (const name of Object.keys(namespaces[ns]).sort()) {
      let parts;
      try { parts = parseBody(namespaces[ns][name]); }
      catch (e) { throw new Error(ns + "." + name + ": " + e.message); }
      encoded[ns][name] = encodeBody(parts);
      stats.bodies++;
      for (const p of parts) {
        stats.parts++;
        stats.commands += p.cmds.length;
        stats.roles[p.role || "-"] = (stats.roles[p.role || "-"] || 0) + 1;
        if (p.width !== null) stats.widths[p.width] = (stats.widths[p.width] || 0) + 1;
        if (p.butt) stats.butt++;
      }
    }
  }

  const sheet = SHEET_ORDER.map((g) => ({ group: g, names: Object.keys(I[g]) }));
  const shadowed = [];
  for (const g of COMMON_ORDER) for (const k of Object.keys(I[g])) if (owner[k] !== g) shadowed.push(g + "." + k);

  const rules = I.pointWords.map((r) => {
    if (r[0].flags.replace("i", "")) throw new Error("флаги регулярки, кроме i: " + r[0].flags + " в " + r[0].source);
    return [jsToIcu(r[0].source), r[1], r[2]];
  });
  /* Слабый ярус: константа `WEAK` в icons.js не экспортируется. Достаём из
     текста — иначе она тихо разойдётся при правке. */
  const weakM = /var WEAK = (\d+);/.exec(src);
  if (!weakM) throw new Error("в icons.js нет `var WEAK = N;`");
  const weak = +weakM[1];

  let swift = "";
  swift += "// GENERATED — не править руками.\n";
  swift += "// Собрано `Tools/icons2assets.js` из `light_plan:Light_Plan/beta/icons.js`.\n";
  swift += "// Пересобрать: `node Tools/icons2assets.js` (или `make icons`).\n";
  swift += "//\n";
  swift += "// Знак — части: `роль ⇥ ширина ⇥ концы ⇥ команды`, части через перевод строки.\n";
  swift += "// Роль пуста у обычной части и `sun`/`cloud`/`rain` у частей погоды.\n";
  swift += "// Ширина пуста, если её задаёт вызывающий; иначе — в единицах холста 24×24.\n";
  swift += "// Концы `b` — плоские (`butt`), иначе круглые. Команды абсолютные: M L C Q Z.\n";
  swift += "//\n";
  swift += "// Источник: " + srcBytes + " байт, слепок в beta/index.html совпал побайтно.\n";
  swift += "// Затенено общим словарём (первый набор выигрывает, как `merge` в icons.js): "
    + (shadowed.length ? shadowed.join(", ") : "ничего") + ".\n";
  swift += "\nenum IconLibrary {\n";
  for (const ns of ["common", "genres", "wishes"]) {
    swift += "    static let " + ns + ": [String: String] = [\n";
    for (const name of Object.keys(encoded[ns])) {
      swift += "        " + swiftString(name) + ": " + swiftString(encoded[ns][name]) + ",\n";
    }
    swift += "    ]\n\n";
  }
  swift += "    /// Наборы в порядке контрольного листа. Имена — как в `icons.js`.\n";
  swift += "    static let sheet: [(group: String, names: [String])] = [\n";
  for (const s of sheet) swift += "        (" + swiftString(s.group) + ", [" + s.names.map(swiftString).join(", ") + "]),\n";
  swift += "    ]\n\n";
  swift += "    /// Ярус, с которого слово «слабое»: точку оно не решает, если есть студия.\n";
  swift += "    static let weakTier = " + weak + "\n\n";
  swift += "    /// Правила подбора знака точки по слову — `POINT_WORDS` из icons.js. Шаблон уже\n";
  swift += "    /// переписан под ICU (границы слов — явные, латинские); регистр не учитывается.\n";
  swift += "    static let pointWords: [(pattern: String, sign: String, tier: Int)] = [\n";
  for (const r of rules) swift += "        (" + swiftString(r[0]) + ", " + swiftString(r[1]) + ", " + r[2] + "),\n";
  swift += "    ]\n}\n";

  /* Строка корпуса: [название, место, студия 0/1, знак на экране, знак по словарю] */
  const answers = buildCorpus(I).map(([name, place, studio]) => [
    name, place, studio ? 1 : 0,
    I.pointSign(name, place, studio ? "studio" : undefined, false),
    I.pointSign(name, place, studio ? "studio" : undefined, true),
  ]);
  const points = {
    meta: {
      source: "beta/icons.js, ICONS.pointSign",
      what: "cases: [название, место, есть ссылка на студию, знак на экране, знак по словарю без оглядки на нарисованность]",
      count: answers.length,
      rules: I.pointWords.length,
    },
    cases: answers,
  };

  return { swift, points, stats, weak, shadowed, rules: rules.length };
}

function main() {
  const check = process.argv.includes("--check");
  const r = build();
  const files = [
    [OUT_SWIFT, r.swift],
    [OUT_POINTS, "{\n \"meta\": " + JSON.stringify(r.points.meta) + ",\n \"cases\": [\n"
      + r.points.cases.map((c) => JSON.stringify(c)).join(",\n") + "\n ]\n}\n"],
  ];
  if (check) {
    let bad = 0;
    for (const [file, text] of files) {
      const have = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : null;
      if (have !== text) { console.log("  РАЗОШЛОСЬ: " + path.relative(ROOT, file)); bad++; }
    }
    if (bad) { console.log("  знаки в Swift отстали от beta/icons.js — node Tools/icons2assets.js"); process.exit(1); }
    console.log("  знаки в Swift совпадают с beta/icons.js");
    return;
  }
  for (const [file, text] of files) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
  }
  console.log("знаков: " + r.stats.bodies + ", частей: " + r.stats.parts + ", команд пути: " + r.stats.commands);
  console.log("роли частей: " + JSON.stringify(r.stats.roles) + ", своя ширина: " + JSON.stringify(r.stats.widths)
    + ", плоские концы: " + r.stats.butt);
  console.log("правил слов: " + r.rules + ", слабый ярус: " + r.weak + ", корпус подбора: " + r.points.cases.length);
  console.log("затенено: " + (r.shadowed.join(", ") || "ничего"));
  for (const [file, text] of files) console.log("  " + path.relative(ROOT, file) + "  " + Buffer.byteLength(text) + " байт");
}

main();
