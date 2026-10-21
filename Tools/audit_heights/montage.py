#!/usr/bin/env python3
"""Склейка снимков в одну картинку: python3 montage.py <out> <файл.png> <модель> <сцена,сцена,…> [масштаб px/pt]
(один и тот же масштаб для всех — модели и сцены сопоставимы по точкам)."""
import os, sys
from PIL import Image, ImageDraw
out, dst, model, scenes = sys.argv[1:5]
k = float(sys.argv[5]) if len(sys.argv) > 5 else 0.5
SIZE = {'ASE3': (375, 667), 'A15P': (393, 852), 'A17P': (402, 874), 'A15PM': (430, 932), 'A17PM': (440, 956)}
tiles = []
for sc in scenes.split(','):
    for m in model.split('+'):
        p = os.path.join(out, m, sc + '-dark', 'native.png')
        if os.path.exists(p):
            w, h = SIZE[m]
            tiles.append((f'{sc} {m}', Image.open(p).convert('RGB').resize((int(w * k * 2), int(h * k * 2)))))
if tiles:
    H = max(t.height for _, t in tiles)
    sheet = Image.new('RGB', (sum(t.width + 6 for _, t in tiles), H + 12), (110, 110, 110))
    x = 0; d = ImageDraw.Draw(sheet)
    for n, t in tiles:
        sheet.paste(t, (x, 12)); d.text((x + 2, 0), n, fill=(255, 255, 255)); x += t.width + 6
    sheet.save(dst); print(sheet.size)
