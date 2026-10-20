#!/usr/bin/env python3
"""Панорама Млечного Пути для AR (шаг 29.8в.20): исходник → 4096 пикселей в ширину, чёрное = прозрачное.

    python3 Tools/mw_pano_prepare.py "<MW.png>" mw
    python3 Tools/mw_pano_prepare.py "<MW2.png>" mw2

Исходник — эквидистантная проекция в галактических координатах (ядро l = 0 в центре, l растёт влево, b = 0 по
вертикали посередине), RGBA: у прозрачных мест цвет белый, поэтому картинка сначала умножается на альфу (на чёрное).
Результат — `Packages/LightPlanUI/Sources/LightPlanUI/MilkyWayData/pano_<name>.png`, RGB 8 бит. В репозиторий файлы
не кладутся (`.gitignore`): права на исходник неизвестны, репозиторий публичный.
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

WIDTH = 4096
OUT = Path(__file__).resolve().parent.parent / "Packages/LightPlanUI/Sources/LightPlanUI/MilkyWayData"


def main(src: str, name: str) -> None:
    im = Image.open(src).convert("RGBA")
    a = np.asarray(im).astype(np.float32)
    rgb = a[..., :3] * (a[..., 3:4] / 255.0)
    black = Image.fromarray(np.clip(rgb + 0.5, 0, 255).astype(np.uint8))
    h = round(im.height * WIDTH / im.width)
    small = black.resize((WIDTH, h), Image.LANCZOS)
    dest = OUT / f"pano_{name}.png"
    small.save(dest, optimize=True)
    print(f"{dest} {WIDTH}x{h} {dest.stat().st_size / 1e6:.1f} MB (исходник {im.width}x{im.height})")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
