#!/usr/bin/env python3
"""28к.2: числа вариантов светлой темы.

    python3 measure.py [<папка кадров с now/ A/ B/ C/ D/>]

1. Из кода (*из кода, не мерено*): контраст токенов варианта (`LightVariant.swift` повторён здесь таблицей, тест
   `LightVariantTests` держит имена).
2. С кадров (мерено), если дана папка: строка «Организаций» (`org.row.0`) — середина плашки к странице и самая
   тёмная полоса ≤ 10 pt под нижним краем; сегмент «Частные | Компании» — выбранное к жёлобу.
"""
import json
import os
import sys

W, K = 0xFFFFFF, 0x000000


def lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def Y(rgb):
    r, g, b = rgb
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def L(rgb):
    y = Y(rgb)
    f = y ** (1 / 3) if y > 0.008856 else 7.787 * y + 16 / 116
    return 116 * f - 16


def rgb(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


def over(fg, a, bg):
    return tuple(round(f * a + b * (1 - a)) for f, b in zip(rgb(fg), rgb(bg)))


def cr(a, b):
    ya, yb = Y(a if isinstance(a, tuple) else rgb(a)), Y(b if isinstance(b, tuple) else rgb(b))
    hi, lo = max(ya, yb), min(ya, yb)
    return (hi + 0.05) / (lo + 0.05)


def dl(a, b):
    a = a if isinstance(a, tuple) else rgb(a)
    b = b if isinstance(b, tuple) else rgb(b)
    return L(a) - L(b)


# Светлые значения: сейчас (Palette) и подмены вариантов (LightVariant.swift).
NOW = dict(surface=0xFAF8F3, bg=0xEDE9E1, sheet=W, sheet2=0xF1EDE4, sheet4=W, segOn=0xDDD6C8, ink=0x17150F,
           ink6=0x8C8578, ink7=0x9A9385, brass=0xA9721F, onBrass=W, pressBrass=0xF7E9CF, weekend=0x8A5A18, sel=None)
A = {**NOW, "surface": 0xF0ECE5, "bg": 0xE6E1D8, "sheet2": 0xF7F5F0, "segOn": W, "ink6": 0x6F685C, "ink7": 0x8E877A,
     "brass": 0x8F5D17}
N = {**NOW, "surface": 0xEDEDF0, "bg": 0xE3E3E7, "sheet2": 0xF6F6F8, "segOn": W, "ink": 0x141416, "ink6": 0x69696E,
     "ink7": 0x86868B, "sheet4": (W, 0.72)}
B = {**N, "brass": 0xE4570B, "pressBrass": 0xFFE7D9}
C = {**N, "brass": 0xE0282E, "pressBrass": 0xFDE3E3}
D = {**N, "brass": 0x3A6B0C, "pressBrass": 0xD6F66A, "fill": 0xC6F135}
VARIANTS = [("сейчас", NOW), ("А", A), ("Б", B), ("В-красный", C), ("В-зелёный", D)]


def f2(x):
    return f"{x:.2f}".replace(".", ",")


def f1(x):
    return f"{x:+.1f}".replace(".", ",")


def code_table():
    rows = []
    for name, v in VARIANTS:
        s, w = v["surface"], W
        s4 = v["sheet4"]
        s4c = over(s4[0], s4[1], s) if isinstance(s4, tuple) else rgb(s4)
        seg_trough = v["bg"] if v is not NOW else W
        rows.append([
            name,
            f"#{s:06X}",
            f"{f2(cr(w, s))} / {f1(dl(w, s))}",
            f"{f2(cr(s4c, s))} / {f1(dl(s4c, s))}",
            f"{f2(cr(v['sheet2'], s))} / {f1(dl(v['sheet2'], s))}",
            f2(cr(v["ink"], s)),
            f"{f2(cr(v['ink6'], w))} / {f2(cr(v['ink6'], s))}",
            f2(cr(v["ink7"], s)),
            f"{f2(cr(v['brass'], w))} / {f2(cr(v['brass'], s))}",
            f2(cr(W, v["brass"])) + (f" (чёрное на #{v['fill']:06X}: {f2(cr(0x141416, v['fill']))})" if "fill" in v else ""),
            f2(cr(v["brass"], v["pressBrass"])),
            f"{f2(cr(v['segOn'], seg_trough))} / {f1(dl(v['segOn'], seg_trough))}",
        ])
    head = ["вариант", "фон страницы", "белая плашка / фон", "плашка «Съёмок» / фон", "лист карточки / фон",
            "текст / фон", "пояснения на белом / на фоне", "подписи разделов / фон", "акцент текстом на белом / на фоне",
            "белое на акценте", "акцент на своей бледной заливке", "выбранный сегмент / жёлоб"]
    md = "| " + " | ".join(head) + " |\n|" + "---|" * len(head) + "\n"
    for r in rows:
        md += "| " + " | ".join(r) + " |\n"
    return md


def frame_table(root):
    from PIL import Image
    out = []
    for key, name in [("now", "сейчас"), ("A", "А"), ("B", "Б"), ("C", "В-красный"), ("D", "В-зелёный")]:
        d = os.path.join(root, key, "m28-orgs-light")
        if not os.path.exists(os.path.join(d, "native.png")):
            continue
        im = Image.open(os.path.join(d, "native.png")).convert("RGB")
        nodes = json.load(open(os.path.join(d, "native.json")))["nodes"]
        sx = im.size[0] / 440
        r = nodes["org.row.0"]
        cx = int((r["x"] + r["w"] * 0.6) * sx)
        mid = im.getpixel((cx, int((r["y"] + r["h"] / 2) * sx)))
        bottom = (r["y"] + r["h"]) * sx
        page = im.getpixel((cx, int(bottom + 40 * sx)))  # между строками — 8 pt; берём под последней? см. ниже
        # Страница: левее строк (поле 24 pt) на высоте середины строки.
        page = im.getpixel((int(6 * sx), int((r["y"] + r["h"] / 2) * sx)))
        band = [im.getpixel((cx, int(bottom + k))) for k in range(2, int(8 * sx))]  # до следующей строки 8 pt
        darkest = min(band, key=L)
        seg = [k for k in nodes if k.startswith("clk.seg.") or k.startswith("cls.seg.")]
        out.append([name, f"{f2(cr(mid, page))} / {f1(dl(mid, page))}", f1(L(darkest) - L(page)),
                    "#%02X%02X%02X" % page, "#%02X%02X%02X" % mid])
    head = ["вариант", "строка / страница (мерено)", "тень под краем, ΔL* (мерено, полоса 8 pt до соседа)",
            "страница на кадре", "плашка на кадре"]
    md = "| " + " | ".join(head) + " |\n|" + "---|" * len(head) + "\n"
    for r in out:
        md += "| " + " | ".join(r) + " |\n"
    return md


if __name__ == "__main__":
    print(code_table())
    if len(sys.argv) > 1:
        print(frame_table(sys.argv[1]))
