#!/usr/bin/env node
/* Шаг 28о: форма новой съёмки при черновике другого дня. Только натив: у веба (заморожен)
   порядка блоков и окна вопроса нет, пары быть не может.

   Состояния (`LPShotDraft` в ShotScenario): ask — окно «Продолжить черновик от 27 сентября или
   начать новую на 29 октября?» над «Съёмками»; continue — черновик открыт, плашка называет день;
   new — чистая форма на 29 октября. `warn` — форма на 24 сентября, 15:00, без черновика (внахлёст со свадьбой «Лена и Тимур»
   11:00–22:00: предупреждение о времени под датой). Темы light, dark.

   Экран — iPhone 17 Pro (402 × 874), свой симулятор `LP <ветка> pro`. Числа: порядок блоков по y,
   дата и время без прокрутки (низ капсулы выше низа экрана минус нижний отступ 34 pt).

     node Tools/shots/draft_day.js [--skip-build] [--out <dir>]                    */
const fs = require('fs'), os = require('os'), path = require('path');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : []).filter(x => x.length));
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const BUNDLE = 'Novopashin.LightPlan', ZONE = 'Asia/Barnaul', SCREEN_H = 874, HOME_BAR = 34;

function proSim() {
  const name = sim.nameFor(ROOT) + ' pro';
  const lists = JSON.parse(run('xcrun', ['simctl', 'list', 'devices', 'available', '-j'])).devices;
  for (const [rt, l] of Object.entries(lists)) for (const d of l) if (d.name === name) return d.udid;
  const rt = Object.keys(lists).find(k => lists[k].some(d => d.name === 'iPhone 17 Pro Max'));
  return run('xcrun', ['simctl', 'create', name, 'iPhone 17 Pro', rt]).trim();
}

(async () => {
  const udid = proSim();
  try { run('xcrun', ['simctl', 'boot', udid], { stdio: 'ignore' }); } catch (e) {}
  const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-shots', 'draft-day'));
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

  const seed = JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8'));
  const plannerSeed = JSON.parse(fs.readFileSync(path.join(FX, 'seed_planner.json'), 'utf8'));   // для `warn`: записи сезона
  const states = [['ask', ['-LPShotDraft', 'ask']], ['continue', ['-LPShotDraft', 'continue']],
    ['new', ['-LPShotDraft', 'new']], ['warn', ['-LPShotFormDay', '2026-09-24', '-LPShotFormStart', '900']]];
  const rows = [];
  for (const theme of ['light', 'dark']) for (const [state, extra] of states) {
    const dir = path.join(OUT, state + '-' + theme);
    fs.mkdirSync(dir, { recursive: true });
    const seedFile = path.join(dir, 'seed.json');
    fs.writeFileSync(seedFile, JSON.stringify({ ...(state === 'warn' ? plannerSeed : seed), theme, pro: false, drumSlot: 'paper', ribbonMode: 'drum' }));
    const report = path.join(dir, 'native.json');
    fs.rmSync(report, { force: true });
    try { run('xcrun', ['simctl', 'terminate', udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
    run('xcrun', ['simctl', 'ui', udid, 'appearance', theme]);
    run('xcrun', ['simctl', 'launch', udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
      '-LPShotNow', '2026-09-23T13:00:00+07:00', '-LPShotZone', ZONE, '-LPShotSeed', seedFile,
      '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
      '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'planner', '-LPShotSheet', 'form', ...extra,
      '-LPShotReport', report], { env: { ...process.env, SIMCTL_CHILD_TZ: ZONE } });
    for (let i = 0; i < 240 && !fs.existsSync(report); i++) await sleep(250);
    if (!fs.existsSync(report)) throw new Error('нет рамок: ' + state + '-' + theme);
    await sleep(1500);   // окно вопроса (UIAlert) выезжает после первого кадра
    run('xcrun', ['simctl', 'io', udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
    const nodes = JSON.parse(fs.readFileSync(report, 'utf8')).nodes || {};
    const r = k => nodes[k] ? { y: +nodes[k].y.toFixed(1), bottom: +(nodes[k].y + nodes[k].h).toFixed(1) } : null;
    const row = { state, theme, title: nodes['form.title'] && nodes['form.title'].text,
      genre: r('form.genre'), startDate: r('form.startDate'), startVal: r('form.startVal'), who: r('form.who'), warn: r('form.wishWarn') };
    const limit = SCREEN_H - HOME_BAR;
    if (row.startDate) row.dateVisible = row.startDate.bottom <= limit && row.startVal.bottom <= limit;
    if (row.genre && row.startDate && row.who) row.orderOk = row.genre.y < row.startDate.y && row.startDate.y < row.who.y;
    if (row.warn && row.startDate && row.who) row.warnBetween = row.startDate.bottom <= row.warn.y && row.warn.bottom <= row.who.y;
    rows.push(row);
  }
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(rows, null, 1));
  for (const r of rows) console.log(JSON.stringify(r));
  console.log('→ ' + OUT);
})().catch(e => { console.error(e.message); process.exit(1); });
