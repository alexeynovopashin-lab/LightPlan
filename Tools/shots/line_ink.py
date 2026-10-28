#!/usr/bin/env python3
"""Строка света дня («Съёмки», день): где стоят чернила знаков и цифр, в pt по снимку.

    python3 Tools/shots/line_ink.py <папка пары с native.png и native.json> [--json]

Для каждого знака и каждой подписи строки — рамка чернил (верх, низ, середина по y, лево, право) в pt экрана.
Ось строки — середина цифр времени «восход» и «закат». Смещение знака = середина его чернил − ось
(плюс — ниже оси). Рамки узлов `native.json` (`dp.rise`, `dp.set`, `dp.gold`, `dp.temp`, `dp.chev`) — это
рамки строк текста, а не чернил: чернила цифр короче строки, поэтому ось меряется по пикселям.
Чернила — пиксели, отличающиеся от фона области не меньше чем наполовину наибольшего отличия.
"""
import json, sys, os
from PIL import Image
import numpy as np

SCALE = 3  # снимки пар — @3x


def ink_box(img, x0, y0, x1, y1):
    """Рамка чернил в области (pt) → (x0, y0, x1, y1) в pt или None."""
    a = np.asarray(img.convert('RGB'), dtype=np.int32)
    px0, py0, px1, py1 = [int(round(v * SCALE)) for v in (x0, y0, x1, y1)]
    reg = a[py0:py1, px0:px1]
    if reg.size == 0:
        return None
    bg = np.median(reg.reshape(-1, 3), axis=0)
    diff = np.abs(reg - bg).sum(axis=2)
    m = diff.max()
    if m < 40:
        return None
    on = diff >= 0.5 * m
    rows, cols = np.where(on.any(axis=1))[0], np.where(on.any(axis=0))[0]
    return ((px0 + cols[0]) / SCALE, (py0 + rows[0]) / SCALE, (px0 + cols[-1] + 1) / SCALE, (py0 + rows[-1] + 1) / SCALE)


def measure(folder):
    img = Image.open(os.path.join(folder, 'native.png'))
    n = json.load(open(os.path.join(folder, 'native.json')))['nodes']
    out = {}

    def text(key, name):
        f = n.get(key)
        if f:
            out[name] = ink_box(img, f['x'], f['y'] - 4, f['x'] + f['w'], f['y'] + f['h'] + 4)

    def sign(key, name, left_gap):
        """Знак стоит слева от подписи `key` на `left_gap` pt; ширина 17."""
        f = n.get(key)
        if f:
            out[name] = ink_box(img, f['x'] - left_gap - 17, f['y'] - 6, f['x'] - left_gap, f['y'] + f['h'] + 6)

    text('dp.rise', 'rise.text'); sign('dp.rise', 'rise.icon', 3)
    text('dp.set', 'set.text'); sign('dp.set', 'set.icon', 3)
    text('dp.gold', 'gold.text'); sign('dp.gold', 'gold.icon', 3)
    text('dp.temp', 'temp.text')
    t = n.get('dp.wxicon')   # у новой сборки у знака погоды свой узел
    if t:
        out['wx.icon'] = ink_box(img, t['x'], t['y'] - 6, t['x'] + t['w'], t['y'] + t['h'] + 6)
    elif 'dp.temp' in n:
        f = n['dp.temp']
        out['wx.icon'] = ink_box(img, f['x'] - 11 - 17, f['y'] - 6, f['x'] - 11, f['y'] + f['h'] + 6)
    c = n.get('dp.chev')
    if c:
        out['chev'] = ink_box(img, c['x'], c['y'], c['x'] + c['w'], c['y'] + c['h'])
    axis = None
    if out.get('rise.text') and out.get('set.text'):
        axis = (sum(out[k][1] + out[k][3] for k in ('rise.text', 'set.text')) / 4)
    rows = {}
    for k, b in out.items():
        if b is None:
            continue
        mid = (b[1] + b[3]) / 2
        rows[k] = dict(top=b[1], bottom=b[3], mid=round(mid, 2), left=b[0], right=b[2],
                       dy=None if axis is None else round(mid - axis, 2))
    return dict(axis=None if axis is None else round(axis, 2), rows=rows)


if __name__ == '__main__':
    folder = sys.argv[1]
    r = measure(folder)
    if '--json' in sys.argv:
        print(json.dumps(r, ensure_ascii=False))
    else:
        print('ось строки (середина цифр): y =', r['axis'])
        for k, v in r['rows'].items():
            print(f"{k:10s} y {v['top']:.2f}…{v['bottom']:.2f}  середина {v['mid']:.2f}  от оси {v['dy']:+.2f}  x {v['left']:.2f}…{v['right']:.2f}")
