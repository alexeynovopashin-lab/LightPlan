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

    need = ["start", "on", "repeat", "deleted-by-hand", "reconciled", "moved", "trashed", "restored", "calendar-recreated", "reinstalled",
            "hand-moved", "hand-moved-returned", "hand-renamed", "hand-block-moved", "hand-added", "hand-added-repeat", "hand-added-reinstalled", "hand-draft-deleted",
            "ghost-seed", "ghost-on", "ghost-unticked", "ghost-reticked", "ghost-changed", "ghost-off", "done"]
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
    ok("свадьба: ссылка, место, координаты, «занят» (где календарь это умеет), без напоминаний",
       w.get("url") == "lightplan://shoot/probe-w" and w.get("location") == "Парк, ул. Ленина 5" and abs(w.get("lat", 0) - 56.4977) < 1e-3
       and (w.get("busy") or not calendars(on)[0].get("supportsBusy")) and w.get("alarms") == 0, str(w))
    ok("свадьба: в заметках событий телефон клиента (международный вид) и заметки съёмки",
       w.get("notes") == WEDDING_NOTES, repr(w.get("notes")))
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
    out += check_reverse(by)
    out += check_ghosts(by)
    return out


WEDDING_NOTES = "Клиент: Ирина +7 916 123-45-67\n\nПриезжать за час"


def secs(iso):
    return time.mktime(time.strptime(iso, "%Y-%m-%dT%H:%M:%SZ"))


def record(stage, rid=None):
    rs = stage.get("sessions", [])
    return next((r for r in rs if r["id"] == rid), None) if rid else rs


def check_reverse(by):
    """Шаг 30.4: человек работает в Календаре — время и место возвращаются, название и заметки нет, событие рождает один черновик."""
    out = []

    def ok(name, cond, detail=""):
        out.append((name, bool(cond), detail))

    before = record(by["reinstalled"], "probe-w")
    ev = lambda st, title: next((e for e in events(st) if e["title"] == title), {})
    w0, w1 = ev(by["reinstalled"], "Свадьба · Ирина"), ev(by["hand-moved-returned"], "Свадьба · Ирина")
    r1 = record(by["hand-moved-returned"], "probe-w")
    ok("двигали событие в Календаре: съёмка в приложении сдвинулась на тот же час и сменила место",
       before and r1 and r1["start"] == before["start"] + 60 and r1["end"] == before["end"] + 60 and r1["place"] == "Набережная"
       and r1["day"] == before["day"], f"{before and (before['start'], before['end'])} → {r1 and (r1['start'], r1['end'], r1['place'])}")
    ok("двигали событие: метка правки (mt) записи стала свежей", r1 and before and r1["mt"] > before["mt"], f"{before and before['mt']} → {r1 and r1['mt']}")
    ok("двигали событие: оно осталось там, куда его поставил человек, место в нём — новое, дубля нет",
       w0.get("start") and w1.get("start") and secs(w1["start"]) - secs(w0["start"]) == 3600 and w1.get("location") == "Набережная"
       and len(events(by["hand-moved-returned"])) == len(events(by["reinstalled"])),
       f"{w0.get('start')} → {w1.get('start')} / {w1.get('location')}")
    r2 = record(by["hand-renamed"], "probe-w")
    w2 = ev(by["hand-renamed"], "Свадьба · Ирина")
    ok("переименовали событие и переписали заметки: в съёмку это не вернулось",
       r1 and r2 and all(r1[k] == r2[k] for k in ("start", "end", "contact", "notes", "genre", "place")), f"{r1} / {r2}")
    ok("…а событие вернулось к названию и заметкам, как у нас (к ним добавилась строка о сдвиге)", (w2.get("notes") or "").startswith(WEDDING_NOTES) and "время сдвинуто в календаре" in (w2.get("notes") or "") and not [e for e in events(by["hand-renamed"]) if e["title"] == "Чужое название"],
       f"{w2.get('notes')!r}")

    ok("двигали событие: в съёмке отметка «время сдвинуто» — было прежнее время, а не промежуточное",
       r1 and before and r1.get("moved") == [before["start"], before["end"]] and r1.get("movedDay") == "",
       f"{r1 and r1.get('moved')} vs {before and (before['start'], before['end'])}")
    ok("после переименования в Календаре отметка о сдвиге не пропала и не задвоилась", r2 and r2.get("moved") == r1.get("moved"), f"{r2 and r2.get('moved')}")

    bb = by["hand-block-moved"]
    off0 = next((b for b in by["hand-renamed"].get("blocks", []) if b["id"] == "probe-b"), None)
    off1 = next((b for b in bb.get("blocks", []) if b["id"] == "probe-b"), None)
    fl0 = next((b for b in by["hand-renamed"].get("blocks", []) if b["id"] == "probe-f"), None)
    fl1 = next((b for b in bb.get("blocks", []) if b["id"] == "probe-f"), None)
    ok("занятое время на весь день подвинули в Календаре: блок сдвинулся на сутки, число дней то же, отметка есть",
       off0 and off1 and off1["moved"] and off1["days"] == off0["days"] and off1["movedFrom"] == off0["from"] and off1["from"] != off0["from"] and off1["text"].startswith("Время сдвинуто в календаре"),
       f"{off0} → {off1}")
    ok("перелёт подвинули на час: старт блока на час позже, длительность та же, отметка есть",
       fl0 and fl1 and fl1["start"] == fl0["start"] + 60 and fl1["duration"] == fl0["duration"] and fl1["moved"], f"{fl0} → {fl1}")
    ok("после сдвигов блоков событий столько же, дублей нет", len(events(bb)) == len(events(by["hand-renamed"])), f"{len(events(bb))}")

    added = by["hand-added"]
    drafts = [r for r in record(added) if r["draft"]]
    d = drafts[0] if drafts else {}
    ok("событие, заведённое руками в «Light Plan», стало ровно одним черновиком съёмки", len(drafts) == 1 and d.get("from") == "Маша фотосессия"
       and d.get("genre") == "" and d.get("contact") == "", str(record(added)))
    ok("черновик: время, место и заметки взяты из события (название — первой строкой заметок)",
       d.get("place") == "Парк Горького" and d.get("notes") == "Маша фотосессия\nв парке", str(d))
    e = ev(added, "Маша фотосессия")
    ok("событие получило ссылку на черновик и сохранило своё название; новых событий нет (всего на одно больше)",
       e.get("url") == f"lightplan://shoot/{d.get('id')}" and len(events(added)) == len(events(by["hand-moved-returned"])) + 1, str(e))
    for name in ("hand-added-repeat", "hand-added-reinstalled", "hand-draft-deleted"):
        st = by[name]
        ds = [r for r in record(st) if r["draft"]]
        label = {"hand-added-repeat": "ещё два прохода", "hand-added-reinstalled": "«переустановка» (память стёрта)", "hand-draft-deleted": "событие черновика удалили руками"}[name]
        ok(f"{label}: черновик один, событий столько же, календарь один",
           len(ds) == 1 and ds[0]["id"] == d.get("id") and len(events(st)) == len(events(added)) and len(calendars(st)) == 1,
           f"черновиков {len(ds)}, событий {len(events(st))}, календарей {len(calendars(st))}")
    ok("событие черновика удалили руками: черновик остался, событие вернулось со ссылкой",
       ev(by["hand-draft-deleted"], "Маша фотосессия").get("url") == f"lightplan://shoot/{d.get('id')}", str(ev(by["hand-draft-deleted"], "Маша фотосессия")))
    return out


SEEDED = ["Матч", "Планёрка", "Каникулы", "Кружок", "Ночная смена", "Секция"]


def check_ghosts(by):
    """Шаг 30.5: чужие календари призраками. «Сын» и «Работа» заведены вторым EKEventStore; смотрим, что приложение прочитало."""
    out = []

    def ok(name, cond, detail=""):
        out.append((name, bool(cond), detail))

    g = lambda st, title=None: [x for x in st.get("ghosts", []) if title is None or x["title"] == title]
    titles = lambda st: sorted(x["title"] for x in st.get("ghosts", []))
    seed, on = by["ghost-seed"], by["ghost-on"]
    ok("до включения призраков нет, тумблер выключен", not seed["ghosts"] and not seed["ghostsOn"], str(titles(seed)))
    ok("включили (право уже было): тумблер включён", on["ghostsOn"], str(on["ghostsOn"]))
    ok("прочитано всё заведённое: матч, планёрка, каникулы, кружок, ночная смена", all(g(on, t) for t in SEEDED), str(titles(on)))
    m = (g(on, "Матч") or [{}])[0]
    ok("матч: 10:00–11:30 (полтора часа), место «Стадион», календарь «Сын»",
       m and secs(m["end"]) - secs(m["start"]) == 5400 and m["loc"] == "Стадион" and m["cal"] == "Сын" and not m["allDay"], str(m))
    ok("место, записанное только текстом («Где»), не потерялось", (g(on, "Секция") or [{}])[0].get("loc") == "Бассейн", str(g(on, "Секция")))
    ok("каникулы — на весь день, кружок — три вхождения с разным началом (повторы раскрыты), ночная смена — восемь часов",
       (g(on, "Каникулы") or [{}])[0].get("allDay") is True and len({x["start"] for x in g(on, "Кружок")}) == 3
       and (g(on, "Ночная смена") or [{}])[0] and secs(g(on, "Ночная смена")[0]["end"]) - secs(g(on, "Ночная смена")[0]["start"]) == 8 * 3600,
       f"кружок: {[x['start'] for x in g(on, 'Кружок')]}")
    ok("наши съёмки и занятое время призраками не стали (календарь «Light Plan» не читается)",
       not [x for x in on["ghosts"] if x["cal"] == "Light Plan"] and not [x for x in on["ghosts"] if x["title"] in ("Выходной", "Перелёт", "Маша фотосессия")],
       str(titles(on)))
    ok("«Light Plan» нет и в списке календарей для галочек", not [c for c in on["choices"] if c["title"] == "Light Plan"], str(on["choices"]))
    ok("«Сын» и «Работа» отмечены по умолчанию", all(c["shown"] for c in on["choices"] if c["title"] in ("Сын", "Работа")) and
       {c["title"] for c in on["choices"]} >= {"Сын", "Работа"}, str(on["choices"]))
    env = on.get("env", [])
    nonpersonal = [c for c in env if c["type"] in (3, 4)]          # EKCalendarTypeSubscription, EKCalendarTypeBirthday
    shown = {c["title"]: c["shown"] for c in on["choices"]}
    ok(f"подписки и дни рождения по умолчанию сняты (в симуляторе таких календарей: {len(nonpersonal)})",
       all(shown.get(c["title"]) is False for c in nonpersonal if c["title"] in shown), str(nonpersonal))
    blob = on["debug"] + on["snapshotJSON"]
    ok("заметки и ссылка чужого события не прочитаны и не попали в данные", "SECRET" not in blob and "secret.example" not in blob, "")
    ok("призраков нет в снимке данных (ни названия, ни календаря)", "Матч" not in on["snapshotJSON"] and "Планёрка" not in on["snapshotJSON"], "")

    un = by["ghost-unticked"]
    ok("сняли галочку у «Сын»: его призраки пропали, «Работа» осталась",
       not [x for x in un["ghosts"] if x["cal"] == "Сын"] and g(un, "Планёрка") and g(un, "Ночная смена"), str(titles(un)))
    re_ = by["ghost-reticked"]
    ok("вернули галочку: всё, как было", titles(re_) == titles(on), f"{titles(on)} → {titles(re_)}")

    ch = by["ghost-changed"]
    ok("добавили событие в Календаре руками — призрак появился сам, без перезапуска", g(ch, "Новый матч"), f"ждали {ch.get('waitedMs')} мс; {titles(ch)}")

    off = by["ghost-off"]
    ok("выключили: призраков нет, тумблер выключен", not off["ghosts"] and not off["ghostsOn"], str(titles(off)))
    return out


def selftest():
    good = [{"stage": "start", "auth": "allowed", "on": False, "source": "", "rows": []}]
    # Пустой и подпорченный журналы обязаны стать красными.
    bad = check(good)
    assert not all(c[1] for c in bad), "журнал без шагов прошёл проверку"

    # Обратная сторона: синтетический хороший журнал зелёный, а каждая поломка по отдельности — красная.
    def ev_row(title, start, url, notes="", loc=""):
        return {"title": title, "start": start, "end": start, "allDay": False, "url": url, "notes": notes, "location": loc}

    def st(name, events_, sessions, blocks=()):
        return {"stage": name, "auth": "allowed", "on": True, "source": "iCloud",
                "rows": [{"calendar": "Light Plan"}] + events_, "sessions": sessions, "blocks": list(blocks)}

    base_s = {"id": "probe-w", "day": "2026-10-25", "start": 660, "end": 900, "draft": False, "from": "", "genre": "wedding",
              "contact": "Ирина", "notes": "Приезжать за час", "place": "Парк", "mt": 10}
    moved_s = dict(base_s, start=720, end=960, place="Набережная", mt=20, moved=[660, 900], movedDay="")
    off_b = {"id": "probe-b", "from": "2026-10-28", "days": 2, "start": -1, "duration": -1, "moved": False, "movedFrom": "", "text": ""}
    off_m = dict(off_b, **{"from": "2026-10-29", "moved": True, "movedFrom": "2026-10-28", "text": "Время сдвинуто в календаре. Было 28 окт"})
    fl_b = {"id": "probe-f", "from": "2026-10-31", "days": 1, "start": 540, "duration": 240, "moved": False, "movedFrom": "", "text": ""}
    fl_m = dict(fl_b, start=600, moved=True, movedFrom="2026-10-31", text="Время сдвинуто в календаре.")
    draft_s = {"id": "n1", "day": "2026-11-01", "start": 900, "end": 960, "draft": True, "from": "Маша фотосессия", "genre": "", "contact": "",
               "notes": "Маша фотосессия\nв парке", "place": "Парк Горького", "mt": 30}
    w = lambda t: ev_row("Свадьба · Ирина", t, "lightplan://shoot/probe-w", WEDDING_NOTES, "Парк")
    wm = lambda t: ev_row("Свадьба · Ирина", t, "lightplan://shoot/probe-w",
                          WEDDING_NOTES + "\n22 окт 12:41 · время сдвинуто в календаре: 11:00 – 15:00 → 12:00 – 16:00", "Набережная")
    other = ev_row("Выходной", "2026-10-28T00:00:00Z", "lightplan://block/probe-b")
    draft_e = ev_row("Маша фотосессия", "2026-11-01T12:00:00Z", "lightplan://shoot/n1", "Маша фотосессия\nв парке", "Парк Горького")

    def make(**kw):
        d = {
            "reinstalled": st("reinstalled", [w("2026-10-25T08:00:00Z"), other], [base_s]),
            "hand-moved-returned": st("hand-moved-returned", [wm("2026-10-25T09:00:00Z"), other], [moved_s]),
            "hand-renamed": st("hand-renamed", [wm("2026-10-25T09:00:00Z"), other], [moved_s], [off_b, fl_b]),
            "hand-block-moved": st("hand-block-moved", [wm("2026-10-25T09:00:00Z"), other], [moved_s], [off_m, fl_m]),
            "hand-added": st("hand-added", [wm("2026-10-25T09:00:00Z"), other, draft_e], [moved_s, draft_s]),
            "hand-added-repeat": st("hand-added-repeat", [wm("2026-10-25T09:00:00Z"), other, draft_e], [moved_s, draft_s]),
            "hand-added-reinstalled": st("hand-added-reinstalled", [wm("2026-10-25T09:00:00Z"), other, draft_e], [moved_s, draft_s]),
            "hand-draft-deleted": st("hand-draft-deleted", [wm("2026-10-25T09:00:00Z"), other, draft_e], [moved_s, draft_s]),
        }
        d.update(kw)
        return d

    assert all(c[1] for c in check_reverse(make())), [c for c in check_reverse(make()) if not c[1]]
    breakages = {
        "блок не сдвинулся": make(**{"hand-block-moved": st("hand-block-moved", [wm("2026-10-25T09:00:00Z"), other], [moved_s], [off_b, fl_b])}),
        "отметки о сдвиге нет": make(**{"hand-moved-returned": st("hand-moved-returned", [wm("2026-10-25T09:00:00Z"), other], [dict(moved_s, moved=[])])}),
        "съёмка не сдвинулась": make(**{"hand-moved-returned": st("hand-moved-returned", [wm("2026-10-25T09:00:00Z"), other], [base_s])}),
        "событие откатили к прежнему времени": make(**{"hand-moved-returned": st("hand-moved-returned", [w("2026-10-25T08:00:00Z"), other], [moved_s])}),
        "название съёмки переписали из Календаря": make(**{"hand-renamed": st("hand-renamed", [wm("2026-10-25T09:00:00Z"), other], [dict(moved_s, notes="другой текст")])}),
        "событие осталось переименованным": make(**{"hand-renamed": st("hand-renamed", [dict(wm("2026-10-25T09:00:00Z"), title="Чужое название"), other], [moved_s])}),
        "второй черновик после переустановки": make(**{"hand-added-reinstalled": st("hand-added-reinstalled", [wm("2026-10-25T09:00:00Z"), other, draft_e], [moved_s, draft_s, dict(draft_s, id="n2")])}),
        "событие черновика не вернулось": make(**{"hand-draft-deleted": st("hand-draft-deleted", [wm("2026-10-25T09:00:00Z"), other], [moved_s, draft_s])}),
        "черновика нет": make(**{"hand-added": st("hand-added", [wm("2026-10-25T09:00:00Z"), other, draft_e], [moved_s])}),
    }
    for name, log in breakages.items():
        assert not all(c[1] for c in check_reverse(log)), f"поломка «{name}» прошла проверку"

    # Призраки: синтетический хороший журнал зелёный, каждая поломка по отдельности — красная.
    def gh(title, cal, start, end, all_day=False, loc=""):
        return {"title": title, "cal": cal, "allDay": all_day, "start": start, "end": end, "loc": loc, "id": title + start}

    base_g = [gh("Матч", "Сын", "2026-10-28T07:00:00Z", "2026-10-28T08:30:00Z", loc="Стадион"),
              gh("Планёрка", "Работа", "2026-10-28T07:30:00Z", "2026-10-28T08:00:00Z"),
              gh("Каникулы", "Сын", "2026-10-29T00:00:00Z", "2026-10-30T20:59:59Z", True),
              gh("Кружок", "Сын", "2026-10-28T14:00:00Z", "2026-10-28T15:00:00Z"),
              gh("Кружок", "Сын", "2026-10-29T14:00:00Z", "2026-10-29T15:00:00Z"),
              gh("Кружок", "Сын", "2026-10-30T14:00:00Z", "2026-10-30T15:00:00Z"),
              gh("Ночная смена", "Работа", "2026-10-31T15:00:00Z", "2026-10-31T23:00:00Z"),
              gh("Секция", "Сын", "2026-10-28T12:00:00Z", "2026-10-28T13:00:00Z", loc="Бассейн")]
    choices = [{"title": "Сын", "shown": True, "personal": True}, {"title": "Работа", "shown": True, "personal": True},
               {"title": "Дни рождения", "shown": False, "personal": False}]
    env = [{"title": "Дни рождения", "type": 4, "source": "Другое"}, {"title": "Сын", "type": 0, "source": "На iPhone"}]
    own = {"id": "b1", "note": "", "kind": "off", "start": -1, "duration": -1, "allDay": True}

    def gs(name, ghosts, on_=True, blocks=(own,), lp=("Свадьба · Ирина",), **kw):
        d = {"stage": name, "ghostsOn": on_, "ghosts": ghosts, "choices": choices, "blocks": list(blocks), "lpEvents": list(lp),
             "debug": "", "snapshotJSON": "{}", "env": env}
        d.update(kw)
        return d

    def gmake(**kw):
        d = {
            "ghost-seed": gs("ghost-seed", [], False),
            "ghost-on": gs("ghost-on", base_g),
            "ghost-unticked": gs("ghost-unticked", [x for x in base_g if x["cal"] != "Сын"]),
            "ghost-reticked": gs("ghost-reticked", base_g),
            "ghost-changed": gs("ghost-changed", base_g + [gh("Новый матч", "Сын", "2026-11-02T06:00:00Z", "2026-11-02T07:00:00Z")], waitedMs=1200),
            "ghost-off": gs("ghost-off", [], False),
        }
        d.update(kw)
        return d

    assert all(c[1] for c in check_ghosts(gmake())), [c for c in check_ghosts(gmake()) if not c[1]]
    gbreak = {
        "включено, но ничего не прочитано": gmake(**{"ghost-on": gs("ghost-on", [])}),
        "призраки до включения": gmake(**{"ghost-seed": gs("ghost-seed", base_g)}),
        "место только текстом потеряно": gmake(**{"ghost-on": gs("ghost-on", [dict(x, loc="") if x["title"] == "Секция" else x for x in base_g])}),
        "наш календарь стал призраком": gmake(**{"ghost-on": gs("ghost-on", base_g + [gh("Свадьба · Ирина", "Light Plan", "2026-10-28T07:00:00Z", "2026-10-28T08:00:00Z")])}),
        "«Light Plan» попал в список галочек": gmake(**{"ghost-on": gs("ghost-on", base_g, choices=choices + [{"title": "Light Plan", "shown": True, "personal": True}])}),
        "дни рождения показаны по умолчанию": gmake(**{"ghost-on": gs("ghost-on", base_g, choices=[dict(c, shown=True) for c in choices])}),
        "заметки чужого события прочитаны": gmake(**{"ghost-on": gs("ghost-on", base_g, debug="notes: SECRET-NOTES")}),
        "чужое событие попало в данные": gmake(**{"ghost-on": gs("ghost-on", base_g, snapshotJSON='{"note":"Матч"}')}),
        "повтор не раскрыт": gmake(**{"ghost-on": gs("ghost-on", [x for x in base_g if x["title"] != "Кружок"] + base_g[3:4])}),
        "галочка не сняла календарь": gmake(**{"ghost-unticked": gs("ghost-unticked", base_g)}),
        "новое событие не появилось": gmake(**{"ghost-changed": gs("ghost-changed", base_g)}),
        "после выключения призраки остались": gmake(**{"ghost-off": gs("ghost-off", base_g, False)}),
    }
    for name, log in gbreak.items():
        assert not all(c[1] for c in check_ghosts(log)), f"поломка призраков «{name}» прошла проверку"
    print(f"selftest призраков: ok (хороший журнал зелёный; {len(gbreak)} поломок красные)")

    print(f"selftest: ok (неполный журнал красный; хороший обратный журнал зелёный; {len(breakages)} поломок красные)")
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
