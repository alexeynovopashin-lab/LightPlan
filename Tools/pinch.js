#!/usr/bin/env node
/* Итерация 21б: щипок на OpenStreetMap (MapLibre) меняет масштаб. На телефоне
   карта не приближалась и не отдалялась: после щипка SwiftUI ещё кадр рисовал
   прежнее место (оно доезжает до таймбара своей задачей), холст принимал его
   за переезд снаружи и ставил старый центр с уровнем 14 — замер: 16 → 14
   через 12 мс.

   Прогон: Debug-сборка на симулятор, «Карта» с сетью (`-LPShotLiveMap`) на
   MapLibre; приложение само говорит холсту конец щипка (`-LPShotPinchReport`:
   новый уровень, центр к пальцам, причина `.gesturePinch`) пять раз подряд и
   после каждого через 1 с пишет уровень и остался ли центр. Пять — потому что
   ошибка гонка: на старом коде один щипок ловил её в 4 прогонах из 6, пять —
   в 4 из 4. Руки у симулятора нет — движок щипка не проверяется, только путь
   после него. MapKit сюда не входит: он ставит
   камеру по смене центра (`onChange`) и этой ошибки не имел.

   node Tools/pinch.js [--skip-build]
   Симулятор — свой у ветки (`Tools/sim.js`); другой — LP_SIM=<имя>.
   Нужна сеть: без стиля холст камеры не шлёт. */
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');
const sim = require('./sim');

const ROOT = path.resolve(__dirname, '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const BUNDLE = 'Novopashin.LightPlan';
const args = {};
process.argv.slice(2).forEach((a, i, all) => {
  if (a.startsWith('--')) args[a.slice(2)] = all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : '1';
});
if (args.device) process.env.LP_SIM = args.device;
const OUT = path.join(os.tmpdir(), 'lp-pinch', sim.nameFor(ROOT).replace(/\W+/g, '-'));
fs.mkdirSync(OUT, { recursive: true });

const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));

function build(udid) {
  const dd = path.join(OUT, 'DerivedData');
  const log = path.join(OUT, 'xcodebuild.log');
  try {
    run('xcodebuild', ['-project', path.join(ROOT, 'LightPlan.xcodeproj'), '-scheme', 'LightPlan-iOS',
      '-configuration', 'Debug', '-destination', 'platform=iOS Simulator,id=' + udid,
      '-derivedDataPath', dd, 'build'], { stdio: ['ignore', fs.openSync(log, 'w'), fs.openSync(log, 'a')] });
  } catch (e) {
    const errs = fs.readFileSync(log, 'utf8').split('\n').filter(l => /error:/.test(l)).slice(0, 10);
    throw new Error('сборка упала (' + log + '):\n' + errs.join('\n'));
  }
  return path.join(dd, 'Build', 'Products', 'Debug-iphonesimulator', 'LightPlan.app');
}

(async () => {
  const dev = sim.device(ROOT);
  if (!args['skip-build']) run('xcrun', ['simctl', 'install', dev.udid, build(dev.udid)]);

  const seed = JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8'));
  const seedFile = path.join(OUT, 'seed.json');
  const report = path.join(OUT, 'pinch.json');
  fs.writeFileSync(seedFile, JSON.stringify({ ...seed, spots: [], mapSource: 'mapLibre' }));
  fs.rmSync(report, { force: true });
  try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore' }); } catch (e) {}
  run('xcrun', ['simctl', 'launch', dev.udid, BUNDLE,
    '-LPShotNow', '2026-09-23T13:00:00+07:00', '-LPShotZone', 'Asia/Barnaul', '-LPShotSeed', seedFile,
    '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
    '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'map', '-LPShotLiveMap', 'YES',
    '-LPShotPinchReport', report], { stdio: 'ignore' });
  for (let t = 0; t < 40 && !fs.existsSync(report); t++) await sleep(500);
  const got = fs.existsSync(report) ? JSON.parse(fs.readFileSync(report, 'utf8')) : { error: 'нет отчёта за 20 с' };
  const ok = !got.error && Math.abs(got.before - 14) < 0.01 &&
    got.levels.every((l, i) => Math.abs(got.zooms[i] - l) < 0.01 && got.stayed[i]);
  console.log(`${ok ? 'ок    ' : 'ПАДАЕТ'} mapLibre: ${JSON.stringify(got)}`);
  try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore' }); } catch (e) {}
  process.exit(ok ? 0 : 1);
})().catch(e => { console.error(e.message); process.exit(2); });
