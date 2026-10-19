#!/usr/bin/env python3
"""Шаг 29.8в.4: что стоит слой стеклянных дисков над кадром камеры. Симулятор, подставная камера
(`-LPSunARFakeCamera 1`: 30 кадров/с из двух заранее нарисованных), числа:

  - кадров/с, принятых слоем (журнал `-LPSunARLensLog`: принято, нарисовано, кадров/с, мс процессора на кадр);
  - загрузка процесса приложения (ps, приращение процессорного времени за окно) — с дисками в кадре и без них
    (камера смотрит в сторону: ни солнца, ни луны — дисков нет, слой только показывает кадр).

Телефон и энергия этим не мерятся: симулятор считает на видеокарте мака, а не на A-серии.

    python3 Tools/ar_lens_bench.py [--seconds 20] [--out FILE] [--extra "-lightplan.native.sunar.glass own"] [--stars]

`--stars` (29.8в.13): вместо дневных строк — ночные: слои «Звёзды» и «Созвездия» включены и выключены в одном и том же кадре
(ночь 20 октября, Томск, камера на Лиру), и числа «со слоем» против «без слоя».

`--planets` (29.8в.15): ночь 5 ноября, Томск, камера на Марс и Юпитер (обе планеты и их подписи в кадре): слой «Планеты»
выключен и включён, две пробы подряд — цена слоя планет.

`--extra` — аргументы запуска сверх своих: так сравниваются своё и системное стекло дисков (29.8в.9а).
`--milkyway` (29.8в.14) — ночь над Сочи 15.08 22:30, камера на ядро (полоса во весь экран): по три прогона с
Млечным Путём и без него, по очереди; печатает средние и разброс — цена слоя полосы.
"""
import json, math, os, re, shlex, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, 'Fixtures', 'shots')
BUNDLE = 'Novopashin.LightPlan'
EXTRA = shlex.split(sys.argv[sys.argv.index('--extra') + 1]) if '--extra' in sys.argv else []


def sh(*a):
    return subprocess.run(a, check=True, capture_output=True, text=True).stdout


def udid():
    out = subprocess.run(['node', os.path.join(ROOT, 'Tools', 'sim.js')], capture_output=True, text=True, cwd=ROOT).stdout
    m = re.search(r'([0-9A-F]{8}-[0-9A-F-]{27})', out)
    if not m:
        sys.exit('нет симулятора ветки: make sims')
    return m.group(1)


def cpu_seconds(pid):
    t = sh('ps', '-o', 'time=', '-p', str(pid)).strip()          # [[HH:]MM:]SS.cc
    parts = [float(x) for x in t.split(':')]
    s = 0.0
    for p in parts:
        s = s * 60 + p
    return s


def rss_mb(pid):
    return int(sh('ps', '-o', 'rss=', '-p', str(pid)).strip()) / 1024


NIGHT = ('2026-10-20T14:00:00Z', '2026-10-20T21:00:00+07:00')
DAY = ('2026-10-14T05:00:00Z', '2026-10-14T12:00:00+07:00')
# 29.8в.14: ночь над Сочи 15.08 22:30, ядро над горизонтом; обзор вокруг ядра — новая поза каждые 50 мс
# (`-LPSunARPoseHold 50`), 20 с — экран перерисовывается на каждом отсчёте.
MW_NIGHT = ('2026-08-15T19:30:00Z', '2026-08-15T19:30:00Z')
TOMSK, SOCHI = '56.4977,84.9744,Asia/Tomsk', '43.585,39.723,Europe/Moscow'
SWEEP = ';'.join(f'{206.2 + 12 * math.sin(i / 25):.2f},{20.6 + 6 * math.sin(i / 17):.2f},{4 * math.sin(i / 40):.2f}'
                 for i in range(400))


def run(sim, label, pose, seconds, log, when=DAY, moon='YES', stars='NO', mw=None, planets='NO'):
    if os.path.exists(log):
        os.remove(log)
    subprocess.run(['xcrun', 'simctl', 'terminate', sim, BUNDLE], capture_output=True)
    out = sh('xcrun', 'simctl', 'launch', sim, BUNDLE, '-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
             '-LPShotNow', when[1], '-LPShotZone', 'Asia/Tomsk', '-LPShotSeed', FX + '/seed.json',
             '-LPShotForecast', FX + '/forecast_barnaul.json', '-LPShotAir', FX + '/air_barnaul.json',
             '-LPShotName', FX + '/place_barnaul.json', '-LPShotScreen', 'map',
             '-lightplan.native.sunar.calibrationSeen', 'YES', '-lightplan.native.sunar.moon', moon,
             '-lightplan.native.sunar.milkyWay', 'YES' if mw else 'NO',
             '-lightplan.native.sunar.stars', stars, '-lightplan.native.sunar.constellations', stars,
             '-lightplan.native.sunar.planets', planets,
             '-LPSunAR', '1', '-LPSunARMoment', when[0], '-LPSunARPose', pose,
             '-LPSunARPhone', SOCHI if mw is not None else TOMSK, '-LPSunARFakeCamera', '1', '-LPSunARLensLog', log,
             *(['-LPSunARGlow', '0', '-LPSunARPoseHold', '50'] if mw is not None else []), *EXTRA)
    pid = int(re.search(r':\s*(\d+)', out).group(1))
    time.sleep(6)                                                # запуск, первая отрисовка
    c0, t0 = cpu_seconds(pid), time.time()
    time.sleep(seconds)
    c1, t1 = cpu_seconds(pid), time.time()
    last = open(log).read().strip().splitlines()[-1] if os.path.exists(log) else ''
    m = dict(re.findall(r'(\w+)=([0-9.]+)', last))
    return {'label': label, 'pose': pose, 'mw': bool(mw), 'cpu_percent': round((c1 - c0) / (t1 - t0) * 100, 1),
            'rss_mb': round(rss_mb(pid)), 'frames_in': int(m.get('in', 0)), 'frames_drawn': int(m.get('drawn', 0)),
            'fps': float(m.get('fps', 0)), 'renderer_cpu_ms_per_frame': float(m.get('cpuMsPerFrame', 0))}


def main():
    seconds = 20
    if '--seconds' in sys.argv:
        seconds = int(sys.argv[sys.argv.index('--seconds') + 1])
    sim = udid()
    subprocess.run(['xcrun', 'simctl', 'boot', sim], capture_output=True)
    log = '/tmp/cc-lens-log.txt'
    if '--milkyway' in sys.argv:
        rows = []
        for i in range(3):
            for mw in (False, True):
                rows.append(run(sim, 'ночь, камеру водят ±12° вокруг ядра', SWEEP, seconds, log, MW_NIGHT, moon='NO', mw=mw))
                print(json.dumps(rows[-1], ensure_ascii=False), flush=True)
        for mw in (False, True):
            rs = [r for r in rows if r['mw'] == mw]
            for k in ('cpu_percent', 'fps', 'renderer_cpu_ms_per_frame'):
                v = [r[k] for r in rs]
                print(('с полосой' if mw else 'без полосы'), k, 'среднее', round(sum(v) / len(v), 2), 'разброс', round(max(v) - min(v), 2))
        if '--out' in sys.argv:
            open(sys.argv[sys.argv.index('--out') + 1], 'w').write(json.dumps(rows, ensure_ascii=False, indent=1))
        return
    if '--planets' in sys.argv:
        night = ('2026-11-04T20:00:00Z', '2026-11-04T03:00:00+07:00')
        rows = []
        for i in range(3):
            for on in ('NO', 'YES'):
                label = 'ночь, «Планеты» ' + ('включены (Марс и Юпитер в кадре)' if on == 'YES' else 'выключены') + f', проба {i + 1}'
                rows.append(run(sim, label, '93,20,0', seconds, log, night, moon='NO', planets=on))
                rows[-1]['planets'] = on == 'YES'
                time.sleep(2)
    elif '--stars' in sys.argv:
        rows = [run(sim, 'ночь, слои звёзд выключены', '240,52,0', seconds, log, NIGHT, moon='NO', stars='NO'),
                run(sim, 'ночь, «Звёзды» и «Созвездия» включены', '240,52,0', seconds, log, NIGHT, moon='NO', stars='YES'),
                run(sim, 'ночь, слои выключены (вторая проба)', '240,52,0', seconds, log, NIGHT, moon='NO', stars='NO'),
                run(sim, 'ночь, слои включены (вторая проба)', '240,52,0', seconds, log, NIGHT, moon='NO', stars='YES')]
    else:
        rows = [run(sim, 'диски в кадре (солнце + луна)', '162,24,0', seconds, log),
                run(sim, 'дисков нет (смотрим на север и вверх)', '0,70,0', seconds, log)]
    for r in rows:
        print(json.dumps(r, ensure_ascii=False))
    if '--planets' in sys.argv:
        for on in (False, True):
            rs = [r for r in rows if r['planets'] == on and r['frames_in'] > 0]
            for k in ('cpu_percent', 'fps', 'renderer_cpu_ms_per_frame'):
                v = [r[k] for r in rs]
                print(('с планетами' if on else 'без планет'), k, 'проб', len(v), 'среднее', round(sum(v) / len(v), 2), 'разброс', round(max(v) - min(v), 2))
    if '--out' in sys.argv:
        open(sys.argv[sys.argv.index('--out') + 1], 'w').write(json.dumps(rows, ensure_ascii=False, indent=1))


main()
