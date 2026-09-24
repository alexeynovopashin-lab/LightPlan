#!/usr/bin/env node
/* Засев пар «Съёмок» (итерация 21): посев сезона беты при прибитых часах.

   Планировщик без записей пуст, а базовый `Fixtures/shots/seed.json` записей
   не держит. Своих записей здесь нет: страница `beta/_seed_season.html`
   (те же правила, что у кнопки «Тестовый посев») открывается в
   headless-браузере с часами, стоящими на моменте пар, жмётся «Засеять», и
   из хранилища берутся записи, занятость, организации, студии и точки. Даты
   посева считаются от «сегодня», поэтому часы прибиты — файл повторяется.

   Запуск (из корня натива): node Tools/shots/planner_seed.js
   → Fixtures/shots/seed_planner.json (база `seed.json` + данные посева).
   Из worktree: LIGHT_PLAN_WEB=<путь к Light_Plan>. */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const FX = path.join(ROOT, 'Fixtures', 'shots');
const ZONE = 'Asia/Barnaul';
const AT = '2026-09-23T13:00:00+07:00';
const KEYS = ['sessions', 'blocks', 'orgs', 'studios', 'spots'];

function webRoot() {
  if (process.env.LIGHT_PLAN_WEB) return path.resolve(process.env.LIGHT_PLAN_WEB);
  let dir = ROOT;
  for (let i = 0; i < 8; i++) {
    const c = path.join(dir, 'Light_Plan');
    if (fs.existsSync(path.join(c, 'beta', 'seed.js'))) return c;
    dir = path.dirname(dir);
  }
  throw new Error('не нашёл Light_Plan; задай LIGHT_PLAN_WEB');
}
const WEB = webRoot();
function playwright() {
  for (let dir = WEB; dir !== path.dirname(dir); dir = path.dirname(dir)) {
    const p = path.join(dir, 'node_modules', 'playwright');
    if (fs.existsSync(p)) return require(p);
  }
  throw new Error('не нашёл playwright рядом с ' + WEB);
}

(async () => {
  const beta = path.join(WEB, 'beta');
  const { chromium } = playwright();
  const browser = await chromium.launch();
  const context = await browser.newContext({ timezoneId: ZONE, locale: 'ru-RU' });
  // Страница с диска под своим адресом: у file:// нет localStorage, сеть закрыта.
  await context.route(/^https?:/, route => {
    const url = new URL(route.request().url());
    if (url.host !== 'lp.test') return route.abort();
    const file = path.join(beta, decodeURIComponent(url.pathname));
    if (!file.startsWith(beta) || !fs.existsSync(file)) return route.fulfill({ status: 404, body: '' });
    return route.fulfill({ status: 200, body: fs.readFileSync(file),
      contentType: file.endsWith('.html') ? 'text/html' : 'text/javascript' });
  });
  const page = await context.newPage();
  await page.clock.install({ time: new Date(AT) });
  await page.goto('http://lp.test/_seed_season.html');
  await page.click('#go');
  await page.waitForTimeout(300);
  const stored = JSON.parse(await page.evaluate(() => localStorage.getItem('lightplan.beta.v1')));
  await browser.close();

  const base = JSON.parse(fs.readFileSync(path.join(FX, 'seed.json'), 'utf8'));
  const out = { ...base };
  for (const k of KEYS) out[k] = stored[k] || [];
  // Время правки записи — часы страницы: прибиты, но вписаны явно, чтобы файл
  // не зависел от того, сколько миллисекунд шёл посев.
  for (const k of KEYS) for (const r of out[k]) if (r && typeof r.mt === 'number') r.mt = Date.parse(AT);
  const file = path.join(FX, 'seed_planner.json');
  fs.writeFileSync(file, JSON.stringify(out, null, 1) + '\n');
  console.log(file + ': ' + KEYS.map(k => k + ' ' + out[k].length).join(', '));
})().catch(e => { console.error(String(e && e.stack || e)); process.exit(1); });
