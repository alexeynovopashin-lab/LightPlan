#!/usr/bin/env node
/* Стенд малых движений «Съёмок» (29.2в, правило 14: сначала на старом коде).
   Сборка Debug ставится на симулятор ветки, приложение само делает движение (`-LPMotionBench <имя>`,
   `PlannerMotionBench.swift`), `simctl io recordVideo` пишет кадры, `Tools/motion/frames.swift` режет область
   в серые байты, `Tools/motion/measure.js` считает числа: когда началось и кончилось, сколько кадров в пути,
   какая кривая и длительность подходят лучше всего (E1, ease-out, ease-in-out, линейная), смещение, прозрачность.

     node Tools/motion_bench.js [--scenario month,week,bar,fan,tab,ring] [--theme dark|light] [--reduce]
                                [--skip-build] [--out <папка>] [--check]

   `--check` сверяет числа с бетой (красный = выход 1); без него только печатает. `--reduce` включает
   «Уменьшение движения» симулятора на время прогона. Видео и кадры лежат в `--out`. */
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync, spawn } = require('child_process');
const sim = require('./sim');
const M = require('./motion/measure');

const ROOT = path.resolve(__dirname, '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = {};
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a.startsWith('--')) {
    const k = a.slice(2), nx = process.argv[i + 1];
    if (nx && !nx.startsWith('--')) { args[k] = nx; i++; } else args[k] = true;
  }
}
const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-motion', sim.nameFor(ROOT).replace(/\W+/g, '-')));
fs.mkdirSync(OUT, { recursive: true });
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const BUNDLE = 'Novopashin.LightPlan';
const ZONE = 'Asia/Barnaul';
const THEME = args.theme || 'dark';
const AGAIN = !!args.again;   // не писать заново: пересчитать числа по видео и журналу, что лежат в --out
const SCENARIOS = (args.scenario || 'month,week,bar,fan,tab,ring').split(',');

function build(udid) {
  const dd = path.join(OUT, 'DerivedData');
  const log = path.join(OUT, 'xcodebuild.log');
  try {
    run('xcodebuild', ['-project', path.join(ROOT, 'LightPlan.xcodeproj'), '-scheme', 'LightPlan-iOS', '-configuration', 'Debug',
      '-destination', 'platform=iOS Simulator,id=' + udid, '-derivedDataPath', dd, 'build'],
    { stdio: ['ignore', fs.openSync(log, 'w'), fs.openSync(log, 'a')] });
  } catch (e) {
    const errs = fs.readFileSync(log, 'utf8').split('\n').filter(l => /error:/.test(l)).slice(0, 10);
    throw new Error('сборка упала (' + log + '):\n' + errs.join('\n'));
  }
  const products = path.join(dd, 'Build', 'Products', 'Debug-iphonesimulator');
  return path.join(products, fs.readdirSync(products).find(f => f.endsWith('.app')));
}

function frames(video, region, bin) {
  const tool = path.join(OUT, 'frames');
  if (!fs.existsSync(tool)) run('xcrun', ['swiftc', '-O', path.join(__dirname, 'motion', 'frames.swift'), '-o', tool]);
  run(tool, [video, bin, ...region.map(v => String(Math.round(v)))]);
  return M.readFrames(bin);
}

async function scenario(udid, name) {
  const dir = path.join(OUT, name + (args.reduce ? '-still' : '') + '-' + THEME);
  if (!AGAIN) fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  const seed = JSON.parse(fs.readFileSync(path.join(FX, 'seed_planner.json'), 'utf8'));
  const seedFile = path.join(dir, 'seed.json');
  fs.writeFileSync(seedFile, JSON.stringify({ ...seed, theme: THEME, pro: false, drumSlot: 'paper', ribbonMode: 'drum' }));
  const logFile = path.join(dir, 'bench.log'), report = path.join(dir, 'native.json'), video = path.join(dir, 'video.mp4');
  const spec = M.SPEC[name];
  if (AGAIN) {
    const nodes = JSON.parse(fs.readFileSync(report, 'utf8')).nodes, log = fs.readFileSync(logFile, 'utf8');
    const region = spec.region(nodes, log);
    return { dir, log, nodes, fr: frames(video, region.rect, path.join(dir, 'frames.bin')), region };
  }
  try { run('xcrun', ['simctl', 'terminate', udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
  run('xcrun', ['simctl', 'ui', udid, 'appearance', THEME]);
  const rec = spawn('xcrun', ['simctl', 'io', udid, 'recordVideo', '--codec=h264', '--force', video], { stdio: 'ignore' });
  await sleep(2500);
  run('xcrun', ['simctl', 'launch', udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
    '-LPShotNow', spec.now || '2026-09-23T13:00:00+07:00', '-LPShotZone', ZONE, '-LPShotSeed', seedFile,
    '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
    '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'planner', '-LPShotScope', spec.scope,
    '-LPShotReport', report, '-LPShotReportDelay', '3', '-LPPartLog', logFile, '-LPMotionBench', name],
  { env: { ...process.env, SIMCTL_CHILD_TZ: ZONE } });
  for (let i = 0; i < 240 && !(fs.existsSync(logFile) && / done/.test(fs.readFileSync(logFile, 'utf8'))); i++) await sleep(250);
  await sleep(1200);
  rec.kill('SIGINT');
  await new Promise(r => rec.on('exit', r));
  if (!fs.existsSync(logFile)) throw new Error('стенд не отметился: ' + name);
  const nodes = JSON.parse(fs.readFileSync(report, 'utf8')).nodes;
  const log = fs.readFileSync(logFile, 'utf8');
  const region = spec.region(nodes, log);
  const fr = frames(video, region.rect, path.join(dir, 'frames.bin'));
  return { dir, log, nodes, fr, region };
}

(async () => {
  const dev = sim.device(ROOT);
  console.log('симулятор: ' + dev.name + ' · вывод: ' + OUT);
  run('xcrun', ['simctl', 'status_bar', dev.udid, 'override', '--time', '9:41', '--batteryState', 'charged',
    '--batteryLevel', '100', '--cellularBars', '4', '--wifiBars', '3']);
  if (!args['skip-build'] && !AGAIN) {
    const app = build(dev.udid);
    run('xcrun', ['simctl', 'install', dev.udid, app]);
    console.log('собрано и поставлено: ' + path.basename(app));
  }
  const reduce = v => AGAIN ? 0 : run('xcrun', ['simctl', 'spawn', dev.udid, 'defaults', 'write', 'com.apple.Accessibility', 'ReduceMotionEnabled', '-bool', v]);
  if (args.reduce) reduce('YES');
  let red = 0;
  try {
    for (const name of SCENARIOS) {
      const r = await scenario(dev.udid, name);
      const res = M.analyze(name, r, { still: !!args.reduce, check: !!args.check });
      console.log('\n== ' + name + (args.reduce ? ' (уменьшение движения)' : '') + ' · ' + THEME + ' ==');
      for (const l of res.lines) console.log('  ' + l);
      fs.writeFileSync(path.join(r.dir, 'result.json'), JSON.stringify(res, null, 1));
      red += res.red;
    }
  } finally {
    if (args.reduce) reduce('NO');
  }
  if (args.check) { console.log(red ? `\nКРАСНЫЙ: ${red}` : '\nзелёный'); process.exit(red ? 1 : 0); }
})().catch(e => { console.error(e.message); process.exit(1); });
