#!/usr/bin/env python3
"""Доля пустоты плитки дня (шаг 29.11в) по снимку симулятора.

    day_tile_void.py <png> <x> <y> <w> <h> <ширина экрана в pt> [<куда положить кадр плитки>]

Печатает JSON {"void": доля, "ink": доля, "area": pt²}. Плитка — скруглённый прямоугольник (радиус 18 pt), заливка — самый
частый цвет внутри. Чернила — пиксели, отличные от заливки больше чем на 24 по любому каналу (текст, знаки, нить, чёрточка
у даты). Каждое чернило расширено на 4 pt (между буквами и вокруг знака пустоты нет). Пустота = 1 − расширенные чернила /
площадь плитки. Одна и та же мера до и после правки; «выглядит лучше» числом не является.
"""
import json
import sys
from collections import Counter

from PIL import Image, ImageChops, ImageDraw, ImageFilter

png, x, y, w, h, screen_pt = sys.argv[1], *map(float, sys.argv[2:6]), float(sys.argv[6])
out = sys.argv[7] if len(sys.argv) > 7 else None
im = Image.open(png).convert('RGB')
k = im.width / screen_pt                      # пикселей в точке
box = tuple(round(v * k) for v in (x, y, x + w, y + h))
tile = im.crop(box)
if out:
    pad = round(12 * k)
    im.crop((max(0, box[0] - pad), max(0, box[1] - pad), min(im.width, box[2] + pad), min(im.height, box[3] + pad))).save(out)

# Работаем в точках: 1 пиксель = 1 pt, ячейка берёт «есть чернила», если они есть в любой из её пикселей.
fill = Counter(tile.getdata()).most_common(1)[0][0]
diff = ImageChops.difference(tile, Image.new('RGB', tile.size, fill))
r, g, b = diff.split()
ink = ImageChops.lighter(ImageChops.lighter(r.point(lambda v: 255 if v > 24 else 0), g.point(lambda v: 255 if v > 24 else 0)),
                         b.point(lambda v: 255 if v > 24 else 0))
shape = Image.new('L', tile.size, 0)
ImageDraw.Draw(shape).rounded_rectangle((0, 0, tile.width - 1, tile.height - 1), radius=18 * k, fill=255)
ink = ImageChops.multiply(ink, shape)
small = ink.resize((max(1, round(w)), max(1, round(h))), Image.BOX).point(lambda v: 255 if v > 0 else 0)
grown = small.filter(ImageFilter.MaxFilter(9))                    # ±4 pt
mask = shape.resize(small.size, Image.BOX).point(lambda v: 255 if v > 127 else 0)
grown = ImageChops.multiply(grown, mask)
area = sum(1 for v in mask.getdata() if v)
used = sum(1 for v in grown.getdata() if v)
print(json.dumps({'void': round(1 - used / area, 4), 'ink': round(used / area, 4), 'area': area}))
