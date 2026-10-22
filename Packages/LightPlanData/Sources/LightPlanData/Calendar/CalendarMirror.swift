import Foundation

/// Зеркало записей в календаре телефона (шаг 30.1–4, `docs/14`).
///
/// Правда живёт в Light Plan, Календарь её показывает; в обратную сторону едет только то, что человек сделал в
/// Календаре руками: **время и место** (подвинул событие) и **новое событие** в нашем календаре (станет черновиком).
/// Название и заметки событий остаются нашими: правка их в Календаре не возвращается, а откатывается.
/// Один проход `sync` приводит календарь к списку событий (`CalendarPlan.drafts`): создаёт недостающее, переписывает
/// разошедшееся, убирает лишнее — молча. Что должно вернуться в записи, проход не пишет в календарь, а отдаёт в
/// `Report.incoming`: применить к данным и сохранить — дело приложения, потом следующий проход сойдётся. Запускается «там, где человек»: после сохранения записи и при возврате в приложение, по таймеру
/// никогда.
///
/// Как запись и событие узнают друг друга: на устройстве лежит связь «ключ записи → идентификатор события»
/// (`CalendarMirrorRecord.links`), а в самом событии — ссылка `lightplan://shoot/<id>`. Связь — подсказка, ссылка —
/// страховка: потерялась память — событие всё равно находится в нашем календаре по ссылке, и дубля не будет.
///
/// Актор, и всё же очередь своя (`exclusive`): актор переключается на каждом `await`, и два прохода, запущенные
/// вместе, оба не увидели бы чужого свежесозданного события и завели бы его вдвоём (поймано тестом
/// `concurrentRunsNeverCreateTwins`). Проходы и включение идут строго по одному.
public actor CalendarMirror {

    public struct Report: Sendable, Equatable {
        public var created = 0
        public var updated = 0
        public var removed = 0
        /// Уже стояли такими, как надо.
        public var kept = 0
        /// Запись не удалась — следующий проход попробует снова.
        public var failed = 0
        /// Что человек сделал в Календаре и должно вернуться в записи (30.4). События из этого списка проход не писал.
        public var incoming: [Incoming] = []
        public var changed: Bool { created + updated + removed > 0 }
    }

    /// Правка, пришедшая из Календаря.
    public enum Incoming: Sendable, Equatable {
        /// Человек подвинул событие записи или сменил его место: время и место возвращаются в запись.
        case moved(key: String, event: StoredEvent)
        /// Человек завёл событие прямо в нашем календаре: оно станет черновиком съёмки.
        case created(StoredEvent)
    }

    public enum Outcome: Sendable, Equatable {
        case synced(Report)
        /// Права нет (или забрали): ничего не тронуто, данные приложения целы.
        case noAccess(CalendarAuthorization)
        /// Нашего календаря в телефоне больше нет: его удалили руками. Заново — только когда человек скажет «да».
        case calendarGone
        /// Не удалось завести календарь (учётная запись не берёт, нет места).
        case failed(String)
    }

    /// Имя календаря в списке Календаря: бренд, не переводится.
    public static let calendarTitle = "Light Plan"

    private let store: any CalendarStoring
    private let memory: any CalendarMirrorMemory
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private func exclusive<T>(_ body: () async -> T) async -> T {
        if busy { await withCheckedContinuation { waiting.append($0) } }
        busy = true
        let out = await body()
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
        return out
    }

    public init(store: any CalendarStoring, memory: any CalendarMirrorMemory) {
        self.store = store
        self.memory = memory
    }

    // MARK: - Состояние

    public var record: CalendarMirrorRecord { memory.record }

    /// Наш календарь, если он есть: откуда он и как называется — для строки «Куда класть».
    public func calendar() async -> StoredCalendar? {
        guard await store.authorization() == .allowed, let id = memory.record.calendarId else { return nil }
        return await store.calendar(id: id)
    }

    // MARK: - Включение

    /// Включить зеркало: спросить право (один раз), завести календарь. Отказ ничего не ломает: возвращается
    /// `.noAccess`, и вызывающий говорит человеку, где право выдаётся.
    public func enable(sourceId: String? = nil) async -> Outcome {
        await exclusive { await enableLocked(sourceId: sourceId) }
    }

    private func enableLocked(sourceId: String?) async -> Outcome {
        var auth = await store.authorization()
        if auth == .notDetermined {
            _ = await store.requestAccess()
            auth = await store.authorization()
        }
        guard auth == .allowed else { return .noAccess(auth) }
        let before = memory.record
        var r = before
        r.wanted = true
        if let sourceId { r.sourceId = sourceId }
        memory.record = r
        let out = await ensureCalendar(strict: sourceId != nil).outcome
        if case .failed = out {
            // Календаря нет — включённым зеркало не считается: тумблер не должен обещать того, чего нет.
            var back = memory.record
            back.wanted = before.wanted
            back.sourceId = before.sourceId
            memory.record = back
        }
        return out
    }

    /// Выключить: наши события и (если в нём нет ничего чужого) весь календарь убираются из телефона, память
    /// забывается. Съёмки в Light Plan целы. Не вышло убрать — `.failed`, память прежняя, зеркало остаётся включённым:
    /// выключатель не должен говорить «выключено», оставив события в телефоне.
    @discardableResult
    public func disable() async -> Outcome {
        await exclusive { await disableLocked() }
    }

    private func disableLocked() async -> Outcome {
        var r = memory.record
        guard await store.authorization() == .allowed else {
            // Право отняли: убрать нечем. Выключаем, но связь помним — вернут право и включат, всё сойдётся.
            r.wanted = false
            memory.record = r
            return .synced(Report())
        }
        if let id = r.calendarId, !(await retire(id)) { return .failed("could not remove the calendar") }
        var n = CalendarMirrorRecord()
        n.sourceId = r.sourceId
        memory.record = n
        return .synced(Report())
    }

    /// Сменить учётную запись: календарь заводится в новой, старый уходит, связи забываются. Следующий `sync` кладёт
    /// все события в новый. Старый не убрался — откат: новый (если мы его завели) снимается, всё остаётся как было,
    /// иначе события встали бы дублями в двух календарях.
    public func moveCalendar(to sourceId: String) async -> Outcome {
        await exclusive { await moveLocked(to: sourceId) }
    }

    private func moveLocked(to sourceId: String) async -> Outcome {
        guard await store.authorization() == .allowed else { return .noAccess(await store.authorization()) }
        let old = memory.record
        if old.calendarId != nil, let c = await calendar(), c.sourceId == sourceId { return .synced(Report()) }
        var r = old
        r.sourceId = sourceId
        r.calendarId = nil
        r.links = [:]
        r.facts = [:]
        memory.record = r
        let made = await ensureCalendar(strict: true)
        if case .failed = made.outcome {
            // Новая учётная запись не берёт календарь: остаёмся там, где были.
            memory.record = old
            return made.outcome
        }
        if let oldId = old.calendarId, oldId != memory.record.calendarId, !(await retire(oldId)) {
            if let fresh = made.created { _ = await retire(fresh) }
            memory.record = old
            return .failed("could not remove the old calendar")
        }
        return made.outcome
    }

    /// Человек сказал «да» на вопрос «календарь удалён, завести заново?».
    public func recreateCalendar() async -> Outcome {
        await exclusive { await recreateLocked() }
    }

    private func recreateLocked() async -> Outcome {
        var r = memory.record
        r.calendarId = nil
        r.links = [:]
        r.facts = [:]
        memory.record = r
        return await ensureCalendar().outcome
    }

    // MARK: - Свой календарь

    /// Наш ли это календарь: пустой или с нашими событиями (хоть одно со ссылкой записи). Чужой «Light Plan» с делами
    /// человека, где наших ссылок нет совсем, нашим не считается: его нельзя принять за свой. С 30.4 в нашем календаре
    /// законно лежат и события, заведённые руками (они становятся черновиками), поэтому «все — наши» уже не условие.
    private func isOurs(_ calendarId: String) async -> Bool {
        let events = await ownEvents(calendarId)
        return events.isEmpty || events.contains { CalendarPlan.isRecordLink($0.url) }
    }

    /// Все события календаря за сто лет в обе стороны: по этому списку решается, наш ли календарь и можно ли убрать его
    /// целиком, поэтому окно шире любой съёмки. Редкая операция (принять, выключить, переехать): хранилище режет окно
    /// на куски, запросов около шестидесяти.
    private func ownEvents(_ calendarId: String) async -> [StoredEvent] {
        let year: TimeInterval = 366 * 86_400
        return await store.events(calendarId: calendarId, from: Date().addingTimeInterval(-100 * year),
                                  to: Date().addingTimeInterval(100 * year))
    }

    /// Убрать наш календарь из телефона. Целиком — если в нём только наше; иначе только наши события, а календарь
    /// остаётся человеку. `false` — что-то убрать не удалось.
    private func retire(_ calendarId: String) async -> Bool {
        guard await store.calendar(id: calendarId) != nil else { return true }
        let events = await ownEvents(calendarId)
        if events.allSatisfy({ CalendarPlan.isRecordLink($0.url) }) {
            if (try? await store.removeCalendar(id: calendarId)) != nil { return true }
        }
        var ok = true
        for e in events where CalendarPlan.isRecordLink(e.url) {
            do { try await store.remove(eventId: e.id) } catch { ok = false }
        }
        return ok
    }

    /// Календарь на месте или заведён заново. `created` — идентификатор, если завели именно мы сейчас.
    /// `strict` — человек назвал учётную запись сам: не берёт календарь — это отказ, другую не подставляем. Иначе
    /// идём по списку: запомненная, календарь по умолчанию телефона, потом остальные (iCloud раньше телефона): Google
    /// и Exchange новых календарей через EventKit обычно не берут (замер на телефоне Алексея 22.10).
    private func ensureCalendar(strict: Bool = false) async -> (outcome: Outcome, created: String?) {
        var r = memory.record
        if let id = r.calendarId {
            return (await store.calendar(id: id) == nil ? .calendarGone : .synced(Report()), nil)
        }
        let sources = await store.sources()
        var order: [String] = []
        let first = [r.sourceId, strict ? nil : await store.defaultSourceId()].compactMap { $0 }
        for id in first where sources.contains(where: { $0.id == id }) && !order.contains(id) { order.append(id) }
        if !strict {
            for s in sources where !order.contains(s.id) { order.append(s.id) }
        }
        guard !order.isEmpty else { return (.failed("no calendar account"), nil) }
        var lastError = ""
        for source in order {
            // Память потеряна, а календарь в телефоне остался (переустановка): принимаем его обратно, а не заводим
            // второй. Названия мало: берём календарь, где только наши события (или пусто), — чужой «Light Plan» с
            // делами человека не трогаем.
            for own in await store.calendars(titled: Self.calendarTitle) where own.sourceId == source {
                if await isOurs(own.id) {
                    r.calendarId = own.id
                    r.sourceId = own.sourceId
                    r.links = [:]
                    r.facts = [:]
                    memory.record = r
                    return (.synced(Report()), nil)
                }
            }
            do {
                let c = try await store.createCalendar(title: Self.calendarTitle, sourceId: source)
                r.calendarId = c.id
                r.sourceId = c.sourceId
                r.links = [:]
                r.facts = [:]
                memory.record = r
                return (.synced(Report()), c.id)
            } catch {
                lastError = "\(error)"
            }
        }
        return (.failed(lastError), nil)
    }

    // MARK: - Проход

    /// Привести календарь к `drafts`. Права нет — ничего не трогаем. Календаря нет (его удалили) — не заводим
    /// молча: ждём ответа человека.
    public func sync(_ drafts: [EventDraft], now: Date = Date()) async -> Outcome {
        await exclusive { await syncLocked(drafts, now: now) }
    }

    /// Событие, заведённое руками, приложение превратило в черновик: связываем его с новой записью. Следующий
    /// проход допишет в него ссылку и всё остальное. Вызывать надо после того, как запись сохранена на диск.
    public func adopt(eventId: String, key: String) async {
        await exclusive {
            var r = memory.record
            r.links[key] = eventId
            memory.record = r
        }
    }

    /// Приложение не смогло принять правку из Календаря (например, место в записи занято бронью студии): событие
    /// считается увиденным в этом виде, и следующий проход перепишет его, как у нас, — а не будет отдавать одну и ту же
    /// правку снова и снова.
    public func dismiss(key: String, event: StoredEvent) async {
        await exclusive {
            var r = memory.record
            r.facts[key] = EventFacts(event: event)
            memory.record = r
        }
    }

    /// Куда смотреть за событиями, заведёнными руками, вперёд: дальше запись не появится, пока съёмки не подойдут.
    private static let lookAhead: TimeInterval = 3 * 366 * 86_400

    /// Можно ли сделать из события черновик съёмки: обычное событие со временем и не длиннее суток. «На весь день» —
    /// это скорее занятый день (не съёмка), повторяющееся делит один идентификатор между вхождениями, а событие
    /// длиннее суток не помещается в сутки съёмки. Такие остаются в календаре как есть и не трогаются.
    static func isDraftable(_ e: StoredEvent) -> Bool {
        !e.allDay && !e.recurring && e.end > e.start && e.end.timeIntervalSince(e.start) <= 86_400
    }

    /// Чья правка свежее, если время или место двигали с обеих сторон.
    private enum Winner { case event, record }

    /// Кто двигал: событие в Календаре или запись у нас.
    ///
    /// Отпечаток `facts` — то, какими время и место были, когда обе стороны последний раз сошлись. Событие ушло от
    /// отпечатка, а запись нет — правил человек в Календаре. Ушла только запись — обычная правка у нас. Ушли обе —
    /// побеждает та, что правили позже (метки правок: `mt` записи и `lastModifiedDate` события). Отпечатка нет
    /// (первый проход, переустановка) — побеждает запись: хуже всего тогда потерять один сдвиг в Календаре, а не
    /// откатить съёмку устаревшим событием.
    private func winner(event: StoredEvent, draft: EventDraft, seen: EventFacts?) -> Winner {
        guard let seen else { return .record }
        let eventMoved = !EventFacts(event: event).isClose(to: seen)
        let recordMoved = !EventFacts(draft: draft).isClose(to: seen)
        switch (eventMoved, recordMoved) {
        case (false, _): return .record
        case (true, false): return .event
        case (true, true):
            guard let mt = draft.recordModified, let em = event.modified else { return .record }
            return em.timeIntervalSince1970 * 1000 > Double(mt) ? .event : .record
        }
    }

    private func syncLocked(_ drafts: [EventDraft], now: Date) async -> Outcome {
        guard memory.record.wanted else { return .synced(Report()) }
        let auth = await store.authorization()
        guard auth == .allowed else { return .noAccess(auth) }
        if memory.record.calendarId == nil {
            let made = await ensureCalendar().outcome
            guard case .synced = made else { return made }
        }
        var rec = memory.record
        guard let cid = rec.calendarId, await store.calendar(id: cid) != nil else { return .calendarGone }

        // Что стоит в нашем календаре сейчас. Окно — от самой ранней записи до самой поздней, с запасом в год назад и
        // на три года вперёд: события, заведённые руками, ищутся и там. События исчезнувших записей вне окна
        // находятся по связи (`stale` ниже), а не по запросу к календарю.
        let edges = drafts.flatMap { [$0.start, $0.end] } + [now]
        let year: TimeInterval = 366 * 86_400
        let found = await store.events(calendarId: cid, from: edges.min()!.addingTimeInterval(-year),
                                       to: edges.max()!.addingTimeInterval(Self.lookAhead))
        // Своими считаем события со ссылкой записи (`shoot`, `block`); остальные в этом календаре — человека: не
        // перезаписываем, а те из них, что можно, предлагаем стать черновиками (`unlinked`).
        var byKey: [String: [StoredEvent]] = [:]
        for e in found { if let u = e.url, CalendarPlan.isRecordLink(u) { byKey[u.absoluteString, default: []].append(e) } }
        let hinted = Set(rec.links.values)
        let unlinked = found.filter { !CalendarPlan.isRecordLink($0.url) && !hinted.contains($0.id) && Self.isDraftable($0) }

        var report = Report()
        var links: [String: String] = [:]
        var facts: [String: EventFacts] = [:]
        let wanted = Dictionary(drafts.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

        for draft in drafts where links[draft.key] == nil {
            var candidates = byKey[draft.key] ?? []
            // Связь — подсказка: событие, которое человек переименовал или у которого стёр ссылку, находится по ней.
            if let linked = rec.links[draft.key], !candidates.contains(where: { $0.id == linked }),
               let e = await store.event(id: linked), e.calendarId == cid { candidates.append(e) }
            let linkedId = rec.links[draft.key]
            candidates.sort { ($0.id == linkedId ? 0 : 1, $0.id) < ($1.id == linkedId ? 0 : 1, $1.id) }

            guard let keep = candidates.first else {
                do {
                    links[draft.key] = try await store.save(draft, replacing: nil, calendarId: cid)
                    facts[draft.key] = EventFacts(draft: draft)
                    report.created += 1
                } catch { report.failed += 1 }
                continue
            }
            links[draft.key] = keep.id
            // Двойники одной записи (прошлый сбой, сеть календаря) — лишнее убираем.
            for extra in candidates.dropFirst() {
                do { try await store.remove(eventId: extra.id); report.removed += 1 } catch { report.failed += 1 }
            }
            if keep.matches(draft) { report.kept += 1; facts[draft.key] = EventFacts(draft: draft); continue }
            // Разошлись: если дело во времени или месте съёмки и правил человек в Календаре, это правка для записи, а не
            // повод переписывать событие. Занятое время (`block`) обратно не едет: его событие всегда как у нас.
            // Повторяющееся событие и событие длиннее суток в запись не возвращаются (как и в черновики): они остаются как у нас.
            if CalendarPlan.shootId(in: draft.url) != nil, !keep.timeAndPlaceMatch(draft), Self.isDraftable(keep), !draft.allDay,
               winner(event: keep, draft: draft, seen: rec.facts[draft.key]) == .event {
                report.incoming.append(.moved(key: draft.key, event: keep))
                if let seen = rec.facts[draft.key] { facts[draft.key] = seen }
                continue
            }
            do {
                _ = try await store.save(draft, replacing: keep.id, calendarId: cid)
                facts[draft.key] = EventFacts(draft: draft)
                report.updated += 1
            } catch {
                report.failed += 1
                if let seen = rec.facts[draft.key] { facts[draft.key] = seen }
            }
        }

        // События, заведённые руками, — черновикам. Какие из них уже отданы приложению и ждут, пока их свяжут, —
        // не повторяем: связь пишется сразу после сохранения записи (`adopt`).
        report.incoming += unlinked.sorted { ($0.start, $0.id) < ($1.start, $1.id) }.map { .created($0) }

        // Записи нет (удалили, ушла в корзину) — событие убираем, связь забываем. Убрать не вышло — связь остаётся:
        // событие может лежать вне окна поиска, и без связи следующий проход его уже не найдёт.
        var stale: [String: String] = [:]                      // идентификатор события → ключ записи
        for (key, id) in rec.links where wanted[key] == nil { stale[id] = key }
        for (key, events) in byKey where wanted[key] == nil { for e in events { stale[e.id] = stale[e.id] ?? key } }
        var retained: [String: String] = [:]
        for (id, key) in stale.sorted(by: { $0.key < $1.key }) {
            // Уже нет (убрали руками) или переехало в чужой календарь — не наше дело.
            guard let e = await store.event(id: id), e.calendarId == cid else { continue }
            do { try await store.remove(eventId: id); report.removed += 1 } catch { report.failed += 1; retained[key] = id }
        }
        links.merge(retained) { a, _ in a }

        // Не удалось записать — связь прежняя остаётся (следующий проход попробует снова).
        for (key, id) in rec.links where links[key] == nil && wanted[key] != nil { links[key] = id }
        for (key, seen) in rec.facts where facts[key] == nil && wanted[key] != nil && links[key] != nil { facts[key] = seen }
        rec = memory.record
        rec.links = links
        rec.facts = facts
        memory.record = rec
        return .synced(report)
    }
}
