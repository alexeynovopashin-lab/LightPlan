#!/usr/bin/env node
/* Шаг К1 «Клиенты»: экран «Клиенты» в обеих темах — «Частные» (все, пары, семьи, персоны), «Компании» и пустой.
   Шаг К3 (`head-*`, `form-*`): имя клиента в шапке карточки съёмки (по центру, знак «›» справа), карточка клиента из шапки
   («Назад» — в съёмку), плашка клиента в новой форме — по номеру, подсказка по имени, после «Да», у свадьбы.
   Шаг К2: карточка клиента — пара, семья, персона, подсказка «объединить?» (`twin`), лист «С кем объединить» (`pick`),
   черновик «+ Клиент» (`new`): «Назад» и поля 24, вид в карточке совпадает с выбранным, группы людей и строки съёмок во всю
   ширину полей, строк съёмок столько, сколько в итоге «N съёмок», в листе — все клиенты, кроме открытого.
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
  { name: 'card-couple', sheet: 'clientcard', way: 'couple', card: 'couple' },
  { name: 'card-family', sheet: 'clientcard', way: 'family', card: 'family' },
  { name: 'card-person', sheet: 'clientcard', way: 'person', card: 'person' },
  { name: 'card-twin', sheet: 'clientcard', way: 'twin', card: 'person' },
  { name: 'card-pick', sheet: 'clientcard', way: 'pick', card: 'couple' },
  { name: 'card-new', sheet: 'clientcard', way: 'new', card: 'person' },
  // К3: входы из съёмки.
  { name: 'head-couple', sheet: 'clienthead', way: 'couple' },
  { name: 'head-person', sheet: 'clienthead', way: 'person' },
  { name: 'head-open', sheet: 'clienthead', way: 'couple+open', card: 'couple' },
  { name: 'form-phone', sheet: 'clientform', way: 'phone', plate: 'phone' },
  { name: 'form-name', sheet: 'clientform', way: 'name', plate: 'name' },
  { name: 'form-yes', sheet: 'clientform', way: 'yes', plate: 'bound' },
  { name: 'form-couple', sheet: 'clientform', way: 'couple', plate: 'phone' },
];

const num = t => parseInt(t, 10);

const KINDS = ['couple', 'family', 'person'];

/* Карточка клиента (К2). */
function cardVerdict(c, nodes, screen) {
  const bad = [], n = k => { if (!nodes[k]) bad.push('нет узла ' + k); return nodes[k]; };
  const inFields = (r, what) => { if (r && (Math.abs(r.x - 24) > 0.6 || Math.abs(r.w - (screen.w - 48)) > 0.6)) bad.push(`${what}: x=${r.x.toFixed(1)} w=${r.w.toFixed(1)}`); };
  if (c.way === 'pick') {
    const pk = n('clc.picker');
    if (pk && num(pk.text) < 1) bad.push('в листе «С кем объединить» никого');
    for (let i = 0; i < Math.min(pk ? num(pk.text) : 0, 4); i++) {
      const r = n('clc.pick.' + i);
      if (r && Math.abs(r.h - 64) > 0.6) bad.push(`строка листа ${i}: высота ${r.h.toFixed(1)}`);
    }
    return bad;
  }
  const back = n('clc.back'), card = n('clc.card');
  if (back && Math.abs(back.x - 24) > 0.6) bad.push(`«Назад» не на поле 24: x=${back.x.toFixed(1)}`);
  if (card && card.text !== c.card) bad.push(`вид карточки ${card.text}, ждали ${c.card}`);
  n('clc.title');
  inFields(n('clc.kinds'), 'вид «Пара | Семья | Персона»');
  for (let i = 0; i < 3; i++) n('clc.kind.' + i);
  inFields(n('clc.person.0'), 'человек 1');
  const total = n('clc.total'), shoots = total ? (parseInt(total.text, 10) || 0) : 0;
  let rows = 0;
  while (nodes['clc.shoot.' + rows]) { inFields(nodes['clc.shoot.' + rows], 'съёмка ' + rows); if (Math.abs(nodes['clc.shoot.' + rows].h - 64) > 0.6) bad.push(`съёмка ${rows}: высота ≠ 64`); rows++; }
  if (rows !== shoots) bad.push(`строк съёмок ${rows}, а в итоге «${total && total.text}»`);
  if (c.way === 'new') {
    if (rows) bad.push('у черновика есть съёмки');
    if (nodes['clc.merge']) bad.push('у черновика есть «Объединить»');
    n('clc.linksEmpty');
  } else {
    if (!(rows > 0)) bad.push('у клиента из засева нет съёмок');
    n('clc.merge');
  }
  if (c.way === 'twin') inFields(n('clc.twin.0'), 'подсказка «объединить?»');
  if (c.card === 'couple' && c.way !== 'new') inFields(n('clc.person.1'), 'человек 2');
  n('clc.delete');
  return bad;
}

/* Шапка карточки съёмки (К3): имя по центру, как у веба, знак «›» справа от него и в экране; из шапки — карточка клиента
   поверх съёмки, «Назад» ведёт в неё. */
function headVerdict(c, nodes, screen) {
  const bad = [], n = k => { if (!nodes[k]) bad.push('нет узла ' + k); return nodes[k]; };
  if (c.way.includes('open')) {
    const back = n('clc.back'), card = n('clc.card');
    if (back && back.text !== 'Назад') bad.push(`«Назад» подписан «${back.text}»`);
    if (back && Math.abs(back.x - 24) > 0.6) bad.push(`«Назад» не на поле 24: x=${back.x.toFixed(1)}`);
    if (card && card.text !== c.card) bad.push(`вид карточки ${card.text}, ждали ${c.card}`);
    return bad;
  }
  const link = n('card.client'), name = n('card.name'), go = n('card.nameGo');
  if (link && !link.text) bad.push('у входа нет ключа клиента');
  if (name && Math.abs(name.x + name.w / 2 - screen.w / 2) > 1) bad.push(`имя не по центру: ${(name.x + name.w / 2).toFixed(1)} при ${screen.w / 2}`);
  if (name && go) {
    if (go.x < name.x + name.w - 0.1) bad.push('знак «›» наезжает на имя');
    if (go.x + go.w > screen.w - 16) bad.push(`знак «›» у края экрана: ${(go.x + go.w).toFixed(1)}`);
    if (Math.abs(go.y + go.h / 2 - (name.y + name.h / 2)) > 3) bad.push('знак «›» не на высоте имени');
  }
  return bad;
}

/* Плашка клиента в форме (К3): вид плашки тот, что ждали; «Да» — только у подсказки по имени, «Другой» — у подсказки и у
   выбранного, у «по номеру» кнопок нет; плашка во всю ширину группы «Клиент». */
function formVerdict(c, nodes) {
  const bad = [], n = k => { if (!nodes[k]) bad.push('нет узла ' + k); return nodes[k]; };
  const plate = n('form.client'), who = n('form.who'), text = n('form.clientText');
  if (plate && plate.text !== c.plate) bad.push(`плашка «${plate.text}», ждали «${c.plate}»`);
  if (plate && who && (Math.abs(plate.x - who.x) > 0.6 || Math.abs(plate.w - who.w) > 0.6)) bad.push(`плашка не во всю группу: x=${plate.x.toFixed(1)} w=${plate.w.toFixed(1)}`);
  if (plate && who && (plate.y < who.y - 0.1 || plate.y + plate.h > who.y + who.h + 0.1)) bad.push('плашка вне группы «Клиент»');
  const yes = !!nodes['form.clientYes'], other = !!nodes['form.clientOther'];
  if (yes !== (c.plate === 'name')) bad.push(yes ? '«Да» не у подсказки' : 'нет «Да»');
  if (other !== (c.plate !== 'phone')) bad.push(other ? '«Другой» у плашки «по номеру»' : 'нет «Другой»');
  const word = { phone: 'По номеру — ', name: 'Это ', bound: 'Это ' }[c.plate];
  if (text && !text.text.startsWith(word)) bad.push(`текст «${text.text}»`);
  if (text && (c.plate === 'name') !== text.text.includes('?')) bad.push(`вопрос не там: «${text.text}»`);
  return bad;
}

function verdict(c, nodes, screen) {
  if (c.sheet === 'clienthead') return headVerdict(c, nodes, screen);
  if (c.sheet === 'clientform') return formVerdict(c, nodes);
  if (c.sheet === 'clientcard') return cardVerdict(c, nodes, screen);
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
      // Размер экрана — `size` [w, h]; `screen` в отчёте — имя вкладки (до К3 ширина тут была NaN, и проверки ширины молчали).
      const screen = { w: rep.size[0], h: rep.size[1] };
      const bad = verdict(c, nodes, screen);
      const list = nodes['clc.picker'] || nodes['cl.list'] || nodes['org.list'];
      rows.push({ shot: c.name + '_' + theme, c: c.name, theme, bad, count: list ? num(list.text) : null });
    }
  }
  // Виды делят «Все» без остатка: пары + семьи + персоны = все.
  for (const theme of ['dark', 'light']) {
    const get = n => (rows.find(r => r.c === n && r.theme === theme) || {}).count;
    const all = get('all'), sum = get('couples') + get('families') + get('persons');
    if (all !== sum) rows.find(r => r.c === 'all' && r.theme === theme).bad.push(`виды (${sum}) не равны «Все» (${all})`);
    // В листе «С кем объединить» — все, кроме открытого.
    const pick = get('card-pick');
    if (pick !== all - 1) rows.find(r => r.c === 'card-pick' && r.theme === theme).bad.push(`в листе ${pick}, ждали ${all - 1}`);
  }
  fs.writeFileSync(path.join(OUT, 'clients-report.json'), JSON.stringify(rows, null, 1));
  for (const r of rows) console.log(r.shot + ': ' + (r.bad.length ? 'НАРУШЕНИЯ ' + r.bad.join('; ') : 'ок') + (r.count != null ? '  строк ' + r.count : ''));
  console.log('→ ' + OUT);
  const fails = rows.flatMap(r => r.bad.map(m => `${r.shot}: ${m}`));
  if (fails.length) throw new Error('клиенты: ' + fails.length + ' нарушений:\n' + fails.join('\n'));
})().catch(e => { console.error(e.message); process.exit(1); });
