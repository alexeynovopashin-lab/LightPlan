#!/usr/bin/env python3
"""Эталон Солнца для экранов приложения (шаг 29.8в.25): JPL Horizons, 5 мест × 12 дат 2026 года.

Для каждой пары «место, дата» берёт у Horizons азимут и высоту Солнца (Q4, без рефракции, место на уровне моря)
**каждую минуту** суток по часам места (с запасом ±2 часа), ищет по ним пересечения порогов высоты — восход и закат
(−0,833°), золотой час (+6°), синий (−4°), гражданские (−6°), навигационные (−12°) и астрономические (−18°) сумерки —
линейной интерполяцией между минутами и записывает события и положение Солнца каждые 30 минут.
Пороги те же, что у `SolarDay`: меняется только положение Солнца, не определение события.

Читает `SolarDayExactTests` (`Packages/LightPlanCore/Tests/LightPlanCoreTests`). Сеть нужна только здесь:

    python3 Tools/sun_horizons_ref.py

Тромсё (69,65° с. ш.) взят нарочно: 20 мая и 25 июля Солнце там едва касается горизонта, и время события плохо
определено — ошибка в минутах велика даже при ошибке положения в сотые доли градуса. Эти случаи в тесте отдельно.
"""
import datetime, json, os, sys, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Fixtures", "sun_horizons.json")
API = "https://ssd.jpl.nasa.gov/api/horizons.api"

# имя: (широта, долгота, высота над уровнем моря в км, смещение пояса часов на дату)
PLACES = {
    "tomsk": (56.4977, 84.9744, 0.1, lambda d: 7), "moscow": (55.7558, 37.6173, 0.15, lambda d: 3),
    "tromso": (69.6492, 18.9553, 0.0, lambda d: 2 if (3, 29) <= (d[1], d[2]) < (10, 25) else 1),
    "capetown": (-33.9249, 18.4241, 0.0, lambda d: 2), "honolulu": (21.3069, -157.8583, 0.0, lambda d: -10),
}
DATES = [(2026, 1, 15), (2026, 2, 20), (2026, 3, 20), (2026, 4, 25), (2026, 5, 20), (2026, 6, 21), (2026, 7, 25),
         (2026, 8, 25), (2026, 9, 23), (2026, 10, 21), (2026, 11, 26), (2026, 12, 21)]
# событие: (порог высоты, +1 восходящее / −1 нисходящее) — как поля `SolarDay`
THRESHOLDS = {"rise": (-0.833, 1), "set": (-0.833, -1), "goldA": (6, 1), "goldB": (6, -1), "blueA": (-4, 1),
              "blueB": (-4, -1), "civA": (-6, 1), "civB": (-6, -1), "nauA": (-12, 1), "nauB": (-12, -1),
              "astA": (-18, 1), "astB": (-18, -1)}
MARGIN = 120  # минут запаса до и после суток


def fetch(lat, lon, alt, tz, d):
    mid = datetime.datetime(*d, tzinfo=datetime.timezone.utc) - datetime.timedelta(hours=tz)
    start, stop = mid - datetime.timedelta(minutes=MARGIN), mid + datetime.timedelta(minutes=1440 + MARGIN)
    f = lambda t: t.strftime("%Y-%m-%d %H:%M")
    q = {"format": "text", "COMMAND": "'10'", "OBJ_DATA": "'NO'", "MAKE_EPHEM": "'YES'", "EPHEM_TYPE": "'OBSERVER'",
         "CENTER": "'coord@399'", "SITE_COORD": f"'{lon},{lat},{alt}'", "COORD_TYPE": "'GEODETIC'",
         "START_TIME": f"'{f(start)}'", "STOP_TIME": f"'{f(stop)}'", "STEP_SIZE": "'1 min'", "QUANTITIES": "'4'",
         "CSV_FORMAT": "'YES'", "ANG_FORMAT": "'DEG'", "TIME_TYPE": "'UT'", "TIME_DIGITS": "'MINUTES'"}
    for _ in range(4):
        try:
            text = urllib.request.urlopen(API + "?" + urllib.parse.urlencode(q), timeout=120).read().decode()
            rows = text.split("$$SOE")[1].split("$$EOE")[0].strip().splitlines()
            break
        except Exception as e:  # сеть или лимит Horizons
            print("повтор", d, e, file=sys.stderr)
            time.sleep(3)
    else:
        sys.exit("Horizons не ответил")
    az, el = [], []
    for line in rows:
        c = [x.strip() for x in line.split(",")]
        az.append(float(c[3])); el.append(float(c[4]))
    assert len(el) == 1440 + 2 * MARGIN + 1, len(el)
    return az, el


def events(el):
    """Минуты шкалы суток (от местной полуночи) пересечений порогов; утро — до максимума высоты, вечер — после."""
    top = max(range(len(el)), key=lambda i: el[i])
    out = {}
    for name, (h, direction) in THRESHOLDS.items():
        found = None
        if direction == 1:
            for i in range(top - 1, -1, -1):
                if el[i] < h <= el[i + 1]:
                    found = i + (h - el[i]) / (el[i + 1] - el[i]) - MARGIN
                    break
        else:
            for i in range(top, len(el) - 1):
                if el[i] >= h > el[i + 1]:
                    found = i + (el[i] - h) / (el[i] - el[i + 1]) - MARGIN
                    break
        out[name] = None if found is None else round(found, 4)
    return out


def main():
    cases = []
    for name, (lat, lon, alt, tz_of) in PLACES.items():
        for d in DATES:
            tz = tz_of(d)
            az, el = fetch(lat, lon, alt, tz, d)
            samples = [dict(minute=m, az=az[m + MARGIN], el=el[m + MARGIN]) for m in range(0, 1441, 30)]
            cases.append(dict(place=name, date="%d-%02d-%02d" % d, latitude=lat, longitude=lon, heightKm=alt,
                              utcOffsetHours=tz, events=events(el), samples=samples))
            print(name, d, file=sys.stderr)
    json.dump(dict(source="JPL Horizons, Sun, Q4 (airless apparent), 1-min step, interpolated crossings",
                   thresholds={k: v[0] for k, v in THRESHOLDS.items()}, cases=cases), open(OUT, "w"), ensure_ascii=False)
    print("записано", OUT, len(cases))


if __name__ == "__main__":
    main()
