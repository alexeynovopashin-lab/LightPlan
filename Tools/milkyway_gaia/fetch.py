#!/usr/bin/env python3
"""Скачивание данных Gaia DR3 из архива ESA (TAP, асинхронные запросы ADQL) в сырой кэш raw/.

    python3 Tools/milkyway_gaia/fetch.py                     всё: яркие звёзды, свечение, контроль, цвет, судья, SIMBAD
    python3 Tools/milkyway_gaia/fetch.py --what glow --workers 3
    python3 Tools/milkyway_gaia/fetch.py --what simbad       только снимок SIMBAD (нужны raw/bright/)

Куски, которые уже лежат в raw/, не качаются второй раз: прерванный прогон продолжается с места.
Каждый запрос повторяется до --retries раз с паузой 15 с, 30 с, 60 с, …

Что куда:
  raw/bright/g_<от>_<до>.csv.gz   звёзды G ≤ 10, срезами по величине (столбцы — как вернул сервер)
  raw/glow/hpx2_<NNN>.csv.gz      свечение G 10…21 по ячейкам 0,125°, кусок неба = пиксель HEALPix уровня 2
  raw/meta.json                   когда, откуда, какие запросы, контрольные счётчики сервера (glowcount:
                                  число звёзд свечения в 12 пикселях HEALPix уровня 0 — для сверки сумм)
  raw/color/hip_bv.csv.gz         B−V Hipparcos и BP−RP Gaia у ~99 тыс. общих звёзд — для перевода цвета в температуру
  raw/judge/…jpg                  карта NASA SVS 1024×512 — только судья для validate.py, в репозиторий не идёт
  check/simbad20.json             20 звёзд из SIMBAD для сверки (маленький снимок, лежит в репозитории)
"""
import argparse
import concurrent.futures as cf
import csv
import datetime as dt
import gzip
import io
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402

import requests  # noqa: E402

UA = {"User-Agent": "LightPlan-milkyway_gaia/1 (python-requests)"}
MAXREC = 3_000_000

Q_BRIGHT = """SELECT source_id, ra, dec, l, b, phot_g_mean_mag, bp_rp
FROM gaiadr3.gaia_source
WHERE phot_g_mean_mag > {g0} AND phot_g_mean_mag <= {g1}"""

Q_BRIGHT_COUNT = "SELECT COUNT(*) AS n, COUNT(bp_rp) AS n_bp_rp FROM gaiadr3.gaia_source WHERE phot_g_mean_mag <= {g}"
# Звёзды, у которых за 10 лет от эпохи Gaia (J2016) сдвиг больше половины шага упаковки l (≈ 10″): pm > 1″/год.
Q_BRIGHT_PM = "SELECT COUNT(*) AS n FROM gaiadr3.gaia_source WHERE phot_g_mean_mag <= {g} AND pm > 1000"

# Ячейка 0,125°: FLOOR(l/0.125) = FLOOR(l*8) точно (0,125 — степень двойки). Сумм вместо AVG — чтобы складывать
# куски: ячейка на границе двух пикселей HEALPix приходит из обоих. fn — поток звёзд, у которых есть BP−RP
# (bp_rp*0+1 — NULL у звезды без цвета, SUM пропускает NULL; CASE парсер сервера не принимает).
Q_GLOW = """SELECT FLOOR(l*8) AS il, FLOOR((b+90)*8) AS ib, COUNT(*) AS n,
SUM(POWER(10,-0.4*phot_g_mean_mag)) AS f, COUNT(bp_rp) AS nc, SUM(bp_rp) AS sc,
SUM(POWER(10,-0.4*phot_g_mean_mag)*bp_rp) AS fc, SUM(POWER(10,-0.4*phot_g_mean_mag)*(bp_rp*0+1)) AS fn
FROM gaiadr3.gaia_source
WHERE source_id BETWEEN {s0} AND {s1}
AND phot_g_mean_mag > {g0} AND phot_g_mean_mag <= {g1}
GROUP BY il, ib"""

# Контроль: сервер сам считает звёзды свечения в пикселе HEALPix уровня 0 (12 кусков по 16 наших),
# build.py сверяет с суммой COUNT(*) по ячейкам этих 16 кусков.
Q_GLOW_COUNT = """SELECT COUNT(*) AS n FROM gaiadr3.gaia_source
WHERE source_id BETWEEN {s0} AND {s1}
AND phot_g_mean_mag > {g0} AND phot_g_mean_mag <= {g1}"""

# Цвет → температура: B−V Hipparcos (новая редукция, van Leeuwen 2007) против BP−RP Gaia DR3 у тех же звёзд
# (официальная таблица соответствия архива). build.py строит по ним медианы B−V в интервалах BP−RP.
Q_COLOR = """SELECT g.source_id, g.bp_rp, g.phot_g_mean_mag, h.hip, h.b_v, h.e_b_v
FROM gaiadr3.hipparcos2_best_neighbour AS x
JOIN gaiadr3.gaia_source AS g ON g.source_id = x.source_id
JOIN public.hipparcos_newreduction AS h ON h.hip = x.original_ext_source_id
WHERE g.bp_rp IS NOT NULL AND h.b_v IS NOT NULL"""

Q_SIMBAD = """SELECT i.id AS gaia_id, b.main_id, b.ra, b.dec, b.coo_bibcode, f.flux AS g_simbad, f.bibcode AS g_bibcode
FROM ident AS i JOIN basic AS b ON i.oidref = b.oid
LEFT OUTER JOIN flux AS f ON f.oidref = b.oid AND f.filter = 'G'
WHERE i.id IN ({ids})"""


def log(*a):
    print(*a, flush=True)


def tap_async(base, query, fmt="csv", poll=3.0, timeout=3 * 3600):
    """Один асинхронный запрос TAP: создать задание, ждать COMPLETED, забрать результат.

    Без MAXREC архив ESA отдаёт анонимному пользователю 50 000 строк и молча обрезает остальное (так обрезались
    три среза ярких звёзд в первом прогоне, 20.10.2026). Поэтому MAXREC задан явно, а ответ ровно в MAXREC
    строк считается обрезанным (ошибка). Одно задание живёт не дольше 600 с (executionDuration в /capabilities)."""
    r = requests.post(base + "/async", data={"REQUEST": "doQuery", "LANG": "ADQL", "FORMAT": fmt,
                                              "PHASE": "RUN", "QUERY": query, "MAXREC": str(MAXREC)},
                      headers=UA, allow_redirects=False, timeout=120)
    loc = r.headers.get("Location")
    if r.status_code not in (200, 303) or not loc:
        raise RuntimeError(f"задание не создано: HTTP {r.status_code}: {r.text[:500]}")
    t0 = time.time()
    while True:
        ph = requests.get(loc + "/phase", headers=UA, timeout=60).text.strip()
        if ph in ("COMPLETED", "ERROR", "ABORTED"):
            break
        if time.time() - t0 > timeout:
            raise RuntimeError(f"нет ответа за {timeout} с ({loc})")
        time.sleep(poll)
    if ph != "COMPLETED":
        err = requests.get(loc + "/error", headers=UA, timeout=60).text
        raise RuntimeError(f"{ph}: {err[:1500]}")
    res = requests.get(loc + "/results/result", headers=UA, timeout=1800)
    res.raise_for_status()
    if fmt == "csv" and res.content.count(b"\n") - 1 >= MAXREC:
        raise RuntimeError(f"ответ упёрся в MAXREC = {MAXREC} строк — обрезан ({loc})")
    return res.content, loc


def tap_sync(base, query, fmt="csv"):
    r = requests.post(base + "/sync", data={"REQUEST": "doQuery", "LANG": "ADQL", "FORMAT": fmt, "QUERY": query},
                      headers=UA, timeout=300)
    r.raise_for_status()
    return r.content


def with_retries(what, fn, retries):
    for k in range(retries):
        try:
            return fn()
        except Exception as e:  # сеть, 5xx, ошибка задания — пробуем ещё
            wait = 15 * 2 ** k
            log(f"  {what}: попытка {k + 1}/{retries} не удалась: {str(e)[:300]}")
            if k == retries - 1:
                raise
            log(f"  {what}: повтор через {wait} с")
            time.sleep(wait)


def csv_rows(content):
    return list(csv.reader(io.StringIO(content.decode("utf-8"))))


def save_gz(path, content):
    tmp = path + ".part"
    with gzip.GzipFile(tmp, "wb", mtime=0) as f:
        f.write(content)
    os.replace(tmp, path)


def load_meta():
    if os.path.exists(C.RAW_META):
        with open(C.RAW_META, encoding="utf-8") as f:
            return json.load(f)
    return {}


def put_meta(meta, key, value):
    """Записать один раздел raw/meta.json: файл перечитывается, чтобы параллельный прогон fetch.py (другой --what)
    не затёр чужой раздел старой копией (так 20.10.2026 пропал раздел color)."""
    cur = load_meta()
    cur.setdefault("source", meta.get("source"))
    cur[key] = value
    save_meta(cur)
    meta[key] = value


def save_meta(meta):
    tmp = C.RAW_META + ".part"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1, sort_keys=True)
    os.replace(tmp, C.RAW_META)


def now():
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------- яркие звёзды

def fetch_bright(args, meta):
    os.makedirs(C.RAW_BRIGHT, exist_ok=True)
    total = 0
    for g0, g1 in C.BRIGHT_SLICES:
        path = os.path.join(C.RAW_BRIGHT, f"g_{g0:+05.1f}_{g1:04.1f}.csv.gz")
        if os.path.exists(path) and not args.force:
            with gzip.open(path) as f:
                n = len(csv_rows(f.read())) - 1
            log(f"bright G ({g0}, {g1}]: уже есть, {n} звёзд")
            total += n
            continue
        q = Q_BRIGHT.format(g0=g0, g1=g1)
        t0 = time.time()
        content, loc = with_retries(f"bright ({g0}, {g1}]", lambda: tap_async(C.TAP_ESA, q), args.retries)
        n = len(csv_rows(content)) - 1
        save_gz(path, content)
        total += n
        log(f"bright G ({g0}, {g1}]: {n} звёзд, {time.time() - t0:.0f} с")
    q = Q_BRIGHT_COUNT.format(g=C.G_BRIGHT)
    content, _ = with_retries("bright count", lambda: tap_async(C.TAP_ESA, q), args.retries)
    rows = csv_rows(content)
    n_server, n_col = int(float(rows[1][0])), int(float(rows[1][1]))
    qpm = Q_BRIGHT_PM.format(g=C.G_BRIGHT)
    content, _ = with_retries("bright pm", lambda: tap_async(C.TAP_ESA, qpm), args.retries)
    n_pm = int(float(csv_rows(content)[1][0]))
    log(f"bright: в срезах {total}, сервер COUNT(G ≤ {C.G_BRIGHT}) = {n_server}, из них с BP−RP {n_col}, "
        f"с движением > 1″/год {n_pm}")
    put_meta(meta, "bright", {"fetched_utc": now(), "slices": C.BRIGHT_SLICES, "query": Q_BRIGHT,
                              "count_query": q, "server_count": n_server, "server_count_bp_rp": n_col,
                              "pm_query": qpm, "server_count_pm_gt_1as": n_pm, "rows_in_slices": total})


# ---------------------------------------------------------------- свечение

def glow_path(p):
    return os.path.join(C.RAW_GLOW, f"hpx{C.HPX_LEVEL}_{p:03d}.csv.gz")


def fetch_glow_one(p, retries):
    s0, s1 = p * C.HPX_STEP, (p + 1) * C.HPX_STEP - 1
    q = Q_GLOW.format(s0=s0, s1=s1, g0=C.G_BRIGHT, g1=C.G_FAINT)
    t0 = time.time()
    content, loc = with_retries(f"glow {p:03d}", lambda: tap_async(C.TAP_ESA, q), retries)
    rows = csv_rows(content)
    if rows[0][:3] != ["il", "ib", "n"]:
        raise RuntimeError(f"glow {p:03d}: неожиданная шапка {rows[0]}")
    n_stars = sum(int(float(r[2])) for r in rows[1:])
    save_gz(glow_path(p), content)
    return p, len(rows) - 1, n_stars, time.time() - t0


def fetch_glow(args, meta):
    os.makedirs(C.RAW_GLOW, exist_ok=True)
    npix = 12 * 4 ** C.HPX_LEVEL
    todo = [p for p in range(npix) if args.force or not os.path.exists(glow_path(p))]
    if args.limit:
        todo = todo[:args.limit]
    log(f"glow: кусков {npix}, уже есть {npix - len(todo) if not args.limit else '…'}, качаю {len(todo)}, "
        f"потоков {args.workers}")
    t_all = time.time()
    done = 0
    failed = []
    with cf.ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(fetch_glow_one, p, args.retries): p for p in todo}
        for fu in cf.as_completed(futs):
            p = futs[fu]
            try:
                _, cells, n, sec = fu.result()
                done += 1
                log(f"glow {p:03d}: ячеек {cells}, звёзд {n}, {sec:.0f} с  [{done}/{len(todo)}, "
                    f"{(time.time() - t_all) / 60:.1f} мин]")
            except Exception as e:
                failed.append(p)
                log(f"glow {p:03d}: НЕ СКАЧАН: {str(e)[:300]}")
    have = sum(os.path.exists(glow_path(p)) for p in range(npix))
    put_meta(meta, "glow", {"fetched_utc": now(), "healpix_level": C.HPX_LEVEL, "chunks": npix,
                            "chunks_present": have, "query": Q_GLOW, "g_range": [C.G_BRIGHT, C.G_FAINT],
                            "cell_deg": C.CELL_DEG})
    if failed:
        log(f"glow: не скачаны куски {failed} — запустите fetch.py ещё раз, он докачает только их")
        return False
    return True


def fetch_glowcount(args, meta):
    step0 = C.HPX_STEP * 4 ** C.HPX_LEVEL
    counts = meta.get("glow_control", {}).get("counts", {})
    for p0 in range(12):
        if str(p0) in counts and not args.force:
            continue
        q = Q_GLOW_COUNT.format(s0=p0 * step0, s1=(p0 + 1) * step0 - 1, g0=C.G_BRIGHT, g1=C.G_FAINT)
        t0 = time.time()
        content, _ = with_retries(f"glow count {p0}", lambda: tap_async(C.TAP_ESA, q), args.retries)
        counts[str(p0)] = int(float(csv_rows(content)[1][0]))
        log(f"glow count HEALPix-0 {p0}: {counts[str(p0)]} звёзд, {time.time() - t0:.0f} с")
        put_meta(meta, "glow_control", {"fetched_utc": now(), "query": Q_GLOW_COUNT, "counts": counts})
    log(f"glow count: всего {sum(counts.values())} звёзд G ({C.G_BRIGHT}, {C.G_FAINT}]")


def fetch_color(args, meta):
    os.makedirs(C.RAW_COLOR, exist_ok=True)
    if os.path.exists(C.COLOR_FILE) and not args.force:
        log("color: уже есть")
        return
    content, _ = with_retries("color", lambda: tap_async(C.TAP_ESA, Q_COLOR), args.retries)
    save_gz(C.COLOR_FILE, content)
    n = len(csv_rows(content)) - 1
    put_meta(meta, "color", {"fetched_utc": now(), "query": Q_COLOR, "rows": n})
    log(f"color: {n} звёзд Hipparcos с B−V и BP−RP")


# ---------------------------------------------------------------- судья NASA

def fetch_judge(args, meta):
    os.makedirs(C.RAW_JUDGE, exist_ok=True)
    if os.path.exists(C.JUDGE_FILE) and not args.force:
        log("judge: уже есть")
        return
    def get():
        r = requests.get(C.JUDGE_URL, headers=UA, timeout=120)
        r.raise_for_status()
        return r.content
    content = with_retries("judge", get, args.retries)
    with open(C.JUDGE_FILE, "wb") as f:
        f.write(content)
    put_meta(meta, "judge", {"fetched_utc": now(), "url": C.JUDGE_URL, "bytes": len(content),
                             "note": "NASA SVS «Deep Star Maps 2020» (id 4851), только для сверки; в репозиторий "
                                     "не кладётся"})
    log(f"judge: {len(content)} байт")


# ---------------------------------------------------------------- SIMBAD

def read_bright_raw():
    import numpy as np
    sid, l, b, g, c = [], [], [], [], []
    for g0, g1 in C.BRIGHT_SLICES:
        path = os.path.join(C.RAW_BRIGHT, f"g_{g0:+05.1f}_{g1:04.1f}.csv.gz")
        with gzip.open(path) as f:
            rows = csv_rows(f.read())
        hdr = rows[0]
        ix = {k: hdr.index(k) for k in ("source_id", "l", "b", "phot_g_mean_mag", "bp_rp")}
        for r in rows[1:]:
            sid.append(int(r[ix["source_id"]]))
            l.append(float(r[ix["l"]]))
            b.append(float(r[ix["b"]]))
            g.append(float(r[ix["phot_g_mean_mag"]]))
            c.append(float(r[ix["bp_rp"]]) if r[ix["bp_rp"]] else float("nan"))
    return {"source_id": np.array(sid, dtype=np.int64), "l": np.array(l), "b": np.array(b),
            "g": np.array(g), "c": np.array(c)}


def fetch_simbad(args, meta):
    import numpy as np
    s = read_bright_raw()
    order = np.argsort(s["source_id"], kind="stable")
    s = {k: v[order] for k, v in s.items()}
    picks = C.simbad_pick(s["source_id"], s["g"], s["b"])
    ids = [f"Gaia DR3 {s['source_id'][i]}" for i in picks]
    q = Q_SIMBAD.format(ids=", ".join(f"'{x}'" for x in ids))
    content = with_retries("simbad", lambda: tap_sync(C.TAP_SIMBAD, q), args.retries)
    rows = csv_rows(content)
    hdr = rows[0]
    by_id = {}
    for r in rows[1:]:
        d = dict(zip(hdr, r))
        by_id.setdefault(d["gaia_id"], d)
    out = []
    for i, gid in zip(picks, ids):
        d = by_id.get(gid)
        out.append({
            "gaia_id": gid,
            "gaia_l": round(float(s["l"][i]), 7), "gaia_b": round(float(s["b"][i]), 7),
            "gaia_g": round(float(s["g"][i]), 4),
            "simbad_main_id": d["main_id"] if d else None,
            "simbad_ra": float(d["ra"]) if d and d["ra"] else None,
            "simbad_dec": float(d["dec"]) if d and d["dec"] else None,
            "simbad_coo_bibcode": d["coo_bibcode"] if d else None,
            "simbad_g": float(d["g_simbad"]) if d and d["g_simbad"] else None,
            "simbad_g_bibcode": d["g_bibcode"] if d else None,
        })
    doc = {"what": "20 звёзд stars_gaia.bin для сверки с SIMBAD (validate.py, проверка «е»)",
           "rule": "5 интервалов G × 4 интервала |b| (common.simbad_pick), в каждом — звезда с наименьшим "
                   "source_id mod 1000003",
           "fetched_utc": now(), "service": C.TAP_SIMBAD, "query": q,
           "credit": "This research has made use of the SIMBAD database, CDS, Strasbourg Astronomical "
                     "Observatory, France",
           "stars": out}
    os.makedirs(os.path.dirname(C.SIMBAD_FILE), exist_ok=True)
    with open(C.SIMBAD_FILE, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
        f.write("\n")
    found = sum(1 for o in out if o["simbad_ra"] is not None)
    log(f"simbad: {len(out)} звёзд, найдено в SIMBAD {found} → {os.path.relpath(C.SIMBAD_FILE)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--what", default="bright,glow,glowcount,color,judge,simbad",
                    help="что качать, через запятую: bright, glow, glowcount, color, judge, simbad")
    ap.add_argument("--workers", type=int, default=3, help="параллельных запросов свечения (вежливо — 2–4)")
    ap.add_argument("--retries", type=int, default=5)
    ap.add_argument("--limit", type=int, default=0, help="только первые N недостающих кусков свечения (проба)")
    ap.add_argument("--force", action="store_true", help="качать заново, даже если файл уже есть")
    args = ap.parse_args()
    os.makedirs(C.RAW, exist_ok=True)
    meta = load_meta()
    meta.setdefault("source", {"archive": "ESA Gaia Archive", "tap": C.TAP_ESA, "table": "gaiadr3.gaia_source",
                               "release": "Gaia DR3"})
    what = set(args.what.split(","))
    ok = True
    if "bright" in what:
        fetch_bright(args, meta)
    if "glow" in what:
        ok = fetch_glow(args, meta) and ok
    if "glowcount" in what:
        fetch_glowcount(args, meta)
    if "color" in what:
        fetch_color(args, meta)
    if "judge" in what:
        fetch_judge(args, meta)
    if "simbad" in what:
        fetch_simbad(args, meta)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
