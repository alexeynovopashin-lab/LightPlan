"""Цвет звезды из BP−RP Gaia: BP−RP → B−V (медианы по звёздам Hipparcos) → температура чёрного тела
(Ballesteros 2012) → линейный sRGB (кривые сложения CIE 1931 в аналитическом приближении Wyman et al. 2013).

Белая точка — чёрное тело 5800 K (свет Солнца, «дневной» баланс белого фотографа) = (1, 1, 1).
"""
import csv
import gzip
import io

import numpy as np

T_WHITE = 5800.0
T_MIN, T_MAX = 2000.0, 40000.0

# B−V против BP−RP: интервалы BP−RP шириной 0,1; медиана B−V звёзд Hipparcos с e(B−V) < 0,03 и G > 4
# (ярче G ≈ 4 фотометрия Gaia насыщена). В интервале нужно ≥ 20 звёзд; дальше кривая сделана неубывающей:
# у M-звёзд B−V перестаёт расти с BP−RP (около 1,6–1,7), и без этого красные звёзды «синели» бы обратно.
BV_BIN = 0.1
BV_MIN_STARS = 20


def bv_table(path):
    with gzip.open(path) as f:
        rows = list(csv.reader(io.StringIO(f.read().decode("utf-8"))))
    hdr = rows[0]
    ix = {k: hdr.index(k) for k in ("bp_rp", "phot_g_mean_mag", "b_v", "e_b_v")}
    a = np.array([[float(r[ix[k]]) if r[ix[k]] else np.nan for k in ("bp_rp", "phot_g_mean_mag", "b_v", "e_b_v")]
                  for r in rows[1:]])
    x, g, bv, e = a.T
    m = (e < 0.03) & (g > 4) & np.isfinite(x) & np.isfinite(bv)
    edges = np.round(np.arange(-0.6, 4.5 + 1e-9, BV_BIN), 3)
    centers, med, cnt = [], [], []
    for lo, hi in zip(edges[:-1], edges[1:]):
        s = m & (x >= lo) & (x < hi)
        if s.sum() >= BV_MIN_STARS:
            centers.append(round(float(np.median(x[s])), 4))
            med.append(round(float(np.median(bv[s])), 4))
            cnt.append(int(s.sum()))
    med = np.maximum.accumulate(np.array(med))
    return {"bp_rp": centers, "b_v": [float(v) for v in med], "stars": cnt, "used": int(m.sum()),
            "rows": int(len(a))}


def bv_from_bprp(c, table):
    return np.interp(c, table["bp_rp"], table["b_v"])


def temp_from_bv(bv):
    """Ballesteros 2012 (EPL 97, 34008): T = 4600 K·(1/(0,92(B−V) + 1,7) + 1/(0,92(B−V) + 0,62))."""
    bv = np.clip(bv, -0.4, 2.0)
    return np.clip(4600.0 * (1.0 / (0.92 * bv + 1.7) + 1.0 / (0.92 * bv + 0.62)), T_MIN, T_MAX)


def _g(lam, mu, s1, s2):
    s = np.where(lam < mu, s1, s2)
    return np.exp(-0.5 * ((lam - mu) / s) ** 2)


def cmf(lam):
    """CIE 1931 x̄, ȳ, z̄: многолепестковое приближение Wyman, Sloan & Shirley 2013 (JCGT 2(2), 1–11); λ в нм."""
    x = 1.056 * _g(lam, 599.8, 37.9, 31.0) + 0.362 * _g(lam, 442.0, 16.0, 26.7) - 0.065 * _g(lam, 501.1, 20.4, 26.2)
    y = 0.821 * _g(lam, 568.8, 46.9, 40.5) + 0.286 * _g(lam, 530.9, 16.3, 31.1)
    z = 1.217 * _g(lam, 437.0, 11.8, 36.0) + 0.681 * _g(lam, 459.0, 26.0, 13.8)
    return np.stack([x, y, z])


# XYZ → линейный sRGB (IEC 61966-2-1, белая D65)
XYZ_TO_RGB = np.array([[3.2406, -1.5372, -0.4986],
                       [-0.9689, 1.8758, 0.0415],
                       [0.0557, -0.2040, 1.0570]])
LUMA = np.array([0.2126, 0.7152, 0.0722])


def _rgb_bb(T):
    lam = np.arange(360.0, 831.0, 1.0)
    T = np.atleast_1d(T)[:, None]
    lm = lam[None, :] * 1e-9
    planck = 1.0 / (lm ** 5 * np.expm1(1.4387769e-2 / (lm * T)))     # с точностью до множителя
    xyz = planck @ cmf(lam).T
    return xyz @ XYZ_TO_RGB.T


_T_GRID = np.geomspace(T_MIN, T_MAX, 1024)
_RGB_GRID = _rgb_bb(_T_GRID)
_RGB_GRID = _RGB_GRID / _rgb_bb(T_WHITE)[0]                          # 5800 K → (1, 1, 1)
_RGB_GRID = np.clip(_RGB_GRID, 0, None)
_CHROMA_GRID = _RGB_GRID / (_RGB_GRID @ LUMA)[:, None]               # яркость Y = 1


def chroma(T):
    """Линейный sRGB с яркостью Y = 1 для чёрного тела T (белая точка 5800 K)."""
    lt = np.log(np.clip(T, T_MIN, T_MAX))
    lg = np.log(_T_GRID)
    out = np.stack([np.interp(lt, lg, _CHROMA_GRID[:, k]) for k in range(3)], axis=-1)
    return out


def chroma_from_bprp(c, table):
    return chroma(temp_from_bv(bv_from_bprp(c, table)))
