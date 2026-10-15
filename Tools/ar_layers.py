#!/usr/bin/env python3
"""Шаг 29.8в.5: порядок слоёв экрана AR по пикселям (а не по коду). Симулятор, подставная камера, кадр «день»
(диск солнца лежит на дуге). Приложение рисует только слои из `-LPSunARLayers` (отладка, `SunARLayers`), кадр
снимается на каждой ступени, и считается, сколько пикселей изменилось внутри диска и в кольце снаружи:

  камера → + дуга → + линза → + налёт

Что читать: «+ дуга» меняет кольцо вокруг диска и НЕ меняет середину (дуга внутри диска вырезана); «+ линза»
возвращает дугу внутрь диска (гнутую); «+ налёт» красит диск. Если линза лежит под дугой или не гнёт, второй
шаг пуст.

    python3 Tools/ar_layers.py [--out DIR]
"""
import json, os, re, subprocess, sys, tempfile, time
from PIL import Image, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, 'Fixtures', 'shots')
BUNDLE = 'Novopashin.LightPlan'
STEPS = [('camera', 'камера'), ('camera,arc', '+ дуга'), ('camera,arc,lens', '+ линза'), ('camera,arc,lens,paint', '+ налёт')]


def sh(*a):
    return subprocess.run(a, check=True, capture_output=True, text=True).stdout


def udid():
    out = subprocess.run(['node', os.path.join(ROOT, 'Tools', 'sim.js')], capture_output=True, text=True, cwd=ROOT).stdout
    m = re.search(r'([0-9A-F]{8}-[0-9A-F-]{27})', out)
    if not m:
        sys.exit('нет симулятора ветки: make sims')
    return m.group(1)


def shot(sim, layers, path, report):
    subprocess.run(['xcrun', 'simctl', 'terminate', sim, BUNDLE], capture_output=True)
    if os.path.exists(report):
        os.remove(report)
    sh('xcrun', 'simctl', 'launch', sim, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
       '-LPShotNow', '2026-10-14T12:00:00+07:00', '-LPShotZone', 'Asia/Tomsk', '-LPShotSeed', FX + '/seed.json',
       '-LPShotForecast', FX + '/forecast_barnaul.json', '-LPShotAir', FX + '/air_barnaul.json',
       '-LPShotName', FX + '/place_barnaul.json', '-LPShotScreen', 'map', '-LPShotReportDelay', '5',
       '-lightplan.native.sunar.calibrationSeen', 'YES', '-lightplan.native.sunar.moon', 'NO',
       '-lightplan.native.sunar.milkyWay', 'NO', '-LPSunAR', '1', '-LPSunARMoment', '2026-10-14T05:00:00Z',
       '-LPSunARPose', '162,24,0', '-LPSunARPhone', '56.4977,84.9744,Asia/Tomsk', '-LPSunARFakeCamera', '1',
       '-LPSunARLayers', layers, '-LPShotReport', report)
    for _ in range(80):
        if os.path.exists(report):
            break
        time.sleep(0.25)
    time.sleep(1.5)
    sh('xcrun', 'simctl', 'io', sim, 'screenshot', '--type=png', path)


def main():
    out = sys.argv[sys.argv.index('--out') + 1] if '--out' in sys.argv else tempfile.mkdtemp(prefix='lp-ar-layers-')
    os.makedirs(out, exist_ok=True)
    sim = udid()
    subprocess.run(['xcrun', 'simctl', 'boot', sim], capture_output=True)
    subprocess.run(['xcrun', 'simctl', 'ui', sim, 'appearance', 'dark'], capture_output=True)
    frames = []
    box = None
    for layers, _ in STEPS:
        p = os.path.join(out, layers.replace(',', '_') + '.png')
        rep = os.path.join(out, 'report.json')
        shot(sim, layers, p, rep)
        frames.append(Image.open(p).convert('RGB'))
        if box is None and layers.endswith('paint'):
            nodes = json.load(open(rep)).get('nodes', {})
            n = nodes.get('ar.mark.sun.now')
            if n:
                box = n
    if box is None:
        sys.exit('диска солнца в кадре нет')
    scale = frames[0].width / 440.0
    cx, cy = (box['x'] + box['w'] / 2) * scale, (box['y'] + box['h'] / 2) * scale
    r = box['w'] / 2 * scale

    def zone(inside):
        lo, hi = (0, r - 1) if inside else (r + 2, r + 10 * scale)
        pts = []
        for y in range(int(cy - hi), int(cy + hi) + 1):
            for x in range(int(cx - hi), int(cx + hi) + 1):
                d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                if lo <= d <= hi:
                    pts.append((x, y))
        return pts

    zin, zout = zone(True), zone(False)
    rows = []
    for i in range(1, len(frames)):
        diff = ImageChops.difference(frames[i], frames[i - 1]).convert('L')
        px = diff.load()
        n_in = sum(1 for p in zin if px[p] > 12)
        n_out = sum(1 for p in zout if px[p] > 12)
        rows.append({'step': STEPS[i][1], 'layers': STEPS[i][0], 'changed_inside_disc_px': n_in,
                     'inside_total_px': len(zin), 'changed_ring_outside_px': n_out, 'ring_total_px': len(zout)})
    print(json.dumps({'disc': {'center_pt': [round(cx / scale, 1), round(cy / scale, 1)], 'd_pt': box['w']}, 'steps': rows},
                     ensure_ascii=False, indent=1))
    open(os.path.join(out, 'layers.json'), 'w').write(json.dumps(rows, ensure_ascii=False, indent=1))


main()
