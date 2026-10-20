#!/usr/bin/env node
/* Шаг 29.8в.4: экран AR в симуляторе с подставной камерой. Только натив: у веба AR нет, пары быть не может.

   Камера — `-LPSunARFakeCamera 1` (отладка): тридцать кадров в секунду из двух заранее нарисованных, весь
   путь «кадр → слой Metal → диск» работает как с настоящей камерой. Место телефона подставляется
   (`-LPSunARPhone`), поворот — `-LPSunARPose`, момент — `-LPSunARMoment`.

   Сценарии: day (солнце в кадре, луна ниже горизонта), sunset (солнце на горизонте: красно-оранжевый диск,
   дуга и линия горизонта в диске гнутся), blue (синий час: солнце под горизонтом — призрак, контур пунктиром),
   dusk_both (солнце-призрак и луна в одном кадре: различие без цвета), night_moon (луна в фазе, солнце за
   краем — стрелка), night_mw (Млечный Путь и луна, ядро над горизонтом), toggles (оба включателя и курс в
   ряду: рамки не накладываются; на узком симуляторе — `LP_SIM="<имя SE>"`), entry_far (плашка входа:
   выбранное далеко от телефона), entry_off (плашка входа: нет доступа к геопозиции).
   `--only a,b` — только эти сценарии.

   Числа из отчёта приложения (рамки узлов): диаметры меток, высота касания кнопок, присутствие слоёв,
   стрелки и плашки. Любое нарушение — код 1.

     node Tools/shots/ar.js [--skip-build] [--out <dir>]      (или make shots ARGS="--screens ar")        */
const fs = require('fs'), os = require('os'), path = require('path');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : []).filter(x => x.length));
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const BUNDLE = 'Novopashin.LightPlan';
// 29.8в.16: язык (`--lang ru|en`) и тема (`--appearance dark|light`) снимка; по умолчанию как раньше — русский, тёмная.
const LANG = String(args.lang || 'ru'), APPEARANCE = String(args.appearance || 'dark');
const LOCALE = { ru: 'ru_RU', en: 'en_US', es: 'es_ES', ja: 'ja_JP', zh: 'zh_CN' }[LANG] || LANG;
const TOMSK = '56.4977,84.9744,Asia/Tomsk', MOSCOW = '55.7558,37.6173,Europe/Moscow';
// Южная широта начинается с минуса: такое значение аргумента система читает как новый ключ, поэтому оно уходит в
// приложение строкой plist в кавычках (см. запуск ниже).
const SYDNEY = '-33.8688,151.2093,Australia/Sydney';

/* Сценарии: now — «сейчас» приложения, moment — выбранный момент, pose — азимут,высота,крен. */
const SCENARIOS = [
  { name: 'day', now: '2026-10-14T12:00:00+07:00', moment: '2026-10-14T05:00:00Z', pose: '162,24,0', phone: TOMSK,
    moon: true, mw: false, camera: true, merged: true },
  { name: 'sunset', now: '2026-10-20T17:00:00+07:00', moment: '2026-10-20T11:00:00Z', pose: '251,4,0', phone: TOMSK,
    moon: false, mw: false, camera: true },
  { name: 'blue', now: '2026-10-20T19:00:00+07:00', moment: '2026-10-20T12:00:00Z', pose: '263,0,0', phone: TOMSK,
    moon: false, mw: false, camera: true },
  { name: 'dusk_both', now: '2026-10-12T19:30:00+07:00', moment: '2026-10-12T12:30:00Z', pose: '262,0,0', phone: TOMSK,
    moon: true, mw: false, camera: true },
  { name: 'toggles', now: '2026-10-14T12:00:00+07:00', moment: '2026-10-14T05:00:00Z', pose: '162,24,0', phone: TOMSK,
    moon: true, mw: true, camera: true, merged: true },
  // 29.8в.9б: список «Слоёв» открыт (`-LPSunARLayersOpen 1`, отладка): строки луны и Млечного Пути на стекле.
  { name: 'layers_open', now: '2026-10-14T12:00:00+07:00', moment: '2026-10-14T05:00:00Z', pose: '162,24,0', phone: TOMSK,
    moon: true, mw: false, camera: true, merged: true, layersOpen: true },
  { name: 'night_moon', now: '2026-10-20T21:00:00+07:00', moment: '2026-10-20T14:00:00Z', pose: '183,18,0', phone: TOMSK,
    moon: true, mw: false, camera: true },
  { name: 'night_mw', now: '2026-08-20T22:00:00+07:00', moment: '2026-08-20T15:00:00Z', pose: '198,14,0', phone: TOMSK,
    moon: true, mw: true, camera: true },
  // 29.8в.6: подписи у горизонта на рассвете («восход 07:57» рядом с часом «08:00»): зазор между плашками ≥ 4 pt.
  { name: 'sunrise', now: '2026-10-17T09:00:00+07:00', moment: '2026-10-17T02:00:00Z', pose: '107.4,6,0', phone: TOMSK,
    moon: false, mw: false, camera: true, merged: true, sunrise: true },
  // 29.8в.6: диск солнца под верхними кнопками не виден — стрелка к нему нужна.
  { name: 'under_buttons', now: '2026-10-14T12:00:00+07:00', moment: '2026-10-14T05:00:00Z', pose: '162,-4,0', phone: TOMSK,
    moon: false, mw: false, camera: true, merged: true, underButtons: true },
  // 29.8в.7: центр диска в окне видимости, верхний край под кнопками — стрелка всё равно нужна.
  { name: 'half_hidden', now: '2026-10-14T12:00:00+07:00', moment: '2026-10-14T05:00:00Z', pose: '162,2.6,0', phone: TOMSK,
    moon: false, mw: false, camera: true, merged: true, halfHidden: true },
  // 29.8в.13: звёзды и созвездия. Ночь (солнце ≈ −25°): точки, линии, названия; сумерки (−6…−12°): яркость растёт плавно;
  // день: слои включены, звёзд нет, плашка «Звёзд днём не видно». Подписи не ложатся на метки, подписи и стрелки.
  { name: 'night_stars', now: '2026-10-20T21:00:00+07:00', moment: '2026-10-20T14:00:00Z', pose: '30,42,0', phone: TOMSK,
    moon: false, mw: false, stars: true, cons: true, camera: true, starsNight: true },
  { name: 'night_stars_sw', now: '2026-10-20T21:00:00+07:00', moment: '2026-10-20T14:00:00Z', pose: '240,52,0', phone: TOMSK,
    moon: false, mw: false, stars: true, cons: true, camera: true, starsNight: true },
  // Те же кадры на ровном ночном фоне (`-LPSunARBackdrop night`): так звёзды выглядят на настоящем ночном небе, а не на
  // подставном кадре с закатным градиентом.
  { name: 'night_stars_dark', now: '2026-10-20T21:00:00+07:00', moment: '2026-10-20T14:00:00Z', pose: '30,42,0', phone: TOMSK,
    moon: false, mw: false, stars: true, cons: true, camera: true, backdrop: 'night', starsNight: true },
  { name: 'night_stars_sw_dark', now: '2026-10-20T21:00:00+07:00', moment: '2026-10-20T14:00:00Z', pose: '240,52,0', phone: TOMSK,
    moon: false, mw: false, stars: true, cons: true, camera: true, backdrop: 'night', starsNight: true },
  { name: 'night_stars_s_dark', now: '2026-10-20T21:00:00+07:00', moment: '2026-10-20T14:00:00Z', pose: '200,30,0', phone: TOMSK,
    moon: false, mw: false, stars: true, cons: false, camera: true, backdrop: 'night', starsNight: true },
  // 29.8в.13б: яркие звёзды вне фигур в слое — южная ночь в Сиднее. Южный Крест (≈ 50°, юго-запад) и Канопус (≈ 4°) в один
  // кадр не входят: Крест уходит под кнопки, Канопус — под панель. Два кадра, в каждом звезда подписана.
  { name: 'night_stars_cross_dark', now: '2026-06-15T22:00:00+10:00', moment: '2026-06-15T12:00:00Z', pose: '214,42,0', phone: SYDNEY,
    moon: false, mw: false, stars: true, cons: false, camera: true, backdrop: 'night', starsNight: true,
    starLabels: ['star.acrux', 'star.mimosa'] },
  { name: 'night_stars_canopus_dark', now: '2026-06-15T22:00:00+10:00', moment: '2026-06-15T12:00:00Z', pose: '204,0,0', phone: SYDNEY,
    moon: false, mw: false, stars: true, cons: false, camera: true, backdrop: 'night', starsNight: true,
    starLabels: ['star.canopus'] },
  { name: 'night_all', now: '2026-10-20T21:00:00+07:00', moment: '2026-10-20T14:00:00Z', pose: '183,18,0', phone: TOMSK,
    moon: true, mw: true, stars: true, cons: true, camera: true, starsNight: true },
  { name: 'dusk_stars', now: '2026-10-20T19:00:00+07:00', moment: '2026-10-20T12:00:00Z', pose: '60,38,0', phone: TOMSK,
    moon: false, mw: false, stars: true, cons: true, camera: true, starsDusk: true },
  { name: 'day_stars', now: '2026-10-14T12:00:00+07:00', moment: '2026-10-14T05:00:00Z', pose: '162,24,0', phone: TOMSK,
    moon: false, mw: false, stars: true, cons: true, camera: true, merged: true, starsDay: true },
  { name: 'day_stars_moon', now: '2026-10-14T12:00:00+07:00', moment: '2026-10-14T05:00:00Z', pose: '162,24,0', phone: TOMSK,
    moon: true, mw: false, stars: true, cons: true, camera: true, merged: true, starsDay: true },
  // 29.8в.15: планеты. Ночь: Марс и Юпитер в 3° друг от друга (подписи не друг на друге); то же вместе со звёздами и
  // созвездиями (подписи слоёв не накладываются); сумерки: Сатурн, яркость между 0 и 1; день: слой включён, планет нет;
  // Меркурий в 13° от Солнца утром: не нарисован, в списке «Слоёв» подписан; день в списке: «Днём планет не видно».
  { name: 'planets_night', now: '2026-11-04T03:00:00+07:00', moment: '2026-11-04T20:00:00Z', pose: '93,20,0', phone: TOMSK,
    moon: false, mw: false, planets: true, camera: true, backdrop: 'night', planetsNight: true, planetNames: ['mars', 'jupiter'] },
  { name: 'planets_night_stars', now: '2026-11-04T03:00:00+07:00', moment: '2026-11-04T20:00:00Z', pose: '93,20,0', phone: TOMSK,
    moon: false, mw: false, stars: true, cons: true, planets: true, camera: true, backdrop: 'night', starsNight: true,
    planetsNight: true, planetNames: ['mars', 'jupiter'] },
  { name: 'planets_dusk', now: '2026-10-20T19:00:00+07:00', moment: '2026-10-20T12:00:00Z', pose: '101,10,0', phone: TOMSK,
    moon: false, mw: false, planets: true, camera: true, planetsDusk: true, planetNames: ['saturn'] },
  { name: 'planets_day', now: '2026-10-14T12:00:00+07:00', moment: '2026-10-14T05:00:00Z', pose: '231,35,0', phone: TOMSK,
    moon: false, mw: false, planets: true, camera: true, planetsDay: true },
  { name: 'planets_near', now: '2026-11-11T08:00:00+07:00', moment: '2026-11-11T01:00:00Z', pose: '118,6,0', phone: TOMSK,
    moon: false, mw: false, planets: true, camera: true, layersOpen: true, planetsNear: ['mercury'], planetsDusk: true },
  { name: 'planets_day_list', now: '2026-10-14T12:00:00+07:00', moment: '2026-10-14T05:00:00Z', pose: '231,35,0', phone: TOMSK,
    moon: false, mw: false, planets: true, camera: true, layersOpen: true, planetsDay: true, planetsDayList: true },
  { name: 'entry_far', now: '2026-10-20T21:00:00+07:00', moment: '2026-10-20T14:00:00Z', pose: '183,18,0', phone: MOSCOW,
    moon: false, mw: false, camera: false, entry: true },
  { name: 'entry_off', now: '2026-10-20T21:00:00+07:00', moment: '2026-10-20T14:00:00Z', pose: '183,18,0', phone: null,
    moon: false, mw: false, camera: false, entry: true },
];

const node = (nodes, k) => nodes[k];
const gapOf = (a, b) => {
  const dx = Math.max(b.x - (a.x + a.w), a.x - (b.x + b.w)), dy = Math.max(b.y - (a.y + a.h), a.y - (b.y + b.h));
  return dx > 0 && dy > 0 ? Math.hypot(dx, dy) : Math.max(dx, dy);
};
/* 29.8в.15: планеты — яркость по солнцу, день, «рядом с Солнцем», подписи не на чужих подписях. */
function planetChecks(sc, nodes, bad) {
  const pl = nodes['ar.planets'];
  if (!pl) { bad.push('нет узла ar.planets'); return; }
  const t = pl.text || '';
  const vis = +(/vis=([0-9.]+)/.exec(t) || [])[1], day = /day=1/.test(t);
  const names = ((/names=([a-z,]*)/.exec(t) || [])[1] || '').split(',').filter(Boolean);
  const near = ((/near=([a-z,]*)/.exec(t) || [])[1] || '').split(',').filter(Boolean);
  const labels = Object.keys(nodes).filter(k => k.startsWith('ar.planetLabel.'));
  if (sc.planetsNight) {
    if (vis !== 1 || day) bad.push('ночью яркость планет не 1: ' + t);
    for (const n of sc.planetNames || []) {
      if (!names.includes(n)) bad.push('нет точки планеты ' + n + ': ' + t);
      if (!nodes['ar.planetLabel.' + n]) bad.push('нет подписи планеты ' + n);
    }
  }
  if (sc.planetsDusk) {
    if (!(vis > 0 && vis < 1) || day) bad.push('в сумерках яркость планет не между 0 и 1: ' + t);
    for (const n of sc.planetNames || []) if (!names.includes(n)) bad.push('нет точки планеты ' + n + ': ' + t);
  }
  if (sc.planetsDay) {
    if (vis !== 0 || !day) bad.push('днём яркость планет не 0: ' + t);
    if (labels.length) bad.push('днём стоят подписи планет: ' + labels.join(','));
  }
  for (const n of sc.planetsNear || []) {
    if (!near.includes(n)) bad.push(n + ' ближе 15° к Солнцу, а в сцене «рядом» нет: ' + t);
    if (names.includes(n)) bad.push(n + ' рядом с Солнцем, а точка нарисована');
    if (nodes['ar.planetLabel.' + n]) bad.push(n + ' рядом с Солнцем, а подпись стоит');
    const row = (nodes['ar.layer.planets'] || {}).text || '';
    if (!/рядом с Солнцем|near the Sun/.test(row)) bad.push('строка «Планеты» не говорит «рядом с Солнцем»: ' + row);
  }
  if (sc.planetsDayList && !/Днём планет не видно|No planets in daylight/.test((nodes['ar.layer.planets'] || {}).text || '')) bad.push('в списке нет «Днём планет не видно»: ' + (nodes['ar.layer.planets'] || {}).text);
  // Ничего слоя не лежит на метках, подписях, стрелках и подписях звёзд, подписи — друг на друге тоже нет.
  const other = Object.keys(nodes).filter(k => /^ar\.(mark\.|pointer|label\.|layers$|back$|follow$|calibrate$|heading$|panel$|starLabel\.|starsDay)/.test(k));
  const scr = nodes['ar.background'];
  for (const k of labels) {
    const a = nodes[k];
    if (scr && (a.x < -0.5 || a.y < -0.5 || a.x + a.w > scr.w + 0.5 || a.y + a.h > scr.h + 0.5)) bad.push(`${k} за краем экрана`);
    for (const o of other) if (gapOf(a, nodes[o]) < 0) bad.push(`${k} лежит на ${o}`);
  }
  for (let i = 0; i < labels.length; i++) for (let j = i + 1; j < labels.length; j++) if (gapOf(nodes[labels[i]], nodes[labels[j]]) < 0) bad.push(`${labels[i]} лежит на ${labels[j]}`);
}
/* 29.8в.13: звёзды и созвездия — яркость по солнцу, дневная плашка, подписи не на чужих подписях. */
function starChecks(sc, nodes, bad) {
  const st = nodes['ar.stars'];
  if (!st) { bad.push('нет узла ar.stars'); return; }
  const t = st.text || '';
  const vis = +(/vis=([0-9.]+)/.exec(t) || [])[1], day = /day=1/.test(t);
  const dots = +(/dots=(\d+)/.exec(t) || [])[1], lines = +(/lines=(\d+)/.exec(t) || [])[1];
  if (sc.starsNight) {
    if (vis !== 1 || day) bad.push('ночью яркость слоя не 1: ' + t);
    if (sc.stars && !(dots > 0)) bad.push('точек нет: ' + t);
    if (sc.cons && !(lines > 0)) bad.push('линий фигур нет: ' + t);
    if (nodes['ar.starsDay']) bad.push('ночью плашка «днём не видно»');
    for (const k of sc.starLabels || []) if (!nodes['ar.starLabel.' + k]) bad.push('нет подписи ' + k);
  }
  if (sc.starsDusk) {
    if (!(vis > 0 && vis < 1) || day) bad.push('в сумерках яркость не между 0 и 1: ' + t);
    if (nodes['ar.starsDay']) bad.push('в сумерках плашка «днём не видно»');
  }
  if (sc.starsDay) {
    if (vis !== 0 || !day) bad.push('днём яркость не 0: ' + t);
    const n = nodes['ar.starsDay'];
    if (!n) bad.push('днём нет плашки «Звёзд днём не видно»');
    else if (!/Звёзд днём не видно/.test(n.text || '')) bad.push('плашка говорит не то: ' + n.text);
    if (Object.keys(nodes).some(k => k.startsWith('ar.starLabel.'))) bad.push('днём стоят подписи звёзд');
  }
  // Ничего слоя не лежит на метках, подписи выбранного момента и стрелках (правила 29.8в.6, 29.8в.10); сами подписи слоя
  // — друг на друге тоже нет.
  const mine = Object.keys(nodes).filter(k => k.startsWith('ar.starLabel.') || k === 'ar.starsDay');
  const other = Object.keys(nodes).filter(k => /^ar\.(mark\.|pointer|label\.|layers$|back$|follow$|calibrate$|heading$|panel$)/.test(k));
  const scr = nodes['ar.background'];
  for (const k of mine) {
    const a = nodes[k];
    if (scr && (a.x < -0.5 || a.y < -0.5 || a.x + a.w > scr.w + 0.5 || a.y + a.h > scr.h + 0.5)) bad.push(`${k} за краем экрана`);
    for (const o of other) if (gapOf(a, nodes[o]) < 0) bad.push(`${k} лежит на ${o}`);
  }
  for (let i = 0; i < mine.length; i++) for (let j = i + 1; j < mine.length; j++) if (gapOf(nodes[mine[i]], nodes[mine[j]]) < 0) bad.push(`${mine[i]} лежит на ${mine[j]}`);
}
/* Проверки по рамкам узлов. Возвращают список нарушений. */
function verdict(sc, nodes) {
  const bad = [];
  const need = k => { if (!nodes[k]) { bad.push('нет узла ' + k); return false; } return true; };
  const touch = k => { if (need(k) && nodes[k].h < 43.9) bad.push(`${k}: высота касания ${nodes[k].h.toFixed(1)} < 44`); };
  if (sc.entry) {
    need('ar.entry'); need('ar.entry.why'); touch('ar.entry.useMine'); touch('ar.entry.keep');
    if (nodes['ar.entry.keep'] && !/Барнаул/.test(nodes['ar.entry.keep'].text || '')) bad.push('«Оставить» не называет выбранное место');
    if (nodes['ar.entry.useMine'] && !/моё местоположение/.test(nodes['ar.entry.useMine'].text || '')) bad.push('нет «Использовать моё местоположение»');
    return bad;
  }
  touch('ar.back'); touch('ar.layers');
  if (nodes['ar.layers'] && (nodes['ar.layers'].w < 43.9 || Math.abs(nodes['ar.layers'].w - nodes['ar.layers'].h) > 0.5)) bad.push('кнопка «Слои» не круг 44 pt: ' + nodes['ar.layers'].w + ' × ' + nodes['ar.layers'].h);
  if (nodes['ar.moonToggle'] || nodes['ar.mwToggle']) bad.push('остались круглые включатели луны / Млечного Пути: слои — одной кнопкой');
  // Кнопка «Слои» показывает включённые слои (точки под значком); список — в отчёте текстом узла.
  if (nodes['ar.layers']) {
    const on = (nodes['ar.layers'].text || '').split(',').filter(Boolean).sort().join(',');
    const want = [sc.moon ? 'moon' : '', sc.mw ? 'milkyWay' : '', sc.stars ? 'stars' : '', sc.cons ? 'constellations' : '', sc.planets ? 'planets' : ''].filter(Boolean).sort().join(',');
    if (on !== want) bad.push(`«Слои» показывает «${on}», включено «${want}»`);
  }
  if (sc.layersOpen) {
    for (const k of ['ar.layer.moon', 'ar.layer.mw', 'ar.layer.stars', 'ar.layer.constellations', 'ar.layer.planets']) { if (need(k)) touch(k); }
    for (const k of ['ar.layer.stars', 'ar.layer.constellations']) if (nodes[k] && !/off$/.test(nodes[k].text || '')) bad.push(k + ' включена сама: ' + nodes[k].text);
    const a = nodes['ar.layer.moon'], b = nodes['ar.layer.mw'];
    if (a && b && Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y) > 0.5) bad.push('строки слоёв накладываются');
    if (a && sc.moon && !/on$/.test(a.text || '')) bad.push('луна включена, а строка говорит: ' + a.text);
    if (b && !sc.mw && !/off$/.test(b.text || '')) bad.push('Млечный Путь выключен, а строка говорит: ' + b.text);
    // Строки списка не накладываются друг на друга и пять строк стоят одна под другой.
    const rows = ['ar.layer.moon', 'ar.layer.mw', 'ar.layer.stars', 'ar.layer.constellations', 'ar.layer.planets'].map(k => nodes[k]).filter(Boolean);
    for (let i = 0; i < rows.length; i++) for (let j = i + 1; j < rows.length; j++) if (Math.min(rows[i].y + rows[i].h, rows[j].y + rows[j].h) - Math.max(rows[i].y, rows[j].y) > 0.5) bad.push('строки слоёв накладываются: ' + i + '/' + j);
    const plRow = nodes['ar.layer.planets'];
    if (plRow && sc.planets && !/on$/.test(plRow.text || '')) bad.push('планеты включены, а строка говорит: ' + plRow.text);
    if (plRow && !sc.planets && !/off$/.test(plRow.text || '')) bad.push('планеты выключены, а строка говорит: ' + plRow.text);
  } else if (nodes['ar.layer.moon'] || nodes['ar.layer.mw'] || nodes['ar.layer.stars'] || nodes['ar.layer.constellations'] || nodes['ar.layer.planets']) bad.push('список слоёв открыт без нажатия');
  // Ряд кнопок: рамки не накладываются друг на друга.
  const row = ['ar.back', 'ar.follow', 'ar.calibrate', 'ar.heading', 'ar.layers'].filter(k => nodes[k]);
  for (let i = 0; i < row.length; i++) for (let j = i + 1; j < row.length; j++) {
    const a = nodes[row[i]], b = nodes[row[j]];
    const ox = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x), oy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
    if (ox > 0.5 && oy > 0.5) bad.push(`${row[i]} и ${row[j]} накладываются на ${ox.toFixed(1)} × ${oy.toFixed(1)} pt`);
  }
  // Кнопки ряда целиком на экране (узкий экран: ряд не вылезает за край и не уходит под соседа).
  const scr = nodes['ar.background'];
  if (scr) for (const k of row) if (nodes[k].x < -0.5 || nodes[k].x + nodes[k].w > scr.w + 0.5) bad.push(`${k} за краем экрана: x ${nodes[k].x}, w ${nodes[k].w}, экран ${scr.w}`);
  // Время «сейчас» на метке не пишется: подпись — только у выбранного момента, и это время, а не слово.
  const lab = nodes['ar.label.picked'];
  if (lab && /сейчас/i.test(lab.text || '')) bad.push('на метке написано «сейчас»: ' + lab.text);
  if (sc.merged && lab) bad.push('метка одна («сейчас»), а подпись есть: ' + lab.text);
  if (!sc.merged && !sc.entry && sc.camera && lab === undefined && /sun\.picked/.test(Object.keys(nodes).join(','))) bad.push('у выбранного момента нет подписи времени');
  need('ar.panel');
  // Стрелки за краем не накладываются друг на друга (значки и подписи), зазор ≥ 8 pt (29.8в.6).
  const pts = Object.keys(nodes).filter(k => /^ar\.pointer(Label)?\./.test(k));
  const idOf = k => k.replace(/^ar\.pointer(Label)?\./, '');
  for (let i = 0; i < pts.length; i++) for (let j = i + 1; j < pts.length; j++) {
    if (idOf(pts[i]) === idOf(pts[j])) continue;
    const a = nodes[pts[i]], b = nodes[pts[j]];
    const dx = Math.max(b.x - (a.x + a.w), a.x - (b.x + b.w)), dy = Math.max(b.y - (a.y + a.h), a.y - (b.y + b.h));
    const gap = dx > 0 && dy > 0 ? Math.hypot(dx, dy) : Math.max(dx, dy);
    if (gap < 8) bad.push(`${pts[i]} и ${pts[j]}: зазор ${gap.toFixed(1)} pt < 8`);
  }
  if (sc.sunrise) {
    const m = /labelGap=(-?[0-9.]+)/.exec((nodes['ar.overlay'] || {}).text || '');
    if (!m) bad.push('в отчёте нет labelGap'); else if (+m[1] < 4) bad.push(`подписи у горизонта: зазор ${m[1]} pt < 4`);
  }
  if (sc.underButtons) {
    // Низ кнопок — самой нижней из них (на узком экране включатели стоят второй строкой).
    const bottom = Math.max(...['ar.back', 'ar.follow', 'ar.calibrate', 'ar.heading', 'ar.layers'].filter(k => nodes[k]).map(k => nodes[k].y + nodes[k].h));
    const mark = nodes['ar.mark.sun.now'];
    if (!mark) bad.push('диска солнца нет в кадре');
    // Диск скрыт целиком (вся рамка выше низа кнопок), а не только центр (29.8в.7).
    else if (mark.y + mark.h > bottom) bad.push(`диск не скрыт под кнопками целиком: низ диска y ${(mark.y + mark.h).toFixed(0)}, низ кнопок ${bottom.toFixed(0)}`);
    else if (!nodes['ar.pointer.sun']) bad.push('диск под кнопками, а стрелки к солнцу нет');
  }
  if (sc.halfHidden) {
    // Центр диска уже в окне видимости, верхний край ещё под кнопками: стрелка нужна, пока диск виден не целиком.
    const bottom = Math.max(...['ar.back', 'ar.follow', 'ar.calibrate', 'ar.heading', 'ar.layers'].filter(k => nodes[k]).map(k => nodes[k].y + nodes[k].h));
    const mark = nodes['ar.mark.sun.now'];
    if (!mark) bad.push('диска солнца нет в кадре');
    else if (mark.y >= bottom + 8) bad.push(`диск не залез под кнопки: верх y ${mark.y.toFixed(0)}, низ кнопок ${bottom.toFixed(0)}`);
    else if (mark.y + mark.h / 2 < bottom + 8) bad.push(`центр диска ещё под кнопками (y ${(mark.y + mark.h / 2).toFixed(0)}): сценарий не про край`);
    else if (!nodes['ar.pointer.sun']) bad.push('диск виден не целиком (край под кнопками), а стрелки к солнцу нет');
  }
  if (sc.stars || sc.cons) starChecks(sc, nodes, bad);
  else if (nodes['ar.stars']) bad.push('слой звёзд нарисован при выключенных переключателях');
  if (sc.planets) planetChecks(sc, nodes, bad);
  else if (nodes['ar.planets']) bad.push('слой планет нарисован при выключенном переключателе');
  const marks = Object.keys(nodes).filter(k => k.startsWith('ar.mark.'));
  const sun = marks.filter(k => /sun/.test(k)), moon = marks.filter(k => /moon/.test(k));
  for (const k of sun) if (![48, 34].includes(Math.round(nodes[k].w))) bad.push(`${k}: диаметр ${nodes[k].w} не 48/34`);
  if (sc.name === 'day' && !sun.length) bad.push('солнца в кадре нет');
  if (sc.name === 'night_moon') {
    if (!moon.length) bad.push('луны в кадре нет');
    if (!nodes['ar.pointer.sun']) bad.push('нет стрелки к солнцу за краем');
    for (const k of moon) {
      const t = nodes[k].text || '';
      const m = /f=([0-9.]+)/.exec(t);
      if (!/limb=-?[0-9.]/.test(t)) bad.push(k + ': нет наклона кромки (' + t + ')');
      if (!m || Math.abs(+m[1] - 0.69) > 0.02) bad.push(k + ': фаза ' + (m && m[1]) + ' не 0,69');
    }
  }
  if (sc.name === 'night_mw') {
    if (!need('ar.milkyWay')) return bad;
    const t = nodes['ar.milkyWay'].text || '';
    if (/polys=0/.test(t)) bad.push('полосы нет: ' + t);
    if (/core=—/.test(t)) bad.push('ядра нет в кадре: ' + t);
    if (/ghost=1/.test(t)) bad.push('ночью полоса идёт призраком: ' + t);
  }
  if (sc.moon && !sc.mw && nodes['ar.milkyWay']) bad.push('Млечный Путь нарисован при выключенном включателе');
  return bad;
}

(async () => {
  const udid = sim.device(ROOT).udid;
  try { run('xcrun', ['simctl', 'boot', udid], { stdio: 'ignore' }); } catch (e) {}
  const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-shots', 'ar'));
  fs.mkdirSync(OUT, { recursive: true });
  const dd = path.join(OUT, 'DerivedData');
  if (!args['skip-build']) {
    const log = path.join(OUT, 'xcodebuild.log');
    try {
      run('xcodebuild', ['-project', path.join(ROOT, 'LightPlan.xcodeproj'), '-scheme', 'LightPlan-iOS', '-configuration', 'Debug',
        '-destination', 'platform=iOS Simulator,id=' + udid, '-derivedDataPath', dd, 'build'], { stdio: ['ignore', fs.openSync(log, 'w'), fs.openSync(log, 'a')] });
    } catch (e) { throw new Error('сборка упала: ' + log); }
  }
  const products = path.join(dd, 'Build', 'Products', 'Debug-iphonesimulator');
  const app = path.join(products, fs.readdirSync(products).find(f => f.endsWith('.app')));
  run('xcrun', ['simctl', 'install', udid, app]);
  run('xcrun', ['simctl', 'ui', udid, 'appearance', APPEARANCE]);
  // Флаги устройства — аргументами запуска: `defaults write` через simctl пишет не в тот файл, что читает приложение.
  const flag = (k, v) => ['-lightplan.native.sunar.' + k, v ? 'YES' : 'NO'];

  const rows = [];
  const only = args.only ? String(args.only).split(',') : null;
  for (const sc of SCENARIOS) {
    if (only && !only.includes(sc.name)) continue;
    const dir = path.join(OUT, sc.name);
    fs.mkdirSync(dir, { recursive: true });
    const report = path.join(dir, 'native.json');
    fs.rmSync(report, { force: true });
    try { run('xcrun', ['simctl', 'terminate', udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
    run('xcrun', ['simctl', 'launch', udid, BUNDLE, '-AppleLanguages', `(${LANG})`, '-AppleLocale', LOCALE,
      '-LPShotNow', sc.now, '-LPShotZone', 'Asia/Tomsk', '-LPShotSeed', path.join(FX, 'seed.json'),
      '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
      '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'map', '-LPShotReportDelay', '5',
      ...flag('calibrationSeen', true), ...flag('moon', sc.moon), ...flag('milkyWay', sc.mw),
      ...flag('stars', sc.stars), ...flag('constellations', sc.cons), ...flag('planets', sc.planets),
      '-LPSunAR', '1', '-LPSunARMoment', sc.moment, '-LPSunARPose', sc.pose,
      ...(sc.phone ? ['-LPSunARPhone', sc.phone.startsWith('-') ? `"${sc.phone}"` : sc.phone] : []), ...(sc.camera ? ['-LPSunARFakeCamera', '1'] : []),
      ...(sc.backdrop ? ['-LPSunARBackdrop', sc.backdrop] : []),
      ...(sc.entry ? ['-LPSunAREntry', '1'] : []), ...(sc.layersOpen ? ['-LPSunARLayersOpen', '1'] : []),
      '-LPShotReport', report]);
    for (let i = 0; i < 240 && !fs.existsSync(report); i++) await sleep(250);
    if (!fs.existsSync(report)) throw new Error('нет рамок: ' + sc.name);
    await sleep(1500);
    run('xcrun', ['simctl', 'io', udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
    const nodes = JSON.parse(fs.readFileSync(report, 'utf8')).nodes || {};
    const bad = verdict(sc, nodes);
    const marks = Object.fromEntries(Object.keys(nodes).filter(k => /^ar\.(mark|pointer|milkyWay|stars|starLabel|starsDay|planets|planetLabel|layers?|layer|entry|overlay|back)/.test(k))
      .map(k => [k, { x: +nodes[k].x.toFixed(1), y: +nodes[k].y.toFixed(1), w: +nodes[k].w.toFixed(1), h: +nodes[k].h.toFixed(1), text: nodes[k].text }]));
    rows.push({ scenario: sc.name, bad, nodes: marks });
  }
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(rows, null, 1));
  for (const r of rows) console.log(r.scenario + ': ' + (r.bad.length ? 'НАРУШЕНИЯ ' + r.bad.join('; ') : 'ок') + '  [' + Object.keys(r.nodes).join(', ') + ']');
  console.log('→ ' + OUT);
  const fails = rows.flatMap(r => r.bad.map(m => `${r.scenario}: ${m}`));
  if (fails.length) throw new Error('AR: ' + fails.length + ' нарушений:\n' + fails.join('\n'));
})().catch(e => { console.error(e.message); process.exit(1); });
