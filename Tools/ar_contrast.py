#!/usr/bin/env python3
"""Шаг 29.8в.4: контраст текста нижней панели и кнопок AR над белым, серым и чёрным фоном.

Панель и кнопки — системное стекло `.glassEffect`: его цвет не лежит в константах, поэтому контраст считается по
снимку симулятора. Фон — сплошной (`-LPSunARBackdrop white|gray|black`, отладка), без камеры. Для каждого узла
(рамки из отчёта приложения, `-LPShotReport`): фон — медианная яркость рамки, текст — самый светлый пиксель рамки
(у мелкого текста сглаживание занижает максимум, оценка осторожная). Контраст WCAG: (L1 + 0,05) / (L2 + 0,05).

    python3 Tools/ar_contrast.py [--out DIR] [--min 4.5]
Цель — не ниже 4,5 : 1 у текста панели; код 1, если ниже.
"""
import json, os, subprocess, sys, tempfile, time
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, 'Fixtures', 'shots')
BUNDLE = 'Novopashin.LightPlan'
PANEL = ['ar.time', 'ar.note', 'ar.sunPos']
BUTTONS = ['ar.back', 'ar.calibrate', 'ar.heading', 'ar.moonToggle', 'ar.mwToggle']


def sh(*a, **k):
    return subprocess.run(a, check=True, capture_output=True, text=True, **k).stdout


def sim_udid():
    name = subprocess.run(['node', os.path.join(ROOT, 'Tools', 'sim.js')], capture_output=True, text=True, cwd=ROOT).stdout
    import re
    m = re.search(r'([0-9A-F]{8}-[0-9A-F-]{27})', name)
    if not m:
        sys.exit('нет симулятора ветки: make sims')
    return m.group(1)


def lum(c):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2])


def contrast(l1, l2):
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def measure(img, frame, scale):
    x, y, w, h = [int(round(v * scale)) for v in (frame['x'], frame['y'], frame['w'], frame['h'])]
    box = img.crop((x, y, x + w, y + h)).convert('RGB')
    ls = sorted(lum(p) for p in box.getdata())
    if not ls:
        return None
    bg = ls[len(ls) // 2]
    fg = ls[-1]
    return contrast(fg, bg), fg, bg


def main():
    out = tempfile.mkdtemp(prefix='lp-ar-contrast-')
    minimum = 4.5
    if '--min' in sys.argv:
        minimum = float(sys.argv[sys.argv.index('--min') + 1])
    if '--out' in sys.argv:
        out = sys.argv[sys.argv.index('--out') + 1]
        os.makedirs(out, exist_ok=True)
    udid = sim_udid()
    subprocess.run(['xcrun', 'simctl', 'boot', udid], capture_output=True)
    subprocess.run(['xcrun', 'simctl', 'ui', udid, 'appearance', 'dark'], capture_output=True)
    rows, worst_panel = [], 99.0
    for backdrop in ('white', 'gray', 'black'):
        report = os.path.join(out, backdrop + '.json')
        png = os.path.join(out, backdrop + '.png')
        if os.path.exists(report):
            os.remove(report)
        subprocess.run(['xcrun', 'simctl', 'terminate', udid, BUNDLE], capture_output=True)
        sh('xcrun', 'simctl', 'launch', udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
           '-LPShotNow', '2026-10-20T21:00:00+07:00', '-LPShotZone', 'Asia/Tomsk', '-LPShotSeed', FX + '/seed.json',
           '-LPShotForecast', FX + '/forecast_barnaul.json', '-LPShotAir', FX + '/air_barnaul.json',
           '-LPShotName', FX + '/place_barnaul.json', '-LPShotScreen', 'map', '-LPShotReportDelay', '5',
           '-lightplan.native.sunar.calibrationSeen', 'YES', '-lightplan.native.sunar.moon', 'NO',
           '-lightplan.native.sunar.milkyWay', 'NO',
           '-LPSunAR', '1', '-LPSunARMoment', '2026-10-20T14:00:00Z', '-LPSunARPose', '183,18,0',
           '-LPSunARPhone', '56.4977,84.9744,Asia/Tomsk', '-LPSunARBackdrop', backdrop, '-LPShotReport', report)
        for _ in range(240):
            if os.path.exists(report):
                break
            time.sleep(0.25)
        else:
            sys.exit('нет рамок: ' + backdrop)
        time.sleep(1.5)
        sh('xcrun', 'simctl', 'io', udid, 'screenshot', '--type=png', png)
        nodes = json.load(open(report))['nodes']
        size = json.load(open(report))['size']
        img = Image.open(png)
        scale = img.size[0] / size[0]
        for name in PANEL + BUTTONS:
            if name not in nodes:
                rows.append((backdrop, name, None))
                continue
            r = measure(img, nodes[name], scale)
            rows.append((backdrop, name, r))
            if name in PANEL and r:
                worst_panel = min(worst_panel, r[0])
    print('%-6s %-14s %8s' % ('фон', 'узел', 'контраст'))
    for b, n, r in rows:
        print('%-6s %-14s %s' % (b, n, ('%.2f : 1' % r[0]) if r else 'нет узла'))
    worst_btn = min([r[0] for b, n, r in rows if n in BUTTONS and r] or [99.0])
    print('худший у текста панели: %.2f : 1 (цель ≥ %.1f)' % (worst_panel, minimum))
    print('худший у кнопок: %.2f : 1 (цель ≥ %.1f)' % (worst_btn, minimum))
    print('→ ' + out)
    sys.exit(0 if min(worst_panel, worst_btn) >= minimum else 1)


main()
