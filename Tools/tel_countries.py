#!/usr/bin/env python3
"""Все страны телефонной нумерации из данных Google libphonenumber (шаг 30ж.2).

Алексей 06.11: «Любой мобильный номер должен учитываться… проще добавить в память все коды всех стран».
Скачивает `resources/PhoneNumberMetadata.xml` КОНКРЕТНОГО ТЕГА (не ветки) и пишет
`Packages/LightPlanDomain/Sources/LightPlanDomain/Rules/TelCountries.generated.swift` — страны, которых нет
среди 27 строк веба (`TelCountry.web` в `TelFormat.swift`, их строки не трогаются). Исходный XML в репозиторий
не кладётся. Данные: © The Libphonenumber Authors, Apache License 2.0.

Что берётся у страны: код (`countryCode`), внутренний префикс (`nationalPrefix`), длины (мобильный ∪ городской,
`possibleLengths national`; больше двух разных — длиной не меряем, как DE и IT у веба, судим по образцу мобильного),
правило мобильного (`mobile/nationalNumberPattern`; где Google не отличает мобильный от городского, образцы
совпадают — номер принимается, как у США), вид записи (тот `numberFormat`, что Google берёт для примера мобильного;
международный вид, если он есть — в поле стоит часть после «+код»), пример (`mobile/exampleNumber`).

  python3 Tools/tel_countries.py                 скачать тег и записать
  python3 Tools/tel_countries.py --check         собрать и сравнить с лежащим (расхождение — код выхода 1)
  python3 Tools/tel_countries.py --xml <файл>    взять уже скачанный XML того же тега
  python3 Tools/tel_countries.py --diff27        расхождения Google с 27 строками веба (в отчёт, ничего не пишет)
"""
import re
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

TAG = "v9.0.42"  # релиз 2026-10-27
URL = f"https://raw.githubusercontent.com/google/libphonenumber/{TAG}/resources/PhoneNumberMetadata.xml"
ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / "Packages/LightPlanDomain/Sources/LightPlanDomain/Rules"
OUT = RULES / "TelCountries.generated.swift"
WEB = RULES / "TelFormat.swift"


def squash(s):
    return re.sub(r"\s+", "", s or "")


def lengths(desc):
    """`possibleLengths national="[6-8],10,12"` → {6, 7, 8, 10, 12}."""
    if desc is None:
        return set()
    pl = desc.find("possibleLengths")
    if pl is None or not pl.get("national"):
        return set()
    out = set()
    for part in pl.get("national").split(","):
        m = re.fullmatch(r"\[(\d+)-(\d+)\]", part)
        if m:
            out.update(range(int(m.group(1)), int(m.group(2)) + 1))
        else:
            out.add(int(part))
    return out


def pattern(desc):
    if desc is None:
        return None
    p = desc.find("nationalNumberPattern")
    return squash(p.text) if p is not None else None


def shape(formats, ex):
    """Вид записи примера: первый `numberFormat`, чьи `leadingDigits` (последний, самый точный) и образец сходятся."""
    for nf in formats:
        lds = nf.findall("leadingDigits")
        if lds and not re.match(squash(lds[-1].text), ex):
            continue
        m = re.fullmatch(nf.get("pattern"), ex)
        if not m:
            continue
        intl = nf.find("intlFormat")
        fmt = intl.text if intl is not None and intl.text != "NA" else nf.find("format").text
        return re.sub(r"\$(\d)", lambda g: "#" * len(m.group(int(g.group(1)))), fmt)
    return "#" * len(ex)


def countries(xml):
    terr = ET.parse(xml).getroot().find("territories").findall("territory")
    main_formats = {}
    for t in terr:
        if t.get("mainCountryForCode") == "true" or t.get("countryCode") not in main_formats:
            af = t.find("availableFormats")
            if af is not None:
                main_formats[t.get("countryCode")] = af.findall("numberFormat")
    out, skipped, shared = [], [], []
    for t in terr:
        iso, cc = t.get("id"), t.get("countryCode")
        mob, fix = t.find("mobile"), t.find("fixedLine")
        mp = pattern(mob)
        ex = mob.find("exampleNumber") if mob is not None else None
        if iso == "001" or not mp or mp == "NA" or ex is None:
            skipped.append(iso)
            continue
        ex = ex.text.strip()
        assert re.fullmatch(mp, ex), f"{iso}: пример {ex} не проходит своё правило"
        if pattern(fix) == mp:
            shared.append(iso)
        lens = lengths(mob) or lengths(t.find("generalDesc"))
        if pattern(fix) not in (None, "NA"):
            lens |= lengths(fix)
        af = t.find("availableFormats")
        formats = af.findall("numberFormat") if af is not None else main_formats.get(cc, [])
        out.append(dict(iso=iso, cc=cc, trunk=t.get("nationalPrefix") or "", lens=sorted(lens),
                        format=shape(formats, ex), mobile="^(?:" + mp + ")$", example=ex,
                        main=t.get("mainCountryForCode") == "true", fixed=pattern(fix)))
    return out, skipped, shared


def web_rows():
    rows = {}
    for m in re.finditer(r'\.init\(iso: "(\w\w)", cc: "(\d+)", trunk: "(\d*)", nsn: \[([\d, ]*)\], format: "([^"]*)", '
                         r'mobile: "((?:[^"\\]|\\.)*)", example: "(\d+)"\)', WEB.read_text()):
        iso, cc, trunk, nsn, fmt, mob, ex = m.groups()
        rows[iso] = dict(cc=cc, trunk=trunk, lens=[int(x) for x in nsn.replace(" ", "").split(",") if x],
                         format=fmt, mobile=mob.replace("\\\\", "\\"), example=ex)
    assert len(rows) == 27, f"строк веба {len(rows)}, ждали 27"
    return rows


def literal(p):
    hashes = "#"
    while '"' + hashes in p:
        hashes += "#"
    return f'{hashes}"{p}"{hashes}'


def swift(rows):
    lines = [
        "// Сгенерировано `python3 Tools/tel_countries.py` — руками не править.",
        f"// Источник: Google libphonenumber {TAG}, resources/PhoneNumberMetadata.xml",
        "// (© The Libphonenumber Authors, Apache License 2.0, https://www.apache.org/licenses/LICENSE-2.0).",
        "// Взяты код страны, внутренний префикс, длины, правило мобильного, вид записи и пример мобильного;",
        "// страны веба (`TelCountry.web`) здесь не повторяются.",
        "",
        "extension TelCountry {",
        f'    /// Тег данных Google, из которого собрана таблица.',
        f'    public static let googleTag = "{TAG}"',
        "",
        "    static let google: [TelCountry] = [",
    ]
    for r in rows:
        spread = len(r["lens"]) > 2
        nsn = "" if spread else ", ".join(map(str, r["lens"]))
        longest = f", longest: {max(r['lens'])}" if spread else ""
        lines.append(f'        .init(iso: "{r["iso"]}", cc: "{r["cc"]}", trunk: "{r["trunk"]}", nsn: [{nsn}]{longest}, '
                     f'format: "{r["format"]}", mobile: {literal(r["mobile"])}, example: "{r["example"]}"),')
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def diff27(goog, web):
    by = {r["iso"]: r for r in goog}
    out = []
    for iso, w in web.items():
        g = by[iso]
        notes = []
        for k in ("cc", "trunk", "format"):
            if w[k] != g[k]:
                notes.append(f"{k}: веб «{w[k]}», Google «{g[k]}»")
        if w["lens"] != g["lens"]:
            notes.append(f"длины: веб {w['lens'] or 'по образцу'}, Google {g['lens']}")
        if not re.fullmatch(g["mobile"], w["example"]):
            notes.append(f"пример веба {w['example']} Google мобильным не считает")
        if not re.fullmatch(w["mobile"], g["example"]):
            notes.append(f"мобильный пример Google {g['example']} веб не принимает")
        fx = g["fixed"]
        if fx and fx != "NA" and fx != g["mobile"][4:-2]:
            m = [n for n in [w["example"]] if re.fullmatch("^(?:" + fx + ")$", n)]
            if m:
                notes.append(f"пример веба {m[0]} у Google ещё и городской")
        out.append(f"{iso} +{w['cc']}: " + ("; ".join(notes) if notes else "совпадает"))
    return out


def main():
    args = sys.argv[1:]
    if "--xml" in args:
        xml = Path(args[args.index("--xml") + 1])
    else:
        xml = Path(tempfile.mkdtemp(prefix="tel-countries-")) / "PhoneNumberMetadata.xml"
        urllib.request.urlretrieve(URL, xml)
    goog, skipped, shared = countries(xml)
    web = web_rows()
    if "--diff27" in args:
        print("\n".join(diff27(goog, web)))
        return 0
    rows = sorted((r for r in goog if r["iso"] not in web), key=lambda r: (int(r["cc"]), not r["main"], r["iso"]))
    text = swift(rows)
    print(f"{TAG}: стран с мобильным {len(goog)}, новых {len(rows)} (+27 веба = {len(rows) + 27}); "
          f"без правила мобильного пропущено {len(skipped)}: {' '.join(skipped)}; "
          f"мобильный = городской у {len(shared)}: {' '.join(shared)}")
    if "--check" in args:
        same = OUT.exists() and OUT.read_text() == text
        print("совпадает с лежащим" if same else f"РАСХОДИТСЯ с {OUT.relative_to(ROOT)}")
        return 0 if same else 1
    OUT.write_text(text)
    print(f"записано {OUT.relative_to(ROOT)}, {len(text.encode())} байт")
    return 0


if __name__ == "__main__":
    sys.exit(main())
