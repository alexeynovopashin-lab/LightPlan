#!/usr/bin/env node
/* Геометрия «блок карточки в руке» (27а.3) для `pair.js --drag`, без браузера и пикселей — поэтому проверяется
   сама (`node Tools/shots/drag_geom.js --selftest`).

   Поднятая строка стоит на `dy` ниже своего места и размера не меняет (56); слот — на месте
   `to = clamp(i + round(dy / 64))`; соседи между старым местом и слотом шагнули ровно на 64.
   Рука не выходит за список: сдвиг прижат к `[-i·64, (n-1-i)·64]` (`CardOrderList.swift`, `dy = min(max(raw, …), …)`) —
   живой прогон 12.10 на `place:-150`: строка встала на верх списка, а не на 22 pt выше него.

   Начало сетки строк берётся не от «первой строки» (её сам слот может сдвинуть на 64, когда блок
   унесли на первое место), а от любой неподнятой строки, у которой известно, где она должна стоять
   (хвост 06.10, случай 1). Слот, закрытый поднятой строкой целиком (сдвиг на целое число шагов, 64 pt) —
   не нарушение: проверять в нём нечего, пиксели слота пропускаются (хвост 06.10, случай 2). */
const ORDER = ['deal', 'day', 'place', 'weather', 'brief', 'docs', 'notes', 'delivery', 'money'];
const STEP = 64, H = 56, TOL = 0.6;

/* rects: { <блок>: {x, y, w, h} } из рамок `card.order.row.<блок>`. */
function geometry(rects, blk, dy) {
  const bad = [], li = ORDER.indexOf(blk);
  for (const k of ORDER) if (!rects[k]) bad.push('нет строки ' + k);
  if (bad.length) return { bad };
  const to = Math.max(0, Math.min(ORDER.length - 1, li + Math.round(dy / STEP)));
  const held = Math.max(-li * STEP, Math.min((ORDER.length - 1 - li) * STEP, dy));   // сдвиг руки после прижима к краям
  // Где строка i стоит на сетке, когда блок li унесён на место `to`.
  const place = i => {
    if (i === li) return to;
    const j = i > li ? i - 1 : i;     // номер среди остальных
    return j >= to ? j + 1 : j;
  };
  const ref = li === 0 ? 1 : 0;       // неподнятая строка, от неё сетка
  const y0 = rects[ORDER[ref]].y - STEP * place(ref);
  const frames = {};
  ORDER.forEach((k, i) => {
    const r = rects[k], want = i === li ? y0 + STEP * li + held : y0 + STEP * place(i);
    frames[k] = { y: +r.y.toFixed(1), want, h: +r.h.toFixed(1) };
    if (Math.abs(r.y - want) > TOL) bad.push(`${k}: y ${r.y.toFixed(1)}, ждали ${want}`);
    if (Math.abs(r.h - H) > TOL) bad.push(`${k}: высота ${r.h.toFixed(1)}, ждали ${H} (размер не меняется)`);
    if (Math.abs(r.x - 36) > TOL || Math.abs(r.w - 368) > TOL) bad.push(`${k}: x ${r.x} w ${r.w}`);
  });
  const slotTop = y0 + STEP * to, liftTop = y0 + STEP * li + held;
  // Открытая часть слота: слот минус поднятая строка (две полосы — над ней и под ней), берём большую; отступ 4 pt
  // от краёв полосы, чтобы не попасть в сглаженный край и тень строки.
  const bands = [[slotTop, Math.min(slotTop + H, liftTop)], [Math.max(slotTop, liftTop + H), slotTop + H]].filter(b => b[1] - b[0] > 8);
  const open = bands.sort((a, b) => (b[1] - b[0]) - (a[1] - a[0]))[0];
  return { bad, li, to, held, y0, slotTop, liftTop, frames, openSlotY: open ? (open[0] + open[1]) / 2 : null, slotCovered: !open };
}

module.exports = { ORDER, STEP, geometry };

/* ── самопроверка: порча краснеет, правильные кадры зелёные ── */
if (require.main === module) {
  if (!process.argv.includes('--selftest')) { console.error('node Tools/shots/drag_geom.js --selftest'); process.exit(2); }
  const Y0 = 300;
  // Кадр, каким он должен быть: тот же закон, что в `geometry`, записанный прямо, без общих функций.
  const layout = (blk, dy) => {
    const li = ORDER.indexOf(blk), to = Math.max(0, Math.min(ORDER.length - 1, li + Math.round(dy / STEP)));
    const rest = ORDER.filter(k => k !== blk);
    rest.splice(to, 0, blk);                       // порядок после того, как блок встал в слот
    const r = {};
    ORDER.forEach(k => { r[k] = { x: 36, y: Y0 + STEP * rest.indexOf(k), w: 368, h: H }; });
    r[blk].y = Y0 + STEP * li + Math.max(-li * STEP, Math.min((ORDER.length - 1 - li) * STEP, dy));   // в руке, прижата к краям списка
    return r;
  };
  let fails = 0;
  const check = (name, cond, extra = '') => { if (!cond) fails++; console.log((cond ? 'ok    ' : 'КРАСНОЕ ') + name + (cond ? '' : ' ' + extra)); };
  const run = (blk, dy, mutate) => { const r = layout(blk, dy); if (mutate) mutate(r); return geometry(r, blk, dy); };

  // Стандартные кадры шага.
  for (const dy of [24, 44]) check(`place:${dy} — рамки сходятся`, run('place', dy).bad.length === 0);
  // Случай 1: не первая строка унесена на первое место — сетка не от сдвинутой первой строки.
  const up = run('weather', -200);
  check('weather на первое место: слот 0, рамки сходятся', up.to === 0 && up.bad.length === 0, JSON.stringify(up.bad));
  check('weather на первое место: начало сетки не уехало', up.y0 === Y0, 'y0 ' + up.y0);
  // Блок в руке — первая строка.
  const first = run('deal', 150);
  check('deal на третье место: рамки сходятся', first.to === 2 && first.bad.length === 0, JSON.stringify(first.bad));
  // Рука не выходит за список: сдвиг -150 у третьей строки прижат к верху (живой прогон), +900 — к низу.
  check('place:-150 — рука прижата к верху списка, рамки сходятся', run('place', -150).bad.length === 0 && run('place', -150).held === -128);
  check('place:900 — рука прижата к низу списка, рамки сходятся', run('place', 900).bad.length === 0 && run('place', 900).to === ORDER.length - 1);
  check('place:-150 — рука выше списка (без прижима) — красное', run('place', -150, r => { r.place.y -= 22; }).bad.length > 0);
  // Случай 2: сдвиг ровно на шаг — слот закрыт строкой, это не нарушение.
  const whole = run('place', 64);
  check('place:64 — слот закрыт строкой, нарушения нет', whole.bad.length === 0 && whole.slotCovered && whole.openSlotY === null, JSON.stringify(whole.bad));
  check('place:24 — слот виден полосой', run('place', 24).slotCovered === false);
  // Порча: каждая должна покраснеть.
  check('сосед не шагнул — красное', run('place', 44, r => { r.weather.y -= STEP; }).bad.length > 0);
  check('на первом месте сосед не шагнул — красное', run('weather', -200, r => { r.deal.y -= STEP; }).bad.length > 0);
  check('высота строки изменилась — красное', run('place', 24, r => { r.notes.h = 60; }).bad.length > 0);
  check('нет строки — красное', geometry({ deal: { x: 36, y: 0, w: 368, h: H } }, 'place', 24).bad.length > 0);
  console.log(fails ? `КРАСНЫХ: ${fails}` : 'зелёный');
  process.exit(fails ? 1 : 0);
}
