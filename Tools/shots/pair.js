#!/usr/bin/env node
/* Пара снимков «веб / натив» и сверка числами (итерация 19б, § 5.4 плана).

   Одна команда: собирает Debug-сборку, ставит её на симулятор iPhone 17 Pro
   Max, открывает сценарий (момент, место, погода, настройки — прибиты), ждёт
   рамки узлов от приложения, снимает экран симулятора; тот же сценарий
   снимает веб (`Light_Plan/tools/shot.js`) с отступами выреза, которые
   назвало приложение. Дальше в headless-браузере обе картинки кладутся рядом,
   узлы сверяются по имени: место и размер в точках, цвет фона и чернил в
   пикселях снимка.

   Запуск (из корня натива):
     node Tools/shots/pair.js                      # всё: 2 экрана × 2 темы × моменты
     node Tools/shots/pair.js --screens light --themes dark --moments day
     node Tools/shots/pair.js --skip-build         # сборка уже стоит на симуляторе
     node Tools/shots/pair.js --screens planner --scopes day   # «Съёмки» (итерация 21):
                                                   # засев сезона (planner_seed.js), виды месяц/неделя/день
     node Tools/shots/pair.js --screens light --sheets fork,addr,geo   # лист «Где снимаем» (21в)
     node Tools/shots/pair.js --drum-nudge 20      # барабан провёрнут на 20 pt (только натив):
                                                   # видно, как кромка окна гнёт число
   Выход: --out (по умолчанию $TMPDIR/lp-shots/<ветка>) — по папке на сценарий
   (web.png, native.png, web.json, native.json, pair.png) и report.md.
   Из worktree: LIGHT_PLAN_WEB=<путь к Light_Plan>, если папка не рядом.
   Симулятор — свой у ветки (`Tools/sim.js`, итерация 21а): два worktree
   снимают пары одновременно; другой — переменной LP_SIM=<имя>. */
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = {};
process.argv.slice(2).forEach((a, i, all) => {
  if (a.startsWith('--')) args[a.slice(2)] = all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : '1';
});

/* Сценарий пары. Место — Барнаул: пояс машины Алексея тот же (+7), а
   прогноз в Fixtures/shots снят 23 сентября 2026 для этих координат. Моменты
   — состояния неба того же дня: светлый день, золотой час (веб в этот
   день пишет «18:37 – 19:44»), ночь и глубокие сумерки перед рассветом
   (06:05, светило около −8°, у самого горизонта: его свет лежит под
   куполом — на нём Алексей поймал обрезку, которой три прежних момента
   не показывали). */
const ZONE = 'Asia/Barnaul';
const MOMENTS = { day: '2026-09-23T13:00', golden: '2026-09-23T18:50', night: '2026-09-23T23:00',
  dawn: '2026-09-23T06:05' };
const OFFSET = '+07:00';
const BUNDLE = 'Novopashin.LightPlan';

const screens = (args.screens || 'light,map,planner,settings').split(',');
/* Виды «Съёмок» (итерация 21). Режим и момент им не нужны: одна пара на вид
   и тему, в 13:00 — рядом съёмка «прямо сейчас» и черта «сейчас» на ленте. */
const scopes = (args.scopes || 'month,week,day').split(',');
/* Режим: «Просто» и «Астро» — у «Света» разный состав (лента суток и
   «Подробно» только в астро), у «Настроек» — разделы вида. Прорези барабана
   (`drumSlot`) различимы только в светлой теме, снимаются одним моментом. */
const modes = (args.modes || 'simple,astro').split(',');
const slots = (args.slots || 'paper,graphite,window').split(',');
/* Главы настроек, которые сверяются сверх корня: «Вид» (сегменты и образец
   барабана) и «Язык и регион» (сегменты и фишки) — на них все детали
   главы, остальные собраны из тех же. */
const chapters = (args.chapters === '' ? [] : (args.chapters || 'view,locale,places').split(','));
const themes = (args.themes || 'dark,light').split(',');
const moments = (args.moments || 'day,golden,night,dawn').split(',');
/* Сводка карты (итерация 20б): свёрнутая — окно прибора 20а, раскрытая —
   строки свода. Центр прибора от сводки не зависит, поэтому раскрытая
   сверяет и прибор. */
const folds = (args.fold || 'shut,open').split(',');
/* Лист «Где снимаем» (итерация 21в): развилка и два пути над «Светом», над
   «Картой» — развилка (та же кнопка места в шапке). В засеве две точки
   «Моих мест»: с адресом и безымянная (строку называют координаты). */
const sheets = args.sheets === '' ? [] : (args.sheets || 'fork,addr,geo').split(',');
const SHEET_SPOTS = [
  { id: 'p_shot_a', name: 'Нагорный парк', address: 'ул. Гоголя, 2', lat: 53.3334, lon: 83.8035, pinned: true },
  { id: 'p_shot_b', name: '', address: '', lat: 53.35, lon: 83.75, pinned: true }
];
const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-shots', sim.nameFor(ROOT).replace(/\W+/g, '-')));
fs.mkdirSync(OUT, { recursive: true });

function webRoot() {
  if (process.env.LIGHT_PLAN_WEB) return path.resolve(process.env.LIGHT_PLAN_WEB);
  let dir = ROOT;
  for (let i = 0; i < 8; i++) {
    const c = path.join(dir, 'Light_Plan');
    if (fs.existsSync(path.join(c, 'tools', 'shot.js'))) return c;
    dir = path.dirname(dir);
  }
  throw new Error('не нашёл Light_Plan; задай LIGHT_PLAN_WEB');
}
const WEB = webRoot();
/* Playwright стоит в node_modules основной папки веба; у worktree своего нет
   — ищем вверх по папкам, как это делает сам node. */
function playwright() {
  for (let dir = WEB; dir !== path.dirname(dir); dir = path.dirname(dir)) {
    const p = path.join(dir, 'node_modules', 'playwright');
    if (fs.existsSync(p)) return require(p);
  }
  throw new Error('не нашёл playwright рядом с ' + WEB + ' — npm install в Light_Plan');
}

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
  const products = path.join(dd, 'Build', 'Products', 'Debug-iphonesimulator');
  const app = fs.readdirSync(products).find(f => f.endsWith('.app'));
  if (!app) throw new Error('нет .app в ' + products);
  return path.join(products, app);
}

async function nativeShot(udid, sc, dir) {
  const report = path.join(dir, 'native.json');
  fs.rmSync(report, { force: true });
  // Потолок 10 с: на свежем симуляторе `terminate` неработающего приложения
  // висел минутами (замер 21в); ошибка здесь не важна — приложения может и не быть.
  try { run('xcrun', ['simctl', 'terminate', udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
  run('xcrun', ['simctl', 'ui', udid, 'appearance', sc.theme]);
  run('xcrun', ['simctl', 'launch', udid, BUNDLE,
    '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
    '-LPShotNow', MOMENTS[sc.moment] + ':00' + OFFSET, '-LPShotZone', ZONE,
    '-LPShotSeed', sc.seed, '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'),
    '-LPShotAir', path.join(FX, 'air_barnaul.json'), '-LPShotName', path.join(FX, 'place_barnaul.json'),
    '-LPShotScreen', sc.screen, ...(sc.chapter ? ['-LPShotChapter', sc.chapter] : []),
    ...(sc.scope ? ['-LPShotScope', sc.scope] : []), ...(sc.pick != null ? ['-LPShotPick', String(sc.pick)] : []),
    ...(args['drum-nudge'] ? ['-LPShotDrumNudge', args['drum-nudge']] : []),
    ...(sc.sheet ? ['-LPShotSheet', 'loc', ...(sc.sheet !== 'fork' ? ['-LPShotWay', sc.sheet] : [])] : []),
    '-LPShotReport', report],
  { env: { ...process.env, SIMCTL_CHILD_TZ: ZONE } });
  // Первый запуск после установки идёт до 20 с (замер 19б), следующие — 3–4 с.
  for (let i = 0; i < 240 && !fs.existsSync(report); i++) await sleep(250);
  if (!fs.existsSync(report)) throw new Error('приложение не написало рамки за 60 с: ' + sc.name);
  await sleep(300);
  run('xcrun', ['simctl', 'io', udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
  return JSON.parse(fs.readFileSync(report, 'utf8'));
}

function webShot(sc, dir, safe) {
  const out = run('node', [path.join(WEB, 'tools', 'shot.js'), '--screen',
    sc.screen === 'light' ? 'today' : sc.screen === 'planner' ? 'plan' : sc.screen, ...(sc.scope ? ['--scope', sc.scope] : []),
    ...(sc.pick != null ? ['--pick', String(sc.pick)] : []),
    '--at', MOMENTS[sc.moment], '--tz', ZONE, '--seed', sc.seed,
    '--forecast', path.join(FX, 'forecast_barnaul.json'), '--air', path.join(FX, 'air_barnaul.json'),
    '--name', path.join(FX, 'place_barnaul.json'), '--safe', safe.map(v => Math.round(v)).join(','),
    ...(sc.chapter ? ['--chapter', sc.chapter] : []),
    ...(sc.sheet ? ['--sheet', 'loc', ...(sc.sheet !== 'fork' ? ['--way', sc.sheet] : [])] : []),
    '--scale', '3', '--out', path.join(dir, 'web.png'), '--report', path.join(dir, 'web.json')]);
  return JSON.parse(fs.readFileSync(path.join(dir, 'web.json'), 'utf8'));
}

/* Сверка в браузере: canvas даёт пиксели обеих картинок без зависимостей.
   Фон узла — медиана пикселей по контуру на 2 pt снаружи рамки; чернила —
   пиксель внутри рамки, дальше всех от фона (у текста это сердцевина
   буквы, у знака — линия). */
async function compare(page, dir, web, nat, scale) {
  const img = f => 'data:image/png;base64,' + fs.readFileSync(path.join(dir, f)).toString('base64');
  return page.evaluate(async ({ w, n, wn, nn, scale }) => {
    const load = src => new Promise(r => { const i = new Image(); i.onload = () => r(i); i.src = src; });
    const [wi, ni] = await Promise.all([load(w), load(n)]);
    const ctxOf = im => {
      const c = document.createElement('canvas'); c.width = im.width; c.height = im.height;
      const x = c.getContext('2d', { willReadFrequently: true }); x.drawImage(im, 0, 0); return x;
    };
    const wc = ctxOf(wi), nc = ctxOf(ni);
    const px = (ctx, x, y) => { const d = ctx.getImageData(Math.round(x * scale), Math.round(y * scale), 1, 1).data; return [d[0], d[1], d[2]]; };
    const med = a => [0, 1, 2].map(k => a.map(p => p[k]).sort((p, q) => p - q)[a.length >> 1]);
    const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
    const probe = (ctx, r) => {
      const ring = [];
      for (let i = 0; i <= 8; i++) {
        const fx = r.x - 2 + (r.w + 4) * i / 8, fy = r.y - 2 + (r.h + 4) * i / 8;
        ring.push(px(ctx, fx, r.y - 2), px(ctx, fx, r.y + r.h + 2), px(ctx, r.x - 2, fy), px(ctx, r.x + r.w + 2, fy));
      }
      const bg = med(ring);
      const d = ctx.getImageData(Math.round(r.x * scale), Math.round(r.y * scale),
        Math.max(1, Math.round(r.w * scale)), Math.max(1, Math.round(r.h * scale))).data;
      let best = bg, bd = -1;
      for (let i = 0; i < d.length; i += 4) {
        const p = [d[i], d[i + 1], d[i + 2]], v = dist(p, bg);
        if (v > bd) { bd = v; best = p; }
      }
      return { bg, ink: best };
    };
    const hex = c => '#' + c.map(v => v.toString(16).padStart(2, '0')).join('');
    const names = [...new Set([...Object.keys(wn), ...Object.keys(nn)])].sort();
    const rows = names.map(k => {
      const a = wn[k], b = nn[k];
      const av = !!(a && a.visible !== false && a.w > 0 && a.h > 0);
      const bv = !!(b && b.w > 0 && b.h > 0);
      const row = { name: k, web: av, native: bv };
      if (av) row.w = [a.x, a.y, a.w, a.h];
      if (bv) row.n = [b.x, b.y, b.w, b.h];
      if (av && bv) {
        row.d = [b.x - a.x, b.y - a.y, b.w - a.w, b.h - a.h];
        const pw = probe(wc, a), pn = probe(nc, b);
        row.bg = [hex(pw.bg), hex(pn.bg), Math.round(dist(pw.bg, pn.bg))];
        row.ink = [hex(pw.ink), hex(pn.ink), Math.round(dist(pw.ink, pn.ink))];
        // Неразрывный пробел веба и приложения — один и тот же пробел.
        // Веб отдаёт первые 80 знаков — столько же сравниваем у приложения.
        const norm = t => (t || '').replace(/\u00a0/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 80);
        row.text = [norm(a.text), norm(b.text)];
      }
      return row;
    });
    return { rows, screenBg: [hex(px(wc, 4, 480)), hex(px(nc, 4, 480))] };
  }, { w: img('web.png'), n: img('native.png'), wn: web.nodes, nn: nat.nodes, scale });
}

/* Картинка пары: веб слева, натив справа, в точках (1×), рамки узлов обоих
   поверх — синим веб, оранжевым натив, чтобы сдвиг был виден без подписи. */
async function pairImage(page, dir, web, nat) {
  const img = f => 'data:image/png;base64,' + fs.readFileSync(path.join(dir, f)).toString('base64');
  const boxes = nodes => Object.entries(nodes).filter(([, r]) => r.visible !== false && r.w > 0)
    .map(([k, r]) => `<i style="left:${r.x}px;top:${r.y}px;width:${r.w}px;height:${r.h}px" title="${k}"></i>`).join('');
  await page.setViewportSize({ width: 900, height: 956 });
  await page.setContent(`<style>body{margin:0;background:#888;display:flex;gap:20px}
    .f{position:relative;width:440px;height:956px}.f img{width:440px;height:956px;display:block}
    .f i{position:absolute;outline:1px solid var(--c);opacity:.55}
    .web{--c:#29f}.nat{--c:#f82}</style>
    <div class="f web"><img src="${img('web.png')}">${boxes(web.nodes)}</div>
    <div class="f nat"><img src="${img('native.png')}">${boxes(nat.nodes)}</div>`);
  await page.waitForTimeout(100);
  await page.screenshot({ path: path.join(dir, 'pair.png') });
}

function markdown(results) {
  const f = v => (v > 0 ? '+' : '') + v;
  let md = '# Пары веб / натив\n\n';
  for (const r of results) {
    md += `## ${r.name}\n\nфон экрана: веб ${r.cmp.screenBg[0]} · натив ${r.cmp.screenBg[1]}\n\n`;
    if (r.cmp.norm) {
      md += `лист × ${r.cmp.norm.scale} (парящий лист iOS 26); смещения от верха листа, делённые на масштаб, Δ x,y,w,h:\n\n`;
      md += Object.entries(r.cmp.norm.rows).map(([k, d]) => `- ${k}: ${d.join(', ')}`).join('\n') + '\n\n';
    }
    md += '| узел | веб x,y,w,h | Δ натив x,y,w,h | фон веб/натив Δ | чернила веб/натив Δ | текст |\n|---|---|---|---|---|---|\n';
    for (const row of r.cmp.rows) {
      if (!row.web && !row.native) continue;
      if (!row.web || !row.native) {
        md += `| ${row.name} | ${row.web ? row.w.join(',') : '—'} | ${row.native ? 'только натив ' + row.n.join(',') : 'нет в нативе'} | | | |\n`;
        continue;
      }
      const same = row.text[0] === row.text[1] ? '=' : `«${row.text[0].slice(0, 24)}» / «${row.text[1].slice(0, 24)}»`;
      md += `| ${row.name} | ${row.w.join(',')} | ${row.d.map(f).join(',')} | ${row.bg[0]}/${row.bg[1]} ${row.bg[2]} | ${row.ink[0]}/${row.ink[1]} ${row.ink[2]} | ${same} |\n`;
    }
    md += '\n';
  }
  return md;
}

(async () => {
  const dev = sim.device(ROOT);
  console.log('симулятор: ' + dev.name + ' · вывод: ' + OUT);
  run('xcrun', ['simctl', 'status_bar', dev.udid, 'override', '--time', '9:41', '--batteryState', 'charged',
    '--batteryLevel', '100', '--cellularBars', '4', '--wifiBars', '3']);
  if (!args['skip-build']) {
    const app = build(dev.udid);
    run('xcrun', ['simctl', 'install', dev.udid, app]);
    console.log('собрано и поставлено: ' + path.basename(app));
  }

  const seed = JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8'));
  const list = [];
  const plannerSeed = JSON.parse(fs.readFileSync(path.join(FX, 'seed_planner.json'), 'utf8'));
  const add = (screen, theme, mode, moment, slot, chapter, ribbon = 'drum', fold = 'shut', scope = null, pick = null) => {
    const name = scope ? [screen, scope + (pick != null ? pick : ''), theme].join('-')
      : [screen, mode, theme, screen === 'settings' ? null : moment, slot === 'paper' ? null : slot, chapter,
        ribbon === 'drum' ? null : ribbon, fold === 'open' ? 'fold' : null].filter(Boolean).join('-');
    const dir = path.join(OUT, name);
    fs.mkdirSync(dir, { recursive: true });
    const s = { ...(scope ? plannerSeed : seed), theme, pro: mode === 'astro', drumSlot: slot, ribbonMode: ribbon };
    /* Карта (итерация 20а): в «Просто» солнце и луна, в «Астро» к ним
       Млечный Путь — так обе пары слоёв снимаются без отдельного перебора.
       Сводка — свёрнутая и раскрытая (`--fold`). */
    if (screen === 'map') {
      s.mapLayers = { sun: true, moon: true, mw: mode === 'astro', compass: true, spots: true };
      s.mapFold = fold !== 'open';
    }
    const seedFile = path.join(dir, 'seed.json');
    fs.writeFileSync(seedFile, JSON.stringify(s));
    list.push({ name, dir, screen, theme, moment, chapter, scope, pick, seed: seedFile });
  };
  for (const screen of ['light', 'map'].filter(x => screens.includes(x))) for (const way of sheets) for (const theme of themes) {
    if (screen === 'map' && way !== 'fork') continue;
    const name = [screen, 'loc', way, theme].join('-');
    const dir = path.join(OUT, name);
    fs.mkdirSync(dir, { recursive: true });
    const s = { ...seed, theme, pro: false, drumSlot: 'paper', ribbonMode: 'drum', spots: SHEET_SPOTS };
    if (screen === 'map') { s.mapLayers = { sun: true, moon: true, mw: false, compass: true, spots: true }; s.mapFold = true; }
    const seedFile = path.join(dir, 'seed.json');
    fs.writeFileSync(seedFile, JSON.stringify(s));
    list.push({ name, dir, screen, theme, moment: 'day', sheet: way, seed: seedFile });
  }
  if (args['only-sheets']) screens.length = 0;
  if (screens.includes('planner')) for (const scope of scopes) for (const theme of themes) {
    add('planner', theme, 'simple', 'day', 'paper', null, 'drum', 'shut', scope);
    /* Суббота 26-го: две съёмки внахлёст (14:00–15:30 и 15:00–16:30) —
       колонки ленты на экране, а не только в стенде `make planner` */
    if (scope === 'day') add('planner', theme, 'simple', 'day', 'paper', null, 'drum', 'shut', scope, 5);
  }
  for (const screen of screens.filter(x => x !== 'planner')) for (const mode of modes) for (const theme of themes) {
    // «Настройки» от момента не зависят — одна пара на тему и режим.
    for (const moment of screen === 'settings' ? [moments[0]] : moments) {
      for (const fold of screen === 'map' ? folds : ['shut']) add(screen, theme, mode, moment, 'paper', null, 'drum', fold);
    }
    if (screen === 'settings') for (const ch of chapters) add(screen, theme, mode, moments[0], 'paper', ch);
    // Меню слоёв карты (20б) — одним моментом, сводка свёрнута.
    if (screen === 'map' && !args['no-layers']) add(screen, theme, mode, moments[0], 'paper', 'layers');
    // Закладка нажата — точка под головкой и полоса её имени (20б).
    if (screen === 'map' && !args['no-spot']) add(screen, theme, mode, moments[0], 'paper', 'spot');
    if (screen === 'light' && mode === 'astro' && theme === 'light') {
      for (const slot of slots) if (slot !== 'paper') add(screen, theme, mode, moments[0], slot);
    }
    // Лента суток «Полоса» вместо барабана — второй вид того же органа.
    if (screen === 'light' && mode === 'astro' && !args['no-lane']) add(screen, theme, mode, moments[0], 'paper', null, 'lane');
  }

  const { chromium } = playwright();
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const results = [];
  for (const sc of list) {
    const nat = await nativeShot(dev.udid, sc, sc.dir);
    // Под главой корень остаётся в стеке и пишет свои рамки — сверяется
    // только глава (веб прячет корень листом главы).
    if (sc.chapter && sc.screen === 'settings') for (const k of Object.keys(nat.nodes)) if (/^(header|mode|nav)/.test(k)) delete nat.nodes[k];
    // Соседняя вкладка тоже жива и пишет рамки за краем экрана — не в счёт.
    for (const [k, r] of Object.entries(nat.nodes)) if (r.x + r.w <= 0 || r.x >= 440 || r.y >= 956 || r.y + r.h <= 0) delete nat.nodes[k];
    // Под листом места экран жив и пишет рамки — сверяется только лист.
    if (sc.sheet) for (const k of Object.keys(nat.nodes)) if (!k.startsWith('loc.')) delete nat.nodes[k];
    const web = webShot(sc, sc.dir, nat.safe);
    // Лист главы у веба закрывает панель вкладок, но в разметке она «видна»;
    // приложение её прячет — под главой панель не сверяется.
    if (sc.chapter && sc.screen === 'settings') for (const k of Object.keys(web.nodes)) if (/^tab(bar|\.)/.test(k)) delete web.nodes[k];
    const cmp = await compare(page, sc.dir, web, nat, 3);
    await pairImage(page, sc.dir, web, nat);
    /* Лист места (21в): системный лист iOS 26 на неполной высоте — парящая
       карточка, всё в ней уменьшено в (ширина листа / 440) раз (замер:
       424 / 440 = 0,964). Сверка раскладки — смещения от верха листа,
       делённые на этот масштаб. */
    if (sc.sheet && web.nodes['loc.sheet'] && nat.nodes['loc.sheet']) {
      const ns = nat.nodes['loc.sheet'], ws = web.nodes['loc.sheet'], k = ns.w / 440;
      let worst = { v: 0, name: '—' };
      cmp.norm = { scale: +k.toFixed(4), rows: {} };
      for (const [name, a] of Object.entries(web.nodes)) {
        const b = nat.nodes[name];
        if (name === 'loc.sheet' || !b || a.visible === false) continue;
        const d = [(b.x - ns.x) / k - a.x, (b.y - ns.y) / k - (a.y - ws.y), b.w / k - a.w, b.h / k - a.h].map(v => +v.toFixed(1));
        cmp.norm.rows[name] = d;
        const m = Math.max(...d.map(Math.abs));
        if (m > worst.v) worst = { v: m, name };
      }
      cmp.norm.worst = worst;
      console.log(`${sc.name}: лист × ${k.toFixed(3)}, после деления на масштаб худший узел ${worst.name} ${worst.v} pt`);
    }
    results.push({ name: sc.name, cmp });
    const both = cmp.rows.filter(r => r.web && r.native);
    const off = both.filter(r => r.d.some(v => Math.abs(v) > 2)).length;
    const gone = cmp.rows.filter(r => r.web !== r.native).length;
    console.log(`${sc.name}: узлов в обоих ${both.length}, сдвиг > 2 pt у ${off}, есть только с одной стороны ${gone}`);
  }
  await browser.close();
  fs.writeFileSync(path.join(OUT, 'report.md'), markdown(results));
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(results, null, 1));
  console.log('отчёт: ' + path.join(OUT, 'report.md'));
})().catch(e => { console.error(String(e && e.stack || e)); process.exit(1); });
