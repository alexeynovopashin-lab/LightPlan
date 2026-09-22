import Foundation

/// Календарный день: год, месяц, число. Без времени и без пояса.
///
/// Солнечная модель веба берёт номер дня через локальный `new Date(y, 0, 0)`,
/// и в поясе с переводом часов номер уезжает на сутки. Здесь день — просто три
/// числа, поэтому результат не зависит от зоны машины (итерация 7 плана).
/// Итерация 11 положит рядом `WallTime`, который несёт такую дату.
public struct CivilDate: Sendable, Hashable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Номер дня в году: 1 января — 1, 29 февраля високосного года — 60.
    /// Целочисленная арифметика, ни `Date`, ни `Calendar`.
    public var ordinal: Int {
        CivilDate.daysFromCivil(year, month, day) - CivilDate.daysFromCivil(year, 1, 1) + 1
    }

    /// Дни от 1970-01-01 по григорианскому календарю (алгоритм Хиннанта).
    static func daysFromCivil(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let yy = m <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Обратное преобразование: день от 1970-01-01 → год, месяц, число
    /// (тот же алгоритм Хиннанта, что и `daysFromCivil`, — пара с ним).
    static func civilFromDays(_ z: Int) -> (year: Int, month: Int, day: Int) {
        let z2 = z + 719_468
        let era = (z2 >= 0 ? z2 : z2 - 146_096) / 146_097
        let doe = z2 - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    /// День, отстоящий на `delta` календарных суток — вперёд или назад, с
    /// переходом через границы месяца и года. Порт приёма `new Date(y, m, d
    /// + offset)` веба (`moonArc`, `mwSkyAt`, `nextAstroNight`): там это делает
    /// сам `Date`, здесь — та же арифметика дней, что и `ordinal`.
    public func adding(days delta: Int) -> CivilDate {
        let (y, m, d) = CivilDate.civilFromDays(CivilDate.daysFromCivil(year, month, day) + delta)
        return CivilDate(year: y, month: m, day: d)
    }
}

/// Дни упорядочены по календарю: год, потом месяц, потом число.
extension CivilDate: Comparable {
    public static func < (a: CivilDate, b: CivilDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}
