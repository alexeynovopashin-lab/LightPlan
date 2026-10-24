#!/usr/bin/env python3
"""Клиенты в Контактах iPhone на настоящей книге симулятора (шаг К7). Только stdlib, красный код при расхождении.

Приложение (Debug, обычный ид `Novopashin.LightPlan` — сборка симулятора) само проходит сценарий `-LPContactsProbe <файл>`
(App/AppModel+ContactsProbe.swift): заводит пять клиентов и «твой» контакт «Нина Своя» вторым CNContactStore, открывает
«Клиенты», правит клиента, пересохраняет, отвечает «Да» на прошлых, «руками» удаляет свой контакт, «Убрать всё», — и после
каждого шага пишет, что лежит в книге на самом деле. Здесь — драйвер: ставит приложение, выдаёт право
`simctl privacy grant contacts`, запускает, разбирает файл и проверяет по шагам. Подставной книги нет: это Contacts.

  python3 Tools/contacts_sim.py --app <путь к LightPlan.app> [--device <имя или udid>] [--out <файл>]
  python3 Tools/contacts_sim.py --selftest        проверка проверяющего: подпорченный журнал должен стать красным

Симулятор по умолчанию — `LP <ветка>` (node Tools/sim.js). Книга симулятора — не личные данные; на телефоне не запускать.
"""
import argparse, copy, json, os, re, subprocess, sys, tempfile, time

BUNDLE = "Novopashin.LightPlan"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROBE = {"Ольга Смирнова", "Ольга Петрова", "Анна Петрова", "Иван Петров", "Мария Иванова", "Сергей Прошлый", "Нина", "Петя"}


def sh(*argv, check=True):
    r = subprocess.run(argv, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise SystemExit(f"{' '.join(argv)}\n{r.stdout}{r.stderr}")
    return r.stdout.strip()


def device(name):
    if name and re.fullmatch(r"[0-9A-F-]{36}", name):
        return name
    if name:
        for line in sh("xcrun", "simctl", "list", "devices", "available").splitlines():
            if f"{name} (" in line:
                return re.search(r"\(([0-9A-F-]{36})\)", line).group(1)
        raise SystemExit(f"нет симулятора {name}")
    return sh("node", os.path.join(ROOT, "Tools", "sim.js")).split("·")[-1].strip()


def stages(path):
    return [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]


def probe_rows(st):
    """Контакты сценария (имя из списка) и «твой» — по имени."""
    return [r for r in st["rows"] if r["name"] in PROBE or r["name"] == "Нина Своя"]


def by_name(st, name):
    return [r for r in st["rows"] if r["name"] == name]


def digits(s):
    return re.sub(r"\D", "", s)


def check(log):
    out = []
    s = {x["stage"]: x for x in log}

    def ok(name, good, detail=""):
        out.append((name, bool(good), detail))

    need = ["start", "opened", "edited", "resaved", "past-yes", "gone", "removed", "done"]
    missing = [n for n in need if n not in s]
    ok("все шаги в журнале", not missing, f"нет {missing}")
    if missing:
        return out
    st, op, ed, rs, py, gn, rm = (s[n] for n in need[:7])
    ok("сборка симулятора пишет (обычный ид), право полное", op["writes"] and op["auth"] == "full" and op["on"],
       f"writes={op['writes']} auth={op['auth']} on={op['on']}")
    ok("до открытия «Клиентов» своих контактов нет", not any(r["name"] in PROBE for r in st["rows"]),
       [r["name"] for r in st["rows"] if r["name"] in PROBE])
    hand = by_name(op, "Нина Своя")
    ok("«твой» контакт на месте до прохода", len(by_name(st, "Нина Своя")) == 1, len(by_name(st, "Нина Своя")))
    # Проход: по контакту на человека с номером; ребёнок без номера, «твой» номер и прошлый клиент — нет.
    names = sorted(r["name"] for r in op["rows"] if r["name"] in PROBE)
    ok("по контакту на человека с номером (Ольга, Анна, Иван, Мария)",
       names == sorted(["Ольга Смирнова", "Анна Петрова", "Иван Петров", "Мария Иванова"]), names)
    ok("ребёнок без номера не записан", not by_name(op, "Петя"))
    ok("номер «твоего» контакта (8 (913)… = +7 913…) не продублирован", not by_name(op, "Нина"),
       [r["phones"] for r in by_name(op, "Нина")])
    ok("«твой» контакт не изменён", hand == by_name(st, "Нина Своя"), hand)
    ok("прошлый клиент без «Да» не записан", not by_name(op, "Сергей Прошлый"))
    ok("вопрос о прошлых: 1 клиент", op["pastAsk"] == 1, op["pastAsk"])
    olga = by_name(op, "Ольга Смирнова")
    ok("номер записан международным, ДР и Telegram на месте",
       olga and olga[0]["phones"] == ["+79161234567"] and olga[0]["bd"] == "1990-10-25" and "Telegram:olga_s" in olga[0]["social"],
       olga)
    anna, ivan = by_name(op, "Анна Петрова"), by_name(op, "Иван Петров")
    ok("годовщина пары у обоих", anna and ivan and anna[0]["anniv"] == ["2025-6-14"] and ivan[0]["anniv"] == ["2025-6-14"],
       (anna, ivan))
    d = [c for c in op["clients"] if c["id"] == "probe-d"][0]["people"][0]
    ok("из «твоего» контакта прочитано недостающее: ДР и Telegram", d["bd"] == "1960-03-08" and "telegram:nina_own" in d["msg"], d)
    ok("связи записаны (4)", len(op["links"]) == 4, op["links"])
    # Правка.
    ep = by_name(ed, "Ольга Петрова")
    ok("правка имени и VK уехала в тот же контакт", ep and ep[0]["id"] == olga[0]["id"] and "VK:olga_p" in ep[0]["social"]
       and not by_name(ed, "Ольга Смирнова"), ep)
    ok("правка не завела новых контактов", len(probe_rows(ed)) == len(probe_rows(op)), len(probe_rows(ed)))
    ok("«твой» контакт после правки тот же", by_name(ed, "Нина Своя") == hand)
    ok("пересохранение без правки — книга та же", rs["rows"] == ed["rows"])
    # «Да».
    ok("после «Да» прошлый клиент записан", len(by_name(py, "Сергей Прошлый")) == 1, by_name(py, "Сергей Прошлый"))
    ok("после «Да» вопрос ушёл", py["pastAsk"] == -1, py["pastAsk"])
    # Удалён руками.
    ok("удалённый руками свой контакт не заведён снова", not by_name(gn, "Мария Иванова") and "probe-c#0" in gn["dropped"],
       (by_name(gn, "Мария Иванова"), gn["dropped"]))
    # «Убрать всё».
    left = sorted(r["name"] for r in probe_rows(rm))
    ok("«Убрать всё» убрало только записанное приложением", left == ["Нина Своя"], left)
    ok("«твой» контакт после «Убрать всё» тот же", by_name(rm, "Нина Своя") == hand)
    others_before = sorted(r["id"] for r in st["rows"] if r not in probe_rows(st))
    others_after = sorted(r["id"] for r in rm["rows"] if r not in probe_rows(rm))
    ok("чужие контакты книги не тронуты", others_before == others_after, (others_before, others_after))
    ok("«Убрать всё»: убрано 4 (Ольга, Анна, Иван, Сергей), тумблер выключен, связей нет",
       rm["removed"] == 4 and not rm["on"] and not rm["wanted"] and not rm["links"], (rm["removed"], rm["on"], rm["links"]))
    return out


def selftest():
    good = [
        {"stage": "start", "writes": True, "auth": "full", "on": True, "pastAsk": -1, "removed": -1, "links": {}, "dropped": [],
         "wanted": True, "clients": [], "rows": [{"id": "k", "name": "Kate Bell", "phones": [], "bd": "", "anniv": [], "social": []},
                                                 {"id": "h", "name": "Нина Своя", "phones": ["8 (913) 000-00-01"], "bd": "1960-3-8", "anniv": [], "social": ["Telegram:nina_own"]}]},
    ]
    def row(i, n, ph, bd="", an=(), so=()):
        return {"id": i, "name": n, "phones": [ph], "bd": bd, "anniv": list(an), "social": list(so)}
    base = good[0]["rows"]
    ap = [row("a", "Ольга Смирнова", "+79161234567", "1990-10-25", (), ["Telegram:olga_s"]),
          row("b", "Анна Петрова", "+79031112233", "", ["2025-6-14"]), row("i", "Иван Петров", "+79034445566", "", ["2025-6-14"]),
          row("c", "Мария Иванова", "+79132223344")]
    cl = [{"id": "probe-d", "people": [{"n": "Нина", "tel": "+7", "bd": "1960-03-08", "msg": ["telegram:nina_own"]}]}]
    links = {"probe-a#0": "a", "probe-b#0": "b", "probe-b#1": "i", "probe-c#0": "c"}
    op = dict(good[0], stage="opened", rows=base + ap, pastAsk=1, links=links, clients=cl)
    edr = [dict(ap[0], name="Ольга Петрова", social=["Telegram:olga_s", "VK:olga_p"])] + ap[1:]
    ed = dict(op, stage="edited", rows=base + edr, pastAsk=1)
    rs = dict(ed, stage="resaved")
    py = dict(ed, stage="past-yes", rows=ed["rows"] + [row("p", "Сергей Прошлый", "+79995556677")], pastAsk=-1)
    gn = dict(py, stage="gone", rows=[r for r in py["rows"] if r["id"] != "c"], dropped=["probe-c#0"])
    rm = dict(gn, stage="removed", rows=base, removed=4, on=False, wanted=False, links={})
    log = good + [op, ed, rs, py, gn, rm, dict(rm, stage="done")]
    bad = [r for r in check(log) if not r[1]]
    if bad:
        print("selftest: хороший журнал красный:", bad)
        return 1
    breakages = [
        ("op", lambda L: L[1]["rows"].append(row("x", "Нина", "+79130000001"))),       # дубль «твоего» номера
        ("op", lambda L: L[1]["rows"].append(row("y", "Сергей Прошлый", "+79995556677"))),  # прошлый без «Да»
        ("ed", lambda L: L[2]["rows"].append(row("z", "Ольга Петрова", "+79161234567"))),   # правка завела новый
        ("rm", lambda L: L[6]["rows"].append(row("a", "Ольга Петрова", "+79161234567"))),   # «Убрать всё» не убрало
        ("rm", lambda L: L[6].update(rows=[base[1]])),                                      # убрало чужой
        ("gn", lambda L: L[5]["rows"].append(ap[3])),                                         # удалённый руками вернулся
    ]
    for name, br in breakages:
        L = copy.deepcopy(log)
        br(L)
        if all(r[1] for r in check(L)):
            print(f"selftest: поломка {name} осталась зелёной")
            return 1
    if all(r[1] for r in check(log[:3])):
        print("selftest: неполный журнал зелёный")
        return 1
    print(f"selftest: ok (неполный журнал красный; хороший зелёный; {len(breakages)} поломок красные)")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app")
    ap.add_argument("--device")
    ap.add_argument("--out")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if not a.app:
        ap.error("нужен --app <путь к .app>")
    udid = device(a.device)
    sh("xcrun", "simctl", "boot", udid, check=False)
    sh("xcrun", "simctl", "bootstatus", udid, "-b", check=False)
    sh("xcrun", "simctl", "uninstall", udid, BUNDLE, check=False)
    sh("xcrun", "simctl", "privacy", udid, "reset", "contacts", BUNDLE, check=False)
    sh("xcrun", "simctl", "install", udid, a.app)
    sh("xcrun", "simctl", "privacy", udid, "grant", "contacts", BUNDLE)
    log = a.out or os.path.join(tempfile.mkdtemp(prefix="lp-contactsim-"), "contacts.jsonl")
    if os.path.exists(log):
        os.remove(log)
    sh("xcrun", "simctl", "launch", udid, BUNDLE, "-LPContactsProbe", log)
    t0 = time.time()
    while time.time() - t0 < 90:
        if os.path.exists(log) and '"stage":"done"' in open(log, encoding="utf-8").read():
            break
        time.sleep(1)
    sh("xcrun", "simctl", "terminate", udid, BUNDLE, check=False)
    if not os.path.exists(log):
        raise SystemExit("приложение не записало журнал")
    rows = check(stages(log))
    for name, good, detail in rows:
        print(("  да  " if good else "  НЕТ ") + name + ("" if good else f"   ← {detail}"))
    print(f"журнал: {log}")
    return 0 if all(r[1] for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
