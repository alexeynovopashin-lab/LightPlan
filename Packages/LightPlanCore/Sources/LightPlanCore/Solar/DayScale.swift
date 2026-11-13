import Foundation

/// Шкала времени ползунка: какой отрезок суток он показывает и какие на нём риски и цифры (30з.4).
///
/// - `.calendar` — шкала всех экранов с ползунком: «Свет», «Карта» (общий таймбар приложения) и AR (30з.4, слово Алексея 13.11: «да переводи»). Календарные сутки выбранного дня и по часу живого времени
///   с каждой стороны: от 23:00 предыдущего дня до 01:00 следующего, **26 часов, одинаково в любом городе и в любое время года**
///   (слово Алексея 13.11: «шкала суток 0–24», «по одной риске слева и справа… палец упирается в край экрана или чехла, нужен
///   зазор», зазор — «живое время»). Окно не зависит от солнца вовсе.
/// - `.solar` — шкала прежних суток: истинный полдень ± 12 ч (`SolarDay.mint…maxt`, как в вебе). **Ни у одного экрана её больше нет**; осталась
///   только умолчанием `TimelineMachine` для старых тестов механики взвода (окно у них считано по солнцу). Новому коду она не нужна.
///
/// Минуты — от полуночи **выбранного дня** по часам места (как везде): −60 — это 23:00 предыдущего дня, 1500 — 01:00 следующего.
public enum DayScale: Sendable, Equatable {
    case solar
    case calendar

    /// Окно календарной шкалы: час до полуночи выбранного дня и час после следующей.
    public static let calendarStart: Minutes = -60
    public static let calendarEnd: Minutes = 1500

    /// Окно шкалы для суток `day`: у календарной не зависит от суток, у солнечной — `mint…maxt`.
    public func window(for day: SolarDay) -> (start: Minutes, end: Minutes) {
        switch self {
        case .calendar: return (Self.calendarStart, Self.calendarEnd)
        case .solar: return (day.mint, day.maxt)
        }
    }

    /// Ярус риски: длина и вес. Календарная шкала рисует три яруса, солнечная — два (`long`, `short`).
    public enum Tier: Int, Sendable, Equatable {
        case short, medium, long
    }

    /// Риска шкалы; `hour` — час цифры над ней (0…24), если она есть. Цифра и риска — одна метка, поэтому цифра всегда над своей риской.
    /// Как цифру писать, решает экран (24 часа: `digit`; 12 часов: `ClockText.scaleLabel`) — шкала не знает про часы пользователя.
    public struct Mark: Sendable, Equatable {
        public let minute: Minutes
        public let tier: Tier
        public let hour: Int?
        /// Цифра по 24-часовому счёту: 0, 3, … 24 (у солнечной шкалы — час по модулю суток).
        public var digit: String? { hour.map(String.init) }
    }

    /// Все метки в окне `start…end`, слева направо.
    ///
    /// Календарная: риска каждый час, включая оба края (23:00 и 01:00); длинные под 0, 6, 12, 18, 24, средние под 3, 9, 15, 21,
    /// короткие на остальных часах; цифры 0, 3, 6, … 24 над рисками длинных и средних ярусов, над краевыми часами цифр нет.
    /// Солнечная — как было до 30з.4: риски по настенным часам (`h·60`, h от 0 до 47) там, где час лежит в окне, длинная каждые
    /// шесть часов; цифра каждые три часа, час по модулю суток.
    public func marks(start: Minutes, end: Minutes) -> [Mark] {
        switch self {
        case .calendar:
            return Self.hours(from: -1, through: 25).compactMap { h -> Mark? in
                let t = Minutes(h * 60)
                guard t >= start, t <= end else { return nil }
                let long = h % 6 == 0, medium = h % 3 == 0
                return Mark(minute: t, tier: long ? .long : medium ? .medium : .short,
                            hour: medium && h >= 0 && h <= 24 ? h : nil)
            }
        case .solar:
            return (0..<48).compactMap { h -> Mark? in
                let t = Minutes(h * 60)
                guard t >= start, t <= end else { return nil }
                return Mark(minute: t, tier: h % 6 == 0 ? .long : .short, hour: h % 3 == 0 ? h % 24 : nil)
            }
        }
    }

    private static func hours(from a: Int, through b: Int) -> [Int] { Array(a...b) }

    /// Доля окна `start…end`, на которой стоит минута `t`: 0 у левого края, 1 у правого; за краем прижимается.
    public static func fraction(of t: Minutes, start: Minutes, end: Minutes) -> Double {
        let span = end - start
        guard span > 0 else { return 0 }
        return min(max((t - start) / span, 0), 1)
    }

    /// Минута, лежащая на доле `f` окна `start…end` (обратное к `fraction`).
    public static func minute(at f: Double, start: Minutes, end: Minutes) -> Minutes {
        start + min(max(f, 0), 1) * (end - start)
    }
}
