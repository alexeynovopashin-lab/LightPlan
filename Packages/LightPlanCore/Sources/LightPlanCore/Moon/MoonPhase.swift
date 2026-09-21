import Foundation

/// Код фазы луны — ключ словаря (`moon.new` и так далее). Фаза считается по
/// доле фазового цикла, от языка не зависит; слово по ключу берёт словарь
/// (итерация 14).
public enum MoonPhaseName: String, Sendable, CaseIterable {
    case new = "moon.new"
    case waxingCrescent = "moon.waxCres"
    case firstQuarter = "moon.firstQ"
    case waxingGibbous = "moon.waxGib"
    case full = "moon.full"
    case waningGibbous = "moon.wanGib"
    case lastQuarter = "moon.lastQ"
    case waningCrescent = "moon.wanCres"

    /// Границы веба (`PHASES`): первая граница, которую фаза не достигает,
    /// называет её; за последней — снова новолуние. Числа — физика продукта,
    /// «причёсывать» их запрещено (план, итерация 8).
    private static let bounds: [(Double, MoonPhaseName)] = [
        (0.02, .new), (0.24, .waxingCrescent), (0.28, .firstQuarter),
        (0.48, .waxingGibbous), (0.52, .full), (0.72, .waningGibbous),
        (0.76, .lastQuarter), (0.98, .waningCrescent), (1.01, .new),
    ]

    /// Название фазы по её положению в цикле: 0 — новолуние, 0.5 — полнолуние
    /// (`phaseName`). Не число (NaN) называется новолунием, как в вебе.
    public init(phase p: Double) {
        for (bound, name) in Self.bounds where p < bound {
            self = name
            return
        }
        self = .new
    }
}

/// Фаза луны: освещённая доля диска и положение в цикле.
///
/// Порт `moonPhase` и `phaseName`. Фаза зависит от солнца и луны, но не от
/// места на земле: широта и долгота здесь не нужны.
public struct MoonPhase: Sendable, Equatable {
    /// Освещённая доля диска, `0 ... 1`.
    public let fraction: Double
    /// Положение в цикле: 0 — новолуние, 0.5 — полнолуние, к 1 — снова новая.
    public let cycle: Double

    public var name: MoonPhaseName { MoonPhaseName(phase: cycle) }

    init(days d: Double) {
        let s = MoonSample.sunEquatorial(days: d)
        let m = MoonSample.equatorial(days: d)
        let sd = 149_598_000.0   // расстояние до солнца, км
        let phi = acos(sin(s.dec) * sin(m.dec) + cos(s.dec) * cos(m.dec) * cos(s.ra - m.ra))
        let inc = atan2(sd * sin(phi), m.dist - sd * cos(phi))
        let angle = atan2(
            cos(s.dec) * sin(s.ra - m.ra),
            sin(s.dec) * cos(m.dec) - cos(s.dec) * sin(m.dec) * cos(s.ra - m.ra)
        )
        self.fraction = (1 + cos(inc)) / 2
        self.cycle = 0.5 + 0.5 * inc * (angle < 0 ? -1 : 1) / Double.pi
    }

    /// Фаза без положения: смещение пояса задано явно.
    public init(date: CivilDate, minutes: Minutes, utcOffsetHours: Double) {
        self.init(days: Sky.days(date: date, minutes: minutes, utcOffsetHours: utcOffsetHours))
    }

    public init(date: CivilDate, minutes: Minutes, zone: ZoneID) {
        self.init(date: date, minutes: minutes, utcOffsetHours: zone.utcOffsetHours(on: date))
    }
}
