#!/usr/bin/env python3
"""28к.3: числа с кадров `pair.js --native-only` (светлая тема): было (main d468b34) | стало.

    python3 measure.py <папка was> <папка now>

Мерено на кадрах (×3, 1320×2868; 440 pt):
 · «Организации»: середина строки к полю страницы левее строк; самая тёмная полоса ≤ 8 pt под нижним краем строки (тень);
   выбранный сегмент «Компании» к жёлобу;
 · «Съёмки», месяц: выбранный день 23 к подложке месяца; кнопка «Съёмка» к подложке под ней;
 · карточка: плитка «Место» к листу, тень под плиткой (6 pt);
 · текст: цвет самого контрастного пикселя внутри рамки узла (середина штриха; у тонкого шрифта чуть светлее настоящего
   цвета, поэтому число — нижняя оценка) и его контраст к фону рядом.
"""
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from code_numbers import L, cr, dl, f1, f2  # noqa: E402


def load(root, scen):
    d = os.path.join(root, scen)
    im = Image.open(os.path.join(d, "native.png")).convert("RGB")
    n = json.load(open(os.path.join(d, "native.json")))["nodes"]
    return im, n, im.size[0] / 440


def px(im, sx, x, y):
    return im.getpixel((int(x * sx), int(y * sx)))


def hexs(c):
    return "#%02X%02X%02X" % c


def darkest_below(im, sx, cx, bottom, pts):
    band = [im.getpixel((int(cx), int(bottom * sx + k))) for k in range(2, int(pts * sx))]
    return min(band, key=L)


def ink_of(im, sx, node, inset=0):
    """Самый контрастный к фону пиксель внутри рамки узла и фон (пиксель в углу рамки)."""
    x0, y0 = int(node["x"] * sx), int(node["y"] * sx)
    x1, y1 = int((node["x"] + node["w"]) * sx), int((node["y"] + node["h"]) * sx)
    bg = im.getpixel((x0 + 1, y0 + 1))
    best, bd = bg, -1
    for y in range(y0, min(y1, im.size[1])):
        for x in range(x0, min(x1, im.size[0])):
            p = im.getpixel((x, y))
            d = sum((a - b) ** 2 for a, b in zip(p, bg))
            if d > bd:
                best, bd = p, d
    return best, bg


def rows(root):
    r = {}
    im, n, sx = load(root, "m28-orgs-light")
    o = n["org.row.0"]
    cx = (o["x"] + o["w"] * 0.6) * sx
    mid = px(im, sx, o["x"] + o["w"] * 0.6, o["y"] + o["h"] / 2)
    page = px(im, sx, 6, o["y"] + o["h"] / 2)
    dark = darkest_below(im, sx, cx, o["y"] + o["h"], 8)
    r["org_row"] = (cr(mid, page), dl(mid, page), L(dark) - L(page), page, mid)
    t = n["cl.tab.1"]
    y = t["y"] + t["h"] / 2
    thumb, trough = px(im, sx, t["x"] + 4, y), px(im, sx, t["x"] - 1.5, y)
    r["segment"] = (cr(thumb, trough), dl(thumb, trough), thumb, trough)

    im, n, sx = load(root, "planner-month-light")
    c = n["cal.n.23-0"]
    sel = px(im, sx, c["x"] + c["w"] / 2, c["y"] + 3)
    plate = px(im, sx, c["x"] - 8, c["y"] + c["h"] / 2)
    r["sel_day"] = (cr(sel, plate), dl(sel, plate), sel, plate)
    s = n["st.shoot"]
    btn = px(im, sx, s["x"] + 8, s["y"] + s["h"] / 2)
    under = px(im, sx, s["x"] + 8, s["y"] + s["h"] + 5)
    r["shoot_btn"] = (cr(btn, under), dl(btn, under), btn, under)

    im, n, sx = load(root, "card-people-during-light")
    b = n["card.block.place"]
    cxp = (b["x"] + b["w"] * 0.5)
    tile = px(im, sx, cxp, b["y"] + b["h"] / 2)
    sheet = px(im, sx, b["x"] - 5, b["y"] + b["h"] / 2)
    dark = darkest_below(im, sx, cxp * sx, b["y"] + b["h"], 6)
    r["card_tile"] = (cr(tile, sheet), dl(tile, sheet), L(dark) - L(sheet), sheet, tile)
    txt = {}
    for key in ("card.tel", "card.studioTel", "card.name"):
        if key in n:
            ink, bg = ink_of(im, sx, n[key])
            txt[key] = (cr(ink, bg), ink, bg)
    r["text"] = txt
    return r


def main(was, now):
    A, B = rows(was), rows(now)
    out = ["| что | было | стало | норма |", "|---|---|---|---|"]
    def line(name, a, b, norm):
        out.append(f"| {name} | {a} | {b} | {norm} |")
    line("строка «Организаций» / страница (отн. / ΔL*)", f"{f2(A['org_row'][0])} / {f1(A['org_row'][1])}", f"{f2(B['org_row'][0])} / {f1(B['org_row'][1])}", "≥ 1,12 и ΔL* ≥ 4, иначе тень")
    line("тень под строкой, ΔL* (полоса 8 pt)", f1(A['org_row'][2]), f1(B['org_row'][2]), "≤ −6")
    line("фон страницы на кадре", hexs(A['org_row'][3]), hexs(B['org_row'][3]), "")
    line("выбранный сегмент / жёлоб", f"{f2(A['segment'][0])} / {f1(A['segment'][1])}", f"{f2(B['segment'][0])} / {f1(B['segment'][1])}", "≥ 1,2 и ΔL* ≥ 7")
    line("выбранный день 23 / подложка месяца", f"{f2(A['sel_day'][0])} / {f1(A['sel_day'][1])}", f"{f2(B['sel_day'][0])} / {f1(B['sel_day'][1])}", "≥ 1,2 и ΔL* ≥ 7")
    line("«Съёмка» (включена) / подложка под ней", f"{f2(A['shoot_btn'][0])} / {f1(A['shoot_btn'][1])}", f"{f2(B['shoot_btn'][0])} / {f1(B['shoot_btn'][1])}", "≥ 1,2 и ΔL* ≥ 7")
    line("плитка «Место» карточки / лист", f"{f2(A['card_tile'][0])} / {f1(A['card_tile'][1])}", f"{f2(B['card_tile'][0])} / {f1(B['card_tile'][1])}", "≥ 1,12 и ΔL* ≥ 4, иначе тень")
    line("тень под плиткой карточки, ΔL* (6 pt)", f1(A['card_tile'][2]), f1(B['card_tile'][2]), "≤ −6")
    for k in sorted(set(A['text']) | set(B['text'])):
        a, b = A['text'].get(k), B['text'].get(k)
        fa = f"{hexs(a[1])} на {hexs(a[2])} → {f2(a[0])}" if a else "—"
        fb = f"{hexs(b[1])} на {hexs(b[2])} → {f2(b[0])}" if b else "—"
        line(f"текст {k}: цвет штриха на фоне → контраст", fa, fb, "≥ 4,5 (мелкий)")
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
