#!/usr/bin/env python3
"""Шаг 29.8в.6: насыщенность видимого цвета диска солнца на белом, сером и чёрном фоне.

Симулятор, сплошной фон (`-LPSunARBackdrop white|gray|black`, отладка) вместо кадра камеры. Камера смотрит прямо
на солнце, метка стоит в середине кадра. Для каждой высоты солнца (день, золотой час, закат, синий час, призрак)
берётся рамка метки из отчёта приложения (`-LPShotReport`), внутри неё — круг радиуса 0,5 от радиуса метки
(мимо кромки), медиана по каналам, насыщенность HSV. Фоны: белый v = 0,95 (`Color(white: 1)` приложения плюс
стекло «Света»), серый 0,5, чёрный 0 — фон меряется на том же снимке, у угла экрана.

    python3 Tools/ar_disc_sat.py --app <путь к .app> [--out DIR] [--only a,b] [--json file]
Код 1, если не выполнены цели: закат и золотой час ≥ 0,55, призрак под горизонтом ≥ 0,40 на любом из трёх фонов.
"""
import colorsys, datetime, json, math, os, re, statistics, subprocess, sys, tempfile, time
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, 'Fixtures', 'shots')
BUNDLE = 'Novopashin.LightPlan'
LAT, LON, ZONE = 56.4977, 84.9744, 'Asia/Tomsk'
BACKDROPS = (('white', 0.95), ('gray', 0.5), ('black', 0.0))

# Состояния света: имя, целевая геометрическая высота, день для поиска, цель насыщенности (None — не проверяется)
STATES = [
    ('день +40°', 40, '2026-06-21', None),
    ('золотой час +6°', 6, '2026-10-20', 0.55),
    ('золотой час +3°', 3, '2026-10-20', 0.55),
    ('закат −0,8°', -0.8, '2026-10-20', 0.55),
    ('под горизонтом −2°', -2, '2026-10-20', 0.40),
    ('синий час −5°', -5, '2026-10-20', 0.40),
    ('призрак −8°', -8, '2026-10-20', 0.40),
    ('призрак −12°', -12, '2026-10-20', 0.40),
    ('ночь −20°', -20, '2026-10-20', 0.40),
]


def sun_position(utc):
    """Геометрическая высота и азимут солнца (NOAA, точность порядка сотых градуса)."""
    jd = utc.timestamp() / 86400 + 2440587.5
    t = (jd - 2451545.0) / 36525
    l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)) % 360
    m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
    e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
    c = (math.sin(math.radians(m)) * (1.914602 - t * (0.004817 + 0.000014 * t))
         + math.sin(math.radians(2 * m)) * (0.019993 - 0.000101 * t) + math.sin(math.radians(3 * m)) * 0.000289)
    true_long = l0 + c
    omega = 125.04 - 1934.136 * t
    lam = true_long - 0.00569 - 0.00478 * math.sin(math.radians(omega))
    eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
    eps = eps0 + 0.00256 * math.cos(math.radians(omega))
    decl = math.degrees(math.asin(math.sin(math.radians(eps)) * math.sin(math.radians(lam))))
    y = math.tan(math.radians(eps / 2)) ** 2
    eqt = 4 * math.degrees(y * math.sin(2 * math.radians(l0)) - 2 * e * math.sin(math.radians(m))
                           + 4 * e * y * math.sin(math.radians(m)) * math.cos(2 * math.radians(l0))
                           - 0.5 * y * y * math.sin(4 * math.radians(l0)) - 1.25 * e * e * math.sin(2 * math.radians(m)))
    minutes = utc.hour * 60 + utc.minute + utc.second / 60
    tst = (minutes + eqt + 4 * LON) % 1440
    ha = tst / 4 - 180
    lat, d, h = math.radians(LAT), math.radians(decl), math.radians(ha)
    alt = math.asin(math.sin(lat) * math.sin(d) + math.cos(lat) * math.cos(d) * math.cos(h))
    az = math.degrees(math.atan2(math.sin(h), math.cos(h) * math.sin(lat) - math.tan(d) * math.cos(lat))) + 180
    return math.degrees(alt), az % 360


def find_moment(day, target):
    """Минута вечера дня `day` (UTC), на которой высота ближе всего к `target`."""
    base = datetime.datetime.fromisoformat(day + 'T04:00:00+00:00')   # 11:00 по Томску
    best = None
    for k in range(0, 17 * 60):
        t = base + datetime.timedelta(minutes=k)
        alt, az = sun_position(t)
        if best is None or abs(alt - target) < abs(best[1] - target):
            best = (t, alt, az)
    return best


def sh(*a):
    return subprocess.run(a, check=True, capture_output=True, text=True).stdout


def sim_udid():
    out = subprocess.run(['node', os.path.join(ROOT, 'Tools', 'sim.js')], capture_output=True, text=True, cwd=ROOT).stdout
    m = re.search(r'([0-9A-F]{8}-[0-9A-F-]{27})', out)
    if not m:
        sys.exit('нет симулятора ветки: make sims')
    return m.group(1)


def hsv_sat(rgb):
    return colorsys.rgb_to_hsv(*(c / 255 for c in rgb))


def disc_colour(img, frame, scale):
    cx = (frame['x'] + frame['w'] / 2) * scale
    cy = (frame['y'] + frame['h'] / 2) * scale
    r = frame['w'] / 2 * scale * 0.5
    px = img.convert('RGB').load()
    chans = ([], [], [])
    for y in range(int(cy - r), int(cy + r) + 1):
        for x in range(int(cx - r), int(cx + r) + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                p = px[x, y]
                for i in range(3):
                    chans[i].append(p[i])
    return tuple(statistics.median(c) for c in chans)


def main():
    args = sys.argv[1:]
    def opt(name, default=None):
        return args[args.index(name) + 1] if name in args else default
    app = opt('--app')
    if not app or not os.path.isdir(app):
        sys.exit('нужен --app <путь к .app>')
    out = opt('--out') or tempfile.mkdtemp(prefix='lp-ar-sat-')
    os.makedirs(out, exist_ok=True)
    only = opt('--only').split(',') if opt('--only') else None
    udid = sim_udid()
    subprocess.run(['xcrun', 'simctl', 'boot', udid], capture_output=True)
    sh('xcrun', 'simctl', 'install', udid, app)
    sh('xcrun', 'simctl', 'ui', udid, 'appearance', 'dark')
    result, failures = [], []
    for name, target, day, goal in STATES:
        if only and name.split()[0] not in only and str(target) not in only:
            continue
        moment, alt, az = find_moment(day, target)
        iso = moment.strftime('%Y-%m-%dT%H:%M:%SZ')
        local = (moment + datetime.timedelta(hours=7)).strftime('%Y-%m-%dT%H:%M:%S+07:00')
        row = {'state': name, 'altitude': round(alt, 2), 'sat': {}, 'rgb': {}}
        for bd, _ in BACKDROPS:
            report = os.path.join(out, '%s_%s.json' % (target, bd))
            png = os.path.join(out, '%s_%s.png' % (target, bd))
            if os.path.exists(report):
                os.remove(report)
            subprocess.run(['xcrun', 'simctl', 'terminate', udid, BUNDLE], capture_output=True)
            sh('xcrun', 'simctl', 'launch', udid, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
               '-LPShotNow', local, '-LPShotZone', ZONE, '-LPShotSeed', FX + '/seed.json',
               '-LPShotForecast', FX + '/forecast_barnaul.json', '-LPShotAir', FX + '/air_barnaul.json',
               '-LPShotName', FX + '/place_barnaul.json', '-LPShotScreen', 'map', '-LPShotReportDelay', '5',
               '-lightplan.native.sunar.calibrationSeen', 'YES', '-lightplan.native.sunar.moon', 'NO',
               '-lightplan.native.sunar.milkyWay', 'NO', '-LPSunAR', '1', '-LPSunARMoment', iso,
               '-LPSunARPose', '%.2f,%.2f,0' % (az, alt), '-LPSunARPhone', '%s,%s,%s' % (LAT, LON, ZONE),
               '-LPSunARBackdrop', bd, '-LPShotReport', report)
            for _ in range(240):
                if os.path.exists(report):
                    break
                time.sleep(0.25)
            else:
                sys.exit('нет рамок: %s %s' % (name, bd))
            time.sleep(1.5)
            sh('xcrun', 'simctl', 'io', udid, 'screenshot', '--type=png', png)
            data = json.load(open(report))
            nodes = data['nodes']
            mark = nodes.get('ar.mark.sun.now') or nodes.get('ar.mark.sun.picked')
            if not mark:
                sys.exit('нет метки солнца: %s %s' % (name, bd))
            img = Image.open(png)
            scale = img.size[0] / data['size'][0]
            rgb = disc_colour(img, mark, scale)
            h, s, v = hsv_sat(rgb)
            row['sat'][bd] = round(s, 3)
            row['rgb'][bd] = [int(c) for c in rgb]
        row['min'] = min(row['sat'].values())
        row['goal'] = goal
        if goal is not None and row['min'] < goal:
            failures.append('%s: %.2f < %.2f' % (name, row['min'], goal))
        result.append(row)
    print('%-22s %7s %8s %8s %8s %6s' % ('состояние', 'высота', 'белый', 'серый', 'чёрный', 'цель'))
    for r in result:
        print('%-22s %+6.1f° %8.2f %8.2f %8.2f %6s   rgb(белый)=%s' % (
            r['state'], r['altitude'], r['sat']['white'], r['sat']['gray'], r['sat']['black'],
            ('≥%.2f' % r['goal']) if r['goal'] else '—', tuple(r['rgb']['white'])))
    if opt('--json'):
        json.dump(result, open(opt('--json'), 'w'), ensure_ascii=False, indent=1)
    print('→ ' + out)
    if failures:
        print('НЕ ДОТЯНУТО: ' + '; '.join(failures))
        sys.exit(1)


main()
