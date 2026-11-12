#!/usr/bin/env python3
"""28к.3: доски «было (main d468b34) | стало» из кадров `pair.js --native-only`, светлая тема.

    python3 boards.py <папка с was/ now/> <папка досок>

В каждой папке — подпапки сценариев `pair.js` (`light-astro-light-day`, …) с `native.png` (×3, 1320×2868).
Доска — два кадра в натуральную половину (660×1434) рядом, подписи сверху; JPEG 90.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

COLS = [("was", "было · main d468b34"), ("now", "стало · 28к.3")]
SCREENS = [
    ("light-astro-light-day", "svet_den", "«Свет», день («Астро»: купол, барабан «Бумага»)"),
    ("light-astro-light-night", "svet_noch", "«Свет», ночь (купол ночью — как решено в 28е, не тронут)"),
    ("planner-month-light", "semki_mesyac", "«Съёмки», месяц"),
    ("card-people-during-light", "kartochka", "Карточка съёмки (идёт съёмка)"),
    ("m28-orgs-light", "organizacii", "«Организации»"),
    ("m28-mbgallery-light", "mudbord", "Мудборд"),
]
SCALE = 2
GAP = 32
HEAD = 150


def font(size):
    for p in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def main(src, out):
    os.makedirs(out, exist_ok=True)
    f, ft = font(44), font(52)
    for key, name, title in SCREENS:
        shots = [os.path.join(src, c, key, "native.png") for c, _ in COLS]
        if not all(os.path.exists(p) for p in shots):
            print("нет кадров:", name)
            continue
        ims = [Image.open(p).convert("RGB") for p in shots]
        w, h = ims[0].size[0] // SCALE, ims[0].size[1] // SCALE
        board = Image.new("RGB", (len(ims) * w + (len(ims) + 1) * GAP, h + HEAD + GAP), (118, 118, 122))
        d = ImageDraw.Draw(board)
        d.text((GAP, 18), title + " — светлая тема, iPhone 17 Pro Max", fill=(255, 255, 255), font=ft)
        for i, im in enumerate(ims):
            x = GAP + i * (w + GAP)
            d.text((x, 88), COLS[i][1], fill=(255, 255, 255), font=f)
            board.paste(im.resize((w, h), Image.LANCZOS), (x, HEAD))
        path = os.path.join(out, name + ".jpg")
        board.save(path, quality=90)
        print(path, board.size)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
