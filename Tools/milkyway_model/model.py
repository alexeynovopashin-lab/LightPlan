#!/usr/bin/env python3
"""Модель Галактики для карты Млечного Пути: светимость звёзд и плотность пыли в каждой точке.

Только опубликованные формулы и параметры (источники — README.md, раздел «Модель»); чужого кода нет.
Случайных чисел нет: карта — интеграл гладких функций, повтор прогона даёт те же числа.

Координаты — как у Drimmel & Spergel 2001 (DS01), ур. 11: центр Галактики в начале, Солнце в (R0, 0, Z_SUN),
    x = R0 − s·cos b·cos l,   y = s·cos b·sin l,   z = Z_SUN + s·sin b,
азимут φ = atan2(y, x): 0 — на Солнце, растёт по вращению Галактики (к l = 90°). Это же азимут β у Reid et al.
2019 (§3: «0 toward the Sun and increasing in the direction of Galactic rotation»). Длины — кпк.

Две популяции звёзд: старая (тонкий и толстый диск, балдж, длинная перемычка; тёплый свет) и молодая (рукава;
холодно-белый свет). Свет тонкого диска — по функции светимости: каждая звёздная величина со своей толщиной
слоя, и звёзды ярче V_cut с данного расстояния в свечение не входят. Пыль: диск с дырой в центре, утолщением к
краю и изгибом + усиление вдоль рукавов; свет проходит её с поправкой на облачность.
"""
import math

import numpy as np

DEG = math.pi / 180

# Длины DS01 даны «в единицах R_sun = 8 кпк» (DS01 §2: модель безразмерна, R_sun ≡ 1; §4: «units where
# R_sun = 8 kpc»). Переводим их к нашему R0 одним множителем.
R0 = 8.15                      # кпк, Reid et al. 2019, Table 3 (подгонки A5 и B)
Z_SUN = 0.0208                 # кпк, Bennett & Bovy 2019
K_DS = R0 / 8.0

PARAMS = {
    # --- Тонкий диск: свет считаем по функции светимости, а не по массе. Свет в V дают в основном яркие звёзды
    #     (A, B, гиганты), а их слой тонкий (90 пк); 300 пк BHG16 — шкала массы, её держат слабые карлики.
    #   Φ(M_V) = n*·10^(β·x) / (1 + 10^(−(α−β)δ·x))^(1/δ), x = M_V − M*: n* 4·10⁻³ пк⁻³, M* 1,28, α 0,74, β 0,04,
    #   1/δ 3,4 — Bahcall & Soneira 1980, с. 77 (аппроксимация функции Лейтена);
    #   шкала высоты H(M_V): 90 пк при M_V < 2,3; 90 + 83,9·(M_V − 2,3) пк до 5,1; 325 пк ярче — Bahcall 1986, с. 595.
    #   Обе формулы дословно — Paczyński & Stanek 1994 (astro-ph/9402025), ур. 2–3. Пределы M_V −6…+16 — наши.
    #   Радиальная шкала 2,6 кпк (BHG16 §5.1.3). Звёзды ярче M_young (B5 и раньше, сверхгиганты) — молодое
    #   население: их свет уходит в рукава (ниже), остальное — гладкий старый диск.
    'thin':  dict(h_r=2.6),
    'lf':    dict(n_star=4.0e-3, M_star=1.28, alpha=0.74, beta=0.04, inv_delta=3.4, M_min=-6.0, M_max=16.0, dM=0.1,
                  M_young=-1.0, H_bright=0.090, H_faint=0.325, M_bright=2.3, M_faint=5.1, M_sun_V=4.83),
    # Звёзды ярче V_cut в свечение не входят: приложение рисует яркие звёзды само (каталог), а судья — карта NASA
    # «milkyway» — тоже без звёзд Hipparcos/Tycho; Tycho-2 полон до V ≈ 11 (Høg et al. 2000). Видимая величина
    # звезды считается с поглощением на пути до неё.
    'V_cut': 11.0,
    # Весь свет Галактики в V: M_V = −21,37 (BHG16 Table 4, по Licquia et al. 2015). Что не дал тонкий диск по
    # функции светимости, делят балдж, перемычка и толстый диск пропорционально массе (одно M/L на старые звёзды).
    'galaxy_MV': -21.37,
    'thick': dict(mass=6.0e9, h_r=2.0, h_z=0.900),      # BHG16 §5.2.2 / §5.1.3: R 2,0 ± 0,2; Z 900 ± 180 пк; M 6e9
    # Обрез звёздного диска DS01 ур. 27: f = exp(−(r − r_c)/(r_*/5)) при r > r_c; r_c = 10,52, r_* = 2,264 (Table 2)
    'cut':   dict(r_c=10.52 * K_DS, scale=2.264 * K_DS / 5.0),
    # Балдж-«арахис»: экспонента по эллипсоиду, шкалы по осям 0,70 : 0,44 : 0,18 кпк (Wegg & Gerhard 2013, §8),
    # угол перемычки 27° (там же; BHG16 §4.2.1: 27 ± 2°); масса (1,4–1,7)e10 (BHG16 §4.2.4) → 1,5e10.
    'bulge': dict(mass=1.5e10, x0=0.70, y0=0.44, z0=0.18, angle=27.0),
    # Длинная перемычка (BHG16 §4.3, по Wegg, Gerhard & Portail 2015): полудлина 5,0 ± 0,2 кпк, угол 28–33° → 28°,
    # тонкая часть h 180 пк, M ≈ 7e9; сверхтонкая h 45 пк, M ≈ 3e9. Профиль вдоль оси — exp(−(x'/R)^4) (плоский до
    # конца и обрыв), поперёк в плоскости — экспонента 0,5 кпк: наше допущение, в обзоре формы нет.
    'longbar': dict(half_length=5.0, angle=28.0, y_scale=0.5,
                    parts=[dict(mass=7e9, h_z=0.180), dict(mass=3e9, h_z=0.045)]),
    # Изгиб диска DS01 ур. 30–31: Z_w = a_w·(r − r_w)²·sin(φ − φ_w) при r > r_w (r_w 6,993 кпк, φ_w −0,12°,
    # Table 1); a_w звёзд 27,4 пк/кпк² (Table 2), пыли 72,8 пк/кпк² (Table 1).
    'warp':  dict(r_w=6.993, phi_w=-0.12, a_star=0.0274, a_dust=0.0728),
    # Молодое население живёт в рукавах (геометрия Reid 2019): плотность ∝ профиль рукава / профиль у Солнца, так
    # что у Солнца она равна местной функции светимости, а в середине рукава выше.

    # --- Пыль: форма DS01 ур. 13–17 (Table 1) с геометрией рукавов Reid 2019 вместо Taylor & Cordes.
    #   по высоте: exp(−|z|/h_d(R)); тонкий пылевой диск утолщается с радиусом от 60 пк (R = 5 кпк) до 200 пк
    #   (R = 14 кпк) — Zhang, Yuan, Chen et al. 2026 (arXiv:2601.02724, аннотация; 5 млн звёзд, R 5–14 кпк);
    #   внутри 5 кпк держим 60 пк, снаружи 14 — 200 пк. У Солнца это 109 пк — как 103 пк у Li, Shen & Hou 2018
    #   (arXiv:1803.10540: экспоненциальный диск, Солнце на 23 пк выше него). Толстый пылевой диск той же работы
    #   (300–800 пк) не моделируем: в аннотации нет его доли. Слои DS01 (sech² 134 пк + расширение) и
    #   Marshall et al. 2006 (sech² 125 пк) толще у центра: окно Бааде давало A_V 6,4–7,7 при измеренных ≈ 1,5–2;
    #   по радиусу: exp(−R/h_r), h_r = 2,26 кпк (DS01 Table 1, подгонка по всей Галактике; у Li 2018 3,19 кпк по
    #   внешнему диску, с ней A_V до центра ≈ 23 вместо измеренных 30–40);
    #   дыра: при R < 0,5·R0 плотность = ρ(0,5·R0)·exp(−((R − 0,5R0)/0,25R0)²) (DS01 §3.1, текст после ур. 14);
    #   рукава: A_d·ρ_диск(R, 0)·профиль поперёк·exp(−(z/h_a)²), h_a = 80 пк (DS01 Table 1, h_{0,a}).
    # Нормировка — средняя A_V на первый кпк в плоскости 1,8 зв. вел. (по всем l). A_d = 1 — наше допущение.
    'dust':  dict(h_r=2.26 * K_DS, h_in=0.060, h_out=0.200, R_in=5.0, R_out=14.0, hole=0.5, hole_w=0.25,
                  arm_amp=1.0, arm_h0=0.080,
                  av_per_kpc=1.8,         # средняя A_V на первый кпк в плоскости (по всем l) — нормировка
                  bubble_r=0.0),          # радиус «Местного пузыря» без пыли, кпк (0 — нет; опыты — README)
    # Облачность: часть пыли f(R) сидит в облаках с A_V облака av_cloud; для облаков, разбросанных по Пуассону,
    # среднее пропускание exp(−N̄·(1 − e^(−τ_обл))) (Natta & Panagia 1984; пересказ — Városi & Dwek 1999, §2),
    # то есть свет проходит с τ_эфф = τ·[(1 − f) + f·(1 − e^(−τ_обл))/τ_обл]. Средняя толщина τ (карта τ, A_V до
    # центра) от этого не меняется. f(R) = f_min + (f_max − f_min)/(1 + exp((R − R_half)/width)) — доля
    # молекулярного газа: > 0,5 при R < 5 кпк, < 0,1 при R > 8 кпк (Nakanishi & Sofue 2016, §4.6).
    # A_V облака 5 зв. вел. — столбец гигантского облака ~10²² см⁻² (закон Ларсона) при N_H/A_V = 1,87·10²¹.
    # f_min = 0,3 — подобрано (README, «Подбор»): пятнистость пыли у Солнца (облака пояса Гулда, холодный HI)
    # сверх средней по кольцу доли молекул; без неё полоса на l = 90° шире NASA на 44 %.
    'clump': dict(f_min=0.3, f_max=1.0, R_half=5.0, width=1.3, av_cloud=5.0),
    # Закон поглощения Cardelli, Clayton & Mathis 1989, ур. 3a–3b, R_V = 3,1.
    'Rv': 3.1,
    # Каналы (эффективные длины волн, мкм) и цвет популяций: чёрное тело с температурой по показателю цвета B−V
    # (формула Ballesteros 2012, EPL 97, 34008); белая точка — 5800 K (свет Солнца, B−V 0,65 → 5780 K).
    # Старые звёзды: B−V = 0,73 — цвет всей Галактики (BHG16 Table 4, по Licquia et al. 2015) → ≈ 5500 K;
    # молодые: B−V = 0 (интегральный свет B- и A-звёзд, наше допущение) → ≈ 10 100 K. Тёплый вид ядра даёт пыль.
    'lambda_um': (0.65, 0.55, 0.45),
    'BV_old': 0.73, 'BV_young': 0.0, 'T_white': 5800.0,
}

# Рукава Reid et al. 2019, Table 2: (β_kink°, R_kink кпк, ψ<°, ψ>°, ширина σ при R_kink кпк); ln(R/R_kink) =
# −(β − β_kink)·tan ψ (§3). Ширина растёт 42 пк/кпк (§3). Диапазон β с данными в таблице уже наших: рукава
# продлены по той же спирали (так делает и сама статья, §6 и рис. 1), концы мягко гаснут (TAPER°).
REID = {
    'Norma':   (18.0, 4.46, -1.0, 19.5, 0.14),
    'Sct-Cen': (23.0, 4.91, 14.1, 12.1, 0.23),
    'Sgr-Car': (24.0, 6.04, 17.1, 1.0, 0.27),
    'Local':   (9.0, 8.26, 11.4, 11.4, 0.31),
    'Perseus': (40.0, 8.87, 10.3, 8.7, 0.35),
    'Outer':   (18.0, 12.24, 3.0, 9.4, 0.65),
}
DW_DR = 0.042
TAPER = 20.0


def reid_r(arm, beta):
    """Радиус спирали Reid 2019 при азимуте β (градусы)."""
    bk, rk, plt, pgt, _ = REID[arm]
    psi = plt if beta <= bk else pgt
    return rk * math.exp(-(beta - bk) * DEG * math.tan(psi * DEG))


def reid_w(arm, r):
    bk, rk, plt, pgt, w = REID[arm]
    return w + DW_DR * (r - rk)


def _nodes(arm, betas, shift=0.0):
    return [(b + shift, reid_r(arm, b), reid_w(arm, reid_r(arm, b))) for b in betas]


def arm_table():
    """Рукава модели: имя → узлы (φ°, R кпк, σ кпк) по возрастанию φ; между узлами ln R линейна по φ (спираль).

    Норма–Внешний — один рукав (Reid 2019 §3: «Most likely the Norma arm wraps around the far side of the Galactic
    center and becomes the Outer arm»): участок Внешнего сдвинут на виток (φ = β − 360°), за центром — перемычка
    постоянного шага между концом Нормы за касательной l ≈ 328° и концом данных Внешнего (β = 71°). Щит–Центавр
    продолжается за центр во «внешний Щит–Центавр» (§6). Персей — до дальнего конца бара (§6), Местный — отрезок.
    Пределы продления по β: дальше рукава пересекали бы соседние (Reid §6: «arms do not cross each other»).
    """
    return {
        'Norma-Outer': _nodes('Outer', [-40.0, 18.0, 71.0], shift=-360.0) + _nodes('Norma', [-70.0, 18.0, 60.0]),
        'Sct-Cen':     _nodes('Sct-Cen', [-260.0, 23.0, 104.0]),
        'Sgr-Car':     _nodes('Sgr-Car', [-120.0, 24.0, 130.0]),
        'Local':       _nodes('Local', [-30.0, 9.0, 50.0]),
        'Perseus':     _nodes('Perseus', [-60.0, 40.0, 207.0]),
    }


def arm_centerline(nodes, phi):
    """R центра рукава, tan ψ и σ при развёрнутом азимуте phi (градусы, массив); вне диапазона — NaN."""
    ph = np.array([n[0] for n in nodes])
    lr = np.log([n[1] for n in nodes])
    sg = np.array([n[2] for n in nodes])
    inside = (phi >= ph[0]) & (phi <= ph[-1])
    p = np.clip(phi, ph[0], ph[-1])
    k = np.clip(np.searchsorted(ph, p, side='right') - 1, 0, len(ph) - 2)
    t = (p - ph[k]) / (ph[k + 1] - ph[k])
    lnr = lr[k] + t * (lr[k + 1] - lr[k])
    tanpsi = -(lr[k + 1] - lr[k]) / ((ph[k + 1] - ph[k]) * DEG)
    sigma = sg[k] + t * (sg[k + 1] - sg[k])
    taper = np.minimum(np.clip((p - ph[0]) / TAPER, 0, 1), np.clip((ph[-1] - p) / TAPER, 0, 1))
    taper = taper * taper * (3 - 2 * taper)
    r = np.where(inside, np.exp(lnr), np.nan)
    return r, tanpsi, np.maximum(sigma, 0.10), taper


def arm_profile(x, y, arms=None):
    """Поперечный профиль ближайшего рукава в плоскости: max по рукавам и виткам exp(−d²/2σ²)·затухание концов
    (выбор «ближайшего» — как DS01 §3.1: берётся рукав, где exp−(d/w)² наибольший)."""
    arms = arms or arm_table()
    r = np.hypot(x, y)
    phi = np.degrees(np.arctan2(y, x))
    best = np.zeros_like(r)
    for nodes in arms.values():
        lo, hi = nodes[0][0], nodes[-1][0]
        for k in range(int(math.floor((lo - 180) / 360)), int(math.ceil((hi + 180) / 360)) + 1):
            pu = phi + 360.0 * k
            if pu.max() < lo or pu.min() > hi:
                continue
            ra, tanpsi, sg, tp = arm_centerline(nodes, pu)
            d = np.abs(r - ra) / np.sqrt(1 + tanpsi * tanpsi)
            v = np.where(np.isnan(ra), 0.0, tp * np.exp(-0.5 * (d / sg) ** 2))
            best = np.maximum(best, v)
    return best


class ArmGrid:
    """Профиль рукавов на сетке 20 пк в квадрате ±20 кпк; внутри лучей — билинейная выборка (быстрее в ~10 раз)."""

    def __init__(self, half=20.0, step=0.02):
        self.half, self.step = half, step
        n = int(round(2 * half / step)) + 1
        self.n = n
        ax = -half + step * np.arange(n)
        rows = []
        for i in range(0, n, 250):            # кусками, чтобы не держать все временные массивы сразу
            xx, yy = np.meshgrid(ax[i:i + 250], ax, indexing='ij')
            rows.append(arm_profile(xx, yy))
        self.grid = np.concatenate(rows, axis=0).ravel()

    def __call__(self, x, y):
        fx = np.clip((x + self.half) / self.step, 0, self.n - 1.000001)
        fy = np.clip((y + self.half) / self.step, 0, self.n - 1.000001)
        i = fx.astype(np.int64)
        j = fy.astype(np.int64)
        tx = fx - i
        ty = fy - j
        g = self.grid
        b = i * self.n + j
        return ((g[b] * (1 - ty) + g[b + 1] * ty) * (1 - tx)
                + (g[b + self.n] * (1 - ty) + g[b + self.n + 1] * ty) * tx)



def warp_z(r, phi_rad, a, P):
    w = P['warp']
    rr = r / K_DS - w['r_w']
    return np.where(rr > 0, K_DS * a * rr * rr, 0.0) * np.sin(phi_rad - w['phi_w'] * DEG)


def star_cut(r, P):
    c = P['cut']
    return np.where(r > c['r_c'], np.exp(-(r - c['r_c']) / c['scale']), 1.0)


class LumTable:
    """Свет популяции звёзд в единице объёма, L☉/пк³, по высоте |z| над плоскостью и пределу m_lim: учитываются
    звёзды с M_V > m_lim (те, что слабее V_cut с данного расстояния). Билинейная выборка по сетке."""
    Z_STEP, M_LO, M_STEP = 0.005, -12.0, 0.1

    def __init__(self, weights, heights, mags, z_max=6.0):
        zt = np.arange(0, z_max + 1e-9, self.Z_STEP)
        mt = np.arange(self.M_LO, 30.0 + 1e-9, self.M_STEP)
        e = weights[None, :] * np.exp(-zt[:, None] / heights[None, :])         # (z, M)
        tail = np.cumsum(e[:, ::-1], axis=1)[:, ::-1]                         # Σ по M ≥ M_k
        k = np.searchsorted(mags, mt, side='right')                           # первый бин с M > m
        self.t = np.where(k[None, :] < len(mags), tail[:, np.minimum(k, len(mags) - 1)], 0.0)
        self.nz, self.nm = self.t.shape
        self.flat = self.t.ravel()
        self.mid_all = float(self.t[0, 0])

    def __call__(self, az, m_lim=None):
        fz = np.clip(az / self.Z_STEP, 0, self.nz - 1.000001)
        iz = fz.astype(np.int64)
        tz = fz - iz
        if m_lim is None:
            return self.t[iz, 0] * (1 - tz) + self.t[iz + 1, 0] * tz
        fm = np.clip((m_lim - self.M_LO) / self.M_STEP, 0, self.nm - 1.000001)
        im = fm.astype(np.int64)
        tm = fm - im
        b = iz * self.nm + im
        f = self.flat
        return ((f[b] * (1 - tm) + f[b + 1] * tm) * (1 - tz)
                + (f[b + self.nm] * (1 - tm) + f[b + self.nm + 1] * tm) * tz)


def luminosity_function(P=PARAMS):
    """Бины M_V, Φ (пк⁻³ на бин), L (L☉) и H (кпк) по Bahcall & Soneira 1980 и Bahcall 1986."""
    f = P['lf']
    M = np.arange(f['M_min'] + f['dM'] / 2, f['M_max'], f['dM'])
    x = M - f['M_star']
    delta = 1.0 / f['inv_delta']
    phi = f['n_star'] * 10 ** (f['beta'] * x) / (1 + 10 ** (-(f['alpha'] - f['beta']) * delta * x)) ** f['inv_delta']
    lum = 10 ** (-0.4 * (M - f['M_sun_V']))
    H = np.where(M < f['M_bright'], f['H_bright'],
                 np.where(M < f['M_faint'], f['H_bright'] + (f['H_faint'] - f['H_bright']) / (f['M_faint'] - f['M_bright'])
                          * (M - f['M_bright']), f['H_faint']))
    return M, phi * f['dM'], lum, H


class Galaxy:
    def __init__(self, P=PARAMS, arms=None):
        self.P = P
        self.arms = arms if arms is not None else ArmGrid()
        M, phi, lum, H = luminosity_function(P)
        w = phi * lum * np.exp(Z_SUN / H)          # Φ·L в плоскости (функция светимости измерена у Солнца, z = Z_SUN)
        young = M < P['lf']['M_young']
        self.lt_thin = LumTable(np.where(young, 0.0, w), H, M)
        self.lt_young = LumTable(np.where(young, w, 0.0), H, M)
        wt = np.where(young, 0.0, w)
        self.lt_thick = LumTable(wt / wt.sum(), np.full_like(H, P['thick']['h_z']), M)
        self.arm_sun = float(self.arms(np.array([R0]), np.array([0.0]))[0])
        self._budget(M, phi, lum, H, w, young)
        self.kappa = 1.0                       # τ_V на кпк при единичной плотности пыли — ставит calibrate_dust

    def _budget(self, M, phi, lum, H, w, young):
        """Светимости компонент (L☉) из полного света Галактики; старым — по массе."""
        P = self.P
        g = self.arms
        n = g.n
        ax = -g.half + g.step * np.arange(n)
        X, Y = np.meshgrid(ax, ax, indexing='ij')
        R = np.hypot(X, Y)
        env = np.exp(-(R - R0) / P['thin']['h_r']) * star_cut(R, P)
        area = g.step ** 2 * 1e6                                   # пк² на ячейку
        col_old = float((np.where(young, 0, w) * 2 * H * 1e3).sum())  # L☉/пк² у Солнца (H в пк)
        col_young = float((np.where(young, w, 0) * 2 * H * 1e3).sum())
        L_thin = col_old * area * env.sum()
        L_young = col_young * area * (env * g.grid.reshape(n, n) / self.arm_sun).sum()
        L_gal = 10 ** (-0.4 * (P['galaxy_MV'] - P['lf']['M_sun_V']))
        lb = P['longbar']
        masses = {'bulge': P['bulge']['mass'], 'thick': P['thick']['mass']}
        masses.update({f'longbar{i}': p['mass'] for i, p in enumerate(lb['parts'])})
        L_rest = L_gal - L_thin - L_young
        if L_rest <= 0:
            raise ValueError(f'свет тонкого диска {L_thin:.3g} + молодых {L_young:.3g} больше всего света {L_gal:.3g}')
        ups = sum(masses.values()) / L_rest
        self.budget = dict(L_galaxy=L_gal, L_thin_old=L_thin, L_young=L_young, L_old_rest=L_rest, ML_old=ups,
                           local_midplane_Lpc3=float(w.sum()), local_column_Lpc2=col_old + col_young)
        b = P['bulge']
        self.bulge_rho = P['bulge']['mass'] / ups / (8 * math.pi * b['x0'] * b['y0'] * b['z0']) / 1e9
        gx = 2 * lb['half_length'] * math.gamma(1.25)
        self.lb_rho = [p['mass'] / ups / (gx * 2 * lb['y_scale'] * 2 * p['h_z']) / 1e9 for p in lb['parts']]
        tk = P['thick']
        self.thick_rho = tk['mass'] / ups / (4 * math.pi * tk['h_r'] ** 2 * tk['h_z']) / 1e9

    # --- звёзды -------------------------------------------------------------------------------------------
    def stars(self, x, y, z, arm=None, m_lim=None):
        """(старые, молодые) — свет в V, L☉/пк³; m_lim — самая яркая абсолютная величина, что ещё входит (None — все)."""
        P = self.P
        r = np.hypot(x, y)
        phi = np.arctan2(y, x)
        cut = star_cut(r, P)
        az = np.abs(z - warp_z(r, phi, P['warp']['a_star'], P))
        env = np.exp(-(r - R0) / P['thin']['h_r']) * cut
        old = env * self.lt_thin(az, m_lim)
        tk = P['thick']
        old += self.thick_rho * np.exp(-r / tk['h_r']) * cut * self.lt_thick(az, m_lim)
        b = P['bulge']
        ca, sa = math.cos(b['angle'] * DEG), math.sin(b['angle'] * DEG)
        xb = x * ca + y * sa
        yb = -x * sa + y * ca
        m = np.sqrt((xb / b['x0']) ** 2 + (yb / b['y0']) ** 2 + (z / b['z0']) ** 2)
        old += self.bulge_rho * np.exp(-m)
        lb = P['longbar']
        ca, sa = math.cos(lb['angle'] * DEG), math.sin(lb['angle'] * DEG)
        xl = x * ca + y * sa
        yl = -x * sa + y * ca
        plane = np.exp(-(xl / lb['half_length']) ** 4 - np.abs(yl) / lb['y_scale'])
        for rho, part in zip(self.lb_rho, lb['parts']):
            old += rho * plane * np.exp(-np.abs(z) / part['h_z'])
        if arm is None:
            arm = self.arms(x, y)
        young = env * (arm / self.arm_sun) * self.lt_young(az, m_lim)
        return old, young

    # --- пыль ---------------------------------------------------------------------------------------------
    def dust(self, x, y, z, arm=None):
        """Плотность пыли (безразмерная; τ_V на кпк = kappa·dust)."""
        d = self.P['dust']
        r = np.hypot(x, y)
        phi = np.arctan2(y, x)
        zd = z - warp_z(r, phi, self.P['warp']['a_dust'], self.P)
        rh = d['hole'] * R0
        rad = np.where(r >= rh, np.exp(-r / d['h_r']),
                       math.exp(-rh / d['h_r']) * np.exp(-((r - rh) / (d['hole_w'] * R0)) ** 2))
        u = np.clip((r - d['R_in']) / (d['R_out'] - d['R_in']), 0.0, 1.0)
        hd = d['h_in'] + (d['h_out'] - d['h_in']) * u            # толщина растёт с радиусом (Zhang et al. 2026)
        ha = d['arm_h0']
        vert = np.exp(-np.abs(zd) / hd)
        if arm is None:
            arm = self.arms(x, y)
        rho = rad * (vert + d['arm_amp'] * arm * np.exp(-(zd / ha) ** 2))
        if d['bubble_r'] > 0:
            s2 = (x - R0) ** 2 + y * y + (z - Z_SUN) ** 2
            rho = rho * (1.0 - np.exp(-(s2 / d['bubble_r'] ** 2) ** 2))
        return rho


    def clump_factor(self, r):
        """τ_эфф / τ для пропускания света (облачность, см. PARAMS['clump'])."""
        c = self.P['clump']
        f = c['f_min'] + (c['f_max'] - c['f_min']) / (1.0 + np.exp((r - c['R_half']) / c['width']))
        tc = c['av_cloud'] / 1.0857
        return (1.0 - f) + f * (-math.expm1(-tc) / tc)


# --- лучи -------------------------------------------------------------------------------------------------
def ray_steps(s_max, ds0=0.002, growth=0.012):
    """Края шагов по лучу: ds = ds0 + growth·s (2 пк у Солнца, 50 пк на 4 кпк, ~0,3 кпк на 25 кпк)."""
    n = int(math.ceil(math.log(1 + growth * s_max / ds0) / math.log(1 + growth)))
    s = (ds0 / growth) * ((1 + growth) ** np.arange(n + 1) - 1)
    s[-1] = s_max                      # s[n−1] < s_max ≤ s[n]: последний шаг укорочен до конца луча
    return s


def to_galactocentric(l_deg, b_deg, s):
    lr, br = np.radians(l_deg), np.radians(b_deg)
    cb = np.cos(br)
    x = R0 - s * cb * np.cos(lr)
    y = s * cb * np.sin(lr)
    z = Z_SUN + s * np.sin(br)
    return x, y, z


def calibrate_dust(gal, s_len=1.0, n_l=720):
    """kappa такое, что средняя A_V на первый кпк в плоскости (b = 0, все l) равна av_per_kpc."""
    l = (np.arange(n_l) + 0.5) * 360.0 / n_l
    s = np.linspace(0, s_len, 1001)
    sm = 0.5 * (s[1:] + s[:-1])
    L, S = np.meshgrid(l, sm, indexing='ij')
    x, y, z = to_galactocentric(L, 0.0, S)
    col = (gal.dust(x, y, z) * np.diff(s)).sum(axis=1)
    gal.kappa = gal.P['dust']['av_per_kpc'] * s_len / (1.0857 * col.mean())
    return gal.kappa


def av_to(gal, l_deg, b_deg, s_len, n=4001):
    s = np.linspace(0, s_len, n)
    sm = 0.5 * (s[1:] + s[:-1])
    x, y, z = to_galactocentric(l_deg, b_deg, sm)
    return 1.0857 * gal.kappa * float((gal.dust(x, y, z) * np.diff(s)).sum())


# --- цвет ---------------------------------------------------------------------------------------------------
def ccm89(lam_um, rv=3.1):
    """A_λ/A_V, Cardelli, Clayton & Mathis 1989, ур. 3a–3b (оптика, 1,1 ≤ x ≤ 3,3 мкм⁻¹)."""
    y = 1.0 / lam_um - 1.82
    a = (1 + 0.17699 * y - 0.50447 * y ** 2 - 0.02427 * y ** 3 + 0.72085 * y ** 4
         + 0.01979 * y ** 5 - 0.77530 * y ** 6 + 0.32999 * y ** 7)
    b = (1.41338 * y + 2.28305 * y ** 2 + 1.07233 * y ** 3 - 5.38434 * y ** 4
         - 0.62251 * y ** 5 + 5.30260 * y ** 6 - 2.09002 * y ** 7)
    return a + b / rv


def planck(lam_um, T):
    c2 = 14387.77                      # мкм·K
    return 1.0 / (lam_um ** 5 * (math.exp(c2 / (lam_um * T)) - 1.0))


def t_from_bv(bv):
    """Температура по B−V, Ballesteros 2012: T = 4600 K·(1/(0,92·(B−V) + 1,7) + 1/(0,92·(B−V) + 0,62))."""
    return 4600.0 * (1.0 / (0.92 * bv + 1.7) + 1.0 / (0.92 * bv + 0.62))


def population_color(T, P=PARAMS):
    """RGB чёрного тела T относительно белой точки, зелёный канал = 1."""
    lam = P['lambda_um']
    c = [planck(l_, T) / planck(l_, P['T_white']) for l_ in lam]
    return np.array(c) / c[1]


def channel_tau(P=PARAMS):
    """τ канала / τ_V для (R, G, B)."""
    return np.array([ccm89(l_, P['Rv']) for l_ in P['lambda_um']])
