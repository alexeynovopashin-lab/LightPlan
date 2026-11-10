#!/usr/bin/env node
/* Шаг 30е.1: общий список студий в листе «Фотостудия». Только натив: у веба списка нет.
   Список в кадрах — выдуманный (`-LPShotCatalog demo`, `ShotScenario.demoCatalog`): Томсон и придуманные места,
   настоящий файл в кадры не идёт. Набранное в поиске — `-LPShotCatalogQuery`, выбор первой строки — `-LPShotCatalogPick 1`.
   Сцены: `none` — списка нет, лист как до шага; `hint` — список есть, ничего не набрано; `tomsk` — набрано «томс»
   (город съёмки и другой город); `hall` — «лофт»: в Томске по залу, в другом городе по названию; `picked` — первая строка выбрана: галочка у строки (третье поле текста рамки «выбрана»).
   Числа из рамок узлов (`-LPShotReport`): узлы внутри экрана по ширине, строки не накладываются и не ниже 44 pt,
   пометки по строкам те, что задумано (Томсон «проверена», выдуманные «не проверена»/«возможно, дубль»), закрытой нет,
   пояснение под последней строкой; без списка нет ни одного узла `loc.catalog*`. Нарушение — код 1.
   Темы dark и light, симулятор ветки.

     node Tools/shots/studio_list.js [--skip-build] [--only a,b] [--out <dir>]                                      */
const fs = require('fs'), os = require('os'), path = require('path');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : []).filter(x => x.length));
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const BUNDLE = 'Novopashin.LightPlan';

// `rows` — что ждём в выдаче: секция (`here`/`other`) → [название, пометка]. Пометка — слово пилюли.
const SCENES = [
  { name: 'none', catalog: false },
  { name: 'hint', catalog: true, query: '' },
  { name: 'tomsk', catalog: true, query: 'томс', rows: {
      here: [['Томсон', '✓ проверена'], ['Ромашка', 'не проверена'], ['Белый свет', 'возможно, дубль — сверьте адрес']],
      other: [['Томский лофт', 'не проверена']] } },
  { name: 'hall', catalog: true, query: 'лофт', rows: { here: [['Белый свет', 'возможно, дубль — сверьте адрес']], other: [['Томский лофт', 'не проверена']] } },
  { name: 'picked', catalog: true, query: 'томсон', pick: true, rows: { here: [['Томсон', '✓ проверена']], other: [] } },
];

function verdict(sc, nodes, screen) {
  const bad = [];
  const keys = Object.keys(nodes);
  const cat = keys.filter(k => k.startsWith('loc.catalog'));
  for (const k of keys.filter(k => k.startsWith('loc.'))) {
    const b = nodes[k];
    if (b.x < -0.5 || b.x + b.w > screen.w + 0.5) bad.push(`${k} выходит за экран: ${b.x.toFixed(1)}…${(b.x + b.w).toFixed(1)}`);
  }
  if (!sc.catalog) { if (cat.length) bad.push('без списка есть узлы ' + cat.join(', ')); return bad; }
  if (sc.query === '' && !nodes['loc.catalogHint']) bad.push('нет строки-подсказки с числом студий');
  if (sc.rows) {
    const all = [];
    for (const sec of ['here', 'other']) {
      const want = sc.rows[sec];
      const got = keys.filter(k => k.startsWith(`loc.catalog.${sec}.`)).sort((a, b) => nodes[a].y - nodes[b].y);
      if (got.length !== want.length) bad.push(`${sec}: строк ${got.length}, ждали ${want.length}`);
      want.forEach(([name, mark], i) => {
        const n = nodes[got[i]];
        if (!n) return;
        const [gn, gm, gp] = (n.text || '').split('|');
        if (!!gp !== !!(sc.pick && sec === 'here' && i === 0)) bad.push(`${sec}.${i} «${gn}»: ${gp ? 'выбрана, а не должна' : 'не выбрана'}`);
        if (gn !== name) bad.push(`${sec}.${i}: «${gn}», ждали «${name}»`);
        if (gm !== mark) bad.push(`${sec}.${i} «${gn}»: пометка «${gm}», ждали «${mark}»`);
        if (n.h < 43.9) bad.push(`${sec}.${i}: высота ${n.h.toFixed(1)} < 44`);
        all.push(n);
      });
    }
    if (keys.some(k => (nodes[k].text || '').startsWith('Закрытая'))) bad.push('закрытая студия в выдаче');
    all.sort((a, b) => a.y - b.y).forEach((n, i, a) => { if (i && a[i - 1].y + a[i - 1].h > n.y + 0.5) bad.push(`строки ${i - 1} и ${i} накладываются`); });
    const note = nodes['loc.catalogNote'];
    if (!note) bad.push('нет пояснения под списком');
    else if (all.length && note.y < Math.max(...all.map(n => n.y + n.h)) - 0.5) bad.push('пояснение не под последней строкой');
  }
  if (sc.pick && !nodes['loc.done']) bad.push('нет «Готово» после выбора');
  return bad;
}

(async () => {
  const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-shots', 'studio_list'));
  fs.mkdirSync(OUT, { recursive: true });
  const dd = path.join(OUT, 'DerivedData');
  const dev = sim.device(ROOT);
  try { run('xcrun', ['simctl', 'boot', dev.udid], { stdio: 'ignore' }); } catch (e) {}
  if (!args['skip-build']) {
    const log = path.join(OUT, 'xcodebuild.log');
    try {
      run('xcodebuild', ['-project', path.join(ROOT, 'LightPlan.xcodeproj'), '-scheme', 'LightPlan-iOS', '-configuration', 'Debug',
        '-destination', 'platform=iOS Simulator,id=' + dev.udid, '-derivedDataPath', dd, 'build'], { stdio: ['ignore', fs.openSync(log, 'w'), fs.openSync(log, 'a')] });
    } catch (e) { throw new Error('сборка упала: ' + log); }
  }
  const products = path.join(dd, 'Build', 'Products', 'Debug-iphonesimulator');
  const app = path.join(products, fs.readdirSync(products).find(f => f.endsWith('.app')));
  run('xcrun', ['simctl', 'bootstatus', dev.udid, '-b'], { stdio: 'ignore' });
  run('xcrun', ['simctl', 'install', dev.udid, app]);
  const only = args.only ? String(args.only).split(',') : null;
  const rows = [];
  for (const sc of SCENES.filter(s => !only || only.includes(s.name))) {
    for (const theme of ['dark', 'light']) {
      run('xcrun', ['simctl', 'ui', dev.udid, 'appearance', theme]);
      const dir = path.join(OUT, sc.name + '_' + theme);
      fs.mkdirSync(dir, { recursive: true });
      const report = path.join(dir, 'native.json');
      const seedFile = path.join(dir, 'seed.json');
      fs.writeFileSync(seedFile, JSON.stringify({ ...JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8')), theme }));
      fs.rmSync(report, { force: true });
      try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
      const extra = [];
      if (sc.catalog) extra.push('-LPShotCatalog', 'demo', '-LPShotCatalogQuery', sc.query);
      else extra.push('-LPShotCatalog', 'off');
      extra.push('-LPShotCatalogPick', sc.pick ? '1' : '0');
      run('xcrun', ['simctl', 'launch', dev.udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
        '-LPShotNow', '2026-10-20T12:00:00+07:00', '-LPShotZone', 'Asia/Tomsk', '-LPShotSeed', seedFile,
        '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
        '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'planner', '-LPShotSheet', 'form',
        '-LPShotFormStudio', '1', '-LPShotFormCity', 'Томск', '-LPShotReportDelay', '5', '-LPShotReport', report, ...extra]);
      for (let i = 0; i < 240 && !fs.existsSync(report); i++) await sleep(250);
      if (!fs.existsSync(report)) throw new Error('нет рамок: ' + dir);
      await sleep(800);
      run('xcrun', ['simctl', 'io', dev.udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
      const rep = JSON.parse(fs.readFileSync(report, 'utf8'));
      const nodes = rep.nodes || {};
      const screen = { w: (rep.size || [])[0] };
      if (!screen.w) throw new Error('в рамках нет ширины экрана: ' + report);
      const bad = verdict(sc, nodes, screen);
      const list = Object.keys(nodes).filter(k => k.startsWith('loc.catalog.')).sort((a, b) => nodes[a].y - nodes[b].y)
        .map(k => `${k.slice(12)} y${nodes[k].y.toFixed(0)} h${nodes[k].h.toFixed(1)} «${nodes[k].text || ''}»`);
      rows.push({ shot: sc.name + '_' + theme, bad, list });
    }
  }
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(rows, null, 1));
  for (const r of rows) console.log(r.shot + ': ' + (r.bad.length ? 'НАРУШЕНИЯ ' + r.bad.join('; ') : 'ок') + (r.list.length ? '\n   ' + r.list.join('\n   ') : ''));
  console.log('→ ' + OUT);
  const fails = rows.flatMap(r => r.bad.map(m => `${r.shot}: ${m}`));
  if (fails.length) throw new Error('список студий: ' + fails.length + ' нарушений');
})().catch(e => { console.error(e.message); process.exit(1); });
