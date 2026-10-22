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

/// Календарь в базе телефона, как его видит приложение.
public struct StoredCalendar: Sendable, Hashable {
    public let id: String
    public let title: String
    public let sourceId: String
    public let sourceTitle: String

    public init(id: String, title: String, sourceId: String, sourceTitle: String) {
        self.id = id
        self.title = title
        self.sourceId = sourceId
        self.sourceTitle = sourceTitle
    }
}

/// Событие, которое приложение хочет видеть в календаре: всё, что зеркалим, и ничего сверх (`docs/14`, «Поля события»).
/// Напоминаний нет, заметок нет: телефон клиента, суммы и документы в календарь не едут.
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

    public init(title: String, start: Date, end: Date, allDay: Bool = false, timeZoneId: String? = nil,
                offsetSeconds: Int = 0, locationTitle: String? = nil, latitude: Double? = nil,
                longitude: Double? = nil, url: URL) {
        self.title = title; self.start = start; self.end = end; self.allDay = allDay
        self.timeZoneId = timeZoneId; self.offsetSeconds = offsetSeconds
        self.locationTitle = locationTitle; self.latitude = latitude; self.longitude = longitude
        self.url = url
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

    public init(id: String, calendarId: String, title: String, start: Date, end: Date, allDay: Bool,
                offsetSeconds: Int, locationTitle: String?, latitude: Double?, longitude: Double?, url: URL?) {
        self.id = id; self.calendarId = calendarId; self.title = title; self.start = start; self.end = end
        self.allDay = allDay; self.offsetSeconds = offsetSeconds; self.locationTitle = locationTitle
        self.latitude = latitude; self.longitude = longitude; self.url = url
    }

    /// Совпадает ли событие с тем, что должно стоять. Сравниваются только наши поля: напоминания и заметки, которые
    /// человек добавил сам, расхождением не считаются (`docs/14`: «мы это переживём»).
    public func matches(_ d: EventDraft) -> Bool {
        guard title == d.title, allDay == d.allDay, url == d.url else { return false }
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
    func createCalendar(title: String, sourceId: String) async throws -> StoredCalendar
    /// Вместе со всеми событиями в нём.
    func removeCalendar(id: String) async throws
    func events(calendarId: String, from: Date, to: Date) async -> [StoredEvent]
    /// По идентификатору события; `nil` — не найдено.
    func event(id: String) async -> StoredEvent?
    /// Завести событие (`replacing == nil`) или переписать наши поля у существующего. Возвращает идентификатор.
    func save(_ draft: EventDraft, replacing id: String?, calendarId: String) async throws -> String
    func remove(eventId: String) async throws
}
