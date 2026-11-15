#!/usr/bin/env python3
"""30з.3б: перепад яркости на линии дуги купола, «как было» (`-clip`, `-LPDomeClip 1`) против «как стало».
   python3 Tools/shots/dome_clip.py <папка кадров> [--cases glow-morning-dark,glow-set-dark]
Берёт кадры `glow-<момент>-<тема>.png` и `…-clip.png`, на дуге купола (эллипс 163 × 148, центр (195, 196) от левого края
рамки `dome` + 25 pt) ставит пары точек: внутри и снаружи дуги на 9 pt по нормали, сравнивает яркость (L* по sRGB, 0…100) —
отдельно левая (угол 135–176°) и правая (4–45°) стороны. Печатает средний перепад «внутри − снаружи» и самый большой."""
import json, math, os, sys
import numpy as np
from PIL import Image

CX, CY, RX, RY = 195.0, 196.0, 163.0, 148.0

def lstar(rgb):
    c = np.asarray(rgb, float) / 255
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    y = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    return 116 * y ** (1 / 3) - 16 if y > 0.008856 else 903.3 * y

def sides(png, rep, off=9.0):
    im = np.asarray(Image.open(png).convert('RGB'))
    d = rep['nodes']['dome']; px = im.shape[1] / rep['size'][0]
    ox, oy = d['x'] + (d['w'] - 390) / 2, d['y']
    out = {}
    for name, (a0, a1) in {'лев': (135, 176), 'прав': (4, 45)}.items():
        diffs = []; steps = []
        for deg in np.linspace(a0, a1, 24):
            th = math.radians(deg)
            x, y = CX + RX * math.cos(th), CY - RY * math.sin(th)
            nx, ny = math.cos(th) / RX, -math.sin(th) / RY
            n = math.hypot(nx, ny); nx, ny = nx / n, ny / n  # наружу
            def at(k):
                X = int(round((ox + x + nx * k) * px)); Y = int(round((oy + y + ny * k) * px))
                return lstar(im[Y - 2:Y + 3, X - 2:X + 3].reshape(-1, 3).mean(0))
            # Ступень на линии дуги: перепад «внутри 5 pt − снаружи 5 pt» за вычетом такого же перепада рядом снаружи (5 pt − 15 pt):
            # плавный спад яркости входит в оба, край — только в первый.
            steps.append((at(-5) - at(5)) - (at(5) - at(15)))
            diffs.append(at(-off) - at(off))
        out[name] = (float(np.mean(diffs)), float(np.max(np.abs(diffs))), float(np.mean(steps)), float(np.max(np.abs(steps))))
    return out

def main():
    d = sys.argv[1]
    only = sys.argv[sys.argv.index('--cases') + 1].split(',') if '--cases' in sys.argv else None
    print('%-24s %-5s %-22s %-22s' % ('случай', 'сторона', 'было (внутри−снаружи, L*)', 'стало'))
    for f in sorted(os.listdir(d)):
        if not (f.startswith('glow-') and f.endswith('.png')) or f.endswith('-off.png') or f.endswith('-clip.png'): continue
        n = f[:-4]
        if only and n not in only: continue
        if not os.path.exists(os.path.join(d, n + '-clip.png')): continue
        new = sides(os.path.join(d, n + '.png'), json.load(open(os.path.join(d, n + '.json'))))
        old = sides(os.path.join(d, n + '-clip.png'), json.load(open(os.path.join(d, n + '-clip.json'))))
        for s in new:
            print('%-22s %-5s ступень на дуге L*: было среднее %+5.2f макс %5.2f → стало среднее %+5.2f макс %5.2f   (перепад ±9 pt: %+5.2f → %+5.2f)' % (
                n, s, old[s][2], old[s][3], new[s][2], new[s][3], old[s][0], new[s][0]))

main()
