#!/usr/bin/env python3
"""Шапка «Съёмок» (кнопки над календарём): рамки нажатия и чернила значков, в pt по снимку.

    python3 Tools/shots/header_ink.py <папка пары с native.png и native.json>

По каждому узлу `plan.*` — рамка узла (зона нажатия), рамка чернил внутри неё и размер значка; плюс зазоры между зонами
соседних кнопок (отрицательный — перекрытие) и `dd.0` — где стоит неделя ниже шапки (сдвиг неё — сдвиг шапки).
"""
import json, os, sys
from PIL import Image
import numpy as np

SCALE = 3


def ink(a, f, inset=0.0):
    x0, y0 = int(round((f['x'] + inset) * SCALE)), int(round((f['y'] + inset) * SCALE))
    x1, y1 = int(round((f['x'] + f['w'] - inset) * SCALE)), int(round((f['y'] + f['h'] - inset) * SCALE))
    reg = a[y0:y1, x0:x1]
    bg = np.median(reg.reshape(-1, 3), axis=0)
    d = np.abs(reg - bg).sum(axis=2)
    m = d.max()
    if m < 40:
        return None
    on = d >= 0.5 * m
    r, c = np.where(on.any(axis=1))[0], np.where(on.any(axis=0))[0]
    return ((x0 + c[0]) / SCALE, (y0 + r[0]) / SCALE, (x0 + c[-1] + 1) / SCALE, (y0 + r[-1] + 1) / SCALE)


def measure(folder):
    a = np.asarray(Image.open(os.path.join(folder, 'native.png')).convert('RGB'), dtype=np.int32)
    n = json.load(open(os.path.join(folder, 'native.json')))['nodes']
    out = {}
    for k in ['plan.scope', 'plan.add', 'plan.stats', 'plan.search', 'plan.quest']:
        f = n.get(k)
        if not f:
            continue
        # у кнопки вида под значком плашка — чернила ищутся внутри неё, на 6 pt от края
        b = ink(a, f, inset=6 if k == 'plan.scope' else 0)
        out[k] = dict(hit=[f['x'], f['y'], f['w'], f['h']],
                      ink=None if b is None else [round(float(v), 2) for v in b],
                      glyph=None if b is None else [round(float(b[2] - b[0]), 2), round(float(b[3] - b[1]), 2)])
    names = [k for k in ['plan.scope', 'plan.add', 'plan.stats', 'plan.search'] if k in n]
    gaps = {}
    for p, q in zip(names, names[1:]):
        gaps[p + ' → ' + q] = round(n[q]['x'] - (n[p]['x'] + n[p]['w']), 2)
    t = n.get('plan.title')
    return dict(buttons=out, gaps=gaps, title=t, week_y=(n.get('dd.0') or {}).get('y'),
                header_bottom=max(n[k]['y'] + n[k]['h'] for k in names))


if __name__ == '__main__':
    r = measure(sys.argv[1])
    for k, v in r['buttons'].items():
        print(f"{k:12s} зона {v['hit']}  чернила {v['ink']}  значок {v['glyph']}")
    print('зазоры между зонами:', r['gaps'])
    print('заголовок:', r['title'], ' неделя dd.0 y =', r['week_y'], ' низ кнопок =', r['header_bottom'])
