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
        guard sun.polar == .normal else { return nil }
        switch (sun.rise, sun.set) {
        case (nil, nil): return nil
        case (_?, nil): return .dawn
        case (nil, _?): return .sunset
        case (_?, _?): return t < morningEnd(sun) ? .dawn : .sunset
        }
    }

    /// Конец утра — конец утреннего золотого часа; без него — полдень.
    public static func morningEnd(_ sun: SolarDay) -> Minutes { sun.goldenA ?? sun.solarNoon }
}

extension WeatherDay {
    /// Балл события: рассветный (`sunrise`) или закатный (`sunset`).
    public func score(_ e: SkyEvent) -> Int? { e == .dawn ? sunrise : sunset }

    /// Час события целиком: ярусы и влажность.
    public func layers(_ e: SkyEvent) -> HourRecord? { e == .dawn ? dawnLayers : layers }
}
