#!/usr/bin/env node
/* Шаг «Поле-2»: «На связи через» — форма «Праздник» (заполненная и свёрнутая), досье Ольга + Алёна, шапка карточки съёмки.
   Только натив: у веба такой строки нет (он заморожен). Числа — из рамок узлов (`-LPShotReport`): строка в полях 24 pt,
   кнопки отношения внутри строки, свёрнутая строка 52 pt и без полей имени и телефона; в досье два человека, у второго
   подпись «На связи · подруга»; в шапке «на связи: Алёна, подруга» и номер Алёны (звонок идёт ей, у Ольги номера нет).

     node Tools/shots/pole2.js [--skip-build] [--out <dir>] [--cases form,dossier]                                  */
const fs = require('fs'), os = require('os'), path = require('path');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const SEED = path.join(ROOT, 'Packages', 'LightPlanUI', 'Sources', 'LightPlanUI', 'Resources', 'test_seed.json');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : []).filter(x => x.length));
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const BUNDLE = 'Novopashin.LightPlan';

const CASES = [
  { name: 'form', sheet: 'poletwo', way: 'form' },
  { name: 'form-empty', sheet: 'poletwo', way: 'form-empty' },
  { name: 'dossier', sheet: 'poletwo', way: 'dossier' },
  { name: 'head', sheet: 'poletwo', way: 'head' },
];

function verdict(c, nodes, screen) {
  const bad = [], n = k => { if (!nodes[k]) bad.push('нет узла ' + k); return nodes[k]; };
  const inFields = (r, what) => { if (r && (Math.abs(r.x - 24) > 0.6 || Math.abs(r.w - (screen.w - 48)) > 0.6)) bad.push(`${what}: x=${r.x.toFixed(1)} w=${r.w.toFixed(1)}`); };
  if (c.name === 'form' || c.name === 'form-empty') {
    const via = n('form.via'), who = n('form.who');
    if (c.name === 'form') {
      const chips = n('form.via.chips'), name = n('form.viaName');
      if (via && who && (via.x < who.x - 0.1 || via.x + via.w > who.x + who.w + 0.1)) bad.push('строка вне группы «Кто»');
      if (chips && via && (chips.x < via.x + 14 || chips.x + chips.w > via.x + via.w - 14)) bad.push(`кнопки отношения вне строки: x=${chips.x.toFixed(1)} w=${chips.w.toFixed(1)}`);
      if (name && name.h < 47.9) bad.push(`поле имени ниже 48: ${name.h.toFixed(1)}`);
    } else {
      if (via && Math.abs(via.h - 52) > 0.6) bad.push(`свёрнутая строка ${via.h.toFixed(1)} ≠ 52`);
      if (nodes['form.viaName']) bad.push('в свёрнутой строке есть поле имени');
    }
  } else if (c.name === 'dossier') {
    n('clc.person.0'); n('clc.person.1');
    if (nodes['clc.person.2']) bad.push('в досье три человека');
    const l0 = n('clc.label.0'), l1 = n('clc.label.1');
    if (l0 && l0.text !== 'Человек') bad.push(`подпись героя «${l0.text}»`);
    if (l1 && l1.text !== 'На связи · подруга') bad.push(`подпись второго «${l1.text}»`);
    const title = nodes['clc.title'];
    if (title && title.text && title.text !== 'Ольга') bad.push(`имя карточки «${title.text}»`);
  } else if (c.name === 'head') {
    const v = n('card.via'), tel = n('card.tel');
    if (v && v.text !== 'на связи: Алёна, подруга') bad.push(`строка «${v.text}»`);
    if (tel && tel.text !== '+79135556677') bad.push(`звонок на ${tel.text}`);
  }
  return bad;
}

(async () => {
  const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-shots', 'pole2'));
  fs.mkdirSync(OUT, { recursive: true });
  const dd = args.dd ? path.resolve(args.dd) : path.join(OUT, 'DerivedData');
  const dev = sim.device(ROOT);
  try { run('xcrun', ['simctl', 'boot', dev.udid], { stdio: 'ignore' }); } catch (e) {}
  if (!args['skip-build']) {
    const log = path.join(OUT, 'xcodebuild-pole2.log');
    try {
      run('xcodebuild', ['-project', path.join(ROOT, 'LightPlan.xcodeproj'), '-scheme', 'LightPlan-iOS', '-configuration', 'Debug',
        '-destination', 'platform=iOS Simulator,id=' + dev.udid, '-derivedDataPath', dd, 'build'], { stdio: ['ignore', fs.openSync(log, 'w'), fs.openSync(log, 'a')] });
    } catch (e) { throw new Error('сборка упала: ' + log); }
  }
  const products = path.join(dd, 'Build', 'Products', 'Debug-iphonesimulator');
  const app = path.join(products, fs.readdirSync(products).find(f => f.endsWith('.app')));
  run('xcrun', ['simctl', 'bootstatus', dev.udid, '-b'], { stdio: 'ignore' });
  run('xcrun', ['simctl', 'install', dev.udid, app]);

  const rows = [];
  for (const theme of ['dark', 'light']) {
    run('xcrun', ['simctl', 'ui', dev.udid, 'appearance', theme]);
    const only = typeof args.cases === 'string' ? args.cases.split(',') : null;
    for (const c of CASES.filter(c => !only || only.includes(c.name))) {
      const dir = path.join(OUT, 'pole2-' + c.name + '-' + theme);
      fs.mkdirSync(dir, { recursive: true });
      const report = path.join(dir, 'native.json');
      const seedFile = path.join(dir, 'seed.json');
      fs.writeFileSync(seedFile, JSON.stringify({ ...JSON.parse(fs.readFileSync(SEED, 'utf8')), theme }));
      fs.rmSync(report, { force: true });
      try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
      run('xcrun', ['simctl', 'launch', dev.udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
        '-LPShotNow', '2026-10-23T12:00:00+07:00', '-LPShotZone', 'Asia/Tomsk', '-LPShotSeed', seedFile,
        '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
        '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'planner', '-LPShotScope', 'month',
        '-LPShotSheet', c.sheet, '-LPShotWay', c.way, ...(c.name.startsWith('form') ? ['-LPShotFormScroll', 'who'] : []), '-LPShotReportDelay', '4', '-LPShotReport', report]);
      for (let i = 0; i < 240 && !fs.existsSync(report); i++) await sleep(250);
      if (!fs.existsSync(report)) throw new Error('нет рамок: ' + dir);
      await sleep(1200);
      run('xcrun', ['simctl', 'io', dev.udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
      const rep = JSON.parse(fs.readFileSync(report, 'utf8'));
      const screen = { w: rep.size[0], h: rep.size[1] };
      rows.push({ shot: c.name + '_' + theme, bad: verdict(c, rep.nodes || {}, screen) });
    }
  }
  fs.writeFileSync(path.join(OUT, 'pole2-report.json'), JSON.stringify(rows, null, 1));
  for (const r of rows) console.log(r.shot + ': ' + (r.bad.length ? 'НАРУШЕНИЯ ' + r.bad.join('; ') : 'ок'));
  console.log('→ ' + OUT);
  const fails = rows.flatMap(r => r.bad.map(m => `${r.shot}: ${m}`));
  if (fails.length) throw new Error('Поле-2: ' + fails.length + ' нарушений:\n' + fails.join('\n'));
})().catch(e => { console.error(e.message); process.exit(1); });
