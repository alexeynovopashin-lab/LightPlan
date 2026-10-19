#!/usr/bin/env python3
"""Проверка карты Млечного Пути числами: модель против карты звёзд NASA SVS «Deep Star Maps 2020» (судья, не текстура).

    python3 validate.py [--ref ref/milkyway_2020_4k_gal_print.jpg] [--out out] [--json отчёт.json] [--repeat DIR]

Читает то, что прочтёт приложение — PNG из out/. Карта NASA (1024×512, галактическая, l = 0 в центре, l растёт
влево, без ярких звёзд Hipparcos/Tycho) лежит в ref/ (в .gitignore; как скачать — README). Её JPG расшифровывается
кривой sRGB в линейную яркость (сверено один раз с линейным EXR той же карты: наклон 0,985 в логарифмах).

Обе карты сглаживаются одинаково (гаусс σ = 1° по небу на своей сетке), модель берётся в центрах пикселей NASA.
Метрики и пороги — из задачи (README, «Проверка»). Любое «НЕТ» — код 1; строки «·» — справка, не вердикт.
Без карты NASA проверяются только файлы, самопроверки модели и тонирование, сравнение — «не проверялось» (код 2).
"""
import argparse
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import model as M  # noqa: E402
import pngio  # noqa: E402
import sky  # noqa: E402
from sky import LUMA, grid, signed, smooth  # noqa: E402

# Внешние галактики есть на карте NASA, но не в модели Галактики: БМО, ММО (центр l, b; радиус маски, °).
MASKS = [(280.47, -32.89, 8.0), (302.80, -44.30, 4.5)]
FWHM_L = (0.0, 90.0, 180.0, 270.0)


def srgb_to_linear(v):
    return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)


def load_nasa(path):
    from PIL import Image
    a = np.asarray(Image.open(path).convert('RGB')).astype(np.float64) / 255.0
    return srgb_to_linear(a) @ LUMA


def load_model(out_dir):
    spec = json.load(open(os.path.join(out_dir, 'spec.json')))
    g = pngio.read(os.path.join(out_dir, spec['glow']['file'])).astype(np.float64) / 65535.0
    t = pngio.read(os.path.join(out_dir, spec['tau']['file'])).astype(np.float64) / 100.0
    return spec, g, t


# --- метрики -----------------------------------------------------------------------------------------------
def weighted_corr(a, b, w):
    w = w / w.sum()
    ma, mb = (w * a).sum(), (w * b).sum()
    cov = (w * (a - ma) * (b - mb)).sum()
    return cov / math.sqrt((w * (a - ma) ** 2).sum() * (w * (b - mb) ** 2).sum())


def mask_galaxies(l, b):
    L, B = np.meshgrid(l, b)
    keep = np.ones_like(L, bool)
    for l0, b0, r in MASKS:
        cosd = (np.sin(np.radians(B)) * math.sin(math.radians(b0))
                + np.cos(np.radians(B)) * math.cos(math.radians(b0)) * np.cos(np.radians(L - l0)))
        keep &= np.degrees(np.arccos(np.clip(cosd, -1, 1))) > r
    return keep


def core_peak(Y, l, b):
    """Самая яркая точка в |l| ≤ 30°, |b| ≤ 30° (сглаженная карта)."""
    m = (np.abs(signed(l))[None, :] <= 30) & (np.abs(b)[:, None] <= 30)
    Z = np.where(m, Y, -1)
    j, i = np.unravel_index(Z.argmax(), Z.shape)
    return float(signed(l)[i]), float(b[j])


def band_profile_l(Y, l, b, half_b=1.0):
    """Яркость вдоль плоскости: среднее по |b| ≤ half_b, по долготе с шагом 1°."""
    rows = np.abs(b) <= half_b
    ls = np.arange(0.5, 360, 1.0)
    prof = np.array([Y[rows][:, np.abs(((l - x + 180) % 360) - 180) <= 0.5].mean() for x in ls])
    return ls, prof


def lat_profile(Y, l, b, l0, dl=5.0):
    cols = np.abs(((l - l0 + 180) % 360) - 180) <= dl
    return Y[:, cols].mean(axis=1)


def rift_ratio(Y, l, b):
    """Большой разлом: l 10°…50°, средний профиль поперёк; бока 2°–5° с обеих сторон / середина |b| ≤ 1°."""
    p = lat_profile(Y, l, b, 30.0, 20.0)
    mid = p[np.abs(b) <= 1.0].mean()
    sides = p[(np.abs(b) >= 2.0) & (np.abs(b) <= 5.0)].mean()
    per_l = []
    for x in range(10, 51, 2):
        q = lat_profile(Y, l, b, float(x), 1.0)
        per_l.append(q[(np.abs(b) >= 2.0) & (np.abs(b) <= 5.0)].mean() / q[np.abs(b) <= 1.0].mean())
    return float(sides / mid), float(np.median(per_l)), float(np.mean(np.array(per_l) >= 1.3))


def fwhm(p, b):
    """Ширина на половине высоты над фоном (фон — среднее при 30° ≤ |b| ≤ 40°): между крайними пересечениями
    половины в |b| ≤ 30° (полоса, разрезанная пылью на два горба, меряется целиком), и второй горб — доля пика."""
    bg = p[(np.abs(b) >= 30) & (np.abs(b) <= 40)].mean()
    q = p - bg
    inner = np.abs(b) <= 30
    peak = q[inner].max()
    idx = np.where(inner & (q >= 0.5 * peak))[0]
    lo, hi = idx.min(), idx.max()

    def cross(i, j):                    # линейная интерполяция между i (выше) и j (ниже половины)
        if j < 0 or j >= len(b):
            return b[i]
        t = (q[i] - 0.5 * peak) / (q[i] - q[j])
        return b[i] + t * (b[j] - b[i])
    ipk = int(np.argmax(np.where(inner, q, -np.inf)))
    other = np.where(inner & (np.sign(b) != np.sign(b[ipk])) & (np.abs(b) >= 1.5), q, -np.inf).max()
    return float(abs(cross(lo, lo - 1) - cross(hi, hi + 1))), float(other / peak)


# --- самопроверки модели -----------------------------------------------------------------------------------
def model_checks():
    gal = M.Galaxy()
    M.calibrate_dust(gal)
    res = {
        'A_V до центра (l = 0°, b = 0°, 8,15 кпк), зв. вел.': M.av_to(gal, 0.0, 0.0, M.R0),
        'A_V через Галактику к северному полюсу, зв. вел.': M.av_to(gal, 0.0, 90.0, 8.0),
        'A_V через Галактику к южному полюсу, зв. вел.': M.av_to(gal, 0.0, -90.0, 8.0),
        'A_V окно Бааде (l = 1°, b = −3,9°), зв. вел.': M.av_to(gal, 1.0, -3.9, 12.0),
    }
    ls = np.arange(0.5, 360, 1.0)
    res['A_V на 1 кпк в плоскости, среднее по l, зв. вел.'] = float(np.mean([M.av_to(gal, x, 0.0, 1.0, 801) for x in ls]))
    tang = {}
    for name, ref in (('Norma-Outer', 327.5), ('Sct-Cen', 306.1), ('Sgr-Car', 285.6)):
        nodes = M.arm_table()[name]
        ph = np.linspace(nodes[0][0], nodes[-1][0], 40001)
        r, _, _, _ = M.arm_centerline(nodes, ph)
        x, y = r * np.cos(np.radians(ph)), r * np.sin(np.radians(ph))
        lg = np.degrees(np.arctan2(y, M.R0 - x)) % 360
        m = (lg > 270) & (r < M.R0)
        tang[name] = (float(lg[m].min()), ref)
    return res, tang, gal.budget


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ref', default=os.path.join(HERE, 'ref', 'milkyway_2020_4k_gal_print.jpg'))
    ap.add_argument('--out', default=os.path.join(HERE, 'out'))
    ap.add_argument('--json', default=None)
    ap.add_argument('--set', action='append', default=[], metavar='KEY=VALUE', help='те же опыты, что у build_map.py')
    ap.add_argument('--repeat', default=None, metavar='DIR', help='папка второго прогона: значения должны совпасть')
    a = ap.parse_args()
    import build_map
    build_map.apply_overrides({k: json.loads(v) for k, v in (s.split('=', 1) for s in a.set)})
    rows, report, bad = [], {}, 0

    def line(name, value, ok):
        nonlocal bad
        mark = {True: 'да ', False: 'НЕТ', None: '·  '}[ok]
        bad += ok is False
        rows.append(f'  {mark} {name}: {value}')

    # файлы для приложения
    spec, glow, tau = load_model(a.out)
    h, w = tau.shape
    names = [spec['glow']['file'], spec['tau']['file'], 'spec.json']
    total = sum(os.path.getsize(os.path.join(a.out, f)) for f in names)
    line('файлы для приложения вместе', f'{total / 1e6:.2f} МБ (≤ 3)', total <= 3e6)
    line('свечение: максимум канала', f'{glow.max():.4f} (= 1)', abs(glow.max() - 1) < 1e-9)
    report['files_bytes'] = total
    if a.repeat:
        _, g2, t2 = load_model(a.repeat)
        d = max(float(np.abs(g2 - glow).max()) * 65535, float(np.abs(t2 - tau).max()) * 100)
        line('повторный прогон: те же значения в PNG', f'наибольшая разница {d:.0f} ед.', d == 0)

    res, tang, budget = model_checks()
    for k, v in res.items():
        line(k, f'{v:.2f}', None)
    report['model'] = res
    report['budget'] = budget
    line('свет у Солнца в плоскости / по столбу (функция светимости)',
         f"{budget['local_midplane_Lpc3']:.3f} L☉/пк³, {budget['local_column_Lpc2']:.1f} L☉/пк²; M/L_V старых {budget['ML_old']:.2f}", None)
    av_gc = res['A_V до центра (l = 0°, b = 0°, 8,15 кпк), зв. вел.']
    line('A_V до центра в пределах 25–45 зв. вел. (цель ≈ 30; BHG16 §4.1: ≈ 40)', f'{av_gc:.1f}', 25 <= av_gc <= 45)
    for name, (got, ref) in tang.items():
        line(f'касательная рукава {name} (Reid 2019 Table 2: {ref}°)', f'{got:.1f}°', abs(got - ref) <= 2.0)
    report['tangents'] = tang

    # тонирование, которое советуем приложению
    tn = spec['tone']
    out = sky.tone(glow, tn['k'], tn['gamma'])
    core_out = 1 - math.exp(-tn['k'] * sky.core_y(glow) ** tn['gamma'])
    line(f"тонирование γ = {tn['gamma']}, k = {tn['k']}: ядро", f'{core_out:.3f} (≈ 0,6)', abs(core_out - 0.6) < 0.02)
    c = sky.band_contrast(out @ LUMA)
    line('контраст полосы к соседнему небу (гребень |b| ≤ 10° / 20°–30°), по l', f'медиана {np.median(c):.1f}, максимум {c.max():.1f}:1 (≤ 6)', c.max() <= 6.0)
    c1 = sky.band_contrast(sky.tone(glow, tn['plain_rule_gamma_1']['k'], 1.0) @ LUMA)
    line(f"для сравнения формула задачи (γ = 1, k = {tn['plain_rule_gamma_1']['k']})", f'медиана {np.median(c1):.1f}, максимум {c1.max():.1f}:1', None)
    report['tone'] = {'core_out': core_out, 'contrast_median': float(np.median(c)), 'contrast_max': float(c.max()),
                      'plain_contrast_median': float(np.median(c1)), 'plain_contrast_max': float(c1.max())}

    lm, bm = grid(h, w)
    Ym = smooth(glow @ LUMA)
    if not os.path.exists(a.ref):
        rows.append(f'  ·   карты NASA нет ({a.ref}) — сравнение не проверялось')
        print('\n'.join(rows))
        sys.exit(2)
    Yn_raw = load_nasa(a.ref)
    hn, wn = Yn_raw.shape
    ln, bn = grid(hn, wn)
    Yn = smooth(Yn_raw)
    L, B = np.meshgrid(ln, bn)
    Ym_on_n = sky.sample(Ym, L, B)

    keep = mask_galaxies(ln, bn)
    wgt = np.cos(np.radians(B)) * keep
    floor_m = np.percentile(Ym_on_n[keep], 0.5)
    floor_n = np.percentile(Yn[keep], 0.5)
    lm_ = np.log10(np.maximum(Ym_on_n, floor_m))
    ln_ = np.log10(np.maximum(Yn, floor_n))
    r = weighted_corr(lm_, ln_, wgt)
    r_all = weighted_corr(lm_, ln_, np.cos(np.radians(B)))
    line('корреляция log свечения с NASA (σ 1°, вес cos b, без БМО/ММО)', f'{r:.3f} (≥ 0,8); с Облаками {r_all:.3f}', r >= 0.8)
    report['corr_log'] = r
    report['corr_log_with_clouds'] = r_all

    cm, cn = core_peak(Ym, lm, bm), core_peak(Yn, ln, bn)
    line('ядро: максимум свечения в |l| ≤ 3°, |b| ≤ 3°', f'модель l = {cm[0]:.1f}°, b = {cm[1]:+.1f}°', abs(cm[0]) <= 3 and abs(cm[1]) <= 3)
    line('ядро у NASA (тот же критерий)', f'l = {cn[0]:.1f}°, b = {cn[1]:+.1f}° — {"в рамке" if abs(cn[0]) <= 3 and abs(cn[1]) <= 3 else "тоже вне рамки"}', None)
    line('ядро: высота над плоскостью модели и NASA', f'|b| {abs(cm[1]):.1f}° и {abs(cn[1]):.1f}°; сторона {"та же" if cm[1] * cn[1] > 0 else "противоположная"}', None)
    report['core'] = {'model': cm, 'nasa': cn}

    ls, prof = band_profile_l(Ym, lm, bm)
    lmin = float(ls[prof.argmin()])
    line('антицентр: минимум вдоль b = 0 (|b| ≤ 1°) в l = 180° ± 25°', f'модель l = {lmin:.1f}°', abs(lmin - 180) <= 25)
    lsn, profn = band_profile_l(Yn, ln, bn)
    line('антицентр у NASA (для сравнения)', f'l = {float(lsn[profn.argmin()]):.1f}°', None)
    report['anticenter_min_l'] = {'model': lmin, 'nasa': float(lsn[profn.argmin()])}

    rm, rn = rift_ratio(Ym, lm, bm), rift_ratio(Yn, ln, bn)
    line('Большой разлом l 10°–50°: бока 2°–5° / середина |b| ≤ 1°',
         f'модель {rm[0]:.2f} (медиана по l {rm[1]:.2f}, доля l ≥ 1,3: {rm[2]:.0%}); NASA {rn[0]:.2f} ({rn[1]:.2f}, {rn[2]:.0%})', rm[0] >= 1.3)
    report['rift'] = {'model': rm, 'nasa': rn}

    report['fwhm'] = {}
    for l0 in FWHM_L:
        fm, om = fwhm(lat_profile(Ym, lm, bm, l0), bm)
        fn, on = fwhm(lat_profile(Yn, ln, bn, l0), bn)
        dev = fm / fn - 1
        line(f'ширина полосы FWHM по b на l = {l0:.0f}° (±5°)',
             f'модель {fm:.1f}°, NASA {fn:.1f}°, разница {dev:+.0%} (≤ 30 %); второй горб {om:.2f} / {on:.2f} пика', abs(dev) <= 0.30)
        report['fwhm'][str(int(l0))] = {'model': fm, 'nasa': fn, 'second_lobe': [om, on]}

    print('\n'.join(rows))
    if a.json:
        with open(a.json, 'w') as f:
            json.dump(report, f, ensure_ascii=False, indent=1)
    print('  итог: ' + ('всё да' if bad == 0 else f'«НЕТ»: {bad}'))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
