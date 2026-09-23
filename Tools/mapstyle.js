/* Описание холста карты для приложения (итерация 20а): тот же
   `MAPSTYLE.build()` из `beta/mapstyle.js`, что рисует бету, — снятый в JSON.
   Файлы в `LightPlanMapCanvas/Resources/` руками не правятся: меняется веб —
   `make mapstyle` снимает заново. Подписи выключены (так по умолчанию и у
   веба, `mapLabels`); тумблер подписей и язык — итерация 20б.

     node Tools/mapstyle.js          снять оба стиля
     node Tools/mapstyle.js --check  доказать, что снятое совпадает с вебом */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..');
const WEB = process.env.LIGHT_PLAN_WEB || path.resolve(ROOT, '..', 'Light_Plan');
const SRC = path.join(WEB, 'beta', 'mapstyle.js');
const OUT = path.join(ROOT, 'Packages', 'LightPlanUI', 'Sources', 'LightPlanMapCanvas', 'Resources');

const ctx = vm.createContext({ JSON, Math, Object, Array, RegExp, String, Number });
vm.runInContext(fs.readFileSync(SRC, 'utf8') + '\n;this.__S = MAPSTYLE;', ctx, { filename: SRC });
const check = process.argv.includes('--check');
let bad = 0;
for (const dark of [true, false]) {
  const text = JSON.stringify(ctx.__S.build({ dark, labels: false })) + '\n';
  const file = path.join(OUT, dark ? 'style_dark.json' : 'style_light.json');
  if (check) {
    const same = fs.existsSync(file) && fs.readFileSync(file, 'utf8') === text;
    console.log((same ? '  ок  ' : '  РАЗНЫЕ  ') + path.basename(file));
    if (!same) bad++;
  } else {
    fs.writeFileSync(file, text);
    console.log('  ' + path.basename(file) + ' — ' + Buffer.byteLength(text) + ' байт');
  }
}
if (bad) { console.error('стиль разошёлся с бетой: make mapstyle'); process.exit(1); }
