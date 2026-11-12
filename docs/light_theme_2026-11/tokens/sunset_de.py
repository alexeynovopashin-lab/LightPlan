#!/usr/bin/env python3
"""28к.3: оранжевый акцент против неба «Света» в золотой час — ΔE по кадрам.

    python3 sunset_de.py <папка прогона was> <папка now>      (сценарий light-astro-light-golden, «Астро», светлая)

Кадр ×3. Небо — пиксели внутри купола (рамка `dome.arc` ужата на 12 pt), без текста (светлота L* < 70 отбрасывается) и без
самого диска солнца (круг 20 pt вокруг `dome.sun`). Дуга купола — цветные пиксели обода (рамка `dome.arc`, кольцо 3 pt у края, без кнопки «Солнце или луна»).
Акцент — токены: яркий `brass` и тёмный `brassInk` (было: `brass` #A9721F). ΔE — CIEDE2000 (и ΔE76 для справки).
"""
import json
import math
import os
import sys

from PIL import Image


def xyz(c):
    def f(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (f(x) for x in c)
    return (0.4124564 * r + 0.3575761 * g + 0.1804375 * b, 0.2126729 * r + 0.7151522 * g + 0.0721750 * b,
            0.0193339 * r + 0.1191920 * g + 0.9503041 * b)


def lab(c):
    X, Y, Z = xyz(c)
    def g(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = g(X / 0.95047), g(Y), g(Z / 1.08883)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def de76(a, b):
    return math.dist(a, b)


def de2000(l1, l2):
    L1, a1, b1 = l1
    L2, a2, b2 = l2
    C1, C2 = math.hypot(a1, b1), math.hypot(a2, b2)
    Cm = (C1 + C2) / 2
    G = 0.5 * (1 - math.sqrt(Cm ** 7 / (Cm ** 7 + 25 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1 = math.degrees(math.atan2(b1, a1p)) % 360
    h2 = math.degrees(math.atan2(b2, a2p)) % 360
    dL, dC = L2 - L1, C2p - C1p
    dh = h2 - h1
    if C1p * C2p == 0:
        dh = 0
    elif dh > 180:
        dh -= 360
    elif dh < -180:
        dh += 360
    dH = 2 * math.sqrt(C1p * C2p) * math.sin(math.radians(dh / 2))
    Lm, Cmp = (L1 + L2) / 2, (C1p + C2p) / 2
    if C1p * C2p == 0:
        hm = h1 + h2
    elif abs(h1 - h2) <= 180:
        hm = (h1 + h2) / 2
    else:
        hm = (h1 + h2 + 360) / 2 if h1 + h2 < 360 else (h1 + h2 - 360) / 2
    T = (1 - 0.17 * math.cos(math.radians(hm - 30)) + 0.24 * math.cos(math.radians(2 * hm))
         + 0.32 * math.cos(math.radians(3 * hm + 6)) - 0.20 * math.cos(math.radians(4 * hm - 63)))
    dTh = 30 * math.exp(-(((hm - 275) / 25) ** 2))
    Rc = 2 * math.sqrt(Cmp ** 7 / (Cmp ** 7 + 25 ** 7))
    Sl = 1 + 0.015 * (Lm - 50) ** 2 / math.sqrt(20 + (Lm - 50) ** 2)
    Sc, Sh = 1 + 0.045 * Cmp, 1 + 0.015 * Cmp * T
    Rt = -math.sin(math.radians(2 * dTh)) * Rc
    return math.sqrt((dL / Sl) ** 2 + (dC / Sc) ** 2 + (dH / Sh) ** 2 + Rt * (dC / Sc) * (dH / Sh))


def rgb(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


def sample(root):
    d = os.path.join(root, "light-astro-light-golden")
    im = Image.open(os.path.join(d, "native.png")).convert("RGB")
    n = json.load(open(os.path.join(d, "native.json")))["nodes"]
    sx = im.size[0] / 440
    a, s = n["dome.arc"], n["dome.sun"]
    sc = (s["x"] + s["w"] / 2, s["y"] + s["h"] / 2)
    x0, y0, x1, y1 = a["x"] + 12, a["y"] + 12, a["x"] + a["w"] - 12, a["y"] + a["h"] - 6
    sky = []
    for y in range(int(y0 * sx), int(y1 * sx), 3):
        for x in range(int(x0 * sx), int(x1 * sx), 3):
            if math.dist((x / sx, y / sx), sc) < 20:
                continue
            p = im.getpixel((x, y))
            if lab(p)[0] >= 70:
                sky.append(p)
    ring = []
    for y in range(int(a["y"] * sx), int((a["y"] + a["h"]) * sx)):
        for x in list(range(int(a["x"] * sx), int((a["x"] + 3) * sx))) + list(range(int((a["x"] + a["w"] - 3) * sx), int((a["x"] + a["w"]) * sx))):
            ring.append(im.getpixel((x, y)))
    ring = [p for p in ring if max(p) - min(p) > 40]
    ring = []
    sw = n["dome.swap"]
    for y in range(int(a["y"] * sx), int((a["y"] + a["h"]) * sx)):
        for x in list(range(int(a["x"] * sx), int((a["x"] + 3) * sx))) + list(range(int((a["x"] + a["w"] - 3) * sx), int((a["x"] + a["w"]) * sx))):
            inside = sw["x"] * sx <= x <= (sw["x"] + sw["w"]) * sx and sw["y"] * sx <= y <= (sw["y"] + sw["h"]) * sx
            p = im.getpixel((x, y))
            if not inside and max(p) - min(p) > 40:
                ring.append(p)
    return sky, ring, im, n, sx


def stats(vals):
    vals = sorted(vals)
    return vals[0], vals[len(vals) // 20], vals[len(vals) // 2]


def main(was, now):
    acc = {"было `brass` #A9721F": rgb(0xA9721F), "стало `brass` #E4570B (заливки, знаки)": rgb(0xE4570B),
           "стало `brassInk` #B83C00 (текст)": rgb(0xB83C00)}
    print("| кадр | с чем | акцент | ΔE2000 min | 5-й процентиль | медиана | ΔE76 min |\n|---|---|---|---|---|---|---|")
    for tag, root, keys in (("было", was, [0]), ("стало", now, [1, 2])):
        sky, ring, im, n, sx = sample(root)
        skyl = [lab(p) for p in sky]
        ringl = [lab(p) for p in ring]
        for k in keys:
            name, c = list(acc.items())[k]
            cl = lab(c)
            for what, ll, cnt in (("небо в куполе", skyl, len(sky)), ("дуга купола", ringl, len(ring))):
                d = [de2000(cl, v) for v in ll]
                d76 = [de76(cl, v) for v in ll]
                mn, p5, med = stats(d)
                print(f"| {tag} | {what} ({cnt} px) | {name} | {mn:.1f} | {p5:.1f} | {med:.1f} | {min(d76):.1f} |")
        # цвет на кадре: ярко-оранжевые элементы экрана (знак солнца, «18:50» в кнопке)
        for key in ("action.sub", "dome.swap"):
            nd = n[key]
            px = [im.getpixel((x, y)) for y in range(int(nd["y"] * sx), int((nd["y"] + nd["h"]) * sx))
                  for x in range(int(nd["x"] * sx), int((nd["x"] + nd["w"]) * sx))]
            best = max(px, key=lambda p: (max(p) - min(p)))
            print(f"| {tag} | цвет на кадре: {key} | самый насыщенный пиксель #%02X%02X%02X | | | | |" % best)
    sky, ring, *_ = sample(now)
    print("\nпримеры неба (стало): светлый край %s, у солнца самый тёплый %s" % ("#%02X%02X%02X" % max(sky, key=lambda p: sum(p)), "#%02X%02X%02X" % max(sky, key=lambda p: p[0] - p[2])))
    print("пример дуги (стало): %s" % ("#%02X%02X%02X" % max(ring, key=lambda p: p[0] - p[2]) if ring else "—"))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
