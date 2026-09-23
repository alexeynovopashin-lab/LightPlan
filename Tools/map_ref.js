/* Эталон снимка сцены прибора карты (итерация 20а): разметка `#mapLight`,
   которую рисует живая бета (`renderMap`) через `tools/shot.js --svg`, снятая
   в числа. Swift-тест строит сцену на тех же входах и сверяет элемент за
   элементом — порядок, координаты, цвет, подписи
   (Packages/LightPlanUI/Tests/LightPlanUITests/MapSceneParityTests.swift).

   Входы — те же, что у пар снимков (Tools/shots/pair.js): Барнаул,
   23 сентября 2026, четыре момента; «Просто» — солнце и луна, «Астро» — плюс
   Млечный Путь; обе темы. Чипа нет: он живёт от пальца, в разметке покоя его
   не бывает.

   Playwright и сам прибор берутся из соседней папки веба; сеть у веба
   закрыта, холста карты в разметке нет — только прибор.

     node Tools/map_ref.js          снять эталон
     node Tools/map_ref.js --check  доказать, что повторный прогон даёт то же */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const WEB = process.env.LIGHT_PLAN_WEB || path.resolve(ROOT, '..', 'Light_Plan');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const OUT = path.join(ROOT, 'Packages', 'LightPlanUI', 'Tests', 'LightPlanUITests', 'map_scene_ref.json');
const ZONE = 'Asia/Barnaul';
// Те же моменты, что `MOMENTS` в Tools/shots/pair.js.
const MOMENTS = { day: '2026-09-23T13:00', golden: '2026-09-23T18:50', night: '2026-09-23T23:00',
  dawn: '2026-09-23T06:05' };

/* Цвет как у Swift `RGBA`: 0…255 и прозрачность; `*-opacity` уже умножен. */
function color(a, key) {
  const v = a[key];
  if (v == null || v === 'none') return null;
  let c;
  let m;
  if ((m = /^#([0-9a-f]{6})$/i.exec(v))) {
    const n = parseInt(m[1], 16);
    c = [(n >> 16) & 255, (n >> 8) & 255, n & 255, 1];
  } else if ((m = /^rgba?\(([^)]*)\)$/.exec(v))) {
    const p = m[1].split(',').map(Number);
    c = [p[0], p[1], p[2], p.length > 3 ? p[3] : 1];
  } else throw new Error('цвет не разобран: ' + v);
  if (a[key + '-opacity'] != null) c[3] *= +a[key + '-opacity'];
  return c;
}
const num = (a, k, d = 0) => (a[k] == null ? d : +a[k]);
const dash = a => (a['stroke-dasharray'] ? a['stroke-dasharray'].split(/[ ,]+/).map(Number) : []);

/* Путь: «M x y L x y …» (или с запятыми) — прогоны точек; «M x yh.01» подряд —
   облако точек, у веба так рисуется точка круглым концом. */
function runs(d) {
  const out = [];
  for (const part of d.split('M').slice(1)) {
    const pts = [];
    const re = /(-?[\d.]+)[ ,](-?[\d.]+)/g;
    let m;
    while ((m = re.exec(part))) pts.push([+m[1], +m[2]]);
    out.push(pts);
  }
  return out;
}

function parse(svg) {
  const list = [];
  const re = /<(circle|line|path|text)\b([^>]*)>([^<]*)/g;
  let m;
  while ((m = re.exec(svg))) {
    const a = {};
    m[2].replace(/([\w-]+)="([^"]*)"/g, (_, k, v) => { a[k] = v; });
    const tag = m[1];
    if (tag === 'circle') {
      if (/^url\(/.test(a.fill || '')) { list.push({ k: 'scrim', x: +a.cx, y: +a.cy, r: +a.r }); continue; }
      // Мишень тапа по светилу: у натива это кнопка поверх `Canvas`, не примитив.
      if (a.fill === 'transparent') { list.push({ k: 'hit', x: +a.cx, y: +a.cy, r: +a.r }); continue; }
      list.push({ k: 'circle', x: +a.cx, y: +a.cy, r: +a.r, fill: color(a, 'fill'), stroke: color(a, 'stroke'),
        w: num(a, 'stroke-width'), dash: dash(a) });
    } else if (tag === 'line') {
      list.push({ k: 'line', x1: +a.x1, y1: +a.y1, x2: +a.x2, y2: +a.y2, stroke: color(a, 'stroke'),
        w: num(a, 'stroke-width', 1), dash: dash(a), round: a['stroke-linecap'] === 'round' });
    } else if (tag === 'path') {
      if (/h\.01/.test(a.d)) {
        list.push({ k: 'dots', pts: runs(a.d).map(r => r[0]), color: color(a, 'stroke'), w: num(a, 'stroke-width') });
      } else {
        list.push({ k: 'path', runs: runs(a.d), stroke: color(a, 'stroke'), w: num(a, 'stroke-width', 1),
          dash: dash(a) });
      }
    } else {
      list.push({ k: 'text', text: m[3], x: +a.x, y: +a.y, size: num(a, 'font-size'),
        weight: num(a, 'font-weight', 400), mono: /monospace/.test(a['font-family'] || ''),
        color: color(a, 'fill'), anchor: a['text-anchor'] || 'start',
        tracking: parseFloat(a['letter-spacing'] || '0'), middle: a['dominant-baseline'] === 'middle' });
    }
  }
  return list;
}

function snap() {
  const seed = JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8'));
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'lp-mapref-'));
  const cases = [];
  for (const mode of ['simple', 'astro']) for (const theme of ['dark', 'light']) for (const moment of Object.keys(MOMENTS)) {
    const name = [mode, theme, moment].join('-');
    // Настройки — как у пары снимков карты (pair.js, экран map).
    const s = { ...seed, theme, pro: mode === 'astro', mapFold: true,
      mapLayers: { sun: true, moon: true, mw: mode === 'astro', compass: true, spots: true } };
    const seedFile = path.join(tmp, name + '.seed.json');
    const svgFile = path.join(tmp, name + '.svg');
    fs.writeFileSync(seedFile, JSON.stringify(s));
    execFileSync('node', [path.join(WEB, 'tools', 'shot.js'), '--screen', 'map', '--at', MOMENTS[moment], '--tz', ZONE,
      '--seed', seedFile, '--forecast', path.join(FX, 'forecast_barnaul.json'), '--air', path.join(FX, 'air_barnaul.json'),
      '--name', path.join(FX, 'place_barnaul.json'), '--scale', '1', '--out', path.join(tmp, name + '.png'),
      '--svg', svgFile], { cwd: WEB, stdio: 'ignore' });
    if (!fs.existsSync(svgFile)) throw new Error('веб не отдал разметку карты: ' + name);
    const [date, hm] = MOMENTS[moment].split('T');
    const [h, mi] = hm.split(':').map(Number);
    cases.push({ name, date, minute: h * 60 + mi, pro: mode === 'astro', light: theme === 'light',
      layers: s.mapLayers, elements: parse(fs.readFileSync(svgFile, 'utf8')) });
  }
  fs.rmSync(tmp, { recursive: true, force: true });
  return { place: { lat: seed.me.cityLat, lon: seed.me.cityLon, zone: ZONE }, cases };
}

// Четыре знака после точки: допуск теста 0,01, полная точность double ему
// не нужна (файл 392 → 359 КБ; основной вес — облако и пути, у веба они уже
// с одним знаком).
const text = JSON.stringify(snap(), (k, v) => (typeof v === 'number' ? Math.round(v * 1e4) / 1e4 : v)) + '\n';
if (process.argv.includes('--check')) {
  const same = fs.existsSync(OUT) && fs.readFileSync(OUT, 'utf8') === text;
  console.log((same ? '  ок  ' : '  РАЗНЫЕ  ') + path.relative(ROOT, OUT));
  process.exit(same ? 0 : 1);
}
fs.writeFileSync(OUT, text);
const data = JSON.parse(text);
console.log(path.relative(ROOT, OUT) + ': ' + data.cases.map(c => c.name + ' ' + c.elements.length).join(', '));
