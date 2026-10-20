"""Общее для fetch.py, build.py, validate.py и preview.py: пути, сетка неба, формат stars_gaia.bin,
переход ICRS → галактические координаты, выбор звёзд для сверки с SIMBAD.

Карта — равнопромежуточная (plate carrée) в галактических координатах, как у карт NASA SVS:
столбец i — долгота l = 180° − (i + 0,5)·360°/W (mod 360), то есть l = 0 посередине и растёт влево;
строка j — широта b = 90° − (j + 0,5)·180°/H, сверху северный полюс Галактики.
Ячейки сервера ESA считаются в другой нумерации (il = floor(l·8), ib = floor((b + 90)·8)), перевод — cell_to_pixel.
"""
import math
import os
import struct

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
RAW_BRIGHT = os.path.join(RAW, "bright")
RAW_GLOW = os.path.join(RAW, "glow")
RAW_JUDGE = os.path.join(RAW, "judge")
RAW_COLOR = os.path.join(RAW, "color")
COLOR_FILE = os.path.join(RAW_COLOR, "hip_bv.csv.gz")
RAW_META = os.path.join(RAW, "meta.json")
GRID_CACHE = os.path.join(RAW, "glow_grid.npz")
FULL_PNG = os.path.join(RAW, "milkyway_glow_gaia_2880x1440.png")
JUDGE_FILE = os.path.join(RAW_JUDGE, "milkyway_2020_4k_gal_print.jpg")
JUDGE_URL = "https://svs.gsfc.nasa.gov/vis/a000000/a004800/a004851/milkyway_2020_4k_gal_print.jpg"
SIMBAD_FILE = os.path.join(HERE, "check", "simbad20.json")

TAP_ESA = "https://gea.esac.esa.int/tap-server/tap"
TAP_SIMBAD = "https://simbad.cds.unistra.fr/simbad/sim-tap"

# Граница ярких звёзд (точки) и свечения (карта): G ≤ G_BRIGHT — в stars_gaia.bin, G_BRIGHT < G ≤ G_FAINT — в карте.
G_BRIGHT = 10.0
G_FAINT = 21.0
CELL_DEG = 0.125                  # шаг сетки сервера: 2880 × 1440
CELLS_L = 2880
CELLS_B = 1440
HPX_LEVEL = 2                     # куски запросов: HEALPix уровня 2, 192 куска (source_id кодирует место на небе)
HPX_STEP = 2 ** 35 * 4 ** (12 - HPX_LEVEL)   # source_id = 2^35 · (номер HEALPix уровня 12) + …

# Срезы ярких звёзд по величине: каждый срез — отдельный запрос (у сервера есть индекс по G, срез идёт секунды).
BRIGHT_SLICES = [(-5.0, 6.0), (6.0, 7.0), (7.0, 8.0), (8.0, 8.5), (8.5, 9.0), (9.0, 9.5), (9.5, 10.0)]

LUMA = np.array([0.2126, 0.7152, 0.0722])     # яркость Y из линейных R, G, B (Rec. 709 / sRGB)


# ---------------------------------------------------------------- сетка

def grid(h, w):
    """Долготы столбцов и широты строк карты (центры пикселей), градусы."""
    l = (180.0 - (np.arange(w) + 0.5) * 360.0 / w) % 360.0
    b = 90.0 - (np.arange(h) + 0.5) * 180.0 / h
    return l, b


def signed(l):
    return np.where(l > 180, l - 360, l)


def cell_to_pixel(il, ib):
    """Ячейка сервера (il = floor(l·8), ib = floor((b + 90)·8)) → (строка, столбец) карты 2880 × 1440.
    Центр ячейки il — l = (il + 0,5)/8; в карте столбец i с тем же центром: i = 1439 − il (mod 2880)."""
    col = (CELLS_L // 2 - 1 - il) % CELLS_L
    row = CELLS_B - 1 - ib
    return row, col


def gauss_kernel(sigma_px):
    r = max(1, int(math.ceil(4 * sigma_px)))
    x = np.arange(-r, r + 1)
    k = np.exp(-0.5 * (x / sigma_px) ** 2)
    return k / k.sum()


def smooth(img, sigma_deg):
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
    """Билинейная выборка карты (H, W[, C]) в точках l, b; по долготе с повтором (так читает и GPU)."""
    h, w = img.shape[:2]
    fu = ((0.5 - np.asarray(l_deg) / 360.0) % 1.0) * w - 0.5
    fv = np.clip((0.5 - np.asarray(b_deg) / 180.0) * h - 0.5, 0, h - 1.000001)
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


def downsample2(img):
    """Вдвое меньше по каждой оси, среднее 2 × 2 (поток на площадь сохраняется)."""
    h, w = img.shape[:2]
    return img.reshape(h // 2, 2, w // 2, 2, *img.shape[2:]).mean(axis=(1, 3))


# ---------------------------------------------------------------- координаты

# ICRS → галактические: матрица A_G из тома 1 каталога Hipparcos (ESA 1997, § 1.5.3);
# ею же Gaia считает столбцы l, b (validate.py сверяет: расхождение должно быть меньше 0,01″).
A_G = np.array([[-0.0548755604162154, -0.8734370902348850, -0.4838350155487132],
                [+0.4941094278755837, -0.4448296299600112, +0.7469822444972189],
                [-0.8676661490190047, -0.1980763734312015, +0.4559837761750669]])


def icrs_to_gal(ra, dec):
    ra, dec = np.radians(ra), np.radians(dec)
    v = np.stack([np.cos(dec) * np.cos(ra), np.cos(dec) * np.sin(ra), np.sin(dec)])
    g = A_G @ v.reshape(3, -1)
    l = np.degrees(np.arctan2(g[1], g[0])) % 360.0
    b = np.degrees(np.arcsin(np.clip(g[2], -1, 1)))
    return l.reshape(np.shape(ra)), b.reshape(np.shape(ra))


def sep_deg(l1, b1, l2, b2):
    """Угловое расстояние, градусы (формула гаверсинусов)."""
    l1, b1, l2, b2 = map(np.radians, (l1, b1, l2, b2))
    h = np.sin((b2 - b1) / 2) ** 2 + np.cos(b1) * np.cos(b2) * np.sin((l2 - l1) / 2) ** 2
    return np.degrees(2 * np.arcsin(np.sqrt(np.clip(h, 0, 1))))


# ---------------------------------------------------------------- stars_gaia.bin

BIN_MAGIC = b"LPGS"
BIN_VERSION = 1
BIN_HEADER = 16
BIN_RECORD = 8
BIN_DTYPE = np.dtype([("l", "<u2"), ("b", "<i2"), ("g", "u1"), ("c", "i1"), ("flags", "u1"), ("pad", "u1")])
L_SCALE = 65536 / 360.0            # l = raw · 360/65536
B_SCALE = 65536 / 180.0            # b = raw · 180/65536
G_SCALE = 10.0                     # G = raw / 10
C_SCALE = 10.0                     # BP−RP = (raw + C_OFFSET) / 10
C_OFFSET = 0
FLAG_COLOR_FROM_G = 1              # бит 0: BP−RP у звезды нет, поставлен типичный для её G


def read_bin(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, rec, count, gmax10, _ = struct.unpack_from("<4sHHIHH", data, 0)
    if magic != BIN_MAGIC or version != BIN_VERSION or rec != BIN_RECORD:
        raise ValueError(f"{path}: не stars_gaia.bin v{BIN_VERSION} ({magic!r}, v{version}, {rec} байт)")
    if len(data) != BIN_HEADER + count * rec:
        raise ValueError(f"{path}: длина {len(data)} не сходится с числом записей {count}")
    r = np.frombuffer(data, dtype=BIN_DTYPE, offset=BIN_HEADER, count=count)
    return {
        "l": r["l"] / L_SCALE,
        "b": r["b"] / B_SCALE,
        "g": r["g"] / G_SCALE,
        "c": (r["c"].astype(float) + C_OFFSET) / C_SCALE,
        "flags": r["flags"].copy(),
        "g_max": gmax10 / 10.0,
        "count": count,
    }


# ---------------------------------------------------------------- сверка с SIMBAD

SIMBAD_G_BINS = [(3.0, 5.0), (5.0, 6.5), (6.5, 8.0), (8.0, 9.0), (9.0, 10.0)]
SIMBAD_B_BINS = [(0.0, 5.0), (5.0, 20.0), (20.0, 50.0), (50.0, 90.01)]


def simbad_pick(source_id, g, b):
    """20 звёзд для сверки: 5 интервалов G × 4 интервала |b|, в каждом — звезда с наименьшим
    (source_id mod 1 000 003): правило без случайных чисел, но не «самая северная» и не «самая яркая»."""
    picks = []
    key = source_id % 1000003
    for g0, g1 in SIMBAD_G_BINS:
        for b0, b1 in SIMBAD_B_BINS:
            m = (g > g0) & (g <= g1) & (np.abs(b) >= b0) & (np.abs(b) < b1)
            idx = np.flatnonzero(m)
            if len(idx):
                picks.append(int(idx[np.argmin(key[idx])]))
    return picks
