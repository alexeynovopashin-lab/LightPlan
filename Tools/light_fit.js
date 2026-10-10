#!/usr/bin/env node
/* «Подробно» на экране «Свет»: где стоит кнопка относительно нижней панели (29.2г) и куда раскрывается список (29.2г-3).
   Для каждой модели iPhone, обеих тем и четырёх текстов («спокойно», «сильный ветер», ночь с «Теней нет», «дымка» — все восемь строк) ставит
   сборку Debug на свой симулятор `LP29d <модель>`, открывает «Свет» в «Астро» (кнопка есть только там) и читает рамки
   из `-LPShotReport`, в двух видах: закрытый и раскрытый (`-LPShotSpoiler 2`: раскрыт и стоит в начале). Меряет:
     зазор  = верх узла `timebar` (нижней панели) − низ узла `spoiler` (кнопки). Это ИЗМЕРЕНИЕ, не условие: кнопка в
              потоке прокрутки, её видимость без прокрутки зависит от модели (слово Алексея 10.10: решит отдельно);
              ≤ 0 печатается пометкой «под панелью», красным не считается. `--min-gap <pt>` включает порог (0 — как
              требовала версия 29.2г: кнопка видна целиком);
     раскрытый вид (узлы `spoiler.list`, `spoiler.g0`): список начинается у низа кнопки (над кнопкой 0 px), шапку не
              накрывает, у него высота > 0, первый ряд есть, лежит в рамке списка и начинается у её верха
              (`--selftest` — проверка самой проверки: нормальный список и испорченные, без симулятора);
     кнопка стоит на месте: её y в закрытом и раскрытом виде одинаков;
     «воздух» (`tele.air`): низ строки против верха панели — для сведения (строка достижима прокруткой).
   Красный (выход 1) — только структура: нет узла, список вне места, кнопка уехала.

     node Tools/light_fit.js --app <путь к .app> [--models iPhone-15,iPhone-17] [--views closed,open] [--cases calm,wind,night,haze] [--ribbon drum|lane] [--mode simple] [--min-gap 0] [--out <папка>] [--keep]
     node Tools/light_fit.js --selftest

   Модели — имена `SimDeviceType`. Симуляторы по одному: два загруженных разом заклинивали `simctl launch` (16 ГБ,
   своп); после модели симулятор гасится, созданные — удаляются, если нет `--keep`. */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = {};
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a.startsWith('--')) { const k = a.slice(2), nx = process.argv[i + 1]; if (nx && !nx.startsWith('--')) { args[k] = nx; i++; } else args[k] = true; }
}
/* Проверки раскрытого списка: без высоты и первого ряда прежний прибор зеленел на пустом списке (замечание ревью 29.2г-2).
   Вход — рамки {x,y,w,h}: list, g0 (первая группа списка), sp (кнопка), head — низ шапки. Выход — список причин, пустой = зелёный. */
function listProblems(list, g0, head, sp) {
  const why = [];
  if (!list) return ['нет узла spoiler.list'];
  if (!(list.h > 0)) why.push('у списка нет высоты');
  if (!g0) why.push('нет первого ряда spoiler.g0');
  else {
    if (list.h > 0 && (g0.y + g0.h <= list.y + 0.5 || g0.y >= list.y + list.h - 0.5 || g0.h <= 0)) why.push('первый ряд вне рамки списка');
    if (Math.abs(g0.y - list.y) > 0.5) why.push(`первый ряд не у верха списка (${(g0.y - list.y).toFixed(1)})`);
  }
  const under = sp.y + sp.h;
  if (list.y < under - 0.5) why.push(`список заходит на кнопку (${(under - list.y).toFixed(1)} над её низом)`);
  else if (list.y > under + 0.5) why.push(`список не вплотную под кнопкой (зазор ${(list.y - under).toFixed(1)})`);
  if (list.y < head - 0.5) why.push('список накрывает шапку');
  return why;
}
if (args.selftest) {
  const sp = { x: 24, y: 700, w: 340, h: 43 }, head = 120;
  const ok = { x: 24, y: 743, w: 340, h: 400 }, g = { x: 24, y: 743, w: 340, h: 120 };
  const cases = [
    ['нормальный', listProblems(ok, g, head, sp), false],
    ['высота 0', listProblems({ ...ok, h: 0 }, g, head, sp), true],
    ['нет первого ряда', listProblems(ok, undefined, head, sp), true],
    ['ряд вне списка', listProblems(ok, { ...g, y: 1200 }, head, sp), true],
    ['ряд не у верха', listProblems(ok, { ...g, y: 760 }, head, sp), true],
    ['нет списка', listProblems(undefined, g, head, sp), true],
    ['растёт вверх', listProblems({ ...ok, y: 300, h: 400 }, { ...g, y: 300 }, head, sp), true],
    ['с зазором под кнопкой', listProblems({ ...ok, y: 790 }, { ...g, y: 790 }, head, sp), true],
    ['накрывает шапку', listProblems({ ...ok, y: 93 }, { ...g, y: 93 }, head, { ...sp, y: 50 }), true],
  ];
  let bad = 0;
  for (const [name, why, wantRed] of cases) {
    const okc = (why.length > 0) === wantRed; if (!okc) bad++;
    console.log((okc ? 'ok  ' : 'FAIL'), name.padEnd(22), why.length ? 'красный: ' + why.join('; ') : 'зелёный');
  }
  process.exit(bad ? 1 : 0);
}
if (!args.app) { console.error('нужен --app <путь к .app>'); process.exit(2); }
const APP = path.resolve(args.app);
const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-light-fit'));
/* 15 Pro Max — телефон Алексея; SE 3 — для сведения (прокрутка там допустима, слово Алексея 09.10). */
const ALL = ['iPhone-15', 'iPhone-15-Pro-Max', 'iPhone-16', 'iPhone-16-Pro-Max', 'iPhone-17', 'iPhone-17-Pro-Max', 'iPhone-SE-3rd-generation'];
const MODELS = (args.models || ALL.join(',')).split(',');
const MIN_GAP = args['min-gap'] === undefined ? null : Number(args['min-gap']);
const VIEWS = (args.views || 'closed,open').split(',');
const RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-26-5';
const BUNDLE = 'Novopashin.LightPlan';
const run = (c, a, o = {}) => execFileSync(c, a, { encoding: 'utf8', ...o });
const sleep = s => execFileSync('sleep', [String(s)]);
fs.mkdirSync(OUT, { recursive: true });

/* Прогноз с сильным ветром на все дни посева: «16 м/с · сильный · с ЮЗ · порывы 28» — самая длинная строка ветра. */
const windForecast = path.join(OUT, 'forecast_wind.json');
{
  const d = JSON.parse(fs.readFileSync(path.join(FX, 'forecast_barnaul.json'), 'utf8')), h = d.hourly;
  h.time.forEach((t, i) => { if (t.startsWith('2026-09-2')) { h.wind_speed_10m[i] = 16; h.wind_gusts_10m[i] = 28; h.wind_direction_10m[i] = 225; } });
  fs.writeFileSync(windForecast, JSON.stringify(d));
}
/* Строка «Воздух» (`tele.air`) есть только при дымке/дыме/пыли («прозрачный воздух не новость, о нём молчим»): в
   посеве воздух чистый, и в замере 29.2г её не было вовсе (+35 pt, строка 14 pt + поля 9·9 + волосок). Для случая `haze`
   воздух с дымкой (оптическая толща 0,4 — порог слова 0,35) на все часы. */
const hazeAir = path.join(OUT, 'air_haze.json');
{
  const d = JSON.parse(fs.readFileSync(path.join(FX, 'air_barnaul.json'), 'utf8'));
  d.hourly.aerosol_optical_depth = d.hourly.time.map(() => 0.4);
  fs.writeFileSync(hazeAir, JSON.stringify(d));
}
const CLEAN_AIR = path.join(FX, 'air_barnaul.json');
const CASES = [
  { name: 'calm', at: '2026-09-23T13:00', forecast: path.join(FX, 'forecast_barnaul.json'), air: CLEAN_AIR },
  { name: 'wind', at: '2026-09-23T13:00', forecast: windForecast, air: CLEAN_AIR },
  { name: 'night', at: '2026-09-23T23:00', forecast: path.join(FX, 'forecast_barnaul.json'), air: CLEAN_AIR },
  /* Все восемь строк разом и самый длинный ветер: самый высокий экран. */
  { name: 'haze', at: '2026-09-23T13:00', forecast: windForecast, air: hazeAir },
].filter(c => !args.cases || args.cases.split(',').includes(c.name));

function device(model) {
  const name = 'LP29d ' + model;
  const all = () => Object.values(JSON.parse(run('xcrun', ['simctl', 'list', 'devices', '-j'])).devices).flat();
  let d = all().find(x => x.name === name), created = false;
  if (!d) {
    run('xcrun', ['simctl', 'create', name, 'com.apple.CoreSimulator.SimDeviceType.' + model, RUNTIME]); created = true;
    d = all().find(x => x.name === name);
  }
  /* Два загруженных симулятора разом заклинивают `simctl launch` (замер 29.2г-2): чужие `LP29d …` гасим. */
  for (const o of all()) if (o.name.startsWith('LP29d ') && o.udid !== d.udid && o.state === 'Booted') {
    try { run('xcrun', ['simctl', 'shutdown', o.udid], { stdio: 'ignore', timeout: 60000 }); } catch (e) {}
  }
  if (d.state !== 'Booted') { try { run('xcrun', ['simctl', 'boot', d.udid]); } catch (e) {} run('xcrun', ['simctl', 'bootstatus', d.udid, '-b'], { stdio: 'ignore' }); }
  return { udid: d.udid, created };
}

function shoot(udid, theme, c, view, dir) {
  fs.mkdirSync(dir, { recursive: true });
  const seed = { ...JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8')), theme, pro: args.mode !== 'simple', drumSlot: 'paper', ribbonMode: args.ribbon || 'drum' };
  const sf = path.join(dir, 'seed.json'); fs.writeFileSync(sf, JSON.stringify(seed));
  const rep = path.join(dir, 'native.json');
  run('xcrun', ['simctl', 'ui', udid, 'appearance', theme], { timeout: 30000 });
  /* Редко приложение не пишет рамки (запуск потерян на загруженном симуляторе) — один повтор, не весь прогон заново. */
  for (let attempt = 0; attempt < 3; attempt++) {
    fs.rmSync(rep, { force: true });
    try { run('xcrun', ['simctl', 'terminate', udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
    try {
      run('xcrun', ['simctl', 'launch', udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
        '-LPShotNow', c.at + ':00+07:00', '-LPShotZone', 'Asia/Barnaul', '-LPShotSeed', sf, '-LPShotForecast', c.forecast,
        '-LPShotAir', c.air, '-LPShotName', path.join(FX, 'place_barnaul.json'),
        '-LPShotScreen', 'light', '-LPShotReport', rep, ...(view === 'open' ? ['-LPShotSpoiler', '2'] : [])],
        { env: { ...process.env, SIMCTL_CHILD_TZ: 'Asia/Barnaul' }, timeout: 90000 });
    } catch (e) {
      if (attempt >= 2) throw e;
      /* Запуск завис (рядом загружен чужой симулятор): перезагрузить свой и повторить. */
      try { run('xcrun', ['simctl', 'shutdown', udid], { stdio: 'ignore', timeout: 60000 }); } catch (e2) {}
      try { run('xcrun', ['simctl', 'boot', udid], { stdio: 'ignore', timeout: 60000 }); run('xcrun', ['simctl', 'bootstatus', udid, '-b'], { stdio: 'ignore', timeout: 120000 }); } catch (e2) {}
      continue;
    }
    for (let i = 0; i < 160 && !fs.existsSync(rep); i++) sleep(0.25);
    if (fs.existsSync(rep)) break;
    if (attempt >= 2) throw new Error('приложение не написало рамки: ' + dir);
  }
  sleep(1);
  return JSON.parse(fs.readFileSync(rep, 'utf8'));
}

const bottomOf = n => n.y + n.h;
let red = 0, under = 0, runs = 0;
const f1 = v => v.toFixed(1).padStart(7);
console.log('модель'.padEnd(26), 'тема'.padEnd(6), 'текст'.padEnd(6), 'вид'.padEnd(7), 'окно'.padEnd(10),
  'шапка низ', ' кнопка верх/низ', ' панель верх', '  зазор', ' список верх/низ', ' 1-й ряд', ' воздух−панель');
for (const model of MODELS) {
  const { udid, created } = device(model);
  run('xcrun', ['simctl', 'install', udid, APP]);
  for (const theme of ['dark', 'light']) for (const c of CASES) {
    let closedY = null;
    for (const view of VIEWS) {
      const j = shoot(udid, theme, c, view, path.join(OUT, model, theme + '-' + c.name + '-' + view)), n = j.nodes;
      const sp = n.spoiler, tb = n.timebar, list = n['spoiler.list'], g0 = n['spoiler.g0'], air = n['tele.air'];
      const head = Math.max(...['header.note', 'wx.lo', 'wx.hi', 'wx.none'].filter(k => n[k]).map(k => bottomOf(n[k])));
      const win = `${Math.round(j.size[0])}×${Math.round(j.size[1] + j.safe[0] + j.safe[1])}`.padEnd(10);
      runs++;
      if (args.mode === 'simple' && tb && !sp) {
        console.log(model.padEnd(26), theme.padEnd(6), c.name.padEnd(6), view.padEnd(7), win, '«Просто»: кнопки нет, панель сверху', f1(tb.y).trim()); continue;
      }
      if (!sp || !tb) { console.log(model.padEnd(26), theme.padEnd(6), c.name.padEnd(6), view.padEnd(7), win, 'нет узла spoiler/timebar'); red++; continue; }
      const gap = tb.y - bottomOf(sp);
      const why = [], note = [];
      if (gap <= 0) { note.push('под панелью'); if (view === 'closed' || VIEWS.length === 1) under++; }
      if (MIN_GAP !== null && gap < MIN_GAP) why.push(`зазор ${gap.toFixed(1)} < ${MIN_GAP}`);
      if (closedY === null) closedY = sp.y;
      else if (Math.abs(sp.y - closedY) > 0.5) why.push(`кнопка уехала на ${(sp.y - closedY).toFixed(1)}`);
      if (view === 'open') why.push(...listProblems(list, g0, head, sp));
      if (why.length) red++;
      console.log(model.padEnd(26), theme.padEnd(6), c.name.padEnd(6), view.padEnd(7), win, f1(head).padStart(9),
        (f1(sp.y) + '/' + f1(bottomOf(sp)).trim()).padStart(16), f1(tb.y).padStart(12), f1(gap),
        (list ? f1(list.y) + '/' + f1(bottomOf(list)).trim() : '—').padStart(16), (g0 ? f1(g0.y) : '—').padStart(8),
        (air ? f1(bottomOf(air) - tb.y) : '—').padStart(13),
        why.length ? ' ← красный: ' + why.join('; ') : note.length ? ' · ' + note.join('; ') : '');
    }
  }
  run('xcrun', ['simctl', 'shutdown', udid], { stdio: 'ignore' });
  if (created && !args.keep) run('xcrun', ['simctl', 'delete', udid], { stdio: 'ignore' });
}
console.log(red ? `\nне сошлось в ${red} из ${runs} прогонов (см. «красный»)`
  : `\nсписок встаёт под кнопкой, шапку не накрывает, кнопка стоит на месте — во всех ${runs} прогонах; кнопка под панелью в ${under} (для сведения)`);
process.exit(red ? 1 : 0);
