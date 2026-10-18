#!/usr/bin/env node
/* Шаг 29.8в.8: экран калибровки компаса в симуляторе на подставном потоке датчиков (`-LPSunARCalibScript`).
   Только натив: у веба AR нет. Датчиков в симуляторе нет, поэтому поток — формула (`CalibrationScript`), та же,
   что гоняют юнит-тесты; настоящие руки и магнитное поле — только на телефоне.

   Сценарии (кадр снимается на `delay`-й секунде от запуска приложения; время хода калибровки — от входа на экран):
     start      телефон лежит, система говорит ±25°: шкала 0
     mid        восьмёрка вполовину размаха: шкала ≈ ⅔, подсказки ещё нет
     hint       то же, шкала стоит дольше 4 с: подсказка «наклоняйте сильнее»
     notbetter  восьмёрка полная, а точность осталась ±25°: «лучше не стал», «Ещё раз», «Готово» недоступна
     ready      восьмёрка полная, точность ±25° → ±8°: «Готово» доступна
     ready_late то же, но кадр снят через 16 с: экран на месте (сам не закрылся)
     reduce     «Готово» с «Уменьшением движения»: статичная схема со стрелками
   Устройства: 17 Pro Max (440 pt, симулятор ветки), iPhone 15 (393 pt) и SE 3 (375 pt) — последние два создаются
   здесь и удаляются в конце (`--keep` оставляет). Языки на SE: `--langs ru,en,es,ja,zh` (сценарии start и notbetter).

   Числа из рамок узлов: все узлы внутри экрана, текст не залезает на кнопки, кнопки ≥ 44 pt, шкала и фаза те, что
   ждёт сценарий. Нарушение — код 1.

     node Tools/shots/ar_cal.js [--skip-build] [--devices max,15,se] [--only a,b] [--langs ru,...] [--out <dir>] [--keep] */
const fs = require('fs'), os = require('os'), path = require('path');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : []).filter(x => x.length));
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const BUNDLE = 'Novopashin.LightPlan';
const RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-26-5';

const SCENARIOS = [
  { name: 'start', script: 'still', acc: '25,25', delay: 3, phase: 'measuring', scale: [0, 0], accLine: /25/, buzz: { ticks: [0, 0], done: 0 } },
  { name: 'mid', script: 'eight:0.5', acc: '25,25', delay: 4, phase: 'measuring', scale: [0.4, 0.9], hint: false },
  { name: 'hint', script: 'eight:0.5', acc: '25,25', delay: 18, phase: 'measuring', scale: [0.4, 0.9], hint: true },
  { name: 'notbetter', script: 'eight:1', acc: '25,25', delay: 10, phase: 'notImproved', scale: [1, 1], retry: true, done: false, lang: true },
  { name: 'ready', script: 'eight:1', acc: '25,8,2', delay: 6, phase: 'ready', scale: [1, 1], done: true, accLine: /25.*8/, buzz: { ticks: [10, 99], done: 1 } },
  { name: 'ready_late', script: 'eight:1', acc: '25,8,2', delay: 16, phase: 'ready', scale: [1, 1], done: true, buzz: { ticks: [10, 99], done: 1 } },
  { name: 'reduce', script: 'eight:1', acc: '25,8,2', delay: 6, phase: 'ready', scale: [1, 1], done: true, reduce: true },
];
const LOC = { ru: 'ru_RU', en: 'en_US', es: 'es_ES', ja: 'ja_JP', zh: 'zh_CN' };
const DEVICES = {
  max: { pt: 440, name: null },
  15: { pt: 393, type: 'com.apple.CoreSimulator.SimDeviceType.iPhone-15', name: 'LP wt-29-8v8 15' },
  se: { pt: 375, type: 'com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation', name: 'LP wt-29-8v8 se' },
};

/* Журнал отдачи (`-LPHapticLog`): строка на щелчок `calib.tick` и на сигнал конца `calib.done`. Тактильности в симуляторе нет,
   меряем журнал: сколько щелчков, один ли сигнал, нет ли щелчков после него, не чаще ли 50 мс друг от друга. */
function buzzVerdict(sc, file) {
  const bad = [];
  if (!sc.buzz) return bad;
  const lines = fs.existsSync(file) ? fs.readFileSync(file, 'utf8').split('\n').filter(Boolean) : [];
  const rows = lines.map(l => { const m = /^([0-9.]+) calib\.(tick|done)/.exec(l); return m && { t: +m[1], k: m[2] }; }).filter(Boolean);
  const ticks = rows.filter(r => r.k === 'tick'), done = rows.filter(r => r.k === 'done');
  if (ticks.length < sc.buzz.ticks[0] || ticks.length > sc.buzz.ticks[1]) bad.push(`щелчков ${ticks.length} вне ${sc.buzz.ticks}`);
  if (done.length !== sc.buzz.done) bad.push(`сигналов конца ${done.length}, ждали ${sc.buzz.done}`);
  if (done.length && ticks.some(t => t.t > done[0].t)) bad.push('щелчки после сигнала конца');
  for (let i = 1; i < ticks.length; i++) if (ticks[i].t - ticks[i - 1].t < 0.0495) bad.push(`щелчки через ${(ticks[i].t - ticks[i - 1].t) * 1000 | 0} мс < 50`);
  sc.buzzCount = `щелчков ${ticks.length}, сигналов ${done.length}`;
  return bad;
}

function verdict(sc, nodes, W, H) {
  const bad = [];
  const need = k => nodes[k] || (bad.push('нет узла ' + k), null);
  const screen = need('ar.cal.screen');
  if (!screen) return bad;
  if (screen.text !== sc.phase) bad.push(`фаза ${screen.text}, ждали ${sc.phase}`);
  const scale = need('ar.cal.scale');
  if (scale) {
    const p = parseFloat(scale.text);
    if (p < sc.scale[0] - 1e-9 || p > sc.scale[1] + 1e-9) bad.push(`шкала ${scale.text} вне ${sc.scale}`);
  }
  // Все узлы внутри экрана; текст не залезает под кнопки.
  const row = ['ar.cal.title', 'ar.cal.scale', 'ar.cal.acc', 'ar.cal.text', 'ar.cal.why', 'ar.cal.hint'].filter(k => nodes[k]);
  for (const k of [...row, 'ar.cal.done', 'ar.cal.retry', 'ar.cal.skip'].filter(k => nodes[k])) {
    const n = nodes[k];
    if (n.x < -0.5 || n.x + n.w > W + 0.5 || n.y < 0 || n.y + n.h > H + 0.5) bad.push(`${k}: рамка ${n.x.toFixed(0)},${n.y.toFixed(0)} ${n.w.toFixed(0)}×${n.h.toFixed(0)} вне экрана ${W}×${H}`);
  }
  const buttons = ['ar.cal.done', 'ar.cal.retry', 'ar.cal.skip'].filter(k => nodes[k]);
  const buttonsTop = Math.min(...buttons.map(k => nodes[k].y));
  for (const k of row) if (nodes[k].y + nodes[k].h > buttonsTop - 2) bad.push(`${k}: низ ${(nodes[k].y + nodes[k].h).toFixed(0)} залезает на кнопки (верх ${buttonsTop.toFixed(0)})`);
  for (const k of buttons) if (nodes[k].h < 44 - 0.5) bad.push(`${k}: высота ${nodes[k].h.toFixed(0)} < 44`);
  if (!nodes['ar.cal.skip']) bad.push('«Пропустить» должна быть всегда');
  if (sc.done !== undefined) {
    const d = nodes['ar.cal.done'];
    if (!d) bad.push('нет «Готово»'); else if (/\(off\)/.test(d.text) === sc.done) bad.push(`«Готово» ${sc.done ? 'должна быть доступна' : 'должна быть недоступна'}: «${d.text}»`);
  }
  if (sc.retry && !nodes['ar.cal.retry']) bad.push('нет «Ещё раз»');
  if (!sc.retry && nodes['ar.cal.retry']) bad.push('«Ещё раз» не к месту');
  if (sc.hint !== undefined && !!nodes['ar.cal.hint'] !== sc.hint) bad.push(`подсказка ${nodes['ar.cal.hint'] ? 'есть' : 'нет'}, ждали ${sc.hint ? 'есть' : 'нет'}`);
  if (sc.accLine && nodes['ar.cal.acc'] && !sc.accLine.test(nodes['ar.cal.acc'].text)) bad.push(`строка точности «${nodes['ar.cal.acc'].text}»`);
  return bad;
}

(async () => {
  const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-shots', 'ar_cal'));
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
  const langs = args.langs ? String(args.langs).split(',') : ['ru'];
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
        for (const lang of (sc.lang || sc.name === 'start') && key === 'se' ? langs : ['ru']) {
          const tag = `${key}_${sc.name}${lang === 'ru' ? '' : '_' + lang}`;
          const dir = path.join(OUT, tag);
          fs.mkdirSync(dir, { recursive: true });
          const report = path.join(dir, 'native.json');
          fs.rmSync(report, { force: true }); fs.rmSync(path.join(dir, 'haptic.log'), { force: true });
          try { run('xcrun', ['simctl', 'terminate', udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
          run('xcrun', ['simctl', 'launch', udid, BUNDLE, '-AppleLanguages', `(${lang})`, '-AppleLocale', LOC[lang],
            '-LPShotNow', '2026-10-14T12:00:00+07:00', '-LPShotZone', 'Asia/Tomsk', '-LPShotSeed', path.join(FX, 'seed.json'),
            '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
            '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'map', '-LPShotReportDelay', String(sc.delay),
            '-lightplan.native.sunar.calibrationSeen', 'NO', '-lightplan.native.sunar.moon', 'NO', '-lightplan.native.sunar.milkyWay', 'NO',
            '-LPSunAR', '1', '-LPSunARCalib', '1', '-LPSunARMoment', '2026-10-14T05:00:00Z', '-LPSunARPhone', '56.4977,84.9744,Asia/Tomsk',
            '-LPSunARCalibScript', sc.script, '-LPSunARCalibAcc', sc.acc, ...(sc.reduce ? ['-LPSunARReduceMotion', '1'] : []),
            '-LPShotReport', report, '-LPHapticLog', path.join(dir, 'haptic.log')]);
          for (let i = 0; i < 120 + sc.delay * 4 && !fs.existsSync(report); i++) await sleep(250);
          if (!fs.existsSync(report)) throw new Error('нет рамок: ' + tag);
          await sleep(300);
          run('xcrun', ['simctl', 'io', udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
          const nodes = JSON.parse(fs.readFileSync(report, 'utf8')).nodes || {};
          const scr = nodes['ar.cal.screen'];
          const bad = scr ? [...verdict(sc, nodes, scr.w, scr.h), ...buzzVerdict(sc, path.join(dir, 'haptic.log'))] : ['нет экрана калибровки'];
          const brief = Object.fromEntries(Object.keys(nodes).filter(k => k.startsWith('ar.cal.')).map(k => [k, { x: +nodes[k].x.toFixed(1), y: +nodes[k].y.toFixed(1), w: +nodes[k].w.toFixed(1), h: +nodes[k].h.toFixed(1), text: nodes[k].text }]));
          rows.push({ tag, bad, nodes: brief, buzz: sc.buzzCount });
        }
      }
    }
  } finally {
    if (!args.keep) for (const u of made) { try { run('xcrun', ['simctl', 'delete', u], { stdio: 'ignore' }); } catch (e) {} }
  }
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(rows, null, 1));
  for (const r of rows) console.log(r.tag + ': ' + (r.bad.length ? 'НАРУШЕНИЯ ' + r.bad.join('; ') : 'ок') +
    `  шкала=${(r.nodes['ar.cal.scale'] || {}).text} acc=«${(r.nodes['ar.cal.acc'] || {}).text}»${r.buzz ? '  ' + r.buzz : ''}`);
  console.log('→ ' + OUT);
  const fails = rows.flatMap(r => r.bad.map(m => `${r.tag}: ${m}`));
  if (fails.length) throw new Error('калибровка: ' + fails.length + ' нарушений:\n' + fails.join('\n'));
})().catch(e => { console.error(e.message); process.exit(1); });
