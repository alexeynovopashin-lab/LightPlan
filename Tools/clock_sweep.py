#!/usr/bin/env python3
"""Мины дат в тестах: полный набор на подставных «сейчас» (аудит часов, 24.10.2026). Только stdlib.

Тест «Запланировать съёмку» покраснел 24.10 на каждом коммите: в нём был вписан день 24.10.2026, а «сегодня»
приложения шло от настоящих часов (по Москве — столица языка). Такой тест краснеет ровно в один день, поэтому
его не ловит ни один прогон до этого дня. Здесь часы процесса тестов сдвигаются (Tools/clock_sweep/fakeclock.c,
DYLD_INSERT_LIBRARIES в процесс тестов симулятора), и набор гоняется на ряде «сейчас»:

  python3 Tools/clock_sweep.py                 полный набор: настоящие часы + 16 моментов (полночь МСК и Томска,
                                               конец месяца и года, 2027–2031), ~45 мин
  python3 Tools/clock_sweep.py --targeted      каждая будущая дата, вписанная в тесты: файлы с ней на шести
                                               моментах вокруг неё (накануне, 23:30 и 02:30 МСК, полдень, назавтра)
  python3 Tools/clock_sweep.py --at 2026-10-24T12:00:00+03:00 [--only LightPlanUITests/LightPlanShootButtonTests]
  python3 Tools/clock_sweep.py --selftest      проверка прибора: сдвиг часов виден в Date() процесса Swift на Mac

Тест, красный на одних моментах и зелёный на других, перепроверяется в одиночку на обоих; повторилось — мина
(код 1), нет — шаткий, не дата. Симулятор по умолчанию — `LP <ветка>` (node Tools/sim.js); сборка — в /tmp/cc-clock-sweep.
"""
import argparse, collections, datetime, glob, json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = "/tmp/cc-clock-sweep"
C_SRC = os.path.join(ROOT, "Tools", "clock_sweep", "fakeclock.c")
# Полночь по Москве (столица языка ru) и по Томску/Барнаулу (+7, пояс Мака и симулятора), конец месяца и года,
# високосный день, далёкое будущее — для тестов, сравнивающих «сегодня» с прошлым или будущим днём.
BROAD = ["2026-10-24T23:30:00+03:00", "2026-10-25T02:30:00+03:00", "2026-10-26T05:00:00+03:00",
         "2026-10-26T19:30:00+03:00", "2026-10-31T23:50:00+03:00", "2026-11-01T00:30:00+03:00",
         "2026-11-15T12:00:00+03:00", "2026-12-01T12:00:00+03:00", "2026-12-31T19:30:00+03:00",
         "2026-12-31T23:50:00+03:00", "2027-01-01T00:30:00+03:00", "2027-03-01T12:00:00+03:00",
         "2027-07-15T12:00:00+03:00", "2028-02-29T12:00:00+03:00", "2031-06-01T12:00:00+03:00"]
DATE_PATTERNS = [re.compile(r"CivilDate\(year:\s*(\d{4}),\s*month:\s*(\d+),\s*day:\s*(\d+)"),
                 re.compile(r"(?<!\d)(20\d\d)-(\d\d)-(\d\d)(?!\d)"),
                 re.compile(r"DateComponents\([^)]*year:\s*(\d{4}),\s*month:\s*(\d+),\s*day:\s*(\d+)")]


def sh(*argv, check=True, env=None, out=None):
    r = subprocess.run(argv, capture_output=out is None, stdout=out, stderr=subprocess.STDOUT if out else None,
                       text=True, env=env)
    if check and r.returncode != 0:
        raise SystemExit(f"{' '.join(argv)}\n{r.stdout or ''}{r.stderr or ''}")
    return (r.stdout or "").strip(), r.returncode


def device(name):
    if name and re.fullmatch(r"[0-9A-F-]{36}", name):
        return name
    if name:
        for line in sh("xcrun", "simctl", "list", "devices", "available")[0].splitlines():
            if f"{name} (" in line:
                return re.search(r"\(([0-9A-F-]{36})\)", line).group(1)
        raise SystemExit(f"нет симулятора {name}")
    return sh("node", os.path.join(ROOT, "Tools", "sim.js"))[0].splitlines()[-1].split("·")[-1].strip()


def build(udid, reuse):
    os.makedirs(WORK, exist_ok=True)
    sdk = sh("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path")[0]
    lib = os.path.join(WORK, "fakeclock_sim.dylib")
    sh("xcrun", "clang", "-dynamiclib", "-target", "arm64-apple-ios17.0-simulator", "-isysroot", sdk, "-o", lib, C_SRC)
    runs = glob.glob(os.path.join(WORK, "dd", "Build", "Products", "*.xctestrun"))
    if not (reuse and runs):
        log = os.path.join(WORK, "build.log")
        with open(log, "w") as f:
            _, code = sh("xcodebuild", "build-for-testing", "-project", "LightPlan.xcodeproj", "-scheme", "LightPlan-iOS",
                         "-destination", f"platform=iOS Simulator,id={udid}", "-derivedDataPath", os.path.join(WORK, "dd"),
                         check=False, out=f)
        if code != 0:
            raise SystemExit(f"сборка тестов не прошла, журнал {log}")
        runs = glob.glob(os.path.join(WORK, "dd", "Build", "Products", "*.xctestrun"))
    return lib, runs[0]


def results(bundle):
    raw = sh("xcrun", "xcresulttool", "get", "test-results", "tests", "--path", bundle, check=False)[0]
    try:
        nodes = json.loads(raw).get("testNodes", [])
    except json.JSONDecodeError:
        return {}
    out = {}

    def walk(n, path):
        kind, name = n.get("nodeType"), n.get("name")
        if kind == "Test Case":
            out["/".join(path + [name])] = n.get("result")
        for c in n.get("children", []):
            walk(c, path + [name] if kind in ("Test Suite", "Unit test bundle") else path)
    for n in nodes:
        walk(n, [])
    return out


def run(lib, xctestrun, udid, iso, only):
    """Набор (или его часть) на «сейчас» = iso (None — настоящие часы): {тест: Passed|Failed|…}."""
    env = dict(os.environ)
    if iso:
        env["TEST_RUNNER_DYLD_INSERT_LIBRARIES"] = lib
        env["TEST_RUNNER_LPFAKE_NOW"] = str(datetime.datetime.fromisoformat(iso).timestamp())
    with tempfile.TemporaryDirectory(dir=WORK) as tmp:
        bundle = os.path.join(tmp, "r.xcresult")
        with open(os.path.join(WORK, "last-run.log"), "w") as f:
            sh("xcodebuild", "test-without-building", "-xctestrun", xctestrun,
               "-destination", f"platform=iOS Simulator,id={udid}", "-resultBundlePath", bundle,
               "-collect-test-diagnostics", "never", *[f"-only-testing:{o}" for o in only],
               check=False, env=env, out=f)
        return results(bundle)


def plan():
    """Будущие даты, вписанные в тесты: {дата: [Пакет/Набор, …]} (набор = struct/class файла, известный прогону)."""
    today = datetime.date.today()
    by = collections.defaultdict(set)
    for f in sorted(glob.glob(os.path.join(ROOT, "Packages", "*", "Tests", "*", "**", "*.swift"), recursive=True)):
        s = open(f, encoding="utf-8").read()
        bundle = f.split(os.sep + "Tests" + os.sep)[1].split(os.sep)[0]
        # Наборы называются «…Tests» (все 268 на 24.10); тест вне набора — по имени функции.
        names = {f"{bundle}/{n}" for n in re.findall(r"(?:struct|class)\s+(\w+Tests)\b", s)} \
            or {f"{bundle}/{n}()" for n in re.findall(r"@Test[^\n]*\n?\s*func\s+(\w+)\(\)", s)}
        for p in DATE_PATTERNS:
            for m in p.finditer(s):
                try:
                    d = datetime.date(int(m[1]), int(m[2]), int(m[3]))
                except ValueError:
                    continue
                if today <= d <= today + datetime.timedelta(days=6 * 366):
                    by[d] |= names
    return {d: sorted(v) for d, v in sorted(by.items()) if v}


def around(d):
    a, b = d - datetime.timedelta(days=1), d + datetime.timedelta(days=1)
    return [f"{a}T12:00:00+03:00", f"{a}T23:30:00+03:00", f"{d}T02:30:00+03:00", f"{d}T12:00:00+03:00",
            f"{d}T23:30:00+03:00", f"{b}T12:00:00+03:00"]


def selftest():
    """Сдвиг виден в Date() процесса Swift (Mac, тот же исходник) и пропадает без LPFAKE_NOW."""
    with tempfile.TemporaryDirectory() as tmp:
        lib, probe = os.path.join(tmp, "f.dylib"), os.path.join(tmp, "probe")
        sh("xcrun", "clang", "-dynamiclib", "-o", lib, C_SRC)
        src = os.path.join(tmp, "p.swift")
        open(src, "w").write("import Foundation\nprint(Date().timeIntervalSince1970, Date.now.timeIntervalSince1970)\n")
        sh("xcrun", "swiftc", src, "-o", probe)
        want = datetime.datetime.fromisoformat("2026-10-24T00:01:00+03:00").timestamp()
        env = dict(os.environ, DYLD_INSERT_LIBRARIES=lib, LPFAKE_NOW=str(want))
        fake = [float(x) for x in sh(probe, env=env)[0].split()]
        real = [float(x) for x in sh(probe, env=dict(os.environ, DYLD_INSERT_LIBRARIES=lib))[0].split()]
        now = datetime.datetime.now().timestamp()
        ok = all(abs(x - want) < 5 for x in fake) and all(abs(x - now) < 5 for x in real)
        print(f"подставные: {fake} (ждём {want:.0f}); без LPFAKE_NOW: {real} (сейчас {now:.0f}) — {'да' if ok else 'НЕТ'}")
        return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--targeted", action="store_true")
    ap.add_argument("--at", nargs="+", metavar="ISO")
    ap.add_argument("--only", nargs="+", default=[], metavar="Пакет/Набор")
    ap.add_argument("--device")
    ap.add_argument("--reuse", action="store_true", help="не пересобирать, если в /tmp/cc-clock-sweep уже есть сборка")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    udid = device(a.device)
    subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
    lib, xctestrun = build(udid, a.reuse)
    jobs = [(iso, a.only) for iso in a.at] if a.at else \
        [(iso, s) for d, s in plan().items() for iso in around(d)] if a.targeted else [(iso, a.only) for iso in BROAD]
    seen = collections.defaultdict(dict)       # тест → {момент: результат}
    for iso, only in [(None, a.only)] + jobs:
        r = run(lib, xctestrun, udid, iso, only)
        red = sorted(t for t, v in r.items() if v == "Failed")
        print(f"{iso or 'настоящие часы':26} {len(r) - len(red):5} зелёных {len(red):3} красных"
              + "".join(f"\n    ✘ {t}" for t in red), flush=True)
        if not r:
            print(f"    ни одного теста — журнал {WORK}/last-run.log")
        for t, v in r.items():
            seen[t][iso] = v
    mines = []
    for t, by in seen.items():
        reds = [m for m, v in by.items() if v == "Failed"]
        greens = [m for m, v in by.items() if v == "Passed"]
        if not (reds and greens):
            continue
        only = ["/".join(t.split("/")[:2])]
        again_red = run(lib, xctestrun, udid, reds[0], only).get(t) == "Failed"
        again_green = run(lib, xctestrun, udid, greens[0], only).get(t) == "Passed"
        verdict = "МИНА ДАТЫ" if again_red and again_green else "шаткий, не дата"
        print(f"{verdict}: {t}\n    красный: {', '.join(m or 'настоящие часы' for m in reds)}")
        if again_red and again_green:
            mines.append(t)
    print(f"итог: мин {len(mines)}")
    return 1 if mines else 0


if __name__ == "__main__":
    sys.exit(main())
