#!/usr/bin/env python3
"""Картинки для глаза из файлов приложения (milkyway_glow_gaia.png + stars_gaia.bin) → previews/. Без подписей.

    python3 Tools/milkyway_gaia/preview.py [--dir DIR] [--out DIR]

  sky_gaia.jpg              всё небо, только свечение, тонирование I_out = 1 − exp(−k·I), ядро → 0,6
  view_core_l0.jpg          «камера телефона»: прямолинейная проекция 90° × 60°, центр l = 0°, b = 0°, верх — север
  view_cygnus_l80.jpg       то же, Лебедь, l = 80°
  view_crux_l303.jpg        то же, Южный Крест и Угольный Мешок, l = 303°
  zoom_core_20x13.jpg       кусок 20° × 13° у ядра (l = 0°, b = 0°), та же проекция, карта для приложения
  zoom_core_20x13_2880.jpg  тот же кусок из полной сетки 2880 × 1440 (0,125°) — она не влезла в 2,5 МБ и лежит
                            только в сыром кэше; картинка — чтобы видеть, что теряет понижение до 1440 × 720

На видах поверх свечения — точки stars_gaia.bin: радиус от G, цвет от BP−RP (то же правило цвета, что у карты).
JPEG качества 95 без прореживания цвета: вчетверо легче PNG (россыпь звёзд плохо жмётся), ошибка 1–2 уровня из 255.
"""
import argparse
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import color as COL  # noqa: E402
import common as C  # noqa: E402
import pngio  # noqa: E402

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

TONE_CORE = 0.6       # ядро → 0,6 (Алексей, «скромнее»)
CORE_BOX = 10.0       # яркость ядра — 99,9-й перцентиль сглаженной (σ 1°) Y в |l|, |b| ≤ 10°

VIEWS = [
    ("view_core_l0.jpg", 0.0, 0.0, 90.0, 60.0, 1800),
    ("view_cygnus_l80.jpg", 80.0, 0.0, 90.0, 60.0, 1800),
    ("view_crux_l303.jpg", 303.0, 0.0, 90.0, 60.0, 1800),
    ("zoom_core_20x13.jpg", 0.0, 0.0, 20.0, 13.0, 1800),
]


def tone_k(rgb):
    Y = C.smooth(rgb @ C.LUMA, 1.0)
    l, b = C.grid(*Y.shape)
    m = (np.abs(b)[:, None] <= CORE_BOX) & (np.abs(C.signed(l))[None, :] <= CORE_BOX)
    core = float(np.percentile(Y[m], 99.9))
    return -math.log(1 - TONE_CORE) / core, core


def tone(rgb, k):
    """I_out = 1 − exp(−k·I) по яркости Y, оттенок сохраняется: out_c = I_c · (1 − exp(−k·Y)) / Y."""
    Y = rgb @ C.LUMA
    Yc = np.maximum(Y, 1e-30)
    f = np.where(Y > 0, -np.expm1(-k * Yc) / Yc, 0.0)
    return np.clip(rgb * f[..., None], 0, 1)


def save(img, path):
    Image.fromarray(to8(img)).save(path, quality=95, subsampling=0)


def to8(v):
    """Тонированное значение пишется в 8 бит напрямую, без кривой sRGB (как в PR #5): ядро 0,6 → 153 из 255."""
    return np.round(np.clip(v, 0, 1) * 255).astype(np.uint8)


def unit(l, b):
    l, b = np.radians(l), np.radians(b)
    return np.stack([np.cos(b) * np.cos(l), np.cos(b) * np.sin(l), np.sin(b)], axis=-1)


def camera(l0, b0):
    f = unit(l0, b0)
    r = np.cross(f, [0.0, 0.0, 1.0])
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return f, r, u


def render_view(rgb_toned, stars, star_rgb, l0, b0, hfov, vfov, width):
    tx, ty = math.tan(math.radians(hfov / 2)), math.tan(math.radians(vfov / 2))
    height = int(round(width * ty / tx))
    f, r, u = camera(l0, b0)
    xs = (2 * (np.arange(width) + 0.5) / width - 1) * tx
    ys = (1 - 2 * (np.arange(height) + 0.5) / height) * ty
    X, Yy = np.meshgrid(xs, ys)
    d = f + X[..., None] * r + Yy[..., None] * u
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    l = np.degrees(np.arctan2(d[..., 1], d[..., 0])) % 360
    b = np.degrees(np.arcsin(np.clip(d[..., 2], -1, 1)))
    img = C.sample(rgb_toned, l, b)

    # звёзды: проекция на ту же плоскость, круг с мягким краем; радиус и яркость от G
    v = unit(stars["l"], stars["b"])
    z = v @ f
    front = z > 0.05
    px = ((v[front] @ r) / z[front] / tx + 1) * width / 2 - 0.5
    py = (1 - (v[front] @ u) / z[front] / ty) * height / 2 - 0.5
    g = stars["g"][front]
    col = star_rgb[front]
    inside = (px > -4) & (px < width + 3) & (py > -4) & (py < height + 3)
    px, py, g, col = px[inside], py[inside], g[inside], col[inside]
    rad = 0.55 + 0.32 * np.clip(10 - g, 0, 9)              # G 10 → 0,55 пкс, G 4 → 2,5 пкс, G ≤ 1 → 3,4 пкс
    amp = np.clip(10 ** (-0.2 * (g - 5)), 0.15, 1.0)         # корень из потока: G ≤ 5 → 1, G 7 → 0,4, G ≥ 9,1 → 0,15
    layer = np.zeros_like(img)
    for oy in range(-4, 5):
        for ox in range(-4, 5):
            ix = np.round(px).astype(int) + ox
            iy = np.round(py).astype(int) + oy
            dist = np.hypot(ix - px, iy - py)
            cov = np.clip(rad + 0.5 - dist, 0, 1)
            ok = (cov > 0) & (ix >= 0) & (ix < width) & (iy >= 0) & (iy < height)
            np.add.at(layer, (iy[ok], ix[ok]), (amp[ok] * cov[ok])[:, None] * col[ok])
    out = 1 - (1 - img) * (1 - np.clip(layer, 0, 1))        # «экран»: звезда не тонет в ярком свечении
    return out, int(inside.sum())


def load_full(spec):
    """Полная карта 2880 × 1440 из сырого кэша в шкале карты приложения (или None)."""
    info_path = os.path.join(C.RAW, "build_info.json")
    if not (os.path.exists(C.FULL_PNG) and os.path.exists(info_path)):
        return None
    with open(info_path, encoding="utf-8") as f:
        s_full = json.load(f)["glow"]["s_max_2880x1440"]
    s_app = spec["glow"]["scale"]["one_equals_flux_per_deg2"]
    return pngio.read_png16(C.FULL_PNG).astype(float) / 65535.0 * (s_full / s_app)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default=C.HERE)
    ap.add_argument("--out", default=os.path.join(C.HERE, "previews"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    rgb = pngio.read_png16(os.path.join(args.dir, "milkyway_glow_gaia.png")).astype(float) / 65535.0
    stars = C.read_bin(os.path.join(args.dir, "stars_gaia.bin"))
    with open(os.path.join(args.dir, "spec.json"), encoding="utf-8") as f:
        spec = json.load(f)
    k, core = tone_k(rgb)
    toned = tone(rgb, k)
    table = {"bp_rp": spec["glow"]["color"]["bp_rp_to_b_v"]["bp_rp"],
             "b_v": spec["glow"]["color"]["bp_rp_to_b_v"]["b_v"]}
    ch = COL.chroma_from_bprp(stars["c"], table)
    star_rgb = ch / ch.max(axis=1, keepdims=True)            # для точки: самый яркий канал = 1

    info = {"tone": {"rule": "I_out = 1 − exp(−k·I) по яркости Y, оттенок сохраняется", "k": k, "core_Y": core,
                     "core_out": TONE_CORE, "core_def": f"99,9-й перцентиль сглаженной (σ 1°) Y в |l|, |b| ≤ {CORE_BOX:g}°"},
            "files": {}}
    save(toned, os.path.join(args.out, "sky_gaia.jpg"))
    info["files"]["sky_gaia.jpg"] = {"size": list(toned.shape[1::-1])}
    for name, l0, b0, hf, vf, w in VIEWS:
        img, n = render_view(toned, stars, star_rgb, l0, b0, hf, vf, w)
        save(img, os.path.join(args.out, name))
        info["files"][name] = {"center_l": l0, "center_b": b0, "fov_deg": [hf, vf], "size": list(img.shape[1::-1]),
                               "stars_drawn": n}
        print(f"{name}: {img.shape[1]}×{img.shape[0]}, звёзд {n}")
    full = load_full(spec)
    if full is not None:
        name, l0, b0, hf, vf, w = VIEWS[-1]
        name = name.replace(".jpg", "_2880.jpg")
        img, n = render_view(tone(full, k), stars, star_rgb, l0, b0, hf, vf, w)
        save(img, os.path.join(args.out, name))
        info["files"][name] = {"center_l": l0, "center_b": b0, "fov_deg": [hf, vf], "size": list(img.shape[1::-1]),
                               "stars_drawn": n, "glow": "полная сетка 2880×1440 из сырого кэша, та же шкала и k"}
        print(f"{name}: {img.shape[1]}×{img.shape[0]}, звёзд {n}")
    else:
        print("полной сетки 2880×1440 в сыром кэше нет — zoom_core_20x13_2880.jpg не построен")
    for name in info["files"]:
        info["files"][name]["bytes"] = os.path.getsize(os.path.join(args.out, name))
    with open(os.path.join(args.out, "previews.json"), "w", encoding="utf-8") as f:
        json.dump(info, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"тонирование: k = {k:.4f} (ядро Y = {core:.5f} → {TONE_CORE})")


if __name__ == "__main__":
    main()
