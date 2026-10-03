#!/usr/bin/env node
/* Замер кадров жеста «назад» от левого края (итерация 28з.5).

   На каждом экране со слоем запускает приложение со сценарием (как `Tools/shots/pair.js`), ждёт стенд без пальца
   (`-LPEdgeBackBench`, `App/EdgeBackMeter.swift`: два возврата и два закрытия на разных скоростях) и собирает
   из журнала (`-LPEdgeBackLog`) строки замера: кадры, пропущенные, p50 / p95 / max интервала, пересчёты `body`.

   Запуск (из корня натива, Debug-сборка уже собрана):
     node Tools/edge_back_bench.js --app <путь к .app>            # все экраны
     node Tools/edge_back_bench.js --app <.app> --only card,docs   # часть
     node Tools/edge_back_bench.js --skip-install --out <папка>    # приложение уже стоит
     node Tools/edge_back_bench.js --skip-install --live --only contacts   # без стенда: жест делает палец (журнал `meter` на каждый жест)
     --extra "-ключ значение …"                                     # свои аргументы запуска приложению
   Симулятор — свой у ветки (`Tools/sim.js`), другой — LP_SIM=<имя>. Выход: <папка>/<экран>.log, bench.json и
   таблица в stdout. Сценарии берут засев из `Fixtures/shots/seed_planner.json` и константы шага 10б / 27 из pair.js
   (вырезаются из его текста, не копируются: копия расходится молча). */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const sim = require('./sim');

const ROOT = path.resolve(__dirname, '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const BUNDLE = 'Novopashin.LightPlan';
const args = {};
process.argv.slice(2).forEach((a, i, all) => {
  if (a.startsWith('--')) args[a.slice(2)] = all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : '1';
});
const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-edgeback', sim.nameFor(ROOT).replace(/\W+/g, '-')));
fs.mkdirSync(OUT, { recursive: true });
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));

// Константы засева — из текста pair.js.
const pairSrc = fs.readFileSync(path.join(__dirname, 'shots', 'pair.js'), 'utf8');
const cut = (from, to) => {
  const a = pairSrc.indexOf(from), b = pairSrc.indexOf(to, a);
  if (a < 0 || b < 0) throw new Error('pair.js изменился: нет якорей ' + from + ' / ' + to);
  return pairSrc.slice(a, b);
};
const consts = new Function(cut('const R27_ROUTE', 'const cards =') + cut('const M28_WED_TAGS', '/* Экран →') +
  '; return { R27_ROUTE, R27_SHOTS, R27_BOARDS, M28_SHOTS, M28_BOARDS, M28_DOCS };')();
const plannerSeed = JSON.parse(fs.readFileSync(path.join(FX, 'seed_planner.json'), 'utf8'));
const wallAt = (iso, m) => new Date(Date.parse(iso) + 7 * 3600e3 + m * 60e3).toISOString().slice(0, 16);
const NOW = '2026-09-23T13:00';

const m28seed = s => ({ ...s, shots: consts.M28_SHOTS, boards: consts.M28_BOARDS,
  orgs: s.orgs.map(o => consts.M28_DOCS[o.id] ? { ...o, docs: consts.M28_DOCS[o.id] } : o) });
const card = (extra = []) => {
  const s = { ...plannerSeed };
  const id = 'sd_sep_wed';
  const at = s.sessions.findIndex(x => x.id === id);
  s.sessions = s.sessions.map((x, i) => i !== at ? x : { ...x, route: consts.R27_ROUTE, min: 480, dur: 840, end: 1320 });
  s.shots = consts.R27_SHOTS; s.boards = consts.R27_BOARDS;
  const rec = s.sessions[at];
  return { seed: s, now: wallAt(rec.date, 1080), args: ['-LPShotSheet', 'card', '-LPShotWay', id, ...extra] };
};
const m28 = (sheet, way) => ({ seed: m28seed(plannerSeed), now: NOW, args: ['-LPShotSheet', sheet, ...(way ? ['-LPShotWay', way] : [])] });
const plain = args_ => ({ seed: plannerSeed, now: NOW, args: args_ });

/* Экран → сценарий. Два слоя подряд: `card-refs` (референсы над карточкой), `docs-paper` (корень, раздел, бумага). */
const SCREENS = {
  card: () => card(),
  'card-refs': () => card(['-LPShotRefs', 'full']),
  gallery: () => m28('mbgallery'),
  shelf: () => m28('mbshelf', 'wedding'),
  folder: () => m28('mbfolder', 'bd_m28_wed'),
  docs: () => m28('docs'),
  'docs-section': () => m28('docs', 'recent'),
  'docs-paper': () => m28('docs', 'recent+paper'),
  orgs: () => m28('orgs'),
  orgcard: () => m28('orgcard', 'sd_org_agency'),
  contacts: () => m28('contacts'),
  form: () => plain(['-LPShotSheet', 'form', '-LPShotWay', 'wedding']),
  year: () => plain(['-LPShotSheet', 'year']),
  year12: () => plain(['-LPShotSheet', 'year12']),
  stats: () => plain(['-LPShotSheet', 'stats']),
  search: () => plain(['-LPShotSheet', 'search']),
};

function deviceApp() {
  const dev = sim.device(ROOT);
  if (!args['skip-install']) {
    if (!args.app) throw new Error('--app <путь к .app> или --skip-install');
    run('xcrun', ['simctl', 'install', dev.udid, path.resolve(args.app)]);
  }
  run('xcrun', ['simctl', 'status_bar', dev.udid, 'override', '--time', '9:41', '--batteryState', 'charged',
    '--batteryLevel', '100', '--cellularBars', '4', '--wifiBars', '3'], { stdio: 'ignore' });
  run('xcrun', ['simctl', 'ui', dev.udid, 'appearance', args.theme || 'light']);
  return dev;
}

function launch(dev, name, sc, extra) {
  const dir = path.join(OUT, name);
  fs.mkdirSync(dir, { recursive: true });
  const seedFile = path.join(dir, 'seed.json');
  fs.writeFileSync(seedFile, JSON.stringify({ ...sc.seed, theme: args.theme || 'light', pro: false, drumSlot: 'paper', ribbonMode: 'drum' }));
  const log = path.join(OUT, name + '.log');
  fs.rmSync(log, { force: true });
  try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
  const launched = run('xcrun', ['simctl', 'launch', dev.udid, BUNDLE,
    '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
    '-LPShotNow', sc.now + ':00+07:00', '-LPShotZone', 'Asia/Barnaul',
    '-LPShotSeed', seedFile, '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'),
    '-LPShotAir', path.join(FX, 'air_barnaul.json'), '-LPShotName', path.join(FX, 'place_barnaul.json'),
    '-LPShotScreen', args.tab || 'planner', '-LPShotScope', 'month', ...sc.args,
    '-LPEdgeBackLog', log, ...(args.live ? [] : ['-LPEdgeBackBench', '1']), ...extra, ...(args.extra ? args.extra.split(' ') : [])],
  { env: { ...process.env, SIMCTL_CHILD_TZ: 'Asia/Barnaul' } });
  return { log, dir, pid: (launched.match(/: (\d+)/) || [])[1] };
}

async function scenario(dev, name, sc) {
  const { log, pid } = launch(dev, name, sc, ['-LPEdgeBackReps', args.reps || '3']);
  let sampled = !args.sample;
  for (let i = 0; i < 400; i++) {
    const t = fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : '';
    // Профиль главного потока на время одного прогона стенда (`--sample slow-return`): macOS `sample` читает процесс симулятора.
    if (!sampled && pid && t.includes('bench ' + args.sample + ' to=')) {
      sampled = true;
      run('sample', [pid, args['sample-seconds'] || '1', '1', '-file', path.join(OUT, name + '.sample.txt')], { stdio: 'ignore' });
    }
    if (/bench done/.test(t)) break;
    await sleep(250);
  }
  const text = fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : '';
  const rows = parse(text);
  validate(name, text, rows, +(args.reps || 3));
  return rows;
}

/* Пустой или неполный прогон — ошибка, а не «нет данных»: иначе его легко принять за проверенный (ревью GPT к 2175133). */
function validate(name, text, rows, reps) {
  if (!/bench done/.test(text)) throw new Error(name + ': стенд не дошёл до конца (в журнале нет «bench done»)');
  const done = rows.filter(r => !r.skipped && r.dragDts);
  if (!done.length) throw new Error(name + ': в журнале нет ни одной строки meter');
  const n = run_ => done.filter(r => r.run === run_).length;
  if (n('slow-return') !== reps) throw new Error(`${name}: медленных возвратов ${n('slow-return')} из ${reps}`);
  for (const must of ['fast-return', 'cancel-mid', 'slow-close']) if (n(must) < 1) throw new Error(`${name}: не было прогона ${must} (слой не взял жест?)`);
}


/* ——— Тень слоя: кадр в покое против первого кадра жеста (`--shade`) ———
   Первый кадр жеста — `begin` без движения, сдвиг 0 (`--hold <pt>` задаёт другой: тогда сдвинут весь слой, и сравнение
   с покоем перестаёт быть чистым — ревью GPT к 2175133). Всё, что отличается от покоя вне полосы у левой кромки, — лишнее
   (тень под плашками и кнопками, когда `.shadow` лежал на содержимом слоя). Попиксельно, без допуска. */
const zlib = require('zlib');
function readPng(file) {
  const b = fs.readFileSync(file);
  let o = 8, ihdr = null; const idat = [];
  while (o < b.length) {
    const len = b.readUInt32BE(o), type = b.toString('latin1', o + 4, o + 8), body = b.subarray(o + 8, o + 8 + len);
    if (type === 'IHDR') ihdr = { w: body.readUInt32BE(0), h: body.readUInt32BE(4), depth: body[8], color: body[9], interlace: body[12] };
    if (type === 'IDAT') idat.push(body);
    o += 12 + len;
  }
  if (!ihdr || ihdr.depth !== 8 || ![2, 6].includes(ihdr.color) || ihdr.interlace) throw new Error('PNG не 8 бит RGB/RGBA: ' + file);
  const ch = ihdr.color === 6 ? 4 : 3, stride = ihdr.w * ch;
  const raw = zlib.inflateSync(Buffer.concat(idat)), out = Buffer.alloc(ihdr.h * stride);
  for (let y = 0; y < ihdr.h; y++) {
    const f = raw[y * (stride + 1)], src = y * (stride + 1) + 1, dst = y * stride;
    for (let x = 0; x < stride; x++) {
      const a = x >= ch ? out[dst + x - ch] : 0, up = y ? out[dst - stride + x] : 0, c = x >= ch && y ? out[dst - stride + x - ch] : 0;
      const v = raw[src + x];
      out[dst + x] = f === 0 ? v : f === 1 ? v + a : f === 2 ? v + up : f === 3 ? v + ((a + up) >> 1)
        : v + (() => { const p = a + up - c, pa = Math.abs(p - a), pb = Math.abs(p - up), pc = Math.abs(p - c); return pa <= pb && pa <= pc ? a : pb <= pc ? up : c; })();
    }
  }
  return { w: ihdr.w, h: ihdr.h, ch, px: out };
}
function writePng(file, w, h, rgb) {
  const crcT = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
  const crc = buf => { let c = 0xffffffff; for (const x of buf) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 2;
  const raw = Buffer.alloc(h * (w * 3 + 1));
  for (let y = 0; y < h; y++) rgb.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3);
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
}
/* Сравнение двух кадров: сколько пикселей отличается, сколько из них правее полосы у кромки (`edgePx`), наибольшая разница
   по каналу, строки и столбцы, где она есть; картинка разницы (красное — отличается) для глаз. */
function diffPng(a, b, edgePx, outFile) {
  if (a.w !== b.w || a.h !== b.h) throw new Error('кадры разного размера');
  let changed = 0, outside = 0, max = 0, minY = Infinity, maxY = -1, minX = Infinity, maxX = -1;
  const vis = Buffer.alloc(a.w * a.h * 3, 255);
  for (let y = 0; y < a.h; y++) for (let x = 0; x < a.w; x++) {
    let d = 0;
    for (let c = 0; c < 3; c++) d = Math.max(d, Math.abs(a.px[(y * a.w + x) * a.ch + c] - b.px[(y * b.w + x) * b.ch + c]));
    if (!d) continue;
    changed++; max = Math.max(max, d);
    if (x < edgePx) { vis.fill(0, (y * a.w + x) * 3, (y * a.w + x) * 3 + 3); vis[(y * a.w + x) * 3] = 200; continue; }
    outside++; minY = Math.min(minY, y); maxY = Math.max(maxY, y); minX = Math.min(minX, x); maxX = Math.max(maxX, x);
    vis[(y * a.w + x) * 3] = 255; vis[(y * a.w + x) * 3 + 1] = 0; vis[(y * a.w + x) * 3 + 2] = 0;
  }
  if (outFile) writePng(outFile, a.w, a.h, vis);
  return { changed, outside, max, rows: outside ? [minY, maxY] : null, cols: outside ? [minX, maxX] : null };
}
async function shadeScenario(dev, name, sc) {
  const { log, dir } = launch(dev, name, sc, ['-LPEdgeBackHold', args.hold || '0']);
  const shot = f => run('xcrun', ['simctl', 'io', dev.udid, 'screenshot', '--type=png', path.join(dir, f)], { stdio: 'ignore' });
  const done = new Set();
  for (let i = 0; i < 400; i++) {
    const t = fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : '';
    if (!done.has('rest') && t.includes('hold rest')) { done.add('rest'); shot('rest.png'); await sleep(500); shot('rest2.png'); }
    if (!done.has('gesture') && /hold gesture dx=/.test(t)) { done.add('gesture'); shot('gesture.png'); }
    if (/hold done|hold refused/.test(t)) break;
    await sleep(100);
  }
  if (!done.has('gesture')) return { error: 'нет кадра жеста (слой не взял жест?)' };
  const rest = readPng(path.join(dir, 'rest.png')), rest2 = readPng(path.join(dir, 'rest2.png')), g = readPng(path.join(dir, 'gesture.png'));
  const scale = rest.w / 440, edgePx = Math.ceil(2 * scale);   // полоса у левой кромки: 2 pt — сдвиг слоя на первом кадре и сглаживание
  return { scale, noise: diffPng(rest, rest2, edgePx), shade: diffPng(rest, g, edgePx, path.join(dir, 'diff.png')) };
}

/* Журнал → строки: `bench <прогон>` открывает прогон, `meter …` закрывает его числами. */
function parse(text) {
  const rows = [];
  let cur = null;
  for (const l of text.split('\n')) {
    let m = l.match(/^bench (\S+) to=/);
    if (m) { cur = { run: m[1] }; continue; }
    m = l.match(/^bench (\S+) skipped/);
    if (m) { rows.push({ run: m[1], skipped: true }); cur = null; continue; }
    if (cur && /^begin /.test(l)) cur.begin = l;
    if (cur && /^end /.test(l)) cur.end = l;
    if (cur && /^closed /.test(l)) cur.closed = l;
    m = l.match(/^meter period=([\d.]+)ms moves=(\d+) \| drag (.*?) \| settle (.*?) \| cpu drag .*? \| bodies (.*?) \| raw drag=(\S*) settle=(\S*) cpudrag=(\S*) cpusettle=(\S*)$/);
    if (cur && m) {
      const num = s => Object.fromEntries([...s.matchAll(/(\w+)=([\d.]+)/g)].map(x => [x[1], +x[2]]));
      const list = s => s ? s.split(',').map(Number) : [];
      cur.period = +m[1]; cur.moves = +m[2]; cur.drag = num(m[3]); cur.settle = num(m[4]);
      cur.bodies = m[5] === '-' ? {} : Object.fromEntries(m[5].split(' ').map(x => x.split('=')).map(([k, v]) => [k, +v]));
      cur.dragDts = list(m[6]); cur.settleDts = list(m[7]); cur.dragCpu = list(m[8]); cur.settleCpu = list(m[9]);
      rows.push(cur); cur = null;
    }
  }
  return rows;
}

/* Итог по экрану: все кадры жестов (палец и доезд) вместе. Пропущенный кадр — интервал, округлённый до k периодов, минус один. */
function summarize(rows, { fresh = true } = {}) {
  const gs = rows.filter(r => !r.skipped && r.dragDts && (fresh || r.run !== 'fresh-return'));
  if (!gs.length) return null;
  const period = gs[0].period;
  const all = gs.flatMap(r => [...r.dragDts, ...r.settleDts]);
  const q = (a, p) => { const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(s.length * p))]; };
  const missed = a => a.reduce((n, v) => n + Math.max(0, Math.round(v / period) - 1), 0);
  const drag = gs.flatMap(r => r.dragDts);
  const cpu = gs.flatMap(r => [...r.dragCpu, ...r.settleCpu]);
  const bodies = {};
  for (const r of gs) for (const [k, v] of Object.entries(r.bodies)) bodies[k] = (bodies[k] || 0) + v;
  for (const k of Object.keys(bodies)) bodies[k] = Math.round(bodies[k] / gs.length);
  return { gestures: gs.length, period, frames: all.length, missed: missed(all), p50: q(all, 0.5), p95: q(all, 0.95), p99: q(all, 0.99), max: Math.max(...all),
    dragFrames: drag.length, dragMissed: missed(drag), dragP95: q(drag, 0.95), bodies,
    cpuP50: q(cpu, 0.5), cpuP95: q(cpu, 0.95), cpuMax: Math.max(...cpu),
    cpuOver8: cpu.filter(v => v > 8.33).length, cpuOver16: cpu.filter(v => v > 16.7).length, cpuN: cpu.length };
}

/* По видам прогонов: все экраны вместе (возвраты, обрыв жеста, жест на только что открытом слое). */
function byRun(all) {
  const groups = {};
  for (const rows of Object.values(all)) for (const r of rows) if (!r.skipped && r.dragDts) (groups[r.run] = groups[r.run] || []).push(r);
  const pad = (s, n) => String(s).padEnd(n);
  const lines = ['\n' + pad('прогон', 14) + pad('жестов', 8) + pad('кадров', 8) + pad('проп.', 7) + pad('p95', 7) + pad('max', 8) + pad('cpu p50', 8) + pad('cpu p95', 8) + 'cpu max'];
  for (const [name, rs] of Object.entries(groups)) {
    const t = summarize(rs);
    lines.push(pad(name, 14) + pad(t.gestures, 8) + pad(t.frames, 8) + pad(t.missed, 7) + pad(t.p95.toFixed(1), 7) + pad(t.max.toFixed(1), 8) + pad(t.cpuP50.toFixed(1), 8) + pad(t.cpuP95.toFixed(1), 8) + t.cpuMax.toFixed(1));
  }
  return lines.join('\n');
}

function table(all) {
  const pad = (s, n) => String(s).padEnd(n);
  const lines = [pad('экран', 14) + pad('жестов', 8) + pad('кадров', 8) + pad('проп.', 7) + pad('p50', 7) + pad('p95', 7) + pad('p99', 7) + pad('max', 8) + pad('cpu p50', 8) + pad('cpu p95', 8) + pad('cpu max', 8) + pad('>8,3', 6) + pad('>16,7', 7) + 'пересчётов body на жест (среднее)'];
  for (const [name, rows] of Object.entries(all)) {
    // Жест на только что открытом слое (`fresh-return`) считается отдельно: первые 0,5 с идёт въезд слоя, его цена не жеста.
    const t = summarize(rows, { fresh: false });
    if (!t) { lines.push(pad(name, 14) + 'нет данных (журнал пуст)'); continue; }
    const b = Object.entries(t.bodies).map(([k, v]) => k + '=' + v).join(' ');
    lines.push(pad(name, 14) + pad(t.gestures, 8) + pad(t.frames, 8) + pad(t.missed, 7) + pad(t.p50.toFixed(1), 7) + pad(t.p95.toFixed(1), 7) + pad(t.p99.toFixed(1), 7) + pad(t.max.toFixed(1), 8) + pad(t.cpuP50.toFixed(1), 8) + pad(t.cpuP95.toFixed(1), 8) + pad(t.cpuMax.toFixed(1), 8) + pad(t.cpuOver8, 6) + pad(t.cpuOver16, 7) + b);
  }
  return lines.join('\n');
}

module.exports = { parse, validate, summarize };
if (require.main === module) (async () => {
  // Таблицы из сохранённого bench.json, без симулятора: `--table <файл>`.
  if (args.table) {
    const all = JSON.parse(fs.readFileSync(args.table, 'utf8'));
    console.log(table(all)); console.log(byRun(all));
    return;
  }
  const dev = deviceApp();
  // Живой палец: сценарий запущен с журналом, без стенда; жест делает человек или `simctl`/`control swipe`.
  if (args.live) {
    const name = args.only || 'contacts';
    const { log } = launch(dev, name, SCREENS[name](), []);
    console.log('запущено: ' + name + ', журнал жестов: ' + log);
    return;
  }
  if (args.shade) {
    const only = args.only ? args.only.split(',') : ['card', 'contacts', 'docs', 'orgcard'];
    const res = {};
    for (const name of only) { res[name] = await shadeScenario(dev, name, SCREENS[name]()); console.error('готово: ' + name); }
    fs.writeFileSync(path.join(OUT, 'shade.json'), JSON.stringify(res, null, 1));
    console.log('экран         шум покоя (px)  жест: отличается всего  вне полосы у кромки  max по каналу  строки          столбцы');
    for (const [n, r] of Object.entries(res)) {
      if (r.error) { console.log(n.padEnd(14) + r.error); continue; }
      console.log(n.padEnd(14) + String(r.noise.changed).padEnd(16) + String(r.shade.changed).padEnd(24) + String(r.shade.outside).padEnd(21) +
        String(r.shade.max).padEnd(15) + (r.shade.rows ? r.shade.rows.join('–') : '—').padEnd(16) + (r.shade.cols ? r.shade.cols.join('–') : '—'));
    }
    const bad = Object.entries(res).filter(([, r]) => r.error || r.noise.changed > 0 || r.shade.outside > 0).map(([n]) => n);
    if (bad.length) { console.log('\nНЕ ЧИСТО: ' + bad.join(', ') + ' (ошибка, шум покоя или тень вне полосы у кромки)'); process.exitCode = 1; }
    console.log('\nтема: ' + (args.theme || 'light') + ', масштаб ×' + Object.values(res).find(r => r.scale).scale + '; снимки и diff.png — в ' + OUT);
    return;
  }
  const only = args.only ? args.only.split(',') : Object.keys(SCREENS);
  const all = {};
  for (const name of only) {
    if (!SCREENS[name]) throw new Error('нет сценария ' + name + '; есть: ' + Object.keys(SCREENS).join(' '));
    all[name] = await scenario(dev, name, SCREENS[name]());
    console.error('готово: ' + name);
  }
  fs.writeFileSync(path.join(OUT, 'bench.json'), JSON.stringify(all, null, 1));
  console.log(table(all));
  console.log(byRun(all));
  console.log('\nжурналы и bench.json: ' + OUT);
})().catch(e => { console.error(e.message); process.exit(1); });
