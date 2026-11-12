#!/usr/bin/env python3
"""28к.2: доски «сейчас | А | Б | В-красный | В-зелёный» из кадров `pair.js --native-only`.

    python3 boards.py <папка с now/ A/ B/ C/ D/> <папка досок>

В каждой папке варианта — подпапки сценариев `pair.js` (`light-astro-light-day`, …) с `native.png` (×3, 1320×2868).
Доска — пять кадров вдвое меньше, рядом, подписи внизу; JPEG 88.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

COLS = [("now", "сейчас"), ("A", "А · бумага поправленная"), ("B", "Б · как на образцах, оранжевый"),
        ("C", "В · красный"), ("D", "В · кислотно-зелёный")]
SCREENS = [
    ("light-astro-light-day", "svet_den", "«Свет», день («Астро»: барабан «Бумага»)"),
    ("light-astro-light-night", "svet_noch", "«Свет», ночь («Астро»: купол ночью, барабан)"),
    ("planner-month-light", "semki_mesyac", "«Съёмки», месяц"),
    ("card-people-during-light", "kartochka", "Карточка съёмки"),
    ("m28-orgs-light", "organizacii", "«Организации»"),
    ("m28-mbgallery-light", "mudbord", "Мудборд"),
]
SCALE = 2
GAP = 24
LABEL = 120


def font(size):
    for p in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def find(root, key):
    p = os.path.join(root, key, "native.png")
    return p if os.path.exists(p) else None


def main(src, out):
    os.makedirs(out, exist_ok=True)
    f, ft = font(40), font(46)
    for key, name, title in SCREENS:
        shots = [find(os.path.join(src, c), key) for c, _ in COLS]
        if not all(shots):
            print("нет кадров:", name, shots)
            continue
        ims = [Image.open(p).convert("RGB") for p in shots]
        w, h = ims[0].size[0] // SCALE, ims[0].size[1] // SCALE
        board = Image.new("RGB", (len(ims) * w + (len(ims) + 1) * GAP, h + LABEL + 90 + GAP), (128, 128, 128))
        d = ImageDraw.Draw(board)
        d.text((GAP, 22), title + " — светлая тема, iPhone 17 Pro Max", fill=(255, 255, 255), font=ft)
        for i, im in enumerate(ims):
            x = GAP + i * (w + GAP)
            board.paste(im.resize((w, h), Image.LANCZOS), (x, 90))
            d.text((x + 8, 90 + h + 30), COLS[i][1], fill=(255, 255, 255), font=f)
        path = os.path.join(out, name + ".jpg")
        board.save(path, quality=88)
        print(path, board.size)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
