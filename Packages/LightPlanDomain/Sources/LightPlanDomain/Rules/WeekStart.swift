import Foundation
import LightPlanCore

/// С какого дня начинается неделя в сетках календаря (Алексей 28.10: «в настройках добавить, с какого дня начинается
/// неделя»). Веб жёстко держит понедельник, и он остаётся умолчанием — все пути без выбора идут через `.monday`.
/// Чистая арифметика дней, ни `Date`, ни `Calendar`: тот же счёт, что у `CivilDate`.
public enum WeekStart: String, CaseIterable, Sendable {
    case monday = "mon", sunday = "sun", saturday = "sat"

    /// День недели как `Date.getDay()` веба: 0 — воскресенье.
    public static func weekday(_ d: CivilDate) -> Int {
        // 1970-01-01 — четверг (4).
        ((d.daysSince1970 % 7) + 7 + 4) % 7
    }

    /// Суббота и воскресенье — всегда, с какого бы дня ни начиналась неделя (Алексей 28.10, «выходные»).
    public static func isWeekend(_ d: CivilDate) -> Bool {
        let w = weekday(d)
        return w == 0 || w == 6
    }

    /// Первый день недели как `getDay()`.
    public var first: Int {
        switch self { case .monday: 1; case .sunday: 0; case .saturday: 6 }
    }

    /// Номер колонки дня в неделе: 0 — первый день недели.
    public func column(of d: CivilDate) -> Int { (Self.weekday(d) - first + 7) % 7 }

    /// Первый день недели, в которую входит `d`.
    public func start(of d: CivilDate) -> CivilDate { d.adding(days: -column(of: d)) }

    public func week(of d: CivilDate) -> [CivilDate] {
        let s = start(of: d)
        return (0..<7).map { s.adding(days: $0) }
    }

    /// Сетка месяца: от первого дня недели, в которую входит 1-е число, до последнего дня недели последнего числа
    /// (веб `renderCal`: хвост прошлого месяца, месяц, голова следующего).
    public func grid(of month: CivilDate) -> [CivilDate] {
        let firstDay = CivilDate(year: month.year, month: month.month, day: 1)
        let lastDay = Self.nextMonth(firstDay).adding(days: -1)
        let from = start(of: firstDay)
        let to = start(of: lastDay).adding(days: 6)
        return (0...to.days(since: from)).map { from.adding(days: $0) }
    }

    /// Пустых клеток перед 1-м числом в сетке без хвостов (мини-месяцы года).
    public func leadingBlanks(year: Int, month: Int) -> Int {
        column(of: CivilDate(year: year, month: month, day: 1))
    }

    /// `getDay()` дней по колонкам шапки: понедельник — 1…6, 0; воскресенье — 0…6.
    public var weekdayOrder: [Int] { (0..<7).map { (first + $0) % 7 } }

    // MARK: Лента листания: номер недели от общей точки отсчёта

    /// Первый день недели, ближайший к 1970-01-01 (четвергу) вперёд: от него считаются номера недель.
    private var epoch: CivilDate { CivilDate(year: 1970, month: 1, day: 1).adding(days: (first - 4 + 7) % 7) }

    /// Номер недели дня: у недель одного дня подряд номера идут подряд, до 1970 года — отрицательные.
    public func index(of d: CivilDate) -> Int {
        let n = start(of: d).days(since: epoch)
        return n >= 0 ? n / 7 : (n - 6) / 7
    }

    /// Первый день недели с номером `index`.
    public func start(index: Int) -> CivilDate { epoch.adding(days: index * 7) }

    private static func nextMonth(_ first: CivilDate) -> CivilDate {
        first.month == 12 ? CivilDate(year: first.year + 1, month: 1, day: 1)
                          : CivilDate(year: first.year, month: first.month + 1, day: 1)
    }
}

/// Выбор в настройках. «Как в системе» читает первый день недели телефона (`Calendar.firstWeekday`: 1 — воскресенье,
/// 2 — понедельник, 7 — суббота); телефон с другим днём (пятница и т. п.) даёт понедельник — других начал у сеток нет.
public enum WeekStartChoice: String, CaseIterable, Sendable {
    case mon, sun, sat, auto

    /// Что действует при отсутствии выбора: понедельник, как у веба и как было до настройки.
    public static let standard: WeekStartChoice = .mon

    public func resolved(systemFirstWeekday: Int) -> WeekStart {
        switch self {
        case .mon: .monday
        case .sun: .sunday
        case .sat: .saturday
        case .auto:
            switch systemFirstWeekday { case 1: .sunday; case 7: .saturday; default: .monday }
        }
    }
}
