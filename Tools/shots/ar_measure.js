#!/usr/bin/env node
/* Шаг 29.8в.11: плашка «Замер» в симуляторе — итог, отказы, история. Только натив и только Debug: у выпуска
   измерителя нет. Замеры запускает `-LPSunARMeasureAuto N` (без касаний), журнал читается с Mac через
   `-LPSunARMeasureLog <файл>`. Настоящее солнце и датчики здесь не проверяются — подставной поворот.

     node Tools/shots/ar_measure.js [--skip-build] [--out <dir>]                                             */
const fs = require('fs'), os = require('os'), path = require('path');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : []).filter(x => x.length));
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const BUNDLE = 'Novopashin.LightPlan';
const TOMSK = '56.4977,84.9744,Asia/Tomsk';

/* day: солнце на 162°/24° (правее/выше на несколько градусов от позы — отклонение видно в числах); blue: солнце под
   горизонтом; off: прицел на 45° в стороне. */
const SCENARIOS = [
  { name: 'result', now: '2026-10-14T12:00:00+07:00', moment: '2026-10-14T05:00:00Z', pose: '158,23.2,0', n: 1, label: 'силикон' },
  { name: 'below', now: '2026-10-20T19:00:00+07:00', moment: '2026-10-20T12:00:00Z', pose: '263,0,0', n: 1, label: '' },
  { name: 'off', now: '2026-10-14T12:00:00+07:00', moment: '2026-10-14T05:00:00Z', pose: '207,24,0', n: 1, label: '' },
  { name: 'history', now: '2026-10-14T12:00:00+07:00', moment: '2026-10-14T05:00:00Z', pose: '158,23.2,0;165,25,0;161,24,0;156,22,0', n: 4, label: 'MagSafe' },
];

(async () => {
  const udid = sim.device(ROOT).udid;
  try { run('xcrun', ['simctl', 'boot', udid], { stdio: 'ignore' }); } catch (e) {}
  const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-shots', 'ar_measure'));
  fs.mkdirSync(OUT, { recursive: true });
  const dd = path.join(OUT, 'DerivedData');
  if (!args['skip-build']) {
    const log = path.join(OUT, 'xcodebuild.log');
    try {
      run('xcodebuild', ['-project', path.join(ROOT, 'LightPlan.xcodeproj'), '-scheme', 'LightPlan-iOS', '-configuration', 'Debug',
        '-destination', 'platform=iOS Simulator,id=' + udid, '-derivedDataPath', dd, 'build'], { stdio: ['ignore', fs.openSync(log, 'w'), fs.openSync(log, 'a')] });
    } catch (e) { throw new Error('сборка упала: ' + log); }
  }
  const products = path.join(dd, 'Build', 'Products', 'Debug-iphonesimulator');
  const app = path.join(products, fs.readdirSync(products).find(f => f.endsWith('.app')));
  run('xcrun', ['simctl', 'install', udid, app]);
  run('xcrun', ['simctl', 'ui', udid, 'appearance', 'dark']);
  const flag = (k, v) => ['-lightplan.native.sunar.' + k, v];
  const rows = [];
  for (const sc of SCENARIOS) {
    const dir = path.join(OUT, sc.name);
    fs.mkdirSync(dir, { recursive: true });
    const report = path.join(dir, 'native.json'), csv = path.join(dir, 'measure.csv');
    fs.rmSync(report, { force: true }); fs.rmSync(csv, { force: true });
    try { run('xcrun', ['simctl', 'terminate', udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
    const delay = 1.5 + 2.9 * sc.n + 1.5;
    run('xcrun', ['simctl', 'launch', udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
      '-LPShotNow', sc.now, '-LPShotZone', 'Asia/Tomsk', '-LPShotSeed', path.join(FX, 'seed.json'),
      '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
      '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'map', '-LPShotReportDelay', String(delay),
      ...flag('calibrationSeen', 'YES'), ...flag('moon', 'NO'), ...flag('milkyWay', 'NO'),
      ...flag('measure.case', sc.label), ...flag('measure.body', 'sun'), ...flag('measure.history', ''),
      '-LPSunAR', '1', '-LPSunARMoment', sc.moment, '-LPSunARPose', sc.pose, '-LPSunARPhone', TOMSK, '-LPSunARFakeCamera', '1',
      '-LPSunARMeasureAuto', String(sc.n), '-LPSunARMeasureLog', csv, '-LPShotReport', report]);
    for (let i = 0; i < 120 && !fs.existsSync(report); i++) await sleep(250 + 0);
    if (!fs.existsSync(report)) throw new Error('нет рамок: ' + sc.name);
    await sleep(800);
    run('xcrun', ['simctl', 'io', udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
    const nodes = JSON.parse(fs.readFileSync(report, 'utf8')).nodes || {};
    const lines = fs.existsSync(csv) ? fs.readFileSync(csv, 'utf8').trim().split('\n') : [];
    rows.push({ scenario: sc.name, plate: nodes['ar.measure'] && nodes['ar.measure'].text, button: !!nodes['ar.measureButton'], csvLines: lines.length });
  }
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(rows, null, 1));
  for (const r of rows) console.log(`${r.scenario}: плашка «${r.plate}», кнопка ${r.button ? 'есть' : 'НЕТ'}, строк в CSV ${r.csvLines}`);
  console.log('→ ' + OUT);
})().catch(e => { console.error(e.message); process.exit(1); });
