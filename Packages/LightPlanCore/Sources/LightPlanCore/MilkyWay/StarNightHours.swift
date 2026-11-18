import Foundation

/// Часы ночи даты D для «Звёзд» (31.6в, Алексей 18.11: «1Б, но надо учитывать работу приложения во всех городах, местах»): где
/// облака «Звёзд» смотрят, если время съёмки не назвал человек. Ночь D — от солнечного полудня D до полудня D+1, на шкале D
/// (минуты за полночь — больше 1440): вечер D и утро D+1. Утро самой D — хвост прошлой ночи, ему здесь не место.
///
/// Порядок: окно Млечного Пути этой ночи (`MilkyWayWindow`, то же окно, что у строки «Звёзды» карточки), нет окна — темнота
/// (солнце ниже −18°). Не темнеет вовсе (белые ночи, полярный день) — пусто: облака не судятся, первой стоит «недостаточно темно».
public enum StarNightHours {

    /// Окно, иначе темнота; пусто — ни того, ни другого.
    public static func hours(date: CivilDate, place: Place) -> [ClosedRange<Minutes>] {
        let w = milkyWay(date: date, place: place)
        if !w.isEmpty { return w }
        return dark(date: date, place: place).map { [$0] } ?? []
    }

    /// Окно Млечного Пути ночи D: вечерние отрезки D (с полудня) и утренние D+1 (до полудня), сшитые через полночь
    /// (шаг окна 5 мин), как сшивает их строка «Звёзды» карточки (`NightLight.stars`).
    public static func milkyWay(date: CivilDate, place: Place) -> [ClosedRange<Minutes>] {
        let next = date.adding(days: 1)
        let noon = SolarDay(date: date, place: place).solarNoon
        let nextNoon = SolarDay(date: next, place: place).solarNoon
        let evening = MilkyWayWindow(date: date, place: place).spans.filter { $0.from >= noon }.map { $0.from...$0.to }
        let morning = MilkyWayWindow(date: next, place: place).spans.filter { $0.to <= nextNoon }
            .map { ($0.from + 1440)...($0.to + 1440) }
        var out: [ClosedRange<Minutes>] = []
        for r in (evening + morning).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = out.last, r.lowerBound - last.upperBound <= 5 {
                out[out.count - 1] = last.lowerBound...max(last.upperBound, r.upperBound)
            } else {
                out.append(r)
            }
        }
        return out
    }

    /// Темнота ночи D: солнце ниже −18° между полуднем D и полуднем D+1, края — до минуты. Считается прямо по высоте солнца,
    /// а не по вечернему переходу −18°: в начале мая и в середине августа на 50–60° темнота начинается после полуночи, и
    /// вечернего перехода у D нет (`SolarDay.astroB` пуст), а темно бывает. Солнце ниже −18° весь промежуток (дальше 84,5° с. ш.
    /// зимой; посёлков там нет) — 12 часов вокруг самого низкого солнца, а не сутки. Не темнеет — `nil`.
    public static func dark(date: CivilDate, place: Place) -> ClosedRange<Minutes>? {
        let sun = SolarDay(date: date, place: place), next = SolarDay(date: date.adding(days: 1), place: place)
        func elevation(_ x: Minutes) -> Degrees { x < 1440 ? sun.elevation(at: x) : next.elevation(at: x - 1440) }
        func dark(_ x: Minutes) -> Bool { elevation(x) <= -18 }
        let from = sun.solarNoon, to = next.solarNoon + 1440
        var first: Minutes?, last: Minutes?
        var lowest = (minute: from, elevation: Degrees.infinity)
        var x = from
        while x <= to {
            let e = elevation(x)
            if e < lowest.elevation { lowest = (x, e) }
            if e <= -18 {
                if first == nil { first = x }
                last = x
            }
            x += 5
        }
        guard var a = first, var b = last else { return nil }
        if a <= from && b + 5 > to { return (lowest.minute - 360)...(lowest.minute + 360) }
        while a - 1 >= from && dark(a - 1) { a -= 1 }
        while b + 1 <= to && dark(b + 1) { b += 1 }
        return a...b
    }
}
