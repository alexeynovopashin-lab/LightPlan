#!/usr/bin/env node
/* Шаг 30ж.1: первый запуск только с городом и лист «Ваш номер», обе темы. Только натив: веб заморожен и спрашивает по-старому.
   Числа — из рамок узлов (`-LPShotReport`): на первом запуске нет поля номера; на листе поле и строка «зачем» в ширине экрана,
   «Готово» выключено без номера и включено с мобильным; городской номер даёт подсказку и «Готово» не включает.
   Номера в кадрах вымышленные (`ShotScenario`, `phoneask`).

     node Tools/shots/phone_sheet.js [--skip-build] [--dd <DerivedData>] [--out <dir>] [--cases start,ask,part,mobile,landline] */
const fs = require('fs'), os = require('os'), path = require('path');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : null).filter(Boolean));
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const BUNDLE = 'Novopashin.LightPlan';

const CASES = [
  { name: 'start', met: false },
  { name: 'ask', met: true, sheet: 'phoneask', done: 'off' },
  { name: 'part', met: true, sheet: 'phoneask', way: 'part', done: 'off' },
  { name: 'mobile', met: true, sheet: 'phoneask', way: 'mobile', done: 'on' },
  { name: 'landline', met: true, sheet: 'phoneask', way: 'landline', done: 'off', hint: true },
];

function verdict(c, nodes, screen) {
  const bad = [], n = k => { if (!nodes[k]) bad.push('нет узла ' + k); return nodes[k]; };
  if (c.name === 'start') {
    for (const k of ['phone.field', 'phone.why', 'phone.done.on', 'phone.done.off']) if (nodes[k]) bad.push('на первом запуске есть ' + k);
    return bad;
  }
  const field = n('phone.field'), why = n('phone.why');
  for (const [r, what] of [[field, 'поле'], [why, 'строка «зачем»']]) {
    if (r && (r.x < 0 || r.x + r.w > screen.w)) bad.push(`${what} за краем экрана: x=${r.x.toFixed(1)} w=${r.w.toFixed(1)}`);
  }
  if (field && why && why.y < field.y + field.h) bad.push('строка «зачем» налезает на поле');
  if (field && field.h < 30) bad.push(`поле ниже 30: ${field.h.toFixed(1)}`);
  n('phone.done.' + c.done);
  if (nodes['phone.done.' + (c.done === 'on' ? 'off' : 'on')]) bad.push('«Готово» не в том состоянии');
  if (c.hint) n('phone.notMobile');
  else if (nodes['phone.notMobile']) bad.push('подсказка о мобильном без причины');
  return bad;
}

(async () => {
  const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-shots', 'phone_sheet'));
  fs.mkdirSync(OUT, { recursive: true });
  const dd = args.dd ? path.resolve(args.dd) : path.join(OUT, 'DerivedData');
  const dev = sim.device(ROOT);
  try { run('xcrun', ['simctl', 'boot', dev.udid], { stdio: 'ignore' }); } catch (e) {}
  if (!args['skip-build']) {
    const log = path.join(OUT, 'xcodebuild-phone.log');
    try {
      run('xcodebuild', ['-project', path.join(ROOT, 'LightPlan.xcodeproj'), '-scheme', 'LightPlan-iOS', '-configuration', 'Debug',
        '-destination', 'platform=iOS Simulator,id=' + dev.udid, '-derivedDataPath', dd, 'build'], { stdio: ['ignore', fs.openSync(log, 'w'), fs.openSync(log, 'a')] });
    } catch (e) { throw new Error('сборка упала: ' + log); }
  }
  const products = path.join(dd, 'Build', 'Products', 'Debug-iphonesimulator');
  const app = path.join(products, fs.readdirSync(products).find(f => f.endsWith('.app')));
  run('xcrun', ['simctl', 'bootstatus', dev.udid, '-b'], { stdio: 'ignore' });
  run('xcrun', ['simctl', 'install', dev.udid, app]);

  const seed = JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8'));
  const rows = [];
  const only = typeof args.cases === 'string' ? args.cases.split(',') : null;
  for (const theme of ['dark', 'light']) {
    run('xcrun', ['simctl', 'ui', dev.udid, 'appearance', theme]);
    for (const c of CASES.filter(c => !only || only.includes(c.name))) {
      const dir = path.join(OUT, c.name + '-' + theme);
      fs.mkdirSync(dir, { recursive: true });
      const report = path.join(dir, 'native.json'), seedFile = path.join(dir, 'seed.json');
      const me = { ...(seed.me || {}), met: c.met };
      delete me.phone;
      fs.writeFileSync(seedFile, JSON.stringify({ ...seed, me, theme, telCountry: 'RU' }));
      fs.rmSync(report, { force: true });
      try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
      run('xcrun', ['simctl', 'launch', dev.udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
        '-LPShotNow', '2026-11-05T12:00:00+07:00', '-LPShotZone', 'Asia/Barnaul', '-LPShotSeed', seedFile,
        '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
        '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'light',
        ...(c.sheet ? ['-LPShotSheet', c.sheet] : []), ...(c.way ? ['-LPShotWay', c.way] : []),
        '-LPShotReportDelay', '4', '-LPShotReport', report]);
      for (let i = 0; i < 240 && !fs.existsSync(report); i++) await sleep(250);
      if (!fs.existsSync(report)) throw new Error('нет рамок: ' + dir);
      await sleep(1200);
      run('xcrun', ['simctl', 'io', dev.udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
      const rep = JSON.parse(fs.readFileSync(report, 'utf8'));
      const nodes = rep.nodes || {}, screen = { w: rep.size[0], h: rep.size[1] };
      const fmt = r => r ? `x=${r.x.toFixed(1)} y=${r.y.toFixed(1)} w=${r.w.toFixed(1)} h=${r.h.toFixed(1)}` : '—';
      rows.push({ shot: c.name + '_' + theme, screen, field: fmt(nodes['phone.field']), why: fmt(nodes['phone.why']),
        doneOn: !!nodes['phone.done.on'], doneOff: !!nodes['phone.done.off'], hint: !!nodes['phone.notMobile'], bad: verdict(c, nodes, screen) });
    }
  }
  fs.writeFileSync(path.join(OUT, 'phone-report.json'), JSON.stringify(rows, null, 1));
  for (const r of rows) console.log(`${r.shot}: поле ${r.field} · зачем ${r.why} · Готово ${r.doneOn ? 'вкл' : r.doneOff ? 'выкл' : '—'} · подсказка ${r.hint ? 'да' : 'нет'} · ${r.bad.length ? 'НАРУШЕНИЯ ' + r.bad.join('; ') : 'ок'}`);
  console.log('→ ' + OUT);
  const fails = rows.flatMap(r => r.bad.map(m => `${r.shot}: ${m}`));
  if (fails.length) throw new Error('30ж.1: ' + fails.length + ' нарушений:\n' + fails.join('\n'));
})().catch(e => { console.error(e.message); process.exit(1); });
