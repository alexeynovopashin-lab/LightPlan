#!/usr/bin/env python3
"""Зеркало съёмок в Календаре на настоящем календаре симулятора (шаг 30.1–3). Только stdlib, красный код при расхождении.

Приложение (Debug) само проходит сценарий `-LPCalendarProbe <файл>` (App/AppModel+CalendarProbe.swift): включает
зеркало, правит записи, «руками» удаляет событие и календарь вторым EKEventStore, и после каждого шага пишет, что лежит
в базе календарей на самом деле. Здесь — драйвер: ставит приложение, выдаёт право `simctl privacy grant calendar`,
запускает, разбирает файл и проверяет по шагам. Подставного календаря нет: это настоящий EventKit.

  python3 Tools/calendar_sim.py --app <путь к LightPlan.app> [--device <имя или udid>] [--keep] [--out <файл>]
  python3 Tools/calendar_sim.py --selftest        проверка проверяющего: подпорченный журнал должен стать красным

Симулятор по умолчанию — `LP <ветка>` (node Tools/sim.js). Календарь `Light Plan` в нём перед прогоном чистится.
"""
import argparse, json, os, re, subprocess, sys, tempfile, time

BUNDLE = "Novopashin.LightPlan"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def sh(*argv, check=True):
    r = subprocess.run(argv, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise SystemExit(f"{' '.join(argv)}\n{r.stdout}{r.stderr}")
    return r.stdout.strip()


def device(name):
    if name and re.fullmatch(r"[0-9A-F-]{36}", name):
        return name
    out = sh("node", os.path.join(ROOT, "Tools", "sim.js")) if not name else None
    if name:
        for line in sh("xcrun", "simctl", "list", "devices", "available").splitlines():
            if f"{name} (" in line:
                return re.search(r"\(([0-9A-F-]{36})\)", line).group(1)
        raise SystemExit(f"нет симулятора {name}")
    return out.split("·")[-1].strip()


def lines(path):
    return [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]


def stages(path):
    return [d for d in lines(path) if "stage" in d]


def events(stage):
    return [r for r in stage["rows"] if "title" in r]


def calendars(stage):
    return [r for r in stage["rows"] if "calendar" in r]


def check(log):
    """Список (проверка, ок, подробность)."""
    out = []
    by = {s["stage"].split(" ")[0]: s for s in log}
    ask = {s["stage"]: s for s in log}

    def ok(name, cond, detail=""):
        out.append((name, bool(cond), detail))

    need = ["start", "on", "repeat", "deleted-by-hand", "reconciled", "moved", "trashed", "restored", "calendar-recreated", "reinstalled", "done"]
    ok("журнал полон", all(n in by for n in need), f"есть шаги: {[s['stage'] for s in log]}")
    if not all(n in by for n in need):
        return out
    ok("в начале нашего календаря нет", not calendars(by["start"]), str(calendars(by["start"])))
    on = by["on"]
    ok("включили: доступ полный и тумблер включён", on["auth"] == "allowed" and on["on"], f"auth={on['auth']} on={on['on']}")
    ok("календарь «Light Plan» заведён один", len(calendars(on)) == 1 and calendars(on)[0]["calendar"] == "Light Plan", str(calendars(on)))
    titles = sorted(e["title"] for e in events(on))
    ok("четыре записи — четыре события", titles == sorted(["Свадьба · Ирина", "Встреча · портрет · Олег", "Выходной", "Перелёт"]), str(titles))
    w = next((e for e in events(on) if e["title"] == "Свадьба · Ирина"), {})
    ok("свадьба: ссылка, место, координаты, «занят» (где календарь это умеет), без напоминаний и заметок",
       w.get("url") == "lightplan://shoot/probe-w" and w.get("location") == "Парк, ул. Ленина 5" and abs(w.get("lat", 0) - 56.4977) < 1e-3
       and (w.get("busy") or not calendars(on)[0].get("supportsBusy")) and w.get("alarms") == 0 and w.get("notes") == "", str(w))
    ok("свадьба: пояс места съёмки (оценка Томска +6 или +7), а не телефона", w.get("tzOffset") in (21600, 25200) and w.get("tz"), f"tz={w.get('tz')} off={w.get('tzOffset')}")
    f = next((e for e in events(on) if e["title"] == "Перелёт"), {})
    ok("перелёт: пояс вылета +7, четыре часа в пути", f.get("tzOffset") == 25200 and f.get("end") and
       (time.mktime(time.strptime(f["end"], "%Y-%m-%dT%H:%M:%SZ")) - time.mktime(time.strptime(f["start"], "%Y-%m-%dT%H:%M:%SZ"))) == 4 * 3600, str(f))
    o = next((e for e in events(on) if e["title"] == "Выходной"), {})
    ok("выходной на два дня — одно событие на весь день", o.get("allDay") is True, str(o))
    ok("повторные проходы не плодят события", sorted(e["title"] for e in events(by["repeat"])) == titles and len(calendars(by["repeat"])) == 1,
       str(len(events(by["repeat"]))))
    rr = by.get("repeat-report", {})
    ok("неизменные данные — проход ничего не пишет в календарь (на месте 4, создано/переписано/убрано 0)",
       rr.get("kept") == 4 and not (rr.get("created") or rr.get("updated") or rr.get("removed") or rr.get("failed")), str(rr))
    ok("удалили руками — события нет", "Свадьба · Ирина" not in [e["title"] for e in events(by["deleted-by-hand"])])
    ok("при возврате событие вернулось, дубля нет", sorted(e["title"] for e in events(by["reconciled"])) == titles)
    m = next((e for e in events(by["moved"]) if e["title"] == "Свадьба · Ирина"), {})
    ok("сдвинули на час — то же событие на час позже", m.get("start") and w.get("start") and
       time.mktime(time.strptime(m["start"], "%Y-%m-%dT%H:%M:%SZ")) - time.mktime(time.strptime(w["start"], "%Y-%m-%dT%H:%M:%SZ")) == 3600
       and len(events(by["moved"])) == 4, f"{w.get('start')} → {m.get('start')}")
    ok("корзина — события нет", "Свадьба · Ирина" not in [e["title"] for e in events(by["trashed"])] and len(events(by["trashed"])) == 3)
    ok("вернули из корзины — событие снова", len(events(by["restored"])) == 4)
    gone = next((s for k, s in ask.items() if k.startswith("calendar-deleted")), None)
    ok("календарь удалили руками — молча не заводим, спрашиваем", gone is not None and "ask=true" in gone["stage"] and not calendars(gone), gone and gone["stage"])
    rec = by["calendar-recreated"]
    ok("«да» — календарь и все события на месте", len(calendars(rec)) == 1 and sorted(e["title"] for e in events(rec)) == titles, str(len(events(rec))))
    re_ = by["reinstalled"]
    ok("переустановка: память стёрта — прежний календарь принят обратно, второго нет, дублей нет",
       len(calendars(re_)) == 1 and sorted(e["title"] for e in events(re_)) == titles, f"календарей {len(calendars(re_))}, событий {len(events(re_))}")
    return out


def selftest():
    good = [{"stage": "start", "auth": "allowed", "on": False, "source": "", "rows": []}]
    # Пустой и подпорченный журналы обязаны стать красными.
    bad = check(good)
    assert not all(c[1] for c in bad), "журнал без шагов прошёл проверку"
    print("selftest: ok (неполный журнал красный)")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app")
    ap.add_argument("--device")
    ap.add_argument("--out")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--bulk", type=int, default=0, help="после сценария: N съёмок разом, замер времени первого и повторного прохода")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if not a.app:
        ap.error("нужен --app <путь к .app>")
    udid = device(a.device)
    sh("xcrun", "simctl", "bootstatus", udid, "-b", check=False)
    sh("xcrun", "simctl", "boot", udid, check=False)
    sh("xcrun", "simctl", "bootstatus", udid, "-b", check=False)
    sh("xcrun", "simctl", "uninstall", udid, BUNDLE, check=False)
    sh("xcrun", "simctl", "privacy", udid, "reset", "calendar", BUNDLE, check=False)
    sh("xcrun", "simctl", "install", udid, a.app)
    sh("xcrun", "simctl", "privacy", udid, "grant", "calendar", BUNDLE)
    log = a.out or os.path.join(tempfile.mkdtemp(prefix="lp-calsim-"), "calendar.jsonl")
    if os.path.exists(log):
        os.remove(log)          # журнал прошлого прогона не должен сойти за свежий
    extra = ["-LPCalendarBulk", str(a.bulk)] if a.bulk else []
    sh("xcrun", "simctl", "launch", udid, BUNDLE, "-LPCalendarProbe", log, *extra)
    t0 = time.time()
    while time.time() - t0 < 90:
        text = open(log, encoding="utf-8").read() if os.path.exists(log) else ""
        if '"stage":"done"' in text and (not a.bulk or '"bulk"' in text):
            break
        time.sleep(1)
    if not a.keep:
        sh("xcrun", "simctl", "terminate", udid, BUNDLE, check=False)
    if not os.path.exists(log):
        raise SystemExit("приложение не записало журнал")
    rows = check(stages(log))
    for name, good, detail in rows:
        print(("  да  " if good else "  НЕТ ") + name + ("" if good else f"   ← {detail}"))
    for d in lines(log):
        if "bulk" in d:
            print(f"  объём: {d['bulk']} съёмок — первое включение {d['createdMs']} мс (создано {d['created']}), повторный проход {d['repeatMs']} мс (на месте {d['kept']})")
    print(f"журнал: {log}")
    return 0 if all(r[1] for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
