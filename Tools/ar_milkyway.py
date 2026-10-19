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
  4. солнце выше −6° — слой пуст (ни одной точки ярче 2/255), сумерки и засветка — та же формула с видимостью.

Пять моментов: разные широты (−34°…+64°), часы, курсы и крен кадра. Плюс кадры для глаза (`--frames`): ночь без
засветки, ночь с городом (`-LPSunARGlow 12`), сумерки, день — все слои, без камеры.

    python3 Tools/ar_milkyway.py --app <LightPlan.app> [--out DIR] [--only a,b] [--frames]
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
    h = math.radians(280.16 + 360.9856235 * d) + math.radians(lon) - ra
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
    # Засветка 3 (ступень «слабая»): контраст 1/4 — свет ещё различим по 8 битам; кадр для глаза — с 12.
    ('sochi_city', SOCHI, '2026-08-15T19:30:00Z', (0, 0), 0, {'glow': 3}),
    ('sochi_twilight', SOCHI, '2026-08-15T17:55:00Z', (0, 0), 0, {}),
    ('sochi_day', SOCHI, '2026-08-15T12:00:00Z', (0, 0), 0, {'empty': True}),
]


def sh(*a, **kw):
    return subprocess.run(a, check=True, capture_output=True, text=True, **kw).stdout


def udid():
    out = subprocess.run(['node', os.path.join(ROOT, 'Tools', 'sim.js')], capture_output=True, text=True, cwd=ROOT).stdout
    m = re.search(r'([0-9A-F]{8}-[0-9A-F-]{27})', out)
    if not m:
        sys.exit('нет симулятора ветки: make sims')
    return m.group(1)


def launch(sim, name, place, moment, aim, roll, layers, parts, extra, mw=True):
    lat, lon, zone = place
    ra, dec = gal_to_eq(*aim)
    az, alt = horizontal(ra, dec, moment, lat, lon)
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    report = os.path.join(d, 'native.json' if mw else 'base.json')
    if os.path.exists(report):
        os.remove(report)
    subprocess.run(['xcrun', 'simctl', 'terminate', sim, BUNDLE], capture_output=True)
    argv = ['xcrun', 'simctl', 'launch', sim, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
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
            exp_ = 255 * green(gl) * min(1.0, smooth(gl, gb) * 0.55 * vis * fade(alt))
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
           'profileResidual': round(resid, 4)}
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


def main():
    sim = udid()
    subprocess.run(['xcrun', 'simctl', 'boot', sim], capture_output=True)
    app = arg('--app')
    if app:
        sh('xcrun', 'simctl', 'install', sim, app)
    sh('xcrun', 'simctl', 'ui', sim, 'appearance', 'dark')
    os.makedirs(OUT, exist_ok=True)
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
        if extra.get('empty'):
            mx = empty(png, nodes, base)
            row['maxPixel'] = mx
            if pic['vis'] != 0:
                bad.append(f"днём видимость {pic['vis']}, не 0")
            if mx > 2:
                bad.append(f'днём слой не пуст: ярчайшая точка {mx}/255')
        elif not pic['m'] or not pic['vis']:
            bad.append(f"нет картины: vis={pic['vis']} hidden={pic['hidden']}")
        else:
            b2, out = measure(name, nodes, png, pic, base)
            bad += b2
            row.update(out)
            if abs(out.get('k', 0) - 1) > 0.05:
                bad.append(f"яркость кадра не та, что у формулы с видимостью {pic['vis']}: k = {out.get('k')}")
        row['bad'] = bad
        rows.append(row)
        fails += [f'{name}: {b}' for b in bad]
        print(json.dumps(row, ensure_ascii=False))
    if '--frames' in ARGS:
        for name, place, moment, extra in [('frame_night', SOCHI, '2026-08-15T19:30:00Z', {}),
                                           ('frame_city', SOCHI, '2026-08-15T19:30:00Z', {'glow': 12}),
                                           ('frame_twilight', SOCHI, '2026-08-15T17:35:00Z', {}),
                                           ('frame_day', SOCHI, '2026-08-15T12:00:00Z', {'layersOpen': True}),
                                           ('frame_night_list', SOCHI, '2026-08-15T19:30:00Z', {'layersOpen': True})]:
            nodes, png, _ = launch(sim, name, place, moment, (0, 0), 0, None, None, extra)
            pic = parse(nodes)
            row = {'frame': name, 'png': png, 'vis': pic['vis'], 'hidden': pic['hidden'],
                   'layerRow': nodes.get('ar.layer.mw', {}).get('text')}
            if extra.get('layersOpen'):
                t = row['layerRow'] or ''
                if 'рисуется по формуле, условно' not in t:
                    fails.append(f'{name}: в строке слоя нет «рисуется по формуле, условно»: {t}')
                if (pic['vis'] == 0) != ('сейчас не видно' in t):
                    fails.append(f"{name}: строка слоя «{t}» при видимости {pic['vis']}")
            print(json.dumps(row, ensure_ascii=False))
            rows.append(row)
    json.dump(rows, open(os.path.join(OUT, 'report.json'), 'w'), ensure_ascii=False, indent=1)
    print('→ ' + OUT)
    if fails:
        print('НАРУШЕНИЯ:\n' + '\n'.join(fails))
        sys.exit(1)


main()
