#!/usr/bin/env python3
"""Шаг 29.8в.14: Млечный Путь в AR по кадрам симулятора — числами, не на глаз.

Приложение рисует только слой Млечного Пути (`-LPSunARLayers milkyWay`) и только гладкую часть картины
(`-LPSunARMWParts smooth`: без зерна, пыли и подписи ядра), кадр снимается `simctl io screenshot`. Из отчёта
кадра (`ar.milkyWay`) берутся: лучи окна и оси галактики, которыми рисует шейдер, видимость, фокус и середина полосы
`MilkyWay.band`, спроецированная `SkyProjection` — отдельно от шейдера. Проверки:

  1. середина полосы — центр тяжести яркости поперёк полосы (по нормали к спроецированной линии) — лежит на
     линии `MilkyWay.band` в пределах 0,5° на каждой станции;
  2. профиль яркости поперёк полосы совпадает с формулой `MilkyWayLook.smooth` (своя копия формулы ниже — судья
     из описания шага, а не код приложения): один общий множитель k на все кадры, остаток ≤ 4 % от вершины;
  3. ядро — центр тяжести самой яркой части (≥ 97 % максимума) — в пределах 0,5° от `MilkyWay.corePosition`;
  4. планирование (29.8в.17б, слово Алексея 20.10: положение показывается всегда): гладкая полоса рисуется при ЛЮБОЙ
     видимости — днём при Солнце +20°, в сумерках, в городе и при засветке 40 (выше 27: ступень «дальше пусто») —
     яркостью, которая от видимости не зависит (общий множитель k на все кадры ≈ 1, как ночью); яркость в колонке
     поперёк полосы выше фона не меньше чем на 12/255.

Пять моментов: разные широты (−34°…+64°), часы, курсы и крен кадра. Плюс кадры для глаза (`--frames`): ночь без
засветки, ночь с городом (`-LPSunARGlow 12`), сумерки, день — все слои, без камеры.

    python3 Tools/ar_milkyway.py --app <LightPlan.app> [--out DIR] [--only a,b] [--frames]
    python3 Tools/ar_milkyway.py --app <LightPlan.app> --contrast [--goal 1.5]   # контраст на белом, голубом, асфальте, ночи
Любое нарушение — код 1.
"""
import json, math, os, re, subprocess, sys, time
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, 'Fixtures', 'shots')
BUNDLE = 'Novopashin.LightPlan'
ARGS = sys.argv[1:]


def arg(name, default=None):
    return ARGS[ARGS.index(name) + 1] if name in ARGS else default


OUT = arg('--out', '/tmp/cc-ar-milkyway')
OFFSET_LIMIT = 0.5          # градусы: середина полосы и ядро
PROFILE_LIMIT = 0.04        # доля вершины профиля

# --- Наведение (только чтобы ядро или кусок полосы попали в кадр; на вердикт не влияет) ---------------------------

def gal_to_eq(l, b):
    rad = math.radians
    pra, pdec, th = rad(192.85948), rad(27.12825), rad(122.93192)
    L, B = rad(l), rad(b)
    dT = th - L
    dec = math.asin(math.sin(pdec) * math.sin(B) + math.cos(pdec) * math.cos(B) * math.cos(dT))
    ra = pra + math.atan2(math.cos(B) * math.sin(dT), math.cos(pdec) * math.sin(B) - math.sin(pdec) * math.cos(B) * math.cos(dT))
    return ra, dec


def horizontal(ra, dec, iso, lat, lon):
    from datetime import datetime
    t = datetime.fromisoformat(iso.replace('Z', '+00:00')).timestamp()
    d = t / 86400 + 2440587.5 - 2451545
    phi = math.radians(lat)
    # Звёздное время IAU, как у слоёв AR (29.8в.21); прецессии нет: наведение грубое (до 0,4°), вердикт её не использует.
    h = math.radians(280.46061837 + 360.98564736629 * d) + math.radians(lon) - ra
    alt = math.asin(math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec) * math.cos(h))
    az = math.atan2(math.sin(h), math.cos(h) * math.sin(phi) - math.tan(dec) * math.cos(phi))
    return (math.degrees(az) + 180) % 360, math.degrees(alt)


# --- Формула вида (описание шага; копия, чтобы судья не был подсудимым) -----------------------------------------

def from_core(l):
    return abs((l + 180) % 360 - 180)


def half_width(l):
    k = math.cos(math.radians(from_core(l)) / 2)
    return 3 + 8.5 * k * k


def smooth(l, b):
    s = half_width(l) / math.sqrt(2 * math.log(2))
    dl = from_core(l)
    band = (0.35 + 0.65 * math.cos(math.radians(dl) / 2)) * math.exp(-b * b / (2 * s * s))
    bulge = 0.75 * math.exp(-dl * dl / (2 * 7 * 7) - b * b / (2 * 5 * 5))
    return (band + bulge) / 1.75


def green(l):
    warm = math.exp(-from_core(l) ** 2 / (2 * 35 * 35))
    return 0.80 + (0.84 - 0.80) * warm


def fade(alt):
    t = min(1.0, max(0.0, alt / 8))
    return t * t * (3 - 2 * t)


# --- Сценарии ----------------------------------------------------------------------------------------------------

SOCHI = (43.585, 39.723, 'Europe/Moscow')
MOMENTS = [
    # имя, место, момент (UTC), куда смотреть (галактическая l, b), крен
    ('sochi_core', SOCHI, '2026-08-15T19:30:00Z', (0, 0), 0),
    ('tomsk_cygnus', (56.4977, 84.9744, 'Asia/Tomsk'), '2026-09-10T15:00:00Z', (75, 0), 10),
    ('sydney_core', (-33.87, 151.21, 'Australia/Sydney'), '2026-06-15T12:00:00Z', (5, 0), -15),
    ('quito_scutum', (-0.18, -78.47, 'America/Guayaquil'), '2026-07-14T02:00:00Z', (28, 0), 0),
    ('reykjavik_perseus', (64.15, -21.94, 'Atlantic/Reykjavik'), '2026-11-10T22:00:00Z', (140, 0), 20),
]
# Видимость: те же кадры, другое небо. `hidden` — чего ждём; `glow` — подставная засветка.
EXTRA = [
    # Планирование: ни засветка, ни сумерки, ни день полосу не гасят. Засветка 40 — «дальше пусто» атласа (> 27).
    ('sochi_city', SOCHI, '2026-08-15T19:30:00Z', (0, 0), 0, {'glow': 12}),
    ('sochi_glow40', SOCHI, '2026-08-15T19:30:00Z', (0, 0), 0, {'glow': 40}),
    ('sochi_twilight', SOCHI, '2026-08-15T17:55:00Z', (0, 0), 0, {}),
    # Солнце +20° (астропи: 20,1°): целиком днём, aim 'best' — точка полосы, что выше всех в этот момент.
    ('sochi_day_sun20', SOCHI, '2026-08-15T14:27:00Z', 'best', 0, {'day': True}),
    ('sochi_day_sun45', SOCHI, '2026-08-15T12:00:00Z', 'best', 0, {'day': True}),
]


def sh(*a, **kw):
    return subprocess.run(a, check=True, capture_output=True, text=True, **kw).stdout


def udid():
    out = subprocess.run(['node', os.path.join(ROOT, 'Tools', 'sim.js')], capture_output=True, text=True, cwd=ROOT).stdout
    m = re.search(r'([0-9A-F]{8}-[0-9A-F-]{27})', out)
    if not m:
        sys.exit('нет симулятора ветки: make sims')
    return m.group(1)


def best_aim(place, moment):
    """Точка середины полосы (b = 0), самая высокая над горизонтом в этот момент: куда навести кадр днём."""
    lat, lon, _ = place
    best = max(range(0, 360, 5), key=lambda l: horizontal(*gal_to_eq(l, 0), moment, lat, lon)[1])
    return (best, 0)


def launch(sim, name, place, moment, aim, roll, layers, parts, extra, mw=True):
    lat, lon, zone = place
    if aim == 'best':
        aim = best_aim(place, moment)
    ra, dec = gal_to_eq(*aim)
    az, alt = horizontal(ra, dec, moment, lat, lon)
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    report = os.path.join(d, 'native.json' if mw else 'base.json')
    if os.path.exists(report):
        os.remove(report)
    subprocess.run(['xcrun', 'simctl', 'terminate', sim, BUNDLE], capture_output=True)
    lang = extra.get('lang', 'ru')
    locale = {'ru': 'ru_RU', 'en': 'en_US', 'es': 'es_ES', 'ja': 'ja_JP', 'zh': 'zh_CN'}[lang]
    argv = ['xcrun', 'simctl', 'launch', sim, BUNDLE, '-AppleLanguages', f'({lang})', '-AppleLocale', locale,
            '-LPShotNow', moment, '-LPShotZone', zone, '-LPShotSeed', FX + '/seed.json',
            '-LPShotForecast', FX + '/forecast_barnaul.json', '-LPShotAir', FX + '/air_barnaul.json',
            '-LPShotName', FX + '/place_barnaul.json', '-LPShotScreen', 'map', '-LPShotReportDelay', '5',
            '-lightplan.native.sunar.calibrationSeen', 'YES', '-lightplan.native.sunar.moon', 'NO',
            '-lightplan.native.sunar.milkyWay', 'YES' if mw else 'NO',
            '-LPSunAR', '1', '-LPSunARMoment', moment, '-LPSunARPose', f'{az:.3f},{max(alt, 12) + 8:.3f},{roll}',
            '-LPSunARPhone', f' {lat},{lon},{zone}', '-LPSunARGlow', str(extra.get('glow', 0)),
            '-LPShotReport', report]
    if layers:
        argv += ['-LPSunARLayers', layers]
    if parts is not None:
        argv += ['-LPSunARMWParts', parts]
    if extra.get('layersOpen'):
        argv += ['-LPSunARLayersOpen', '1']
    if extra.get('backdrop'):
        argv += ['-LPSunARBackdrop', extra['backdrop']]
    if extra.get('args'):
        argv += extra['args']
    sh(*argv)
    for _ in range(240):
        if os.path.exists(report):
            break
        time.sleep(0.25)
    if not os.path.exists(report):
        raise SystemExit('нет отчёта кадра: ' + name)
    time.sleep(1.5)
    png = os.path.join(d, 'native.png' if mw else 'base.png')
    sh('xcrun', 'simctl', 'io', sim, 'screenshot', '--type=png', png)
    nodes = json.load(open(report)).get('nodes', {})
    return nodes, png, (az, alt)


def parse(nodes):
    t = nodes.get('ar.milkyWay', {}).get('text', '')
    out = {'raw': t}
    for k in ('vis', 'focal', 'coreAlt', 'coreAz'):
        m = re.search(k + r'=(-?[0-9.]+)', t)
        out[k] = float(m.group(1)) if m else None
    m = re.search(r'hidden=(\w+)', t)
    out['hidden'] = m.group(1) if m else None
    m = re.search(r'core=(-?[0-9.]+),(-?[0-9.]+)', t)
    out['core'] = (float(m.group(1)), float(m.group(2))) if m else None
    m = re.search(r' m=([^ ]+)', t)
    out['m'] = [float(x) for x in m.group(1).split(',')] if m else None
    m = re.search(r' line=([^ ]*)', t)
    out['line'] = [tuple(float(v) for v in p.split(',')) for p in m.group(1).split(';') if p] if m else []
    return out


def ray(m, x, y):
    e = (m[0] * x + m[1] * y + m[2], m[3] * x + m[4] * y + m[5], m[6] * x + m[7] * y + m[8])
    n = math.sqrt(sum(c * c for c in e))
    return tuple(c / n for c in e)


def galactic(m, e):
    gx = sum(e[i] * m[9 + i] for i in range(3))
    gy = sum(e[i] * m[12 + i] for i in range(3))
    gz = sum(e[i] * m[15 + i] for i in range(3))
    return math.degrees(math.atan2(gy, gx)) % 360, math.degrees(math.atan2(gz, math.hypot(gx, gy)))


def angle(m, a, b):
    ea, eb = ray(m, *a), ray(m, *b)
    return math.degrees(math.acos(max(-1.0, min(1.0, sum(x * y for x, y in zip(ea, eb))))))


class Frame:
    """Свет полосы: кадр с ней минус кадр без неё (небо без камеры то же; свет складывается — `.plusLighter`)."""
    def __init__(self, png, width_pt, base=None):
        img = Image.open(png).convert('RGB')
        if base:
            b = Image.open(base).convert('RGB')
            from PIL import ImageChops
            img = ImageChops.subtract(img, b)
        self.img = img
        self.px = self.img.load()
        self.s = self.img.width / width_pt

    def g(self, x, y):
        """Зелёный канал в точке окна (pt), билинейно."""
        X, Y = x * self.s - 0.5, y * self.s - 0.5
        i, j = int(math.floor(X)), int(math.floor(Y))
        if i < 0 or j < 0 or i + 1 >= self.img.width or j + 1 >= self.img.height:
            return None
        fx, fy = X - i, Y - j
        p = self.px
        a = p[i, j][1] * (1 - fx) + p[i + 1, j][1] * fx
        b = p[i, j + 1][1] * (1 - fx) + p[i + 1, j + 1][1] * fx
        return a * (1 - fy) + b * fy


def zone(nodes):
    """Окно, где кроме полосы ничего не нарисовано: ниже кнопок и плашек, выше нижней панели."""
    scr = screen(nodes)
    # Кнопки и плашки верха (заметки внизу экрана — над панелью — не в счёт: окно кончается у панели).
    top = max(nodes[k]['y'] + nodes[k]['h'] for k in ('ar.layers', 'ar.place', 'ar.note', 'ar.cameraNote')
              if k in nodes and nodes[k]['y'] < scr[1] / 2)
    panel = nodes.get('ar.panel', {}).get('y', scr[1] - 250)
    return 12, top + 8, scr[0] - 12, panel - 12


def screen(nodes):
    """Размер окна в точках: слой Млечного Пути лежит на весь экран (камеры в замере нет — нет и узла фона)."""
    n = nodes.get('ar.milkyWay') or nodes['ar.background']
    return n['w'], n['h']


def cover(nodes):
    """Стрелки, подписи и кнопки поверх полосы закрывают её: точки под их рамками (с полем 6 pt) не меряются."""
    boxes = [(n['x'] - 6, n['y'] - 6, n['x'] + n['w'] + 6, n['y'] + n['h'] + 6) for k, n in nodes.items()
             if k.startswith('ar.') and k not in ('ar.milkyWay', 'ar.background', 'ar.panel')]
    return lambda x, y: any(a <= x <= c and b <= y <= d for a, b, c, d in boxes)


def measure(name, nodes, png, pic, base):
    bad, rows = [], []
    m, f = pic['m'], pic['focal']
    x0, y0, x1, y1 = zone(nodes)
    fr = Frame(png, screen(nodes)[0], base)
    vis = pic['vis']
    # Стрелки, подписи и кнопки поверх полосы закрывают её: точки под их рамками (с полем 6 pt) не меряются.
    covered = cover(nodes)
    inside = lambda x, y: x0 <= x <= x1 and y0 <= y <= y1
    # Станции вдоль спроецированной середины полосы, шаг 18 pt.
    line = pic['line']
    stations = []
    for (ax, ay), (bx, by) in zip(line, line[1:]):
        seg = math.hypot(bx - ax, by - ay)
        if seg < 1e-6 or seg > 2000:
            continue
        n = max(1, int(seg / 18))
        for k in range(n):
            t = k / n
            x, y = ax + (bx - ax) * t, ay + (by - ay) * t
            if inside(x, y):
                stations.append((x, y, -(by - ay) / seg, (bx - ax) / seg))
    fits = []
    for (x, y, nx, ny) in stations:
        l, b = galactic(m, ray(m, x, y))
        sig_pt = half_width(l) / math.sqrt(2 * math.log(2)) * math.pi / 180 * f
        # ±1,6σ: от вершины до трети яркости — у ядра это уже 400 pt, больше в окно между кнопками и панелью не влезает.
        T = 1.6 * sig_pt
        samples, hidden = [], []
        step = 1.0 / fr.s
        t = -T
        ok = True
        while t <= T:
            px, py = x + nx * t, y + ny * t
            if not inside(px, py):
                ok = False
                break
            e = ray(m, px, py)
            gl, gb = galactic(m, e)
            alt = math.degrees(math.asin(max(-1, min(1, e[2]))))
            if alt < 8.5:            # дымка у горизонта гасит одну сторону — центр тяжести поедет, станция не годится
                ok = False
                break
            # Планирование: яркость от видимости не зависит (`vis` — справка о глазе), дымка гасит только текстуру.
            exp_ = 255 * green(gl) * min(1.0, smooth(gl, gb) * 0.55)
            if covered(px, py):
                hidden.append(exp_)
            else:
                samples.append((t, fr.g(px, py), exp_))
            t += step
        if not ok or len(samples) < 20:
            continue
        # Закрытое не должно попасть в верхнюю часть профиля — иначе центр тяжести сдвинет рамка, а не полоса.
        if hidden and max(hidden) >= 0.6 * max(e for _, _, e in samples + [(0, 0, 0)]):
            continue
        vmax = max(s[1] for s in samples)
        if vmax < 12:
            continue
        top = [(t, v) for t, v, _ in samples if v >= 0.6 * vmax]
        c = sum(t * v for t, v in top) / sum(v for _, v in top)
        off = angle(m, (x, y), (x + nx * c, y + ny * c)) * (1 if c >= 0 else -1)
        rows.append({'x': round(x, 1), 'y': round(y, 1), 'l': round(l, 1), 'offsetDeg': round(off, 3)})
        fits.append(samples)
    if not rows:
        bad.append('ни одной станции поперёк полосы в окне')
        return bad, {}
    worst = max(rows, key=lambda r: abs(r['offsetDeg']))
    if abs(worst['offsetDeg']) > OFFSET_LIMIT:
        bad.append(f"середина полосы мимо линии MilkyWay.band на {worst['offsetDeg']:.2f}° (l {worst['l']}, x {worst['x']} y {worst['y']})")
    # Профиль: общий множитель на кадр, остаток в долях вершины.
    num = sum(v * e for s in fits for _, v, e in s)
    den = sum(e * e for s in fits for _, _, e in s)
    k = num / den if den else 0
    resid = 0.0
    for s in fits:
        peak = max(e for _, _, e in s) * k
        resid = max(resid, max(abs(v - k * e) for _, v, e in s) / peak if peak > 0 else 0)
    if resid > PROFILE_LIMIT:
        bad.append(f'профиль поперёк полосы расходится с формулой: остаток {resid * 100:.1f} % вершины')
    out = {'stations': len(rows), 'maxOffsetDeg': worst['offsetDeg'], 'k': round(k, 4),
           'profileResidual': round(resid, 4),
           # Подъём яркости (зелёный канал, из 255) над фоном в колонке поперёк полосы: самая слабая станция.
           'lift': round(min(max(v for _, v, _ in smp) for smp in fits), 1)}
    # Ядро: центр самой яркой части рядом с проекцией ядра.
    if pic['core'] and inside(*pic['core']) and pic['coreAlt'] > 12:
        cx, cy = pic['core']
        R = 0.12 * f
        pts = []
        yy = cy - R
        while yy <= cy + R:
            xx = cx - R
            while xx <= cx + R:
                if inside(xx, yy) and not covered(xx, yy):
                    v = fr.g(xx, yy)
                    if v is not None:
                        pts.append((xx, yy, v))
                xx += 1 / fr.s
            yy += 1 / fr.s
        vmax = max(v for *_, v in pts)
        top = [(a, b, v) for a, b, v in pts if v >= 0.97 * vmax]
        w = sum(v for *_, v in top)
        mx, my = sum(a * v for a, b, v in top) / w, sum(b * v for a, b, v in top) / w
        d = angle(m, (cx, cy), (mx, my))
        out['coreOffsetDeg'] = round(d, 3)
        if d > OFFSET_LIMIT:
            bad.append(f'ядро картины мимо MilkyWay.corePosition на {d:.2f}°')
    return bad, out


def empty(png, nodes, base):
    fr = Frame(png, screen(nodes)[0], base)
    x0, y0, x1, y1 = zone(nodes)
    covered = cover(nodes)
    mx = 0
    for j in range(int(y0 * fr.s), int(y1 * fr.s), 3):
        for i in range(int(x0 * fr.s), int(x1 * fr.s), 3):
            if not covered(i / fr.s, j / fr.s):
                mx = max(mx, max(fr.px[i, j]))
    return mx


def lum(c):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2])


def ratio(a, b):
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def contrast_station(fr_band, fr_base, m, f, x, y, nx, ny, inside, covered):
    """Наибольший контраст WCAG (L1 + 0,05) / (L2 + 0,05) между кадром с полосой и тем же кадром без неё в колонке
    поперёк полосы (±1,6σ). Яркость точки — по её пикселю, фон — пиксель той же точки в кадре без полосы."""
    l, _ = galactic(m, ray(m, x, y))
    T = 1.6 * half_width(l) / math.sqrt(2 * math.log(2)) * math.pi / 180 * f
    best, n, t = 0.0, 0, -T
    while t <= T:
        px, py = x + nx * t, y + ny * t
        t += 1.0 / fr_band.s
        if not inside(px, py):
            return None       # колонка вылезла за окно: край полосы не виден, станция не меряется
        if covered(px, py):
            continue
        i, j = int(px * fr_band.s), int(py * fr_band.s)
        if i < 0 or j < 0 or i >= fr_band.img.width or j >= fr_band.img.height:
            continue
        best = max(best, ratio(lum(fr_band.px[i, j]), lum(fr_base.px[i, j])))
        n += 1
    return best if n > 20 else None


def contrast_main(sim):
    """Шаг 29.8в.17б: контраст полосы против фона на четырёх подложках (`-LPSunARBackdrop`): белое небо, голубое небо,
    асфальт, ночное небо. Две сцены: ночь на юге (вся картина: гладкая часть, зерно, пыль, контур) и день с
    солнцем +20° (одна планировочная часть). Цель ≥ 1,5 : 1 в станции у ядра и в средней станции вдоль полосы."""
    # 29.8в.19: те же подложки для звёзд Gaia — город (засветка 12 и 27) и Луна 62 % (21.08 22:00 Сочи: возраст
    # ≈ 8,5 суток от новолуния 12.08, Луна над горизонтом рядом с ядром) гасят реалистичную часть до пола.
    scenes = [('night_sydney', ('sydney', (-33.87, 151.21, 'Australia/Sydney'), '2026-06-15T12:00:00Z', (5, 0), -15, {})),
              ('day_sun20', ('sochi', SOCHI, '2026-08-15T14:27:00Z', 'best', 0, {})),
              ('city12', ('sochi', SOCHI, '2026-08-15T19:30:00Z', (0, 0), 0, {'glow': 12})),
              ('city27', ('sochi', SOCHI, '2026-08-15T19:30:00Z', (0, 0), 0, {'glow': 27})),
              ('moon62', ('sochi', SOCHI, '2026-08-21T19:00:00Z', (0, 0), 0, {}))]
    only = arg('--scenes', '').split(',') if arg('--scenes') else None
    rows, fails = [], []
    for backdrop in (arg('--backdrops', 'white,sky,asphalt,night').split(',')):
        for label, (nm, place, moment, aim, roll, sx) in scenes:
            if only and label not in only:
                continue
            extra = dict(sx, backdrop=backdrop)
            if arg('--extra'):
                extra['args'] = arg('--extra').split()
            nodes, png, _ = launch(sim, f'contrast_{backdrop}_{label}', place, moment, aim, roll, 'camera,milkyWay', None, extra)
            _, base, _ = launch(sim, f'contrast_{backdrop}_{label}', place, moment, aim, roll, 'camera,milkyWay', None, extra, mw=False)
            pic = parse(nodes)
            m, f = pic['m'], pic['focal']
            x0, y0, x1, y1 = zone(nodes)
            inside = lambda x, y: x0 <= x <= x1 and y0 <= y <= y1
            covered = cover(nodes)
            fb, fa = Frame(png, screen(nodes)[0]), Frame(base, screen(nodes)[0])
            vals, core_val, detail = [], None, []
            line = pic['line']
            for (ax, ay), (bx, by) in zip(line, line[1:]):
                seg = math.hypot(bx - ax, by - ay)
                if seg < 1e-6 or seg > 2000:
                    continue
                for k in range(max(1, int(seg / 30))):
                    t = k / max(1, int(seg / 30))
                    x, y = ax + (bx - ax) * t, ay + (by - ay) * t
                    if not inside(x, y):
                        continue
                    alt = math.degrees(math.asin(ray(m, x, y)[2]))
                    if alt < 8.5:
                        continue
                    c = contrast_station(fb, fa, m, f, x, y, -(by - ay) / seg, (bx - ax) / seg, inside, covered)
                    if c is None:
                        continue
                    vals.append(c)
                    detail.append((round(x), round(y), round(alt, 1), round(c, 2)))
                    if pic['core'] and math.hypot(x - pic['core'][0], y - pic['core'][1]) < 40:
                        core_val = max(core_val or 0, c)
            if not vals:
                fails.append(f'{backdrop} {label}: нет станций')
                continue
            vals.sort()
            row = {'backdrop': backdrop, 'scene': label, 'stations': len(vals), 'min': round(vals[0], 2),
                   'median': round(vals[len(vals) // 2], 2), 'core': round(core_val, 2) if core_val else None}
            rows.append(row)
            print(json.dumps(row, ensure_ascii=False))
            if '--detail' in ARGS:
                print('   станции (x, y, высота°, контраст):', detail)
            if row['median'] < CONTRAST_GOAL:
                fails.append(f"{backdrop} {label}: медиана {row['median']} < {CONTRAST_GOAL}")
            if core_val is not None and core_val < CONTRAST_GOAL:
                fails.append(f"{backdrop} {label}: у ядра {row['core']} < {CONTRAST_GOAL}")
    json.dump(rows, open(os.path.join(OUT, 'contrast.json'), 'w'), ensure_ascii=False, indent=1)
    if fails:
        print('НАРУШЕНИЯ:\n' + '\n'.join(fails))
        sys.exit(1)


CONTRAST_GOAL = float(arg('--goal', '1.5'))

# Список «Слоёв» под разные места, даты и языки: строки Млечного Пути словами (кадры для глаза и узел `ar.layer.mw`).
LISTS = [
    ('list_tomsk_ru', (56.4977, 84.9744, 'Asia/Tomsk'), '2026-08-30T18:00:00Z', 'ru', 'ядро над горизонтом'),
    ('list_tomsk_en', (56.4977, 84.9744, 'Asia/Tomsk'), '2026-08-30T18:00:00Z', 'en', 'core above the horizon'),
    ('list_sydney_en', (-33.87, 151.21, 'Australia/Sydney'), '2026-06-15T12:00:00Z', 'en', 'core above the horizon'),
    ('list_sydney_ru', (-33.87, 151.21, 'Australia/Sydney'), '2026-06-15T12:00:00Z', 'ru', 'ядро над горизонтом'),
    ('list_lat70_ru', (70.0, 25.0, 'Europe/Oslo'), '2026-06-21T22:00:00Z', 'ru', 'ядро не восходит на этой широте'),
    ('list_lat70_en', (70.0, 25.0, 'Europe/Oslo'), '2026-06-21T22:00:00Z', 'en', 'never rises at this latitude'),
    ('list_south70_ru', (-70.0, -68.0, 'America/Argentina/Ushuaia'), '2026-06-21T03:00:00Z', 'ru', 'ядро не заходит'),
    ('list_south70_es', (-70.0, -68.0, 'America/Argentina/Ushuaia'), '2026-06-21T03:00:00Z', 'es', 'no se pone'),
    ('list_day_en', SOCHI, '2026-08-15T14:27:00Z', 'en', 'not visible by day'),
    ('list_moon_ru', (56.4977, 84.9744, 'Asia/Tomsk'), '2026-10-27T17:00:00Z', 'ru', ''),
]


def lists_main(sim):
    rows, fails = [], []
    for name, place, moment, lang, need in LISTS:
        nodes, png, _ = launch(sim, name, place, moment, (0, 0), 0, None, None, {'layersOpen': True, 'lang': lang})
        t = nodes.get('ar.layer.mw', {}).get('text', '')
        row = {'list': name, 'png': png, 'text': t}
        print(json.dumps(row, ensure_ascii=False))
        rows.append(row)
        if need and need not in t:
            fails.append(f'{name}: нет «{need}» в «{t}»')
    json.dump(rows, open(os.path.join(OUT, 'lists.json'), 'w'), ensure_ascii=False, indent=1)
    if fails:
        print('НАРУШЕНИЯ:\n' + '\n'.join(fails))
        sys.exit(1)


def main():
    sim = udid()
    subprocess.run(['xcrun', 'simctl', 'boot', sim], capture_output=True)
    app = arg('--app')
    if app:
        sh('xcrun', 'simctl', 'install', sim, app)
    sh('xcrun', 'simctl', 'ui', sim, 'appearance', 'dark')
    os.makedirs(OUT, exist_ok=True)
    if '--contrast' in ARGS:
        return contrast_main(sim)
    if '--lists' in ARGS:
        return lists_main(sim)
    only = arg('--only', '').split(',') if arg('--only') else None
    rows, fails = [], []
    for sc in MOMENTS + EXTRA:
        name, place, moment, aim, roll = sc[:5]
        extra = sc[5] if len(sc) > 5 else {}
        if only and name not in only:
            continue
        nodes, png, pose = launch(sim, name, place, moment, aim, roll, 'camera,milkyWay', 'smooth', extra)
        _, base, _ = launch(sim, name, place, moment, aim, roll, 'camera,milkyWay', 'smooth', extra, mw=False)
        pic = parse(nodes)
        row = {'scenario': name, 'pose': [round(pose[0], 1), round(pose[1], 1), roll], 'vis': pic['vis'],
               'hidden': pic['hidden'], 'coreAlt': pic['coreAlt']}
        bad = []
        if not pic['m']:
            bad.append(f"нет картины: vis={pic['vis']} hidden={pic['hidden']}")
        else:
            b2, out = measure(name, nodes, png, pic, base)
            bad += b2
            row.update(out)
            if abs(out.get('k', 0) - 1) > 0.05:
                bad.append(f"яркость полосы зависит от видимости {pic['vis']}: k = {out.get('k')} (ждём 1)")
            if out.get('lift') is not None and out['lift'] < 12:
                bad.append(f"полоса не выше фона: подъём {out['lift']}/255 (порог 12)")
        row['bad'] = bad
        rows.append(row)
        fails += [f'{name}: {b}' for b in bad]
        print(json.dumps(row, ensure_ascii=False))
    if '--frames' in ARGS:
        for name, place, moment, extra in [('frame_night', SOCHI, '2026-08-15T19:30:00Z', {}),
                                           ('frame_city', SOCHI, '2026-08-15T19:30:00Z', {'glow': 12}),
                                           ('frame_twilight', SOCHI, '2026-08-15T17:35:00Z', {}),
                                           ('frame_day', SOCHI, '2026-08-15T14:27:00Z', {'layersOpen': True}),
                                           ('frame_day_closed', SOCHI, '2026-08-15T14:27:00Z', {}),
                                           ('frame_night_list', SOCHI, '2026-08-15T19:30:00Z', {'layersOpen': True})]:
            nodes, png, _ = launch(sim, name, place, moment, (0, 0), 0, None, None, extra)
            pic = parse(nodes)
            row = {'frame': name, 'png': png, 'vis': pic['vis'], 'hidden': pic['hidden'],
                   'layerRow': nodes.get('ar.layer.mw', {}).get('text')}
            if extra.get('layersOpen'):
                t = row['layerRow'] or ''
                for need in ('ядро над горизонтом', 'видимость глазом' if name != 'frame_day' else 'днём не видно',
                             'окно съёмки', 'рисуется по формуле, условно'):
                    if need not in t:
                        fails.append(f'{name}: в строке слоя нет «{need}»: {t}')
                if 'сейчас не видно' in t:
                    fails.append(f"{name}: осталась старая строка «сейчас не видно»: {t}")
            print(json.dumps(row, ensure_ascii=False))
            rows.append(row)
    json.dump(rows, open(os.path.join(OUT, 'report.json'), 'w'), ensure_ascii=False, indent=1)
    print('→ ' + OUT)
    if fails:
        print('НАРУШЕНИЯ:\n' + '\n'.join(fails))
        sys.exit(1)


if __name__ == '__main__':
    main()
