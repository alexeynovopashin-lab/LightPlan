import Foundation

/// Звезда каталога пасхалки «Астро»: экваториальные координаты эпохи J2000.
public struct CatalogStar: Sendable, Equatable {
    /// Прямое восхождение, **часы**.
    public let ra: Double
    /// Склонение, градусы.
    public let dec: Double
    /// Видимая величина: от неё зависит радиус точки.
    public let magnitude: Double
}

/// Созвездие каталога: код, звёзды и линии — пары номеров в списке звёзд.
public struct Constellation: Sendable, Equatable {
    public let code: String
    public let stars: [CatalogStar]
    public let lines: [[Int]]
}

/// Каталог созвездий беты (`beta/sky.js`, `window.SKY`) — данные; литералы
/// лежат в `ConstellationCatalog.generated.swift`, их пишет `Tools/sky2swift.js`.
public enum ConstellationCatalog {}

/// Небо при включении «Астро» (шаг 29.9): какие созвездия стоят над горизонтом
/// и куда на куполе ложится каждая точка. Порт `buildAstroSky` беты.
///
/// Купол во весь слой: зенит в центре поля 200×430, север вверху, восток слева.
/// Расстояние от центра — угол от зенита, поэтому у горизонта фигуры
/// растягиваются, как у настоящего неба.
public enum AstroSky {

    /// Радиус горизонта в единицах поля `200 × 430` (`R` беты).
    public static let horizonRadius = 300.0
    public static let fieldWidth = 200.0
    public static let fieldHeight = 430.0
    /// Созвездие рисуется, только если ВСЕ его звёзды выше этой высоты, градусы.
    /// Половина фигуры за горизонтом читается как другая фигура.
    public static let minimumAltitude = 1.0

    /// Проекция `pt(alt, az)` беты: центр поля, север вверху, восток слева.
    public static func point(altitude: Degrees, azimuth: Degrees) -> (x: Double, y: Double) {
        let r = (90 - altitude) / 90 * horizonRadius
        let a = Sky.rad(azimuth)
        return (fieldWidth / 2 - r * sin(a), fieldHeight / 2 - r * cos(a))
    }

    /// Созвездие, целиком стоящее над горизонтом: положение каждой звезды.
    public struct Visible: Sendable, Equatable {
        public let constellation: Constellation
        public let positions: [HorizontalPoint]
    }

    /// Созвездия над горизонтом для момента (дни от J2000) и места — в порядке
    /// каталога.
    public static func visible(
        days: Double, latitude: Double, longitude: Double,
        catalog: [Constellation] = ConstellationCatalog.all
    ) -> [Visible] {
        catalog.compactMap { con in
            let pos = con.stars.map {
                Sky.horizontal(ra: $0.ra * Double.pi / 12, dec: Sky.rad($0.dec),
                               days: days, latitude: latitude, longitude: longitude)
            }
            return pos.allSatisfy({ $0.altitude > minimumAltitude }) ? Visible(constellation: con, positions: pos) : nil
        }
    }

    /// Всё, что нужно нарисовать: точки, нити, луна. Числа округлены так же,
    /// как у беты (`toFixed`): координаты до 0,1, радиус и задержка до 0,01.
    public struct Scene: Sendable, Equatable {
        public struct Star: Sendable, Equatable {
            public let x: Double, y: Double, radius: Double
            /// Задержка проявления, секунды: `0,02 · (номер % 40)`.
            public let delay: Double
        }
        public struct Line: Sendable, Equatable {
            public let x1: Double, y1: Double, x2: Double, y2: Double
        }
        public let constellations: [String]
        public let stars: [Star]
        public let lines: [Line]
        /// Луна над горизонтом: место значка; `nil` — под горизонтом, её нет.
        public let moon: (x: Double, y: Double)?

        public static func == (a: Scene, b: Scene) -> Bool {
            a.constellations == b.constellations && a.stars == b.stars && a.lines == b.lines
                && a.moon?.x == b.moon?.x && a.moon?.y == b.moon?.y
        }
    }

    /// `toFixed(digits)` JS: десятичное округление, а не двоичное усечение.
    static func fixed(_ v: Double, _ digits: Int) -> Double {
        Double(String(format: "%.\(digits)f", v)) ?? v
    }

    public static func scene(
        days: Double, latitude: Double, longitude: Double, moon: HorizontalPoint?,
        catalog: [Constellation] = ConstellationCatalog.all
    ) -> Scene {
        var stars: [Scene.Star] = [], lines: [Scene.Line] = [], codes: [String] = []
        var n = 0
        for v in visible(days: days, latitude: latitude, longitude: longitude, catalog: catalog) {
            codes.append(v.constellation.code)
            func at(_ i: Int) -> (x: Double, y: Double) {
                let p = point(altitude: v.positions[i].altitude, azimuth: v.positions[i].azimuth)
                return (fixed(p.x, 1), fixed(p.y, 1))
            }
            for ln in v.constellation.lines {
                let a = at(ln[0]), b = at(ln[1])
                lines.append(.init(x1: a.x, y1: a.y, x2: b.x, y2: b.y))
            }
            for (i, st) in v.constellation.stars.enumerated() {
                let p = at(i)
                // Вега и Полярная не могут быть одной точкой: глаз ведёт по ярким.
                stars.append(.init(x: p.x, y: p.y, radius: fixed(max(0.8, 2.1 - 0.3 * st.magnitude), 2),
                                   delay: fixed(0.02 * Double(n % 40), 2)))
                n += 1
            }
        }
        var moonPoint: (x: Double, y: Double)?
        if let m = moon, m.altitude > 0 {
            let p = point(altitude: m.altitude, azimuth: m.azimuth)
            moonPoint = (fixed(p.x, 1), fixed(p.y, 1))
        }
        return Scene(constellations: codes, stars: stars, lines: lines, moon: moonPoint)
    }

    /// Дни от J2000 на момент в миллисекундах эпохи Unix — `toDays(new Date())`.
    public static func days(unixMilliseconds ms: Double) -> Double {
        ms / 86_400_000 - 0.5 + 2_440_588 - 2_451_545
    }

    public static func days(of date: Date) -> Double {
        days(unixMilliseconds: (date.timeIntervalSince1970 * 1000).rounded(.towardZero))
    }
}
