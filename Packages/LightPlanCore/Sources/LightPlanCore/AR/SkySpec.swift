import Foundation

/// Слои неба на экране AR — звёзды, созвездия, планеты, Млечный Путь — это инструмент планирования съёмки, а не копия
/// того, что видит глаз (слова Алексея 20.10): положение показывается всегда, днём и в городе тоже. Видимость глазом —
/// справка с числом и причиной (`SkyEyeNote`), а не условие рисования. Чтобы слои читались поверх дневного кадра, когда
/// выбран ночной момент, кадр камеры затемняется (`SkyMask`).

// MARK: - Справка о видимости

public enum SkyEyeNote {
    public enum Cause: Sendable, Equatable {
        /// Солнце не ниже −6°: небо светлое, звёзд и планет глазом нет.
        case daylight(sun: Degrees)
        /// Сумерки: солнце между −6° и −18°, видны не все.
        case twilight(sun: Degrees)
        /// Засветка атласа мешает: ступень (не «тёмное небо») и число (`ratio`).
        case glow(Glow.Level, value: Double)
    }

    /// Причины, по которым глазом видно не всё, на выбранный момент и место. Пусто — ничто не мешает. Те же пороги, что
    /// у Млечного Пути (`MilkyWayLook.twilight`, `Glow.level`), чтобы справки слоёв не расходились. Засветка `nil` —
    /// атлас молчит, о ней не пишем.
    public static func causes(sunAltitude: Degrees, glow: Double?) -> [Cause] {
        let tw = MilkyWayLook.twilight(sunAltitude: sunAltitude)
        if tw <= 0 { return [.daylight(sun: sunAltitude)] }
        var out: [Cause] = []
        if tw < 1 { out.append(.twilight(sun: sunAltitude)) }
        if let glow, let level = Glow.level(glow), level != .dark { out.append(.glow(level, value: glow)) }
        return out
    }
}

// MARK: - Затемняющая маска

/// Маска над кадром камеры и под слоями неба (слова Алексея 20.10: «крутим ползунок до ночного времени, маска появляется,
/// в действительное ночное время маска не появляется»).
///
/// Сила = темнота выбранного момента × (1 − темнота настоящего неба). Темнота неба — по высоте солнца: ноль при −6° и
/// выше, единица при −18° и ниже, между — гладкая ступень (`MilkyWayLook.twilight`). Настоящее небо — солнце сейчас
/// (часы и место телефона), а не экспозиция камеры. Кадр не доводится до чёрного: контуры зданий должны угадываться.
public enum SkyMask {
    /// Наибольшая непрозрачность чёрной маски: при полной силе остаётся `1 − maxOpacity` яркости кадра. Подобрана замером
    /// (`Tools/ar_mask.py`, запись в DECISIONS шага 29.8в.18).
    public static let maxOpacity = 0.70

    /// Темнота неба `0 … 1` при высоте солнца.
    public static func darkness(sunAltitude: Degrees) -> Double { MilkyWayLook.twilight(sunAltitude: sunAltitude) }

    /// Сила маски `0 … 1`.
    public static func strength(pickedSun: Degrees, nowSun: Degrees) -> Double {
        darkness(sunAltitude: pickedSun) * (1 - darkness(sunAltitude: nowSun))
    }

    /// Непрозрачность чёрной маски `0 … maxOpacity`.
    public static func opacity(pickedSun: Degrees, nowSun: Degrees) -> Double {
        strength(pickedSun: pickedSun, nowSun: nowSun) * maxOpacity
    }
}
