#!/usr/bin/env node
/* Итерация 20е: тап по булавке на живом холсте открывает полосу имени.
   На телефоне тап переносил карту, а полоса не появлялась: у MapKit переезд
   программой считался протяжкой пальцем (центр возвращается с шумом в
   девятом знаке, `moved != placed`) и закрывал полосу в тот же кадр.

   Прогон: Debug-сборка на симулятор, «Карта» с сетью (`-LPShotLiveMap`) на
   каждом холсте — MapLibre и MapKit; приложение само тапает острие булавки
   (`-LPShotTapSpot`, тот же `tapMap`, что у распознавателя холста) и пишет,
   стоит ли полоса через 1 и 4 с и ушла ли через 6,5 с. Протяжку пальцем
   этот прибор не делает — симулятор без руки; её держат модульные тесты
   `MapCanvasHandTests` и замер 20е руками (DECISIONS).

   node Tools/tap_spot.js [--skip-build]
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
const OUT = path.join(os.tmpdir(), 'lp-tap-spot', sim.nameFor(ROOT).replace(/\W+/g, '-'));
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

  // Булавка в полукилометре к северо-востоку от центра Барнаула — на кадре
  // при уровне 14, мимо головки и кнопок.
  const seed = JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8'));
  seed.spots = [{ id: 'tap', name: 'Тест', lat: 53.3572, lon: 83.774, pinned: true, mt: 1 }];
  let fail = 0;
  for (const canvas of ['mapLibre', 'mapKit']) {
    const seedFile = path.join(OUT, `seed_${canvas}.json`);
    const report = path.join(OUT, `tap_${canvas}.json`);
    fs.writeFileSync(seedFile, JSON.stringify({ ...seed, mapSource: canvas }));
    fs.rmSync(report, { force: true });
    try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore' }); } catch (e) {}
    run('xcrun', ['simctl', 'launch', dev.udid, BUNDLE,
      '-LPShotNow', '2026-09-23T13:00:00+07:00', '-LPShotZone', 'Asia/Barnaul', '-LPShotSeed', seedFile,
      '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
      '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'map', '-LPShotLiveMap', 'YES',
      '-LPShotTapSpot', 'tap', '-LPShotTapReport', report], { stdio: 'ignore' });
    for (let t = 0; t < 40 && !fs.existsSync(report); t++) await sleep(500);
    const got = fs.existsSync(report) ? JSON.parse(fs.readFileSync(report, 'utf8')) : { error: 'нет отчёта за 20 с' };
    const ok = !got.error && got.moved && got.bar1 && got.bar4 && !got.bar6_5;
    if (!ok) fail = 1;
    console.log(`${ok ? 'ок    ' : 'ПАДАЕТ'} ${canvas}: ${JSON.stringify(got)}`);
  }
  try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore' }); } catch (e) {}
  process.exit(fail);
})().catch(e => { console.error(e.message); process.exit(2); });
