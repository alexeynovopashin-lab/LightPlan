#!/usr/bin/env python3
"""Шаг 29.8в.9а: стекло дисков солнца и луны в AR — по пикселям кадра симулятора, а не по коду.

Слова Алексея 18.10: диски «будто не стеклянные», «не должны отбрасывать тень», «накладываясь друг на друга нет
искажений», блик сверху и снизу «не живые». Четыре замера (подставная камера, сплошной фон `-LPSunARBackdrop`):

  halo     тень за кромкой: средняя яркость кольца 2–10 pt снаружи диска против фона без диска (белый, серый,
           чёрный). 0 — снаружи фон не темнее; минус — темнее (тень, тёмный ореол).
  tilt     живой ли блик: угол самой светлой части кромки (центр тяжести яркости по кругу; `axis` — ось пары бликов
           друг против друга) при крене −20°, 0, +20° подставного положения. Блик, нарисованный в осях экрана,
           стоит на месте (сдвиг 0°). Системное стекло подставного положения не видит: оно берёт свой датчик.
  overlap  гнёт ли верхний диск нижний: кромка нижнего (34 pt) под верхним (48 pt) против того, где она должна
           лежать без стекла — радиальное смещение, pt. Измеряется там, где кромка нижнего попадает в гнущую кромку
           верхнего; эталон — та же кромка нижнего вне верхнего диска.
  bend     гнёт ли диск линию под собой (только новый код: `-LPSunARMarkPos` ставит диск у линии): горизонт дуги
           (слой SwiftUI) и линия сетки подставной камеры (слой Metal / превью). Смещение линии в кромке, pt.

    python3 Tools/ar_glass.py --app <LightPlan.app> [--only halo,tilt,overlap,bend] [--extra "-LPSunARGlass system"]
                              [--out DIR]

`--extra` — аргументы запуска, которые понимает только новый код (старый их не читает): так одна мерка идёт и по
старому, и по новому приложению.
"""
import json, math, os, re, shlex, subprocess, sys, time
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, 'Fixtures', 'shots')
BUNDLE = 'Novopashin.LightPlan'
TOMSK = '56.4977,84.9744,Asia/Tomsk'
NOW = '2026-10-14T12:00:00+07:00'


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def sh(*a, **kw):
    return subprocess.run(a, check=True, capture_output=True, text=True, **kw).stdout


def udid():
    out = subprocess.run(['node', os.path.join(ROOT, 'Tools', 'sim.js')], capture_output=True, text=True, cwd=ROOT).stdout
    m = re.search(r'([0-9A-F]{8}-[0-9A-F-]{27})', out)
    if not m:
        sys.exit('нет симулятора ветки: make sims')
    return m.group(1)


SIM = None
OUT = None
EXTRA = []


def shoot(name, moment, pose, backdrop=None, layers=None, still=False, extra=()):
    """Запуск, рамки узлов, кадр. Возвращает (картинка, узлы, масштаб px/pt)."""
    report = os.path.join(OUT, name + '.json')
    png = os.path.join(OUT, name + '.png')
    if os.path.exists(report):
        os.remove(report)
    subprocess.run(['xcrun', 'simctl', 'terminate', SIM, BUNDLE], capture_output=True)
    a = ['xcrun', 'simctl', 'launch', SIM, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
         '-LPShotNow', NOW, '-LPShotZone', 'Asia/Tomsk', '-LPShotSeed', FX + '/seed.json',
         '-LPShotForecast', FX + '/forecast_barnaul.json', '-LPShotAir', FX + '/air_barnaul.json',
         '-LPShotName', FX + '/place_barnaul.json', '-LPShotScreen', 'map', '-LPShotReportDelay', '5',
         '-lightplan.native.sunar.calibrationSeen', 'YES', '-lightplan.native.sunar.moon', 'NO',
         '-lightplan.native.sunar.milkyWay', 'NO',
         '-LPSunAR', '1', '-LPSunARMoment', moment, '-LPSunARPose', pose, '-LPSunARPhone', TOMSK,
         '-LPSunARFakeCamera', '1', '-LPShotReport', report]
    if backdrop:
        a += ['-LPSunARBackdrop', backdrop]
    if layers:
        a += ['-LPSunARLayers', layers]
    if still:
        a += ['-LPSunARFakeCameraStill', '1']
    a += EXTRA + list(extra)
    sh(*a)
    for _ in range(240):
        if os.path.exists(report):
            break
        time.sleep(0.25)
    time.sleep(1.5)
    sh('xcrun', 'simctl', 'io', SIM, 'screenshot', '--type=png', png)
    nodes = json.load(open(report)).get('nodes', {}) if os.path.exists(report) else {}
    img = Image.open(png).convert('RGB')
    scale = img.size[0] / 440.0
    return img, nodes, scale


def lum(p):
    return 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]


class Px:
    def __init__(self, img, scale):
        self.img, self.s, self.px = img, scale, img.load()
        self.w, self.h = img.size

    def at(self, x, y):
        """Яркость в точке (pt), билинейно."""
        X, Y = x * self.s - 0.5, y * self.s - 0.5
        x0, y0 = int(math.floor(X)), int(math.floor(Y))
        fx, fy = X - x0, Y - y0
        def g(i, j):
            i = min(max(i, 0), self.w - 1); j = min(max(j, 0), self.h - 1)
            return lum(self.px[i, j])
        return (g(x0, y0) * (1 - fx) * (1 - fy) + g(x0 + 1, y0) * fx * (1 - fy)
                + g(x0, y0 + 1) * (1 - fx) * fy + g(x0 + 1, y0 + 1) * fx * fy)

    def ring(self, c, r0, r1, step=0.5, angles=360):
        vals = []
        r = r0
        while r <= r1 + 1e-6:
            for k in range(angles):
                t = 2 * math.pi * k / angles
                vals.append(self.at(c[0] + r * math.cos(t), c[1] + r * math.sin(t)))
            r += step
        return vals


def disc(nodes, key):
    n = nodes.get(key)
    if not n:
        return None
    return (n['x'] + n['w'] / 2, n['y'] + n['h'] / 2), n['w'] / 2


def median(v):
    s = sorted(v)
    return s[len(s) // 2]


# --- halo ---------------------------------------------------------------------------------------------------------

def halo():
    rows = []
    for bd in ('white', 'gray', 'black'):
        img, nodes, s = shoot('halo_' + bd, '2026-10-14T05:00:00Z', '162,24,0', backdrop=bd, layers='camera,lens,paint')
        d = disc(nodes, 'ar.mark.sun.now')
        if not d:
            rows.append({'backdrop': bd, 'error': 'нет диска'}); continue
        c, r = d
        p = Px(img, s)
        bg = median(p.ring(c, r + 40, r + 60, step=2, angles=180))
        near = p.ring(c, r + 2, r + 10, step=0.5, angles=360)
        mean = sum(near) / len(near)
        rows.append({'backdrop': bd, 'disc': [round(c[0], 1), round(c[1], 1), round(2 * r)],
                     'background': round(bg, 1), 'ring_2_10_mean': round(mean, 1),
                     'delta_mean': round(mean - bg, 2), 'delta_darkest': round(min(near) - bg, 1)})
    return rows


# --- tilt ---------------------------------------------------------------------------------------------------------

def highlight_angle(p, c, r):
    """Угол (°, 0 — вправо, 90 — вверх по экрану) центра тяжести света в полосе кромки r−4…r−0,5."""
    bins = []
    for k in range(360):
        t = math.radians(k)
        v = [p.at(c[0] + rr * math.cos(t), c[1] - rr * math.sin(t)) for rr in (r - 4, r - 3, r - 2, r - 1, r - 0.5)]
        bins.append(sum(v) / len(v))
    lo = sorted(bins)[len(bins) // 2]
    sx = sy = ax = ay = 0.0
    for k, v in enumerate(bins):
        w = max(0.0, v - lo)
        sx += w * math.cos(math.radians(k)); sy += w * math.sin(math.radians(k))
        # Ось блика (два блика друг против друга, как у системного стекла): удвоенный угол.
        ax += w * math.cos(math.radians(2 * k)); ay += w * math.sin(math.radians(2 * k))
    return (math.degrees(math.atan2(sy, sx)) % 360), max(bins) - lo, (math.degrees(math.atan2(ay, ax)) / 2) % 180


def tilt():
    rows = []
    for roll in (-20, 0, 20):
        img, nodes, s = shoot('tilt_%+d' % roll, '2026-10-14T05:00:00Z', '162,24,%d' % roll, backdrop='gray',
                              layers='camera,lens,paint')
        d = disc(nodes, 'ar.mark.sun.now')
        if not d:
            rows.append({'roll': roll, 'error': 'нет диска'}); continue
        a, amp, axis = highlight_angle(Px(img, s), *d)
        rows.append({'roll': roll, 'angle': round(a, 1), 'axis': round(axis, 1), 'amplitude': round(amp, 1)})
    base = next((r for r in rows if r.get('roll') == 0 and 'angle' in r), None)
    for r in rows:
        if base is not None and 'angle' in r:
            r['shift'] = round(((r['angle'] - base['angle'] + 180) % 360) - 180, 1)
            r['axis_shift'] = round(((r['axis'] - base['axis'] + 90) % 180) - 90, 1)
    return rows


# --- overlap ------------------------------------------------------------------------------------------------------

def edge_centroid(p, c, rr, t, half=2.0):
    """Радиус (от центра `c`) тёмного контура кромки вдоль луча `t`: самая тёмная точка окна ±`half`, уточнённая
    параболой по соседям (контур — чёрная линия 1 pt; центр тяжести отклонений сбивает перепад заливок)."""
    samples = []
    k = -half
    while k <= half + 1e-6:
        samples.append((rr + k, p.at(c[0] + (rr + k) * math.cos(t), c[1] + (rr + k) * math.sin(t))))
        k += 0.1
    i = min(range(len(samples)), key=lambda j: samples[j][1])
    if 0 < i < len(samples) - 1:
        (x0, a), (_, b), (_, c2) = samples[i - 1], samples[i], samples[i + 1]
        den = a - 2 * b + c2
        if den > 1e-9:
            return samples[i][0] + 0.05 * (a - c2) / den
    return samples[i][0]


def edge_gradient(p, c, rr, t, half=5.0):
    """Кромка вдоль луча `t` как самый крутой перепад яркости в окне ±`half` (pt): (радиус, крутизна на pt).
    Годится и для тёмного контура своего стекла, и для светлой кромки системного: у размазанной кромки крутизна
    падает — это видно по отношению крутизны под верхним диском к крутизне вне его."""
    xs, vs = [], []
    k = -half
    while k <= half + 1e-6:
        xs.append(rr + k); vs.append(p.at(c[0] + (rr + k) * math.cos(t), c[1] + (rr + k) * math.sin(t)))
        k += 0.1
    best, at = 0.0, rr
    for i in range(3, len(vs) - 3):
        g = abs(vs[i + 3] - vs[i - 3]) / 0.6
        if g > best:
            best, at = g, xs[i]
    return at, best


def overlap_measure(img, nodes, s, rim=9.0, bottom='ar.mark.sun.picked', top='ar.mark.sun.now'):
    b, t = disc(nodes, bottom), disc(nodes, top)
    if not b or not t:
        return {'error': 'нет двух дисков: ' + ', '.join(k for k in nodes if k.startswith('ar.mark.'))}
    (cb, rb), (ct, rt) = b, t
    p = Px(img, s)
    inside, outside = [], []
    g_in, g_out = [], []
    for k in range(1440):
        a = 2 * math.pi * k / 1440
        # Только верхняя половина нижнего диска: в нижней у кромки лежит тёмный штрих толщины стекла, его тоже
        # можно принять за контур.
        if math.sin(a) > -0.15:
            continue
        q = (cb[0] + rb * math.cos(a), cb[1] + rb * math.sin(a))
        dt = math.hypot(q[0] - ct[0], q[1] - ct[1])
        e = edge_centroid(p, cb, rb, a)
        eg = edge_gradient(p, cb, rb, a)
        if rt - rim + 1.5 < dt < rt - 2:          # в гнущей кромке верхнего, мимо его волоска и края
            inside.append(e - rb); g_in.append(eg)
        elif dt > rt + 6:                         # вне верхнего диска с запасом
            outside.append(e - rb); g_out.append(eg)
    if not inside or not outside:
        return {'error': 'кромка нижнего не попала в кромку верхнего', 'centers': [cb, ct]}
    ref = median(outside)
    sh_ = [x - ref for x in inside]
    return {'bottom': [round(cb[0], 1), round(cb[1], 1), round(2 * rb)], 'top': [round(ct[0], 1), round(ct[1], 1), round(2 * rt)],
            'samples_in': len(inside), 'samples_out': len(outside),
            'shift_mean_pt': round(sum(abs(x) for x in sh_) / len(sh_), 2), 'shift_max_pt': round(max(abs(x) for x in sh_), 2),
            'shift_signed_median_pt': round(median(sh_), 2),
            # Кромка как самый крутой перепад: сдвиг от того же перепада вне верхнего диска и доля его крутизны.
            'edge_shift_mean_pt': round(sum(abs(x - median([o for o, _ in g_out])) for x, _ in g_in) / len(g_in), 2),
            'edge_sharpness_ratio': round(median([g for _, g in g_in]) / max(1e-6, median([g for _, g in g_out])), 2)}


def overlap():
    rows = []
    for bd in ('gray', 'white', 'black'):
        img, nodes, s = shoot('overlap_' + bd, '2026-10-14T05:06:00Z', '162,24,0', backdrop=bd, layers='camera,lens,paint')
        r = overlap_measure(img, nodes, s)
        r['backdrop'] = bd
        rows.append(r)
    return rows


# --- bend ---------------------------------------------------------------------------------------------------------

def line_y(p, x, y0, y1):
    """Строка (pt) светлой горизонтальной линии в столбце `x` между y0 и y1: центр тяжести превышения медианы."""
    ys, vs = [], []
    y = y0
    while y <= y1:
        ys.append(y); vs.append(p.at(x, y)); y += 0.1
    m = median(vs)
    w = [max(0.0, v - m) for v in vs]
    tot = sum(w)
    return sum(a * b for a, b in zip(ys, w)) / tot if tot > 0 else None


def line_x(p, y, x0, x1):
    xs, vs = [], []
    x = x0
    while x <= x1:
        xs.append(x); vs.append(p.at(x, y)); x += 0.1
    m = median(vs)
    w = [max(0.0, v - m) for v in vs]
    tot = sum(w)
    return sum(a * b for a, b in zip(xs, w)) / tot if tot > 0 else None


def bend():
    """Диск ставится у линии (`-LPSunARMarkPos`), линия проходит в 0,7 r от центра. Смещение линии в кромке."""
    rows = []
    # (а) горизонт дуги: при высоте камеры 0 и крене 0 горизонт — строка у середины экрана; ищется по пикселям.
    img, nodes, s = shoot('bend_arc_probe', '2026-10-14T05:00:00Z', '162,0,0', backdrop='gray', layers='camera,arc',
                          extra=['-LPSunARMarkPos', 'sun.now:60,60'])
    p = Px(img, s)
    hy = line_y(p, 220, 300, 700)
    if hy is None:
        return [{'error': 'горизонт не найден'}]
    for label, layers, still in (('дуга (SwiftUI)', 'camera,arc,lens,paint', False),):
        cx, cy = 220.0, hy - 0.7 * 24
        img, nodes, s = shoot('bend_arc', '2026-10-14T05:00:00Z', '162,0,0', backdrop='gray', layers=layers,
                              extra=['-LPSunARMarkPos', 'sun.now:%.1f,%.1f' % (cx, cy)])
        rows.append(bend_measure(Px(img, s), nodes, label, 'h', hy))
    # (б) сетка подставной камеры: вертикальная линия. Сперва — где она без диска.
    img, nodes, s = shoot('bend_cam_probe', '2026-10-14T05:00:00Z', '162,0,0', layers='camera', still=True,
                          extra=['-LPSunARMarkPos', 'sun.now:20,20'])
    p = Px(img, s)
    # Самый светлый столбец в строке 600 (линия сетки), затем середина линии по окну ±3 pt.
    xs = [150 + k * 0.25 for k in range(441)]
    peak = max(xs, key=lambda x: p.at(x, 600))
    lx = line_x(p, 600, peak - 3, peak + 3)
    if lx is not None:
        cx, cy = lx - 0.7 * 24, 600.0
        img, nodes, s = shoot('bend_cam', '2026-10-14T05:00:00Z', '162,0,0', layers='camera,arc,lens,paint', still=True,
                              extra=['-LPSunARMarkPos', 'sun.now:%.1f,%.1f' % (cx, cy)])
        rows.append(bend_measure(Px(img, s), nodes, 'кадр камеры (Metal)', 'v', lx))
    return rows


def bend_measure(p, nodes, label, axis, line):
    d = disc(nodes, 'ar.mark.sun.now')
    if not d:
        return {'layer': label, 'error': 'нет диска'}
    (cx, cy), r = d
    # Линия вне диска (эталон) и в кромке: точки на линии, где расстояние до центра r−5…r−2.
    best = []
    span = 6
    for k in range(-60, 61):
        u = k * 0.4
        if axis == 'h':
            x, y0 = cx + u, line
            dist = math.hypot(x - cx, y0 - cy)
            if r - 6 < dist < r - 2:
                f = line_y(p, x, y0 - span, y0 + span)
                if f is not None: best.append(f - line)
        else:
            y, x0 = cy + u, line
            dist = math.hypot(x0 - cx, y - cy)
            if r - 6 < dist < r - 2:
                f = line_x(p, y, x0 - span, x0 + span)
                if f is not None: best.append(f - line)
    ref = []
    for u in (-60, -50, 50, 60):
        if axis == 'h':
            f = line_y(p, cx + u, line - span, line + span)
        else:
            f = line_x(p, cy + u, line - span, line + span)
        if f is not None: ref.append(f - line)
    off = median(ref) if ref else 0
    if not best:
        return {'layer': label, 'error': 'линия не прошла кромкой'}
    sh_ = [b - off for b in best]
    return {'layer': label, 'disc': [round(cx, 1), round(cy, 1), round(2 * r)], 'line': round(line, 1),
            'outside_offset_pt': round(off, 2), 'samples': len(sh_),
            'shift_max_pt': round(max(abs(x) for x in sh_), 2), 'shift_mean_pt': round(sum(abs(x) for x in sh_) / len(sh_), 2)}


def main():
    global SIM, OUT, EXTRA
    app = arg('--app')
    if not app:
        sys.exit(__doc__)
    OUT = os.path.abspath(arg('--out', '/tmp/cc-ar-glass'))
    os.makedirs(OUT, exist_ok=True)
    EXTRA = shlex.split(arg('--extra', ''))
    SIM = udid()
    subprocess.run(['xcrun', 'simctl', 'boot', SIM], capture_output=True)
    sh('xcrun', 'simctl', 'install', SIM, app)
    sh('xcrun', 'simctl', 'ui', SIM, 'appearance', 'dark')
    only = arg('--only', 'halo,tilt,overlap').split(',')
    res = {}
    for name in only:
        res[name] = globals()[name]()
        for r in res[name]:
            print(name, json.dumps(r, ensure_ascii=False))
    json.dump(res, open(os.path.join(OUT, 'ar_glass.json'), 'w'), ensure_ascii=False, indent=1)
    print('→', OUT)


main()
