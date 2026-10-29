#!/usr/bin/env node
/* Стенд закреплённой шапки ленты года (30.1б): кадры шапки при прокрутке, цепочке видов и «сегодня».
   Сборка Debug ставится на симулятор ветки, приложение само ведёт ленту (`-LPPinScript scroll|today|chain`, `PlannerYearPinBench.swift`),
   пишет журнал рамок шапки (`-LPPinLog`), `simctl io recordVideo` пишет кадры, `Tools/motion/frames.swift` режет область шапки.

     node Tools/pin_bench.js --app <.app> [--scenario scroll,today,chain] [--theme dark|light] [--out <папка>]

   Числа: по журналу — рамки шапки / названия / линейки в каждом кадре раскладки, самый большой скачок от кадра к кадру по y;
   по видео — сколько кадров шапка отличается от обоих устойчивых состояний (двойная отрисовка / наложение) и самый большой
   скачок пикселей между соседними кадрами в полосе линейки (она не должна меняться совсем). */
const fs = require('fs'), path = require('path'), os = require('os');
const { execFileSync, spawn } = require('child_process');
const sim = require('./sim');
const M = require('./motion/measure');
const ROOT = path.resolve(__dirname, '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = {};
for (let i = 2; i < process.argv.length; i++) { const a = process.argv[i]; if (a.startsWith('--')) { const nx = process.argv[i + 1]; if (nx && !nx.startsWith('--')) { args[a.slice(2)] = nx; i++; } else args[a.slice(2)] = true; } }
const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-pin-bench'));
fs.mkdirSync(OUT, { recursive: true });
const run = (c, a, o = {}) => execFileSync(c, a, { encoding: 'utf8', ...o });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const THEME = args.theme || 'dark';
const BUNDLE = 'Novopashin.LightPlan';
const APP = args.app;
if (!APP) { console.error('--app <.app>'); process.exit(2); }

function parseLog(text) {
  const rows = [];
  for (const l of text.split('\n')) {
    const m = /^\s*(\d+) (.*)$/.exec(l); if (!m) continue;
    const t = +m[1], rest = m[2];
    let g = /^geo (\S+) ([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)$/.exec(rest);
    if (g) { rows.push({ t, kind: 'geo', key: g[1], x: +g[2], y: +g[3], w: +g[4], h: +g[5] }); continue; }
    g = /^scroll=([-\d.]+) pinned=(\S+)/.exec(rest);
    if (g) { rows.push({ t, kind: 'scroll', s: +g[1], pinned: g[2] }); continue; }
    rows.push({ t, kind: 'mark', text: rest });
  }
  return rows;
}

function crop(video, bin, r) {
  const tool = path.join(OUT, 'frames');
  if (!fs.existsSync(tool)) run('xcrun', ['swiftc', '-O', path.join(__dirname, 'motion', 'frames.swift'), '-o', tool]);
  run(tool, [video, bin, ...r.map(v => String(Math.round(v)))]);
  return M.readFrames(bin);
}
const mad = (a, b) => { let s = 0; for (let i = 0; i < a.length; i++) s += Math.abs(a[i] - b[i]); return s / a.length; };
const maxd = (a, b) => { let m = 0; for (let i = 0; i < a.length; i++) m = Math.max(m, Math.abs(a[i] - b[i])); return m; };

async function scenario(dev, name) {
  const dir = path.join(OUT, name + '-' + THEME); fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true });
  const seed = JSON.parse(fs.readFileSync(path.join(FX, 'seed_planner.json'), 'utf8'));
  const seedFile = path.join(dir, 'seed.json');
  fs.writeFileSync(seedFile, JSON.stringify({ ...seed, theme: THEME, pro: false, drumSlot: 'paper', ribbonMode: 'drum' }));
  const log = path.join(dir, 'pin.log'), video = path.join(dir, 'video.mp4'), report = path.join(dir, 'native.json');
  try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore' }); } catch (e) {}
  run('xcrun', ['simctl', 'ui', dev.udid, 'appearance', THEME]);
  const rec = spawn('xcrun', ['simctl', 'io', dev.udid, 'recordVideo', '--codec=h264', '--force', video], { stdio: 'ignore' });
  await sleep(2500);
  const open = name === 'chain' ? [] : name === 'zoom' ? ['-LPShotSheet', 'year12'] : ['-LPShotSheet', 'year'];
  run('xcrun', ['simctl', 'launch', dev.udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
    '-LPShotNow', '2026-10-29T13:00:00+07:00', '-LPShotZone', 'Asia/Barnaul', '-LPShotSeed', seedFile,
    '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
    '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'planner', '-LPShotScope', 'month', ...open,
    '-LPShotReport', report, '-LPShotReportDelay', '3', '-LPPinLog', log, '-LPPinScript', name],
  { env: { ...process.env, SIMCTL_CHILD_TZ: 'Asia/Barnaul' } });
  for (let i = 0; i < 200 && !(fs.existsSync(log) && /script \w+ done/.test(fs.readFileSync(log, 'utf8'))); i++) await sleep(250);
  await sleep(800);
  rec.kill('SIGINT'); await new Promise(r => rec.on('exit', r));
  return { dir, log: parseLog(fs.readFileSync(log, 'utf8')), video };
}

function headRect(rows) { const h = rows.filter(r => r.kind === 'geo' && r.key === 'head').pop(); return h; }
function report(name, r) {
  const L = []; let rows = r.log;
  const mark = t => rows.find(x => x.kind === 'mark' && x.text.startsWith(t));
  const t0 = (mark('script scroll down') || mark('script today') || { t: 0 }).t;
  const t1 = (mark('script scroll done') || mark('script today done') || { t: 1e12 }).t;
  const win = name === 'chain' ? rows : rows.filter(x => x.t >= t0 && x.t <= t1);
  const jumpOf = key => {
    const g = win.filter(x => x.kind === 'geo' && x.key === key);
    let m = 0;
    for (let i = 1; i < g.length; i++) m = Math.max(m, Math.abs(g[i].y - g[i - 1].y));
    return { n: g.length, max: m, ys: [...new Set(g.map(x => x.y.toFixed(1)))].slice(0, 12) };
  };
  if (name === 'scroll' || name === 'today') {
    for (const k of ['head', 'month', 'ruler']) { const j = jumpOf(k); L.push(`${k}: рамок за сценарий ${j.n}, значения y: ${j.ys.join(' / ') || '(не менялась)'}, самый большой скачок y между кадрами ${j.max.toFixed(1)} pt`); }
    const sc = win.filter(x => x.kind === 'scroll');
    const ch = []; let prev = null;
    for (const x of sc) { if (x.pinned !== prev) { ch.push(`${x.pinned}@${x.s.toFixed(0)}`); prev = x.pinned; } }
    let md = 0, big = 0; for (let i = 1; i < sc.length; i++) { const d = Math.abs(sc[i].s - sc[i - 1].s); md = Math.max(md, d); }
    L.push(`кадров прокрутки ${sc.length}; смена названия: ${ch.join(' → ')}; самый большой шаг прокрутки между кадрами ${md.toFixed(1)} pt`);
  } else if (name === 'zoom') {
    const t0 = rows.find(x => x.kind === 'mark' && /zoom start/.test(x.text)).t;
    const g = rows.filter(x => x.kind === 'geo' && x.key === 'head' && x.t >= t0);
    L.push(`рамка шапки ленты по кадрам зума (x, y, ширина, высота): ` + g.map(x => `${x.x.toFixed(0)},${x.y.toFixed(0)},${x.w.toFixed(0)},${x.h.toFixed(0)}`).join(' | '));
    let m = 0; for (let i = 1; i < g.length; i++) m = Math.max(m, Math.abs(g[i].y - g[i - 1].y));
    L.push(`кадров ${g.length}, самый большой скачок y шапки между кадрами ${m.toFixed(1)} pt`);
    for (const k of ['month', 'ruler']) { const a = rows.filter(x => x.kind === 'geo' && x.key === k && x.t >= t0); L.push(`${k}: y по кадрам ${a.map(x => x.y.toFixed(0)).join(' ')}`); }
    const sc = rows.filter(x => x.kind === 'scroll' && x.t >= t0); L.push(`прокрутка/название: ${sc.map(x => x.pinned + '@' + x.s.toFixed(0)).join(' ')}`);
  } else {
    for (const m of rows.filter(x => x.kind === 'mark') .filter(x => name === 'chain' || true)) L.push(`метка ${m.t} мс: ${m.text}`);
    const g = rows.filter(x => x.kind === 'geo' && x.key === 'head');
    const lastOpen = rows.filter(x => x.kind === 'mark' && /year open/.test(x.text));
    L.push(`рамок шапки ленты ${g.length}; y по кадрам: ${g.map(x => x.y.toFixed(0)).join(' ')}`);
    for (const k of ['month', 'ruler']) {
      const a = rows.filter(x => x.kind === 'geo' && x.key === k);
      const off = a.map(x => { const hh = g.filter(y => y.t <= x.t + 5).pop(); return hh ? x.y - hh.y : null; }).filter(v => v != null);
      L.push(`${k}: смещение от верха шапки ${[...new Set(off.map(v => v.toFixed(1)))].join(' / ')} pt (одно число = едут вместе)`);
    }
    const sc = rows.filter(x => x.kind === 'scroll'); const ch = []; let prev = null;
    for (const x of sc) { if (x.pinned !== prev) { ch.push(`${x.pinned}@${x.s.toFixed(0)}`); prev = x.pinned; } }
    L.push(`название шапки по ходу: ${ch.join(' → ')}`);
  }
  const hd = headRect(rows);
  if (name === 'scroll' && hd && fs.existsSync(r.video)) {
    const ru = rows.filter(x => x.kind === 'geo' && x.key === 'ruler').pop(), mo = rows.filter(x => x.kind === 'geo' && x.key === 'month').pop();
    const band = (k, y, h) => crop(r.video, path.join(r.dir, k + '.bin'), [0, y, 440, h]);
    const bf = band('body', 300, 500), rf = band('ruler', ru.y, ru.h), mf = band('month', mo.y, mo.h);
    // окно сценария в видео: самый длинный кластер кадров, где лента движется
    const mv = []; for (let i = 1; i < bf.n; i++) mv.push(mad(bf.data[i], bf.data[i - 1]) > 0.3);
    let best = [0, 0], cur = null;
    for (let i = 0; i < mv.length; i++) { if (mv[i]) { if (!cur) cur = [i + 1, i + 1]; cur[1] = i + 1; } else if (cur && i - cur[1] > 60) { if (cur[1] - cur[0] > best[1] - best[0]) best = cur; cur = null; } }
    if (cur && cur[1] - cur[0] > best[1] - best[0]) best = cur;
    const [i0, i1] = best;
    let rmax = 0, mmax = 0;
    for (let i = i0 + 1; i <= i1; i++) { rmax = Math.max(rmax, mad(rf.data[i], rf.data[i - 1])); mmax = Math.max(mmax, mad(mf.data[i], mf.data[i - 1])); }
    const groups = [];
    for (let i = i0; i <= i1; i++) { const d = mf.data[i]; const g = groups.find(g => mad(g.ref, d) < 0.4); if (g) g.n++; else groups.push({ ref: d, n: 1, first: i }); }
    groups.sort((a, b) => b.n - a.n);
    const odd = groups.slice(2).reduce((s, g) => s + g.n, 0);
    const trans = []; for (let i = i0 + 1; i <= i1; i++) if (mad(mf.data[i], mf.data[i - 1]) > 0.4) trans.push(i - i0);
    L.push(`видео: лента двигалась в кадрах ${i0}…${i1} (${i1 - i0 + 1} кадров, ${(rf.ts[i1] - rf.ts[i0]).toFixed(1)} с)`);
    L.push(`видео: полоса линейки ${ru.h.toFixed(0)} pt — самое большое различие соседних кадров ${rmax.toFixed(3)}/255 (0 = не шелохнулась)`);
    L.push(`видео: полоса названия — видов ${groups.length} (кадров по видам ${groups.map(g => g.n).join('/')}), кадров ни в одном из двух устойчивых видов ${odd}; смена вида в кадрах ${trans.join(', ') || '—'} (от начала движения); самое большое различие соседних ${mmax.toFixed(2)}/255 в среднем по полосе`);
  }
  return L;
}

(async () => {
  const dev = sim.device(ROOT);
  run('xcrun', ['simctl', 'status_bar', dev.udid, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100', '--cellularBars', '4', '--wifiBars', '3']);
  run('xcrun', ['simctl', 'install', dev.udid, APP]);
  for (const name of (args.scenario || 'scroll,today,chain').split(',')) {
    const r = await scenario(dev, name);
    console.log(`\n== ${name} · ${THEME} · ${dev.name} ==`);
    for (const l of report(name, r)) console.log('  ' + l);
    fs.writeFileSync(path.join(r.dir, 'result.txt'), report(name, r).join('\n'));
  }
})().catch(e => { console.error(e.stack || e.message); process.exit(1); });
