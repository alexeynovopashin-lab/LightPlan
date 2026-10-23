#!/usr/bin/env node
/* Шаг К1 «Клиенты»: экран «Клиенты» в обеих темах — «Частные» (все, пары, семьи, персоны), «Компании» и пустой.
   Только натив: у веба такого экрана нет (его «Организации» сверяет пара `make shots ARGS="--screens m28 --m28 orgs"`,
   узлы `org.*` остались теми же). Числа — из рамок узлов (`-LPShotReport`): поля 24 pt, строка клиента 64 pt, переключатель
   «Частные | Компании» не наезжает на «Назад» и не выходит за правое поле, фишки внутри полей, сумма по видам равна «Все».
   Засев — `test_seed.json` приложения (24 записи, свадьбы с двумя людьми): клиенты собирает тот же проход, что на телефоне.

     node Tools/shots/clients.js [--skip-build] [--out <dir>]                                                   */
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

/* sheet — что открыть (`clients` — «Частные», `orgs` — «Компании»); way — фильтр или `empty`. */
const CASES = [
  { name: 'all', sheet: 'clients', way: 'all' },
  { name: 'couples', sheet: 'clients', way: 'couples' },
  { name: 'families', sheet: 'clients', way: 'families' },
  { name: 'persons', sheet: 'clients', way: 'persons' },
  { name: 'companies', sheet: 'orgs' },
  { name: 'empty', sheet: 'clients', way: 'empty' },
];

const num = t => parseInt(t, 10);

function verdict(c, nodes, screen) {
  const bad = [], n = k => { if (!nodes[k]) bad.push('нет узла ' + k); return nodes[k]; };
  const back = n('org.back');
  if (back && Math.abs(back.x - 24) > 0.6) bad.push(`«Назад» не на поле 24: x=${back.x.toFixed(1)}`);
  if (c.sheet === 'orgs') { n('org.list'); n('cl.tabs'); }
  else {
    const tabs = n('cl.tabs');
    if (tabs && back) {
      if (tabs.x < back.x + back.w + 8 - 0.1) bad.push(`переключатель наезжает на «Назад»: ${tabs.x.toFixed(1)} < ${(back.x + back.w + 8).toFixed(1)}`);
      if (tabs.x + tabs.w > screen.w - 23.9) bad.push(`переключатель выходит за правое поле: ${(tabs.x + tabs.w).toFixed(1)}`);
      if (Math.abs(tabs.y + tabs.h / 2 - (back.y + back.h / 2)) > 6) bad.push('переключатель и «Назад» на разной высоте');
    }
    const chips = n('cl.chips');
    if (chips && (chips.x < 23.9 || chips.x + chips.w > screen.w - 23.9)) bad.push('фишки вне полей');
    if (c.way === 'empty') n('cl.empty');
    else {
      const list = n('cl.list'), count = list ? num(list.text) : 0;
      if (list && !(count > 0) && c.way === 'all') bad.push('в «Все» нет ни одной строки');
      for (let i = 0; i < Math.min(count, 5); i++) {
        const r = n('cl.row.' + i);
        if (!r) continue;
        if (Math.abs(r.x - 24) > 0.6 || Math.abs(r.w - (screen.w - 48)) > 0.6) bad.push(`строка ${i}: x=${r.x.toFixed(1)} w=${r.w.toFixed(1)}`);
        if (Math.abs(r.h - 64) > 0.6) bad.push(`строка ${i}: высота ${r.h.toFixed(1)} ≠ 64`);
      }
    }
  }
  return bad;
}

(async () => {
  const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-shots', 'clients'));
  fs.mkdirSync(OUT, { recursive: true });
  const dd = path.join(OUT, 'DerivedData');
  const dev = sim.device(ROOT);
  try { run('xcrun', ['simctl', 'boot', dev.udid], { stdio: 'ignore' }); } catch (e) {}
  if (!args['skip-build']) {
    const log = path.join(OUT, 'xcodebuild-clients.log');
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
    for (const c of CASES) {
      const dir = path.join(OUT, 'clients-' + c.name + '-' + theme);
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
        '-LPShotSheet', c.sheet, ...(c.way ? ['-LPShotWay', c.way] : []), '-LPShotReportDelay', '4', '-LPShotReport', report]);
      for (let i = 0; i < 240 && !fs.existsSync(report); i++) await sleep(250);
      if (!fs.existsSync(report)) throw new Error('нет рамок: ' + dir);
      await sleep(1200);
      run('xcrun', ['simctl', 'io', dev.udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
      const rep = JSON.parse(fs.readFileSync(report, 'utf8'));
      const nodes = rep.nodes || {};
      const screen = rep.screen || { w: 440 };
      const bad = verdict(c, nodes, screen);
      const list = nodes['cl.list'] || nodes['org.list'];
      rows.push({ shot: c.name + '_' + theme, c: c.name, theme, bad, count: list ? num(list.text) : null });
    }
  }
  // Виды делят «Все» без остатка: пары + семьи + персоны = все.
  for (const theme of ['dark', 'light']) {
    const get = n => (rows.find(r => r.c === n && r.theme === theme) || {}).count;
    const all = get('all'), sum = get('couples') + get('families') + get('persons');
    if (all !== sum) rows.find(r => r.c === 'all' && r.theme === theme).bad.push(`виды (${sum}) не равны «Все» (${all})`);
  }
  fs.writeFileSync(path.join(OUT, 'clients-report.json'), JSON.stringify(rows, null, 1));
  for (const r of rows) console.log(r.shot + ': ' + (r.bad.length ? 'НАРУШЕНИЯ ' + r.bad.join('; ') : 'ок') + (r.count != null ? '  строк ' + r.count : ''));
  console.log('→ ' + OUT);
  const fails = rows.flatMap(r => r.bad.map(m => `${r.shot}: ${m}`));
  if (fails.length) throw new Error('клиенты: ' + fails.length + ' нарушений:\n' + fails.join('\n'));
})().catch(e => { console.error(e.message); process.exit(1); });
