import Foundation

/// Событие неба, о котором говорит верх «Света» (31.5, Алексей 18.11: «приложение не про закаты, оно про свет, закаты и
/// рассветы равнозначны»; «до конца рассвета не переключаемся на закат… после окончания рассвета (рассветный золотой час тоже
/// учитываем), переключаемся на расчет заката для того же дня»).
public enum SkyEvent: String, Sendable, Equatable, CaseIterable {
    case dawn, sunset

    /// Событие минуты `t` суток `sun`: до конца утреннего золотого часа (`goldenA`, солнце +6°) — рассвет, дальше — закат тех же
    /// суток. Солнце за день не поднимается до +6° (зима за полярным кругом) — рассвет до полудня. Полярный день и ночь — `nil`:
    /// ни восхода, ни заката нет, говорить не о чем. Сутки, где есть восход, но нет заката (или наоборот), — то, что есть.
    public static func at(_ t: Minutes, sun: SolarDay) -> SkyEvent? {
        pick(t, rise: sun.rise, set: sun.set, morningEnd: morningEnd(sun), polar: sun.polar)
    }

    /// То же правило на любой шкале времени (31.5б): минуты суток у экранов, моменты (`Date`) у виджета, который знает свет дня
    /// только моментами (`WidgetFeed.DayLight`). Одно место выбора — у «Света» и у виджета не может разойтись.
    public static func pick<T: Comparable>(_ t: T, rise: T?, set: T?, morningEnd: T, polar: SolarDay.PolarState) -> SkyEvent? {
        guard polar == .normal else { return nil }
        switch (rise, set) {
        case (nil, nil): return nil
        case (_?, nil): return .dawn
        case (nil, _?): return .sunset
        case (_?, _?): return t < morningEnd ? .dawn : .sunset
        }
    }

    /// Событие знака дня (31.5б, Алексей 18.11 «Да, все «б»»: «до полудня по рассвету, после — по закату»): знак и цвет дня в
    /// планировщике и на ленте «Света» до 12:00 по часам места смотрят на небо рассвета, после — на небо заката. Минута — «сейчас»,
    /// не выбранная: у дня нет своей минуты, а знаки всех дней на экране меняются разом.
    public static func ofDay(nowMinute: Minutes) -> SkyEvent { nowMinute < 12 * 60 ? .dawn : .sunset }

    /// Конец утра — конец утреннего золотого часа; без него — полдень.
    public static func morningEnd(_ sun: SolarDay) -> Minutes { sun.goldenA ?? sun.solarNoon }
}

extension WeatherDay {
    /// Балл события: рассветный (`sunrise`) или закатный (`sunset`).
    public func score(_ e: SkyEvent) -> Int? { e == .dawn ? sunrise : sunset }

    /// Час события целиком: ярусы и влажность.
    public func layers(_ e: SkyEvent) -> HourRecord? { e == .dawn ? dawnLayers : layers }

    /// Небо события: `dawnQuality` у рассвета, категория дня у заката.
    public func quality(_ e: SkyEvent) -> DayQuality { e == .dawn ? dawnQuality : quality }

    /// Осадки в окне события.
    public func precip(_ e: SkyEvent) -> Precip? { e == .dawn ? dawnPrecip : precip }

    /// Тренд облачности к окну события (31.6: искра и «затягивает / проясняется» под отсчётом): у рассвета — часы вокруг восхода.
    public func trend(_ e: SkyEvent) -> [Double] { e == .dawn ? dawnTrend : trend }
}
