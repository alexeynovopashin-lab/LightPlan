#!/usr/bin/env node
/* Кадры шага 29.8в.12 «Место»: только натив (у веба нет ни «Я здесь», ни слежения).
   Лист «Где снимаем» (развилка) — в трёх состояниях слежения; стрелка у имени в шапке «Света» и «Карты» и кнопка-стрелка
   на AR — сплошная (слежение) и контурная (место выбрано руками).
   Состояние задаёт `-LPShotFollow on|hand` (отладка, `ShotScenario`): `on` — доступ дан, телефон стоит в месте засева;
   `hand` — место выбрано руками, слежение выключилось само; без аргумента — доступа нет (как у снимков пар).
   Устройства: 17 Pro Max (440 pt, симулятор ветки), iPhone 15 (393 pt) и SE 3 (375 pt) — последние два создаются здесь и
   удаляются в конце (`--keep` оставляет). Языки `--langs ru,en` (по умолчанию оба).
   Числа из рамок узлов (`-LPShotReport`): все узлы внутри экрана; на развилке сверху вниз «Я здесь» → строка точки →
   переключатель → «Место» → «Координаты», без наложений; «Я здесь» и ряд переключателя не ниже 44 pt; состояние стрелки и
   переключателя — то, что задано; слова «Геопозиция»/«Geolocation» в листе нет. Нарушение — код 1.

     node Tools/shots/place.js [--skip-build] [--devices max,15,se] [--langs ru,en] [--only a,b] [--out <dir>] [--keep] */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : []).filter(x => x.length));
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const BUNDLE = 'Novopashin.LightPlan';
const RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-26-5';
const LOC = { ru: 'ru_RU', en: 'en_US', es: 'es_ES', ja: 'ja_JP', zh: 'zh_CN' };
const branch = run('git', ['-C', ROOT, 'rev-parse', '--abbrev-ref', 'HEAD']).trim().replace(/\//g, '-');
const DEVICES = {
  max: { pt: 440, name: null },
  15: { pt: 393, type: 'com.apple.CoreSimulator.SimDeviceType.iPhone-15', name: `LP ${branch} 15` },
  se: { pt: 375, type: 'com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation', name: `LP ${branch} se` },
};

// `follow` — аргумент `-LPShotFollow`; `arrow` — какой ждём стрелку; `toggle` — каким переключатель; `note` — ключ подписи.
const SCENARIOS = [
  { name: 'sheet_on', screen: 'light', sheet: true, follow: 'on', arrow: 'on', toggle: 'on' },
  { name: 'sheet_hand', screen: 'light', sheet: true, follow: 'hand', arrow: 'off', toggle: 'off' },
  { name: 'sheet_denied', screen: 'light', sheet: true, follow: null, arrow: 'off', toggle: 'off', settings: true },
  { name: 'light_on', screen: 'light', follow: 'on', arrow: 'on' },
  { name: 'light_hand', screen: 'light', follow: 'hand', arrow: 'off' },
  { name: 'map_on', screen: 'map', follow: 'on', arrow: 'on' },
  { name: 'map_hand', screen: 'map', follow: 'hand', arrow: 'off' },
  { name: 'ar_on', screen: 'map', ar: true, follow: 'on', arrow: 'on' },
  { name: 'ar_hand', screen: 'map', ar: true, follow: 'hand', arrow: 'off' },
];

function verdict(sc, nodes, W, H) {
  const bad = [];
  const need = k => nodes[k] || (bad.push('нет узла ' + k), null);
  const inside = k => {
    const n = nodes[k];
    if (n && (n.x < -0.5 || n.x + n.w > W + 0.5 || n.y < -0.5 || n.y + n.h > H + 0.5))
      bad.push(`${k}: рамка ${n.x.toFixed(0)},${n.y.toFixed(0)} ${n.w.toFixed(0)}×${n.h.toFixed(0)} вне экрана ${W}×${H}`);
  };
  if (sc.ar) {
    const a = need('ar.follow');
    if (a) {
      if (a.text !== sc.arrow) bad.push(`стрелка AR «${a.text}», ждали «${sc.arrow}»`);
      if (a.h < 44 - 0.5 || a.w < 44 - 0.5) bad.push(`стрелка AR ${a.w.toFixed(0)}×${a.h.toFixed(0)} < 44`);
      inside('ar.follow');
      const back = nodes['ar.back'];
      if (back && a.x < back.x + back.w - 0.5) bad.push('стрелка AR налезает на «Назад»');
    }
    return bad;
  }
  const h = need('header.follow');
  if (h) {
    if (h.text !== sc.arrow) bad.push(`стрелка шапки «${h.text}», ждали «${sc.arrow}»`);
    inside('header.follow');
    const name = nodes['header.name'];
    if (name && h.x < name.x + name.w - 0.5) bad.push('стрелка налезает на имя места');
  }
  if (!sc.sheet) return bad;
  const order = ['loc.here', 'loc.fix', 'loc.follow', 'loc.way.addr', 'loc.way.geo'];
  for (const k of order) { need(k); inside(k); }
  for (let i = 1; i < order.length; i++) {
    const a = nodes[order[i - 1]], b = nodes[order[i]];
    if (a && b && a.y + a.h > b.y + 0.5) bad.push(`${order[i - 1]} (низ ${(a.y + a.h).toFixed(1)}) налезает на ${order[i]} (верх ${b.y.toFixed(1)})`);
  }
  if (nodes['loc.here'] && nodes['loc.here'].h < 44 - 0.5) bad.push(`«Я здесь» высотой ${nodes['loc.here'].h.toFixed(0)} < 44`);
  const t = nodes['loc.follow'];
  if (t && t.text !== sc.toggle) bad.push(`переключатель «${t.text}», ждали «${sc.toggle}»`);
  if (sc.settings && !nodes['loc.openSettings']) bad.push('нет «Открыть настройки» при отказе');
  if (!sc.settings && nodes['loc.openSettings']) bad.push('«Открыть настройки» не к месту');
  const words = Object.values(nodes).map(n => n.text || '').join(' ');
  if (/Геопозиция|Geolocation/.test(words)) bad.push('в листе звучит «Геопозиция»');
  return bad;
}

(async () => {
  const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-shots', 'place'));
  fs.mkdirSync(OUT, { recursive: true });
  const base = sim.device(ROOT);
  const dd = path.join(OUT, 'DerivedData');
  if (!args['skip-build']) {
    const log = path.join(OUT, 'xcodebuild.log');
    try {
      run('xcodebuild', ['-project', path.join(ROOT, 'LightPlan.xcodeproj'), '-scheme', 'LightPlan-iOS', '-configuration', 'Debug',
        '-destination', 'platform=iOS Simulator,id=' + base.udid, '-derivedDataPath', dd, 'build'], { stdio: ['ignore', fs.openSync(log, 'w'), fs.openSync(log, 'a')] });
    } catch (e) { throw new Error('сборка упала: ' + log); }
  }
  const products = path.join(dd, 'Build', 'Products', 'Debug-iphonesimulator');
  const app = path.join(products, fs.readdirSync(products).find(f => f.endsWith('.app')));
  const only = args.only ? String(args.only).split(',') : null;
  const langs = args.langs ? String(args.langs).split(',') : ['ru', 'en'];
  const wanted = args.devices ? String(args.devices).split(',') : ['max', '15', 'se'];
  const made = [];
  const rows = [];
  try {
    for (const key of wanted) {
      const dev = DEVICES[key];
      let udid = base.udid;
      if (dev.name) {
        udid = run('xcrun', ['simctl', 'create', dev.name, dev.type, RUNTIME]).trim();
        made.push(udid);
      }
      try { run('xcrun', ['simctl', 'boot', udid], { stdio: 'ignore' }); } catch (e) {}
      run('xcrun', ['simctl', 'bootstatus', udid, '-b'], { stdio: 'ignore' });
      run('xcrun', ['simctl', 'install', udid, app]);
      run('xcrun', ['simctl', 'ui', udid, 'appearance', 'dark']);
      for (const sc of SCENARIOS) {
        if (only && !only.includes(sc.name)) continue;
        for (const lang of langs) {
          const tag = `${key}_${sc.name}_${lang}`;
          const dir = path.join(OUT, tag);
          fs.mkdirSync(dir, { recursive: true });
          const report = path.join(dir, 'native.json');
          fs.rmSync(report, { force: true });
          try { run('xcrun', ['simctl', 'terminate', udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
          run('xcrun', ['simctl', 'launch', udid, BUNDLE, '-AppleLanguages', `(${lang})`, '-AppleLocale', LOC[lang],
            '-LPShotNow', '2026-09-23T13:00:00+07:00', '-LPShotZone', 'Asia/Barnaul', '-LPShotSeed', path.join(FX, 'seed.json'),
            '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
            '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', sc.screen, '-LPShotReportDelay', '3',
            ...(sc.sheet ? ['-LPShotSheet', 'loc'] : []), ...(sc.follow ? ['-LPShotFollow', sc.follow] : []),
            ...(sc.ar ? ['-LPSunAR', '1', '-LPSunARFakeCamera', '1', '-LPSunARPhone', '53.3548,83.7698,Asia/Barnaul',
              '-lightplan.native.sunar.calibrationSeen', 'YES'] : []),
            '-LPShotReport', report]);
          for (let i = 0; i < 160 && !fs.existsSync(report); i++) await sleep(250);
          if (!fs.existsSync(report)) throw new Error('нет рамок: ' + tag);
          await sleep(400);
          run('xcrun', ['simctl', 'io', udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
          const rep = JSON.parse(fs.readFileSync(report, 'utf8'));
          const nodes = rep.nodes || {};
          // Окно: ширина и высота вместе с безопасными зонами (рамки узлов — в координатах окна).
          const W = rep.size[0], H = rep.size[1] + rep.safe[0] + rep.safe[1];
          const bad = verdict(sc, nodes, W, H);
          const keys = ['header.name', 'header.follow', 'loc.here', 'loc.fix', 'loc.follow', 'loc.followNote', 'loc.way.addr', 'loc.way.geo', 'loc.openSettings', 'ar.back', 'ar.follow'];
          const brief = Object.fromEntries(keys.filter(k => nodes[k]).map(k => [k, { x: +nodes[k].x.toFixed(1), y: +nodes[k].y.toFixed(1), w: +nodes[k].w.toFixed(1), h: +nodes[k].h.toFixed(1), text: nodes[k].text }]));
          rows.push({ tag, bad, nodes: brief });
        }
      }
    }
  } finally {
    if (!args.keep) for (const u of made) { try { run('xcrun', ['simctl', 'delete', u], { stdio: 'ignore' }); } catch (e) {} }
  }
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(rows, null, 2));
  let failed = 0;
  for (const r of rows) {
    if (r.bad.length) failed++;
    const n = r.nodes;
    const f = k => n[k] ? `${k.replace(/^(loc|header|ar)\./, '')} y${n[k].y} h${n[k].h}` : '';
    console.log(`${r.bad.length ? 'НЕТ' : 'да '} ${r.tag.padEnd(22)} ${[f('header.follow'), f('ar.follow'), f('loc.here'), f('loc.follow'), f('loc.way.geo')].filter(Boolean).join(' · ')}${r.bad.length ? '\n     ' + r.bad.join('\n     ') : ''}`);
    if (n['loc.followNote']) console.log(`     подпись: «${n['loc.followNote'].text}» · строка точки: «${(n['loc.fix'] || {}).text || ''}»`);
  }
  console.log(`${rows.length - failed} из ${rows.length} без нарушений · ${OUT}`);
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error(e.message); process.exit(2); });
