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
     node Tools/shots/pair.js --forecast /tmp/forecast.json --no-sheets --no-pick
                                                   # своё небо без замены эталонной фикстуры
     node Tools/shots/pair.js --screens planner --scopes day   # «Съёмки» (итерация 21):
                                                   # засев сезона (planner_seed.js), виды месяц/неделя/день
     node Tools/shots/pair.js --screens light --sheets fork,addr,geo   # лист «Где снимаем» (21в)
     node Tools/shots/pair.js --layers year,year12,stats,search,bin,blk --only-layers
                                                   # слои и листы «Съёмок» (итерация 22)
     node Tools/shots/pair.js --screens light --no-weather --themes dark --moments day
                                                   # 28ж: БЕЗ прогноза, только натив: у веба в таком кадре выдумка,
                                                   # у натива — «Прогноз недоступен»; пары нет, в no_weather.json —
                                                   # какие узлы погоды на экране есть и их текст
     node Tools/shots/pair.js --net reachable,unreachable,unknown --themes dark,light
                                                   # 28л.6: глава «Сеть» в «Настройках» — только натив (у веба такой главы нет);
                                                   # состояние детектора подставляется (-LPShotNet), в network.json — рамки,
                                                   # слова и нарушения; прогон падает при нарушении
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
if (args.help) {
  console.log(`Пара снимков «веб / натив» (Tools/shots/pair.js). Запуск из корня натива; ничего не строит и не снимает с --help.
  --screens light,map,planner,settings,card,m28   какие экраны (по умолчанию все)
  --themes dark,light   --moments day,golden,night,dawn   --modes simple,astro   --scopes month,week,day
  --m28 mbgallery,mbshelf,mbfolder,orgs,orgcard,contacts,quest,meet   экраны итерации 28 (мудборды, организации, «Контакты», опросник, встреча); только они: --screens m28
  --drag [block:dy,...]   блок карточки в руке (27а.3, только натив; по умолчанию place:24,place:44): сдвиг, зазор, слот, тень
  --grip [<знак записи>]   лента дня с поднятой записью и ручками (29а; по умолчанию 26-е, sd_sep_clash_b); только они: --screens grip
  --part [<мс>,...]   разрез месяца при входе в день, кадр на мс от старта (29.2а; по умолчанию 170); только он: --screens part
  --partyear [<мс>,...]   тот же разрез при входе тапом по числу в ленте года (29.2б); только он: --screens partyear
  --cards / --phases / --forms / --layers / --sheets / --chapters   перебор отдельных экранов (см. шапку файла)
  --skip-build   --out <папка>   --forecast <файл>   --no-sheets --no-pick   --help   эта справка`);
  process.exit(0);
}
const FORECAST = path.resolve(args.forecast || path.join(FX, 'forecast_barnaul.json'));
/* 28ж: файла нет — источник погоды приложения сценария отвечает отказом, как сеть без ответа. */
const NATIVE_FORECAST = args['no-weather'] ? path.join(os.tmpdir(), 'lp-no-forecast-' + process.pid + '.json') : FORECAST;
/* Узлы, по которым видно, есть ли на экране погода (и что вместо неё). */
// Узлы, которым без прогноза на экране не бывать: значок, градусы, небо и ветер
// в телеметрии, график «следующих». Есть хоть один — режим --no-weather падает
// (ревью GPT к 466d9d3: раньше он лишь записывал найденное и выходил с нулём).
const FORBIDDEN_WITHOUT_WEATHER = ['wx.icon', 'wx.temp', 'tele.sky', 'tele.wind', 'next.spark'];
function forbiddenSeen(seenByScreen) {
  const bad = [];
  for (const [screen, seen] of Object.entries(seenByScreen))
    for (const k of FORBIDDEN_WITHOUT_WEATHER) if (k in seen) bad.push(screen + ': ' + k);
  return bad;
}
const WEATHER_NODES = /^(wx\.|tele\.(sky|wind|sunset|golden|cond)|next\.|dp\.(temp|wxnone|rise|set|gold)|wk\.|header\.note)/;

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

const screens = (args.screens || 'light,map,planner,settings,card,m28').split(',');
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
/* Свой момент — `метка=ГГГГ-ММ-ДДTЧЧ:ММ` (28е: «сегодня» ночью и вечером):
   `--moments n2=2026-10-02T22:49,g2=2026-10-02T17:30`. */
const moments = (args.moments || 'day,golden,night,dawn').split(',').map(m => {
  const [label, iso] = m.split(/=(.+)/);
  if (iso) MOMENTS[label] = iso;
  return label;
});
/* Сводка карты (итерация 20б): свёрнутая — окно прибора 20а, раскрытая —
   строки свода. Центр прибора от сводки не зависит, поэтому раскрытая
   сверяет и прибор. */
const folds = (args.fold || 'shut,open').split(',');
/* Лист «Где снимаем» (итерация 21в): развилка и два пути над «Светом», над
   «Картой» — развилка (та же кнопка места в шапке). В засеве две точки
   «Моих мест»: с адресом и безымянная (строку называют координаты). */
const sheets = args.sheets === '' || args['only-layers'] || args['no-sheets'] ? [] : (args.sheets || 'fork,addr,geo').split(',');
// Форма записи (23): `--forms portrait,wedding,report` — «Съёмки», «＋», жанр плиткой.
const forms = args.forms ? args.forms.split(',') : [];
/* Слои и листы «Съёмок» (22): лента года, «Год целиком», статистика, поиск,
   корзина, «Занять время» — поверх месяца, засев сезона. Сверяются только узлы
   слоя (и панель вкладок над слоями); корзине засев кладёт две записи. */
const layers = args.layers ? args.layers.split(',') : [];
const LAYER_NODES = { year: /^(year|ym)\./, year12: /^y12\./, stats: /^stat\./, search: /^se\./,
  bin: /^bin\./, blk: /^blk\./ };
const LAYER_SHEETS = { bin: 1, blk: 1 };
/* Карточка (итерация 25, `--screens card`): три фазы × четыре группы жанров на
   записях посева сезона. Часы — от записи, в её день: «до» — за 2 ч до
   начала, «во время» — через 30 мин после начала, «после» — через час после
   конца. Свадьба с точками и студией (event), портрет в студии с соседкой
   внахлёст (people), интерьер в студии у организации (client), пейзаж на
   рассвете (own). `stack` — 26-е с четырьмя соседями: ступени краёв стопки;
   `finish` — портрет «во время» с «Завершать вручную»: кнопка в нижнем ряду.
   `tune` — заказ до съёмки в режиме перестановки (26, лист «ползунков»),
   `meet` — встреча (26), без маршрута и сдачи.
   Часть — `--cards people,stack`, `--phases during`. */
const CARDS = { event: 'sd_sep_wed', people: 'sd_sep_clash_a', client: 'sd_sep_inter', own: 'sd_aug_land' };
/* Маршрут и референсы (27): свадьба из 12 точек (08:00 – 20:30), два документа,
   четыре кадра (два своих, три в наборе жанра, один лежит в обоих), часы — 18:00
   суток съёмки. `r27route` — лента точек раскрыта, `r27refs` — строка «Референсы»,
   `r27full` — полный экран (сетка, заглушки), `r27view` — просмотрщик первого кадра. */
const R27 = { r27route: { fold: 'route' }, r27refs: {}, r27full: { refs: 'full' }, r27view: { refs: 'view' },
  r27tune: { tune: true } };
const R27_ROUTE = [[480, 540, 'Сборы невесты', 'Гостиница «Магистрат»'], [600, 640, 'Сборы жениха', 'Гостиница «Магистрат»'],
  [660, 720, 'Выездная регистрация', 'Парк у реки'], [780, 900, 'Пара в студии', 'Томсон, зал Эдисон'],
  [840, 870, 'Обед', 'Ресторан «Соль»'], [900, 960, 'Прогулка', 'Дом с драконами'], [960, 990, 'Фотозона', 'Ресторан «Соль»'],
  [1000, 1060, 'Банкет', 'Ресторан «Соль»'], [1100, 1130, 'Первый танец', 'Ресторан «Соль»'],
  [1150, 1180, 'Прогулка на закате', 'Набережная'], [1180, 1200, 'Букет невесты', 'Набережная'], [1230, 1260, 'Торт', 'Ресторан «Соль»']]
  .map(([t, t2, n, p]) => ({ t, t2, n, p, placeId: null, studioId: n === 'Пара в студии' ? 'sd_st_tomson' : null,
    hallId: n === 'Пара в студии' ? 'sd_h_edison' : null }));
const R27_SHOTS = ['a', 'b', 'c', 'd'].map((x, i) => ({ id: 'sh_r27_' + x, k: 'img', im: 'sh_r27_' + x, w: 800, h: [1200, 900, 1000, 1400][i],
  tags: [['bride'], ['couple', 'evening'], ['walk'], ['details']][i] }));
const R27_BOARDS = [{ id: 'bd_r27_own', kind: 'shoot', sid: 'sd_sep_wed', genre: 'wedding', items: ['sh_r27_a', 'sh_r27_b'], name: null, cover: null },
  { id: 'bd_r27_set', kind: 'tpl', genre: 'wedding', items: ['sh_r27_b', 'sh_r27_c', 'sh_r27_d'], name: null, cover: null }];
const cards = args.cards ? args.cards.split(',') : [...Object.keys(CARDS), 'stack', 'finish', 'tune', 'meet', ...Object.keys(R27)];
const phases = (args.phases || 'before,during,after').split(',');
// Стена часов Барнаула (+7, без перехода) в минуту `m` суток записи `iso`.
/* Мудборды, организации, «Контакты», опросник, встреча (итерация 28, шаг 10б). Кадры — ссылки
   без картинок (у обеих сторон одна заглушка), 19 штук по подборкам, как в замере беты 30.09:
   «Свадьба» 10 кадров со всеми семью разделами и вторая папка «На море» (2 кадра, один общий),
   у съёмки свадьбы своя подборка из трёх; портрет, пейзаж и интерьер — по две–три ссылки.
   Организации — из засева планировщика, бумаги ссылками у двух. Часы 13:00 23 сентября. */
const M28_WED_TAGS = ['couple', 'bride', 'groom', 'walk', 'evening', 'details', 'gathering'];
const m28link = (id, n, tags) => ({ id, k: 'link', url: 'https://ru.pinterest.com/pin/' + n + '/', tags });
const M28_SHOTS = [
  ...Array.from({ length: 10 }, (_, i) => m28link('sh_m28_w' + i, 100 + i, [M28_WED_TAGS[i % 7]])),
  m28link('sh_m28_s0', 200, ['couple']), m28link('sh_m28_s1', 201, ['evening']),
  m28link('sh_m28_p0', 300, ['light']), m28link('sh_m28_p1', 301, []), m28link('sh_m28_p2', 302, []),
  m28link('sh_m28_l0', 400, []), m28link('sh_m28_l1', 401, []),
  m28link('sh_m28_i0', 500, []), m28link('sh_m28_i1', 501, ['light'])];
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
/* Экран → откуда веб и натив открывают, какие узлы сверяются (по имени). */
const M28 = { mbgallery: { re: /^mb\.(?!strip|head|s\.)/ }, mbshelf: { way: 'wedding', re: /^mb\.(?!strip|head|s\.)/ },
  mbfolder: { way: 'bd_m28_wed', shelf: 'wedding', re: /^mb\.(?!strip|head|s\.)/ }, orgs: { re: /^org\./ },
  orgcard: { way: 'sd_org_agency', re: /^(org|orgc)\./ }, contacts: { re: /^contacts\./ },
  quest: { way: 'sd_sep_wed', re: /^quest\./ }, meet: { re: /^(form|kit)\./ } };
const m28 = args.m28 ? args.m28.split(',') : Object.keys(M28);
const wallAt = (iso, m) => new Date(Date.parse(iso) + 7 * 3600e3 + m * 60e3).toISOString().slice(0, 16);
const SHEET_SPOTS = [
  { id: 'p_shot_a', name: 'Нагорный парк', address: 'ул. Гоголя, 2', lat: 53.3334, lon: 83.8035, pinned: true },
  { id: 'p_shot_b', name: '', address: '', lat: 53.35, lon: 83.75, pinned: true }
];
/* Веер «Мои места» (шаг 5 итерации 24, `--chapter fan`): три места, первое —
   там, где стоит карта пары (дом `me` сида, Барнаул), — его строка латунью;
   у второго уточнение второй строкой, у третьего — нет. Имена «набраны
   рукой» (`named`): безымянную точку под головкой веб переименовывает ответом
   геокодера («Барнаул» / «Алтайский край»), а натив этого пока не умеет —
   расхождение записано в плане, пара сверяет веер, а не его. */
const FAN_SPOTS = [
  { id: 'p_fan_here', name: 'Барнаул, центр', address: '', lat: 53.3548, lon: 83.7698, pinned: true, named: true },
  { id: 'p_fan_park', name: 'Нагорный парк', sub: 'вход с Гоголя', address: 'ул. Гоголя, 2', lat: 53.3334, lon: 83.8035, pinned: true, named: true },
  { id: 'p_fan_obi', name: 'Берег Оби', address: '', lat: 53.3405, lon: 83.8127, pinned: true, named: true }
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
    '-LPShotNow', (sc.at || MOMENTS[sc.moment]) + ':00' + OFFSET, '-LPShotZone', ZONE,
    '-LPShotSeed', sc.seed, '-LPShotForecast', NATIVE_FORECAST,
    '-LPShotAir', path.join(FX, 'air_barnaul.json'), '-LPShotName', path.join(FX, 'place_barnaul.json'),
    '-LPShotScreen', sc.screen, ...(sc.chapter ? ['-LPShotChapter', sc.chapter] : []),
    ...(sc.chapter === 'spoiler' ? ['-LPShotSpoiler', '1'] : []),
    ...(sc.scope ? ['-LPShotScope', sc.scope] : []), ...(sc.pick != null ? ['-LPShotPick', String(sc.pick)] : []),
    ...(sc.net ? ['-LPShotNet', sc.net] : []),
    ...(sc.roads ? ['-LPShotRoads', sc.roads, ...(sc.roads === 'none' ? ['-LPShotReportDelay', '14'] : [])] : []),
    ...(args['drum-nudge'] ? ['-LPShotDrumNudge', args['drum-nudge']] : []),
    ...(args['form-scroll'] ? ['-LPShotFormScroll', args['form-scroll']] : []),
    ...(sc.form ? ['-LPShotSheet', 'form', '-LPShotWay', sc.form] : []),
    ...(sc.layer ? ['-LPShotSheet', sc.layer] : []),
    ...(sc.grip ? ['-LPShotSheet', 'grip', '-LPShotWay', sc.grip] : []),
    ...(sc.part ? ['-LPShotChapter', sc.partKind + ':' + sc.part, '-LPShotReportDelay', '6'] : []),
    ...(sc.m28 ? ['-LPShotSheet', sc.m28, ...(sc.way ? ['-LPShotWay', sc.way] : [])] : []),
    ...(sc.sheet ? ['-LPShotSheet', 'loc', ...(sc.sheet !== 'fork' ? ['-LPShotWay', sc.sheet] : [])] : []),
    ...(sc.card ? ['-LPShotSheet', 'card', '-LPShotWay', sc.card, ...(sc.tune ? ['-LPShotTune', '1'] : []),
      ...(sc.drag ? ['-LPShotDrag', sc.drag] : []),
      ...(sc.fold ? ['-LPShotFold', sc.fold] : []), ...(sc.refs ? ['-LPShotRefs', sc.refs] : [])] : []),
    '-LPShotReport', report],
  { env: { ...process.env, SIMCTL_CHILD_TZ: ZONE } });
  // Первый запуск после установки идёт до 20 с (замер 19б), следующие — 3–4 с.
  for (let i = 0; i < 240 && !fs.existsSync(report); i++) await sleep(250);
  if (!fs.existsSync(report)) throw new Error('приложение не написало рамки за 60 с: ' + sc.name);
  await sleep(300);
  run('xcrun', ['simctl', 'io', udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
  return JSON.parse(fs.readFileSync(report, 'utf8'));
}

/* 28л.6: глава «Сеть» — только натив. Проверяется по рамкам: слово состояния то, что подставлено; сегмент и кнопка
   на полях соседних глав (x = 24, ширина 392 — как `seg.0` «Вида» и «Языка»); кнопка — рамка строки на всю ширину (0, 440):
   отступы 24 по бокам кладёт сам `.data-btn`, как у «Отправить» в «О приложении»;
   всё на экране и ничего не налезает друг на друга (по порядку сверху вниз). */
const NET_WORD = { reachable: 'доступны', unreachable: 'недоступны', unknown: 'проверяем' };
function netReport(sc, nat) {
  const n = nat.nodes, bad = [];
  const need = ['seg.0', 'note.0', 'item.0', 'item.1', 'note.1'];
  for (const k of need) if (!n[k]) bad.push('нет узла ' + k);
  const out = { state: sc.net, theme: sc.theme, status: n['item.0'] && n['item.0'].text, button: n['item.1'] && n['item.1'].text,
    frames: Object.fromEntries(need.filter(k => n[k]).map(k => [k, [n[k].x, n[k].y, n[k].w, n[k].h].map(v => +v.toFixed(1))])) };
  if (out.status !== NET_WORD[sc.net]) bad.push('слово состояния «' + out.status + '», ждали «' + NET_WORD[sc.net] + '»');
  const seg = n['seg.0'], btn = n['item.1'];
  if (seg && (Math.abs(seg.x - 24) > 0.5 || Math.abs(seg.w - 392) > 0.5)) bad.push('сегмент не на полях соседних глав: x ' + seg.x + ', w ' + seg.w);
  if (btn && (Math.abs(btn.x) > 0.5 || Math.abs(btn.w - 440) > 0.5)) bad.push('кнопка не на всю ширину строки: x ' + btn.x + ', w ' + btn.w);
  const rows = need.filter(k => n[k]).map(k => ({ k, ...n[k] }));
  for (const r of rows) if (r.x < 0 || r.x + r.w > 440 || r.y < 0 || r.y + r.h > 956) bad.push(r.k + ' вне экрана');
  const byY = rows.slice().sort((a, b) => a.y - b.y);
  for (let i = 1; i < byY.length; i++) if (byY[i].y < byY[i - 1].y + byY[i - 1].h - 0.5) bad.push(byY[i - 1].k + ' налезает на ' + byY[i].k);
  out.bad = bad;
  console.log(`${sc.name}: «${out.status}» · кнопка «${out.button}»; сегмент ${out.frames['seg.0']}; ${bad.length ? 'НАРУШЕНИЙ ' + bad.length : 'ровно'}`);
  return out;
}

/* 27а.3: блок карточки в руке (`--drag place:24`). Рамки строк: поднятая стоит на `dy` ниже своего места и
   размера не меняет (56), слот — на месте `to = clamp(i + round(dy / 64))`, соседи шагнули ровно на 64 и между
   собой держат зазор 8. Пиксели: слот светлее (тёмная тема) / темнее (светлая) листа на долю `hair3`; тень —
   боковая полоса левее строки темнее листа. Радиус слота 6 и цвет `hair3` — из кода, тот же, что у маршрута
   (`MapRouteViews.swift`: `RoundedRectangle(6)` + `pal.hair3`), в кадре не мерены. */
const DRAG_ORDER = ['deal', 'day', 'place', 'weather', 'brief', 'docs', 'notes', 'delivery', 'money'];
async function dragReport(page, sc, nat) {
  const n = nat.nodes, [blk, dyS] = sc.drag.split(':'), dy = +dyS, bad = [];
  const li = DRAG_ORDER.indexOf(blk);
  const rect = k => n['card.order.row.' + k];
  for (const k of DRAG_ORDER) if (!rect(k)) bad.push('нет строки ' + k);
  if (bad.length) return { bad };
  // Начало сетки строк; если в руке первая, она сама сдвинута на `dy`.
  const y0 = rect(DRAG_ORDER[0]).y - (li === 0 ? dy : 0);
  const to = Math.max(0, Math.min(DRAG_ORDER.length - 1, li + Math.round(dy / 64)));
  const place = i => i === li ? to : (i > li ? i - 1 : i) >= to ? (i > li ? i - 1 : i) + 1 : (i > li ? i - 1 : i);
  const frames = {};
  DRAG_ORDER.forEach((k, i) => {
    const r = rect(k), want = i === li ? y0 + 64 * li + dy : y0 + 64 * place(i);
    frames[k] = { y: +r.y.toFixed(1), want, h: +r.h.toFixed(1) };
    if (Math.abs(r.y - want) > 0.6) bad.push(`${k}: y ${r.y.toFixed(1)}, ждали ${want}`);
    if (Math.abs(r.h - 56) > 0.6) bad.push(`${k}: высота ${r.h.toFixed(1)}, ждали 56 (размер не меняется)`);
    if (Math.abs(r.x - 36) > 0.6 || Math.abs(r.w - 368) > 0.6) bad.push(`${k}: x ${r.x} w ${r.w}`);
  });
  const slotTop = y0 + 64 * to, liftTop = y0 + 64 * li + dy;
  // Открытая часть слота: слот минус поднятая строка (две полосы — над ней и под ней), берём большую; отступ 4 pt
  // от краёв полосы, чтобы не попасть в сглаженный край и тень строки.
  const bands = [[slotTop, Math.min(slotTop + 56, liftTop)], [Math.max(slotTop, liftTop + 56), slotTop + 56]].filter(b => b[1] - b[0] > 8);
  const open = bands.sort((a, b) => (b[1] - b[0]) - (a[1] - a[0]))[0];
  const openSlotY = open ? (open[0] + open[1]) / 2 : null;
  const png = 'data:image/png;base64,' + fs.readFileSync(path.join(sc.dir, 'native.png')).toString('base64');
  const px = await page.evaluate(async ({ png, pts }) => {
    const img = await new Promise(r => { const i = new Image(); i.onload = () => r(i); i.src = png; });
    const k = img.width / 440;
    const cv = document.createElement('canvas'); cv.width = img.width; cv.height = img.height;
    const cx = cv.getContext('2d'); cx.drawImage(img, 0, 0);
    const out = {};
    for (const [name, [x, y]] of Object.entries(pts)) if (y != null) out[name] = [...cx.getImageData(Math.round(x * k), Math.round(y * k), 1, 1).data].slice(0, 3);
    return out;
  }, { png, pts: {
    // лист в зазоре между двумя неподвижными строками, у самого края (x 200 — середина строки по ширине)
    sheet: [200, y0 + 56 + 4],
    // середина большей части слота, не закрытой поднятой строкой (нет такой — слот закрыт целиком, точки нет)
    slot: [200, openSlotY],
    // боковая тень: 6 pt левее строки на уровне её середины, и там же на уровне строки, до которой тень не достаёт
    shadowL: [30, liftTop + 28], shadowRef: [30, y0 + 64 * (DRAG_ORDER.length - 1) + 28],
    shadowBelow: [200, liftTop + 56 + 4]
  } });
  const dark = sc.theme === 'dark';
  const lum = c => 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  const slotD = px.slot ? lum(px.slot) - lum(px.sheet) : null, shadeD = lum(px.shadowL) - lum(px.shadowRef);
  if (dy !== 0 && slotD == null) bad.push('слот закрыт строкой целиком — проверять нечего');
  else if (dy !== 0 && Math.abs(slotD) < 1) bad.push('слот не виден: яркость ' + slotD.toFixed(1) + ' к листу');
  if (slotD != null && dy !== 0 && (dark ? slotD < 0 : slotD > 0)) bad.push('слот не в ту сторону: ' + slotD.toFixed(1));
  const out = { block: blk, dy, to, theme: sc.theme, frames, slotLum: slotD == null ? null : +slotD.toFixed(1), shadowSideLum: +shadeD.toFixed(1), px, bad,
    gapLiftedToNext: +(rect(DRAG_ORDER[li + 1] || blk).y - (liftTop + 56)).toFixed(1) };
  console.log(`${sc.name}: слот ${to + 1}-й (строка на ${dy} pt ниже места), слот ${slotD == null ? '—' : slotD.toFixed(1)} к листу, тень сбоку ${shadeD.toFixed(1)}; ${bad.length ? 'НАРУШЕНИЙ ' + bad.length : 'рамки сошлись'}`);
  return out;
}

/* 28л.5: числа по плашке «Исправить карту» и подписи авторства. Расстояние —
   от низа подписи до верха плашки в pt (< 0 — пересекаются); контраст — по
   букв внутри рамки: медиана самых тёмных от фона пикселей (см. ниже). Прогон падает, если состояние
   маршрута не то, плашки или подписи нет, они пересекаются или контраст
   плашки ниже 3 (ревью GPT к 18f7ac6). */
async function roadsReport(page, sc, nat) {
  const n = nat.nodes;
  const credit = n['map.credit'], fix = n['map.fixTheMap'], sum = n['route.sum'];
  const out = { state: sc.roads, theme: sc.theme, sum: sum && sum.text, fixTheMap: fix, credit };
  if (credit && fix) {
    out.gapPt = +(fix.y - (credit.y + credit.h)).toFixed(1);
    out.overlapX = !(fix.x + fix.w <= credit.x || fix.x >= credit.x + credit.w);
    out.intersects = out.overlapX && fix.y < credit.y + credit.h && fix.y + fix.h > credit.y;
  }
  const png = 'data:image/png;base64,' + fs.readFileSync(path.join(sc.dir, 'native.png')).toString('base64');
  out.contrast = await page.evaluate(async ({ png, rects }) => {
    const img = await new Promise(r => { const i = new Image(); i.onload = () => r(i); i.src = png; });
    const k = img.width / 440;
    const cv = document.createElement('canvas'); cv.width = img.width; cv.height = img.height;
    const cx = cv.getContext('2d'); cx.drawImage(img, 0, 0);
    const lum = ([r, g, b]) => { const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
    const res = {};
    for (const [name, r] of Object.entries(rects)) {
      if (!r) { res[name] = null; continue; }
      // Только внутренность плашки (отступ 3 pt по бокам и 2 pt сверху и снизу):
      // там фон плашки и буквы, без кромки, тени и карты вокруг. Фон — медиана
      // внутренности (букв меньшинство).
      const x0 = Math.round((r.x + 3) * k), y0 = Math.round((r.y + 2) * k);
      const w = Math.round((r.w - 6) * k), h = Math.round((r.h - 4) * k);
      const data = cx.getImageData(x0, y0, w, h).data;
      const med = i => { const v = []; for (let j = i; j < data.length; j += 4) v.push(data[j]); return v.sort((p, q) => p - q)[v.length >> 1]; };
      const bg = [med(0), med(1), med(2)];
      // Чернила — медианный цвет «буквенных» пикселей: тех, что отстоят от
      // фона не меньше чем на половину самого большого отстояния. Один случайный
      // пиксель числа не задаёт; меньше 12 таких пикселей — букв в рамке нет.
      const d = a => Math.abs(a[0] - bg[0]) + Math.abs(a[1] - bg[1]) + Math.abs(a[2] - bg[2]);
      const px = [];
      let dmax = 0;
      for (let i = 0; i < data.length; i += 4) { const p = [data[i], data[i + 1], data[i + 2]]; px.push(p); dmax = Math.max(dmax, d(p)); }
      const core = px.filter(p => d(p) >= dmax / 2 && dmax > 12);
      if (core.length < 12) { res[name] = { bg, ink: null, ratio: 0, core: core.length }; continue; }
      const mid = i => core.map(p => p[i]).sort((p, q) => p - q)[core.length >> 1];
      const best = [mid(0), mid(1), mid(2)];
      const [a, b] = [lum(bg), lum(best)].sort((p, q) => q - p);
      res[name] = { bg, ink: best, ratio: +((a + 0.05) / (b + 0.05)).toFixed(2), core: core.length };
    }
    return res;
  }, { png, rects: { fixTheMap: fix || null, credit: credit || null } });
  const bad = [];
  if (!fix) bad.push('нет плашки «Исправить карту»');
  if (!credit) bad.push('нет подписи «© CARTO · © OpenStreetMap»');
  if (out.gapPt != null && (out.intersects || out.gapPt < 0)) bad.push('плашка задевает подпись, зазор ' + out.gapPt + ' pt');
  if (sc.roads === 'ok' && !(out.sum && /км/.test(out.sum) && !/недоступен/.test(out.sum))) bad.push('«ok»: в полосе нет километров: ' + out.sum);
  if (sc.roads === 'none' && !(out.sum && /Маршрут недоступен/.test(out.sum))) bad.push('«none»: в полосе нет «Маршрут недоступен»: ' + out.sum);
  const ratio = out.contrast && out.contrast.fixTheMap && out.contrast.fixTheMap.ratio;
  if (!(ratio >= 3)) bad.push('контраст плашки ' + ratio + ' < 3');
  out.bad = bad;
  console.log(`${sc.name}: «${out.sum}»; плашка ${fix ? [fix.x, fix.y, fix.w, fix.h].join(',') : 'нет'}; зазор ${out.gapPt} pt; контраст плашки ${out.contrast.fixTheMap && out.contrast.fixTheMap.ratio}`);
  return out;
}

function webShot(sc, dir, safe) {
  const out = run('node', [path.join(WEB, 'tools', 'shot.js'), '--screen',
    sc.screen === 'light' ? 'today' : sc.screen === 'planner' ? 'plan' : sc.screen, ...(sc.scope ? ['--scope', sc.scope] : []),
    ...(sc.pick != null ? ['--pick', String(sc.pick)] : []),
    '--at', sc.at || MOMENTS[sc.moment], '--tz', ZONE, '--seed', sc.seed,
    '--forecast', FORECAST, '--air', path.join(FX, 'air_barnaul.json'),
    '--name', path.join(FX, 'place_barnaul.json'), '--safe', safe.map(v => Math.round(v)).join(','),
    ...(sc.chapter ? ['--chapter', sc.chapter] : []),
    ...(sc.form ? ['--sheet', 'form', '--way', sc.form] : []),
    ...(sc.layer ? ['--sheet', sc.layer] : []),
    ...(sc.grip ? ['--sheet', 'grip', '--way', sc.grip] : []),
    ...(sc.part ? ['--sheet', sc.partKind, '--way', sc.part] : []),
    ...(sc.m28 ? ['--sheet', sc.m28, ...(sc.way ? ['--way', sc.way] : []), ...(sc.shelf ? ['--shelf', sc.shelf] : [])] : []),
    ...(sc.sheet ? ['--sheet', 'loc', ...(sc.sheet !== 'fork' ? ['--way', sc.sheet] : [])] : []),
    ...(sc.card ? ['--sheet', 'card', '--way', sc.card, ...(sc.tune ? ['--tune'] : []),
      ...(sc.fold ? ['--fold', sc.fold] : []), ...(sc.refs ? ['--refs', sc.refs] : [])] : []),
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
      if (chapter === 'fan') s.spots = FAN_SPOTS;
      /* Режим маршрута (24а): те же три места — все в черновике по порядку.
         У веба в паре сети нет — линия прямая штрихом; натив в паре дорогу
         не спрашивает (`mapOffline`), так что линии сверимы. */
      if (chapter === 'route') { s.spots = FAN_SPOTS; s.mapRoute = FAN_SPOTS.map(x => x.id); }
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
  for (const g of forms) for (const theme of themes) {
    const name = ['planner', 'form', g, theme].join('-');
    const dir = path.join(OUT, name);
    fs.mkdirSync(dir, { recursive: true });
    const seedFile = path.join(dir, 'seed.json');
    fs.writeFileSync(seedFile, JSON.stringify({ ...seed, theme, pro: false, drumSlot: 'paper', ribbonMode: 'drum' }));
    list.push({ name, dir, screen: 'planner', theme, moment: 'day', form: g, seed: seedFile });
  }
  for (const layer of layers) for (const theme of themes) {
    const name = ['planner', 'layer', layer, theme].join('-');
    const dir = path.join(OUT, name);
    fs.mkdirSync(dir, { recursive: true });
    const s = { ...plannerSeed, theme, pro: false, drumSlot: 'paper', ribbonMode: 'drum' };
    if (layer === 'bin') {
      // Две первые записи посева — в корзину, как удалённые веером (веб `trashRecord`).
      const recs = (s.sessions || []).slice(0, 2);
      s.sessions = (s.sessions || []).slice(2);
      s.trashed = recs.map((rec, i) => ({ rec, at: i, del: Date.parse('2026-09-23T12:00:00+07:00') - i * 60000 }));
    }
    const seedFile = path.join(dir, 'seed.json');
    fs.writeFileSync(seedFile, JSON.stringify(s));
    list.push({ name, dir, screen: 'planner', theme, moment: 'day', scope: 'month', layer, seed: seedFile });
  }
  if (screens.includes('card') && !args['only-sheets'] && !args['only-forms'] && !args['only-layers']) {
    for (const g of cards) for (const ph of CARDS[g] ? phases : g === 'tune' ? ['before'] : ['during']) for (const theme of themes) {
      const id = g === 'tune' ? CARDS.client : g === 'meet' ? 'shot_meet' : R27[g] ? CARDS.event : CARDS[g] || 'sd_sep_clash_a';
      const name = ['card', g, ph, theme].join('-');
      const dir = path.join(OUT, name);
      fs.mkdirSync(dir, { recursive: true });
      const s = { ...plannerSeed, theme, pro: false, drumSlot: 'paper', ribbonMode: 'drum' };
      if (g === 'stack') {
        // Три соседа сверх «Семьи Ким»: встреча утром и две съёмки вечером.
        const b = s.sessions.find(x => x.id === 'sd_sep_clash_b');
        s.sessions = [...s.sessions,
          { ...b, id: 'shot_st_meet', kind: 'meet', min: 600, end: 645, dur: 45, contact: 'Анна Лис', persons: [] },
          { ...b, id: 'shot_st_eve', min: 1020, end: 1110, dur: 90, contact: 'Пётр Сомов', persons: [] },
          { ...b, id: 'shot_st_late', min: 1140, end: 1200, dur: 60, contact: 'Ольга Верх', persons: [] }];
      }
      if (g === 'finish') s.manualEnd = true;
      if (R27[g]) {
        // Копия записи: `s` — поверхностная, правка общего объекта протекла бы в другие сценарии (ревью GPT к 7d3362c).
        const at = s.sessions.findIndex(x => x.id === id);
        s.sessions = s.sessions.map((x, i) => i !== at ? x
          : { ...x, route: R27_ROUTE, min: 480, dur: 840, end: 1320 });
        s.shots = R27_SHOTS; s.boards = R27_BOARDS;
      }
      if (g === 'meet') {
        const b = s.sessions.find(x => x.id === 'sd_sep_clash_b');
        s.sessions = [...s.sessions, { ...b, id: 'shot_meet', kind: 'meet', min: 600, end: 645, dur: 45, contact: 'Анна Лис', persons: [] }];
      }
      const rec = s.sessions.find(x => x.id === id);
      const end = rec.end != null ? rec.end : rec.min + (rec.dur || 90);
      const at = wallAt(rec.date, R27[g] ? 1080 : ph === 'before' ? rec.min - 120 : ph === 'during' ? rec.min + 30 : end + 60);
      const seedFile = path.join(dir, 'seed.json');
      fs.writeFileSync(seedFile, JSON.stringify(s));
      list.push({ name, dir, screen: 'planner', theme, moment: 'day', at, card: id, phase: ph, seed: seedFile, tune: g === 'tune', ...(R27[g] || {}) });
    }
  }
  if (screens.includes('m28') && !args['only-sheets'] && !args['only-forms'] && !args['only-layers']) {
    for (const g of m28) for (const theme of themes) {
      const name = ['m28', g, theme].join('-');
      const dir = path.join(OUT, name);
      fs.mkdirSync(dir, { recursive: true });
      const s = { ...plannerSeed, theme, pro: false, drumSlot: 'paper', ribbonMode: 'drum', shots: M28_SHOTS, boards: M28_BOARDS,
        orgs: plannerSeed.orgs.map(o => M28_DOCS[o.id] ? { ...o, docs: M28_DOCS[o.id] } : o) };
      const seedFile = path.join(dir, 'seed.json');
      fs.writeFileSync(seedFile, JSON.stringify(s));
      list.push({ name, dir, screen: 'planner', theme, moment: 'day', scope: 'month', m28: g, ...M28[g], seed: seedFile });
    }
  }
  if (args['only-sheets'] || args.forms && args['only-forms'] || args['only-layers']) screens.length = 0;
  /* 28л.5: маршрут при разных ответах серверов — только натив, веб тут ничего
     не знает. `ok` — сервер отвечает дорогой, `none` — все три молчат (настоящая
     цепочка с настоящими сроками, сети нет). Меряется плашка «Исправить карту»
     и подпись «© CARTO · © OpenStreetMap»: расстояние и контраст — roads.json. */
  const roadStates = args.roads ? (args.roads === '1' ? 'ok,none' : args.roads).split(',') : [];
  if (roadStates.length) {
    screens.length = 0;
    for (const state of roadStates) for (const theme of themes) {
      add('map', theme, 'simple', moments[0], 'paper', 'route');
      const sc = list.pop();
      sc.name = ['map-roads', state, theme].join('-');
      sc.dir = path.join(OUT, sc.name);
      fs.mkdirSync(sc.dir, { recursive: true });
      sc.roads = state;
      list.push(sc);
    }
    list.splice(0, list.length - roadStates.length * themes.length);   // остальные сценарии выше сюда не нужны
  }
  /* 28л.6: глава «Сеть» — только натив, три состояния детектора × темы. */
  const netStates = args.net ? (args.net === '1' ? 'reachable,unreachable,unknown' : args.net).split(',') : [];
  if (netStates.length) {
    screens.length = 0;
    for (const state of netStates) for (const theme of themes) {
      add('settings', theme, 'simple', moments[0], 'paper', 'network');
      const sc = list.pop();
      sc.name = ['settings-net', state, theme].join('-');
      sc.dir = path.join(OUT, sc.name);
      fs.mkdirSync(sc.dir, { recursive: true });
      sc.net = state;
      list.push(sc);
    }
    list.splice(0, list.length - netStates.length * themes.length);
  }
  /* 27а.3: блок карточки в руке — только натив (в бете блок за пальцем не идёт, ей сравнивать не с чем): заказ до
     съёмки в «ползунках», строка `place` на 24 pt ниже места (слот виден полосой, соседи на местах) и на 44 pt
     (слот уже на строку ниже, сосед шагнул). Числа — `dragReport`: сдвиг, зазор, слот, тень. */
  const dragStates = args.drag ? (args.drag === '1' ? 'place:24,place:44' : args.drag).split(',') : [];
  if (dragStates.length) {
    screens.length = 0;
    const id = CARDS.client;
    for (const st of dragStates) for (const theme of themes) {
      const name = ['card-drag', st.replace(':', '-'), theme].join('-');
      const dir = path.join(OUT, name);
      fs.mkdirSync(dir, { recursive: true });
      const s = { ...plannerSeed, theme, pro: false, drumSlot: 'paper', ribbonMode: 'drum' };
      const rec = s.sessions.find(x => x.id === id);
      const seedFile = path.join(dir, 'seed.json');
      fs.writeFileSync(seedFile, JSON.stringify(s));
      list.push({ name, dir, screen: 'planner', theme, moment: 'day', at: wallAt(rec.date, rec.min - 120), card: id,
        phase: 'before', seed: seedFile, tune: true, drag: st });
    }
    list.splice(0, list.length - dragStates.length * themes.length);   // остальные сценарии выше сюда не нужны
  }
  if (screens.includes('planner')) for (const scope of scopes) for (const theme of themes) {
    add('planner', theme, 'simple', 'day', 'paper', null, 'drum', 'shut', scope);
    /* Суббота 26-го: две съёмки внахлёст (14:00–15:30 и 15:00–16:30) —
       колонки ленты на экране, а не только в стенде `make planner` */
    if (scope === 'day') add('planner', theme, 'simple', 'day', 'paper', null, 'drum', 'shut', scope, 5);
  }
  /* Время рукой на ленте дня (29а, `--grip`): 26-е, вторая съёмка внахлёст
     (15:00–16:30, без студии — переносится) поднята и сдвинута на час, палец
     держит. Веб — удержанием мыши (`shot.js --sheet grip`), приложение —
     `-LPShotSheet grip`. Сверяются ручки, капсула минуты и отрезки ленты. */
  if (args.grip || screens.includes('grip')) for (const theme of themes) {
    add('planner', theme, 'simple', 'day', 'paper', null, 'drum', 'shut', 'day', 5);
    const sc = list[list.length - 1];
    sc.grip = !args.grip || args.grip === '1' ? 'sd_sep_clash_b' : args.grip;
    sc.name = ['planner', 'grip', theme].join('-');
    const dir = path.join(OUT, sc.name);
    fs.mkdirSync(dir, { recursive: true });
    fs.renameSync(sc.seed, path.join(dir, 'seed.json'));
    sc.dir = dir;
    sc.seed = path.join(dir, 'seed.json');
  }
  /* Разрез месяца (29.2а, `--part`): второй тап по выбранному 23-му, кадр замороженный на N мс от старта. Веб —
     `shot.js --sheet part` (переходы беты на паузе на той же мс), приложение — `-LPShotChapter part:<мс>`.
     Сверяются половины (`part.up`, `part.down` — видимая часть снимка) и семь ячеек недели (`part.c.N`).
     `--partyear` (29.2б) — тот же разрез из ленты года: тап по сегодняшнему 23-му, `-LPShotChapter partyear:<мс>`. */
  for (const kind of ['part', 'partyear']) if (args[kind] || screens.includes(kind))
    for (const ms of String(args[kind] && args[kind] !== '1' ? args[kind] : '170').split(',')) for (const theme of themes) {
      add('planner', theme, 'simple', 'day', 'paper', null, 'drum', 'shut', 'month');
      const sc = list[list.length - 1];
      sc.part = ms;
      sc.partKind = kind;
      sc.name = ['planner', kind, ms, theme].join('-');
      const dir = path.join(OUT, sc.name);
      fs.mkdirSync(dir, { recursive: true });
      fs.renameSync(sc.seed, path.join(dir, 'seed.json'));
      sc.dir = dir;
      sc.seed = path.join(dir, 'seed.json');
    }
  for (const screen of screens.filter(x => x !== 'planner' && x !== 'card' && x !== 'm28' && x !== 'grip' && x !== 'part' && x !== 'partyear')) for (const mode of modes) for (const theme of themes) {
    // «Настройки» от момента не зависят — одна пара на тему и режим.
    for (const moment of screen === 'settings' ? [moments[0]] : moments) {
      if (args['only-spoiler']) { if (screen === 'light' && mode === 'astro') add(screen, theme, mode, moment, 'paper', 'spoiler'); continue; }
      for (const fold of screen === 'map' ? folds : ['shut']) add(screen, theme, mode, moment, 'paper', null, 'drum', fold);
    }
    if (screen === 'settings') for (const ch of chapters) add(screen, theme, mode, moments[0], 'paper', ch);
    // Меню слоёв карты (20б) — одним моментом, сводка свёрнута.
    if (screen === 'map' && !args['no-layers']) add(screen, theme, mode, moments[0], 'paper', 'layers');
    // Закладка нажата — точка под головкой и полоса её имени (20б).
    if (screen === 'map' && !args['no-spot']) add(screen, theme, mode, moments[0], 'paper', 'spot');
    // Голый холст: низ убран свайпом, кружок возврата по центру (21б).
    if (screen === 'map' && !args['no-bare']) add(screen, theme, mode, moments[0], 'paper', 'bare');
    // «Мои места» в шапке: веер открыт тапом по кнопке (шаг 5 итерации 24).
    if (screen === 'map' && !args['no-fan']) add(screen, theme, mode, moments[0], 'paper', 'fan');
    // Режим маршрута: полоса черновика из трёх точек (24а).
    if (screen === 'map' && !args['no-route']) add(screen, theme, mode, moments[0], 'paper', 'route');
    if (screen === 'light' && mode === 'astro' && theme === 'light') {
      for (const slot of slots) if (slot !== 'paper') add(screen, theme, mode, moments[0], slot);
    }
    // Лист «Когда смотрим» (19в) — тапом по показаниям купола, одним
    // моментом, в «Просто»: состав листа от режима не зависит.
    if (screen === 'light' && mode === 'simple' && !args['no-pick']) add(screen, theme, mode, moments[0], 'paper', 'pick');
    // Лента суток «Полоса» вместо барабана — второй вид того же органа.
    if (screen === 'light' && mode === 'astro' && !args['no-lane']) add(screen, theme, mode, moments[0], 'paper', null, 'lane');
  }

  const { chromium } = playwright();
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const results = [];
  // Фаза карточки — проверка, а не замер: несовпадение роняет прогон в конце
  // (ревью GPT к 4224ce1), пары и отчёт до этого снимаются все.
  const phaseMiss = [];
  const noWeather = {};
  const roadsOut = {};
  const netOut = {};
  const dragOut = {};
  for (const sc of list) {
    const nat = await nativeShot(dev.udid, sc, sc.dir);
    if (sc.roads) { roadsOut[sc.name] = await roadsReport(page, sc, nat); continue; }
    if (sc.net) { netOut[sc.name] = netReport(sc, nat); continue; }
    if (sc.drag) { dragOut[sc.name] = await dragReport(page, sc, nat); continue; }
    if (args['no-weather']) {
      const seen = {};
      for (const [k, r] of Object.entries(nat.nodes)) {
        if (!WEATHER_NODES.test(k) || r.x + r.w <= 0 || r.x >= 440 || r.y >= 956 || r.y + r.h <= 0) continue;
        seen[k] = r.text != null ? r.text : [r.x, r.y, r.w, r.h].map(v => Math.round(v)).join(',');
      }
      noWeather[sc.name] = seen;
      console.log(sc.name + ': узлы погоды на экране — ' + Object.keys(seen).join(' '));
      continue;
    }
    // Под главой корень остаётся в стеке и пишет свои рамки — сверяется
    // только глава (веб прячет корень листом главы).
    if (sc.chapter && sc.screen === 'settings') for (const k of Object.keys(nat.nodes)) if (/^(header|mode|nav)/.test(k)) delete nat.nodes[k];
    // Соседняя вкладка тоже жива и пишет рамки за краем экрана — не в счёт.
    // Форма (24) — длинный лист в прокрутке: её узлы ниже края экрана у обеих
    // сторон в координатах непрокрученной формы, их и сверяем.
    if (!sc.form && sc.m28 !== 'meet') for (const [k, r] of Object.entries(nat.nodes)) if (r.x + r.w <= 0 || r.x >= 440 || r.y >= 956 || r.y + r.h <= 0) delete nat.nodes[k];
    // Под листом места экран жив и пишет рамки — сверяется только лист.
    if (sc.sheet) for (const k of Object.keys(nat.nodes)) if (!k.startsWith('loc.')) delete nat.nodes[k];
    // Под формой «Съёмки» живы и пишут рамки — сверяется только форма.
    if (sc.form) for (const k of Object.keys(nat.nodes)) if (!k.startsWith('form.')) delete nat.nodes[k];
    // Под карточкой «Съёмки» живы и пишут рамки — сверяется только карточка. Фаза
    // натива (`card.phase`) — словом в строке прогона: у веба такого узла нет.
    const natPhase = sc.card && nat.nodes['card.phase'] ? nat.nodes['card.phase'].text : null;
    if (sc.card) for (const k of Object.keys(nat.nodes)) if (!(k.startsWith('card.') || k.startsWith('refs.')) || k === 'card.phase') delete nat.nodes[k];
    // Экраны 28 лежат поверх «Съёмок»: сверяется только их разметка (имена — `M28[..].re`).
    if (sc.m28) for (const k of Object.keys(nat.nodes)) if (!sc.re.test(k)) delete nat.nodes[k];
    // Под слоем «Съёмки» живы и пишут рамки — сверяется только слой (и панель вкладок над ним).
    const keep = sc.layer && (k => LAYER_NODES[sc.layer].test(k) || (!LAYER_SHEETS[sc.layer] && /^tab(bar|\.)/.test(k)));
    if (keep) for (const k of Object.keys(nat.nodes)) if (!keep(k)) delete nat.nodes[k];
    const web = webShot(sc, sc.dir, nat.safe);
    // Режим маршрута (24а): прибор, закладка и сводка у натива гаснут
    // прозрачностью (затухание подмены), а рамки пишут — у веба они скрыты.
    if (sc.chapter === 'route') for (const [k, r] of Object.entries(web.nodes)) if (r.visible === false) delete nat.nodes[k];
    if (sc.m28 && sc.m28 !== 'meet') for (const [k, r] of Object.entries(web.nodes)) if (r.y >= 956 || r.x >= 440) delete web.nodes[k];
    // Карточка длиннее экрана: ниже его края у веба тоже не в счёт.
    if (sc.card) for (const [k, r] of Object.entries(web.nodes)) if (r.y >= 956) delete web.nodes[k];
    /* Полоса карточки у натива — под вырезом экрана (29.09: на 46 от верха
       «＋» уходил под островок), у Chromium пары выреза нет. Сверка — от «✕»:
       всё натива поднимается на разницу, сама разница — в строке прогона. */
    const lift = sc.card && nat.nodes['card.back'] && web.nodes['card.back']
      ? nat.nodes['card.back'].y - web.nodes['card.back'].y : 0;
    if (lift) console.log(`${sc.name}: полоса натива ниже на ${lift} pt (вырез), сверка от «✕»`);
    if (sc.card) console.log(`${sc.name}: ${sc.at}, фаза натива ${natPhase}` + (natPhase === sc.phase ? '' : ` — ждали ${sc.phase}`));
    if (sc.card && natPhase !== sc.phase) phaseMiss.push(`${sc.name}: ${natPhase}, ждали ${sc.phase}`);
    if (keep) for (const [k, r] of Object.entries(web.nodes)) {
      // Лента прокручена к месяцу: ушедшее за край экрана у веба тоже не в счёт.
      if (!keep(k) || r.visible !== false && (r.y >= 956 || r.y + r.h <= 0)) delete web.nodes[k];
    }
    // Лист главы у веба закрывает панель вкладок, но в разметке она «видна»;
    // приложение её прячет — под главой панель не сверяется.
    if (sc.chapter && sc.screen === 'settings') for (const k of Object.keys(web.nodes)) if (/^tab(bar|\.)/.test(k)) delete web.nodes[k];
    const cmp = await compare(page, sc.dir, web, nat, 3);
    // Цвета взяты с кадров как есть, смещение по высоте — от «✕» (см. выше).
    if (lift) { cmp.lift = lift; for (const r of cmp.rows) if (r.d) r.d[1] = +(r.d[1] - lift).toFixed(1); }
    await pairImage(page, sc.dir, web, nat);
    /* Лист места (21в): системный лист iOS 26 на неполной высоте — парящая
       карточка, всё в ней уменьшено в (ширина листа / 440) раз (замер:
       424 / 440 = 0,964). Сверка раскладки — смещения от верха листа,
       делённые на этот масштаб. */
    const sheetKey = sc.m28 === 'quest' ? 'quest.sheet' : sc.sheet ? 'loc.sheet' : LAYER_SHEETS[sc.layer] ? sc.layer + '.sheet' : null;
    if (sheetKey && web.nodes[sheetKey] && nat.nodes[sheetKey]) {
      const ns = nat.nodes[sheetKey], ws = web.nodes[sheetKey], k = ns.w / 440;
      let worst = { v: 0, name: '—' };
      cmp.norm = { scale: +k.toFixed(4), rows: {} };
      for (const [name, a] of Object.entries(web.nodes)) {
        const b = nat.nodes[name];
        if (name === sheetKey || !b || a.visible === false) continue;
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
  if (roadStates.length) {
    fs.writeFileSync(path.join(OUT, 'roads.json'), JSON.stringify(roadsOut, null, 1));
    console.log('маршрут по ответам серверов: ' + path.join(OUT, 'roads.json'));
    const fails = Object.entries(roadsOut).flatMap(([k, v]) => v.bad.map(m => k + ': ' + m));
    if (fails.length) throw new Error('маршрут: ' + fails.length + ' нарушений:\n' + fails.join('\n'));
    return;
  }
  if (dragStates.length) {
    fs.writeFileSync(path.join(OUT, 'drag.json'), JSON.stringify(dragOut, null, 1));
    console.log('блок в руке: ' + path.join(OUT, 'drag.json'));
    const fails = Object.entries(dragOut).flatMap(([k, v]) => v.bad.map(m => k + ': ' + m));
    if (fails.length) throw new Error('блок в руке: ' + fails.length + ' нарушений:\n' + fails.join('\n'));
    return;
  }
  if (netStates.length) {
    fs.writeFileSync(path.join(OUT, 'network.json'), JSON.stringify(netOut, null, 1));
    console.log('глава «Сеть»: ' + path.join(OUT, 'network.json'));
    const fails = Object.entries(netOut).flatMap(([k, v]) => v.bad.map(m => k + ': ' + m));
    if (fails.length) throw new Error('глава «Сеть»: ' + fails.length + ' нарушений:\n' + fails.join('\n'));
    return;
  }
  if (args['no-weather']) {
    fs.writeFileSync(path.join(OUT, 'no_weather.json'), JSON.stringify(noWeather, null, 1));
    console.log('без прогноза: ' + path.join(OUT, 'no_weather.json'));
    const bad = forbiddenSeen(noWeather);
    if (bad.length) throw new Error('без прогноза на экране есть узлы погоды (' + bad.length + '):\n' + bad.join('\n'));
    return;
  }
  fs.writeFileSync(path.join(OUT, 'report.md'), markdown(results));
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(results, null, 1));
  console.log('отчёт: ' + path.join(OUT, 'report.md'));
  if (phaseMiss.length) throw new Error('фаза карточки не совпала у ' + phaseMiss.length + ':\n' + phaseMiss.join('\n'));
})().catch(e => { console.error(String(e && e.stack || e)); process.exit(1); });
