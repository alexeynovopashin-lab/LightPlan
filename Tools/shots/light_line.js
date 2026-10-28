#!/usr/bin/env node
/* Строка света дня («Съёмки», день) без подложки — только натив (28.10). Снимает уже поставленную сборку на
 * симулятор ветки в состояниях: раскрыта / свёрнута × тёмная / светлая, без прогноза, часы 12 ч.
 *   node Tools/shots/light_line.js --out <папка> [--cases open-dark,shut-dark,...]
 * Рядом с каждым снимком — native.json (рамки узлов) и line.png (полоса строки, 3×); числа чернил — Tools/shots/line_ink.py.
 * Сборку ставит `pair.js --screens planner --scopes day` (тот же сценарий, тот же засев). */
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = {};
process.argv.slice(2).forEach((a, i, all) => {
  if (a.startsWith('--')) args[a.slice(2)] = all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : '1';
});
const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-light-line'));
const ZONE = 'Asia/Barnaul';
const AT = args.at || '2026-09-23T13:00';
const BUNDLE = 'Novopashin.LightPlan';
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));

const CASES = {
  'open-dark': { theme: 'dark' }, 'open-light': { theme: 'light' },
  'shut-dark': { theme: 'dark', seed: { dayFold: true } }, 'shut-light': { theme: 'light', seed: { dayFold: true } },
  'nowx-dark': { theme: 'dark', noWeather: true }, 'nowx-light': { theme: 'light', noWeather: true },
  'h12-dark': { theme: 'dark', seed: { clock: '12' } },
};

(async () => {
  const dev = sim.device(ROOT);
  const planner = JSON.parse(fs.readFileSync(path.join(FX, 'seed_planner.json'), 'utf8'));
  const names = (args.cases || Object.keys(CASES).join(',')).split(',');
  run('xcrun', ['simctl', 'status_bar', dev.udid, 'override', '--time', '9:41', '--batteryState', 'charged',
    '--batteryLevel', '100', '--cellularBars', '4', '--wifiBars', '3']);
  for (const name of names) {
    const c = CASES[name];
    const dir = path.join(OUT, name);
    fs.mkdirSync(dir, { recursive: true });
    const seedFile = path.join(dir, 'seed.json');
    fs.writeFileSync(seedFile, JSON.stringify({ ...planner, theme: c.theme, pro: false, drumSlot: 'paper', ribbonMode: 'drum', ...(c.seed || {}) }));
    const report = path.join(dir, 'native.json');
    fs.rmSync(report, { force: true });
    try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
    run('xcrun', ['simctl', 'ui', dev.udid, 'appearance', c.theme]);
    const forecast = c.noWeather ? path.join(os.tmpdir(), 'lp-no-forecast-light-line') : path.join(FX, 'forecast_barnaul.json');
    run('xcrun', ['simctl', 'launch', dev.udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
      '-LPShotNow', AT + ':00+07:00', '-LPShotZone', ZONE, '-LPShotSeed', seedFile, '-LPShotForecast', forecast,
      '-LPShotAir', path.join(FX, 'air_barnaul.json'), '-LPShotName', path.join(FX, 'place_barnaul.json'),
      '-LPShotScreen', 'planner', '-LPShotScope', 'day', '-LPShotReport', report],
    { env: { ...process.env, SIMCTL_CHILD_TZ: ZONE } });
    for (let i = 0; i < 240 && !fs.existsSync(report); i++) await sleep(250);
    if (!fs.existsSync(report)) throw new Error('приложение не написало рамки: ' + name);
    await sleep(1500);   // свёрнутая сводка и погода доезжают за кадр-два
    run('xcrun', ['simctl', 'io', dev.udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
    console.log('снято: ' + name);
  }
})();
