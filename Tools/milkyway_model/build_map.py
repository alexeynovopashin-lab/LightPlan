#!/usr/bin/env python3
"""Карта Млечного Пути из модели Галактики: свечение (3 канала, линейное) и оптическая толщина пыли по небу.

Для каждой ячейки 0,25° × 0,25° в галактических координатах луч от Солнца (до 25 кпк, шаг 2 пк у Солнца,
50 пк на 4 кпк, дальше растёт) складывает свет звёзд с поглощением пыли на пути до них:
    I_c = Σ j_c(s) · e^(−τ_c(s)) · Δs,   τ_c = (A_c/A_V) · τ_V   (Cardelli et al. 1989),
где на шаге свет и пыль постоянны: множитель (1 − e^(−Δτ))/Δτ точен и для толстых шагов. Свет проходит с
поправкой на облачность пыли (model.PARAMS['clump']); карта τ — средняя толщина пыли по всему лучу.

    python3 build_map.py [--jobs N] [--width 1440] [--out DIR] [--previews DIR] [--no-previews] [--set k=v]

Пишет out/milkyway_glow_1440x720.png, out/milkyway_tau_1440x720.png, out/spec.json и картинки previews/.
Сети не нужно; на 4 ядрах около 2 минут.
"""
import argparse
import json
import math
import multiprocessing as mp
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import model as M  # noqa: E402
import pngio  # noqa: E402
import sky  # noqa: E402

S_MAX = 25.0          # кпк, длина луча
Z_MAX = 8.0           # кпк: выше по |z| свет и пыль меньше 1e-5 от плоскости — луч дальше не идёт

_G = None


def apply_overrides(overrides):
    """«dust.h_in=0.08» → PARAMS['dust']['h_in'] = 0.08 (для опытов; итоговые значения живут в model.py)."""
    for key, val in (overrides or {}).items():
        d = M.PARAMS
        parts = key.split('.')
        for p in parts[:-1]:
            d = d[p]
        if parts[-1] not in d:
            raise KeyError(key)
        d[parts[-1]] = val


def _init(kappa, overrides):
    global _G
    apply_overrides(overrides)
    _G = M.Galaxy()
    _G.kappa = kappa


def render_row(args):
    b_deg, width = args
    g = _G
    P = g.P
    sb = abs(math.sin(math.radians(b_deg)))
    s_max = min(S_MAX, Z_MAX / sb) if sb > 0 else S_MAX
    s = M.ray_steps(s_max)
    sm = 0.5 * (s[1:] + s[:-1])
    ds = np.diff(s)
    l, _ = sky.grid(1, width)
    x, y, z = M.to_galactocentric(l[:, None], b_deg, sm[None, :])
    arm = g.arms(x, y)
    dtau_mean = g.kappa * g.dust(x, y, z, arm) * ds
    dtau = dtau_mean * g.clump_factor(np.hypot(x, y))       # для света — с поправкой на облачность
    tau0 = np.cumsum(dtau, axis=1) - dtau
    # звёзды ярче V_cut (с поглощением до них) в свечение не входят — их рисует приложение из каталога
    m_lim = P['V_cut'] - 5.0 * np.log10(sm * 100.0)[None, :] - 1.0857 * (tau0 + 0.5 * dtau)
    old, young = g.stars(x, y, z, arm, m_lim)
    c_old = M.population_color(M.t_from_bv(P['BV_old']), P)
    c_young = M.population_color(M.t_from_bv(P['BV_young']), P)
    ratio = M.channel_tau(P)
    glow = np.empty((width, 3))
    for c in range(3):
        dt = ratio[c] * dtau
        through = np.exp(-ratio[c] * tau0) * np.where(dt > 1e-6, -np.expm1(-dt) / np.maximum(dt, 1e-300), 1.0 - 0.5 * dt)
        glow[:, c] = ((c_old[c] * old + c_young[c] * young) * ds * through).sum(axis=1)
    return glow, dtau_mean.sum(axis=1)


def build(width=1440, jobs=None, quiet=False, overrides=None):
    height = width // 2
    apply_overrides(overrides)
    gal = M.Galaxy()
    kappa = M.calibrate_dust(gal)
    jobs = jobs or min(8, os.cpu_count() or 1)
    t0 = time.time()
    _, b = sky.grid(height, 1)
    rows = [(float(x), width) for x in b]
    if jobs > 1:
        with mp.get_context('spawn').Pool(jobs, initializer=_init, initargs=(kappa, overrides)) as pool:
            res = pool.map(render_row, rows, chunksize=4)
    else:
        _init(kappa, overrides)
        res = [render_row(r) for r in rows]
    glow = np.stack([r[0] for r in res])
    tau = np.stack([r[1] for r in res])
    if not quiet:
        print(f'  лучи: {height}×{width}, {time.time() - t0:.0f} с на {jobs} проц.; kappa = {kappa:.4f} τ_V/кпк')
    return glow, tau, gal


def write_outputs(glow, tau, gal, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    h, w = tau.shape
    peak = glow.max()
    g16 = np.round(np.clip(glow / peak, 0, 1) * 65535).astype(np.uint16)
    t16 = np.round(np.clip(tau * 100.0, 0, 65535)).astype(np.uint16)
    gname = f'milkyway_glow_{w}x{h}.png'
    tname = f'milkyway_tau_{w}x{h}.png'
    pngio.write(os.path.join(out_dir, gname), g16)
    pngio.write(os.path.join(out_dir, tname), t16)
    glow_n = g16.astype(np.float64) / 65535
    k = sky.tone_k(glow_n)
    k1 = sky.tone_k(glow_n, 1.0)
    P = gal.P
    lam = P['lambda_um']
    spec = {
        'what': 'Млечный Путь из модели Галактики, вид из точки Солнца (Tools/milkyway_model/README.md)',
        'projection': 'равнопромежуточная (plate carrée), галактические координаты l, b',
        'size': [w, h],
        'step_deg': 360.0 / w,
        'u': {'axis': 'долгота l', 'formula': 'u = fract(0.5 - l/360)', 'l0_at_u': 0.5,
              'direction': 'l растёт влево (u убывает), как у карт NASA SVS; u = 0 и u = 1 — l = 180°',
              'pixel_center': 'столбец i = 0…W-1: l = 180 - (i + 0.5)·360/W (mod 360)'},
        'v': {'axis': 'широта b', 'formula': 'v = 0.5 - b/180', 'top': 'v = 0 — b = +90° (северный полюс Галактики)',
              'pixel_center': 'строка j = 0…H-1 сверху вниз: b = 90 - (j + 0.5)·180/H'},
        'sampling': 'значение — в центре ячейки (один луч на ячейку); текстуру читать билинейно, по u — с повтором',
        'glow': {'file': gname, 'format': 'PNG, 16 бит, RGB', 'value': 'линейная яркость, max = 1.0 (65535)',
                 'channels_um': {'R': lam[0], 'G': lam[1], 'B': lam[2]},
                 'white_point': f"чёрное тело {P['T_white']:.0f} K = (1, 1, 1)",
                 'stars': f"без звёзд ярче V = {P['V_cut']} (их рисует приложение из каталога)"},
        'tau': {'file': tname, 'format': 'PNG, 16 бит, серый',
                'value': 'средняя оптическая толщина пыли τ_V × 100 (сотые доли), весь луч до 25 кпк',
                'A_V_mag': '1.0857 · τ_V', 'max_tau_V': round(float(tau.max()), 2),
                'channels_from_tau_V': {c: round(float(M.ccm89(x, P['Rv'])), 4) for c, x in zip('RGB', lam)},
                'transmission_note': 'свет в модели проходит с τ_эфф = τ·[(1-f)+f·(1-e^-τc)/τc] (облачность, README)'},
        'tone': {'rule': 'Y = 0.2126 R + 0.7152 G + 0.0722 B;  out_c = I_c · (1 - exp(-k·Y^γ)) / Y;  обрезать в [0, 1]',
                 'gamma': sky.TONE_GAMMA, 'k': round(k, 4), 'core_out': sky.TONE_CORE,
                 'core_Y': round(sky.core_y(glow_n), 5),
                 'plain_rule_gamma_1': {'k': round(k1, 4), 'note': 'формула задачи 1 - exp(-k·Y); контраст у ядра > 6:1'}},
        'model': {'R0_kpc': M.R0, 'z_sun_kpc': M.Z_SUN, 'ray_kpc': S_MAX, 'step_kpc': 'ds = 0.002 + 0.012·s',
                  'A_V_per_kpc_near_sun': P['dust']['av_per_kpc'], 'random_numbers': 'нет: повтор прогона даёт те же значения'},
    }
    with open(os.path.join(out_dir, 'spec.json'), 'w') as f:
        json.dump(spec, f, ensure_ascii=False, indent=1)
        f.write('\n')
    return glow_n, k


# --- картинки для человека ---------------------------------------------------------------------------------
def save8(path, rgb):
    from PIL import Image
    Image.fromarray(np.round(np.clip(rgb, 0, 1) * 255).astype(np.uint8)).save(path, optimize=True)


def view(img, l0, fov_h=90.0, fov_v=60.0, width=1200):
    """Прямолинейная (гномоническая) проекция 90° × 60°: камера на (l0, b = 0), «верх» — северный полюс Галактики."""
    th, tv = math.tan(math.radians(fov_h / 2)), math.tan(math.radians(fov_v / 2))
    height = int(round(width * tv / th))
    px = (np.arange(width) + 0.5) / width * 2 - 1
    py = 1 - (np.arange(height) + 0.5) / height * 2
    X, Y = np.meshgrid(px * th, py * tv)
    lr = math.radians(l0)
    fwd = np.array([math.cos(lr), math.sin(lr), 0.0])
    right = np.array([math.sin(lr), -math.cos(lr), 0.0])        # вправо — к меньшим l, как на небе
    up = np.array([0.0, 0.0, 1.0])
    d = fwd[None, None, :] + X[..., None] * right + Y[..., None] * up
    d /= np.linalg.norm(d, axis=2, keepdims=True)
    l = np.degrees(np.arctan2(d[..., 1], d[..., 0])) % 360
    b = np.degrees(np.arcsin(d[..., 2]))
    return sky.sample(img, l, b)


TOP_YOUNG_BOOST = 8.0   # вид сверху — схема геометрии: свет молодых звёзд ×8, иначе рукава едва видны (3 % света в V)


def top_view(gal, size=800, half=16.0):
    """Галактика с северного полюса: центр в середине, Солнце снизу, l = 90° справа (вращение по часовой).

    Свет звёзд всех величин по столбу z (молодые ×TOP_YOUNG_BOOST), ослабленный половиной пыли столба."""
    P = gal.P
    ax = (np.arange(size) + 0.5) / size * 2 * half - half          # экран: X вправо, Y вверх
    zs = np.linspace(-1.5, 1.5, 121)
    dz = zs[1] - zs[0]
    c_old = M.population_color(M.t_from_bv(P['BV_old']), P)
    c_young = M.population_color(M.t_from_bv(P['BV_young']), P)
    ratio = M.channel_tau(P)
    img = np.zeros((size, size, 3))
    Z = np.repeat(zs[None, :], size, axis=0)
    for i in range(size):
        x = np.full((size, len(zs)), -ax[size - 1 - i])              # x галактики = −Y экрана
        y = np.repeat(ax[:, None], len(zs), axis=1)                  # y галактики = X экрана
        arm = gal.arms(x, y)
        old, young = gal.stars(x, y, Z, arm)
        tau_v = gal.kappa * (gal.dust(x, y, Z, arm) * dz).sum(axis=1)
        for c in range(3):
            img[i, :, c] = ((c_old[c] * old + TOP_YOUNG_BOOST * c_young[c] * young) * dz).sum(axis=1) \
                * np.exp(-0.5 * ratio[c] * tau_v)
    return img


def log_tone(img, decades=2.5):
    """Вид сверху: яркость в логарифме на decades порядков от 99,8-го перцентиля, оттенок сохраняется."""
    Y = img @ sky.LUMA
    hi = np.percentile(Y, 99.8)
    out = np.clip((np.log10(np.maximum(Y, 1e-30)) - math.log10(hi)) / decades + 1, 0, 1)
    return np.clip(img * (out / np.maximum(Y, 1e-30))[..., None], 0, 1)


def previews(glow_n, k, gal, pdir):
    os.makedirs(pdir, exist_ok=True)
    save8(os.path.join(pdir, 'sky_1440x720.png'), sky.tone(glow_n, k))
    for name, l0 in (('view_core_l0.png', 0.0), ('view_anticenter_l180.png', 180.0), ('view_cygnus_l80.png', 80.0)):
        save8(os.path.join(pdir, name), sky.tone(view(glow_n, l0), k))
    size, half = 800, 16.0
    img = log_tone(top_view(gal, size, half))
    yy, xx = np.mgrid[0:size, 0:size]                                # Солнце — тонкое кольцо, подписей нет
    row = (half + M.R0) / (2 * half) * size - 0.5
    img[np.abs(np.hypot(yy - row, xx - (size - 1) / 2) - 5) < 0.9] = [1.0, 0.85, 0.3]
    save8(os.path.join(pdir, 'top_view.png'), img)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--jobs', type=int, default=None)
    ap.add_argument('--width', type=int, default=1440)
    ap.add_argument('--out', default=os.path.join(HERE, 'out'))
    ap.add_argument('--previews', default=os.path.join(HERE, 'previews'))
    ap.add_argument('--no-previews', action='store_true')
    ap.add_argument('--set', action='append', default=[], metavar='KEY=VALUE',
                    help='опыт: переопределить параметр модели, напр. clump.f_min=0.4 (итог — правкой model.py)')
    a = ap.parse_args()
    overrides = {k: json.loads(v) for k, v in (s.split('=', 1) for s in a.set)}
    t0 = time.time()
    glow, tau, gal = build(a.width, a.jobs, overrides=overrides)
    glow_n, k = write_outputs(glow, tau, gal, a.out)
    names = [f for f in sorted(os.listdir(a.out)) if f.endswith(f'{a.width}x{a.width // 2}.png') or f == 'spec.json']
    sizes = {f: os.path.getsize(os.path.join(a.out, f)) for f in names}
    print('  файлы: ' + ', '.join(f'{f} {v / 1e6:.2f} МБ' for f, v in sizes.items()) + f'; всего {sum(sizes.values()) / 1e6:.2f} МБ')
    print(f'  τ_V max {tau.max():.1f}; тонирование γ = {sky.TONE_GAMMA}, k = {k:.3f}')
    if not a.no_previews:
        previews(glow_n, k, gal, a.previews)
        print('  картинки: ' + ', '.join(sorted(os.listdir(a.previews))))
    print(f'  всего {time.time() - t0:.0f} с')


if __name__ == '__main__':
    main()
