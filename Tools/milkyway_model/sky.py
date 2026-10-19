"""Сетка неба карты, сглаживание, выборка и тонирование — общие для build_map.py и validate.py.

Карта — равнопромежуточная (plate carrée) в галактических координатах: столбец i — долгота
l = 180° − (i + 0,5)·360°/W (mod 360), то есть l = 0 посередине и растёт влево, как у карт NASA SVS;
строка j — широта b = 90° − (j + 0,5)·180°/H, сверху север.
"""
import math

import numpy as np

LUMA = np.array([0.2126, 0.7152, 0.0722])     # яркость Y из линейных R, G, B (Rec. 709)

# Тонирование для приложения (README, «Тонирование»): Y_out = 1 − exp(−k·Y^γ), цвет сохраняется.
TONE_CORE = 0.6          # ядро → 0,6
TONE_GAMMA = 0.7         # γ = 1 — формула задачи; 0,7 держит контраст полосы к соседнему небу ≤ 6:1
CORE_BOX = 10.0          # ядро — 99,9-й перцентиль сглаженной Y в |l|, |b| ≤ 10°


def grid(h, w):
    l = (180.0 - (np.arange(w) + 0.5) * 360.0 / w) % 360.0
    b = 90.0 - (np.arange(h) + 0.5) * 180.0 / h
    return l, b


def signed(l):
    return np.where(l > 180, l - 360, l)


def gauss_kernel(sigma_px):
    r = int(math.ceil(4 * sigma_px))
    x = np.arange(-r, r + 1)
    k = np.exp(-0.5 * (x / sigma_px) ** 2)
    return k / k.sum()


def smooth(img, sigma_deg=1.0):
    """Гаусс σ в градусах по сетке карты; по долготе — кольцо, по широте — отражение от полюса."""
    h, w = img.shape[:2]
    kx = gauss_kernel(sigma_deg * w / 360.0)
    r = len(kx) // 2
    a = np.concatenate([img[:, -r:], img, img[:, :r]], axis=1)
    a = sum(kx[i] * a[:, i:i + w] for i in range(len(kx)))
    ky = gauss_kernel(sigma_deg * h / 180.0)
    r = len(ky) // 2
    a = np.concatenate([a[r - 1::-1], a, a[:-r - 1:-1]], axis=0)
    return sum(ky[i] * a[i:i + h] for i in range(len(ky)))


def sample(img, l_deg, b_deg):
    """Билинейная выборка карты (H, W[, C]) в точках l, b; по долготе с повтором."""
    h, w = img.shape[:2]
    fu = ((0.5 - l_deg / 360.0) % 1.0) * w - 0.5
    fv = np.clip((0.5 - b_deg / 180.0) * h - 0.5, 0, h - 1.000001)
    i0 = np.floor(fu).astype(int)
    j0 = np.floor(fv).astype(int)
    tu, tv = fu - i0, fv - j0
    if img.ndim == 3:
        tu, tv = tu[..., None], tv[..., None]
    i0 %= w
    i1 = (i0 + 1) % w
    j1 = np.minimum(j0 + 1, h - 1)
    return ((img[j0, i0] * (1 - tu) + img[j0, i1] * tu) * (1 - tv)
            + (img[j1, i0] * (1 - tu) + img[j1, i1] * tu) * tv)


def core_y(glow):
    """Яркость ядра для тонирования: 99,9-й перцентиль сглаженной Y в |l|, |b| ≤ CORE_BOX."""
    Y = smooth(glow @ LUMA)
    l, b = grid(*Y.shape)
    m = (np.abs(b)[:, None] <= CORE_BOX) & (np.abs(signed(l))[None, :] <= CORE_BOX)
    return float(np.percentile(Y[m], 99.9))


def tone_k(glow, gamma=TONE_GAMMA):
    return -math.log(1 - TONE_CORE) / core_y(glow) ** gamma


def tone(glow, k, gamma=TONE_GAMMA):
    """out_c = I_c · (1 − exp(−k·Y^γ)) / Y, обрезка в [0, 1]: яркость сжимается, оттенок остаётся."""
    Y = glow @ LUMA
    Yc = np.maximum(Y, 1e-30)
    f = np.where(Y > 0, -np.expm1(-k * Yc ** gamma) / Yc, 0.0)
    return np.clip(glow * f[..., None], 0, 1)


def band_contrast(out_y):
    """Контраст полосы к соседнему небу по долготе (шаг 1°): гребень (max при |b| ≤ 10°) / среднее при
    20° ≤ |b| ≤ 30°, на сглаженной (σ 1°) тонированной яркости."""
    h, w = out_y.shape
    l, b = grid(h, w)
    s = smooth(out_y)
    ridge_rows = np.abs(b) <= 10
    side_rows = (np.abs(b) >= 20) & (np.abs(b) <= 30)
    res = []
    for x in np.arange(0.5, 360, 1.0):
        cols = np.abs(((l - x + 180) % 360) - 180) <= 0.5
        res.append(s[ridge_rows][:, cols].max() / s[side_rows][:, cols].mean())
    return np.array(res)
