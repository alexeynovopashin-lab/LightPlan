#!/usr/bin/env python3
"""Сырой кэш Gaia DR3 (raw/) → файлы для приложения: stars_gaia.bin, milkyway_glow_gaia.png, spec.json.

    python3 Tools/milkyway_gaia/build.py [--out DIR] [--color flux|count]

Сети не нужно. Без raw/ (его качает fetch.py) — код 2 и подсказка. Случайных чисел нет: повтор прогона
даёт побайтно те же файлы (make milkywaygaia это проверяет).
"""
import argparse
import csv
import gzip
import io
import json
import math
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import color as COL  # noqa: E402
import common as C  # noqa: E402
import pngio  # noqa: E402

import numpy as np  # noqa: E402

PNG_LIMIT = 2.5e6           # байт, из задачи
BIN_LIMIT = 5.0e6
COLOR_MIN_STARS = 10        # ячейка с меньшим числом звёзд с цветом берёт цвет из сглаженной карты (σ 0,5°)
POOL_ABOVE = "round(1/cos b) ≥ 2, то есть |b| ≳ 48,2°"


def die(msg, code=2):
    print(msg, file=sys.stderr)
    sys.exit(code)


def load_meta():
    if not os.path.exists(C.RAW_META):
        die("нет сырого кэша Tools/milkyway_gaia/raw/ — сначала python3 Tools/milkyway_gaia/fetch.py (нужна сеть)")
    with open(C.RAW_META, encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------- яркие звёзды

def load_bright():
    cols = ("source_id", "l", "b", "phot_g_mean_mag", "bp_rp")
    parts = []
    for g0, g1 in C.BRIGHT_SLICES:
        path = os.path.join(C.RAW_BRIGHT, f"g_{g0:+05.1f}_{g1:04.1f}.csv.gz")
        if not os.path.exists(path):
            die(f"нет {os.path.relpath(path)} — python3 Tools/milkyway_gaia/fetch.py --what bright")
        with gzip.open(path) as f:
            rows = list(csv.reader(io.StringIO(f.read().decode("utf-8"))))
        ix = [rows[0].index(k) for k in cols]
        parts += [[r[i] for i in ix] for r in rows[1:]]
    sid = np.array([int(r[0]) for r in parts], dtype=np.int64)
    l = np.array([float(r[1]) for r in parts])
    b = np.array([float(r[2]) for r in parts])
    g = np.array([float(r[3]) for r in parts])
    c = np.array([float(r[4]) if r[4] else np.nan for r in parts])
    return sid, l, b, g, c


def default_color_by_g(g, c):
    """BP−RP по умолчанию для звезды без цвета: медиана BP−RP звёзд с цветом в том же интервале G шириной 0,5."""
    have = np.isfinite(c)
    edges = np.arange(np.floor(g.min() * 2) / 2, C.G_BRIGHT + 0.5 + 1e-9, 0.5)
    table = []
    out = c.copy()
    for lo, hi in zip(edges[:-1], edges[1:]):
        m = (g > lo) & (g <= hi)
        if not m.any():
            continue
        med = float(np.median(c[m & have])) if (m & have).any() else float(np.median(c[have]))
        miss = m & ~have
        out[miss] = med
        table.append({"g": [round(float(lo), 1), round(float(hi), 1)], "bp_rp": round(med, 3),
                      "missing": int(miss.sum())})
    return out, table


def build_stars(out_dir, meta):
    sid, l, b, g, c = load_bright()
    n = len(sid)
    server = meta.get("bright", {}).get("server_count")
    if server is not None and server != n:
        die(f"ярких звёзд в кэше {n}, сервер насчитал {server} — кэш неполон, перекачайте --what bright --force", 1)
    if len(np.unique(sid)) != n:
        die("в кэше ярких звёзд повторяются source_id", 1)
    order = np.lexsort((sid, g))                      # от ярких к слабым, при равной G — по source_id
    sid, l, b, g, c = sid[order], l[order], b[order], g[order], c[order]
    c_full, default_table = default_color_by_g(g, c)
    missing = ~np.isfinite(c)

    rec = np.zeros(n, dtype=C.BIN_DTYPE)
    rec["l"] = np.round(l * C.L_SCALE).astype(np.int64) % 65536
    rec["b"] = np.clip(np.round(b * C.B_SCALE), -32768, 32767).astype(np.int16)
    g_raw = np.round(g * C.G_SCALE)
    rec["g"] = np.clip(g_raw, 0, 255).astype(np.uint8)
    c_raw = np.round(c_full * C.C_SCALE) - C.C_OFFSET
    rec["c"] = np.clip(c_raw, -128, 127).astype(np.int8)
    rec["flags"] = np.where(missing, C.FLAG_COLOR_FROM_G, 0).astype(np.uint8)
    header = struct.pack("<4sHHIHH", C.BIN_MAGIC, C.BIN_VERSION, C.BIN_RECORD, n, int(round(C.G_BRIGHT * 10)), 0)
    path = os.path.join(out_dir, "stars_gaia.bin")
    with open(path, "wb") as f:
        f.write(header)
        f.write(rec.tobytes())
    size = os.path.getsize(path)
    if size > BIN_LIMIT:
        die(f"stars_gaia.bin {size} байт > {BIN_LIMIT:.0f} — поднимите порог G (задача: в пределах 5 МБ)", 1)

    # ошибка упаковки (для spec.json и отчёта)
    dl = (rec["l"] / C.L_SCALE - l + 180) % 360 - 180
    db = rec["b"] / C.B_SCALE - b
    info = {
        "count": n, "bytes": size,
        "g_min": round(float(g.min()), 4), "g_max": round(float(g.max()), 4),
        "g_clipped_below_0": int((g_raw < 0).sum()),
        "bp_rp_missing": int(missing.sum()), "bp_rp_default_by_g": default_table,
        "bp_rp_min": round(float(np.nanmin(c)), 3), "bp_rp_max": round(float(np.nanmax(c)), 3),
        "bp_rp_clipped": int(((c_raw < -128) | (c_raw > 127)).sum()),
        "pack_error_max_deg": {"l": round(float(np.abs(dl).max()), 5), "b": round(float(np.abs(db).max()), 5),
                               "g_mag": round(float(np.abs(rec["g"] / C.G_SCALE - np.clip(g, 0, 25.5)).max()), 3)},
        "n_brighter_g3": int((g < 3).sum()),
    }
    print(f"stars_gaia.bin: {n} звёзд G ≤ {C.G_BRIGHT:g} ({size / 1e6:.2f} МБ); без BP−RP {info['bp_rp_missing']}; "
          f"G {info['g_min']}…{info['g_max']}; ярче G 3 — {info['n_brighter_g3']}")
    return info


# ---------------------------------------------------------------- свечение

GLOW_COLS = ("il", "ib", "n", "f", "nc", "sc", "fc", "fn")
_EMPTY = re.compile(r"(?<=,)(?=,|$)", re.M)


def read_glow_chunk(path):
    with gzip.open(path) as f:
        text = f.read().decode("utf-8")
    head, _, body = text.partition("\n")
    if tuple(head.strip().split(",")) != GLOW_COLS:
        die(f"{os.path.relpath(path)}: шапка {head.strip()!r}, ждали {','.join(GLOW_COLS)}", 1)
    body = _EMPTY.sub("0", body)                       # SUM по одним NULL → пусто → 0 (nc при этом тоже 0)
    if not body.strip():
        return np.zeros((0, len(GLOW_COLS)))
    return np.loadtxt(io.StringIO(body), delimiter=",", ndmin=2)


def load_glow(meta):
    npix = 12 * 4 ** C.HPX_LEVEL
    shape = (C.CELLS_B, C.CELLS_L)
    acc = {k: np.zeros(shape) for k in GLOW_COLS[2:]}
    per_p0 = np.zeros(12, dtype=np.int64)
    missing = []
    for p in range(npix):
        path = os.path.join(C.RAW_GLOW, f"hpx{C.HPX_LEVEL}_{p:03d}.csv.gz")
        if not os.path.exists(path):
            missing.append(p)
            continue
        a = read_glow_chunk(path)
        il = a[:, 0].astype(int)
        ib = np.minimum(a[:, 1].astype(int), C.CELLS_B - 1)      # b = +90° ровно → верхняя ячейка
        row, col = C.cell_to_pixel(il, ib)
        for k, name in enumerate(GLOW_COLS[2:], start=2):
            np.add.at(acc[name], (row, col), a[:, k])
        per_p0[p // 4 ** C.HPX_LEVEL] += int(a[:, 2].sum())
    if missing:
        die(f"нет {len(missing)} кусков свечения (например, {missing[:5]}) — python3 Tools/milkyway_gaia/fetch.py "
            f"--what glow докачает только их")
    control = meta.get("glow_control", {}).get("counts", {})
    check = []
    for p0 in range(12):
        srv = control.get(str(p0))
        check.append({"healpix0": p0, "cells_sum": int(per_p0[p0]), "server_count": srv})
        if srv is not None and srv != per_p0[p0]:
            die(f"HEALPix-0 {p0}: в ячейках {per_p0[p0]} звёзд, сервер насчитал {srv} — кэш неполон", 1)
    return acc, check, len(control) == 12


def cell_solid_angle_deg2(h, w):
    """Телесный угол ячейки строки j, кв. градусы: Δl · (sin b_верх − sin b_низ)."""
    edges = np.radians(90.0 - np.arange(h + 1) * 180.0 / h)
    return (360.0 / w) * (180.0 / math.pi) * (np.sin(edges[:-1]) - np.sin(edges[1:]))


def pool_widths(h):
    """Сколько соседних ячеек по долготе объединять в строке: настоящая ширина ячейки 0,125°·cos b, у полюса
    в ячейку попадает меньше звезды — объединяем round(1/cos b) ячеек (нечётное число, окно по центру)."""
    _, b = C.grid(h, 2 * h)
    n = np.maximum(1, np.round(1.0 / np.cos(np.radians(b)))).astype(int)
    return np.where(n % 2 == 0, n + 1, n)


def pool_rows(a, widths):
    """Скользящая сумма по долготе с окном widths[j] (кольцо)."""
    out = a.copy()
    for j in np.flatnonzero(widths > 1):
        r = widths[j] // 2
        row = np.concatenate([a[j, -r:], a[j], a[j, :r]])
        cs = np.concatenate([[0.0], np.cumsum(row)])
        out[j] = cs[2 * r + 1:] - cs[:-2 * r - 1]
    return out


def glow_rgb(acc, color_mode, table):
    """Суммы по ячейкам 2880 × 1440 → линейный RGB: поверхностная яркость (поток на кв. градус) × оттенок
    чёрного тела по среднему BP−RP ячейки. Возвращает (rgb, доля ячеек с цветом из сглаженной карты)."""
    h, w = acc["f"].shape
    omega = cell_solid_angle_deg2(h, w)[:, None]
    widths = pool_widths(h)
    F = pool_rows(acc["f"], widths)
    area = pool_rows(np.broadcast_to(omega, (h, w)).copy(), widths)
    S = F / area                                                  # поток звёзд G 10…21 на кв. градус
    if color_mode == "flux":
        num, den = pool_rows(acc["fc"], widths), pool_rows(acc["fn"], widths)
    else:
        num, den = pool_rows(acc["sc"], widths), pool_rows(acc["nc"], widths)
    nc = pool_rows(acc["nc"], widths)
    c_cell = np.where(den > 0, num / np.where(den > 0, den, 1), np.nan)
    sm_num, sm_den = C.smooth(num, 0.5), C.smooth(den, 0.5)
    c_smooth = sm_num / np.where(sm_den > 0, sm_den, np.nan)
    use_cell = (nc >= COLOR_MIN_STARS) & np.isfinite(c_cell)
    c_map = np.where(use_cell, c_cell, c_smooth)
    c_map = np.where(np.isfinite(c_map), c_map, np.nanmedian(c_cell))
    return S[..., None] * COL.chroma_from_bprp(c_map, table), float((~use_cell).mean())


def load_grid_cache():
    """Суммы по ячейкам, сохранённые build.py (raw/glow_grid.npz); None, если кэша нет."""
    if not os.path.exists(C.GRID_CACHE):
        return None
    with np.load(C.GRID_CACHE) as z:
        return {k: z[k].astype(np.float64) for k in z.files}


def build_glow(out_dir, meta, color_mode):
    acc, control, control_full = load_glow(meta)
    h, w = C.CELLS_B, C.CELLS_L
    np.savez(C.GRID_CACHE, **{k: v.astype(np.float32) for k, v in acc.items()})      # кэш для preview
    table = COL.bv_table(C.COLOR_FILE)
    rgb, smoothed_frac = glow_rgb(acc, color_mode, table)

    # Полная сетка 2880 × 1440 пишется в сырой кэш всегда (в репозиторий не идёт); в приложение — она же, если
    # влезает в 2,5 МБ, иначе вдвое меньше (правило задачи).
    size_px = (w, h)
    png_path = os.path.join(out_dir, "milkyway_glow_gaia.png")
    s_max = float(rgb.max())
    img = np.round(np.clip(rgb / s_max, 0, 1) * 65535).astype(np.uint16)
    nbytes_full = pngio.write_png16(C.FULL_PNG, img)
    s_max_full = s_max
    downsampled = nbytes_full > PNG_LIMIT
    if downsampled:
        print(f"milkyway_glow_gaia.png 2880×1440: {nbytes_full / 1e6:.2f} МБ > 2,5 МБ — понижаю до 1440×720 "
              f"(полная — {os.path.relpath(C.FULL_PNG)})")
        rgb = C.downsample2(rgb)
        s_max = float(rgb.max())
        img = np.round(np.clip(rgb / s_max, 0, 1) * 65535).astype(np.uint16)
        size_px = (w // 2, h // 2)
    nbytes = pngio.write_png16(png_path, img)
    print(f"milkyway_glow_gaia.png: {size_px[0]}×{size_px[1]}, {nbytes / 1e6:.2f} МБ; "
          f"1,0 = поток звезды G {-2.5 * math.log10(s_max):.3f} на кв. градус")
    return {
        "size": list(size_px), "bytes": nbytes, "downsampled_from_2880x1440": downsampled,
        "bytes_2880x1440": nbytes_full, "s_max_2880x1440": s_max_full,
        "s_max_flux_per_deg2": s_max, "g_equiv_of_1_per_deg2": round(-2.5 * math.log10(s_max), 4),
        "stars": int(acc["n"].sum()), "stars_with_bp_rp": int(acc["nc"].sum()),
        "cells_empty": int((acc["n"] == 0).sum()),
        "color_from_smoothed_pct": round(100.0 * smoothed_frac, 3),
        "control": control, "control_complete": control_full,
        "bv_table": table, "color_mode": color_mode,
    }


# ---------------------------------------------------------------- spec.json

def write_spec(out_dir, meta, stars, glow):
    W, H = glow["size"]
    spec = {
        "what": "Млечный Путь из каталога Gaia DR3: яркие звёзды точками и свечение слабых звёзд картой "
                "(Tools/milkyway_gaia/README.md)",
        "source": {
            "catalogue": "Gaia DR3, таблица gaiadr3.gaia_source", "archive": C.TAP_ESA,
            "fetched_utc": {k: meta[k]["fetched_utc"] for k in ("bright", "glow", "color") if k in meta},
            "license": "CC BY-NC 3.0 IGO (https://www.cosmos.esa.int/web/gaia-users/license); коммерческое "
                       "использование — только с разрешения ESA (data.licences@esa.int), см. README",
            "credit": "Credit: ESA, Gaia DPAC",
            "changes": "производные данные: выборка G ≤ 10 с упаковкой и суммы потока по ячейкам 0,125°; "
                       "это не исходный каталог",
        },
        "stars": {
            "file": "stars_gaia.bin",
            "selection": f"все источники Gaia DR3 с phot_g_mean_mag ≤ {C.G_BRIGHT:g}",
            "count": stars["count"], "bytes": stars["bytes"],
            "byte_order": "little-endian",
            "header": {
                "size": C.BIN_HEADER,
                "fields": [
                    {"offset": 0, "type": "char[4]", "name": "magic", "value": C.BIN_MAGIC.decode()},
                    {"offset": 4, "type": "uint16", "name": "version", "value": C.BIN_VERSION},
                    {"offset": 6, "type": "uint16", "name": "record_size", "value": C.BIN_RECORD},
                    {"offset": 8, "type": "uint32", "name": "count", "value": stars["count"]},
                    {"offset": 12, "type": "uint16", "name": "g_limit_x10", "value": int(round(C.G_BRIGHT * 10))},
                    {"offset": 14, "type": "uint16", "name": "reserved", "value": 0},
                ],
            },
            "record": {
                "size": C.BIN_RECORD,
                "fields": [
                    {"offset": 0, "type": "uint16", "name": "l", "decode": "l° = raw · 360 / 65536",
                     "step_deg": 360 / 65536},
                    {"offset": 2, "type": "int16", "name": "b", "decode": "b° = raw · 180 / 65536",
                     "step_deg": 180 / 65536},
                    {"offset": 4, "type": "uint8", "name": "g", "decode": "G = raw / 10 (0…25,5)"},
                    {"offset": 5, "type": "int8", "name": "bp_rp",
                     "decode": f"BP−RP = (raw + {C.C_OFFSET}) / 10 (−12,8…+12,7)", "offset_tenths": C.C_OFFSET},
                    {"offset": 6, "type": "uint8", "name": "flags",
                     "bits": {"0": "BP−RP у звезды нет, записан типичный для её G (bp_rp_default_by_g)",
                              "1-7": "0, резерв"}},
                    {"offset": 7, "type": "uint8", "name": "reserved", "value": 0},
                ],
            },
            "order": "по G от ярких к слабым (при равной G — по source_id): первые N записей — N самых ярких",
            "metal": "struct { ushort l; short b; uchar g; char bp_rp; uchar flags; uchar pad; } — 8 байт, "
                     "буфер со смещением 16",
            "g_range": [stars["g_min"], stars["g_max"]],
            "pack_error_max_deg": stars["pack_error_max_deg"],
            "bp_rp_missing": stars["bp_rp_missing"], "bp_rp_default_by_g": stars["bp_rp_default_by_g"],
            "bp_rp_range": [stars["bp_rp_min"], stars["bp_rp_max"]], "bp_rp_clipped": stars["bp_rp_clipped"],
            "g_clipped_below_0": stars["g_clipped_below_0"],
            "bright_incomplete": f"ярче G ≈ 3 Gaia неполна (насыщение детектора): в файле таких {stars['n_brighter_g3']}, "
                                 "их фотометрия и даже наличие ненадёжны. Самые яркие звёзды даёт каталог "
                                 "приложения (ConstellationCatalog + BrightStars, V ≤ 2,5); звёзды ярче G 3 из "
                                 "этого файла рисовать не стоит, либо снимать дубли по расстоянию",
            "positions": "галактические l, b Gaia DR3 (из ICRS, эпоха J2016.0); собственное движение не учтено: "
                         "сдвиг за 10 лет больше половины шага упаковки l (≈ 10″) у звёзд быстрее 1″/год — таких "
                         f"{meta.get('bright', {}).get('server_count_pm_gt_1as', '?')} (запрос в raw/meta.json)",
        },
        "glow": {
            "file": "milkyway_glow_gaia.png", "format": "PNG, 16 бит на канал, RGB, без гаммы (линейные значения)",
            "size": glow["size"], "bytes": glow["bytes"],
            "downsampled_from_2880x1440": glow["downsampled_from_2880x1440"],
            "selection": f"источники Gaia DR3 с {C.G_BRIGHT:g} < G ≤ {C.G_FAINT:g}: {glow['stars']} звёзд, "
                         f"из них с BP−RP {glow['stars_with_bp_rp']}",
            "projection": "равнопромежуточная (plate carrée), галактические координаты l, b",
            "u": {"formula": "u = fract(0.5 − l/360)", "l0_at_u": 0.5,
                  "direction": "l = 0 посередине, долгота растёт ВЛЕВО (u убывает), как у карт NASA SVS; "
                               "u = 0 и u = 1 — l = 180°",
                  "pixel_center": f"столбец i = 0…{W - 1}: l = 180 − (i + 0,5)·360/{W} (mod 360)"},
            "v": {"formula": "v = 0.5 − b/180", "top": "v = 0 — b = +90° (северный полюс Галактики)",
                  "pixel_center": f"строка j = 0…{H - 1} сверху вниз: b = 90 − (j + 0,5)·180/{H}"},
            "sampling": "значение относится к центру пикселя; читать билинейно, по u — с повтором (repeat)",
            "value": "линейная поверхностная яркость: суммарный поток Σ 10^(−0,4·G) звёзд ячейки, делённый на "
                     "телесный угол ячейки; яркость Y = 0,2126 R + 0,7152 G + 0,0722 B; максимум канала по карте = 1,0",
            "scale": {"one_equals_flux_per_deg2": glow["s_max_flux_per_deg2"],
                      "one_equals_g_mag_per_deg2": glow["g_equiv_of_1_per_deg2"],
                      "meaning": "значение 1,0 по каналу = поток звезды G = one_equals_g_mag_per_deg2 на кв. "
                                 "градус: так свечение и точки stars_gaia.bin ставятся в одну шкалу"},
            "pooling": f"у полюсов ячейка 0,125° по долготе сужается как cos b; там соседние ячейки по долготе "
                       f"объединены (окно — нечётное round(1/cos b), {POOL_ABOVE}), чтобы настоящая ширина ячейки "
                       f"была ≥ 0,125°",
            "color": {
                "mode": glow["color_mode"],
                "mean": ("средний BP−RP, взвешенный потоком: Σ F·(BP−RP) / Σ F по звёздам ячейки с цветом"
                         if glow["color_mode"] == "flux" else
                         "средний BP−RP по числу звёзд: AVG(bp_rp) = Σ (BP−RP) / N по звёздам ячейки с цветом"),
                "few_stars": f"ячейка, где звёзд с цветом меньше {COLOR_MIN_STARS}, берёт цвет из карты, сглаженной "
                             f"гауссом σ 0,5° ({glow['color_from_smoothed_pct']} % ячеек)",
                "bp_rp_to_b_v": {"rule": "медиана B−V Hipparcos в интервалах BP−RP по 0,1, неубывающая; линейно "
                                         "между узлами, за краями — крайнее значение",
                                 "bp_rp": glow["bv_table"]["bp_rp"], "b_v": glow["bv_table"]["b_v"],
                                 "stars": glow["bv_table"]["used"]},
                "temperature": "T = 4600 K·(1/(0,92(B−V) + 1,7) + 1/(0,92(B−V) + 0,62)) (Ballesteros 2012), "
                               f"в пределах {COL.T_MIN:.0f}…{COL.T_MAX:.0f} K",
                "rgb": "спектр чёрного тела T × кривые CIE 1931 (Wyman et al. 2013) → XYZ → линейный sRGB; "
                       f"белая точка — чёрное тело {COL.T_WHITE:.0f} K = (1, 1, 1); оттенок нормирован на Y = 1, "
                       "яркость — поверхностная яркость ячейки",
                "same_for_stars": "этим же правилом приложение может красить точки stars_gaia.bin",
            },
        },
    }
    path = os.path.join(out_dir, "spec.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(spec, f, ensure_ascii=False, indent=1)
        f.write("\n")
    return spec


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=C.HERE, help="куда писать (по умолчанию — папка инструмента)")
    ap.add_argument("--color", choices=("flux", "count"), default="flux",
                    help="средний цвет ячейки: flux — взвешенный потоком (по умолчанию), count — AVG(bp_rp)")
    args = ap.parse_args()
    meta = load_meta()
    os.makedirs(args.out, exist_ok=True)
    stars = build_stars(args.out, meta)
    glow = build_glow(args.out, meta, args.color)
    write_spec(args.out, meta, stars, glow)
    with open(os.path.join(C.RAW, "build_info.json"), "w", encoding="utf-8") as f:
        json.dump({"stars": stars, "glow": {k: v for k, v in glow.items() if k != "bv_table"}}, f,
                  ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
