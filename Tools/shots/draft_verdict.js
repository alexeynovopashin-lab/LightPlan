#!/usr/bin/env node
/* Вердикт `make draftday` (28о) по одной строке отчёта: список нарушений, пустой — всё сошлось.
   Раньше `orderOk`, `dateVisible`, `warnBetween` только писались в отчёт, прогон не падал (хвост 05.10).
   Чистая функция — своя самопроверка: `node Tools/shots/draft_verdict.js --selftest`.

   В `continue`, `new`, `warn` должны быть жанр, дата начала, время начала и «Кто» — без них порядок и «без
   прокрутки» не из чего считать, и молчаливое «не проверено» было бы зелёным. В `warn` — ещё плашка
   предупреждения, и она между датой и «Кто». В `ask` формы на экране нет (вопрос стоит над «Съёмками», живой
   прогон 12.10: ни одной рамки формы) — мерить там нечего; если рамки вдруг появились, их проверяют как у
   остальных. */
const SCREEN_H = 874, HOME_BAR = 34;
const LIMIT = SCREEN_H - HOME_BAR;

/* r — `{state, theme, genre, startDate, startVal, who, warn}`, у каждого `{y, bottom}` либо null. */
function verdict(r) {
  const bad = [];
  const formShown = r.state !== 'ask' || !!(r.genre || r.startDate || r.startVal || r.who);
  if (!formShown) return bad;
  const need = ['genre', 'startDate', 'startVal', 'who', ...(r.state === 'warn' ? ['warn'] : [])];
  const missing = need.filter(k => !r[k]);
  if (missing.length) { bad.push('нет рамок: ' + missing.join(', ') + ' — не проверено'); return bad; }
  if (!(r.startDate.bottom <= LIMIT && r.startVal.bottom <= LIMIT))
    bad.push(`дата и время ниже ${LIMIT} pt без прокрутки: дата до ${r.startDate.bottom}, время до ${r.startVal.bottom}`);
  if (!(r.genre.y < r.startDate.y && r.startDate.y < r.who.y))
    bad.push(`порядок блоков: жанр ${r.genre.y}, дата ${r.startDate.y}, «Кто» ${r.who.y}`);
  if (r.state === 'warn' && !(r.startDate.bottom <= r.warn.y && r.warn.bottom <= r.who.y))
    bad.push(`плашка не между датой и «Кто»: дата до ${r.startDate.bottom}, плашка ${r.warn.y}–${r.warn.bottom}, «Кто» с ${r.who.y}`);
  return bad;
}

module.exports = { verdict, LIMIT };

if (require.main === module) {
  if (!process.argv.includes('--selftest')) { console.error('node Tools/shots/draft_verdict.js --selftest'); process.exit(2); }
  const ok = { state: 'new', genre: { y: 100, bottom: 160 }, startDate: { y: 524, bottom: 580 }, startVal: { y: 560, bottom: 617 }, who: { y: 650, bottom: 710 }, warn: null };
  const warn = { ...ok, state: 'warn', warn: { y: 590, bottom: 640 } };
  let fails = 0;
  const t = (name, row, wantBad) => {
    const got = verdict(row), pass = wantBad ? got.length > 0 : got.length === 0;
    if (!pass) fails++;
    console.log((pass ? 'ok    ' : 'КРАСНОЕ ') + name + (pass ? '' : ' → ' + JSON.stringify(got)));
  };
  t('новая форма — сходится', ok, false);
  t('warn — плашка между датой и «Кто»', warn, false);
  t('время ниже границы — красное', { ...ok, startVal: { y: 800, bottom: 841 } }, true);
  t('время ровно на границе — зелёное', { ...ok, startVal: { y: 800, bottom: LIMIT } }, false);
  t('порядок нарушен — красное', { ...ok, who: { y: 300, bottom: 360 } }, true);
  t('плашка выше даты — красное', { ...warn, warn: { y: 400, bottom: 450 } }, true);
  t('плашка залезла на «Кто» — красное', { ...warn, warn: { y: 600, bottom: 660 } }, true);
  t('warn без плашки — красное, а не молчаливое', { ...warn, warn: null }, true);
  t('нет даты — красное, а не молчаливое', { ...ok, startDate: null }, true);
  t('ask: формы на экране нет — мерить нечего, не нарушение', { state: 'ask', genre: null, startDate: null, startVal: null, who: null, warn: null }, false);
  t('ask: форма вдруг на экране, но порядок нарушен — красное', { ...ok, state: 'ask', who: { y: 300, bottom: 360 } }, true);
  t('continue без рамок — красное, а не молчаливое', { state: 'continue', genre: null, startDate: null, startVal: null, who: null, warn: null }, true);
  console.log(fails ? `КРАСНЫХ: ${fails}` : 'зелёный');
  process.exit(fails ? 1 : 0);
}
