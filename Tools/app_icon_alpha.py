#!/usr/bin/env python3
"""Знак тестовых сборок «LP …»: основной значок + латунный кружок с «α».

Алексей (24.10): «Мне нужно четкое различие, пусть на значке будет бирка как на web
версии, там у нас значек beta, тут пусть будет альфа». Бирка — та же, что у веб-беты
(`Light_Plan/beta/icon.svg`, «B»): кружок #E2A44C, центр (385, 383), радиус 99 на холсте
512 — здесь ×2 на 1024; буква чёрная #0F0E0C, по центру кружка. Меняется только буква.

Источник — `App-iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (чистый значок
основного «Light Plan»). Результат — набор `AppIconAlpha.appiconset` рядом; какой из двух
берёт сборка, решает `Config/iOS.xcconfig` по идентификатору (чистый — только у
`Novopashin.LightPlan`), сторожит `Tools/check_app_icon.sh`.

  python3 Tools/app_icon_alpha.py          пересобрать AppIconAlpha из AppIcon (make appicon)
  python3 Tools/app_icon_alpha.py --check  AppIconAlpha собран из нынешнего AppIcon? нет — exit 1

«α» берётся из системного SF Pro (Bold): на другой версии macOS буква может сдвинуться
на пиксель, поэтому `--check` сверяет не букву, а то, что вне кружка значок совпадает
с основным до пикселя, а кружок на месте.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "App-iOS/Assets.xcassets"
SRC = ASSETS / "AppIcon.appiconset/AppIcon.png"
DST_DIR = ASSETS / "AppIconAlpha.appiconset"
DST = DST_DIR / "AppIconAlpha.png"

SIZE = 1024
K = SIZE / 512                      # веб-знак нарисован на 512
CX, CY, R = 385 * K, 383 * K, 99 * K
BADGE = (0xE2, 0xA4, 0x4C)
INK = (0x0F, 0x0E, 0x0C)
FONT = "/System/Library/Fonts/SFNS.ttf"
WEIGHT = b"Bold"
GLYPH_H = 150 * K / 2               # высота «α» по чернилам; «B» на вебе — 103 из 512 (это заглавная)
SS = 4                              # сглаживание: рисуем в 4 раза крупнее и уменьшаем


def badge_layer():
    n = SIZE * SS
    layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([(CX - R) * SS, (CY - R) * SS, (CX + R) * SS, (CY + R) * SS], fill=BADGE + (255,))

    font = ImageFont.truetype(FONT, 100)
    font.set_variation_by_name(WEIGHT)
    l, t, r, b = font.getbbox("α")
    size = 100 * GLYPH_H * SS / (b - t)
    font = ImageFont.truetype(FONT, round(size))
    font.set_variation_by_name(WEIGHT)
    l, t, r, b = font.getbbox("α")
    d.text((CX * SS - (l + r) / 2, CY * SS - (t + b) / 2), "α", font=font, fill=INK + (255,))
    return layer.resize((SIZE, SIZE), Image.BOX)   # среднее по 4×4: без «звона» за краем кружка


def build():
    src = Image.open(SRC).convert("RGB")
    assert src.size == (SIZE, SIZE), f"{SRC}: ждали {SIZE}×{SIZE}, а {src.size}"
    out = src.convert("RGBA")
    out.alpha_composite(badge_layer())
    return out.convert("RGB")       # значок iOS без прозрачности, как основной


def outside(x, y, margin=2):
    return (x + 0.5 - CX) ** 2 + (y + 0.5 - CY) ** 2 > (R + margin) ** 2


def check():
    if not DST.exists():
        print(f"{DST}: нет набора AppIconAlpha — make appicon")
        return 1
    src = Image.open(SRC).convert("RGB")
    dst = Image.open(DST).convert("RGB")
    if dst.size != src.size:
        print(f"{DST}: размер {dst.size}, у основного {src.size} — make appicon")
        return 1
    a, b = src.load(), dst.load()
    diff = sum(1 for y in range(SIZE) for x in range(SIZE) if outside(x, y) and a[x, y] != b[x, y])
    if diff:
        print(f"{DST}: вне кружка {diff} пикселей не как у AppIcon — основной значок менялся, make appicon")
        return 1
    # Кружок на месте: точки на кольце внутри него (между краем и буквой) — латунь.
    for dx, dy in ((0.85, 0), (-0.85, 0), (0, 0.85), (0, -0.85)):
        p = b[int(CX + dx * R), int(CY + dy * R)]
        if max(abs(p[i] - BADGE[i]) for i in range(3)) > 2:
            print(f"{DST}: в кружке {p}, ждали {BADGE} — make appicon")
            return 1
    print("значок α: собран из нынешнего AppIcon — ок")
    return 0


def main():
    if "--check" in sys.argv[1:]:
        return check()
    DST_DIR.mkdir(exist_ok=True)
    build().save(DST, optimize=True)
    contents = {
        "images": [{"filename": DST.name, "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }
    (DST_DIR / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(f"записан {DST.relative_to(ROOT)}")
    return check()


if __name__ == "__main__":
    sys.exit(main())
