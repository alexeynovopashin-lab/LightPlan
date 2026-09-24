#!/usr/bin/env node
/* Итерация 21а: ротор «Карты» под подставным компасом — клина пустоты нет.
   20б закрыла ротор тестом математики (`MapRotorTests`), а живой экран с
   поворотом в симуляторе не видел никто: магнитометра там нет, кнопка
   компаса молчит.

   Прогон: Debug-сборка на симулятор ветки (`Tools/sim.js`), «Карта» в
   сценарии пары (`-LPShotScreen map`), компас включён при запуске
   (`-LPShotChapter compass`), курс — подставной (`-LPShotHeading`: углы по
   очереди, `-LPShotHeadingHold` секунд на угол; ротор сглаживает их тем же
   `smooth`, что живой компас). Под ротором — пустота цвета `VOID`
   (`-LPShotVoid`), которого нет ни на подложке, ни в приборе. Приложение
   пишет, когда ротор встал на угол; прибор в этот миг снимает экран и
   мерит две вещи. Угол: в роторе метка севера (пурпурная точка в 120 pt от
   оси), её пеленг от оси на снимке — это поворот карты, какой видит глаз;
   ждём 360° − курс (карта крутится навстречу телефону) в пределах 1°.
   Клин: пиксели пустоты; хоть один — прогон красный.

   Клин на iPhone 17 Pro Max почти невозможен: окно карты между шапкой и
   доком 440 × ~567 pt, его покрывает любой квадрат от ~810 pt, а сторона
   ротора 1223 (расчёт по оси cy 433,5 из отчёта, 21а). Поэтому главная проверка экрана — угол;
   пустота ловит поломки вёрстки (квадрат не там, обрезан).

   node Tools/rotor.js [--angles 0,45,…] [--hold 3] [--themes dark,light] [--skip-build]
   Выход: $TMPDIR/lp-rotor/<симулятор>/ — снимки углов и report.json.
   Порча, которой прибор проверен (DECISIONS, «Прибор 21а»): знак поворота
   (`rotationEffect(+angle)`) — падает угол; сторона 600 pt — падает пустота.
   Диагональ кадра (прежнее правило веба) на этом экране клина в видимом
   окне не даёт — только под непрозрачной панелью вкладок. */
const fs = require('fs');
const path = require('path');
const os = require('os');
const zlib = require('zlib');
const { execFileSync } = require('child_process');
const sim = require('./sim');

const ROOT = path.resolve(__dirname, '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const BUNDLE = 'Novopashin.LightPlan';
const VOID = [0x00, 0xff, 0x00];
const MARK = [0xff, 0x00, 0xff];
const near = (r, g, b, c) => Math.abs(r - c[0]) <= 40 && Math.abs(g - c[1]) <= 40 && Math.abs(b - c[2]) <= 40;
const args = {};
process.argv.slice(2).forEach((a, i, all) => {
  if (a.startsWith('--')) args[a.slice(2)] = all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : '1';
});
const ANGLES = (args.angles || '0,45,90,135,180,225,270,315').split(',').map(Number);
const HOLD = +(args.hold || 3);
const THEMES = (args.themes || 'dark,light').split(',');
const OUT = path.join(os.tmpdir(), 'lp-rotor', sim.nameFor(ROOT).replace(/\W+/g, '-'));
fs.mkdirSync(OUT, { recursive: true });

const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));

function build(udid) {
  const dd = path.join(OUT, 'DerivedData');
  const log = path.join(OUT, 'xcodebuild.log');
  try {
    run('xcodebuild', ['-project', path.join(ROOT, 'LightPlan.xcodeproj'), '-scheme', 'LightPlan-iOS',
      '-configuration', 'Debug', '-destination', 'platform=iOS Simulator,id=' + udid,
      '-derivedDataPath', dd, 'build'], { stdio: ['ignore', fs.openSync(log, 'w'), fs.openSync(log, 'a')] });
  } catch (e) {
    const errs = fs.readFileSync(log, 'utf8').split('\n').filter(l => /error:/.test(l)).slice(0, 10);
    throw new Error('сборка упала (' + log + '):\n' + errs.join('\n'));
  }
  return path.join(dd, 'Build', 'Products', 'Debug-iphonesimulator', 'LightPlan.app');
}

/* PNG симулятора: 8 бит на канал, RGB или RGBA, без чересстрочности —
   хватает zlib из node, без зависимостей. */
function readPng(file) {
  const buf = fs.readFileSync(file);
  let pos = 8, w = 0, h = 0, type = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos), kind = buf.toString('ascii', pos + 4, pos + 8);
    const body = buf.subarray(pos + 8, pos + 8 + len);
    if (kind === 'IHDR') {
      w = body.readUInt32BE(0); h = body.readUInt32BE(4); type = body[9];
      if (body[8] !== 8 || body[12] !== 0 || (type !== 2 && type !== 6)) throw new Error('PNG не 8-бит RGB(A): ' + file);
    } else if (kind === 'IDAT') idat.push(body);
    pos += 12 + len;
  }
  const bpp = type === 6 ? 4 : 3, stride = w * bpp;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const px = Buffer.alloc(h * stride);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)], src = y * (stride + 1) + 1, dst = y * stride;
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? px[dst + x - bpp] : 0, b = y ? px[dst - stride + x] : 0;
      const c = x >= bpp && y ? px[dst - stride + x - bpp] : 0;
      let v = raw[src + x];
      if (f === 1) v += a;
      else if (f === 2) v += b;
      else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      px[dst + x] = v & 255;
    }
  }
  return { w, h, bpp, px };
}

/* Снимок угла. Пустота: чистый цвет (в 40 по каждому каналу) и
   «подкрашенные» — под стеклом шапки или дока, зелёный выше прочих на 80;
   рамка в точках (снимок 3×). Метка: середина пурпурных пикселей, пеленг от
   оси (x — середина экрана, y — `cy` из отчёта приложения) по часовой от
   верха, градусы. */
function analyze(file, cy) {
  const { w, h, bpp, px } = readPng(file);
  let pure = 0, tint = 0, box = null, mark = 0, mx = 0, my = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = (y * w + x) * bpp, r = px[i], g = px[i + 1], b = px[i + 2];
    if (near(r, g, b, MARK)) { mark++; mx += x; my += y; continue; }
    const isPure = near(r, g, b, VOID);
    const isTint = !isPure && g - Math.max(r, b) >= 80;
    if (!isPure && !isTint) continue;
    if (isPure) pure++; else tint++;
    box = box ? [Math.min(box[0], x), Math.min(box[1], y), Math.max(box[2], x), Math.max(box[3], y)] : [x, y, x, y];
  }
  let bearing = null;
  if (mark >= 20) {
    const dx = mx / mark / 3 - w / 6, dy = my / mark / 3 - cy;
    bearing = (Math.atan2(dx, -dy) * 180 / Math.PI + 360) % 360;
  }
  return { pure, tint, box: box && box.map(v => Math.round(v / 3)), mark, bearing };
}

async function pass(udid, theme) {
  const dir = path.join(OUT, theme);
  fs.mkdirSync(dir, { recursive: true });
  const report = path.join(dir, 'heading.json');
  fs.rmSync(report, { force: true });
  const seed = JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8'));
  // Слои как у пары карты в «Просто»: солнце, луна, стороны света, точки.
  const seedFile = path.join(dir, 'seed.json');
  fs.writeFileSync(seedFile, JSON.stringify({ ...seed, theme, mapFold: true,
    mapLayers: { sun: true, moon: true, mw: false, compass: true, spots: true } }));
  try { run('xcrun', ['simctl', 'terminate', udid, BUNDLE], { stdio: 'ignore' }); } catch (e) {}
  run('xcrun', ['simctl', 'ui', udid, 'appearance', theme]);
  run('xcrun', ['simctl', 'launch', udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
    '-LPShotNow', '2026-09-23T13:00:00+07:00', '-LPShotZone', 'Asia/Barnaul', '-LPShotSeed', seedFile,
    '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
    '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'map', '-LPShotChapter', 'compass',
    '-LPShotHeading', ANGLES.join(','), '-LPShotHeadingHold', String(HOLD),
    '-LPShotVoid', VOID.map(v => v.toString(16).padStart(2, '0')).join(''), '-LPShotHeadingReport', report],
  { stdio: 'ignore', env: { ...process.env, SIMCTL_CHILD_TZ: 'Asia/Barnaul' } });

  const rows = [];
  // Первый запуск после установки — до 20 с (замер 19б), дальше выдержка на угол.
  const deadline = Date.now() + 25000 + ANGLES.length * (HOLD * 3000 + 15000);
  while (rows.length < ANGLES.length && Date.now() < deadline) {
    let got = [];
    try { got = JSON.parse(fs.readFileSync(report, 'utf8')).rows; } catch (e) {}
    if (got.length > rows.length) {
      const row = got[rows.length];
      const shot = path.join(dir, `angle_${String(row.target).padStart(3, '0')}.png`);
      run('xcrun', ['simctl', 'io', udid, 'screenshot', '--type=png', shot], { stdio: 'ignore' });
      const got2 = analyze(shot, row.cy);
      // Карта крутится навстречу телефону: курс 90° — север карты слева.
      const want = (360 - row.target % 360) % 360;
      const err = got2.bearing == null ? null : ((got2.bearing - want + 540) % 360) - 180;
      rows.push({ ...row, shot, ...got2, want, err });
      continue;
    }
    await sleep(60);
  }
  return rows;
}

(async () => {
  const dev = sim.device(ROOT);
  console.log('симулятор: ' + dev.name + ' · вывод: ' + OUT);
  if (!args['skip-build']) run('xcrun', ['simctl', 'install', dev.udid, build(dev.udid)]);
  let fail = 0;
  const all = {};
  for (const theme of THEMES) {
    const rows = await pass(dev.udid, theme);
    all[theme] = rows;
    if (rows.length < ANGLES.length) { fail = 1; console.log(`ПАДАЕТ ${theme}: углов ${rows.length} из ${ANGLES.length}`); }
    for (const r of rows) {
      const ok = r.live && r.settled && r.err != null && Math.abs(r.err) <= 1 && r.pure === 0 && r.tint === 0;
      if (!ok) fail = 1;
      const seen = r.bearing == null ? `метки нет (${r.mark} px)` : `север на экране ${r.bearing.toFixed(1)}° (ждём ${r.want}°, Δ ${r.err.toFixed(1)})`;
      console.log(`${ok ? 'ок    ' : 'ПАДАЕТ'} ${theme} ${String(r.target).padStart(3)}°: ротор ${r.angle.toFixed(2)}°` +
        ` за ${r.ms} мс, ${seen}, пустота ${r.pure} + ${r.tint} px${r.box ? ' в ' + r.box.join(',') + ' pt' : ''}`);
    }
  }
  try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore' }); } catch (e) {}
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(all, null, 1));
  console.log(fail ? 'клин или сбой — см. ' + OUT : 'клина нет ни на одном угле');
  process.exit(fail);
})().catch(e => { console.error(e.message); process.exit(2); });
