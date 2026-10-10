#!/usr/bin/env node
/* «Подробно» на экране «Свет» — видна ли кнопка без прокрутки (29.2г) и куда встаёт раскрытый список (29.2г-2).
   Для каждой модели iPhone, обеих тем и четырёх текстов («спокойно», «сильный ветер», ночь с «Теней нет», «дымка» — все восемь строк) ставит
   сборку Debug на свой симулятор `LP29d <модель>`, открывает «Свет» в «Астро» (кнопка есть только там) и читает рамки
   из `-LPShotReport`, в двух видах: закрытый и раскрытый (`-LPShotSpoiler 2`: раскрыт и стоит в начале). Меряет:
     зазор  = верх узла `timebar` (нижней панели) − низ узла `spoiler` (кнопки). > 0 — кнопка видна целиком и не
              касается панели; ≤ 0 — часть под панелью или вплотную;
     раскрытый вид (узел `spoiler.list`): верх списка не ближе 8 pt к низу шапки, низ списка не ниже верха кнопки, первый
              ряд (`spoiler.g0`) не выше верха списка;
     кнопка стоит на месте: её y в закрытом и раскрытом виде одинаков (закреплена, не уезжает с прокруткой);
     «воздух» (`tele.air`): низ строки против верха закреплённого низа (кнопки, если она закреплена, иначе панели) —
              для сведения: под закреплённым низом строка достижима прокруткой.
   Красный (выход 1) — только у «современных» (15, 16, 16 Pro Max, 17, 17 Pro Max); 15 Pro Max и SE 3 печатаются
   для сведения: прокрутка там допустима (слово Алексея 09.10), но наезда быть не должно.

     node Tools/light_fit.js --app <путь к .app> [--models iPhone-15,iPhone-17] [--views closed,open] [--cases calm,wind,night,haze] [--ribbon drum|lane] [--mode simple] [--out <папка>] [--keep]

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
if (!args.app) { console.error('нужен --app <путь к .app>'); process.exit(2); }
const APP = path.resolve(args.app);
const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-light-fit'));
/* 15 Pro Max — телефон Алексея: красный и у него, хотя в списке «современных» слова от 09.10 его нет. */
const MODERN = ['iPhone-15', 'iPhone-15-Pro-Max', 'iPhone-16', 'iPhone-16-Pro-Max', 'iPhone-17', 'iPhone-17-Pro-Max'];
const MODELS = (args.models || [...MODERN, 'iPhone-SE-3rd-generation'].join(',')).split(',');
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
let red = 0;
const f1 = v => v.toFixed(1).padStart(7);
console.log('модель'.padEnd(26), 'тема'.padEnd(6), 'текст'.padEnd(6), 'вид'.padEnd(7), 'окно'.padEnd(10),
  'шапка низ', ' кнопка верх/низ', ' панель верх', '  зазор', ' список верх/низ', ' 1-й ряд', ' воздух−низ');
for (const model of MODELS) {
  const { udid, created } = device(model);
  run('xcrun', ['simctl', 'install', udid, APP]);
  const modern = MODERN.includes(model);
  for (const theme of ['dark', 'light']) for (const c of CASES) {
    let closedY = null;
    for (const view of VIEWS) {
      const j = shoot(udid, theme, c, view, path.join(OUT, model, theme + '-' + c.name + '-' + view)), n = j.nodes;
      const sp = n.spoiler, tb = n.timebar, dock = n['spoiler.dock'], list = n['spoiler.list'], g0 = n['spoiler.g0'], air = n['tele.air'];
      const head = Math.max(...['header.note', 'wx.lo', 'wx.hi', 'wx.none'].filter(k => n[k]).map(k => bottomOf(n[k])));
      const win = `${Math.round(j.size[0])}×${Math.round(j.size[1] + j.safe[0] + j.safe[1])}`.padEnd(10);
      if (args.mode === 'simple' && tb && !sp) {
        console.log(model.padEnd(26), theme.padEnd(6), c.name.padEnd(6), view.padEnd(7), win, '«Просто»: кнопки нет, панель сверху', f1(tb.y).trim()); continue;
      }
      if (!sp || !tb) { console.log(model.padEnd(26), theme.padEnd(6), c.name.padEnd(6), view.padEnd(7), win, 'нет узла spoiler/timebar'); red++; continue; }
      const gap = tb.y - bottomOf(sp);
      const why = [];
      if (gap <= 0) why.push('кнопка под панелью или вплотную');
      if (closedY === null) closedY = sp.y;
      else if (Math.abs(sp.y - closedY) > 0.5) why.push(`кнопка уехала на ${(sp.y - closedY).toFixed(1)}`);
      if (view === 'open' && list) {
        if (list.y < head + 7.5) why.push('список ближе 8 pt к низу шапки');
        if (bottomOf(list) > sp.y + 0.5) why.push('список ниже верха кнопки');
        if (g0 && g0.y < list.y - 0.5) why.push('первый ряд выше списка');
      }
      if (view === 'open' && !list) why.push('нет узла spoiler.list');
      const limit = dock ? Math.min(dock.y, tb.y) : tb.y;
      const bad = modern && why.length > 0; if (bad) red++;
      console.log(model.padEnd(26), theme.padEnd(6), c.name.padEnd(6), view.padEnd(7), win, f1(head).padStart(9),
        (f1(sp.y) + '/' + f1(bottomOf(sp)).trim()).padStart(16), f1(tb.y).padStart(12), f1(gap),
        (list ? f1(list.y) + '/' + f1(bottomOf(list)).trim() : '—').padStart(16), (g0 ? f1(g0.y) : '—').padStart(8),
        (air ? f1(bottomOf(air) - limit) : '—').padStart(11), why.length ? (modern ? ' ← красный: ' : ' ← ') + why.join('; ') : '');
    }
  }
  run('xcrun', ['simctl', 'shutdown', udid], { stdio: 'ignore' });
  if (created && !args.keep) run('xcrun', ['simctl', 'delete', udid], { stdio: 'ignore' });
}
console.log(red ? `\nна современных не сошлось в ${red} прогонах (см. «красный»)` : '\nкнопка видна, список встаёт между шапкой и кнопкой, кнопка стоит на месте — на всех современных');
process.exit(red ? 1 : 0);
