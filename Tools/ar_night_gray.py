#!/usr/bin/env python3
"""Шаг 29.8в.5: солнце и луна различимы без цвета. Кадр сценария `dusk_both` (`Tools/shots/ar.js`) переводится в
оттенки серого, и для каждого диска считается: сколько раз яркость контура на 1 pt за краем переходит порог
(пунктир — десятки, сплошной — 0) и разброс яркости внутри диска (у луны фаза — разброс большой).

    python3 Tools/ar_night_gray.py <папка ar.js>/dusk_both
"""
import json, math, re, sys
from PIL import Image

d = sys.argv[1]
nodes = json.load(open(d + '/native.json'))['nodes']
img = Image.open(d + '/native.png').convert('L')
scale = img.width / json.load(open(d + '/native.json'))['size'][0]
px = img.load()


def disc(key):
    n = nodes[key]
    return (n['x'] + n['w'] / 2) * scale, (n['y'] + n['h'] / 2) * scale, n['w'] / 2 * scale


def ring_switches(cx, cy, r):
    vals = []
    for k in range(720):
        a = k * math.pi / 360
        x, y = cx + (r + 1.5 * scale) * math.cos(a), cy + (r + 1.5 * scale) * math.sin(a)
        if 0 <= x < img.width and 0 <= y < img.height:
            vals.append(px[int(x), int(y)])
    if not vals:
        return None
    lo, hi = min(vals), max(vals)
    mid = (lo + hi) / 2
    st = [v > mid for v in vals]
    return sum(1 for i in range(len(st)) if st[i] != st[(i + 1) % len(st)]), hi - lo


def spread(cx, cy, r):
    vals = []
    for y in range(int(cy - r + 4 * scale), int(cy + r - 4 * scale)):
        for x in range(int(cx - r + 4 * scale), int(cx + r - 4 * scale)):
            if math.hypot(x - cx, y - cy) < r - 4 * scale and 0 <= x < img.width and 0 <= y < img.height:
                vals.append(px[x, y] / 255)
    if not vals:
        return None
    m = sum(vals) / len(vals)
    return math.sqrt(sum((v - m) ** 2 for v in vals) / len(vals))


for key in sorted(k for k in nodes if k.startswith('ar.mark.')):
    cx, cy, r = disc(key)
    off = cx - r < 0 or cx + r > img.width
    sw = ring_switches(cx, cy, r)
    print(f'{key}: центр ({cx / scale:.0f}, {cy / scale:.0f}) pt, смен контура {sw[0] if sw else "—"} (размах яркости {sw[1] if sw else "—"}), '
          f'разброс внутри {spread(cx, cy, r) if spread(cx, cy, r) is None else round(spread(cx, cy, r), 3)}'
          + ('  [у края кадра: часть контура за экраном]' if off else ''))
