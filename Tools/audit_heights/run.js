#!/usr/bin/env node
/* Аудит высот: те же экраны на разных моделях iPhone (read-only, код приложения не трогает).
   Для каждой модели и сцены запускает готовую Debug-сборку теми же аргументами `-LPShot…`, что и
   `Tools/shots/pair.js`, и кладёт `<out>/<модель>/<сцена>-<тема>/{native.png,native.json}`.
   native.json — рамки узлов из `ShotProbe` (в точках окна); анализ — `analyze.py`.

     node Tools/audit_heights/run.js --app <.app> --out <папка> [--models A15P,A17P,A15PM,A17PM,ASE3]
                                     [--scenes map,card_event_before,…] [--themes dark,light]

   Модели — симуляторы `Audit-<код>` (создаются заранее `simctl create`), по одному за раз.
   Экран «Свет» пропущен: его переделывает другая сессия. */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const BUNDLE = 'Novopashin.LightPlan';
const ZONE = 'Asia/Barnaul', OFFSET = '+07:00', AT = '2026-09-23T13:00';
const args = {};
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a.startsWith('--')) { const k = a.slice(2), nx = process.argv[i + 1]; if (nx && !nx.startsWith('--')) { args[k] = nx; i++; } else args[k] = true; }
}
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const OUT = path.resolve(args.out || path.join(require('os').tmpdir(), 'lp-audit'));
const APP = path.resolve(args.app || '');
const MODELS = (args.models || 'A15P,A17P,A15PM,A17PM,ASE3').split(',');
const THEMES = (args.themes || 'dark').split(',');

const seed = JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8'));
const plannerSeed = JSON.parse(fs.readFileSync(path.join(FX, 'seed_planner.json'), 'utf8'));
const wallAt = (iso, m) => new Date(Date.parse(iso) + 7 * 3600e3 + m * 60e3).toISOString().slice(0, 16);

/* Мудборды (как в pair.js, итерация 28). */
const link = (id, n, tags) => ({ id, k: 'link', url: 'https://ru.pinterest.com/pin/' + n + '/', tags });
const WED = ['couple', 'bride', 'groom', 'walk', 'evening', 'details', 'gathering'];
const M28_SHOTS = [...Array.from({ length: 10 }, (_, i) => link('sh_m28_w' + i, 100 + i, [WED[i % 7]])),
  link('sh_m28_s0', 200, ['couple']), link('sh_m28_s1', 201, ['evening']),
  link('sh_m28_p0', 300, ['light']), link('sh_m28_p1', 301, []), link('sh_m28_p2', 302, []),
  link('sh_m28_l0', 400, []), link('sh_m28_l1', 401, []), link('sh_m28_i0', 500, []), link('sh_m28_i1', 501, ['light'])];
const M28_BOARDS = [
  { id: 'bd_m28_own', kind: 'shoot', sid: 'sd_sep_wed', genre: 'wedding', items: ['sh_m28_w0', 'sh_m28_w1', 'sh_m28_w4'], name: null, cover: null },
  { id: 'bd_m28_wed', kind: 'tpl', genre: 'wedding', items: Array.from({ length: 10 }, (_, i) => 'sh_m28_w' + i), name: null, cover: null },
  { id: 'bd_m28_sea', kind: 'tpl', genre: 'wedding', items: ['sh_m28_s0', 'sh_m28_s1', 'sh_m28_w3'], name: 'На море', cover: null },
  { id: 'bd_m28_por', kind: 'tpl', genre: 'portrait', items: ['sh_m28_p0', 'sh_m28_p1', 'sh_m28_p2'], name: null, cover: null },
  { id: 'bd_m28_lan', kind: 'tpl', genre: 'landscape', items: ['sh_m28_l0', 'sh_m28_l1'], name: null, cover: null },
  { id: 'bd_m28_int', kind: 'tpl', genre: 'architecture', items: ['sh_m28_i0', 'sh_m28_i1'], name: null, cover: null }];
const M28_DOCS = { sd_org_agency: [{ k: 'link', url: 'https://disk.yandex.ru/d/agency-contract', kind: 'acceptance' },
  { k: 'link', url: 'https://disk.yandex.ru/d/agency-release', kind: 'release' }],
  sd_org_rest: [{ k: 'link', url: 'https://disk.yandex.ru/d/rest-act', kind: 'acceptance' }] };
const SPOTS = [
  { id: 'p_shot_a', name: 'Нагорный парк', address: 'ул. Гоголя, 2', lat: 53.3334, lon: 83.8035, pinned: true },
  { id: 'p_shot_b', name: '', address: '', lat: 53.35, lon: 83.75, pinned: true }];
const CARDS = { event: 'sd_sep_wed', people: 'sd_sep_clash_a', client: 'sd_sep_inter', own: 'sd_aug_land' };

/* Сцена: { name, group, seed(theme) -> объект, at, launch: [аргументы], extra: аргументы запуска без -LPShot… } */
const S = [];
const add = (name, group, mk, launch, o = {}) => S.push({ name, group, mk, launch, ...o });
const base = th => ({ ...seed, theme: th, pro: false, drumSlot: 'paper', ribbonMode: 'drum' });
const pl = th => ({ ...plannerSeed, theme: th, pro: false, drumSlot: 'paper', ribbonMode: 'drum' });
const m28 = th => ({ ...pl(th), shots: M28_SHOTS, boards: M28_BOARDS, orgs: plannerSeed.orgs.map(o => M28_DOCS[o.id] ? { ...o, docs: M28_DOCS[o.id] } : o) });

// Карта
const mapSeed = (th, o = {}) => ({ ...base(th), mapLayers: { sun: true, moon: true, mw: !!o.mw, compass: true, spots: true }, mapFold: !o.open, spots: SPOTS, ...(o.route ? { mapRoute: SPOTS.map(x => x.id) } : {}) });
add('map', 'Карта', th => mapSeed(th), ['-LPShotScreen', 'map']);
add('map_fold', 'Карта', th => mapSeed(th, { open: true, mw: true }), ['-LPShotScreen', 'map']);
add('map_route', 'Карта', th => mapSeed(th, { route: true }), ['-LPShotScreen', 'map', '-LPShotChapter', 'route']);
add('map_place_fork', 'Карта', th => mapSeed(th), ['-LPShotScreen', 'map', '-LPShotSheet', 'loc']);
add('map_place_addr', 'Place', th => mapSeed(th), ['-LPShotScreen', 'map', '-LPShotSheet', 'loc', '-LPShotWay', 'addr']);
add('map_place_geo', 'Place', th => mapSeed(th), ['-LPShotScreen', 'map', '-LPShotSheet', 'loc', '-LPShotWay', 'geo']);
// Съёмки
for (const sc of ['month', 'week', 'day']) add('plan_' + sc, 'Съёмки', pl, ['-LPShotScreen', 'planner', '-LPShotScope', sc]);
add('plan_day26', 'Съёмки', pl, ['-LPShotScreen', 'planner', '-LPShotScope', 'day', '-LPShotPick', '5']);
for (const l of ['year', 'year12', 'stats', 'search', 'blk']) add('plan_' + l, 'Съёмки', pl, ['-LPShotScreen', 'planner', '-LPShotScope', 'month', '-LPShotSheet', l]);
add('plan_bin', 'Съёмки', th => { const s = pl(th); const recs = s.sessions.slice(0, 2); s.sessions = s.sessions.slice(2);
  s.trashed = recs.map((rec, i) => ({ rec, at: i, del: Date.parse('2026-09-23T12:00:00+07:00') - i * 60000 })); return s; },
  ['-LPShotScreen', 'planner', '-LPShotScope', 'month', '-LPShotSheet', 'bin']);
// Настройки
add('set_root', 'Настройки', base, ['-LPShotScreen', 'settings']);
for (const ch of ['profile', 'view', 'shoots', 'alerts', 'places', 'store', 'data', 'network', 'locale', 'about'])
  add('set_' + ch, 'Настройки', base, ['-LPShotScreen', 'settings', '-LPShotChapter', ch]);
// Карточка
for (const [g, id] of Object.entries(CARDS)) for (const ph of ['before', 'during', 'after']) {
  if (g !== 'event' && ph !== (g === 'people' ? 'during' : g === 'client' ? 'before' : 'after')) continue;
  add(`card_${g}_${ph}`, 'Card', pl, ['-LPShotScreen', 'planner', '-LPShotSheet', 'card', '-LPShotWay', id], { card: { id, ph } });
}
add('card_stack', 'Card', th => { const s = pl(th); const b = s.sessions.find(x => x.id === 'sd_sep_clash_b');
  s.sessions = [...s.sessions, { ...b, id: 'shot_st_meet', kind: 'meet', min: 600, end: 645, dur: 45, contact: 'Анна Лис', persons: [] },
    { ...b, id: 'shot_st_eve', min: 1020, end: 1110, dur: 90, contact: 'Пётр Сомов', persons: [] },
    { ...b, id: 'shot_st_late', min: 1140, end: 1200, dur: 60, contact: 'Ольга Верх', persons: [] }]; return s; },
  ['-LPShotScreen', 'planner', '-LPShotSheet', 'card', '-LPShotWay', 'sd_sep_clash_a'], { card: { id: 'sd_sep_clash_a', ph: 'during' } });
add('card_tune', 'Card', pl, ['-LPShotScreen', 'planner', '-LPShotSheet', 'card', '-LPShotWay', CARDS.client, '-LPShotTune', '1'], { card: { id: CARDS.client, ph: 'before' } });
add('card_panes', 'Card', th => { const s = pl(th); s.sessions = s.sessions.map(x => x.id !== 'sd_oct_wed_kem' ? x : { ...x, gear: ['body', 'lens', 'flash'] }); return s; },
  ['-LPShotScreen', 'planner', '-LPShotSheet', 'card', '-LPShotWay', 'sd_oct_wed_kem'], { card: { id: 'sd_oct_wed_kem', ph: 'before' } });
add('card_route', 'Card', th => { const s = pl(th); return s; }, ['-LPShotScreen', 'planner', '-LPShotSheet', 'card', '-LPShotWay', CARDS.event, '-LPShotFold', 'route'], { card: { id: CARDS.event, ph: 'during' } });
// Форма
for (const g of ['portrait', 'wedding', 'report']) add('form_' + g, 'Form', base, ['-LPShotScreen', 'planner', '-LPShotSheet', 'form', '-LPShotWay', g]);
add('form_meet', 'Form', m28, ['-LPShotScreen', 'planner', '-LPShotScope', 'month', '-LPShotSheet', 'meet']);
// Мудборд, организации, документы
for (const [n, way] of [['mbgallery', null], ['mbshelf', 'wedding'], ['mbfolder', 'bd_m28_wed']])
  add('mb_' + n.slice(2), 'Moodboard', m28, ['-LPShotScreen', 'planner', '-LPShotScope', 'month', '-LPShotSheet', n, ...(way ? ['-LPShotWay', way] : [])]);
// Длинные мудборды (кнопка прыжка видна): сорок кадров в папке, восемнадцать лишних подборок в галерее.
const mLong = th => { const s = m28(th); const extra = Array.from({ length: 40 }, (_, i) => link('sh_long' + i, 300 + i, [WED[i % 7]]));
  s.shots = [...M28_SHOTS, ...extra];
  s.boards = [...M28_BOARDS.map(b => b.id === 'bd_m28_wed' ? { ...b, items: [...b.items, ...extra.map(e => e.id)] } : b),
    ...Array.from({ length: 18 }, (_, i) => ({ id: 'bd_long' + i, kind: 'tpl', genre: 'wedding', items: ['sh_m28_w0'], name: 'Подборка ' + (i + 1), cover: null })),
    ...s.sessions.slice(0, 14).filter(x => x.id !== 'sd_sep_wed').map((x, i) => ({ id: 'bd_ownx' + i, kind: 'shoot', sid: x.id, genre: x.genre, items: ['sh_m28_w' + (i % 10)], name: null, cover: null }))];
  return s; };
add('mb_gallery_long', 'Moodboard', mLong, ['-LPShotScreen', 'planner', '-LPShotScope', 'month', '-LPShotSheet', 'mbgallery']);
add('mb_gallery_tag', 'Moodboard', mLong, ['-LPShotScreen', 'planner', '-LPShotScope', 'month', '-LPShotSheet', 'mbgallery', '-LPShotWay', 'tag:couple']);
add('mb_folder_long', 'Moodboard', mLong, ['-LPShotScreen', 'planner', '-LPShotScope', 'month', '-LPShotSheet', 'mbfolder', '-LPShotWay', 'bd_m28_wed']);
add('org_list', 'Org', m28, ['-LPShotScreen', 'planner', '-LPShotScope', 'month', '-LPShotSheet', 'orgs']);
add('org_card', 'Org', m28, ['-LPShotScreen', 'planner', '-LPShotScope', 'month', '-LPShotSheet', 'orgcard', '-LPShotWay', 'sd_org_agency']);
add('org_contacts', 'Org', m28, ['-LPShotScreen', 'planner', '-LPShotScope', 'month', '-LPShotSheet', 'contacts']);
add('quest', 'Card', m28, ['-LPShotScreen', 'planner', '-LPShotScope', 'month', '-LPShotSheet', 'quest', '-LPShotWay', 'sd_sep_wed']);
for (const [n, way] of [['sections', null], ['recent', 'recent'], ['paper', 'recent+paper'], ['add', 'recent+add'], ['edit', 'recent+edit']])
  add('docs_' + n, 'Docs', m28, ['-LPShotScreen', 'planner', '-LPShotScope', 'month', '-LPShotSheet', 'docs', ...(way ? ['-LPShotWay', way] : [])]);
// Первый запуск (знакомство): сид без `me.met`
add('onboarding', 'Onboarding', th => { const s = base(th); s.me = { ...s.me }; delete s.me.met; return s; }, ['-LPShotScreen', 'settings']);
// AR
const AR = (name, extra, o = {}) => add(name, 'SunAR', base, ['-LPShotScreen', 'map', '-LPShotReportDelay', '5',
  '-lightplan.native.sunar.calibrationSeen', 'YES', '-lightplan.native.sunar.moon', 'YES', '-lightplan.native.sunar.milkyWay', 'NO',
  '-LPSunAR', '1', '-LPSunARMoment', '2026-10-14T05:00:00Z', '-LPSunARPose', '162,24,0', '-LPSunARPhone', '56.4977,84.9744,Asia/Tomsk',
  '-LPSunARFakeCamera', '1', ...extra], { now: '2026-10-14T12:00:00+07:00', zone: 'Asia/Tomsk', after: 1500, ...o });
AR('ar_day', []);
AR('ar_layers', ['-LPSunARLayersOpen', '1']);
AR('ar_entry', ['-LPSunAREntry', '1']);

async function shoot(model, udid, sc, theme) {
  const dir = path.join(OUT, model, `${sc.name}-${theme}`);
  fs.mkdirSync(dir, { recursive: true });
  const report = path.join(dir, 'native.json');
  fs.rmSync(report, { force: true });
  const sf = path.join(dir, 'seed.json');
  fs.writeFileSync(sf, JSON.stringify(sc.mk(theme)));
  let at = sc.now || AT + ':00' + OFFSET;
  if (sc.card) {
    const s = sc.mk(theme), rec = s.sessions.find(x => x.id === sc.card.id), end = rec.end != null ? rec.end : rec.min + (rec.dur || 90);
    at = wallAt(rec.date, sc.card.ph === 'before' ? rec.min - 120 : sc.card.ph === 'during' ? rec.min + 30 : end + 60) + ':00' + OFFSET;
  }
  try { run('xcrun', ['simctl', 'terminate', udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
  run('xcrun', ['simctl', 'ui', udid, 'appearance', theme]);
  const zone = sc.zone || ZONE;
  run('xcrun', ['simctl', 'launch', udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
    '-LPShotNow', at, '-LPShotZone', zone, '-LPShotSeed', sf, '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'),
    '-LPShotAir', path.join(FX, 'air_barnaul.json'), '-LPShotName', path.join(FX, 'place_barnaul.json'),
    ...sc.launch, ...(args.sjlog ? ['-LPScrollJumpLog', path.join(dir, 'scrolljump.log')] : []), '-LPShotReport', report], { env: { ...process.env, SIMCTL_CHILD_TZ: zone } });
  for (let i = 0; i < 160 && !fs.existsSync(report); i++) await sleep(250);
  const ok = fs.existsSync(report);
  await sleep(sc.after || 500);
  run('xcrun', ['simctl', 'io', udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
  return ok;
}

(async () => {
  const only = args.scenes ? args.scenes.split(',') : null;
  const list = S.filter(s => !only || only.includes(s.name));
  const sims = JSON.parse(run('xcrun', ['simctl', 'list', 'devices', '-j'])).devices;
  const all = Object.values(sims).flat();
  for (const model of MODELS) {
    const dev = all.find(d => d.name === (args.sim || 'Audit-' + model));
    if (!dev) { console.error('нет симулятора Audit-' + model); continue; }
    const boot = async () => {
      for (let t = 0; t < 40; t++) {      // симулятор может ещё гаснуть после прошлого прогона или падения службы
        try { run('xcrun', ['simctl', 'boot', dev.udid], { stdio: 'ignore' }); } catch (e) {}
        try {
          run('xcrun', ['simctl', 'bootstatus', dev.udid, '-b'], { stdio: 'ignore' });
          run('xcrun', ['simctl', 'status_bar', dev.udid, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100', '--cellularBars', '4', '--wifiBars', '3'], { stdio: 'ignore' });
          run('xcrun', ['simctl', 'install', dev.udid, APP], { stdio: 'ignore' });
          return;
        } catch (e) { await sleep(3000); }
      }
      throw new Error('симулятор не поднялся: ' + model);
    };
    await boot();
    const miss = [];
    for (const sc of list) for (const th of (sc.themes || THEMES)) {
      const png = path.join(OUT, model, `${sc.name}-${th}`, 'native.png');
      if (args.resume && fs.existsSync(png)) continue;
      let done = false;
      for (let attempt = 0; attempt < 2 && !done; attempt++) {
        try { done = await shoot(model, dev.udid, sc, th); if (!done) break; }
        catch (e) { await sleep(2000); try { run('xcrun', ['simctl', 'shutdown', dev.udid], { stdio: 'ignore' }); } catch (e2) {} await boot(); }
      }
      if (!done) miss.push(sc.name + '-' + th);
    }
    console.log(`${model}: без рамок: ${miss.join(', ') || 'нет'}`);
    try { run('xcrun', ['simctl', 'shutdown', dev.udid], { stdio: 'ignore' }); } catch (e) {}
  }
})();
