import CoreLocation
import EventKit
import Foundation

/// Настоящий календарь телефона: `EKEventStore` (шаг 30.1).
///
/// Всё, что трогает `EKEventStore`, идёт по одной последовательной очереди: объекты EventKit привязаны к своему
/// хранилищу и не любят, когда их дёргают из нескольких потоков.
public final class EventKitCalendarStore: CalendarStoring, @unchecked Sendable {

    nonisolated(unsafe) private let store = EKEventStore()
    private let queue = DispatchQueue(label: "lightplan.calendar.eventkit")

    public init() {}

    private func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async { cont.resume(with: Result { try body() }) }
        }
    }

    private func read<T: Sendable>(_ fallback: T, _ body: @escaping @Sendable () throws -> T) async -> T {
        (try? await run(body)) ?? fallback
    }

    // MARK: - Право

    public func authorization() async -> CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .allowed
        // «Только запись» — мало: под ней нельзя ни завести календарь, ни найти своё событие.
        case .writeOnly, .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    public func requestAccess() async -> Bool {
        await withCheckedContinuation { cont in
            store.requestFullAccessToEvents { granted, _ in cont.resume(returning: granted) }
        }
    }

    // MARK: - Учётные записи и календари

    private static func kind(_ t: EKSourceType) -> CalendarSource.Kind {
        switch t {
        case .local: .local
        case .calDAV, .mobileMe: .account
        case .exchange: .exchange
        default: .other
        }
    }

    public func sources() async -> [CalendarSource] {
        await read([]) { [self] in
            store.sources
                .filter { [.local, .calDAV, .mobileMe, .exchange].contains($0.sourceType) }
                .map { CalendarSource(id: $0.sourceIdentifier, title: $0.title, kind: Self.kind($0.sourceType)) }
                .sorted { ($0.kind.rawValue, $0.title) < ($1.kind.rawValue, $1.title) }
        }
    }

    public func defaultSourceId() async -> String? {
        await read(nil) { [self] in store.defaultCalendarForNewEvents?.source?.sourceIdentifier }
    }

    private static func type(_ t: EKCalendarType) -> CalendarType {
        switch t {
        case .local: .local
        case .calDAV: .account
        case .exchange: .exchange
        case .subscription: .subscription
        case .birthday: .birthday
        @unknown default: .account
        }
    }

    private static func stored(_ c: EKCalendar) -> StoredCalendar {
        StoredCalendar(id: c.calendarIdentifier, title: c.title, sourceId: c.source?.sourceIdentifier ?? "",
                       sourceTitle: c.source?.title ?? "", type: type(c.type))
    }

    public func allCalendars() async -> [StoredCalendar] {
        await read([]) { [self] in
            store.calendars(for: .event).map(Self.stored).sorted { ($0.sourceTitle, $0.title, $0.id) < ($1.sourceTitle, $1.title, $1.id) }
        }
    }

    public func calendar(id: String) async -> StoredCalendar? {
        await read(nil) { [self] in store.calendar(withIdentifier: id).map(Self.stored) }
    }

    public func calendars(titled title: String) async -> [StoredCalendar] {
        await read([]) { [self] in
            store.calendars(for: .event).filter { $0.title == title && $0.allowsContentModifications }
                .map(Self.stored).sorted { $0.id < $1.id }
        }
    }

    public func createCalendar(title: String, sourceId: String) async throws -> StoredCalendar {
        try await run { [self] in
            guard let source = store.sources.first(where: { $0.sourceIdentifier == sourceId }) else {
                throw CalendarStoreError.refused("source \(sourceId) is gone")
            }
            let c = EKCalendar(for: .event, eventStore: store)
            c.title = title
            c.source = source
            do { try store.saveCalendar(c, commit: true) } catch { throw CalendarStoreError.refused(error.localizedDescription) }
            return Self.stored(c)
        }
    }

    public func removeCalendar(id: String) async throws {
        try await run { [self] in
            guard let c = store.calendar(withIdentifier: id) else { return }
            do { try store.removeCalendar(c, commit: true) } catch { throw CalendarStoreError.refused(error.localizedDescription) }
        }
    }

    // MARK: - События

    private static func stored(_ e: EKEvent) -> StoredEvent? {
        guard let id = e.eventIdentifier, let cal = e.calendar else { return nil }
        let zone = e.timeZone ?? .current
        let geo = e.structuredLocation?.geoLocation?.coordinate
        return StoredEvent(
            id: id, calendarId: cal.calendarIdentifier, title: e.title ?? "", start: e.startDate, end: e.endDate,
            allDay: e.isAllDay, offsetSeconds: zone.secondsFromGMT(for: e.startDate),
            locationTitle: e.structuredLocation?.title, latitude: geo?.latitude, longitude: geo?.longitude, url: e.url,
            notes: e.notes, modified: e.lastModifiedDate, recurring: e.hasRecurrenceRules,
            cancelled: e.status == .canceled)
    }

    public func events(calendarId: String, from: Date, to: Date) async -> [StoredEvent] {
        await read([]) { [self] in
            guard let cal = store.calendar(withIdentifier: calendarId) else { return [] }
            // Запрос EventKit не берёт больше четырёх лет сразу: длинный отрезок режем на куски поменьше.
            let step: TimeInterval = 3 * 365 * 86_400
            var out: [StoredEvent] = []
            var a = from
            while a < to {
                let b = min(a.addingTimeInterval(step), to)
                let p = store.predicateForEvents(withStart: a, end: b, calendars: [cal])
                out += store.events(matching: p).compactMap(Self.stored)
                a = b
            }
            // Событие на стыке кусков приходит дважды.
            return Array(Dictionary(out.map { ($0.id + "|\($0.start.timeIntervalSince1970)", $0) },
                                    uniquingKeysWith: { x, _ in x }).values)
        }
    }

    public func event(id: String) async -> StoredEvent? {
        await read(nil) { [self] in store.event(withIdentifier: id).flatMap(Self.stored) }
    }

    public func save(_ d: EventDraft, replacing id: String?, calendarId: String) async throws -> String {
        try await run { [self] in
            guard let cal = store.calendar(withIdentifier: calendarId) else {
                throw CalendarStoreError.refused("calendar \(calendarId) is gone")
            }
            let e = id.flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
            e.calendar = cal
            e.title = d.title
            e.isAllDay = d.allDay
            e.timeZone = d.allDay ? nil : d.timeZone
            e.startDate = d.start
            e.endDate = d.end
            // «Занят»: ради этого половина затеи — глядя на свой календарь, человек видит, что день не свободен.
            if cal.supportedEventAvailabilities.contains(.busy) { e.availability = .busy }
            e.url = d.url
            // Заметки — наше поле: телефон клиента и заметки съёмки; без них поле чистится.
            e.notes = d.notes
            if let title = d.locationTitle {
                let loc = EKStructuredLocation(title: title)
                if let la = d.latitude, let lo = d.longitude { loc.geoLocation = CLLocation(latitude: la, longitude: lo) }
                e.structuredLocation = loc
            } else {
                e.structuredLocation = nil
            }
            // Напоминаний не ставим (у приложения свои), а чужие — человека — не трогаем.
            do { try store.save(e, span: .thisEvent, commit: true) } catch { throw CalendarStoreError.refused(error.localizedDescription) }
            guard let out = e.eventIdentifier else { throw CalendarStoreError.refused("no identifier after save") }
            return out
        }
    }

    /// `EKEventStoreChanged` приходит и на наши собственные записи, и на правки в Календаре, и на синхронизацию
    /// iCloud; всплески склеивает подписчик.
    public func changes() -> AsyncStream<Void> {
        AsyncStream { cont in
            nonisolated(unsafe) let token = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { _ in
                cont.yield()
            }
            cont.onTermination = { _ in NotificationCenter.default.removeObserver(token) }
        }
    }

    public func remove(eventId: String) async throws {
        try await run { [self] in
            guard let e = store.event(withIdentifier: eventId) else { return }
            do { try store.remove(e, span: .thisEvent, commit: true) } catch { throw CalendarStoreError.refused(error.localizedDescription) }
        }
    }
}
