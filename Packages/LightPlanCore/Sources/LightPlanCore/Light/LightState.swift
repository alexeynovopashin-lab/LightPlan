import Foundation

/// Код состояния света. Пятнадцать, ни одним больше: пять веток `stateAt`
/// дают по два кода — утренний и вечерний. Сырое значение — ключ веба, он же
/// середина ключей словаря `sun.<код>.label|sense|light|rec`.
public enum LightCode: String, Sendable, CaseIterable {
    case noon, morning, day, morningWarm, evening, golden
    case dawn, sunset, dawning, dusk, blue, deepDusk
    case astroDawn, astroDusk, astroNight
}

/// Тон состояния: как оценивается свет для съёмки. `stars` — небо ночное,
/// уровня прибора нет.
public enum LightTone: String, Sendable {
    case neutral, good, excellent, stars
}

/// Состояние света в одну минуту одного дня.
///
/// Порт `stateAt` из `light_plan:Light_Plan/beta/index.html`. Слова состояния
/// (`label`, `sense`, `light`, `rec`) сюда не входят: состояние выбирает высота
/// солнца, а она от языка не зависит; слова приходят из словаря по `code`
/// (итерация 14).
public struct LightState: Sendable, Equatable {
    public let code: LightCode
    /// Деления экспонометра 1…5. `nil` у астрономических сумерек и ночи —
    /// прибор там не показывает уровень (в вебе `level` не задан).
    public let level: Int?
    public let tone: LightTone
    /// Сила зарева, доля.
    public let glow: Double
    /// Цвет неба на этой высоте.
    public let color: SkyColor
    /// Звёзды видны.
    public let stars: Bool

    /// Состояние по высоте светила. `morning` — минута до солнечного полудня.
    ///
    /// Пороги — физика продукта. **6.05, а не 6:** граница золотого часа
    /// считается по +6°, и на самом стыке погрешность float иначе показывает
    /// «вечереет» вместо золотого часа (веб, 7534). Допуск намеренный, его
    /// защищает тест `goldenHourTolerance`.
    public init(elevation e: Degrees, morning: Bool) {
        let color = LightPalette.skyColor(elevation: e)
        func make(_ code: LightCode, _ glow: Double, _ level: Int?, _ tone: LightTone, stars: Bool = false) -> LightState {
            LightState(code: code, level: level, tone: tone, glow: glow, color: color, stars: stars)
        }
        let state: LightState
        if e >= -0.833 {
            if e > 40 {
                state = make(.noon, 0.05, 2, .neutral)
            } else if e > 20 {
                state = make(morning ? .morning : .day, 0.08, 3, .good)
            } else if e > 6.05 {
                state = make(morning ? .morningWarm : .evening, 0.16, 4, .good)
            } else {
                state = make(.golden, 0.34, 5, .excellent)
            }
        } else {
            let d = -e
            if d < 1.8 {
                state = make(morning ? .dawn : .sunset, 0.34, 5, .excellent)
            } else if d < 4 {
                state = make(morning ? .dawning : .dusk, 0.28, 4, .excellent)
            } else if d < 6 {
                state = make(.blue, 0.24, 5, .excellent)
            } else if d < 12 {
                state = make(.deepDusk, 0.13, 1, .neutral)
            } else if d < 18 {
                state = make(morning ? .astroDawn : .astroDusk, 0.06, nil, .stars, stars: true)
            } else {
                state = make(.astroNight, 0.04, nil, .stars, stars: true)
            }
        }
        self = state
    }

    private init(code: LightCode, level: Int?, tone: LightTone, glow: Double, color: SkyColor, stars: Bool) {
        self.code = code
        self.level = level
        self.tone = tone
        self.glow = glow
        self.color = color
        self.stars = stars
    }
}
