#!/usr/bin/env node
/* «Подробно» на экране «Свет» — видна ли кнопка без прокрутки (29.2г).
   Для каждой модели iPhone, обеих тем и трёх текстов («спокойно», «сильный ветер», ночь с «Теней нет») ставит
   сборку Debug на свой симулятор `LP29d <модель>`, открывает «Свет» в «Астро» (кнопка есть только там) и читает рамки
   из `-LPShotReport`: нижний край узла `spoiler` против верхнего края узла `timebar` (нижней панели). Зазор ≥ 0 —
   кнопка видна целиком; < 0 — часть под панелью. Красный (выход 1) — только у «современных» (15, 16, 16 Pro Max, 17,
   17 Pro Max); SE 3 печатается для сведения: прокрутка там допустима (слово Алексея 09.10), но наезда быть не должно.

     node Tools/light_fit.js --app <путь к .app> [--models iPhone-15,iPhone-17] [--out <папка>] [--keep]

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
const MODERN = ['iPhone-15', 'iPhone-16', 'iPhone-16-Pro-Max', 'iPhone-17', 'iPhone-17-Pro-Max'];
const MODELS = (args.models || [...MODERN, 'iPhone-15-Pro-Max', 'iPhone-SE-3rd-generation'].join(',')).split(',');
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
const CASES = [
  { name: 'calm', at: '2026-09-23T13:00', forecast: path.join(FX, 'forecast_barnaul.json') },
  { name: 'wind', at: '2026-09-23T13:00', forecast: windForecast },
  { name: 'night', at: '2026-09-23T23:00', forecast: path.join(FX, 'forecast_barnaul.json') },
];

function device(model) {
  const name = 'LP29d ' + model;
  const all = () => Object.values(JSON.parse(run('xcrun', ['simctl', 'list', 'devices', '-j'])).devices).flat();
  let d = all().find(x => x.name === name), created = false;
  if (!d) {
    run('xcrun', ['simctl', 'create', name, 'com.apple.CoreSimulator.SimDeviceType.' + model, RUNTIME]); created = true;
    d = all().find(x => x.name === name);
  }
  if (d.state !== 'Booted') { try { run('xcrun', ['simctl', 'boot', d.udid]); } catch (e) {} run('xcrun', ['simctl', 'bootstatus', d.udid, '-b'], { stdio: 'ignore' }); }
  return { udid: d.udid, created };
}

function shoot(udid, theme, c, dir) {
  fs.mkdirSync(dir, { recursive: true });
  const seed = { ...JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8')), theme, pro: true, drumSlot: 'paper', ribbonMode: 'drum' };
  const sf = path.join(dir, 'seed.json'); fs.writeFileSync(sf, JSON.stringify(seed));
  const rep = path.join(dir, 'native.json'); fs.rmSync(rep, { force: true });
  run('xcrun', ['simctl', 'ui', udid, 'appearance', theme]);
  try { run('xcrun', ['simctl', 'terminate', udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
  run('xcrun', ['simctl', 'launch', udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
    '-LPShotNow', c.at + ':00+07:00', '-LPShotZone', 'Asia/Barnaul', '-LPShotSeed', sf, '-LPShotForecast', c.forecast,
    '-LPShotAir', path.join(FX, 'air_barnaul.json'), '-LPShotName', path.join(FX, 'place_barnaul.json'),
    '-LPShotScreen', 'light', '-LPShotReport', rep], { env: { ...process.env, SIMCTL_CHILD_TZ: 'Asia/Barnaul' } });
  for (let i = 0; i < 240 && !fs.existsSync(rep); i++) sleep(0.25);
  if (!fs.existsSync(rep)) throw new Error('приложение не написало рамки: ' + dir);
  sleep(1);
  return JSON.parse(fs.readFileSync(rep, 'utf8'));
}

let red = 0;
console.log('модель'.padEnd(26), 'тема'.padEnd(6), 'текст'.padEnd(6), 'окно'.padEnd(10), 'шапка y', ' кнопка низ', ' панель верх', '  зазор');
for (const model of MODELS) {
  const { udid, created } = device(model);
  run('xcrun', ['simctl', 'install', udid, APP]);
  for (const theme of ['dark', 'light']) for (const c of CASES) {
    const j = shoot(udid, theme, c, path.join(OUT, model, theme + '-' + c.name)), n = j.nodes;
    const sp = n.spoiler, tb = n.timebar, hd = n['header.name'];
    if (!sp || !tb) { console.log(model.padEnd(26), theme.padEnd(6), c.name.padEnd(6), 'нет узла spoiler/timebar'); red++; continue; }
    const bottom = sp.y + sp.h, gap = tb.y - bottom, modern = MODERN.includes(model);
    const bad = modern && gap < 0; if (bad) red++;
    console.log(model.padEnd(26), theme.padEnd(6), c.name.padEnd(6), `${j.size[0]}×${Math.round(j.size[1] + j.safe[0] + j.safe[1])}`.padEnd(10),
      String(hd ? hd.y : '—').padStart(7), bottom.toFixed(1).padStart(11), tb.y.toFixed(1).padStart(12), gap.toFixed(1).padStart(7), bad ? ' ← красный' : '');
  }
  run('xcrun', ['simctl', 'shutdown', udid], { stdio: 'ignore' });
  if (created && !args.keep) run('xcrun', ['simctl', 'delete', udid], { stdio: 'ignore' });
}
console.log(red ? `\nкнопка «Подробно» не видна без прокрутки на ${red} из современных прогонов` : '\nкнопка видна на всех современных');
process.exit(red ? 1 : 0);
