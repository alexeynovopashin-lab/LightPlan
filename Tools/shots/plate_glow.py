#!/usr/bin/env python3
"""30з.3: числа света из-под первой плашки по кадрам `plate_glow.js`.
   python3 Tools/shots/plate_glow.py <папка> [--cases a,b]
Для каждого `glow-<момент>-<тема>.png` берёт парный `…-off.png` (тот же момент без света) и считает разность:
пик (самая яркая точка внутри плашки), его цвет на кадре и без света, во сколько раз ярче плашки, непрозрачность света
(разность / (цвет света − плашка)), высота, на которой остаётся половина пика, и разность над верхней кромкой (должна быть 0).
Рамка плашки — из отчёта (`plate.glow`: x, w, верх = y − подъём над горизонтом; низ = y + h, масштаб — размер кадра / `size`)."""
import json, os, sys
import numpy as np
from PIL import Image

def lum(a):
    a = a / 255.0
    a = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]

def main():
    d = sys.argv[1]
    only = sys.argv[sys.argv.index('--cases') + 1].split(',') if '--cases' in sys.argv else None
    names = sorted(f[:-4] for f in os.listdir(d) if f.startswith('glow-') and f.endswith('.png') and not f.endswith('-off.png'))
    print('%-28s %-8s %-6s %-14s %-14s %-7s %-7s %-6s %s' % ('случай', 'пик ур.', 'α пик', 'на кадре', 'без света', 'ярче ×', 'у=½, pt', 'над', 'узел plate.glow'))
    for n in names:
        if only and n not in only: continue
        off = os.path.join(d, n + '-off.png')
        if not os.path.exists(off): continue
        rep = json.load(open(os.path.join(d, n + '.json')))
        node = rep['nodes']['plate.glow']
        sc = Image.open(os.path.join(d, n + '.png')).width / rep['size']['w'] if 'w' in rep['size'] else 3.0
        a = np.asarray(Image.open(os.path.join(d, n + '.png')).convert('RGB')).astype(float)
        b = np.asarray(Image.open(off).convert('RGB')).astype(float)
        diff = np.abs(a - b).sum(2)
        x0, x1 = int(node['x'] * sc), int((node['x'] + node['w']) * sc)
        # Рамка узла — только содержимое плашки; сама плашка выше на подъём. Верх ищем по разности: первая строка, где она есть.
        rows = np.where(diff[:, x0 + 20:x1 - 20].max(1) > 6)[0]
        # Только столбцы без текста: берём медиану по узкой полосе вокруг центра света.
        text = node.get('text', 'none')
        if text == 'none' or not len(rows):
            print('%-28s нет света (узел: %s), разность макс. %d' % (n, text, int(diff.max())))
            continue
        top = rows.min()
        cx = int(x0 + (x1 - x0) * float(text.split('|')[2]))
        band = slice(max(x0, cx - 12), min(x1, cx + 12))
        col = np.median(a[top:top + 200, band], axis=1); colo = np.median(b[top:top + 200, band], axis=1)
        dl = np.abs(col - colo).sum(1)
        i = int(np.argmax(dl[:12]))
        peak, base = col[i], colo[i]
        glow = tuple(int(text[k:k + 2], 16) for k in (0, 2, 4))
        den = np.array(glow, float) - base
        alpha = float(np.median(((peak - base) / np.where(np.abs(den) < 1, np.nan, den))[~np.isnan(np.abs(den) < 1)])) if True else 0
        ratio = lum(peak) / max(lum(base), 1e-6)
        half = next((j for j in range(i, 200) if dl[j] <= dl[i] / 2), 0)
        above = int(diff[max(0, top - 30):top - 2, x0 + 20:x1 - 20].max()) if top > 32 else -1
        print('%-28s %-8s %-6.3f %-14s %-14s %-7.2f %-7.1f %-6s %s' % (n, text.split('|')[1], alpha, tuple(int(v) for v in peak), tuple(int(v) for v in base), ratio, (half - i) / sc, above, text))

main()
