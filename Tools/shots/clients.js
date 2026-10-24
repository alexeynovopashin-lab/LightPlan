#!/usr/bin/env node
/* Шаг К1 «Клиенты»: экран «Клиенты» в обеих темах — «Частные» (все, пары, семьи, персоны), «Компании» и пустой.
   Шаг К4 (`head-msg`, `card-msg`, кнопка «SMS» в `head-couple`/`head-person`): кнопка мессенджера справа от номера в шапке
   съёмки, мессенджеры людей и «Пишем» в карточке клиента (мессенджеры вписывает `seedMessengers` сценария ссылками профиля).
   Шаг К3 (`head-*`, `form-*`): имя клиента в шапке карточки съёмки (по центру, знак «›» справа), карточка клиента из шапки
   («Назад» — в съёмку), плашка клиента в новой форме — по номеру, подсказка по имени, после «Да», у свадьбы.
   Шаг К2: карточка клиента — пара, семья, персона, подсказка «объединить?» (`twin`), лист «С кем объединить» (`pick`),
   черновик «+ Клиент» (`new`): «Назад» и поля 24, вид в карточке совпадает с выбранным, группы людей и строки съёмок во всю
   ширину полей, строк съёмок столько, сколько в итоге «N съёмок», в листе — все клиенты, кроме открытого.
   Шаг К5 (`debts-*`, как в Wallet): вид 1 — карточка самого нового несданного с клиентом, открытая как из календаря, над
   ней краёв нет, остальные долги стопкой внизу экрана (кромки одной ширины, «Ещё несданных: N»); `debts-list` — вид 2,
   все двадцать долгов полосами одной ширины, старый сверху, справа день и просрочка; `few` — две кромки, `done` —
   открытая отмечена «сдана». Мессенджер в шапке.
   Только натив: у веба такого экрана нет (его «Организации» сверяет пара `make shots ARGS="--screens m28 --m28 orgs"`,
   узлы `org.*` остались теми же). Числа — из рамок узлов (`-LPShotReport`): поля 24 pt, строка клиента 64 pt, переключатель
   «Частные | Компании» не наезжает на «Назад» и не выходит за правое поле, фишки внутри полей, сумма по видам равна «Все».
   Засев — `test_seed.json` приложения (24 записи, свадьбы с двумя людьми): клиенты собирает тот же проход, что на телефоне.

     node Tools/shots/clients.js [--skip-build] [--out <dir>] [--cases debts,debts-few]                                                   */
const fs = require('fs'), os = require('os'), path = require('path');
const { execFileSync } = require('child_process');
const sim = require('../sim');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const SEED = path.join(ROOT, 'Packages', 'LightPlanUI', 'Sources', 'LightPlanUI', 'Resources', 'test_seed.json');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : []).filter(x => x.length));
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const BUNDLE = 'Novopashin.LightPlan';

/* sheet — что открыть (`clients` — «Частные», `orgs` — «Компании»); way — фильтр или `empty`. */
const CASES = [
  { name: 'all', sheet: 'clients', way: 'all' },
  { name: 'couples', sheet: 'clients', way: 'couples' },
  { name: 'families', sheet: 'clients', way: 'families' },
  { name: 'persons', sheet: 'clients', way: 'persons' },
  { name: 'companies', sheet: 'orgs' },
  { name: 'empty', sheet: 'clients', way: 'empty' },
  { name: 'card-couple', sheet: 'clientcard', way: 'couple', card: 'couple' },
  { name: 'card-family', sheet: 'clientcard', way: 'family', card: 'family' },
  { name: 'card-person', sheet: 'clientcard', way: 'person', card: 'person' },
  { name: 'card-twin', sheet: 'clientcard', way: 'twin', card: 'person' },
  { name: 'card-pick', sheet: 'clientcard', way: 'pick', card: 'couple' },
  { name: 'card-new', sheet: 'clientcard', way: 'new', card: 'person' },
  // К4: мессенджеры людей, кнопка «написать» у телефона, «Пишем».
  { name: 'card-msg', sheet: 'clientcard', way: 'couple+msg', card: 'couple', msg: true },
  // К6: дни рождения людей, годовщина пары из свадьбы, «Поздравлять».
  { name: 'card-greet', sheet: 'clientcard', way: 'couple+greet', card: 'couple', greet: true },
  { name: 'card-greet-person', sheet: 'clientcard', way: 'person+greet', card: 'person', greet: true },
  // К7: часть «Контакты» под «Семьями» (две строки — тумблер виден без прокрутки): вопрос о прошлых, всё записано, «Нет»,
  // частичный доступ, тестовая сборка.
  { name: 'contacts-past', sheet: 'clients', way: 'families', contacts: 'past' },
  { name: 'contacts-on', sheet: 'clients', way: 'families', contacts: 'on' },
  { name: 'contacts-no', sheet: 'clients', way: 'families', contacts: 'no' },
  { name: 'contacts-limited', sheet: 'clients', way: 'families', contacts: 'limited' },
  { name: 'contacts-test', sheet: 'clients', way: 'families', contacts: 'test' },
  // К3: входы из съёмки.
  { name: 'head-couple', sheet: 'clienthead', way: 'couple', reach: 'sms' },
  { name: 'head-person', sheet: 'clienthead', way: 'person', reach: 'sms' },
  { name: 'head-msg', sheet: 'clienthead', way: 'couple+msg', reach: 'telegram' },
  { name: 'head-open', sheet: 'clienthead', way: 'couple+open', card: 'couple' },
  { name: 'form-phone', sheet: 'clientform', way: 'phone', plate: 'phone' },
  { name: 'form-name', sheet: 'clientform', way: 'name', plate: 'name' },
  { name: 'form-yes', sheet: 'clientform', way: 'yes', plate: 'bound' },
  { name: 'form-couple', sheet: 'clientform', way: 'couple', plate: 'phone' },
  // К5: стопка долгов как в Wallet. pile — сколько долгов в стопке внизу (кромок не больше трёх), list — вид 2.
  { name: 'debts', sheet: 'debts', way: 'many+msg', pile: 19, reach: 'telegram' },
  { name: 'debts-list', sheet: 'debts', way: 'many+msg+list', list: 20 },
  { name: 'debts-few', sheet: 'debts', way: 'few+msg', pile: 2, reach: 'telegram' },
  { name: 'debts-done', sheet: 'debts', way: 'many+done+msg', pile: 19, reach: 'telegram', delivered: true },
];

const num = t => parseInt(t, 10);

const KINDS = ['couple', 'family', 'person'];

/* Карточка клиента (К2). */
function cardVerdict(c, nodes, screen) {
  const bad = [], n = k => { if (!nodes[k]) bad.push('нет узла ' + k); return nodes[k]; };
  const inFields = (r, what) => { if (r && (Math.abs(r.x - 24) > 0.6 || Math.abs(r.w - (screen.w - 48)) > 0.6)) bad.push(`${what}: x=${r.x.toFixed(1)} w=${r.w.toFixed(1)}`); };
  if (c.way === 'pick') {
    const pk = n('clc.picker');
    if (pk && num(pk.text) < 1) bad.push('в листе «С кем объединить» никого');
    for (let i = 0; i < Math.min(pk ? num(pk.text) : 0, 4); i++) {
      const r = n('clc.pick.' + i);
      if (r && Math.abs(r.h - 64) > 0.6) bad.push(`строка листа ${i}: высота ${r.h.toFixed(1)}`);
    }
    return bad;
  }
  const back = n('clc.back'), card = n('clc.card');
  if (back && Math.abs(back.x - 24) > 0.6) bad.push(`«Назад» не на поле 24: x=${back.x.toFixed(1)}`);
  if (card && card.text !== c.card) bad.push(`вид карточки ${card.text}, ждали ${c.card}`);
  n('clc.title');
  inFields(n('clc.kinds'), 'вид «Пара | Семья | Персона»');
  for (let i = 0; i < 3; i++) n('clc.kind.' + i);
  inFields(n('clc.person.0'), 'человек 1');
  const total = n('clc.total'), shoots = total ? (parseInt(total.text, 10) || 0) : 0;
  let rows = 0;
  while (nodes['clc.shoot.' + rows]) { inFields(nodes['clc.shoot.' + rows], 'съёмка ' + rows); if (Math.abs(nodes['clc.shoot.' + rows].h - 64) > 0.6) bad.push(`съёмка ${rows}: высота ≠ 64`); rows++; }
  if (rows !== shoots) bad.push(`строк съёмок ${rows}, а в итоге «${total && total.text}»`);
  if (c.way === 'new') {
    if (rows) bad.push('у черновика есть съёмки');
    if (nodes['clc.merge']) bad.push('у черновика есть «Объединить»');
    n('clc.linksEmpty');
  } else {
    if (!(rows > 0)) bad.push('у клиента из засева нет съёмок');
    n('clc.merge');
  }
  if (c.way === 'twin') inFields(n('clc.twin.0'), 'подсказка «объединить?»');
  if (c.card === 'couple' && c.way !== 'new') inFields(n('clc.person.1'), 'человек 2');
  n('clc.delete');
  if (c.greet) {
    // Строка дня рождения — внутри группы своего человека, 52 и выше; у первого с годом — возраст; группа праздников в полях;
    // у пары — годовщина из свадьбы; тумблер включён.
    const people = c.card === 'couple' ? [0, 1] : [0];
    for (const i of people) {
      const g = nodes['clc.person.' + i], r = n('clc.bday.' + i), v = n('clc.bdayValue.' + i);
      if (r && g && (r.y < g.y - 0.1 || r.y + r.h > g.y + g.h + 0.1)) bad.push(`день рождения ${i + 1} вне группы человека`);
      if (r && r.h < 51.4) bad.push(`день рождения ${i + 1}: высота ${r.h.toFixed(1)} < 52`);
      if (v && !v.text) bad.push(`день рождения ${i + 1} не вписан`);
    }
    if (!nodes['clc.bday.0.sub']) bad.push('у дня рождения с годом нет возраста');
    if (c.card === 'couple' && nodes['clc.bday.1.sub']) bad.push('у дня рождения без года есть возраст');
    inFields(n('clc.greetGroup'), 'группа праздников');
    const t = n('clc.greet');
    if (c.card === 'couple') {
      const a = n('clc.anniv'), av = n('clc.annivValue');
      if (av && !/^\d{4}-\d{2}-\d{2}$/.test(av.text)) bad.push(`годовщина «${av.text}» не из свадьбы`);
      if (a && t && a.y > t.y) bad.push('годовщина ниже тумблера');
      n('clc.anniv.sub');
    } else if (nodes['clc.anniv']) bad.push('у персоны строка годовщины');
    n('clc.greetNote');
  }
  if (c.msg) {
    // Вставленные ссылками профили стали строками своих видов, внутри группы человека; звёздочка — у первого
    // вписанного; кнопка у телефона открывает основной; «Пишем» — оба человека.
    const rowsOf = { 0: ['telegram', 'vk'], 1: ['whatsapp', 'instagram'] };
    for (const i of [0, 1]) {
      const g = nodes['clc.person.' + i];
      for (const k of rowsOf[i]) {
        const r = n(`clc.msg.${i}.${k}`);
        if (r && g && (r.x < g.x - 0.1 || r.x + r.w > g.x + g.w + 0.1 || r.y < g.y - 0.1 || r.y + r.h > g.y + g.h + 0.1)) bad.push(`строка ${k} вне группы человека ${i + 1}`);
        if (r && Math.abs(r.h - 48) > 0.6) bad.push(`строка ${k}: высота ${r.h.toFixed(1)} ≠ 48`);
      }
      const star = n(`clc.msgMain.${i}.${rowsOf[i][0]}`);
      if (star && star.text !== 'on') bad.push(`звёздочка не у ${rowsOf[i][0]}`);
      const reach = n('clc.reach.' + i);
      if (reach && reach.text !== rowsOf[i][0]) bad.push(`кнопка человека ${i + 1} открывает «${reach.text}», ждали ${rowsOf[i][0]}`);
      if (reach && Math.abs(reach.w - 48) > 0.6) bad.push(`кнопка человека ${i + 1}: ширина ${reach.w.toFixed(1)}`);
      n('clc.addMsg.' + i);
    }
    inFields(n('clc.writeTo'), '«Пишем»');
    n('clc.writer.0'); n('clc.writer.1');
  }
  return bad;
}

/* Шапка карточки съёмки (К3): имя по центру, как у веба, знак «›» справа от него и в экране; из шапки — карточка клиента
   поверх съёмки, «Назад» ведёт в неё. */
function headVerdict(c, nodes, screen) {
  const bad = [], n = k => { if (!nodes[k]) bad.push('нет узла ' + k); return nodes[k]; };
  if (c.way.includes('open')) {
    const back = n('clc.back'), card = n('clc.card');
    if (back && back.text !== 'Назад') bad.push(`«Назад» подписан «${back.text}»`);
    if (back && Math.abs(back.x - 24) > 0.6) bad.push(`«Назад» не на поле 24: x=${back.x.toFixed(1)}`);
    if (card && card.text !== c.card) bad.push(`вид карточки ${card.text}, ждали ${c.card}`);
    return bad;
  }
  const link = n('card.client'), name = n('card.name'), go = n('card.nameGo');
  if (c.reach) {
    // К4: кнопка мессенджера справа от номера, на его высоте; строка «номер + кнопка» по центру экрана, в полях 16.
    const tel = n('card.tel'), reach = n('card.reach');
    if (reach && reach.text !== c.reach) bad.push(`кнопка открывает «${reach.text}», ждали ${c.reach}`);
    if (tel && reach) {
      if (reach.x < tel.x + tel.w - 0.1) bad.push('кнопка наезжает на номер');
      if (Math.abs(reach.y + reach.h / 2 - (tel.y + tel.h / 2)) > 1) bad.push('кнопка не на высоте номера');
      const mid = (tel.x + reach.x + reach.w) / 2;
      if (Math.abs(mid - screen.w / 2) > 1) bad.push(`номер с кнопкой не по центру: ${mid.toFixed(1)} при ${screen.w / 2}`);
      if (tel.x < 16 || reach.x + reach.w > screen.w - 16) bad.push('номер с кнопкой выходят за поля 16');
    }
  }
  if (link && !link.text) bad.push('у входа нет ключа клиента');
  if (name && Math.abs(name.x + name.w / 2 - screen.w / 2) > 1) bad.push(`имя не по центру: ${(name.x + name.w / 2).toFixed(1)} при ${screen.w / 2}`);
  if (name && go) {
    if (go.x < name.x + name.w - 0.1) bad.push('знак «›» наезжает на имя');
    if (go.x + go.w > screen.w - 16) bad.push(`знак «›» у края экрана: ${(go.x + go.w).toFixed(1)}`);
    if (Math.abs(go.y + go.h / 2 - (name.y + name.h / 2)) > 3) bad.push('знак «›» не на высоте имени');
  }
  return bad;
}

/* Плашка клиента в форме (К3): вид плашки тот, что ждали; «Да» — только у подсказки по имени, «Другой» — у подсказки и у
   выбранного, у «по номеру» кнопок нет; плашка во всю ширину группы «Клиент». */
function formVerdict(c, nodes) {
  const bad = [], n = k => { if (!nodes[k]) bad.push('нет узла ' + k); return nodes[k]; };
  const plate = n('form.client'), who = n('form.who'), text = n('form.clientText');
  if (plate && plate.text !== c.plate) bad.push(`плашка «${plate.text}», ждали «${c.plate}»`);
  if (plate && who && (Math.abs(plate.x - who.x) > 0.6 || Math.abs(plate.w - who.w) > 0.6)) bad.push(`плашка не во всю группу: x=${plate.x.toFixed(1)} w=${plate.w.toFixed(1)}`);
  if (plate && who && (plate.y < who.y - 0.1 || plate.y + plate.h > who.y + who.h + 0.1)) bad.push('плашка вне группы «Клиент»');
  const yes = !!nodes['form.clientYes'], other = !!nodes['form.clientOther'];
  if (yes !== (c.plate === 'name')) bad.push(yes ? '«Да» не у подсказки' : 'нет «Да»');
  if (other !== (c.plate !== 'phone')) bad.push(other ? '«Другой» у плашки «по номеру»' : 'нет «Другой»');
  const word = { phone: 'По номеру — ', name: 'Это ', bound: 'Это ' }[c.plate];
  if (text && !text.text.startsWith(word)) bad.push(`текст «${text.text}»`);
  if (text && (c.plate === 'name') !== text.text.includes('?')) bad.push(`вопрос не там: «${text.text}»`);
  return bad;
}

/* Стопка долгов (К5, Wallet). Вид 1: над листом краёв нет; стопка внизу экрана — кромок min(3, N) одной ширины (поля
   24), каждая на 8 ниже, счёт N; стопка под листом шапки и у нижнего края; кнопка мессенджера; у `done` — «сдан».
   Вид 2: полос столько, сколько долгов, все одной ширины в полях 24, шаг 52, справа у каждой день (не часы), дни
   по порядку — старый сверху. */
const MON = { янв: 1, фев: 2, мар: 3, апр: 4, мая: 5, май: 5, июн: 6, июл: 7, авг: 8, сен: 9, окт: 10, ноя: 11, дек: 12 };
const dayKey = t => { const m = /^(\d+) ([а-я]+)/.exec(t); return m ? (MON[m[2].slice(0, 3)] || 0) * 100 + num(m[1]) : NaN; };
function debtsVerdict(c, nodes, screen) {
  const bad = [], n = k => { if (!nodes[k]) bad.push('нет узла ' + k); return nodes[k]; };
  const wide = (r, what) => { if (r && (Math.abs(r.x - 24) > 0.6 || Math.abs(r.w - (screen.w - 48)) > 0.6)) bad.push(`${what}: x=${r.x.toFixed(1)} w=${r.w.toFixed(1)}`); };
  if (c.list) {
    const list = n('debts.list'), title = n('debts.title');
    if (list && num(list.text) !== c.list) bad.push(`в списке ${list.text}, ждали ${c.list}`);
    if (title && num(title.text) !== c.list) bad.push(`заголовок ${title.text}`);
    if (nodes['debts.band.' + c.list]) bad.push(`полос больше ${c.list}`);
    let prev = -1;
    for (let k = 0; k < c.list; k++) {
      const b = n('debts.band.' + k), t = nodes['debts.bandTime.' + k];
      wide(b, 'полоса ' + k);
      const a = nodes['debts.band.' + (k - 1)];
      if (b && a && Math.abs(b.y - a.y - 52) > 0.6) bad.push(`полоса ${k} не на 52 ниже: ${(b.y - a.y).toFixed(1)}`);
      if (!t) { bad.push('нет узла debts.bandTime.' + k); continue; }
      if (/\d:\d/.test(t.text)) bad.push(`полоса ${k} пишет часы «${t.text}»`);
      const d = dayKey(t.text);
      if (!(d >= prev)) bad.push(`полоса ${k} «${t.text}» раньше предыдущей`);
      prev = d;
    }
    return bad;
  }
  if (nodes['card.peek.0']) bad.push('над листом есть края');
  const pile = n('card.debtsPile'), more = n('card.debtsMore');
  if (pile && num(pile.text) !== c.pile) bad.push(`в стопке ${pile.text}, ждали ${c.pile}`);
  if (more && num(more.text) !== c.pile) bad.push(`строка счёта ${more.text}`);
  const m = Math.min(3, c.pile);
  if (nodes['card.pile.' + m]) bad.push(`кромок больше ${m}`);
  for (let k = 0; k < m; k++) {
    const p = n('card.pile.' + k), a = nodes['card.pile.' + (k - 1)];
    wide(p, 'кромка ' + k);
    if (p && a && Math.abs(p.y + p.h - a.y - a.h - 8) > 0.6) bad.push(`кромка ${k} не на 8 ниже: ${(p.y + p.h - a.y - a.h).toFixed(1)}`);
  }
  // `size` в отчёте — без полос системы; низ экрана в точках — по ширине кадра (у Pro Max ×3).
  if (pile && (pile.y + pile.h > screen.full + 0.1 || pile.y + pile.h < screen.full - 60)) bad.push(`стопка не у нижнего края: низ ${(pile.y + pile.h).toFixed(1)} при ${screen.full}`);
  const reach = n('card.reach'), name = n('card.name');
  if (reach && reach.text !== c.reach) bad.push(`кнопка открывает «${reach.text}», ждали ${c.reach}`);
  if (name && pile && name.y + name.h > pile.y) bad.push('имя карточки под стопкой');
  const dv = n('card.deliveryText');
  if (dv && !!c.delivered !== /^сдан/i.test(dv.text)) bad.push(`сдача «${dv.text}»`);
  return bad;
}

/* К7: что видно в части «Контакты» по виду; всё в полях 24 и на экране. */
function contactsVerdict(c, nodes, screen) {
  const bad = [], n = k => { if (!nodes[k]) bad.push('нет узла ' + k); return nodes[k]; };
  const no = k => { if (nodes[k]) bad.push('лишний узел ' + k); };
  const part = n('clk.part');
  if (part && (part.x < 23.9 || part.x + part.w > screen.w - 23.9)) bad.push('часть «Контакты» вне полей');
  if (part && part.y + part.h > screen.h) bad.push(`часть «Контакты» ниже экрана: ${(part.y + part.h).toFixed(1)} > ${screen.h}`);
  const tog = nodes['clk.toggle'];
  if (c.contacts === 'test') { no('clk.toggle'); no('clk.remove'); n('clk.testBuild'); return bad; }
  n('clk.toggle'); n('clk.note');
  const on = { past: 'on', on: 'on', no: 'on', limited: 'off' }[c.contacts];
  if (tog && tog.text !== on) bad.push(`тумблер ${tog.text}, ждали ${on}`);
  if (c.contacts === 'past') { const p = n('clk.past'); n('clk.pastYes'); n('clk.pastNo'); if (p && !(num(p.text) > 0)) bad.push('в вопросе нет числа'); no('clk.remove'); }
  else no('clk.past');
  if (c.contacts === 'on') n('clk.remove');
  if (c.contacts === 'no') n('clk.pastAgain'); else no('clk.pastAgain');
  if (c.contacts === 'limited') { const t = nodes['clk.note']; if (t && !/части контактов/.test(t.text)) bad.push('подпись не про частичный доступ'); no('clk.remove'); }
  return bad;
}

function verdict(c, nodes, screen) {
  if (c.sheet === 'debts') return debtsVerdict(c, nodes, screen);
  if (c.sheet === 'clienthead') return headVerdict(c, nodes, screen);
  if (c.sheet === 'clientform') return formVerdict(c, nodes);
  if (c.sheet === 'clientcard') return cardVerdict(c, nodes, screen);
  if (c.contacts) return contactsVerdict(c, nodes, screen);
  const bad = [], n = k => { if (!nodes[k]) bad.push('нет узла ' + k); return nodes[k]; };
  const back = n('org.back');
  if (back && Math.abs(back.x - 24) > 0.6) bad.push(`«Назад» не на поле 24: x=${back.x.toFixed(1)}`);
  if (c.sheet === 'orgs') { n('org.list'); n('cl.tabs'); }
  else {
    const tabs = n('cl.tabs');
    if (tabs && back) {
      if (tabs.x < back.x + back.w + 8 - 0.1) bad.push(`переключатель наезжает на «Назад»: ${tabs.x.toFixed(1)} < ${(back.x + back.w + 8).toFixed(1)}`);
      if (tabs.x + tabs.w > screen.w - 23.9) bad.push(`переключатель выходит за правое поле: ${(tabs.x + tabs.w).toFixed(1)}`);
      if (Math.abs(tabs.y + tabs.h / 2 - (back.y + back.h / 2)) > 6) bad.push('переключатель и «Назад» на разной высоте');
    }
    const chips = n('cl.chips');
    if (chips && (chips.x < 23.9 || chips.x + chips.w > screen.w - 23.9)) bad.push('фишки вне полей');
    if (c.way === 'empty') n('cl.empty');
    else {
      const list = n('cl.list'), count = list ? num(list.text) : 0;
      if (list && !(count > 0) && c.way === 'all') bad.push('в «Все» нет ни одной строки');
      for (let i = 0; i < Math.min(count, 5); i++) {
        const r = n('cl.row.' + i);
        if (!r) continue;
        if (Math.abs(r.x - 24) > 0.6 || Math.abs(r.w - (screen.w - 48)) > 0.6) bad.push(`строка ${i}: x=${r.x.toFixed(1)} w=${r.w.toFixed(1)}`);
        if (Math.abs(r.h - 64) > 0.6) bad.push(`строка ${i}: высота ${r.h.toFixed(1)} ≠ 64`);
      }
    }
  }
  return bad;
}

(async () => {
  const OUT = path.resolve(args.out || path.join(os.tmpdir(), 'lp-shots', 'clients'));
  fs.mkdirSync(OUT, { recursive: true });
  const dd = path.join(OUT, 'DerivedData');
  const dev = sim.device(ROOT);
  try { run('xcrun', ['simctl', 'boot', dev.udid], { stdio: 'ignore' }); } catch (e) {}
  if (!args['skip-build']) {
    const log = path.join(OUT, 'xcodebuild-clients.log');
    try {
      run('xcodebuild', ['-project', path.join(ROOT, 'LightPlan.xcodeproj'), '-scheme', 'LightPlan-iOS', '-configuration', 'Debug',
        '-destination', 'platform=iOS Simulator,id=' + dev.udid, '-derivedDataPath', dd, 'build'], { stdio: ['ignore', fs.openSync(log, 'w'), fs.openSync(log, 'a')] });
    } catch (e) { throw new Error('сборка упала: ' + log); }
  }
  const products = path.join(dd, 'Build', 'Products', 'Debug-iphonesimulator');
  const app = path.join(products, fs.readdirSync(products).find(f => f.endsWith('.app')));
  run('xcrun', ['simctl', 'bootstatus', dev.udid, '-b'], { stdio: 'ignore' });
  run('xcrun', ['simctl', 'install', dev.udid, app]);

  const rows = [];
  for (const theme of ['dark', 'light']) {
    run('xcrun', ['simctl', 'ui', dev.udid, 'appearance', theme]);
    const only = typeof args.cases === 'string' ? args.cases.split(',') : null;
    for (const c of CASES.filter(c => !only || only.includes(c.name))) {
      const dir = path.join(OUT, 'clients-' + c.name + '-' + theme);
      fs.mkdirSync(dir, { recursive: true });
      const report = path.join(dir, 'native.json');
      const seedFile = path.join(dir, 'seed.json');
      fs.writeFileSync(seedFile, JSON.stringify({ ...JSON.parse(fs.readFileSync(SEED, 'utf8')), theme }));
      fs.rmSync(report, { force: true });
      try { run('xcrun', ['simctl', 'terminate', dev.udid, BUNDLE], { stdio: 'ignore', timeout: 10000 }); } catch (e) {}
      run('xcrun', ['simctl', 'launch', dev.udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
        '-LPShotNow', '2026-10-23T12:00:00+07:00', '-LPShotZone', 'Asia/Tomsk', '-LPShotSeed', seedFile,
        '-LPShotForecast', path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', path.join(FX, 'air_barnaul.json'),
        '-LPShotName', path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'planner', '-LPShotScope', 'month',
        '-LPShotSheet', c.sheet, ...(c.way ? ['-LPShotWay', c.way] : []), ...(c.contacts ? ['-LPShotContacts', c.contacts] : []), '-LPShotReportDelay', '4', '-LPShotReport', report]);
      for (let i = 0; i < 240 && !fs.existsSync(report); i++) await sleep(250);
      if (!fs.existsSync(report)) throw new Error('нет рамок: ' + dir);
      await sleep(1200);
      run('xcrun', ['simctl', 'io', dev.udid, 'screenshot', '--type=png', path.join(dir, 'native.png')], { stdio: 'ignore' });
      const rep = JSON.parse(fs.readFileSync(report, 'utf8'));
      const nodes = rep.nodes || {};
      // Размер экрана — `size` [w, h]; `screen` в отчёте — имя вкладки (до К3 ширина тут была NaN, и проверки ширины молчали).
      const png = fs.readFileSync(path.join(dir, 'native.png'));
      const screen = { w: rep.size[0], h: rep.size[1], full: png.readUInt32BE(20) * rep.size[0] / png.readUInt32BE(16) };
      const bad = verdict(c, nodes, screen);
      const list = nodes['clc.picker'] || nodes['cl.list'] || nodes['org.list'] || nodes['debts.list'] || nodes['card.debtsPile'];
      rows.push({ shot: c.name + '_' + theme, c: c.name, theme, bad, count: list ? num(list.text) : null });
    }
  }
  // Виды делят «Все» без остатка: пары + семьи + персоны = все.
  for (const theme of ['dark', 'light']) {
    if (!rows.some(r => r.c === 'all' && r.theme === theme)) continue;
    const get = n => (rows.find(r => r.c === n && r.theme === theme) || {}).count;
    const all = get('all'), sum = get('couples') + get('families') + get('persons');
    if (all !== sum) rows.find(r => r.c === 'all' && r.theme === theme).bad.push(`виды (${sum}) не равны «Все» (${all})`);
    // В листе «С кем объединить» — все, кроме открытого.
    const pick = get('card-pick');
    if (pick !== all - 1) rows.find(r => r.c === 'card-pick' && r.theme === theme).bad.push(`в листе ${pick}, ждали ${all - 1}`);
  }
  fs.writeFileSync(path.join(OUT, 'clients-report.json'), JSON.stringify(rows, null, 1));
  for (const r of rows) console.log(r.shot + ': ' + (r.bad.length ? 'НАРУШЕНИЯ ' + r.bad.join('; ') : 'ок') + (r.count != null ? '  строк ' + r.count : ''));
  console.log('→ ' + OUT);
  const fails = rows.flatMap(r => r.bad.map(m => `${r.shot}: ${m}`));
  if (fails.length) throw new Error('клиенты: ' + fails.length + ' нарушений:\n' + fails.join('\n'));
})().catch(e => { console.error(e.message); process.exit(1); });
