import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain
#if DEBUG && os(iOS)
import CoreLocation
import EventKit

/// Замер на настоящем календаре симулятора (шаг 30.1–3): `-LPCalendarProbe <файл>` (Debug).
///
/// Приложение само проходит сценарий — включает зеркало, правит записи, «удаляет руками» событие вторым
/// `EKEventStore` (как это сделал бы Календарь) — и после каждого шага пишет в файл, что лежит в базе календарей
/// на самом деле: по строке JSON на шаг. Разбирает и проверяет `Tools/calendar_sim.py`. Право на календарь
/// выдаёт драйвер: `simctl privacy grant calendar`.
extension AppModel {

    func runCalendarProbe(log path: String) {
        Task { [weak self] in
            guard let self else { return }
            calendarWatch?.cancel()          // сценарий идёт по шагам; уведомления базы вмешивались бы в его порядок
            calendarWatch = nil
            // Свои записи вместо данных симулятора: сценарий должен читаться одинаково от запуска к запуску.
            let day = Self.today(in: place.place, now: now()).adding(days: 3)
            var wedding = Session(id: "probe-w", kind: .shoot, day: day, start: 600, end: 840, genre: .wedding)
            wedding.contact = "Ирина"; wedding.clientPhone = "8 916 123-45-67"; wedding.notes = "Приезжать за час"
            wedding.place = "Парк"; wedding.placeAddress = "ул. Ленина 5"
            wedding.latitude = 56.4977; wedding.longitude = 84.9744                      // Томск
            var meet = Session(id: "probe-m", kind: .meet, day: day.adding(days: 1), start: 900, end: 960, genre: .portrait)
            meet.contact = "Олег"
            var off = Block(id: "probe-b", kind: .off, from: day.adding(days: 3)); off.allDay = true; off.days = 2
            var flight = Block(id: "probe-f", kind: .flight, from: day.adding(days: 6))
            flight.start = 540; flight.duration = 240; flight.zoneFrom = 7; flight.zoneTo = 3
            snapshot.sessions = [wedding, meet]
            snapshot.blocks = [off, flight]
            snapshot.trashed = []

            @MainActor func dump(_ stage: String) async {
                let rows = await Self.probeRows()
                let records: [[String: Any]] = snapshot.sessions.map { s in
                    ["id": s.id, "day": s.day.snapshotString, "start": s.start, "end": s.endMinute, "draft": s.isCalendarDraft,
                     "from": s.fromCalendar ?? "", "genre": s.genre?.rawValue ?? "", "contact": s.contact, "notes": s.notes,
                     "place": s.place, "mt": s.modifiedAt ?? 0,
                     "moved": s.dayMoved.map { [$0.start, $0.end] } ?? [], "movedDay": s.dayMoved?.day?.snapshotString ?? ""]
                }
                let blocks: [[String: Any]] = snapshot.blocks.map { b in
                    ["id": b.id, "from": b.from.snapshotString, "days": b.days, "start": b.start ?? -1, "duration": b.duration ?? -1,
                     "moved": b.movedFrom != nil, "movedFrom": b.movedFrom?.from.snapshotString ?? "", "text": blockMovedText(b) ?? ""]
                }
                let line = (try? JSONSerialization.data(withJSONObject: ["stage": stage, "auth": "\(calendarAuth)", "on": calendarMirrorOn,
                                                                         "source": calendarSourceTitle ?? "", "rows": rows,
                                                                         "sessions": records, "blocks": blocks], options: [.sortedKeys])) ?? Data()
                let text = String(decoding: line, as: UTF8.self) + "\n"
                if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
                else { try? text.write(toFile: path, atomically: true, encoding: .utf8) }
            }
            try? "".write(toFile: path, atomically: true, encoding: .utf8)
            Self.probeDeleteCalendarByHand()             // чистый лист: календарь прошлого прогона убираем
            await dump("start")

            setCalendarMirror(true); await calendarChain?.value
            await dump("on")

            // Ещё два прохода подряд: дублей быть не должно.
            syncCalendarMirror(force: true); syncCalendarMirror(force: true); await calendarChain?.value
            await dump("repeat")
            // И что проход сделал бы теперь: на неизменных данных — ничего (ни одной записи в календарь).
            if let mirror = calendarMirror, case .synced(let r) = await mirror.sync(calendarDrafts()) {
                let text = "{\"stage\":\"repeat-report\",\"created\":\(r.created),\"updated\":\(r.updated),\"removed\":\(r.removed),\"kept\":\(r.kept),\"failed\":\(r.failed)}\n"
                if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
            }

            // Человек удалил событие в Календаре (другой процесс — другой EKEventStore).
            Self.probeDeleteByHand(title: "Свадьба · Ирина")
            await dump("deleted-by-hand")
            syncCalendarMirror(force: true); await calendarChain?.value
            await dump("reconciled")

            // Съёмку подвинули на час.
            snapshot.sessions[0].start += 60; snapshot.sessions[0].end = 900
            persist(); await calendarChain?.value
            await dump("moved")

            // Корзина и возврат.
            trashSession(id: "probe-w"); await calendarChain?.value
            await dump("trashed")
            restoreSession(id: "probe-w"); await calendarChain?.value
            await dump("restored")

            // Календарь удалили целиком: сначала вопрос, потом «да».
            Self.probeDeleteCalendarByHand()
            syncCalendarMirror(force: true); await calendarChain?.value
            await dump("calendar-deleted (ask=\(calendarGoneAsk))")
            answerCalendarGone(yes: true); await calendarChain?.value
            await dump("calendar-recreated")

            // Переустановка: память приложения стёрта, календарь «Light Plan» со своими событиями в телефоне остался.
            if let store = calendarStore {
                attachCalendar(store: store, memory: InMemoryCalendarMemory())
                setCalendarMirror(true); await calendarChain?.value
                await dump("reinstalled")
            }

            // 30.4. Человек работает в Календаре: второй EKEventStore — как другой процесс (приложение Календарь).
            // Подвинул событие свадьбы на час вперёд и сменил место.
            Self.probeEditByHand(title: "Свадьба · Ирина") { e in
                e.startDate = e.startDate.addingTimeInterval(3600); e.endDate = e.endDate.addingTimeInterval(3600)
                let loc = EKStructuredLocation(title: "Набережная"); loc.geoLocation = CLLocation(latitude: 56.4, longitude: 84.9)
                e.structuredLocation = loc
            }
            await dump("hand-moved")
            syncCalendarMirror(force: true); await calendarChain?.value
            await dump("hand-moved-returned")

            // Переименовал событие и переписал заметки — в съёмку это не едет, событие возвращается как у нас.
            Self.probeEditByHand(title: "Свадьба · Ирина") { e in e.title = "Чужое название"; e.notes = "другой текст" }
            syncCalendarMirror(force: true); await calendarChain?.value
            await dump("hand-renamed")

            // Занятое время двигает так же: «Выходной» (на весь день) на сутки, «Перелёт» на час.
            Self.probeEditByHand(title: "Выходной") { e in
                e.startDate = e.startDate.addingTimeInterval(86_400); e.endDate = e.endDate.addingTimeInterval(86_400)
            }
            Self.probeEditByHand(title: "Перелёт") { e in
                e.startDate = e.startDate.addingTimeInterval(3600); e.endDate = e.endDate.addingTimeInterval(3600)
            }
            syncCalendarMirror(force: true); await calendarChain?.value
            await dump("hand-block-moved")

            // Завёл своё событие прямо в «Light Plan»: черновик, один раз, и после ещё двух проходов, и после «переустановки».
            Self.probeAddByHand(title: "Маша фотосессия", notes: "в парке", daysAhead: 9)
            syncCalendarMirror(force: true); await calendarChain?.value
            await dump("hand-added")
            syncCalendarMirror(force: true); syncCalendarMirror(force: true); await calendarChain?.value
            await dump("hand-added-repeat")
            if let store = calendarStore {
                attachCalendar(store: store, memory: InMemoryCalendarMemory())
                setCalendarMirror(true); await calendarChain?.value
                syncCalendarMirror(force: true); await calendarChain?.value
                await dump("hand-added-reinstalled")
            }
            // Удалил событие черновика — черновик остаётся, событие возвращается.
            Self.probeDeleteByHand(title: "Маша фотосессия")
            syncCalendarMirror(force: true); await calendarChain?.value
            await dump("hand-draft-deleted")
            await dump("done")

            // Объём: сколько стоит первое включение у фотографа с долгой историей (`-LPCalendarBulk N`).
            let n = UserDefaults.standard.integer(forKey: "LPCalendarBulk")
            if n > 0, let mirror = calendarMirror {
                snapshot.sessions = (0..<n).map { i in
                    var s = Session(id: "bulk-\(i)", kind: .shoot, day: day.adding(days: -n / 2 + i), start: 600, end: 720, genre: .family)
                    s.contact = "Клиент \(i)"
                    return s
                }
                snapshot.blocks = []
                let t0 = Date()
                let first = await mirror.sync(calendarDrafts())
                let t1 = Date()
                let second = await mirror.sync(calendarDrafts())
                let t2 = Date()
                var created = 0, kept = 0
                if case .synced(let r) = first { created = r.created }
                if case .synced(let r) = second { kept = r.kept }
                let text = "{\"bulk\":\(n),\"createdMs\":\(Int(t1.timeIntervalSince(t0) * 1000)),\"created\":\(created),\"repeatMs\":\(Int(t2.timeIntervalSince(t1) * 1000)),\"kept\":\(kept)}\n"
                if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
            }
        }
    }

    /// Что на самом деле лежит в календарях телефона: свежий `EKEventStore`, поля, которых наш протокол не читает.
    private static func probeRows() async -> [[String: Any]] {
        let store = EKEventStore()
        let iso = ISO8601DateFormatter(); iso.timeZone = TimeZone(secondsFromGMT: 0)
        var out: [[String: Any]] = []
        for c in store.calendars(for: .event) where c.title == CalendarMirror.calendarTitle {
            let events = store.events(matching: store.predicateForEvents(withStart: Date().addingTimeInterval(-86_400 * 30),
                                                                         end: Date().addingTimeInterval(86_400 * 60), calendars: [c]))
            out.append(["calendar": c.title, "source": c.source?.title ?? "", "events": events.count,
                        "supportsBusy": c.supportedEventAvailabilities.contains(.busy), "supported": c.supportedEventAvailabilities.rawValue])
            for e in events.sorted(by: { ($0.startDate, $0.title ?? "") < ($1.startDate, $1.title ?? "") }) {
                out.append(["title": e.title ?? "", "start": iso.string(from: e.startDate), "end": iso.string(from: e.endDate),
                            "allDay": e.isAllDay, "tz": e.timeZone?.identifier ?? "", "tzOffset": e.timeZone?.secondsFromGMT(for: e.startDate) ?? 0,
                            "busy": e.availability == .busy, "availability": e.availability.rawValue, "alarms": e.alarms?.count ?? 0, "url": e.url?.absoluteString ?? "",
                            "location": e.structuredLocation?.title ?? "",
                            "lat": e.structuredLocation?.geoLocation?.coordinate.latitude ?? 0,
                            "lon": e.structuredLocation?.geoLocation?.coordinate.longitude ?? 0, "notes": e.notes ?? ""])
            }
        }
        return out
    }

    private static func probeDeleteByHand(title: String) {
        let store = EKEventStore()
        for c in store.calendars(for: .event) where c.title == CalendarMirror.calendarTitle {
            let p = store.predicateForEvents(withStart: Date().addingTimeInterval(-86_400 * 30), end: Date().addingTimeInterval(86_400 * 60), calendars: [c])
            for e in store.events(matching: p) where e.title == title { try? store.remove(e, span: .thisEvent, commit: true) }
        }
    }

    /// Правка события вторым хранилищем: как будто человек открыл Календарь и подвинул или переименовал его.
    private static func probeEditByHand(title: String, _ change: (EKEvent) -> Void) {
        let store = EKEventStore()
        for c in store.calendars(for: .event) where c.title == CalendarMirror.calendarTitle {
            let p = store.predicateForEvents(withStart: Date().addingTimeInterval(-86_400 * 30), end: Date().addingTimeInterval(86_400 * 60), calendars: [c])
            for e in store.events(matching: p) where e.title == title { change(e); try? store.save(e, span: .thisEvent, commit: true) }
        }
    }

    /// Событие, заведённое руками в нашем календаре: без ссылки, с названием, заметками и местом.
    private static func probeAddByHand(title: String, notes: String, daysAhead: Int) {
        let store = EKEventStore()
        guard let c = store.calendars(for: .event).first(where: { $0.title == CalendarMirror.calendarTitle }) else { return }
        let e = EKEvent(eventStore: store)
        e.calendar = c
        e.title = title
        e.notes = notes
        e.startDate = Date().addingTimeInterval(Double(daysAhead) * 86_400)
        e.endDate = e.startDate.addingTimeInterval(3600)
        let loc = EKStructuredLocation(title: "Парк Горького"); loc.geoLocation = CLLocation(latitude: 55.73, longitude: 37.6)
        e.structuredLocation = loc
        try? store.save(e, span: .thisEvent, commit: true)
    }

    private static func probeDeleteCalendarByHand() {
        let store = EKEventStore()
        for c in store.calendars(for: .event) where c.title == CalendarMirror.calendarTitle { try? store.removeCalendar(c, commit: true) }
    }

    /// Вызывается при запуске живого приложения.
    func debugCalendarProbe() {
        if let path = UserDefaults.standard.string(forKey: "LPCalendarProbe") { runCalendarProbe(log: path) }
    }
}
#else
extension AppModel {
    func debugCalendarProbe() {}
}
#endif
