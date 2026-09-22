import Foundation
import LightPlanCore

/// Вечернее окно света одних суток одного места: от начала золотого часа до
/// конца синего (веб `SUN.goldB`, `SUN.blueB`; в `SolarDay` — `goldenB`, `blueB`).
public struct EveningLight: Hashable, Sendable {
    public let goldenB: Double?
    public let blueB: Double?

    public init(goldenB: Double?, blueB: Double?) {
        self.goldenB = goldenB
        self.blueB = blueB
    }
}

/// Точка дня, о которой говорит свет: этап маршрута или сама съёмка (`nil`).
public struct LightPoint: Hashable, Sendable {
    /// Минуты от полуночи первого дня.
    public let minute: Int
    /// Имя этапа; `nil` — «съёмка» (без маршрута точками служат её часы).
    public let name: String?
}

/// Окно золотого часа, сдвинутое на сутки точки: минуты от полуночи первого дня.
public struct GoldenWindow: Hashable, Sendable {
    public let start: Double
    public let end: Double
}

/// Что свет скажет в карточке. Свет — условие, а не раздел: три требования
/// сразу — пресет его требует, точка дня попадает в окно, и есть что сказать
/// (`docs/11_EVENT_CARD.md`, `docs/12`, «Свет — условие, а не строка матрицы»).
public enum LightCase: Hashable, Sendable {
    /// Ждали заката, а небо плохое: дождь или туман в сутки, где золотой час
    /// попал в точку (или в день съёмки, если не попал никуда).
    case badSky(point: LightPoint?, day: CivilDate)
    /// Точка в золотом часе.
    case inGolden(point: LightPoint?, window: GoldenWindow)
    /// Мимо окна не больше чем на три часа — стоит сказать; мимо на полдня — нет.
    case nearGolden(point: LightPoint?, window: GoldenWindow, gap: Int)

    /// Допуск к началу вечернего золотого часа (веб `GOLD_EARLY`): точка, начатая
    /// не раньше чем за десять минут до золотого часа, в золотом часе
    /// (Алексей, 15 сентября 2026, вариант «а»).
    public static let goldEarly = 10.0

    /// Часы съёмки без маршрута (веб `shootHours`): шаг в два часа от начала и сам
    /// конец. По ним же идут колонки погоды и знак света.
    public static func hours(of s: Session) -> [Int] {
        let end = s.endMinute
        var out: [Int] = []
        var t = s.start
        while t <= end { out.append(t); t += 120 }
        if out.isEmpty || out.last! != end { out.append(end) }
        return out
    }

    /// Свет записи (веб `lightCase`). `route` — точки дня «что во сколько»
    /// (`Session.timedRoute`; у встречи — пусто).
    ///
    /// - Parameters:
    ///   - evening: вечернее окно места в эти сутки; `nil` в месте — место приложения.
    ///   - skyIsBad: плохо ли небо в эти сутки (дождь или туман — `poor`, `fog`).
    public static func of(_ s: Session, route: [RoutePoint], spots: [Spot], studios: [Studio],
                          evening: (GeoPoint?, CivilDate) -> EveningLight,
                          skyIsBad: (CivilDate) -> Bool) -> LightCase? {
        guard s.wishes.contains(where: \.asksLight) else { return nil }
        let at = Stops.skyPoint(of: s, spots: spots, studios: studios)
        let gate = evening(at, s.day)
        guard gate.goldenB != nil, gate.blueB != nil else { return nil }

        struct Probe { let point: LightPoint; let at: GeoPoint?; let day: Int }
        let probes: [Probe]
        if route.isEmpty {
            probes = hours(of: s).map { Probe(point: LightPoint(minute: $0, name: nil), at: at, day: Session.floorDiv($0, 1440)) }
        } else {
            probes = route.map { r in
                let t = r.start ?? 0
                return Probe(point: LightPoint(minute: t, name: r.name),
                             at: Stops.place(of: r, spots: spots, studios: studios)?.point ?? at,
                             day: Session.floorDiv(t, 1440))
            }
        }
        /* Свет считается в момент события: точка второго дня сверяется с окном
           своих суток, сдвинутым на эти сутки, и солнце — места самой точки. */
        func window(_ p: Probe) -> GoldenWindow? {
            let w = evening(p.at, s.date(ofDay: p.day))
            guard let b = w.goldenB, let e = w.blueB else { return nil }
            let shift = Double(p.day * 1440)
            return GoldenWindow(start: b + shift, end: e + shift)
        }

        var hit: (Probe, GoldenWindow)?
        var near: (Probe, GoldenWindow)?
        var gap = 1e9
        for p in probes {
            guard let w = window(p) else { continue }
            let t = Double(p.point.minute)
            if t >= w.start - goldEarly && t <= w.end {
                if hit == nil { hit = (p, w) }
                continue
            }
            let d = min(abs(t - w.start), abs(t - w.end))
            if d < gap { gap = d; near = (p, w) }
        }

        /* Погода — тех суток, где золотой час попал в точку. */
        let qd = hit.map { s.date(ofDay: $0.0.day) } ?? s.day
        if skyIsBad(qd) { return .badSky(point: hit?.0.point, day: qd) }
        if let (p, w) = hit { return .inGolden(point: p.point, window: w) }
        if let (p, w) = near, gap <= 180 {
            return .nearGolden(point: p.point, window: w, gap: Int((gap + 0.5).rounded(.down)))
        }
        return nil
    }
}
