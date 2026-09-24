#!/usr/bin/env node
/* Свой симулятор у каждой ветки (итерация 21а). Две итерации параллельно
   снимали пары на одном iPhone 17 Pro Max — прогоны сбивали друг друга
   (20б и 21): один ставил сборку и тему, пока второй ждал рамки.

   Имя — по ветке: `LP wt-21a`, `LP main`. Создаётся при первом запуске той
   же модели и той же iOS, что iPhone 17 Pro Max (`simctl create`, а не
   `clone`: клон требует выключить исходник, а им пользуются — PWA Алексея,
   чужой прогон). Экран тот же, 440 × 956, — пары сопоставимы с прежними.
   Своё имя — переменной `LP_SIM` (любой существующий или новый).

   Модулем: `const sim = require('./sim'); const dev = sim.device(root);`
   Командой:  node Tools/sim.js           — какой симулятор у этой ветки
              node Tools/sim.js --prune   — удалить `LP …` веток, которых нет */
const path = require('path');
const { execFileSync } = require('child_process');

const BASE = 'iPhone 17 Pro Max';
const PREFIX = 'LP ';
const run = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { encoding: 'utf8', ...opts });

function branch(root) {
  try { return run('git', ['-C', root, 'rev-parse', '--abbrev-ref', 'HEAD']).trim(); } catch (e) { return 'main'; }
}

/* `wt/21a` → `LP wt-21a`: косая черта в имени симулятора мешает только
   глазам, но и её убираем. */
function nameFor(root) {
  if (process.env.LP_SIM) return process.env.LP_SIM;
  return PREFIX + branch(root).replace(/[^A-Za-z0-9._-]+/g, '-');
}

function all() {
  const out = [];
  const lists = JSON.parse(run('xcrun', ['simctl', 'list', 'devices', 'available', '-j'])).devices;
  for (const [runtime, list] of Object.entries(lists)) for (const d of list) out.push({ ...d, runtime });
  return out;
}

/* Симулятор ветки: есть — берём, нет — создаём по образцу базового;
   выключен — загружаем. Возвращает `{ name, udid, state, runtime }`. */
function device(root, { boot = true } = {}) {
  const name = nameFor(root);
  let dev = all().find(d => d.name === name);
  if (!dev) {
    const base = all().filter(d => d.name === BASE).sort((a, b) => b.runtime.localeCompare(a.runtime))[0];
    if (!base) throw new Error('нет образца ' + BASE + ' — не из чего создать ' + name);
    const udid = run('xcrun', ['simctl', 'create', name, base.deviceTypeIdentifier, base.runtime]).trim();
    console.log(`создан симулятор «${name}» (${base.runtime.split('.').pop()}, ${udid.slice(0, 8)})`);
    dev = all().find(d => d.udid === udid);
  }
  if (boot && dev.state !== 'Booted') {
    run('xcrun', ['simctl', 'boot', dev.udid]);
    run('xcrun', ['simctl', 'bootstatus', dev.udid, '-b'], { stdio: 'ignore' });
    dev = { ...dev, state: 'Booted' };
  }
  return dev;
}

/* Симуляторы `LP …`, чьей ветки больше нет в этом репозитории. */
function stale(root) {
  const branches = new Set(run('git', ['-C', root, 'for-each-ref', '--format=%(refname:short)', 'refs/heads'])
    .split('\n').filter(Boolean).map(b => PREFIX + b.replace(/[^A-Za-z0-9._-]+/g, '-')));
  return all().filter(d => d.name.startsWith(PREFIX) && !branches.has(d.name));
}

module.exports = { device, nameFor, stale };

if (require.main === module) {
  const root = path.resolve(__dirname, '..');
  if (process.argv.includes('--prune')) {
    const old = stale(root);
    for (const d of old) {
      try { run('xcrun', ['simctl', 'shutdown', d.udid], { stdio: 'ignore' }); } catch (e) {}
      run('xcrun', ['simctl', 'delete', d.udid]);
      console.log('удалён ' + d.name);
    }
    if (!old.length) console.log('лишних нет');
  } else {
    const d = device(root, { boot: false });
    console.log(`${d.name} · ${d.state} · ${d.udid}`);
  }
}
