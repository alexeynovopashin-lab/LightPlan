#!/usr/bin/env python3
"""28к.3: тёмная тема не изменилась — попиксельная сверка двух прогонов `pair.js`.

    python3 dark_diff.py <папка A> <папка B> [--tag dark] [--control <второй прогон A>]

Для каждого сценария с `dark` в имени, что есть в обеих папках: байты `native.png` равны? Если нет — сколько пикселей
отличается, на сколько уровней (макс. по каналу) и в какой полосе по вертикали (pt, кадр ×3 → 440 pt). Для контроля
сравнивают дважды снятый один и тот же старый билд: так видно «живые» места (двоеточие студийного часа, свечение,
цвет подборок мудборда), которые отличаются сами от себя.
"""
import hashlib
import os
import sys

from PIL import Image, ImageChops


def scen(root, tag):
    return sorted(d for d in os.listdir(root) if tag in d and os.path.exists(os.path.join(root, d, "native.png")))


def live_mask(a, c, s):
    """Где старый билд отличается сам от себя (два прогона a и c): расширено на 9 px."""
    from PIL import ImageFilter
    d = ImageChops.difference(Image.open(os.path.join(a, s, "native.png")).convert("RGB"),
                              Image.open(os.path.join(c, s, "native.png")).convert("RGB")).convert("L").point(lambda v: 255 if v else 0)
    return d.filter(ImageFilter.MaxFilter(9))


def main(a, b, tag="dark", control=None):
    rows = []
    for s in scen(a, tag):
        pa, pb = os.path.join(a, s, "native.png"), os.path.join(b, s, "native.png")
        if not os.path.exists(pb):
            rows.append((s, "нет в B", "", "", ""))
            continue
        if hashlib.md5(open(pa, "rb").read()).digest() == hashlib.md5(open(pb, "rb").read()).digest():
            rows.append((s, "байт в байт", 0, "", ""))
            continue
        ia, ib = Image.open(pa).convert("RGB"), Image.open(pb).convert("RGB")
        if ia.size != ib.size:
            rows.append((s, "размеры разные", "", "", ""))
            continue
        diff = ImageChops.difference(ia, ib)
        bbox = diff.getbbox()
        if bbox is None:
            rows.append((s, "пиксели равны (байты разные — метаданные png)", 0, "", ""))
            continue
        px = diff.convert("L").point(lambda v: 255 if v else 0)
        n = sum(1 for v in px.getdata() if v)
        mx = max(max(c) for c in (diff.getextrema(),) for c in [[e[1] for e in c]])
        sc = ia.size[0] / 440
        where = f"{bbox[1] / sc:.0f}–{bbox[3] / sc:.0f} pt, x {bbox[0] / sc:.0f}–{bbox[2] / sc:.0f} pt"
        if control:
            only = ImageChops.subtract(px, live_mask(a, control, s))
            ob = only.getbbox()
            k = sum(1 for v in only.getdata() if v)
            where += f"; **вне живых мест (по контролю): {k} px**" + (f" в {ob[1] / sc:.0f}–{ob[3] / sc:.0f} pt" if ob else "")
        rows.append((s, "отличается", n, f"{mx}", where))
    print("| сценарий | итог | пикселей | макс. уровней | где |\n|---|---|---|---|---|")
    for r in rows:
        print("| " + " | ".join(str(x) for x in r) + " |")


if __name__ == "__main__":
    t = sys.argv[sys.argv.index("--tag") + 1] if "--tag" in sys.argv else "dark"
    c = sys.argv[sys.argv.index("--control") + 1] if "--control" in sys.argv else None
    main(sys.argv[1], sys.argv[2], t, c)
