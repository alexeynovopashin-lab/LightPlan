import Foundation

/// Момент — абсолютная точка на оси времени, миллисекунды от 1970-01-01 UTC
/// (`docs/16`, `docs/17` § 5).
///
/// Сравнивают всегда моменты: накладки, дорогу, фазы события, «сейчас»,
/// таймер аренды. Показывают — настенное время места (`WallTime`).
///
/// Целые миллисекунды, как у `Date.UTC` в вебе: смещения поясов кратны
/// четверти часа (у исторических зон — минуте), и «день + минуты − смещение»
/// выходит целым числом без округления.
public struct Moment: Sendable, Hashable, Comparable {
    public let milliseconds: Int64

    public init(milliseconds: Int64) {
        self.milliseconds = milliseconds
    }

    public init(_ date: Date) {
        milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    public var date: Date { Date(timeIntervalSince1970: Double(milliseconds) / 1000) }

    public static func < (a: Moment, b: Moment) -> Bool { a.milliseconds < b.milliseconds }

    /// Сдвиг на минуты.
    public func adding(minutes: Int) -> Moment {
        Moment(milliseconds: milliseconds + Int64(minutes) * 60_000)
    }

    /// Минуты от `other` до этого момента, как `Math.round((a − b) / 60000)`
    /// веба: половина округляется вверх, в том числе у отрицательных.
    public func minutes(since other: Moment) -> Int {
        let diff = milliseconds - other.milliseconds
        return Int((Double(diff) / 60_000 + 0.5).rounded(.down))
    }
}

/// Настенное время: день плюс минуты от его полуночи — то, о чём
/// договорились с клиентом, «10 сентября, 18:00» (`docs/16`).
///
/// Правда договорённости, и она не едет, когда фотограф улетел в другой пояс,
/// поэтому хранение в UTC отвергнуто. Минуты бывают больше 1 440: точка
/// маршрута второго дня съёмки считается от полуночи первого (DECISIONS,
/// «Точка маршрута знает свой день»), и меньше нуля — у хвоста из вчера.
public struct WallTime: Sendable, Hashable {
    public let day: CivilDate
    public let minutes: Int

    public init(day: CivilDate, minutes: Int) {
        self.day = day
        self.minutes = minutes
    }

    /// Момент при смещении пояса места в часах (веб `momentOf`):
    /// `Date.UTC(день) + минуты · 60000 − смещение · 3600000`.
    ///
    /// Смещение одно на всю запись — на её день, даже когда минуты уходят за
    /// полночь в сутки с другим смещением: так считает веб, и так же солнце
    /// итерации 7 (одно смещение на сутки, корзина 3, пункт 15).
    public func moment(utcOffsetHours: Double) -> Moment {
        let base = Int64(day.daysSince1970) * 86_400_000 + Int64(minutes) * 60_000
        return Moment(milliseconds: base - Int64((utcOffsetHours * 3_600_000).rounded()))
    }

    /// Момент в зоне места: смещение берётся на начало этого дня
    /// (`ZoneID.utcOffsetHours(on:)`).
    public func moment(in zone: ZoneID) -> Moment {
        moment(utcOffsetHours: zone.utcOffsetHours(on: day))
    }

    /// Настенные часы места в данный момент: день и минута суток (веб `nowAt`,
    /// дальше `getHours() · 60 + getMinutes()`). Секунды отбрасываются, как у
    /// веба: «сейчас 10:00» длится всю минуту.
    public init(moment: Moment, utcOffsetHours: Double) {
        let local = moment.milliseconds + Int64((utcOffsetHours * 3_600_000).rounded())
        let days = WallTime.floorDiv(local, 86_400_000)
        let rest = local - days * 86_400_000
        self.day = CivilDate(daysSince1970: Int(days))
        self.minutes = Int(rest / 60_000)
    }

    static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }
}

/// Счёт дней: день записи, сутки сдачи, дни многодневной занятости. Соседний
/// день (`adding(days:)`) и обратный ход Хиннанта (`civilFromDays`) завела
/// итерация 10 — здесь то, что нужно моменту и домену сверх них.
extension CivilDate {
    /// Дни от 1970-01-01 по григорианскому календарю.
    public var daysSince1970: Int {
        CivilDate.daysFromCivil(year, month, day)
    }

    /// День по номеру от 1970-01-01.
    public init(daysSince1970 z: Int) {
        let (y, m, d) = CivilDate.civilFromDays(z)
        self.init(year: y, month: m, day: d)
    }

    /// Сколько дней от `other` до этого дня (веб `dayDiff(this, other)`).
    public func days(since other: CivilDate) -> Int {
        daysSince1970 - other.daysSince1970
    }
}
