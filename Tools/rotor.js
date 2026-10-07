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
const SPOTS = !!args.spots;
const BARE = !!args.bare; // 28п: без прибора — подложка и точки, плашки видно по одной заливке
const MOTION = +(args.motion || 0); // 28п: кадров на каждый переход между углами, пока ротор в движении
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
   верха, градусы. Строка состояния (верхние 60 pt) не в счёт: карты там нет,
   а значок батареи на свежем симуляторе зелёный — прибор принял его за
   пустоту (`LP main`, 25.09: 1194 px в 371,27–394,37 pt на всех углах). */
const STATUS_PT = 60;
function analyze(file, cy) {
  const { w, h, bpp, px } = readPng(file);
  let pure = 0, tint = 0, box = null, mark = 0, mx = 0, my = 0;
  for (let y = STATUS_PT * 3; y < h; y++) for (let x = 0; x < w; x++) {
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


/* 28п: плашки имён точек. Кадр → связные пятна «не подложка» (после стирания
   тонких линий прибора 5 px): плашка — пятно шире 36 pt или выше 36 pt;
   булавка (~28 × 34 pt) и светила в счёт не идут. Ожидаемый центр плашки —
   остриё точки (меркатор от центра камеры, зум 14), повёрнутое вокруг оси на
   −курс, и сдвиг подписи (14; −15,7 − 7,5) по неповёрнутому экрану: плашка
   не должна ни расти, ни крутиться. */
// Плашка и булавка светлее подложки в обеих темах, тень — темнее; в светлой теме порог выше (подложка светлая, шум крупнее).
const LIGHT_THR = 25;
const PLATE_SPOTS = [['Дом с драконами', 53.3560, 83.7728], ['Ресторан «Соль»', 53.3538, 83.7663], ['Берег Оби', 53.3541, 83.7748]];
function expectedTip(lat, lon, angle, cy) {
  const mx = l => (l + 180) / 360, my = l => { const f = Math.max(-85.051129, Math.min(85.051129, l)) * Math.PI / 180;
    return (1 - Math.log(Math.tan(f) + 1 / Math.cos(f)) / Math.PI) / 2; };
  const world = 512 * Math.pow(2, 14);
  const dx = (mx(lon) - mx(83.7698)) * world, dy = (my(lat) - my(53.3548)) * world;
  const a = -angle * Math.PI / 180;
  return { x: 220 + dx * Math.cos(a) - dy * Math.sin(a), y: cy + dx * Math.sin(a) + dy * Math.cos(a) };
}
function blobs(file, thr = 9) {
  const { w, h, bpp, px } = readPng(file);
  const hist = new Map();
  for (let y = 700; y < 1900; y += 7) for (let x = 40; x < w - 40; x += 7) {
    const i = (y * w + x) * bpp, k = px[i] << 16 | px[i + 1] << 8 | px[i + 2]; hist.set(k, (hist.get(k) || 0) + 1);
  }
  const g = [...hist.entries()].sort((a, b) => b[1] - a[1])[0][0], gr = g >> 16, gg = g >> 8 & 255, gb = g & 255;
  const m = new Uint8Array(w * h);
  for (let y = 520; y < 2100; y++) for (let x = 0; x < w; x++) {
    const i = (y * w + x) * bpp;
    m[y * w + x] = px[i] - gr + px[i + 1] - gg + px[i + 2] - gb >= thr ? 1 : 0;   // светлее подложки: тень (темнее) не в счёт
  }
  // окно карты: между шапкой и доком (пиксели 3×), кадр 1320 × 2868
  const top = 520, bot = 2100;
  const R = 2, e1 = new Uint8Array(w * h), e2 = new Uint8Array(w * h);
  for (let y = top; y < bot; y++) for (let x = R; x < w - R; x++) {
    let ok = 1; for (let d = -R; d <= R; d++) if (!m[y * w + x + d]) { ok = 0; break; } e1[y * w + x] = ok;
  }
  for (let y = top + R; y < bot - R; y++) for (let x = 0; x < w; x++) {
    let ok = 1; for (let d = -R; d <= R; d++) if (!e1[(y + d) * w + x]) { ok = 0; break; } e2[y * w + x] = ok;
  }
  const out = [], seen = new Uint8Array(w * h);
  for (let y = top; y < bot; y++) for (let x = 0; x < w; x++) {
    const s0 = y * w + x; if (!e2[s0] || seen[s0]) continue;
    const st = [s0]; seen[s0] = 1; let x0 = x, x1 = x, y0 = y, y1 = y, n = 0;
    while (st.length) {
      const c = st.pop(), cx = c % w, cy2 = (c / w) | 0; n++;
      if (cx < x0) x0 = cx; if (cx > x1) x1 = cx; if (cy2 < y0) y0 = cy2; if (cy2 > y1) y1 = cy2;
      for (const nb of [c - 1, c + 1, c - w, c + w]) if (e2[nb] && !seen[nb]) { seen[nb] = 1; st.push(nb); }
    }
    const bw = (x1 - x0 + 1 + 2 * R) / 3, bh = (y1 - y0 + 1 + 2 * R) / 3;
    if (n > 30) out.push({ w: +bw.toFixed(1), h: +bh.toFixed(1), cx: +(((x0 + x1) / 2) / 3).toFixed(1), cy: +(((y0 + y1) / 2) / 3).toFixed(1) });
  }
  return out;
}


/* Плашки трёх точек на кадре: ближайшее к ожидаемому месту пятно шире 36 pt
   или выше 36 pt. Образец — кадр курса 0° (в нём плашки стоят как в покое):
   на другом курсе остриё точки идёт по кругу вокруг оси (−курс), плашка — те
   же размеры и тот же сдвиг (14; −23,2 до верха) от острия, вверх головой. Без образца
   (курса 0° нет в списке) ожидание считается от меркатора — грубее, ~7 pt. */
function platesAt(file, angle, cy, ref, thr) {
  const big = blobs(file, thr).filter(b => b.w > 36 || b.h > 36);
  return PLATE_SPOTS.map(([name, lat, lon], i) => {
    let t, size = null;
    const r0 = ref && ref[i] && ref[i].found;
    if (r0) {
      const a = -angle * Math.PI / 180, dx = r0.left - 14 - 220, dy = r0.mid + 15.7 - cy;
      t = { x: 220 + dx * Math.cos(a) - dy * Math.sin(a), y: cy + dx * Math.sin(a) + dy * Math.cos(a) };
      size = { w: r0.w, h: r0.h };
    } else t = expectedTip(lat, lon, angle, cy);
    const ex = t.x + 14, ey = t.y - 15.7;     // левый край плашки и её середина по высоте (верх −23,2, высота 15)
    let best = null;
    for (const b of big) {
      const d = Math.hypot(b.cx - b.w / 2 - ex, b.cy - ey);
      if (!best || d < best.d) best = { ...b, d };
    }
    const found = best && { w: best.w, h: best.h, left: +(best.cx - best.w / 2).toFixed(1), mid: best.cy, d: +best.d.toFixed(1) };
    const ok = !!(found && size && Math.abs(found.w - size.w) <= 1.5 && Math.abs(found.h - size.h) <= 1.5 && found.d <= 2.5);
    return { name, ex, ey, found, size, ok: size ? ok : null };
  });
}

async function pass(udid, theme) {
  const dir = path.join(OUT, theme);
  fs.mkdirSync(dir, { recursive: true });
  const report = path.join(dir, 'heading.json');
  fs.rmSync(report, { force: true });
  const seed = JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8'));
  // Слои как у пары карты в «Просто»: солнце, луна, стороны света, точки.
  const seedFile = path.join(dir, 'seed.json');
  // 28п: `--spots` — три точки с подписями в окне карты (плашки имён под ротором).
  const spots = SPOTS ? [
    { id: 'p_r_dragon', name: 'Дом с драконами', address: '', lat: 53.3560, lon: 83.7728, pinned: true, named: true },
    { id: 'p_r_sol', name: 'Ресторан «Соль»', address: '', lat: 53.3538, lon: 83.7663, pinned: true, named: true },
    { id: 'p_r_obi', name: 'Берег Оби', address: '', lat: 53.3541, lon: 83.7748, pinned: true, named: true }] : undefined;
  fs.writeFileSync(seedFile, JSON.stringify({ ...seed, theme, mapFold: true, ...(spots ? { spots } : {}),
    mapLayers: BARE ? { sun: false, moon: false, mw: false, compass: false, spots: true }
      : { sun: true, moon: true, mw: false, compass: true, spots: true } }));
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
  let burst = 0;
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
      rows.push({ ...row, shot, ...got2, want, err, plates: SPOTS && BARE ? platesAt(shot, row.angle, row.cy, rows[0] && rows[0].target === 0 ? rows[0].plates : null, theme === 'light' ? LIGHT_THR : 9) : undefined });
      burst = 0;
      continue;
    }
    if (burst < MOTION && rows.length > 0) {
      const f = path.join(dir, `motion_${String(rows.length).padStart(2, '0')}_${String(burst++).padStart(2, '0')}.png`);
      run('xcrun', ['simctl', 'io', udid, 'screenshot', '--type=png', f], { stdio: 'ignore' });
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
      for (const p of r.plates || []) {
        const f = p.found;
        console.log(`        ${p.ok === false ? 'ПАДАЕТ' : p.ok ? 'ок    ' : 'образец'} плашка «${p.name}»: ` + (f ? `${f.w} × ${f.h} pt (образец ${p.size ? p.size.w + ' × ' + p.size.h : '—'}), левый край ${f.left} (ждём ${p.ex.toFixed(1)}), середина ${f.mid} (ждём ${p.ey.toFixed(1)}), уход ${f.d} pt` : 'не найдена'));
        if (p.ok === false) fail = 1;
      }
    }
    if (SPOTS && BARE && !(rows[0] && rows[0].target === 0)) {
      fail = 1;
      console.log('ПАДАЕТ: без кадра курса 0° нет образца плашек — добавьте 0 в --angles');
    }
    if (MOTION && SPOTS && BARE) {
      // Кадры в движении (угол на них неизвестен): плашка не должна раздуться. Раздутое
      // стекло — плита в сотни pt по обеим сторонам (на симуляторе ≈ 390–460 × 415–470),
      // плашка, её тень и полосы краёв — узкие: меньшая сторона ≤ 120 pt.
      const dir = path.join(OUT, theme);
      const frames = fs.readdirSync(dir).filter(n => n.startsWith('motion_')).sort();
      if (!frames.length) { fail = 1; console.log('ПАДАЕТ: кадров в движении нет — ротор встал на угол раньше съёмки; --motion ничего не проверил'); }
      for (const f of frames) {
        const big = blobs(path.join(dir, f), theme === 'light' ? LIGHT_THR : 9).filter(b => b.w > 36 || b.h > 36);
        const slab = big.filter(b => Math.min(b.w, b.h) > 120);
        const ok = slab.length === 0;
        if (!ok) fail = 1;
        console.log(`  ${ok ? 'ок    ' : 'ПАДАЕТ'} в движении ${f}: пятен крупнее 36 pt — ${big.length}, плит (обе стороны > 120 pt) — ${slab.length}${slab.length ? ', самая ' + slab[0].w + ' × ' + slab[0].h + ' pt' : ''}`);
      }
    }
  }
  try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore' }); } catch (e) {}
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(all, null, 1));
  console.log(fail ? 'клин или сбой — см. ' + OUT : 'клина нет ни на одном угле');
  process.exit(fail);
})().catch(e => { console.error(e.message); process.exit(2); });
