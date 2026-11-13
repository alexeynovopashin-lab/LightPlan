#!/usr/bin/env node
/* 28к.4: кадры только натива для сверки светлой темы (палитра Д) и тёмной «до / после» (тёмная не должна измениться ни на пиксель).
 *   node Tools/shots/palette_d.js --app <.app> --out <папка> [--cases a,b,c] [--list]
 * Ставит сборку на симулятор ветки, для каждого случая запускает её с часами, темой и режимом и снимает экран.
 * Часы подменены (`-LPShotNow`), погода и места — из `Fixtures/shots`, так что один случай на одной сборке повторяется.
 * Сравнение двух папок и пиксели ключевых мест — Tools/shots/palette_d.py. */
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

// Моменты 23 сентября 2026 по Барнаулу (+07:00): день, золотой час, сумерки, ночь.
const AT = { day: '2026-09-23T13:00', golden: '2026-09-23T18:50', dusk: '2026-09-23T20:20', night: '2026-09-23T23:00', small: '2026-09-23T03:00' };

const CASES = {};
for (const theme of ['light', 'dark']) {
  for (const mode of ['astro', 'simple']) {
    for (const m of Object.keys(AT)) {
      CASES[`light-${mode}-${m}-${theme}`] = { theme, mode, at: AT[m], screen: 'light' };
    }
  }
  for (const scope of ['month', 'week', 'day']) {
    CASES[`planner-${scope}-${theme}`] = { theme, mode: 'pro', at: AT.day, screen: 'planner', scope, planner: true };
  }
  for (const mode of ['simple', 'pro', 'astro']) {
    CASES[`settings-${mode}-${theme}`] = { theme, mode, at: AT.day, screen: 'settings' };
  }
  // Без прогноза: строка «Условия» говорит «Звёздная ночь» (слово света, не погоды).
  CASES[`light-astro-night-nowx-${theme}`] = { theme, mode: 'astro', at: AT.night, screen: 'light', noWeather: true };
  CASES[`map-astro-${theme}`] = { theme, mode: 'astro', at: AT.golden, screen: 'map' };
  // Нажатие «Астро»: звёзды вылетают на ~2,4 с; снимок через 0,9 с после появления.
  CASES[`settings-enterastro-${theme}`] = { theme, mode: 'pro', at: AT.day, screen: 'settings', extra: ['-LPShotEnterAstro', '1'], delay: 900 };
}

(async () => {
  if (args.list) { console.log(Object.keys(CASES).join('\n')); return; }
  const out = path.resolve(args.out || '/tmp/lp-palette-d');
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
