import Foundation

/// Палитра неба на закате по прогнозу — порт `SKY_STOPS`, `SKY_DEAD`,
/// `skyPalette` веба (`light_plan:Light_Plan/beta/index.html`). Прогноз
/// становится цветом: балл заката и ярусы облаков решают, насколько ярким
/// выйдет небо, а «свинец» — это когда цвета не будет.
///
/// В вебе палитра красит две вещи: плашку неба в сводке и зарево у горизонта
/// купола. В нативе её также использует подложка купола «Астро» (`DomeSky` в UI).
public struct SkyPalette: Sendable, Equatable {
    public let zenith: SkyColor
    public let high: SkyColor
    public let mid: SkyColor
    public let horizon: SkyColor
    /// Насколько живым будет небо, 0…1: ноль — свинец, зарева почти нет.
    public let life: Double
    /// Доля цвета прогноза в каждой точке неба; остальное — свинец.
    private let shares: Shares

    private struct Shares: Sendable, Equatable {
        let zenith, high, mid, horizon: Double
    }

    static let zenithStop = SkyColor(56, 62, 82)     // холодный верх неба
    static let highStop = SkyColor(214, 124, 148)    // розовое послесвечение перистых
    static let midStop = SkyColor(226, 116, 74)      // алый и оранжевый средних облаков
    static let horizonStop = SkyColor(247, 196, 118) // тёплая полоса у самого горизонта
    static let dead = SkyColor(92, 92, 96)           // «свинец»: цвета не будет

    /// `nil` — нет балла заката или часа заката в прогнозе, как у веба.
    public init?(weather w: WeatherDay?) {
        guard let w, let score = w.sunset, let L = w.layers else { return nil }
        func clamp(_ x: Double, _ a: Double, _ b: Double) -> Double { min(b, max(a, x)) }
        func mixDead(_ c: SkyColor, _ k: Double) -> SkyColor { LightPalette.lerp(Self.dead, c, clamp(k, 0, 1)) }
        let s = Double(score) / 100
        // Чем ниже балл, тем ближе к свинцу; влажность добавляет дымки
        let wash = clamp((L.humidity - 65) / 45, 0, 0.45)
        let life = clamp(s * 1.15, 0, 1) * (1 - wash * 0.6)
        // Верхний и средний ярусы работают, только если нижний не закрыл горизонт
        let gap = clamp(1 - L.low / 70, 0, 1)
        let shares = Shares(zenith: 0.35 + life * 0.4, high: life * clamp(L.high / 55, 0.25, 1) * gap,
                            mid: life * clamp(L.mid / 55, 0.3, 1) * gap, horizon: life * gap)
        zenith = mixDead(Self.zenithStop, shares.zenith)
        high = mixDead(Self.highStop, shares.high)
        mid = mixDead(Self.midStop, shares.mid)
        horizon = mixDead(Self.horizonStop, shares.horizon)
        self.life = life * gap
        self.shares = shares
    }

    private init(zenith: SkyColor, high: SkyColor, mid: SkyColor, horizon: SkyColor, life: Double, shares: Shares) {
        self.zenith = zenith
        self.high = high
        self.mid = mid
        self.horizon = horizon
        self.life = life
        self.shares = shares
    }

    /// Та же палитра поверх светлого неба: вместо свинца в смеси — само небо на этой
    /// высоте, так что бесцветный прогноз ничего поверх него не рисует. Холодный верх
    /// неба — тоже цвет прогноза, он уходит вместе с `life` (у веба его нет: это только
    /// купол «Астро» светлой темы, `DomeSky`).
    public func over(zenith z: SkyColor, high h: SkyColor, mid m: SkyColor, horizon n: SkyColor) -> SkyPalette {
        SkyPalette(zenith: LightPalette.lerp(z, Self.zenithStop, shares.zenith * life),
                   high: LightPalette.lerp(h, Self.highStop, shares.high),
                   mid: LightPalette.lerp(m, Self.midStop, shares.mid),
                   horizon: LightPalette.lerp(n, Self.horizonStop, shares.horizon),
                   life: life, shares: shares)
    }
}

/// Зарево у горизонта купола — порт хвоста `renderToday` веба (`#glow`,
/// `#glowStop0`): цвет и плотность центра радиального пятна.
public enum HorizonGlow {
    /// `opacity` — это `stop-opacity` центра градиента целиком. В SVG веба у
    /// стопа записано 0.32, но код перезаписывает его каждый кадр; порт
    /// купола принял 0.32 за множитель, и зарево вышло втрое тусклее.
    public static func paint(state: LightState, elevation e: Degrees, palette: SkyPalette?,
                             moon: Bool, lightTheme: Bool) -> (color: SkyColor, opacity: Double) {
        var color = state.color
        var amount = state.glow
        // Палитра действует только у горизонта и только по солнцу; серое
        // небо честно даёт тусклое зарево.
        if !moon, let pal = palette, e < 8 {
            let near = min(1, max(0, (8 - e) / 14))  // чем ниже солнце, тем сильнее палитра
            color = LightPalette.lerp(state.color, pal.horizon, near * 0.75)
            amount = state.glow * (0.35 + pal.life * 0.85)
        }
        // На светлом фоне нет темноты, которую зарево рассеивает: та же
        // плотность дала бы грязное пятно вместо свечения.
        let k = lightTheme ? 0.42 : 1.0
        let opacity = (min(1, max(0, amount * k)) * 100).rounded() / 100  // `toFixed(2)` веба
        return (color, opacity)
    }
}
