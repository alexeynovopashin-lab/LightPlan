#!/usr/bin/env python3
"""Эталон восхода и захода ядра Млечного Пути для AR (шаг 29.8в.17б): astropy, независимо от кода приложения.

Ядро — центр Галактики (l = 0, b = 0). Для места и даты берётся сетка в одну минуту по часам места, положение
считает astropy (`SkyCoord` галактической системы → `AltAz` с учётом прецессии, нутации, аберрации и рефракции
положение без рефракции): восход и заход — где геометрическая высота пересекает −0,5667° (34′ — стандартная
рефракция у горизонта, как в астрономических таблицах восхода звёзд), линейно между минутами; азимут — там же.
Рефракцию ERFA из astropy не берём: у горизонта она даёт +0,18° вместо 0,57° (измерено), модель обрезана на больших
зенитных расстояниях. Приложение считает иначе (координаты J2000 без прецессии, рефракция Сэмундссона), поэтому
сверка — допуск 2 минуты и 0,5°, как в описании шага.

    python3 Tools/mw_core_ref.py            # пишет Fixtures/mw_core_astropy.json (читает MilkyWayCoreTrackTests)

Нужны astropy и numpy; сеть не нужна (таблицы IERS не скачиваются, для будущих дат берётся точность без них).
"""
import datetime, json, os, sys
from zoneinfo import ZoneInfo

import numpy as np
import astropy.units as u
from astropy.coordinates import AltAz, EarthLocation, SkyCoord
from astropy.time import Time
from astropy.utils import iers

iers.conf.auto_download = False
iers.conf.iers_degraded_accuracy = 'ignore'

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'Fixtures', 'mw_core_astropy.json')

PLACES = [
    # имя, широта, долгота, зона
    ('tomsk', 56.4977, 84.9744, 'Asia/Tomsk'),
    ('sydney', -33.8688, 151.2093, 'Australia/Sydney'),
    ('moscow', 55.7558, 37.6173, 'Europe/Moscow'),
    # Край: широта 70° — ядро не восходит; −70° — не заходит; широта 62° — на пределе, одно событие в сутки.
    ('lat70', 70.0, 25.0, 'Europe/Oslo'),
    ('lat_m70', -70.0, -68.0, 'America/Argentina/Ushuaia'),
]
# Пять дат в разные сезоны (Сидней — и с переходом на летнее время, и без).
DATES = ['2026-01-15', '2026-04-10', '2026-06-21', '2026-08-30', '2026-11-12']

CORE = SkyCoord(l=0 * u.deg, b=0 * u.deg, frame='galactic')


def day_track(lat, lon, zone, day):
    tz = ZoneInfo(zone)
    y, m, d = map(int, day.split('-'))
    start = datetime.datetime(y, m, d, tzinfo=tz)
    # Сутки по часам места: от полуночи до следующей (в день перехода на летнее время их не 24 часа, но приложение
    # считает сутки как 1440 минут от полуночи и смещение берёт на дату, как и здесь по полуночи).
    offset = start.utcoffset().total_seconds() / 3600
    utc0 = start.astimezone(datetime.timezone.utc)
    minutes = np.arange(0, 1441)
    times = Time(utc0) + minutes * u.min
    loc = EarthLocation.from_geodetic(lon=lon * u.deg, lat=lat * u.deg, height=0 * u.m)
    aa = CORE.transform_to(AltAz(obstime=times, location=loc))
    return minutes, aa.alt.deg, aa.az.deg, offset


HORIZON = -0.5667


def events(minutes, alt, az):
    out = []
    for i in range(len(minutes) - 1):
        a0, a1 = alt[i] - HORIZON, alt[i + 1] - HORIZON
        if (a0 < 0) != (a1 < 0):
            f = a0 / (a0 - a1)
            t = minutes[i] + f
            z0, z1 = az[i], az[i + 1]
            if abs(z1 - z0) > 180:
                z1 += 360 if z1 < z0 else -360
            out.append({'kind': 'rise' if a1 >= 0 else 'set', 'minutes': round(float(t), 3),
                        'azimuth': round(float((z0 + (z1 - z0) * f) % 360), 3)})
    return out


def main():
    cases = []
    for name, lat, lon, zone in PLACES:
        for day in DATES:
            minutes, alt, az, offset = day_track(lat, lon, zone, day)
            ev = events(minutes, alt, az)
            state = 'crossing' if ev else ('neverSets' if alt[0] >= HORIZON else 'neverRises')
            cases.append({'place': name, 'lat': lat, 'lon': lon, 'zone': zone, 'date': day, 'utcOffset': offset,
                          'state': state, 'events': ev,
                          # Несколько отсчётов для сверки положения: час, азимут, наблюдаемая высота.
                          'samples': [{'minutes': int(k), 'azimuth': round(float(az[k]), 3),
                                       'altitude': round(float(alt[k]), 3)} for k in (0, 360, 720, 1080, 1320)]})
    with open(OUT, 'w') as f:
        json.dump({'meta': {'source': 'astropy ' + __import__('astropy').__version__,
                            'horizon': 'geometric altitude -0.5667 deg (34 arcmin refraction)', 'tolerance': '2 min, 0.5 deg'},
                   'cases': cases}, f, ensure_ascii=False, indent=1)
    print('written', OUT, len(cases), 'cases')


if __name__ == '__main__':
    sys.exit(main())
