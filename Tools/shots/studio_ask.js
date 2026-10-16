#!/usr/bin/env node
/* Шаг 30а.2: плашка перед системным окном уведомлений, тёмная и светлая тема, три устройства.
   Только натив: у веба такой плашки нет. Плашка включается аргументом запуска `-LPStudioAsk 1` (отладка), без
   сохранения записи и без системы. Числа — из рамок узлов: плашка целиком на экране с полями ≥ 24 pt,
   высота касания «Да»/«Нет» ≥ 44, кнопки не накладываются и не выходят из плашки, текст виден целиком.

   Устройства создаются здесь же и удаляются в конце (`--keep` оставляет): iPhone SE (3rd generation) 375 pt,
   iPhone 15 Pro Max 430 pt, и симулятор ветки (iPhone 17 Pro Max, 440 pt).

     node Tools/shots/studio_ask.js [--skip-build] [--keep] [--out <dir>]                                       */
const fs = require('fs'), os = require('os'), path = require('path');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : []).filter(x => x.length));
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const BUNDLE = 'Novopashin.LightPlan';

const EXTRA = [
  { label: 'se', name: 'LP wt-30a2 SE', type: 'com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation' },
  { label: 'pm15', name: 'LP wt-30a2 15PM', type: 'com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max' },
];

function verdict(nodes, screen) {
  const bad = [], n = k => { if (!nodes[k]) bad.push('нет узла ' + k); return nodes[k]; };
  const plate = n('studio.ask'), text = n('studio.ask.text'), yes = n('studio.ask.yes'), no = n('studio.ask.no');
  if (!plate || !text || !yes || !no) return bad;
  if (plate.x < 23.9 || plate.x + plate.w > screen.w - 23.9) bad.push(`плашка ${plate.x.toFixed(1)}…${(plate.x + plate.w).toFixed(1)} — поля < 24 pt`);
  for (const [k, b] of [['Да', yes], ['Нет', no]]) {
    if (b.h < 43.9) bad.push(`«${k}»: высота касания ${b.h.toFixed(1)} < 44`);
    if (b.x < plate.x || b.x + b.w > plate.x + plate.w) bad.push(`«${k}» выходит из плашки по ширине`);
  }
  if (no.x + no.w > yes.x + 0.1) bad.push('«Нет» заходит на «Да»');
  if (text.y < plate.y || text.y + text.h > yes.y) bad.push('текст вне плашки или под кнопками');
  return bad;
}

(async () => {
  const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-shots', 'studio_ask'));
  fs.mkdirSync(OUT, { recursive: true });
  const dd = path.join(OUT, 'DerivedData');
  const main = sim.device(ROOT);
  const devices = [{ label: 'pm17', udid: main.udid, own: false }];
  const existing = JSON.parse(run('xcrun', ['simctl', 'list', 'devices', 'available', '-j'])).devices;
  const runtime = Object.keys(existing).find(r => existing[r].some(d => d.udid === main.udid));
  for (const e of EXTRA) {
    let d = Object.values(existing).flat().find(x => x.name === e.name);
    const udid = d ? d.udid : run('xcrun', ['simctl', 'create', e.name, e.type, runtime]).trim();
    try { run('xcrun', ['simctl', 'boot', udid], { stdio: 'ignore' }); } catch (x) {}
    devices.push({ label: e.label, udid, own: true });
  }
  if (!args['skip-build']) {
    const log = path.join(OUT, 'xcodebuild.log');
    try {
      run('xcodebuild', ['-project', path.join(ROOT, 'LightPlan.xcodeproj'), '-scheme', 'LightPlan-iOS', '-configuration', 'Debug',
        '-destination', 'platform=iOS Simulator,id=' + main.udid, '-derivedDataPath', dd, 'build'], { stdio: ['ignore', fs.openSync(log, 'w'), fs.openSync(log, 'a')] });
    } catch (e) { throw new Error('сборка упала: ' + log); }
  }
  const products = path.join(dd, 'Build', 'Products', 'Debug-iphonesimulator');
  const app = path.join(products, fs.readdirSync(products).find(f => f.endsWith('.app')));

  const rows = [];
  for (const dev of devices) {
    run('xcrun', ['simctl', 'bootstatus', dev.udid, '-b'], { stdio: 'ignore' });
    run('xcrun', ['simctl', 'install', dev.udid, app]);
    for (const theme of ['dark', 'light']) {
      run('xcrun', ['simctl', 'ui', dev.udid, 'appearance', theme]);
      const dir = path.join(OUT, dev.label + '_' + theme);
      fs.mkdirSync(dir, { recursive: true });
      const report = path.join(dir, 'native.json');
      // Тема живёт в снимке данных, а не в системе: свой seed на каждую тему.
      const seedFile = path.join(dir, 'seed.json');
      fs.writeFileSync(seedFile, JSON.stringify({ ...JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8')), theme }));
      fs.rmSync(report, { force: true });
      try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
      run('xcrun', ['simctl', 'launch', dev.udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
        '-LPShotNow', '2026-10-20T12:00:00+07:00', '-LPShotZone', 'Asia/Tomsk', '-LPShotSeed', seedFile,
        '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
        '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'planner', '-LPShotReportDelay', '4',
        '-LPStudioAsk', '1', '-LPShotReport', report]);
      for (let i = 0; i < 240 && !fs.existsSync(report); i++) await sleep(250);
      if (!fs.existsSync(report)) throw new Error('нет рамок: ' + dir);
      await sleep(1200);
      run('xcrun', ['simctl', 'io', dev.udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
      const rep = JSON.parse(fs.readFileSync(report, 'utf8'));
      const nodes = rep.nodes || {};
      const screen = rep.screen || { w: nodes['studio.ask'] ? nodes['studio.ask'].x * 2 + nodes['studio.ask'].w : 0 };
      const bad = verdict(nodes, screen);
      const b = k => nodes[k] ? { x: +nodes[k].x.toFixed(1), y: +nodes[k].y.toFixed(1), w: +nodes[k].w.toFixed(1), h: +nodes[k].h.toFixed(1) } : null;
      rows.push({ shot: dev.label + '_' + theme, bad, plate: b('studio.ask'), yes: b('studio.ask.yes'), no: b('studio.ask.no'), text: nodes['studio.ask.text'] && nodes['studio.ask.text'].text });
    }
  }
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(rows, null, 1));
  for (const r of rows) console.log(r.shot + ': ' + (r.bad.length ? 'НАРУШЕНИЯ ' + r.bad.join('; ') : 'ок') + '  плашка ' + JSON.stringify(r.plate) + ' да ' + JSON.stringify(r.yes) + ' нет ' + JSON.stringify(r.no));
  if (!args.keep) for (const d of devices) if (d.own) { try { run('xcrun', ['simctl', 'shutdown', d.udid], { stdio: 'ignore' }); run('xcrun', ['simctl', 'delete', d.udid]); } catch (e) {} }
  console.log('→ ' + OUT);
  const fails = rows.flatMap(r => r.bad.map(m => `${r.shot}: ${m}`));
  if (fails.length) throw new Error('плашка: ' + fails.length + ' нарушений:\n' + fails.join('\n'));
})().catch(e => { console.error(e.message); process.exit(1); });
