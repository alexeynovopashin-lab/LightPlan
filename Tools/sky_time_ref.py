#!/usr/bin/env python3
"""Эталон единого звёздного времени для слоёв AR (шаг 29.8в.21): JPL Horizons (DE441) + независимая математика.

Для 10 пар «место, момент UTC» (Томск, Москва, Тромсё, Кейптаун, Гонолулу × два момента) берёт у Horizons:
  * Солнце, Юпитер, Луна: видимые RA/Dec на равноденствие даты (Q2), азимут и высоту без рефракции (Q4), местное
    видимое звёздное время (Q7). Для Луны Q2 берётся геоцентрическим (CENTER 500@399), а азимут/высота Horizons —
    топоцентрические (`az_topo`, `el_topo`, место на уровне моря): с шага 29.8в.23 слой AR сверяется с ними, разница с
    геоцентрическими `az`, `el` и есть суточный параллакс (0,8–0,98°).
  * Сириус: Horizons звёзд не отдаёт, поэтому считается здесь — ICRS J2000 (SIMBAD, эпоха J2000) + собственное
    движение + прецессия IAU 2006 (углы Фукушимы–Вильямс) + четыре главных члена нутации; звёздное время — Horizons Q7.
    Аберрация (≤ 0,006°) не учтена.
Азимут/высота геоцентрических точек считаются тут же (`az_geo`, `el_geo`) по Q2 и Q7 — это и есть то, что обязано
дать приложение. Проверка собственной математики: для Солнца и Юпитера `az_geo`/`el_geo` должны лечь на Q4 Horizons
(печатается в конце).
Пишет `Fixtures/sky_time_horizons.json`; его читает `SkyTimeTests`. Сеть нужна только здесь.

    python3 Tools/sky_time_ref.py
"""
import datetime, json, math, os, sys, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Fixtures", "sky_time_horizons.json")
API = "https://ssd.jpl.nasa.gov/api/horizons.api"

PLACES = {
    "tomsk": (56.4977, 84.9744, 0.1), "moscow": (55.7558, 37.6173, 0.15), "tromso": (69.6492, 18.9553, 0.0),
    "capetown": (-33.9249, 18.4241, 0.0), "honolulu": (21.3069, -157.8583, 0.0),
}
# Два момента на место: разные годы и времена суток, чтобы тела оказывались и над горизонтом, и под ним.
CASES = [
    ("tomsk", (2026, 10, 19, 16, 0)), ("tomsk", (2029, 3, 7, 1, 30)),
    ("moscow", (2026, 6, 21, 2, 40)), ("moscow", (2028, 12, 14, 14, 20)),
    ("tromso", (2027, 1, 30, 11, 0)), ("tromso", (2030, 8, 25, 22, 10)),
    ("capetown", (2026, 12, 21, 17, 30)), ("capetown", (2028, 6, 9, 6, 15)),
    ("honolulu", (2026, 3, 20, 5, 0)), ("honolulu", (2030, 10, 2, 10, 45)),
]
BODIES = {"sun": "10", "moon": "301", "jupiter": "599"}
# Сириус, ICRS, эпоха J2000 (SIMBAD): RA, Dec градусы; собственное движение мсд/год (RA* = RA·cos Dec); параллакс не нужен.
SIRIUS = dict(ra=101.28715533, dec=-16.71611586, pm_ra=-546.01, pm_dec=-1223.07)


def julian(m):
    t = datetime.datetime(*m, tzinfo=datetime.timezone.utc)
    return 2440587.5 + t.timestamp() / 86400


def query(cmd, jd, place, geocentric):
    lat, lon, alt = PLACES[place]
    q = {"format": "text", "COMMAND": f"'{cmd}'", "OBJ_DATA": "'NO'", "MAKE_EPHEM": "'YES'", "EPHEM_TYPE": "'OBSERVER'",
         "CENTER": "'500@399'" if geocentric else "'coord@399'", "TLIST": f"'{jd:.6f}'", "QUANTITIES": "'2,4,7'",
         "CSV_FORMAT": "'YES'", "ANG_FORMAT": "'DEG'"}
    if not geocentric:
        q["SITE_COORD"] = f"'{lon},{lat},{alt}'"
        q["COORD_TYPE"] = "'GEODETIC'"
    text = urllib.request.urlopen(API + "?" + urllib.parse.urlencode(q), timeout=60).read().decode()
    row = [x.strip() for x in text.split("$$SOE")[1].split("$$EOE")[0].strip().splitlines()[0].split(",")]
    # дата, 2 флага, RA, Dec, Az, El, LAST
    def num(x):
        try:
            return float(x)
        except ValueError:   # геоцентр: «n.a.» в азимуте, высоте и звёздном времени
            return None
    return dict(ra=float(row[3]), dec=float(row[4]), az=num(row[5]), el=num(row[6]), last=num(row[7]))


def az_el(ra, dec, last_h, lat):
    """Геометрические азимут (от севера по часовой) и высота по RA/Dec на равноденствие даты и звёздному времени."""
    h = math.radians(last_h * 15 - ra)
    phi, d = math.radians(lat), math.radians(dec)
    alt = math.asin(math.sin(phi) * math.sin(d) + math.cos(phi) * math.cos(d) * math.cos(h))
    az = math.atan2(math.sin(h), math.cos(h) * math.sin(phi) - math.tan(d) * math.cos(phi))
    return (math.degrees(az) + 180) % 360, math.degrees(alt)


# --- Сириус: ICRS J2000 -> видимое на дату ------------------------------------------------------------------------
AS = math.pi / 648000  # угловая секунда в радианах


def rot1(a): c, s = math.cos(a), math.sin(a); return [[1, 0, 0], [0, c, s], [0, -s, c]]
def rot3(a): c, s = math.cos(a), math.sin(a); return [[c, s, 0], [-s, c, 0], [0, 0, 1]]
def mul(a, b): return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
def apply(m, v): return [sum(m[i][k] * v[k] for k in range(3)) for i in range(3)]


def poly(c, t): return sum(k * t ** i for i, k in enumerate(c))


def sirius_apparent(jd):
    """RA/Dec (градусы) Сириуса на истинное равноденствие даты: PM + прецессия IAU 2006 + нутация (4 члена)."""
    t = (jd - 2451545.0) / 36525
    yrs = (jd - 2451545.0) / 365.25
    ra0, dec0 = SIRIUS["ra"], SIRIUS["dec"]
    ra = ra0 + SIRIUS["pm_ra"] / 1000 / 3600 / math.cos(math.radians(dec0)) * yrs
    dec = dec0 + SIRIUS["pm_dec"] / 1000 / 3600 * yrs
    v = [math.cos(math.radians(dec)) * math.cos(math.radians(ra)), math.cos(math.radians(dec)) * math.sin(math.radians(ra)),
         math.sin(math.radians(dec))]
    gam = poly([-0.052928, 10.556378, 0.4932044, -0.00031238, -0.000002788, 0.0000000260], t) * AS
    phi = poly([84381.412819, -46.811016, 0.0511268, 0.00053289, -0.000000440, -0.0000000176], t) * AS
    psi = poly([-0.041775, 5038.481484, 1.5584175, -0.00018522, -0.000026452, -0.0000000148], t) * AS
    eps = poly([84381.406, -46.836769, -0.0001831, 0.00200340, -0.000000576, -0.0000000434], t) * AS
    p = mul(rot1(-eps), mul(rot3(-psi), mul(rot1(phi), rot3(-gam))))
    # Нутация: главные члены IAU 1980 (аргументы в градусах).
    om = math.radians(125.04452 - 1934.136261 * t)
    l = math.radians(280.4665 + 36000.7698 * t)
    lm = math.radians(218.3165 + 481267.8813 * t)
    dpsi = (-17.20 * math.sin(om) - 1.32 * math.sin(2 * l) - 0.23 * math.sin(2 * lm) + 0.21 * math.sin(2 * om)) * AS
    deps = (9.20 * math.cos(om) + 0.57 * math.cos(2 * l) + 0.10 * math.cos(2 * lm) - 0.09 * math.cos(2 * om)) * AS
    n = mul(rot1(-(eps + deps)), mul(rot3(-dpsi), rot1(eps)))
    x = apply(mul(n, p), v)
    return math.degrees(math.atan2(x[1], x[0])) % 360, math.degrees(math.asin(x[2]))


def main():
    cases, worst = [], 0.0
    for place, m in CASES:
        jd = julian(m)
        lat, lon, _ = PLACES[place]
        row = {"place": place, "latitude": lat, "longitude": lon, "utc": list(m), "jd": jd, "bodies": {}}
        last = None
        for name, cmd in BODIES.items():
            topo = query(cmd, jd, place, False)
            last = topo["last"]
            geo = query(cmd, jd, place, True) if name == "moon" else topo
            az, el = az_el(geo["ra"], geo["dec"], last, lat)
            b = {"ra": geo["ra"], "dec": geo["dec"], "az_topo": topo["az"], "el_topo": topo["el"], "az": az, "el": el}
            if name != "moon":   # проверка своей математики: геоцентрический расчёт против топоцентрического Q4
                dz = abs((az - topo["az"] + 180) % 360 - 180) * math.cos(math.radians(el))
                worst = max(worst, dz, abs(el - topo["el"]))
            row["bodies"][name] = b
        ra, dec = sirius_apparent(jd)
        az, el = az_el(ra, dec, last, lat)
        row["bodies"]["sirius"] = {"ra": ra, "dec": dec, "az": az, "el": el}
        row["last_hours"] = last
        cases.append(row)
        print(place, m, {k: (round(v["az"], 3), round(v["el"], 3)) for k, v in row["bodies"].items()})
    print(f"математика сверки против Q4 Horizons (Солнце, Юпитер), худшее расхождение: {worst:.4f}°")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump({"source": "JPL Horizons API (DE441) + Tools/sky_time_ref.py", "sirius_icrs_j2000": SIRIUS, "cases": cases}, f,
                  indent=1)
    print("записано", OUT)


if __name__ == "__main__":
    sys.exit(main())
