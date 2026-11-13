#!/usr/bin/env python3
"""28к.4: числа к кадрам `palette_d.js`.
  palette_d.py diff <папка-до> <папка-после> [--only <подстрока>]   сравнить кадры по пикселям (тёмные: должно быть 0)
  palette_d.py px <png> <x> <y> [<x> <y> ...]                      цвет в точках экрана (pt, кадр 3×)
  palette_d.py col <png> <x> <y0> <y1> [<шаг>]                     цвет по столбцу x от y0 до y1 (pt)
  palette_d.py max <png> <x0> <y0> <x1> <y1>                        самый светлый пиксель в рамке (pt): звёзды ночью
  palette_d.py ratio <#hex> <#hex>                                  контраст WCAG двух цветов
Кадр — 1320 × 2868 (440 × 956 pt, 3×). Рамки узлов — `<случай>.json` рядом с кадром."""
import sys, os, glob
import numpy as np
from PIL import Image

K = 3


def load(p):
    return np.asarray(Image.open(p).convert('RGB')).astype(int)


def hx(c):
    return '#%02X%02X%02X' % tuple(int(v) for v in c)


def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lum(c):
    return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])


def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def parse_hex(s):
    s = s.lstrip('#')
    return [int(s[i:i + 2], 16) for i in (0, 2, 4)]


def cmd_diff(a, b, only=None):
    bad = 0
    names = sorted(os.path.basename(p) for p in glob.glob(os.path.join(a, '*.png')))
    for n in names:
        if only and only not in n:
            continue
        pb = os.path.join(b, n)
        if not os.path.exists(pb):
            print(f'{n:44s} нет в «после»')
            bad += 1
            continue
        x, y = load(os.path.join(a, n)), load(pb)
        if x.shape != y.shape:
            print(f'{n:44s} разный размер')
            bad += 1
            continue
        d = np.abs(x - y).max(axis=2)
        cnt = int((d > 0).sum())
        # строки с отличиями: верхний и нижний край, чтобы видеть, где именно
        rows = np.where((d > 0).any(axis=1))[0]
        where = f'  строки {rows.min() // K}–{rows.max() // K} pt, макс. Δ {int(d.max())}' if cnt else ''
        print(f'{n:44s} {cnt:8d} px{where}')
        bad += cnt > 0
    print('различаются:', bad)
    return 1 if bad else 0


def cmd_px(p, pts):
    im = load(p)
    for i in range(0, len(pts), 2):
        x, y = float(pts[i]), float(pts[i + 1])
        print(f'({x:g}, {y:g}) pt  {hx(im[int(y * K), int(x * K)])}')


def cmd_col(p, x, y0, y1, step=None):
    im = load(p)
    step = float(step) if step else (float(y1) - float(y0)) / 8
    y = float(y0)
    while y <= float(y1) + 1e-6:
        print(f'y={y:6.1f} pt  {hx(im[int(y * K), int(float(x) * K)])}')
        y += step


def cmd_max(p, x0, y0, x1, y1):
    im = load(p)[int(float(y0) * K):int(float(y1) * K), int(float(x0) * K):int(float(x1) * K)]
    l = im.sum(axis=2)
    i = np.unravel_index(l.argmax(), l.shape)
    med = np.median(im.reshape(-1, 3), axis=0)
    print(f'самый светлый {hx(im[i])} в ({(int(float(x0) * K) + i[1]) / K:.1f}, {(int(float(y0) * K) + i[0]) / K:.1f}) pt; медиана рамки {hx(med)}')
    n = int((l >= l.max() - 30).sum())
    print(f'пикселей в пределах 30 от максимума: {n}')


if __name__ == '__main__':
    c = sys.argv[1] if len(sys.argv) > 1 else ''
    if c == 'diff':
        only = sys.argv[sys.argv.index('--only') + 1] if '--only' in sys.argv else None
        sys.exit(cmd_diff(sys.argv[2], sys.argv[3], only))
    elif c == 'px':
        cmd_px(sys.argv[2], sys.argv[3:])
    elif c == 'col':
        cmd_col(*sys.argv[2:])
    elif c == 'max':
        cmd_max(*sys.argv[2:])
    elif c == 'ratio':
        print(f'{ratio(parse_hex(sys.argv[2]), parse_hex(sys.argv[3])):.2f}:1')
    else:
        print(__doc__)
