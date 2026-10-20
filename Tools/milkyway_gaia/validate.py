#!/usr/bin/env python3
"""Проверка числами файлов для приложения (stars_gaia.bin, milkyway_glow_gaia.png, spec.json).

    python3 Tools/milkyway_gaia/validate.py [--dir DIR] [--repeat DIR2] [--json validation.json]

Строки «да / НЕТ / не проверялось». Код 1 — есть «НЕТ»; код 2 — «НЕТ» нет, но что-то не проверялось (нет карты-
судьи NASA или сырого кэша); 0 — всё «да». Читаются сами файлы для приложения, а не сырой кэш: проверяется то,
что получит шейдер. --repeat — сравнить побайтно с файлами второго прогона build.py.

Определения (зафиксированы до первого прогона, под результат не подгонялись):
  (а) число звёзд G ≤ 10 в 400…600 тыс. (оценка задачи) и равно COUNT(*) сервера;
  (б) корреляция Пирсона log10 яркости Y с картой NASA SVS 1024×512 (galactic), обе сглажены гауссом σ 1°,
      наша карта взята в центрах пикселей NASA, вес cos b; JPG NASA расшифрован кривой sRGB; порог 0,9;
  (в) ядро: максимум сглаженной (σ 1°) яркости по всему небу — на |l| ≤ 3°;
  (г) тёмные облака, яркость сглажена σ 0,25°: Угольный Мешок — среднее в кольце 3°…5° вокруг (303°, 0°) к
      среднему в круге 1° вокруг той же точки; Большой разлом — среднее при 2° ≤ |b| ≤ 5° к среднему при
      |b| ≤ 1° на l 10°…50°; порог 1,3;
  (д) Магеллановы Облака, яркость сглажена σ 0,5°: в пределах 1° от ожидаемой точки есть местный максимум —
      пиксель, ярче которого нет ничего в радиусе 1° вокруг него. ИЗМЕНЕНО после первого прогона (20.10.2026):
      сначала искался самый яркий пиксель в круге 3° — у ММО им оказалось шаровое скопление 47 Тукана в 2,3°
      от ММО, и проверка вышла «НЕТ». Задача требует «локальный максимум в пределах 1°»; теперь проверяется
      ровно это, а прежнее определение печатается рядом в скобках (README, «Проверка»);
  (е) 20 звёзд check/simbad20.json: запись stars_gaia.bin против SIMBAD — расстояние ≤ 0,02°, |ΔG| ≤ 0,15.
"""
import argparse
import filecmp
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import pngio  # noqa: E402

import numpy as np  # noqa: E402

RESULTS = []


def line(name, ok, value, detail=""):
    mark = {True: "да", False: "НЕТ", None: "не проверялось"}[ok]
    RESULTS.append({"check": name, "ok": ok, "value": value, "detail": detail})
    print(f"  {mark:>14}  {name}: {value}" + (f"  ({detail})" if detail else ""))


def srgb_to_linear(v):
    return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)


def disk_mask(h, w, l0, b0, r_deg, r_in=0.0):
    l, b = C.grid(h, w)
    d = C.sep_deg(l[None, :], b[:, None], l0, b0)
    return (d <= r_deg) & (d >= r_in), d


def weighted_pearson(x, y, wt):
    wt = wt / wt.sum()
    mx, my = (wt * x).sum(), (wt * y).sum()
    cov = (wt * (x - mx) * (y - my)).sum()
    return float(cov / math.sqrt((wt * (x - mx) ** 2).sum() * (wt * (y - my) ** 2).sum()))


def spearman(x, y):
    rx = np.argsort(np.argsort(x)).astype(float)
    ry = np.argsort(np.argsort(y)).astype(float)
    return float(np.corrcoef(rx, ry)[0, 1])


def check_files(d, spec, stars, glow_img):
    bin_size = os.path.getsize(os.path.join(d, "stars_gaia.bin"))
    png_size = os.path.getsize(os.path.join(d, "milkyway_glow_gaia.png"))
    line("stars_gaia.bin ≤ 5 МБ", bin_size <= 5e6, f"{bin_size / 1e6:.2f} МБ ({bin_size} байт)")
    line("milkyway_glow_gaia.png ≤ 2,5 МБ", png_size <= 2.5e6, f"{png_size / 1e6:.2f} МБ, "
         f"{glow_img.shape[1]}×{glow_img.shape[0]}")
    ok = stars["count"] == spec["stars"]["count"] and list(glow_img.shape[1::-1]) == spec["glow"]["size"]
    line("заголовок и размер совпадают со spec.json", ok, f"{stars['count']} записей, "
         f"{glow_img.shape[1]}×{glow_img.shape[0]}")
    top = int(round(float(glow_img.max()) * 65535))
    line("максимум канала карты = 1,0 (65535)", top == 65535, top)


def check_count(stars, meta):
    n = stars["count"]
    srv = meta.get("bright", {}).get("server_count") if meta else None
    detail = f"сервер COUNT(*) = {srv}" if srv is not None else "сырого кэша нет — с сервером не сверено"
    line("(а) звёзд G ≤ 10 в пределах 400…600 тыс.", 400_000 <= n <= 600_000 and (srv is None or srv == n),
         n, detail)


def check_judge(Y):
    if not os.path.exists(C.JUDGE_FILE):
        line("(б) корреляция log яркости с NASA SVS ≥ 0,9", None, "—",
             f"нет {os.path.relpath(C.JUDGE_FILE)}; скачать: python3 Tools/milkyway_gaia/fetch.py --what judge")
        return None
    from PIL import Image
    nasa = np.asarray(Image.open(C.JUDGE_FILE).convert("RGB"), dtype=float) / 255.0
    Yn = srgb_to_linear(nasa) @ C.LUMA
    hn, wn = Yn.shape
    Yn_s = C.smooth(Yn, 1.0)
    Y_s = C.smooth(Y, 1.0)
    l, b = C.grid(hn, wn)
    L, B = np.meshgrid(l, b)
    ours = C.sample(Y_s, L, B)
    floor_n = max(float(Yn_s[Yn_s > 0].min()), 1e-6)
    x = np.log10(np.maximum(ours, ours.max() * 1e-6))
    y = np.log10(np.maximum(Yn_s, floor_n))
    wt = np.cos(np.radians(B))
    r = weighted_pearson(x.ravel(), y.ravel(), wt.ravel())
    rho = spearman(x.ravel(), y.ravel())
    slope = float(np.polyfit(x.ravel(), y.ravel(), 1, w=np.sqrt(wt.ravel()))[0])
    line("(б) корреляция log яркости с NASA SVS ≥ 0,9", r >= 0.9, f"r = {r:.4f}",
         f"Спирмен {rho:.4f}, наклон log-log {slope:.3f}; σ 1°, вес cos b, {wn}×{hn}")
    return {"pearson_cosb": r, "spearman": rho, "slope": slope}


def color_vs_judge(img):
    """Справочно (не да/нет): отношения R/G и B/G в линейном свете, наша карта против NASA, по четырём областям."""
    if not os.path.exists(C.JUDGE_FILE):
        return None
    from PIL import Image
    nasa = srgb_to_linear(np.asarray(Image.open(C.JUDGE_FILE).convert("RGB"), dtype=float) / 255.0)
    out = {}
    for name, a in (("ours", img), ("nasa", nasa)):
        h, w = a.shape[:2]
        l, b = C.grid(h, w)
        L, B = np.meshgrid(C.signed(l), b)
        regions = {"ядро |l|, |b| ≤ 10°": (np.abs(L) <= 10) & (np.abs(B) <= 10),
                   "полоса l 100°…260°, |b| ≤ 5°": (np.abs(L) >= 100) & (np.abs(B) <= 5),
                   "|b| 20°…40°": (np.abs(B) >= 20) & (np.abs(B) <= 40),
                   "полюса |b| ≥ 60°": np.abs(B) >= 60}
        for reg, m in regions.items():
            wt = np.cos(np.radians(B))[m]
            R, G, Bl = [(a[..., c][m] * wt).sum() for c in range(3)]
            out.setdefault(reg, {})[name] = [round(float(R / G), 3), round(float(Bl / G), 3)]
    for reg, v in out.items():
        print(f"  {'справочно':>14}  цвет R/G, B/G — {reg}: наша {v['ours'][0]:.2f} / {v['ours'][1]:.2f}, "
              f"NASA {v['nasa'][0]:.2f} / {v['nasa'][1]:.2f}")
    return out


def check_core(Y):
    Ys = C.smooth(Y, 1.0)
    h, w = Y.shape
    l, b = C.grid(h, w)
    j, i = np.unravel_index(np.argmax(Ys), Ys.shape)
    lc, bc = float(C.signed(l[i])), float(b[j])
    band = np.abs(b) <= 10
    jb, ib = np.unravel_index(np.argmax(np.where(band[:, None], Ys, -1)), Ys.shape)
    line("(в) ядро: максимум сглаженной яркости на |l| ≤ 3°", abs(lc) <= 3.0, f"l {lc:+.2f}°, b {bc:+.2f}°",
         f"σ 1°; максимум в полосе |b| ≤ 10° — l {float(C.signed(l[ib])):+.2f}°, b {float(b[jb]):+.2f}°")
    return {"l": lc, "b": bc}


def check_dark(Y):
    Ys = C.smooth(Y, 0.25)
    h, w = Y.shape
    l, b = C.grid(h, w)
    disk, _ = disk_mask(h, w, 303.0, 0.0, 1.0)
    ring, _ = disk_mask(h, w, 303.0, 0.0, 5.0, 3.0)
    cs = float(Ys[ring].mean() / Ys[disk].mean())
    line("(г) Угольный Мешок: кольцо 3°…5° / круг 1° вокруг (303°, 0°) ≥ 1,3", cs >= 1.3, f"{cs:.2f}")
    ls = C.signed(l)
    cols = (ls >= 10) & (ls <= 50)
    mid = np.abs(b) <= 1.0
    side = (np.abs(b) >= 2.0) & (np.abs(b) <= 5.0)
    gr = float(Ys[side][:, cols].mean() / Ys[mid][:, cols].mean())
    per_deg = []
    for x in np.arange(10.5, 50, 1.0):
        c = np.abs(ls - x) <= 0.5
        per_deg.append(Ys[side][:, c].mean() / Ys[mid][:, c].mean())
    per_deg = np.array(per_deg)
    line("(г) Большой разлом l 10°…50°: |b| 2°…5° / |b| ≤ 1° ≥ 1,3", gr >= 1.3, f"{gr:.2f}",
         f"по градусам долготы: медиана {np.median(per_deg):.2f}, мин {per_deg.min():.2f}, макс {per_deg.max():.2f}")
    return {"coalsack": cs, "great_rift": gr, "great_rift_per_deg_median": float(np.median(per_deg))}


def check_clouds(Y):
    Ys = C.smooth(Y, 0.5)
    h, w = Y.shape
    l, b = C.grid(h, w)
    out = {}
    for name, (l0, b0) in {"БМО": (280.5, -32.9), "ММО": (302.8, -44.3)}.items():
        ring, _ = disk_mask(h, w, l0, b0, 8.0, 6.0)
        # прежнее определение (первый прогон): самый яркий пиксель в круге 3°
        m3, d = disk_mask(h, w, l0, b0, 3.0)
        j3, i3 = np.unravel_index(np.argmax(np.where(m3, Ys, -1)), Ys.shape)
        # местные максимумы в пределах 1°: ярче всего в радиусе 1° вокруг себя
        cand = np.argwhere(d <= 1.0)
        best = None
        for j, i in cand:
            mj, _ = disk_mask(h, w, float(l[i]), float(b[j]), 1.0)
            if Ys[j, i] >= Ys[mj].max() and (best is None or d[j, i] < best[0]):
                best = (float(d[j, i]), int(j), int(i))
        old = (f"самый яркий в круге 3° — l {l[i3]:.2f}°, b {b[j3]:+.2f}°, {float(d[j3, i3]):.2f}° от точки")
        if best is None:
            line(f"(д) {name}: местный максимум ≤ 1° от (l {l0}°, b {b0}°)", False, "нет", old)
            out[name] = {"local_max": None, "brightest_in_3deg": [float(l[i3]), float(b[j3]), float(d[j3, i3])]}
            continue
        dist, j, i = best
        contrast = float(Ys[j, i] / Ys[ring].mean())
        line(f"(д) {name}: местный максимум ≤ 1° от (l {l0}°, b {b0}°)", True, f"{dist:.2f}°",
             f"максимум в l {l[i]:.2f}°, b {b[j]:+.2f}°; пик / кольцо 6°…8° = {contrast:.1f}; {old}")
        out[name] = {"l": float(l[i]), "b": float(b[j]), "dist_deg": dist, "peak_to_ring": contrast,
                     "brightest_in_3deg": [float(l[i3]), float(b[j3]), float(d[j3, i3])]}
    return out


def check_simbad(stars):
    if not os.path.exists(C.SIMBAD_FILE):
        line("(е) 20 звёзд против SIMBAD", None, "—", f"нет {os.path.relpath(C.SIMBAD_FILE)}")
        return None
    with open(C.SIMBAD_FILE, encoding="utf-8") as f:
        doc = json.load(f)
    rows, n_ok = [], 0
    for s in doc["stars"]:
        near = np.flatnonzero(np.abs(stars["g"] - s["gaia_g"]) <= 0.06)
        dsel = C.sep_deg(stars["l"][near], stars["b"][near], s["gaia_l"], s["gaia_b"])
        k = near[np.argmin(dsel)]
        lb, bb, gb = float(stars["l"][k]), float(stars["b"][k]), float(stars["g"][k])
        r = {"gaia_id": s["gaia_id"], "simbad": s["simbad_main_id"], "bin_l": lb, "bin_b": bb, "bin_g": gb,
             "bin_vs_raw_deg": float(dsel.min())}
        if s["simbad_ra"] is None:
            r.update(ok=False, why="нет в SIMBAD")
        else:
            ls, bs = C.icrs_to_gal(np.array(s["simbad_ra"]), np.array(s["simbad_dec"]))
            sep = float(C.sep_deg(lb, bb, float(ls), float(bs)))
            dg = None if s["simbad_g"] is None else gb - s["simbad_g"]
            r.update(sep_deg=sep, simbad_g=s["simbad_g"], dg=dg,
                     ok=bool(sep <= 0.02 and dg is not None and abs(dg) <= 0.15),
                     why="" if dg is not None else "нет G в SIMBAD")
        n_ok += r["ok"]
        rows.append(r)
    seps = [r["sep_deg"] for r in rows if "sep_deg" in r]
    dgs = [abs(r["dg"]) for r in rows if r.get("dg") is not None]
    line("(е) 20 звёзд против SIMBAD: ≤ 0,02° и ≤ 0,15 mag", n_ok == len(rows) == 20, f"{n_ok}/{len(rows)}",
         f"расстояние макс {max(seps) * 3600:.1f}″, |ΔG| макс {max(dgs):.3f}" if seps and dgs else "")
    for r in rows:
        if not r["ok"]:
            print(f"                  {r['gaia_id']} ({r['simbad']}): {r.get('why') or ''} "
                  f"sep {r.get('sep_deg', float('nan')) * 3600:.1f}″ ΔG {r.get('dg')}")
    return rows


def check_rotation():
    """Самопроверка матрицы ICRS → галактические (ей переводятся координаты SIMBAD): ra, dec → l, b против
    столбцов l, b самой Gaia у ярких звёзд сырого кэша."""
    import csv
    import gzip
    import io
    g0, g1 = C.BRIGHT_SLICES[0]
    path = os.path.join(C.RAW_BRIGHT, f"g_{g0:+05.1f}_{g1:04.1f}.csv.gz")
    if not os.path.exists(path):
        line("матрица ICRS → галактические против l, b Gaia", None, "—", "нет сырого кэша")
        return None
    with gzip.open(path) as f:
        rows = list(csv.reader(io.StringIO(f.read().decode("utf-8"))))
    ix = [rows[0].index(k) for k in ("ra", "dec", "l", "b")]
    a = np.array([[float(r[i]) for i in ix] for r in rows[1:]])
    l, b = C.icrs_to_gal(a[:, 0], a[:, 1])
    d = float(C.sep_deg(l, b, a[:, 2], a[:, 3]).max() * 3600)
    line("матрица ICRS → галактические против l, b Gaia", d < 0.01, f"макс {d:.5f}″", f"{len(a)} звёзд")
    return d


def check_repeat(d, d2):
    same = all(filecmp.cmp(os.path.join(d, f), os.path.join(d2, f), shallow=False)
               for f in ("stars_gaia.bin", "milkyway_glow_gaia.png", "spec.json"))
    line("повторный прогон build.py: побайтно то же", same, "да" if same else "файлы различаются")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default=C.HERE)
    ap.add_argument("--repeat", help="папка второго прогона build.py для сравнения")
    ap.add_argument("--json", default=os.path.join(C.HERE, "validation.json"))
    args = ap.parse_args()
    with open(os.path.join(args.dir, "spec.json"), encoding="utf-8") as f:
        spec = json.load(f)
    meta = None
    if os.path.exists(C.RAW_META):
        with open(C.RAW_META, encoding="utf-8") as f:
            meta = json.load(f)
    stars = C.read_bin(os.path.join(args.dir, "stars_gaia.bin"))
    img = pngio.read_png16(os.path.join(args.dir, "milkyway_glow_gaia.png")).astype(float) / 65535.0
    Y = img @ C.LUMA

    print("Файлы")
    check_files(args.dir, spec, stars, img)
    if args.repeat:
        check_repeat(args.dir, args.repeat)
    print("Проверки задачи")
    res = {}
    check_count(stars, meta)
    res["judge"] = check_judge(Y)
    res["core"] = check_core(Y)
    res["dark"] = check_dark(Y)
    res["clouds"] = check_clouds(Y)
    res["simbad"] = check_simbad(stars)
    print("Справочно (без порога)")
    res["color_vs_nasa"] = color_vs_judge(img)
    print("Самопроверки")
    res["rotation_max_arcsec"] = check_rotation()

    with open(args.json, "w", encoding="utf-8") as f:
        json.dump({"checks": RESULTS, "details": res}, f, ensure_ascii=False, indent=1)
        f.write("\n")
    bad = [r for r in RESULTS if r["ok"] is False]
    skipped = [r for r in RESULTS if r["ok"] is None]
    print(f"итог: «да» {sum(r['ok'] is True for r in RESULTS)}, «НЕТ» {len(bad)}, не проверялось {len(skipped)}")
    sys.exit(1 if bad else 2 if skipped else 0)


if __name__ == "__main__":
    main()
