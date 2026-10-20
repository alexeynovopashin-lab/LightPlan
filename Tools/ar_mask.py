#!/usr/bin/env python3
"""Шаг 29.8в.18: затемняющая маска над кадром камеры — замер яркости до и после, подбор потолка непрозрачности.

Кадр камеры — отладочный «город» (`-LPSunARBackdrop city`): светлое дневное небо и силуэт зданий (тёмные блоки). Сценарий —
«сейчас» день, выбрана ночь, включены звёзды и созвездия: маска на полную силу. Непрозрачность подставляется
(`-LPSunARMask <v>`, отладка), остальное не меняется. По снимку симулятора, в областях из отчёта приложения
(`ar.city.sky`, `ar.city.building`), считается:

  * яркость неба и зданий — медиана «кода» (то, что пишет в пиксель экран, Rec. 709 по гамма-значениям) и линейная
    яркость Y; остаток = после / до маски;
  * разница небо − здание в кодах: по ней контуры зданий угадываются (то же, что граница силуэта на настоящем кадре);
  * контраст светлейшей точки полосы неба над крышами (звезда или линия созвездия, самый светлый пиксель) к медиане полосы, WCAG
    (L1 + 0,05) / (L2 + 0,05): звезда должна читаться поверх светлого неба; без маски на светлом небе она теряется.

    python3 Tools/ar_mask.py [--app <.app>] [--opacities 0,0.5,0.6,0.65,0.7,0.75,0.8] [--out DIR] [--edge-min 40] [--star-min 10]

Цели (`--edge-min`, `--star-min`, выбраны автором шага, не стандарт): разница небо − здание не меньше 40 кодов из 255 (шестая часть
шкалы — контур здания угадывается), контраст светлейшей точки не меньше 10 : 1. Печатает таблицу; потолок — непрозрачность, на которой хуже выполненная из двух целей выполнена лучше всего,
при остатке неба в кодах не меньше четверти. Код 1, если и она не дотягивает до 80 % цели.
"""
import argparse, json, os, re, subprocess, sys, tempfile, time
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, 'Fixtures', 'shots')
BUNDLE = 'Novopashin.LightPlan'


def sh(*a, **k):
    return subprocess.run(a, check=True, capture_output=True, text=True, **k).stdout


def sim_udid():
    out = subprocess.run(['node', os.path.join(ROOT, 'Tools', 'sim.js')], capture_output=True, text=True, cwd=ROOT).stdout
    m = re.search(r'([0-9A-F]{8}-[0-9A-F-]{27})', out)
    if not m:
        sys.exit('нет симулятора ветки: make sims')
    return m.group(1)


def lin(v):
    v /= 255
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def code(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def Y(c):
    return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])


def region(img, f, scale):
    x, y, w, h = [int(round(v * scale)) for v in (f['x'], f['y'], f['w'], f['h'])]
    return list(img.crop((x, y, x + max(w, 1), y + max(h, 1))).convert('RGB').getdata())


def median(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2]


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(q * (len(xs) - 1)))]


def shoot(udid, v, out):
    report = os.path.join(out, f'mask_{v}.json')
    png = os.path.join(out, f'mask_{v}.png')
    if os.path.exists(report):
        os.remove(report)
    subprocess.run(['xcrun', 'simctl', 'terminate', udid, BUNDLE], capture_output=True)
    sh('xcrun', 'simctl', 'launch', udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
       '-LPShotNow', '2026-10-14T12:00:00+07:00', '-LPShotZone', 'Asia/Tomsk', '-LPShotSeed', os.path.join(FX, 'seed.json'),
       '-LPShotForecast', os.path.join(FX, 'forecast_barnaul.json'), '-LPShotAir', os.path.join(FX, 'air_barnaul.json'),
       '-LPShotName', os.path.join(FX, 'place_barnaul.json'), '-LPShotScreen', 'map', '-LPShotReportDelay', '5',
       '-lightplan.native.sunar.calibrationSeen', 'YES', '-lightplan.native.sunar.moon', 'NO',
       '-lightplan.native.sunar.milkyWay', 'NO', '-lightplan.native.sunar.stars', 'YES',
       '-lightplan.native.sunar.constellations', 'YES', '-lightplan.native.sunar.planets', 'NO',
       '-LPSunAR', '1', '-LPSunARMoment', '2026-10-14T14:00:00Z', '-LPSunARPose', '30,42,0',
       '-LPSunARPhone', '56.4977,84.9744,Asia/Tomsk', '-LPSunARFakeCamera', '1', '-LPSunARBackdrop', 'city',
       '-LPSunARMask', str(v), '-LPShotReport', report)
    for _ in range(240):
        if os.path.exists(report):
            break
        time.sleep(0.25)
    else:
        sys.exit('нет рамок: ' + report)
    time.sleep(1.5)
    sh('xcrun', 'simctl', 'io', udid, 'screenshot', '--type=png', png)
    return json.load(open(report)), Image.open(png)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--app')
    ap.add_argument('--opacities', default='0,0.5,0.6,0.65,0.7,0.75,0.8')
    ap.add_argument('--out', default=os.path.join(tempfile.gettempdir(), 'lp-shots', 'mask'))
    ap.add_argument('--edge-min', type=float, default=40)
    ap.add_argument('--star-min', type=float, default=10)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    udid = sim_udid()
    subprocess.run(['xcrun', 'simctl', 'boot', udid], capture_output=True)
    app = a.app or next(os.path.join(r, d) for r, ds, _ in os.walk(os.path.join(tempfile.gettempdir(), 'lp-shots', 'ar', 'DerivedData', 'Build', 'Products', 'Debug-iphonesimulator'))
                        for d in ds if d.endswith('.app'))
    sh('xcrun', 'simctl', 'install', udid, app)
    sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'dark')

    rows = []
    for v in [float(x) for x in a.opacities.split(',')]:
        rep, img = shoot(udid, v, a.out)
        nodes = rep['nodes']
        scale = img.width / rep['size'][0]
        sky, bld = region(img, nodes['ar.city.sky'], scale), region(img, nodes['ar.city.building'], scale)
        ks, kb = median([code(c) for c in sky]), median([code(c) for c in bld])
        ys, yb = median([Y(c) for c in sky]), median([Y(c) for c in bld])
        # Звёзды и линии созвездий лежат над крышами, ниже плашек кнопок: полоса экрана y 0,22…0,46 высоты.
        W, H = rep['size'][0], nodes['ar.background']['h']
        band = region(img, dict(x=0, y=0.22 * H, w=W, h=0.24 * H), scale)
        star = max(Y(c) for c in band)
        ysky_band = median([Y(c) for c in band])
        mask = nodes.get('ar.mask', {}).get('text', 'нет узла ar.mask')
        rows.append(dict(v=v, sky_code=ks, bld_code=kb, sky_y=ys, bld_y=yb, step=ks - kb, star=(star + 0.05) / (ysky_band + 0.05), mask=mask))
    b = rows[0]
    print(f"{'непрозр.':>8} {'небо,код':>9} {'остаток':>8} {'небо Y':>7} {'остаток Y':>9} {'здание,код':>10} {'небо−здание':>11} {'звезда:фон':>10}")
    for r in rows:
        print(f"{r['v']:8.2f} {r['sky_code']:9.1f} {r['sky_code'] / b['sky_code'] * 100:7.1f}% {r['sky_y']:7.3f} {r['sky_y'] / b['sky_y'] * 100:8.1f}% "
              f"{r['bld_code']:10.1f} {r['step']:11.1f} {r['star']:10.2f}")
    print('узел маски при последней непрозрачности:', rows[-1]['mask'])
    # Две цели тянут в разные стороны: темнее — звезда читается лучше, но контур здания слабее. Потолок — непрозрачность, на
    # которой хуже выполненная из двух целей выполнена лучше всего (наибольшее min(контур / цель, звезда / цель)).
    for r in rows:
        r['score'] = min(r['step'] / a.edge_min, r['star'] / a.star_min)
    cand = [r for r in rows if r['v'] > 0 and r['sky_code'] / b['sky_code'] >= 0.25]
    best = max(cand, key=lambda r: r['score'])
    print(f"потолок: {best['v']:.2f} (небо остаётся {best['sky_code'] / b['sky_code'] * 100:.0f} % кода, контур {best['step']:.0f} кодов = "
          f"{best['step'] / a.edge_min * 100:.0f} % цели, звезда {best['star']:.1f} : 1 = {best['star'] / a.star_min * 100:.0f} % цели)")
    if best['score'] < 0.8:
        print('обе цели недостижимы одновременно хотя бы на 80 %'); sys.exit(1)


main()
