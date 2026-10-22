import Foundation

/// Одностороннее зеркало записей в календарь телефона (шаг 30.1–3, `docs/14`).
///
/// Правда живёт в Light Plan, Календарь её показывает. Один проход `sync` приводит календарь к списку событий
/// (`CalendarPlan.drafts`) и ничего не оставляет «на потом»: создаёт недостающее, переписывает разошедшееся, убирает
/// лишнее — молча. Запускается «там, где человек»: после сохранения записи и при возврате в приложение, по таймеру
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
        public var changed: Bool { created + updated + removed > 0 }
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
        var r = memory.record
        r.wanted = true
        if let sourceId { r.sourceId = sourceId }
        memory.record = r
        return await ensureCalendar()
    }

    /// Выключить: календарь с его событиями убирается из телефона, память забывается. Съёмки в Light Plan целы.
    public func disable() async {
        await exclusive { await disableLocked() }
    }

    private func disableLocked() async {
        let r = memory.record
        if let id = r.calendarId, await store.authorization() == .allowed { try? await store.removeCalendar(id: id) }
        var n = CalendarMirrorRecord()
        n.sourceId = r.sourceId
        memory.record = n
    }

    /// Сменить учётную запись: календарь заводится в новой, старый уходит вместе с событиями, связи забываются.
    /// Следующий `sync` кладёт все события в новый.
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
        memory.record = r
        let made = await ensureCalendar()
        if case .failed = made {
            // Новая учётная запись не берёт календарь: остаёмся там, где были.
            memory.record = old
            return made
        }
        if let id = old.calendarId { try? await store.removeCalendar(id: id) }
        return made
    }

    /// Человек сказал «да» на вопрос «календарь удалён, завести заново?».
    public func recreateCalendar() async -> Outcome {
        await exclusive { await recreateLocked() }
    }

    private func recreateLocked() async -> Outcome {
        var r = memory.record
        r.calendarId = nil
        r.links = [:]
        memory.record = r
        return await ensureCalendar()
    }

    private func ensureCalendar() async -> Outcome {
        var r = memory.record
        if let id = r.calendarId {
            return await store.calendar(id: id) == nil ? .calendarGone : .synced(Report())
        }
        let sources = await store.sources()
        let preferred = [r.sourceId, await store.defaultSourceId()].compactMap { $0 }
            .first { id in sources.contains { $0.id == id } } ?? sources.first?.id
        guard let source = preferred else { return .failed("no calendar account") }
        // Память потеряна, а календарь в телефоне остался (переустановка): принимаем его обратно, а не заводим второй.
        if let own = await store.calendars(titled: Self.calendarTitle).first(where: { $0.sourceId == source }) {
            r.calendarId = own.id
            r.sourceId = own.sourceId
            r.links = [:]
            memory.record = r
            return .synced(Report())
        }
        do {
            let c = try await store.createCalendar(title: Self.calendarTitle, sourceId: source)
            r.calendarId = c.id
            r.sourceId = c.sourceId
            r.links = [:]
            memory.record = r
            return .synced(Report())
        } catch {
            return .failed("\(error)")
        }
    }

    // MARK: - Проход

    /// Привести календарь к `drafts`. Права нет — ничего не трогаем. Календаря нет (его удалили) — не заводим
    /// молча: ждём ответа человека.
    public func sync(_ drafts: [EventDraft], now: Date = Date()) async -> Outcome {
        await exclusive { await syncLocked(drafts, now: now) }
    }

    private func syncLocked(_ drafts: [EventDraft], now: Date) async -> Outcome {
        guard memory.record.wanted else { return .synced(Report()) }
        let auth = await store.authorization()
        guard auth == .allowed else { return .noAccess(auth) }
        if memory.record.calendarId == nil {
            let made = await ensureCalendar()
            guard case .synced = made else { return made }
        }
        var rec = memory.record
        guard let cid = rec.calendarId, await store.calendar(id: cid) != nil else { return .calendarGone }

        // Что стоит в нашем календаре сейчас. Окно — от самой ранней записи до самой поздней, с запасом в год. События
        // исчезнувших записей вне окна находятся по связи (`stale` ниже), а не по запросу к календарю.
        let edges = drafts.flatMap { [$0.start, $0.end] } + [now]
        let year: TimeInterval = 366 * 86_400
        let found = await store.events(calendarId: cid, from: edges.min()!.addingTimeInterval(-year),
                                       to: edges.max()!.addingTimeInterval(year))
        // Своими считаем события со ссылкой нашей схемы; всё остальное в этом календаре — человека, не трогаем.
        var byKey: [String: [StoredEvent]] = [:]
        for e in found { if let u = e.url, u.scheme == "lightplan" { byKey[u.absoluteString, default: []].append(e) } }

        var report = Report()
        var links: [String: String] = [:]
        let wanted = Dictionary(drafts.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

        for draft in drafts where links[draft.key] == nil {
            var candidates = byKey[draft.key] ?? []
            // Связь — подсказка: событие, которое человек переименовал или у которого стёр ссылку, находится по ней.
            if let linked = rec.links[draft.key], !candidates.contains(where: { $0.id == linked }),
               let e = await store.event(id: linked), e.calendarId == cid { candidates.append(e) }
            let linkedId = rec.links[draft.key]
            candidates.sort { ($0.id == linkedId ? 0 : 1, $0.id) < ($1.id == linkedId ? 0 : 1, $1.id) }

            guard let keep = candidates.first else {
                do { links[draft.key] = try await store.save(draft, replacing: nil, calendarId: cid); report.created += 1 }
                catch { report.failed += 1 }
                continue
            }
            links[draft.key] = keep.id
            // Двойники одной записи (прошлый сбой, сеть календаря) — лишнее убираем.
            for extra in candidates.dropFirst() {
                do { try await store.remove(eventId: extra.id); report.removed += 1 } catch { report.failed += 1 }
            }
            if keep.matches(draft) { report.kept += 1; continue }
            do { _ = try await store.save(draft, replacing: keep.id, calendarId: cid); report.updated += 1 }
            catch { report.failed += 1 }
        }

        // Записи нет (удалили, ушла в корзину) — событие убираем, связь забываем.
        var stale = Set<String>()
        for (key, id) in rec.links where wanted[key] == nil { stale.insert(id) }
        for (key, events) in byKey where wanted[key] == nil { for e in events { stale.insert(e.id) } }
        for id in stale.sorted() {
            // Уже нет (убрали руками) или переехало в чужой календарь — не наше дело.
            guard let e = await store.event(id: id), e.calendarId == cid else { continue }
            do { try await store.remove(eventId: id); report.removed += 1 } catch { report.failed += 1 }
        }

        // Не удалось записать — связь прежняя остаётся (следующий проход попробует снова).
        for (key, id) in rec.links where links[key] == nil && wanted[key] != nil { links[key] = id }
        rec = memory.record
        rec.links = links
        memory.record = rec
        return .synced(report)
    }
}
