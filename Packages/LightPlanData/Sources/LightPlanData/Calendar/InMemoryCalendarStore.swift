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
        var next = 1
        var saves = 0
        var removes = 0
        var requests = 0
        /// Следующие записи событий отказывают: диск полон, учётная запись отвалилась.
        var failingWrites = false
    }

    private let state: Mutex<State>

    public init(authorization: CalendarAuthorization = .allowed, willGrant: Bool = true,
                sources: [CalendarSource] = [
                    CalendarSource(id: "icloud", title: "iCloud", kind: .account),
                    CalendarSource(id: "local", title: "На моём iPhone", kind: .local),
                ],
                defaultSource: String? = "icloud") {
        state = Mutex(State(auth: authorization, willGrant: willGrant, sources: sources, defaultSource: defaultSource))
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
        state.withLock { s in
            s.calendars[id] = nil
            s.events = s.events.filter { $0.value.calendarId != id }
        }
    }

    public func events(calendarId: String, from: Date, to: Date) async -> [StoredEvent] {
        state.withLock { s in
            guard s.auth == .allowed else { return [] }
            return s.events.values.filter { $0.calendarId == calendarId && $0.start < to && $0.end >= from }
                .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        }
    }

    public func event(id: String) async -> StoredEvent? { state.withLock { $0.auth == .allowed ? $0.events[id] : nil } }

    public func save(_ d: EventDraft, replacing id: String?, calendarId: String) async throws -> String {
        try state.withLock { s in
            guard s.auth == .allowed, !s.failingWrites else { throw CalendarStoreError.refused("write refused") }
            guard s.calendars[calendarId] != nil else { throw CalendarStoreError.refused("calendar is gone") }
            let eid: String
            if let id, s.events[id] != nil { eid = id } else { eid = "ev-\(s.next)"; s.next += 1 }
            s.events[eid] = StoredEvent(
                id: eid, calendarId: calendarId, title: d.title, start: d.start, end: d.end, allDay: d.allDay,
                offsetSeconds: d.allDay ? 0 : d.timeZone.secondsFromGMT(for: d.start),
                locationTitle: d.locationTitle, latitude: d.latitude, longitude: d.longitude, url: d.url)
            s.saves += 1
            return eid
        }
    }

    public func remove(eventId: String) async throws {
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

    /// Человек выдал или отнял право в настройках iPhone.
    public func setAuthorization(_ a: CalendarAuthorization) { state.withLock { $0.auth = a } }
    public func setSourceRefusing(_ id: String, _ on: Bool) {
        state.withLock { if on { $0.refusing.insert(id) } else { $0.refusing.remove(id) } }
    }
    public func setFailingWrites(_ on: Bool) { state.withLock { $0.failingWrites = on } }

    /// Человек удалил событие в Календаре.
    public func userDeleteEvent(_ id: String) { state.withLock { $0.events[id] = nil } }
    /// Человек удалил календарь целиком.
    public func userDeleteCalendar(_ id: String) {
        state.withLock { s in
            s.calendars[id] = nil
            s.events = s.events.filter { $0.value.calendarId != id }
        }
    }
    /// Человек переименовал или подвинул событие: правится любое поле.
    public func userEdit(_ id: String, _ change: (inout StoredEvent) -> Void) {
        state.withLock { s in if var e = s.events[id] { change(&e); s.events[id] = e } }
    }
    /// Человек завёл своё событие прямо в нашем календаре (или в чужом).
    @discardableResult
    public func userAdd(title: String, start: Date, end: Date, calendarId: String, url: URL? = nil) -> String {
        state.withLock { s in
            let id = "ev-\(s.next)"; s.next += 1
            s.events[id] = StoredEvent(id: id, calendarId: calendarId, title: title, start: start, end: end,
                                       allDay: false, offsetSeconds: 0, locationTitle: nil, latitude: nil,
                                       longitude: nil, url: url)
            return id
        }
    }
}
