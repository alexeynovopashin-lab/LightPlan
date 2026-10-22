import Foundation
import Synchronization

/// Календарь в памяти: подставка для тестов и снимков экранов (шаг 30.1). Ведёт себя как настоящий там, где это
/// важно зеркалу: без права ничего не отдаёт и не пишет, идентификаторы выдаёт сам, удалённый календарь уносит
/// свои события. Руками человека в Календаре телефона управляют методы `user…`.
public final class InMemoryCalendarStore: CalendarStoring, @unchecked Sendable {

    private struct State {
        var auth: CalendarAuthorization
        /// Что ответит системное окно, когда его покажут.
        var willGrant: Bool
        var sources: [CalendarSource]
        var defaultSource: String?
        /// Учётные записи, которые не берут календари (как «Дни рождения» или чужой Exchange).
        var refusing: Set<String> = []
        var calendars: [String: StoredCalendar] = [:]
        var events: [String: StoredEvent] = [:]
        /// Правила повторения событий (только у тех, что заведены через `userAddRepeating`): вхождения считаются при чтении.
        var repeats: [String: Repeat] = [:]
        /// Сколько раз спросили события календаря: тест кэша призраков.
        var eventReads = 0
        /// Ответ владельца на приглашение у событий, заведённых с `invite:`.
        var invites: [String: InviteResponse] = [:]
        /// Остановка чтения призраков посреди ответа: тест гонки «ответ пришёл после сброса кэша».
        var readGate: (@Sendable () async -> Void)?
        var next = 1
        var saves = 0
        var removes = 0
        var requests = 0
        /// Следующие записи событий отказывают: диск полон, учётная запись отвалилась.
        var failingWrites = false
        /// Календарь не удаляется: учётная запись недоступна, нет сети.
        var failingCalendarRemoval = false
        /// То же, но только для этих календарей (старая учётная запись недоступна, новая — в порядке).
        var failingRemovalIds: Set<String> = []
        /// Система «нормализует» заметки по-своему: записанное читается чуть иначе, и событие вечно кажется расхождением.
        var normalizingNotes = false
        /// Подписчики на «база изменилась» (`EKEventStoreChanged`).
        var listeners: [Int: AsyncStream<Void>.Continuation] = [:]
        var nextListener = 0
    }

    /// Повторение для подставки: шаг в днях и сколько всего вхождений (с первым).
    public struct Repeat: Sendable, Hashable {
        public var everyDays: Int
        public var count: Int
        public init(everyDays: Int, count: Int) { self.everyDays = everyDays; self.count = count }
    }

    private let state: Mutex<State>
    /// Часы подставки: `modified` событий ставится ими. Тест подаёт свои, чтобы развести «раньше» и «позже».
    private let clock: @Sendable () -> Date

    public init(authorization: CalendarAuthorization = .allowed, willGrant: Bool = true,
                sources: [CalendarSource] = [
                    CalendarSource(id: "icloud", title: "iCloud", kind: .account),
                    CalendarSource(id: "local", title: "На моём iPhone", kind: .local),
                ],
                defaultSource: String? = "icloud", clock: @escaping @Sendable () -> Date = { Date() }) {
        state = Mutex(State(auth: authorization, willGrant: willGrant, sources: sources, defaultSource: defaultSource))
        self.clock = clock
    }

    /// Как EventKit: любая запись в базе — своя или чужая — будит подписчиков.
    private func notify() {
        let all = state.withLock { Array($0.listeners.values) }
        for l in all { l.yield() }
    }

    public func changes() -> AsyncStream<Void> {
        AsyncStream { cont in
            let id = state.withLock { s -> Int in s.nextListener += 1; s.listeners[s.nextListener] = cont; return s.nextListener }
            cont.onTermination = { [weak self] _ in self?.state.withLock { $0.listeners[id] = nil } }
        }
    }

    // MARK: - Протокол

    public func authorization() async -> CalendarAuthorization { state.withLock { $0.auth } }

    public func requestAccess() async -> Bool {
        state.withLock { s in
            s.requests += 1
            if s.auth == .notDetermined { s.auth = s.willGrant ? .allowed : .denied }
            return s.auth == .allowed
        }
    }

    public func sources() async -> [CalendarSource] {
        state.withLock { $0.auth == .allowed ? $0.sources : [] }
    }

    public func defaultSourceId() async -> String? { state.withLock { $0.auth == .allowed ? $0.defaultSource : nil } }

    public func calendar(id: String) async -> StoredCalendar? {
        state.withLock { $0.auth == .allowed ? $0.calendars[id] : nil }
    }

    public func calendars(titled title: String) async -> [StoredCalendar] {
        state.withLock { s in s.auth == .allowed ? s.calendars.values.filter { $0.title == title }.sorted { $0.id < $1.id } : [] }
    }

    public func createCalendar(title: String, sourceId: String) async throws -> StoredCalendar {
        try state.withLock { s in
            guard s.auth == .allowed else { throw CalendarStoreError.refused("no access") }
            guard let src = s.sources.first(where: { $0.id == sourceId }), !s.refusing.contains(sourceId) else {
                throw CalendarStoreError.refused("That account does not allow calendars to be added or removed.")
            }
            let c = StoredCalendar(id: "cal-\(s.next)", title: title, sourceId: src.id, sourceTitle: src.title)
            s.next += 1
            s.calendars[c.id] = c
            return c
        }
    }

    public func removeCalendar(id: String) async throws {
        try state.withLock { s in
            if s.failingCalendarRemoval || s.failingRemovalIds.contains(id) { throw CalendarStoreError.refused("calendar removal refused") }
            s.calendars[id] = nil
            s.events = s.events.filter { $0.value.calendarId != id }
        }
    }

    public func allCalendars() async -> [StoredCalendar] {
        state.withLock { $0.auth == .allowed ? $0.calendars.values.sorted { ($0.sourceTitle, $0.title, $0.id) < ($1.sourceTitle, $1.title, $1.id) } : [] }
    }

    public func events(calendarId: String, from: Date, to: Date) async -> [StoredEvent] {
        state.withLock { s in
            s.eventReads += 1
            guard s.auth == .allowed else { return [] }
            var out: [StoredEvent] = []
            for e in s.events.values where e.calendarId == calendarId {
                guard let r = s.repeats[e.id] else {
                    if e.start < to && e.end >= from { out.append(e) }
                    continue
                }
                // Как EventKit: каждое вхождение — отдельное событие с тем же идентификатором и своим временем.
                for k in 0..<r.count {
                    let shift = TimeInterval(k * r.everyDays * 86_400)
                    let a = e.start.addingTimeInterval(shift), b = e.end.addingTimeInterval(shift)
                    guard a < to && b >= from else { continue }
                    out.append(StoredEvent(id: e.id, calendarId: e.calendarId, title: e.title, start: a, end: b, allDay: e.allDay,
                                           offsetSeconds: e.offsetSeconds, locationTitle: e.locationTitle, latitude: e.latitude,
                                           longitude: e.longitude, url: e.url, notes: e.notes, modified: e.modified, recurring: true,
                                           cancelled: e.cancelled))
                }
            }
            return out.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        }
    }

    public func ghostEvents(calendarId: String, from: Date, to: Date) async -> [GhostEvent] {
        let list = await events(calendarId: calendarId, from: from, to: to)       // снимок базы на этот миг
        if let gate = state.withLock({ $0.readGate }) { await gate() }
        return list.map { e in
            GhostEvent(id: e.id, calendarId: e.calendarId, title: e.title, start: e.start, end: e.end, allDay: e.allDay,
                       location: e.locationTitle, cancelled: e.cancelled, ours: CalendarPlan.isRecordLink(e.url),
                       declined: state.withLock { $0.invites[e.id] } == .declined)
        }
    }

    public func event(id: String) async -> StoredEvent? { state.withLock { $0.auth == .allowed ? $0.events[id] : nil } }

    public func save(_ d: EventDraft, replacing id: String?, calendarId: String) async throws -> String {
        let now = clock()
        defer { notify() }
        return try state.withLock { s in
            guard s.auth == .allowed, !s.failingWrites else { throw CalendarStoreError.refused("write refused") }
            guard s.calendars[calendarId] != nil else { throw CalendarStoreError.refused("calendar is gone") }
            let eid: String
            if let id, s.events[id] != nil { eid = id } else { eid = "ev-\(s.next)"; s.next += 1 }
            s.events[eid] = StoredEvent(
                id: eid, calendarId: calendarId, title: d.title, start: d.start, end: d.end, allDay: d.allDay,
                offsetSeconds: d.allDay ? 0 : d.timeZone.secondsFromGMT(for: d.start),
                locationTitle: d.locationTitle, latitude: d.latitude, longitude: d.longitude, url: d.url,
                notes: s.normalizingNotes ? (d.notes ?? "") + " ·" : d.notes, modified: now)
            s.saves += 1
            return eid
        }
    }

    public func remove(eventId: String) async throws {
        defer { notify() }
        try state.withLock { s in
            guard s.auth == .allowed, !s.failingWrites else { throw CalendarStoreError.refused("write refused") }
            if s.events.removeValue(forKey: eventId) != nil { s.removes += 1 }
        }
    }

    // MARK: - Для тестов: счётчики и руки человека

    /// Сколько раз записали и убрали событие с начала жизни подставки.
    public var writeCounts: (saves: Int, removes: Int) { state.withLock { ($0.saves, $0.removes) } }
    /// Сколько раз показали системное окно.
    public var accessRequests: Int { state.withLock { $0.requests } }
    public var allEvents: [StoredEvent] { state.withLock { $0.events.values.sorted { ($0.start, $0.id) < ($1.start, $1.id) } } }
    public var allCalendars: [StoredCalendar] { state.withLock { $0.calendars.values.sorted { $0.id < $1.id } } }

    /// Тест ставит «ворота»: чтение призраков ждёт их, прежде чем вернуть ответ.
    public func setReadGate(_ gate: (@Sendable () async -> Void)?) { state.withLock { $0.readGate = gate } }
    /// Сколько раз с начала жизни подставки спрашивали события календаря.
    public var eventReads: Int { state.withLock { $0.eventReads } }

    /// Человек подключил или завёл ещё один календарь (рабочий, «Сын», праздники, дни рождения).
    @discardableResult
    public func userAddCalendar(title: String, type: CalendarType = .account, source: String = "iCloud") -> String {
        let id = state.withLock { s -> String in
            let id = "cal-\(s.next)"; s.next += 1
            s.calendars[id] = StoredCalendar(id: id, title: title, sourceId: source.lowercased(), sourceTitle: source, type: type)
            return id
        }
        notify()
        return id
    }

    /// Человек выдал или отнял право в настройках iPhone.
    public func setAuthorization(_ a: CalendarAuthorization) { state.withLock { $0.auth = a } }
    public func setSourceRefusing(_ id: String, _ on: Bool) {
        state.withLock { if on { $0.refusing.insert(id) } else { $0.refusing.remove(id) } }
    }
    public func setNormalizingNotes(_ on: Bool) { state.withLock { $0.normalizingNotes = on } }
    public func setFailingWrites(_ on: Bool) { state.withLock { $0.failingWrites = on } }
    public func setFailingCalendarRemoval(_ on: Bool) { state.withLock { $0.failingCalendarRemoval = on } }
    public func setFailingRemoval(of id: String, _ on: Bool) { state.withLock { if on { $0.failingRemovalIds.insert(id) } else { $0.failingRemovalIds.remove(id) } } }

    /// Человек удалил событие в Календаре.
    public func userDeleteEvent(_ id: String) { state.withLock { $0.events[id] = nil }; notify() }
    /// Человек удалил календарь целиком.
    public func userDeleteCalendar(_ id: String) {
        state.withLock { s in
            s.calendars[id] = nil
            s.events = s.events.filter { $0.value.calendarId != id }
        }
        notify()
    }
    /// Человек переименовал или подвинул событие: правится любое поле. `modified` подставка ставит сама (часы
    /// подставки); closure может задать своё.
    public func userEdit(_ id: String, _ change: (inout StoredEvent) -> Void) {
        let now = clock()
        state.withLock { s in
            if var e = s.events[id] {
                e.modified = now
                change(&e)
                s.events[id] = e
            }
        }
        notify()
    }
    /// Человек завёл своё событие прямо в нашем календаре (или в чужом).
    @discardableResult
    public func userAdd(title: String, start: Date, end: Date, calendarId: String, url: URL? = nil,
                        allDay: Bool = false, offsetSeconds: Int = 0, location: String? = nil,
                        latitude: Double? = nil, longitude: Double? = nil, notes: String? = nil,
                        recurring: Bool = false, cancelled: Bool = false, repeating: Repeat? = nil,
                        invite: InviteResponse? = nil) -> String {
        let now = clock()
        defer { notify() }
        return state.withLock { s in
            let id = "ev-\(s.next)"; s.next += 1
            s.events[id] = StoredEvent(id: id, calendarId: calendarId, title: title, start: start, end: end,
                                       allDay: allDay, offsetSeconds: offsetSeconds, locationTitle: location,
                                       latitude: latitude, longitude: longitude, url: url, notes: notes,
                                       modified: now, recurring: recurring || repeating != nil, cancelled: cancelled)
            if let repeating { s.repeats[id] = repeating }
            if let invite { s.invites[id] = invite }
            return id
        }
    }
}
