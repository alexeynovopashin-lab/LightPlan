#!/usr/bin/env node
/* 30з.3: кадры «Света» для света из-под первой плашки — моменты × темы. Каркас — palette_d.js.
 *   node Tools/shots/plate_glow.js --app <.app> --out <папка> [--cases a,b] [--list]
 * В отчёт пишется узел `plate.glow` (цвет|непрозрачность пика|центр) и рамка `plate.now`; пиксели — Tools/shots/plate_glow.py. */
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = {};
process.argv.slice(2).forEach((a, i, all) => {
  if (a.startsWith('--')) args[a.slice(2)] = all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : '1';
});
const ZONE = 'Asia/Barnaul';
const BUNDLE = 'Novopashin.LightPlan';
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));

// 30з.3: моменты 23 сентября 2026 по Барнаулу (+07:00). Высота солнца (расчёт Meeus, ±0,2°): день +36°, закат 19:30 −2,1°,
// синий час 19:50 −5,0°, глубокие сумерки 20:20 −9,5°, астрономические 20:50 −13,8°, ночь 23:00 −29,8°.
const AT = { day: '2026-09-23T13:00', set: '2026-09-23T19:30', blue: '2026-09-23T19:50', deep: '2026-09-23T20:20', astro: '2026-09-23T20:50', night: '2026-09-23T23:00' };

const CASES = {};
for (const theme of ['light', 'dark']) {
  for (const m of Object.keys(AT)) {
    // Прогноз — `Fixtures/shots/forecast_barnaul.json` как есть; `nowx` — без прогноза (цвет ступени высоты солнца).
    CASES[`glow-${m}-${theme}`] = { theme, mode: 'astro', at: AT[m], screen: 'light' };
    CASES[`glow-${m}-simple-${theme}`] = { theme, mode: 'simple', at: AT[m], screen: 'light' };
    CASES[`glow-${m}-nowx-${theme}`] = { theme, mode: 'astro', at: AT[m], screen: 'light', noWeather: true };
  }
}
// Те же кадры без света (`-LPPlateGlowOff 1`): разность с ними — это и есть свет.
for (const k of Object.keys(CASES)) CASES[k + '-off'] = { ...CASES[k], extra: ['-LPPlateGlowOff', '1'] };

(async () => {
  if (args.list) { console.log(Object.keys(CASES).join('\n')); return; }
  const out = path.resolve(args.out || '/tmp/lp-plate-glow');
  const dev = sim.device(ROOT);
  if (args.app) run('xcrun', ['simctl', 'install', dev.udid, path.resolve(args.app)]);
  run('xcrun', ['simctl', 'status_bar', dev.udid, 'override', '--time', '9:41', '--batteryState', 'charged',
    '--batteryLevel', '100', '--cellularBars', '4', '--wifiBars', '3']);
  const base = JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8'));
  const plan = JSON.parse(fs.readFileSync(path.join(FX, 'seed_planner.json'), 'utf8'));
  const names = args.cases ? args.cases.split(',') : Object.keys(CASES);
  fs.mkdirSync(out, { recursive: true });
  for (const name of names) {
    const c = CASES[name];
    if (!c) throw new Error('нет случая ' + name);
    const seedFile = path.join(out, name + '.seed.json');
    fs.writeFileSync(seedFile, JSON.stringify({ ...(c.planner ? plan : base), theme: c.theme, pro: c.mode !== 'simple',
      appMode: c.mode === 'pro' ? 'pro' : c.mode, drumSlot: 'paper', ribbonMode: 'drum' }));
    const report = path.join(out, name + '.json');
    fs.rmSync(report, { force: true });
    try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
    run('xcrun', ['simctl', 'ui', dev.udid, 'appearance', c.theme]);
    run('xcrun', ['simctl', 'launch', dev.udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
      '-LPShotNow', c.at + ':00+07:00', '-LPShotZone', ZONE, '-LPShotSeed', seedFile,
      '-LPShotForecast', c.noWeather ? path.join(out, 'no-forecast') : path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
      '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', c.screen,
      ...(c.scope ? ['-LPShotScope', c.scope] : []), ...(c.extra || []), '-LPShotReport', report],
    { env: { ...process.env, SIMCTL_CHILD_TZ: ZONE } });
    for (let i = 0; i < 240 && !fs.existsSync(report); i++) await sleep(250);
    if (!fs.existsSync(report)) throw new Error('приложение не написало рамки: ' + name);
    await sleep(c.delay || 1800);
    run('xcrun', ['simctl', 'io', dev.udid, 'screenshot', '--type=png', path.join(out, name + '.png')], { stdio: 'ignore' });
    console.log('снято: ' + name);
  }
})();
