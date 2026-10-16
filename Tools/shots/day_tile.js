#!/usr/bin/env node
/* Шаг 29.11в: плитка дня в карточке съёмки — вид с лентой и вид списком (когда ленты нет). Только натив: веб (заморожен)
   списка не знает, пары быть не может.

   Состояния (записи 15 октября, четверг, Томсон/Эдисон, на сид «Съёмок» дописаны здесь же):
     one-before/-during/-after  одна точка «Фотостудия» 12:00–12:30 — до, во время, после
     three-after/-during        три точки (Сборы, Фотостудия, Прогулка) — лента, вид не меняется
     nohall                     одна точка без зала и адреса
     notime                     точка с часом + точка без часа
     long                       длинное название точки (перенос)
   Темы light/dark; экраны: iPhone 17 Pro Max (440 pt) и iPhone SE 3-го поколения (375 pt).

   Числа — по каждому снимку: высота плитки `card.day` (pt) и доля пустоты (`day_tile_void.py`: площадь плитки без
   чернил текста и знаков, чернила расширены на 4 pt). Правила: ни один узел `card.dayRow.*` не выходит за плитку,
   у вида списком нет `card.lane`, у вида с лентой нет `card.dayRow.*`.

     node Tools/shots/day_tile.js [--skip-build] [--out <dir>] [--sims max,se] [--only one-after,three-after]
                                  [--themes light,dark] [--app <.app>]                                                      */
const fs = require('fs'), os = require('os'), path = require('path');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : []).filter(x => x.length));
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const BUNDLE = 'Novopashin.LightPlan', ZONE = 'Asia/Barnaul';

const DEVICES = { max: { model: 'iPhone 17 Pro Max', suffix: '', pt: 440, ht: 956 }, se: { model: 'iPhone SE (3rd generation)', suffix: ' se', pt: 375, ht: 667 } };

function simFor(key) {
  const d = DEVICES[key];
  const name = sim.nameFor(ROOT) + d.suffix;
  const lists = JSON.parse(run('xcrun', ['simctl', 'list', 'devices', 'available', '-j'])).devices;
  for (const l of Object.values(lists)) for (const x of l) if (x.name === name) return x.udid;
  const rt = Object.keys(lists).find(k => lists[k].some(x => x.name === 'iPhone 17 Pro Max'));
  return run('xcrun', ['simctl', 'create', name, d.model, rt]).trim();
}

const STUDIO = (n, t, t2, p) => ({ t, t2, n, p, placeId: null, studioId: 'sd_st_tomson', hallId: 'sd_h_edison' });
const HALL = 'Томсон, зал Эдисон';
const LONG = 'Свадебная фотосессия с родителями невесты и жениха на набережной';
// Состояния: id → маршрут записи и фаза (когда «сейчас» относительно 12:00–12:30).
const STATES = {
  'one-before':   { phase: 'before', route: [STUDIO('Фотостудия', 720, 750, HALL)] },
  'one-during':   { phase: 'during', route: [STUDIO('Фотостудия', 720, 750, HALL)] },
  'one-after':    { phase: 'after',  route: [STUDIO('Фотостудия', 720, 750, HALL)] },
  'three-during': { phase: 'during', route: threeRoute() },
  'three-after':  { phase: 'after',  route: threeRoute() },
  'nohall':       { phase: 'after',  route: [{ t: 720, t2: 750, n: 'Фотостудия', p: '', placeId: null, studioId: null, hallId: null }] },
  'notime':       { phase: 'after',  route: [STUDIO('Фотостудия', 720, 750, HALL), { n: 'Прогулка', p: 'Лагерный сад', placeId: null, studioId: null, hallId: null }] },
  'long':         { phase: 'after',  route: [STUDIO(LONG, 720, 750, HALL)] },
};
function threeRoute() {
  return [{ t: 600, t2: 660, n: 'Сборы', p: 'Дом невесты', placeId: null, studioId: null, hallId: null },
    STUDIO('Фотостудия', 720, 750, HALL),
    { t: 840, t2: 900, n: 'Прогулка', p: 'Лагерный сад', placeId: null, studioId: null, hallId: null }];
}
const DAY_MIDNIGHT = '2026-10-14T17:00:00.000Z';   // 15 октября 00:00 по Барнаулу
const wallAt = m => new Date(Date.parse(DAY_MIDNIGHT) + 7 * 3600e3 + m * 60e3).toISOString().slice(0, 16);
const NOW = { before: 600, during: 735, after: 830 };   // 10:00, 12:15, 13:50

(async () => {
  const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-shots', 'day-tile'));
  fs.mkdirSync(OUT, { recursive: true });
  const keys = (args.sims || 'max,se').split(',');
  const themes = (args.themes || 'light,dark').split(',');
  const only = args.only && args.only !== true ? args.only.split(',') : Object.keys(STATES);
  const dd = path.join(OUT, 'DerivedData');
  const udids = Object.fromEntries(keys.map(k => [k, simFor(k)]));
  if (!args['skip-build']) {
    const log = path.join(OUT, 'xcodebuild.log');
    try {
      run('xcodebuild', ['-project', path.join(ROOT, 'LightPlan.xcodeproj'), '-scheme', 'LightPlan-iOS', '-configuration', 'Debug',
        '-destination', 'platform=iOS Simulator,id=' + udids[keys[0]], '-derivedDataPath', dd, 'build'], { stdio: ['ignore', fs.openSync(log, 'w'), fs.openSync(log, 'a')] });
    } catch (e) { throw new Error('сборка упала: ' + log); }
  }
  const products = path.join(dd, 'Build', 'Products', 'Debug-iphonesimulator');
  const app = args.app && args.app !== true ? path.resolve(args.app) : path.join(products, fs.readdirSync(products).find(f => f.endsWith('.app')));

  const plannerSeed = JSON.parse(fs.readFileSync(path.join(FX, 'seed_planner.json'), 'utf8'));
  const base = plannerSeed.sessions.find(x => x.id === 'sd_sep_now');
  const rows = [], bad = [];
  for (const key of keys) {
    const udid = udids[key];
    try { run('xcrun', ['simctl', 'boot', udid], { stdio: 'ignore' }); } catch (e) {}
    run('xcrun', ['simctl', 'install', udid, app]);
    for (const theme of themes) {
      run('xcrun', ['simctl', 'ui', udid, 'appearance', theme]);
      const sessions = [...plannerSeed.sessions, ...Object.entries(STATES).map(([id, st]) =>
        ({ ...base, id: 'dt_' + id, date: DAY_MIDNIGHT, min: 720, dur: 30, end: 750, contact: 'Тест плитки', persons: [], route: st.route,
          // Без студии на записи: «студийный час» над плиткой во время съёмки сдвигает её за низ узкого экрана.
          ...(st.phase === 'during' ? { studioId: null, hallId: null } : {}) }))];
      const seedFile = path.join(OUT, `seed-${theme}.json`);
      fs.writeFileSync(seedFile, JSON.stringify({ ...plannerSeed, sessions, theme, pro: false, drumSlot: 'paper', ribbonMode: 'drum' }));
      for (const id of only) {
        const st = STATES[id];
        // «Во время» на узком экране: над плиткой встаёт круг студийного часа, плитка уезжает за низ (667 pt) — не снимается.
        if (key === 'se' && st.phase === 'during') continue;
        const dir = path.join(OUT, `${id}-${theme}-${key}`);
        fs.mkdirSync(dir, { recursive: true });
        const report = path.join(dir, 'native.json');
        fs.rmSync(report, { force: true });
        try { run('xcrun', ['simctl', 'terminate', udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
        run('xcrun', ['simctl', 'status_bar', udid, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100', '--cellularBars', '4', '--wifiBars', '3'], { stdio: 'ignore' });
        run('xcrun', ['simctl', 'launch', udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
          '-LPShotNow', wallAt(NOW[st.phase]) + ':00+07:00', '-LPShotZone', ZONE, '-LPShotSeed', seedFile,
          '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
          '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'planner',
          '-LPShotSheet', 'card', '-LPShotWay', 'dt_' + id, '-LPShotReport', report], { env: { ...process.env, SIMCTL_CHILD_TZ: ZONE } });
        for (let i = 0; i < 240 && !fs.existsSync(report); i++) await sleep(250);
        if (!fs.existsSync(report)) throw new Error('нет рамок: ' + dir);
        await sleep(1200);
        const png = path.join(dir, 'native.png');
        run('xcrun', ['simctl', 'io', udid, 'screenshot', '--type=png', png], { stdio: 'ignore' });
        const nodes = JSON.parse(fs.readFileSync(report, 'utf8')).nodes || {};
        const day = nodes['card.day'];
        if (!day) { bad.push(`${id}-${theme}-${key}: нет узла card.day`); continue; }
        if (day.y + day.h > DEVICES[key].ht) bad.push(`${id}-${theme}-${key}: плитка ниже экрана (низ ${Math.round(day.y + day.h)} > ${DEVICES[key].ht})`);
        const rowsN = Object.keys(nodes).filter(k => /^card\.dayRow\.\d+$/.test(k));
        const hasLane = !!nodes['card.lane'];
        const m = JSON.parse(run('python3', [path.join(__dirname, 'day_tile_void.py'), png, String(day.x), String(day.y), String(day.w), String(day.h), String(DEVICES[key].pt),
          path.join(dir, 'tile.png')]));
        const row = { state: id, theme, device: key, phase: st.phase, h: +day.h.toFixed(1), w: +day.w.toFixed(1), void: m.void, lane: hasLane, rows: rowsN.length };
        // Ограды: ряды внутри плитки; лента и ряды не вместе.
        for (const k of rowsN) {
          const r = nodes[k];
          if (r.x < day.x - 0.5 || r.x + r.w > day.x + day.w + 0.5 || r.y < day.y - 0.5 || r.y + r.h > day.y + day.h + 0.5) bad.push(`${id}-${theme}-${key}: ${k} вне плитки`);
        }
        if (hasLane && rowsN.length) bad.push(`${id}-${theme}-${key}: и лента, и ряды`);
        rows.push(row);
        console.log(JSON.stringify(row));
      }
    }
    try { run('xcrun', ['simctl', 'status_bar', udid, 'clear'], { stdio: 'ignore' }); } catch (e) {}
  }
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(rows, null, 1));
  console.log('→ ' + OUT);
  if (bad.length) { console.error(bad.join('\n')); process.exit(1); }
})().catch(e => { console.error(e.message); process.exit(1); });
