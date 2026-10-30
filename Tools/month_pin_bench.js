#!/usr/bin/env node
/* Стенд закреплённой линейки месяца (30.2): кадры названия шапки, линейки, сетки и панели дня при прокрутке, смене вида, прыжке,
   сворачивании панели и «сегодня» (`PlannerMonthPinBench.swift`, `-LPMonthScript scroll|jump|fold|scopes|today`, журнал `-LPPinLog`).

     node Tools/month_pin_bench.js --app <.app> [--scenario scroll,jump,fold,scopes,today] [--theme dark|light] [--week mon|sun|sat]
                                   [--sim <имя|udid>] [--out <папка>] [--video]

   Числа по журналу: у каждого узла (mtitle, mruler, mhead, mgrid, mpanel) — рамка y в каждом кадре раскладки в окне сценария,
   сколько разных значений, самый большой скачок от кадра к кадру; для сетки и панели — совпадает ли y + прокрутка с константой
   (они едут ровно с пальцем). `--video` режет полосу линейки из записи симулятора: различие соседних кадров должно быть ≈ 0.
   Из отчёта узлов (-LPShotReport): слова линейки стоят над столбцами сетки (разница центров по x). */
const fs = require('fs'), path = require('path'), os = require('os');
const { execFileSync, spawn } = require('child_process');
const sim = require('./sim');
const M = require('./motion/measure');
const ROOT = path.resolve(__dirname, '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = {};
for (let i = 2; i < process.argv.length; i++) { const a = process.argv[i]; if (a.startsWith('--')) { const nx = process.argv[i + 1]; if (nx && !nx.startsWith('--')) { args[a.slice(2)] = nx; i++; } else args[a.slice(2)] = true; } }
const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-month-pin'));
fs.mkdirSync(OUT, { recursive: true });
const run = (c, a, o = {}) => execFileSync(c, a, { encoding: 'utf8', ...o });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const THEME = args.theme || 'dark', WEEK = args.week || 'mon';
const BUNDLE = 'Novopashin.LightPlan';
const APP = args.app;
if (!APP) { console.error('--app <.app>'); process.exit(2); }
const KEYS = ['mtitle', 'mruler', 'mhead', 'mgrid', 'mpanel'];

function parseLog(text) {
  const rows = [];
  for (const l of text.split('\n')) {
    const m = /^\s*(\d+) (.*)$/.exec(l); if (!m) continue;
    const t = +m[1], rest = m[2];
    let g = /^geo (\S+) ([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)$/.exec(rest);
    if (g) { rows.push({ t, kind: 'geo', key: g[1], x: +g[2], y: +g[3], w: +g[4], h: +g[5] }); continue; }
    g = /^mscroll=([-\d.]+)/.exec(rest);
    if (g) { rows.push({ t, kind: 'scroll', s: +g[1] }); continue; }
    rows.push({ t, kind: 'mark', text: rest });
  }
  return rows;
}

async function scenario(dev, name) {
  const dir = path.join(OUT, `${name}-${THEME}-${WEEK}`); fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true });
  const seed = JSON.parse(fs.readFileSync(path.join(FX, 'seed_planner.json'), 'utf8'));
  const seedFile = path.join(dir, 'seed.json');
  fs.writeFileSync(seedFile, JSON.stringify({ ...seed, theme: THEME, pro: false, drumSlot: 'paper', ribbonMode: 'drum', weekStart: WEEK }));
  const log = path.join(dir, 'pin.log'), video = path.join(dir, 'video.mp4'), report = path.join(dir, 'native.json');
  try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore' }); } catch (e) {}
  run('xcrun', ['simctl', 'ui', dev.udid, 'appearance', THEME]);
  let rec = null;
  if (args.video) { rec = spawn('xcrun', ['simctl', 'io', dev.udid, 'recordVideo', '--codec=h264', '--force', video], { stdio: 'ignore' }); await sleep(2500); }
  run('xcrun', ['simctl', 'launch', dev.udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
    '-LPShotNow', '2026-10-29T13:00:00+07:00', '-LPShotZone', 'Asia/Barnaul', '-LPShotSeed', seedFile,
    '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
    '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'planner', '-LPShotScope', 'month',
    '-LPShotReport', report, '-LPShotReportDelay', '3', '-LPPinLog', log, '-LPMonthScript', name],
  { env: { ...process.env, SIMCTL_CHILD_TZ: 'Asia/Barnaul' } });
  for (let i = 0; i < 200 && !(fs.existsSync(log) && /script \w+ done/.test(fs.readFileSync(log, 'utf8'))); i++) await sleep(250);
  await sleep(800);
  if (rec) { rec.kill('SIGINT'); await new Promise(r => rec.on('exit', r)); }
  return { dir, log: parseLog(fs.readFileSync(log, 'utf8')), video, report };
}

const f1 = v => v.toFixed(1);
/* Рамки узла в окне [t0, t1]: значения y по кадрам, число разных, самый большой скачок между соседними кадрами. */
function track(rows, key, t0, t1) {
  // Журнал пишет рамку, только когда она изменилась: узел, что стоял, в окне молчит — берём его последнюю рамку до окна как первый кадр.
  const before = rows.filter(x => x.kind === 'geo' && x.key === key && x.t < t0).pop();
  const g = (before ? [{ ...before, t: t0 }] : []).concat(rows.filter(x => x.kind === 'geo' && x.key === key && x.t >= t0 && x.t <= t1));
  let max = 0; for (let i = 1; i < g.length; i++) max = Math.max(max, Math.abs(g[i].y - g[i - 1].y));
  return { n: g.length, distinct: [...new Set(g.map(x => f1(x.y)))], max, g };
}
/* Низ узла (y + высота) — по нему видно, как растёт шапка. */
function trackBottom(rows, key, t0, t1) {
  const t = track(rows, key, t0, t1);
  const ys = t.g.map(x => x.y + x.h);
  let max = 0; for (let i = 1; i < ys.length; i++) max = Math.max(max, Math.abs(ys[i] - ys[i - 1]));
  return { n: ys.length, distinct: [...new Set(ys.map(f1))], max };
}
const line = (label, t) => `${label}: кадров ${t.n}, y ${t.distinct.length <= 8 ? t.distinct.join(' / ') : t.distinct.slice(0, 4).join(' / ') + ' … ' + t.distinct.slice(-2).join(' / ') + ` (${t.distinct.length} знач.)`}, самый большой скачок между кадрами ${f1(t.max)} pt`;
const markT = (rows, text) => (rows.find(x => x.kind === 'mark' && x.text.startsWith(text)) || {}).t;

/* Узел едет вместе с прокруткой: y + прокрутка в каждом кадре одно число. */
function ridesWithScroll(rows, key, t0, t1) {
  const sc = rows.filter(x => x.kind === 'scroll');
  const g = rows.filter(x => x.kind === 'geo' && x.key === key && x.t >= t0 && x.t <= t1);
  const sums = [];
  for (const x of g) { const s = sc.filter(y => y.t <= x.t + 3).pop(); if (s) sums.push(x.y + s.s); }
  return sums.length ? { n: sums.length, spread: Math.max(...sums) - Math.min(...sums) } : null;
}

function report(name, r) {
  const rows = r.log, L = [];
  if (name === 'scroll' || name === 'jump') {
    const a = name === 'scroll' ? 'script scroll down' : 'script jump down', b = name === 'scroll' ? 'script scroll up' : 'script jump up';
    const t0 = markT(rows, a), t1 = markT(rows, `script ${name} done`);
    const sc = rows.filter(x => x.kind === 'scroll' && x.t >= t0 && x.t <= t1);
    let step = 0; for (let i = 1; i < sc.length; i++) step = Math.max(step, Math.abs(sc[i].s - sc[i - 1].s));
    L.push(`прокрутка: кадров ${sc.length}, от ${f1(Math.min(...sc.map(x => x.s)))} до ${f1(Math.max(...sc.map(x => x.s)))} pt, самый большой шаг между кадрами ${f1(step)} pt`);
    for (const k of ['mtitle', 'mruler', 'mhead']) L.push(line(k, track(rows, k, t0, t1)));
    for (const k of ['mgrid', 'mpanel']) {
      const t = track(rows, k, t0, t1), c = ridesWithScroll(rows, k, t0, t1);
      L.push(line(k, t) + (c ? `; y + прокрутка: разброс ${f1(c.spread)} pt по ${c.n} кадрам (0 = едет ровно с прокруткой)` : ''));
    }
  } else if (name === 'fold') {
    const t0 = markT(rows, 'script fold shut'), t1 = markT(rows, 'script fold done');
    for (const k of KEYS) L.push(line(k, track(rows, k, t0, t1)));
    const p = rows.filter(x => x.kind === 'geo' && x.key === 'mpanel' && x.t >= t0 && x.t <= t1);
    let hm = 0; for (let i = 1; i < p.length; i++) hm = Math.max(hm, Math.abs(p[i].h - p[i - 1].h));
    L.push(`панель дня: высота ${[...new Set(p.map(x => f1(x.h)))].slice(0, 3).join(' … ')}, самый большой скачок высоты между кадрами ${f1(hm)} pt`);
  } else if (name === 'scopes' || name === 'today') {
    const marks = rows.filter(x => x.kind === 'mark' && x.text.startsWith('script ') && !/done$/.test(x.text));
    const end = markT(rows, `script ${name} done`);
    for (let i = 0; i < marks.length; i++) {
      const t0 = marks[i].t, t1 = i + 1 < marks.length ? marks[i + 1].t : end;
      L.push(`— ${marks[i].text}`);
      for (const k of ['mtitle', 'mruler', 'mhead', 'mgrid']) { const t = track(rows, k, t0, t1); if (t.n) L.push('  ' + line(k, t)); else L.push(`  ${k}: рамок нет (узла на экране нет)`); }
      L.push('  ' + line('низ шапки', trackBottom(rows, 'mhead', t0, t1)));
    }
  }
  if (fs.existsSync(r.report)) {
    const nodes = JSON.parse(fs.readFileSync(r.report, 'utf8')).nodes;
    const cx = n => nodes[n] && nodes[n].x + nodes[n].w / 2;
    if (nodes['head.0'] && nodes['cal.0']) {
      const d = []; for (let i = 0; i < 7; i++) d.push(Math.abs(cx(`head.${i}`) - cx(`cal.${i}`)));
      L.push(`слова линейки над столбцами сетки: разница центров по x ${d.map(f1).join(' ')} pt, наибольшая ${f1(Math.max(...d))}; слова: ${[0, 1, 2, 3, 4, 5, 6].map(i => nodes[`head.${i}`].text).join(' ')}`);
    }
  }
  return L;
}

(async () => {
  const dev = args.sim ? { udid: args.sim, name: args.sim } : sim.device(ROOT);
  run('xcrun', ['simctl', 'status_bar', dev.udid, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100', '--cellularBars', '4', '--wifiBars', '3']);
  run('xcrun', ['simctl', 'install', dev.udid, APP]);
  for (const name of (args.scenario || 'scroll,jump,fold,scopes,today').split(',')) {
    const r = await scenario(dev, name);
    console.log(`\n== ${name} · ${THEME} · ${WEEK} · ${dev.name} ==`);
    const L = report(name, r);
    for (const l of L) console.log('  ' + l);
    fs.writeFileSync(path.join(r.dir, 'result.txt'), L.join('\n'));
  }
})().catch(e => { console.error(e.stack || e.message); process.exit(1); });
