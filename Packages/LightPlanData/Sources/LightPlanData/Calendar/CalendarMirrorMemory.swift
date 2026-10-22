import Foundation
import Synchronization

/// Что зеркало помнит о телефоне (шаг 30.1). Лежит на устройстве, а не в снимке съёмок: идентификаторы календаря и
/// событий у каждого телефона свои, а снимок общий с вебом, копией и (позже) облаком. Скопируй такую связь на
/// другой телефон — она будет указывать в пустоту.
public struct CalendarMirrorRecord: Codable, Equatable, Sendable {
    /// Человек включил зеркало. Остаётся включённым и тогда, когда система не даёт доступа: так тумблер знает, что
    /// сказать, и зеркало само продолжает, когда доступ вернули.
    public var wanted = false
    /// Идентификатор нашего календаря в базе телефона.
    public var calendarId: String?
    /// Учётная запись, которую выбрал человек (`nil` — календарь по умолчанию самого телефона).
    public var sourceId: String?
    /// Запись → событие: ключ записи (`lightplan://shoot/<id>`) и идентификатор события. Подсказка, а не истина:
    /// событие в нашем календаре находится и по ссылке внутри него.
    public var links: [String: String] = [:]

    public init() {}
}

public protocol CalendarMirrorMemory: AnyObject, Sendable {
    var record: CalendarMirrorRecord { get set }
}

/// Память на время запуска: тесты и снимки.
public final class InMemoryCalendarMemory: CalendarMirrorMemory, @unchecked Sendable {
    private let box: Mutex<CalendarMirrorRecord>
    public init(_ record: CalendarMirrorRecord = CalendarMirrorRecord()) { box = Mutex(record) }
    public var record: CalendarMirrorRecord {
        get { box.withLock { $0 } }
        set { box.withLock { $0 = newValue } }
    }
}

/// Память телефона: одна запись JSON в `UserDefaults`.
public final class DeviceCalendarMemory: CalendarMirrorMemory, @unchecked Sendable {
    public static let key = "lightplan.native.calendar.mirror"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var record: CalendarMirrorRecord {
        get { defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(CalendarMirrorRecord.self, from: $0) } ?? CalendarMirrorRecord() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.key) }
    }
}
