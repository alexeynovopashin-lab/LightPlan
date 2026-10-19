#!/usr/bin/env python3
"""Эталон планет для слоя AR (шаг 29.8в.15): JPL Horizons (https://ssd.jpl.nasa.gov/api/horizons.api, эфемериды DE441).

Для 8 моментов 2024–2030 и пяти планет берёт у Horizons:
  * геоцентрические видимые RA/Dec на равноденствие даты (Q2, «a-app») — то, что считает `PlanetEphemeris`;
  * видимую величину (Q9, APmag) и удаление от Солнца (Q23, S-O-T);
  * азимут и высоту для места наблюдателя без рефракции (Q4) — то, что на экране даёт `Sky.horizontal`.
Пишет `Fixtures/planets_horizons.json`; его читает `PlanetEphemerisTests`. Сеть нужна только здесь, тесты работают без неё.

    python3 Tools/planets_ref.py            # пересобрать
"""
import datetime, json, os, sys, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Fixtures", "planets_horizons.json")
API = "https://ssd.jpl.nasa.gov/api/horizons.api"

# Томск, как во всех сверках AR (широта, долгота — градусы; высота над морем 0,1 км).
LAT, LON, ALT_KM = 56.4977, 84.9744, 0.1

# Восемь моментов UTC: разные годы 2024–2030 и времена года, не только текущий.
MOMENTS = [
    (2024, 3, 20, 21, 0), (2025, 7, 11, 3, 0), (2026, 10, 19, 16, 0), (2027, 1, 30, 11, 30),
    (2028, 5, 14, 22, 15), (2029, 9, 2, 5, 45), (2030, 2, 25, 13, 20), (2030, 12, 7, 0, 0),
]
# Густая сетка для проверки блеска и положения: 60 моментов через 42 суток с 2024-01-01 (почти семь лет, около
# четырёх оборотов Венеры по фазам), только геоцентрические числа.
DENSE_START, DENSE_STEP, DENSE_COUNT = (2024, 1, 1, 0, 0), 42, 60
PLANETS = {"mercury": "199", "venus": "299", "mars": "499", "jupiter": "599", "saturn": "699"}


def julian(m):
    t = datetime.datetime(*m, tzinfo=datetime.timezone.utc)
    return 2440587.5 + t.timestamp() / 86400


def query(cmd, jds, site):
    q = {
        "format": "text", "COMMAND": f"'{cmd}'", "OBJ_DATA": "'NO'", "MAKE_EPHEM": "'YES'", "EPHEM_TYPE": "'OBSERVER'",
        "CENTER": "'coord@399'" if site else "'500@399'",
        "TLIST": "'" + ",".join(f"{j:.6f}" for j in jds) + "'",
        "QUANTITIES": "'2,4,9,23'", "CSV_FORMAT": "'YES'", "ANG_FORMAT": "'DEG'", "REF_SYSTEM": "'ICRF'",
    }
    if site:
        q["SITE_COORD"] = f"'{LON},{LAT},{ALT_KM}'"
        q["COORD_TYPE"] = "'GEODETIC'"
    url = API + "?" + urllib.parse.urlencode(q)
    text = urllib.request.urlopen(url, timeout=60).read().decode()
    body = text.split("$$SOE")[1].split("$$EOE")[0].strip().splitlines()
    rows = []
    for line in body:
        c = [x.strip() for x in line.split(",")]
        # дата, 2 флага, RA, Dec, Az, El, APmag, S-brt, S-O-T
        rows.append({"ra": c[3], "dec": c[4], "az": c[5], "el": c[6], "mag": c[7], "elong": c[9]})
    if len(rows) != len(jds):
        sys.exit(f"{cmd}: ждали {len(jds)} строк, пришло {len(rows)}")
    return rows


def main():
    jds = [julian(m) for m in MOMENTS]
    out = {"source": "JPL Horizons API 1.2 (DE441), ssd.jpl.nasa.gov; Q2 a-app RA/Dec на равноденствие даты, Q4 Az/El без рефракции, Q9 APmag, Q23 S-O-T",
           "place": {"latitude": LAT, "longitude": LON},
           "moments": [{"utc": "%04d-%02d-%02dT%02d:%02dZ" % m, "jd": j} for m, j in zip(MOMENTS, jds)],
           "planets": {}}
    for name, cmd in PLANETS.items():
        geo, top = query(cmd, jds, False), query(cmd, jds, True)
        rows = []
        for g, t in zip(geo, top):
            rows.append({"ra": float(g["ra"]), "dec": float(g["dec"]), "mag": float(g["mag"]), "elong": float(g["elong"]),
                         "az": float(t["az"]), "el": float(t["el"])})
        out["planets"][name] = rows
    dense_jds = [julian(DENSE_START) + i * DENSE_STEP for i in range(DENSE_COUNT)]
    out["dense"] = {"jds": dense_jds, "planets": {}}
    for name, cmd in PLANETS.items():
        rows = query(cmd, dense_jds, False)
        out["dense"]["planets"][name] = [{"ra": float(g["ra"]), "dec": float(g["dec"]), "mag": float(g["mag"]),
                                          "elong": float(g["elong"])} for g in rows]
    with open(OUT, "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("записано", OUT)


if __name__ == "__main__":
    main()
