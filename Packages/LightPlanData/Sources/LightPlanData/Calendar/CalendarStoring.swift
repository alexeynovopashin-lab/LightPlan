import Foundation

/// Право приложения на календарь телефона (шаг 30.1).
///
/// Просим **полный** доступ, не «только запись» (`docs/14` предполагал запись; замер на iOS 26.5, шаг 30.1 —
/// `Tools/calendar_probe/`): под «только записью» система отдаёт один виртуальный календарь, свой завести
/// нельзя («That account does not allow calendars to be added»), а событие, которое сохранили, потом не
/// находится ни по идентификатору, ни по запросу — обновить и удалить его нельзя. Зеркало «создать, сдвинуть,
/// убрать» без чтения не работает.
public enum CalendarAuthorization: Sendable, Equatable {
    /// Ещё не спрашивали: спросить можно один раз.
    case notDetermined
    /// Отказали, ограничили или оставили только запись (её мало): спросить уже нельзя, выдаётся в настройках iPhone.
    case denied
    /// Полный доступ.
    case allowed
}

/// Откуда берётся календарь: учётная запись телефона (iCloud, Google, Exchange) или сам телефон.
public struct CalendarSource: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case local, account, exchange, other }

    public let id: String
    /// Имя так, как его показывает системный Календарь: «iCloud», «Gmail», «На моём iPhone».
    public let title: String
    public let kind: Kind

    public init(id: String, title: String, kind: Kind) {
        self.id = id
        self.title = title
        self.kind = kind
    }
}

/// Вид календаря в базе телефона (`EKCalendarType`, шаг 30.5): по нему решается, что личное, а что праздники и дни
/// рождения.
public enum CalendarType: String, Sendable, Hashable {
    /// На самом телефоне.
    case local
    /// iCloud, Google и другие учётные записи CalDAV.
    case account
    case exchange
    /// Подписка на чужой календарь (праздники, расписание матчей, «Найдено в программах»).
    case subscription
    /// «Дни рождения» из Контактов.
    case birthday
}

/// Календарь в базе телефона, как его видит приложение.
public struct StoredCalendar: Sendable, Hashable {
    public let id: String
    public let title: String
    public let sourceId: String
    public let sourceTitle: String
    public let type: CalendarType

    public init(id: String, title: String, sourceId: String, sourceTitle: String, type: CalendarType = .account) {
        self.id = id
        self.title = title
        self.sourceId = sourceId
        self.sourceTitle = sourceTitle
        self.type = type
    }
}

/// Событие, которое приложение хочет видеть в календаре: всё, что зеркалим, и ничего сверх (`docs/14`, «Поля события»).
/// Напоминаний нет. Заметки есть с шага 30.4: телефоны клиента и заметки съёмки (календарь личный — решение
/// Алексея 22.10.2026); суммы, предоплата и документы в календарь не едут.
public struct EventDraft: Sendable, Hashable {
    public var title: String
    public var start: Date
    public var end: Date
    /// На весь день: пояса у такого события нет, дни — по часам телефона.
    public var allDay: Bool
    /// Пояс места съёмки, имя IANA (или «GMT+7» у оценки по долготе); `nil` — зона задана только смещением.
    public var timeZoneId: String?
    /// Смещение пояса на момент начала, секунды: запасной путь, когда имени нет (перелёт, дорога из формы).
    public var offsetSeconds: Int
    /// «Парк, ул. Ленина 5».
    public var locationTitle: String?
    public var latitude: Double?
    public var longitude: Double?
    /// Ссылка обратно в запись, `lightplan://shoot/<id>`: единственный ключ, который лежит в самом событии.
    public var url: URL
    /// Заметки события: строки «Клиент: Ирина +7 …», потом заметки съёмки; `nil` — писать нечего.
    public var notes: String?
    /// Когда запись правили (`mt`, миллисекунды): спор «кто двигал позже — приложение или Календарь» решается им.
    public var recordModified: Int64?

    public init(title: String, start: Date, end: Date, allDay: Bool = false, timeZoneId: String? = nil,
                offsetSeconds: Int = 0, locationTitle: String? = nil, latitude: Double? = nil,
                longitude: Double? = nil, url: URL, notes: String? = nil, recordModified: Int64? = nil) {
        self.title = title; self.start = start; self.end = end; self.allDay = allDay
        self.timeZoneId = timeZoneId; self.offsetSeconds = offsetSeconds
        self.locationTitle = locationTitle; self.latitude = latitude; self.longitude = longitude
        self.url = url; self.notes = notes; self.recordModified = recordModified
    }

    /// Ключ записи — её ссылка целиком.
    public var key: String { url.absoluteString }

    /// Пояс для события: по имени, иначе по смещению.
    public var timeZone: TimeZone {
        timeZoneId.flatMap { TimeZone(identifier: $0) } ?? TimeZone(secondsFromGMT: offsetSeconds) ?? .gmt
    }
}

/// Событие, прочитанное из календаря.
public struct StoredEvent: Sendable, Hashable {
    public let id: String
    public let calendarId: String
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool
    /// Смещение пояса события на момент начала, секунды.
    public let offsetSeconds: Int
    public let locationTitle: String?
    public let latitude: Double?
    public let longitude: Double?
    public let url: URL?
    /// Заметки события, как их видит Календарь.
    public let notes: String?
    /// Когда событие правили в последний раз (`lastModifiedDate`); `nil` — база не сказала.
    public var modified: Date?
    /// Событие повторяется: его вхождения делят один идентификатор, поэтому такие события зеркало не трогает.
    public let recurring: Bool
    /// Отменено (приглашение отозвали): призраком не показывается.
    public let cancelled: Bool

    public init(id: String, calendarId: String, title: String, start: Date, end: Date, allDay: Bool,
                offsetSeconds: Int, locationTitle: String?, latitude: Double?, longitude: Double?, url: URL?,
                notes: String? = nil, modified: Date? = nil, recurring: Bool = false, cancelled: Bool = false) {
        self.cancelled = cancelled
        self.id = id; self.calendarId = calendarId; self.title = title; self.start = start; self.end = end
        self.allDay = allDay; self.offsetSeconds = offsetSeconds; self.locationTitle = locationTitle
        self.latitude = latitude; self.longitude = longitude; self.url = url
        self.notes = notes; self.modified = modified; self.recurring = recurring
    }

    /// Заметки сравниваются без концевых пробелов и по единым переводам строк: база может переложить `\r\n` в `\n`.
    static func normalized(_ notes: String?) -> String {
        (notes ?? "").replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Совпадает ли событие с тем, что должно стоять. Сравниваются только наши поля: напоминания, которые человек
    /// добавил сам, расхождением не считаются (`docs/14`: «мы это переживём»). Заметки — наше поле (30.4): правка
    /// заметки в Календаре в запись не возвращается, и событие перепишется как у нас.
    public func matches(_ d: EventDraft) -> Bool {
        guard title == d.title, allDay == d.allDay, url == d.url, Self.normalized(notes) == Self.normalized(d.notes) else { return false }
        return timeAndPlaceMatch(d)
    }

    /// То, что возвращается из Календаря в запись: время и место (30.4).
    public func timeAndPlaceMatch(_ d: EventDraft) -> Bool {
        guard allDay == d.allDay else { return false }
        if allDay {
            // «На весь день» система хранит по дням: конец последнего дня читается как 23:59:59 (замер на настоящем
            // EventKit), а мы кладём его начало. Сравниваются дни, а не секунды, иначе событие переписывалось бы
            // при каждом проходе.
            let cal = Calendar.current
            guard cal.isDate(start, inSameDayAs: d.start), cal.isDate(end, inSameDayAs: d.end) else { return false }
        } else {
            guard abs(start.timeIntervalSince(d.start)) < 1, abs(end.timeIntervalSince(d.end)) < 1 else { return false }
            if offsetSeconds != d.timeZone.secondsFromGMT(for: d.start) { return false }
        }
        guard (locationTitle ?? "") == (d.locationTitle ?? "") else { return false }
        return Self.close(latitude, d.latitude) && Self.close(longitude, d.longitude)
    }

    /// Координаты хранятся не точнее, чем их отдаёт система: до 1e-5 градуса (около метра).
    private static func close(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (x?, y?): abs(x - y) < 1e-5
        default: false
        }
    }
}

/// Время и место события так, как их в последний раз видели и зеркало, и Календарь (шаг 30.4). Лежит на устройстве
/// рядом со связью «запись → событие» и отвечает на один вопрос: кто двигал — приложение или человек в Календаре.
/// Событие, которое отличается от этого отпечатка, правили в Календаре; запись, которая отличается, — в приложении.
public struct EventFacts: Codable, Hashable, Sendable {
    public var start: Double
    public var end: Double
    public var allDay: Bool
    public var location: String
    public var latitude: Double?
    public var longitude: Double?

    public init(event e: StoredEvent) {
        (start, end) = Self.span(e.start, e.end, allDay: e.allDay)
        allDay = e.allDay
        location = e.locationTitle ?? ""; latitude = e.latitude; longitude = e.longitude
    }

    public init(draft d: EventDraft) {
        (start, end) = Self.span(d.start, d.end, allDay: d.allDay)
        allDay = d.allDay
        location = d.locationTitle ?? ""; latitude = d.latitude; longitude = d.longitude
    }

    /// «На весь день» система хранит по дням: конец последнего дня читается как 23:59:59, а мы кладём его начало
    /// (`StoredEvent.matches`). Поэтому у таких событий сравниваются дни — началами суток по часам телефона.
    private static func span(_ s: Date, _ e: Date, allDay: Bool) -> (Double, Double) {
        guard allDay else { return (s.timeIntervalSince1970, e.timeIntervalSince1970) }
        let cal = Calendar.current
        return (cal.startOfDay(for: s).timeIntervalSince1970, cal.startOfDay(for: e).timeIntervalSince1970)
    }

    /// Те же допуски, что у `StoredEvent.matches`: секунда во времени и 1e-5 градуса в координатах.
    public func isClose(to o: EventFacts) -> Bool {
        guard allDay == o.allDay, location == o.location, abs(start - o.start) < 1, abs(end - o.end) < 1 else { return false }
        func close(_ a: Double?, _ b: Double?) -> Bool {
            switch (a, b) {
            case (nil, nil): true
            case let (x?, y?): abs(x - y) < 1e-5
            default: false
            }
        }
        return close(latitude, o.latitude) && close(longitude, o.longitude)
    }
}

public enum CalendarStoreError: Error, Equatable, Sendable {
    /// Система отказала: учётная запись не берёт календари, закончилось место, нет права.
    case refused(String)
}

/// То, что зеркалу нужно от календарной базы телефона. Настоящая — `EventKitCalendarStore`, в тестах и снимках —
/// `InMemoryCalendarStore`.
public protocol CalendarStoring: Sendable {
    func authorization() async -> CalendarAuthorization
    /// Показать системный вопрос (полный доступ). `true` — разрешили.
    func requestAccess() async -> Bool
    /// Учётные записи, где можно завести календарь: без «Дней рождения» и подписок.
    func sources() async -> [CalendarSource]
    /// Куда телефон кладёт новые события по умолчанию (настройка «Календарь по умолчанию» в iOS).
    func defaultSourceId() async -> String?
    /// `nil` — такого календаря нет (его удалили руками).
    func calendar(id: String) async -> StoredCalendar?
    /// Календари с таким именем. Нужны, чтобы не завести второй «Light Plan», когда память потеряна (переустановка:
    /// у бесплатной подписи приложение переставляют раз в семь дней): прежний календарь со своими событиями
    /// принимается обратно.
    func calendars(titled title: String) async -> [StoredCalendar]
    /// Все календари событий, какие видит приложение, со своим видом (шаг 30.5, чужие календари призраками).
    func allCalendars() async -> [StoredCalendar]
    func createCalendar(title: String, sourceId: String) async throws -> StoredCalendar
    /// Вместе со всеми событиями в нём.
    func removeCalendar(id: String) async throws
    func events(calendarId: String, from: Date, to: Date) async -> [StoredEvent]
    /// По идентификатору события; `nil` — не найдено.
    func event(id: String) async -> StoredEvent?
    /// Завести событие (`replacing == nil`) или переписать наши поля у существующего. Возвращает идентификатор.
    func save(_ draft: EventDraft, replacing id: String?, calendarId: String) async throws -> String
    func remove(eventId: String) async throws
    /// Календарная база телефона изменилась (человек правил в Календаре, подтянулась синхронизация, мы сами записали):
    /// `EKEventStoreChanged`. Подписчик сверяется, но не чаще, чем нужно, — склеивает всплески сам.
    func changes() -> AsyncStream<Void>
}
