#!/usr/bin/env node
/* Шаг 29.8в.4: экран AR в симуляторе с подставной камерой. Только натив: у веба AR нет, пары быть не может.

   Камера — `-LPSunARFakeCamera 1` (отладка): тридцать кадров в секунду из двух заранее нарисованных, весь
   путь «кадр → слой Metal → диск» работает как с настоящей камерой. Место телефона подставляется
   (`-LPSunARPhone`), поворот — `-LPSunARPose`, момент — `-LPSunARMoment`.

   Сценарии: day (солнце в кадре, луна ниже горизонта), night_moon (луна в фазе, солнце за краем — стрелка),
   night_mw (Млечный Путь и луна, ядро над горизонтом), entry_far (плашка входа: выбранное далеко от
   телефона), entry_off (плашка входа: нет доступа к геопозиции).

   Числа из отчёта приложения (рамки узлов): диаметры меток, высота касания кнопок, присутствие слоёв,
   стрелки и плашки. Любое нарушение — код 1.

     node Tools/shots/ar.js [--skip-build] [--out <dir>]      (или make shots ARGS="--screens ar")        */
const fs = require('fs'), os = require('os'), path = require('path');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : []).filter(x => x.length));
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const BUNDLE = 'Novopashin.LightPlan';
const TOMSK = '56.4977,84.9744,Asia/Tomsk', MOSCOW = '55.7558,37.6173,Europe/Moscow';

/* Сценарии: now — «сейчас» приложения, moment — выбранный момент, pose — азимут,высота,крен. */
const SCENARIOS = [
  { name: 'day', now: '2026-10-14T12:00:00+07:00', moment: '2026-10-14T05:00:00Z', pose: '162,24,0', phone: TOMSK,
    moon: true, mw: false, camera: true },
  { name: 'night_moon', now: '2026-10-20T21:00:00+07:00', moment: '2026-10-20T14:00:00Z', pose: '183,18,0', phone: TOMSK,
    moon: true, mw: false, camera: true },
  { name: 'night_mw', now: '2026-08-20T22:00:00+07:00', moment: '2026-08-20T15:00:00Z', pose: '198,14,0', phone: TOMSK,
    moon: true, mw: true, camera: true },
  { name: 'entry_far', now: '2026-10-20T21:00:00+07:00', moment: '2026-10-20T14:00:00Z', pose: '183,18,0', phone: MOSCOW,
    moon: false, mw: false, camera: false, entry: true },
  { name: 'entry_off', now: '2026-10-20T21:00:00+07:00', moment: '2026-10-20T14:00:00Z', pose: '183,18,0', phone: null,
    moon: false, mw: false, camera: false, entry: true },
];

const node = (nodes, k) => nodes[k];
/* Проверки по рамкам узлов. Возвращают список нарушений. */
function verdict(sc, nodes) {
  const bad = [];
  const need = k => { if (!nodes[k]) { bad.push('нет узла ' + k); return false; } return true; };
  const touch = k => { if (need(k) && nodes[k].h < 43.9) bad.push(`${k}: высота касания ${nodes[k].h.toFixed(1)} < 44`); };
  if (sc.entry) {
    need('ar.entry'); need('ar.entry.why'); touch('ar.entry.useMine'); touch('ar.entry.keep');
    if (nodes['ar.entry.keep'] && !/Барнаул/.test(nodes['ar.entry.keep'].text || '')) bad.push('«Оставить» не называет выбранное место');
    if (nodes['ar.entry.useMine'] && !/моё местоположение/.test(nodes['ar.entry.useMine'].text || '')) bad.push('нет «Использовать моё местоположение»');
    return bad;
  }
  touch('ar.back'); touch('ar.moonToggle'); touch('ar.mwToggle');
  if (nodes['ar.moonToggle'] && nodes['ar.moonToggle'].w < 43.9) bad.push('включатель луны уже 44');
  need('ar.panel');
  const marks = Object.keys(nodes).filter(k => k.startsWith('ar.mark.'));
  const sun = marks.filter(k => /sun/.test(k)), moon = marks.filter(k => /moon/.test(k));
  for (const k of sun) if (![48, 34].includes(Math.round(nodes[k].w))) bad.push(`${k}: диаметр ${nodes[k].w} не 48/34`);
  if (sc.name === 'day' && !sun.length) bad.push('солнца в кадре нет');
  if (sc.name === 'night_moon') {
    if (!moon.length) bad.push('луны в кадре нет');
    if (!nodes['ar.pointer.sun']) bad.push('нет стрелки к солнцу за краем');
    for (const k of moon) {
      const t = nodes[k].text || '';
      const m = /f=([0-9.]+)/.exec(t);
      if (!/limb=-?[0-9.]/.test(t)) bad.push(k + ': нет наклона кромки (' + t + ')');
      if (!m || Math.abs(+m[1] - 0.69) > 0.02) bad.push(k + ': фаза ' + (m && m[1]) + ' не 0,69');
    }
  }
  if (sc.name === 'night_mw') {
    if (!need('ar.milkyWay')) return bad;
    const t = nodes['ar.milkyWay'].text || '';
    if (/polys=0/.test(t)) bad.push('полосы нет: ' + t);
    if (/core=—/.test(t)) bad.push('ядра нет в кадре: ' + t);
    if (/ghost=1/.test(t)) bad.push('ночью полоса идёт призраком: ' + t);
  }
  if (sc.moon && !sc.mw && nodes['ar.milkyWay']) bad.push('Млечный Путь нарисован при выключенном включателе');
  return bad;
}

(async () => {
  const udid = sim.device(ROOT).udid;
  try { run('xcrun', ['simctl', 'boot', udid], { stdio: 'ignore' }); } catch (e) {}
  const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-shots', 'ar'));
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
  // Флаги устройства — аргументами запуска: `defaults write` через simctl пишет не в тот файл, что читает приложение.
  const flag = (k, v) => ['-lightplan.native.sunar.' + k, v ? 'YES' : 'NO'];

  const rows = [];
  for (const sc of SCENARIOS) {
    const dir = path.join(OUT, sc.name);
    fs.mkdirSync(dir, { recursive: true });
    const report = path.join(dir, 'native.json');
    fs.rmSync(report, { force: true });
    try { run('xcrun', ['simctl', 'terminate', udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
    run('xcrun', ['simctl', 'launch', udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
      '-LPShotNow', sc.now, '-LPShotZone', 'Asia/Tomsk', '-LPShotSeed', path.join(FX, 'seed.json'),
      '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
      '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'map', '-LPShotReportDelay', '5',
      ...flag('calibrationSeen', true), ...flag('moon', sc.moon), ...flag('milkyWay', sc.mw),
      '-LPSunAR', '1', '-LPSunARMoment', sc.moment, '-LPSunARPose', sc.pose,
      ...(sc.phone ? ['-LPSunARPhone', sc.phone] : []), ...(sc.camera ? ['-LPSunARFakeCamera', '1'] : []),
      ...(sc.entry ? ['-LPSunAREntry', '1'] : []), '-LPShotReport', report]);
    for (let i = 0; i < 240 && !fs.existsSync(report); i++) await sleep(250);
    if (!fs.existsSync(report)) throw new Error('нет рамок: ' + sc.name);
    await sleep(1500);
    run('xcrun', ['simctl', 'io', udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
    const nodes = JSON.parse(fs.readFileSync(report, 'utf8')).nodes || {};
    const bad = verdict(sc, nodes);
    const marks = Object.fromEntries(Object.keys(nodes).filter(k => /^ar\.(mark|pointer|milkyWay|moonToggle|mwToggle|entry)/.test(k))
      .map(k => [k, { w: +nodes[k].w.toFixed(1), h: +nodes[k].h.toFixed(1), text: nodes[k].text }]));
    rows.push({ scenario: sc.name, bad, nodes: marks });
  }
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(rows, null, 1));
  for (const r of rows) console.log(r.scenario + ': ' + (r.bad.length ? 'НАРУШЕНИЯ ' + r.bad.join('; ') : 'ок') + '  [' + Object.keys(r.nodes).join(', ') + ']');
  console.log('→ ' + OUT);
  const fails = rows.flatMap(r => r.bad.map(m => `${r.scenario}: ${m}`));
  if (fails.length) throw new Error('AR: ' + fails.length + ' нарушений:\n' + fails.join('\n'));
})().catch(e => { console.error(e.message); process.exit(1); });
