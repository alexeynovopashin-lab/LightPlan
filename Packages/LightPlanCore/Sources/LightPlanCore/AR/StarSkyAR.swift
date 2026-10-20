import Foundation

/// Звёзды и созвездия в слое AR (шаг 29.8в.13). Положение — тот же расчёт, что у луны и ядра Млечного Пути:
/// `Sky.horizontal` по месту и моменту, потом та же проекция на экран (`SkyProjection`) и та же добавка рефракции
/// (`SunTrack.apparent`). Своих формул неба здесь нет.
///
/// Каталог — звёзды фигур созвездий беты (`ConstellationCatalog`, J2000) и яркие звёзды вне фигур (`BrightStarCatalog`:
/// Канопус, Альфа Центавра, Южный Крест и другие, 31 шт.). Поправка на прецессию не вводится:
/// за 26 лет с 2000 года она сдвигает точку на ≈ 0,37° — меньше допуска сверки AR (1°) и меньше погрешности компаса.
/// Первую поправку она потребует, если AR понадобится точность в доли градуса.

// MARK: - Каталог слоя

/// Звезда слоя: экваториальные координаты J2000 и то, что известно о ней сверх положения.
public struct SkyStar: Sendable, Equatable {
    /// Прямое восхождение, **часы**.
    public let ra: Double
    /// Склонение, градусы.
    public let dec: Double
    public let magnitude: Double
    /// Буква спектрального класса (O B A F G K M). В каталоге созвездий беты её нет — точка белая; у ярких звёзд вне фигур
    /// она есть, и цвет точки берётся по ней (`StarLook.tint`).
    public let spectralClass: Character?
    /// Ключ имени звезды в словаре (`star.sirius`); у безымянных `nil`. Имена есть у всех звёзд слоя до величины 1,5.
    public let nameKey: String?

    public init(ra: Double, dec: Double, magnitude: Double, spectralClass: Character? = nil, nameKey: String? = nil) {
        self.ra = ra; self.dec = dec; self.magnitude = magnitude
        self.spectralClass = spectralClass; self.nameKey = nameKey
    }
}

/// Фигура созвездия: номера звёзд в каталоге слоя (`StarCatalogAR.stars`), а не копии — звезда, общая у двух
/// созвездий (Альферац в Пегасе и Андромеде, Эльнат в Тельце и Возничем), в слое одна.
public struct StarFigure: Sendable, Equatable {
    public let code: String
    public let stars: [Int]
    /// Линии фигуры: пары номеров звёзд каталога слоя.
    public let lines: [[Int]]

    public init(code: String, stars: [Int], lines: [[Int]]) {
        self.code = code; self.stars = stars; self.lines = lines
    }
}

/// Имя звезды по её координатам в каталоге слоя. Совпадение — по тем же числам, что в каталоге; тест проверяет,
/// что у каждого имени нашлась ровно одна звезда.
public struct StarName: Sendable, Equatable {
    public let key: String
    public let ra: Double
    public let dec: Double

    /// Подписываются звёзды не слабее этой величины: 15 из каталога созвездий (Сириус … Адара) и 7 ярких вне фигур.
    /// Следующая по блеску — Кастор (1,58).
    public static let limit = 1.5

    /// Все звёзды слоя до величины 1,5 — 22 имени. Сначала звёзды фигур созвездий (по величине), затем яркие вне фигур
    /// (координаты — как в `BrightStarCatalog`).
    public static let brightest: [StarName] = [
        StarName(key: "star.sirius", ra: 6.752, dec: -16.72),
        StarName(key: "star.arcturus", ra: 14.261, dec: 19.18),
        StarName(key: "star.vega", ra: 18.615, dec: 38.78),
        StarName(key: "star.capella", ra: 5.278, dec: 46),
        StarName(key: "star.rigel", ra: 5.242, dec: -8.2),
        StarName(key: "star.procyon", ra: 7.655, dec: 5.22),
        StarName(key: "star.betelgeuse", ra: 5.919, dec: 7.41),
        StarName(key: "star.altair", ra: 19.846, dec: 8.87),
        StarName(key: "star.aldebaran", ra: 4.599, dec: 16.51),
        StarName(key: "star.antares", ra: 16.49, dec: -26.43),
        StarName(key: "star.spica", ra: 13.42, dec: -11.16),
        StarName(key: "star.pollux", ra: 7.755, dec: 28.03),
        StarName(key: "star.deneb", ra: 20.69, dec: 45.28),
        StarName(key: "star.regulus", ra: 10.139, dec: 11.97),
        StarName(key: "star.adhara", ra: 6.977, dec: -28.97),
        StarName(key: "star.canopus", ra: 6.39919, dec: -52.6958),
        StarName(key: "star.rigil", ra: 14.65997, dec: -60.8353),
        StarName(key: "star.achernar", ra: 1.62858, dec: -57.2367),
        StarName(key: "star.hadar", ra: 14.06372, dec: -60.3731),
        StarName(key: "star.acrux", ra: 12.44331, dec: -63.0992),
        StarName(key: "star.fomalhaut", ra: 22.96086, dec: -29.6222),
        StarName(key: "star.mimosa", ra: 12.79533, dec: -59.6886),
    ]
}

/// Каталог слоя «Звёзды» и «Созвездия»: уникальные звёзды и фигуры, ссылающиеся на них. Одна звезда — одна точка
/// и одна подпись, в скольких бы источниках она ни стояла.
public struct StarCatalogAR: Sendable, Equatable {
    public let stars: [SkyStar]
    public let figures: [StarFigure]

    public init(stars: [SkyStar], figures: [StarFigure]) {
        self.stars = stars
        self.figures = figures
    }

    /// Звёзды ближе этого на небе — одна звезда. Тот же допуск, с которым собран `BrightStarCatalog` (0,05°).
    public static let sameStar: Degrees = 0.05

    /// Из каталога созвездий и ярких звёзд вне фигур: одинаковые координаты — одна звезда; яркая звезда ближе
    /// `sameStar` к уже взятой не добавляется; имя — по `StarName`.
    public init(constellations: [Constellation], bright: [BrightStar] = [], names: [StarName] = StarName.brightest) {
        func key(_ ra: Double, _ dec: Double) -> String { "\(Int((ra * 1000).rounded())),\(Int((dec * 100).rounded()))" }
        let named = Dictionary(names.map { (key($0.ra, $0.dec), $0.key) }, uniquingKeysWith: { a, _ in a })
        var stars: [SkyStar] = []
        var index: [String: Int] = [:]
        var figures: [StarFigure] = []
        for con in constellations {
            var own: [Int] = []
            for s in con.stars {
                let k = key(s.ra, s.dec)
                if let i = index[k] { own.append(i); continue }
                index[k] = stars.count
                own.append(stars.count)
                stars.append(SkyStar(ra: s.ra, dec: s.dec, magnitude: s.magnitude, nameKey: named[k]))
            }
            figures.append(StarFigure(code: con.code, stars: own, lines: con.lines.map { $0.map { own[$0] } }))
        }
        func direction(_ ra: Double, _ dec: Double) -> (Double, Double, Double) {
            let a = ra * Double.pi / 12, d = dec * Double.pi / 180
            return (cos(d) * cos(a), cos(d) * sin(a), sin(d))
        }
        let near = cos(Self.sameStar * Double.pi / 180)
        var seen = stars.map { direction($0.ra, $0.dec) }
        for b in bright {
            let v = direction(b.ra, b.dec)
            guard !seen.contains(where: { $0.0 * v.0 + $0.1 * v.1 + $0.2 * v.2 >= near }) else { continue }
            seen.append(v)
            stars.append(SkyStar(ra: b.ra, dec: b.dec, magnitude: b.magnitude, spectralClass: b.spectralClass.first,
                                 nameKey: named[key(b.ra, b.dec)]))
        }
        self.init(stars: stars, figures: figures)
    }

    /// Каталог, по которому рисует экран: звёзды фигур и яркие звёзды вне фигур.
    public static let current = StarCatalogAR(constellations: ConstellationCatalog.all, bright: BrightStarCatalog.all)
}

// MARK: - Вид точки

public enum StarLook {
    /// Радиус точки, pt: Сириус (−1,46) ≈ 3,0; нулевая величина 2,2; вторая 1,1; слабее третьей — 0,8 (меньше точка на
    /// экране теряется).
    public static func radius(magnitude m: Double) -> Double { max(0.8, 2.2 - 0.55 * m) }

    /// Яркость точки `0,4 … 1`: до величины 0,5 — полная, дальше падает на 0,12 за величину.
    public static func brightness(magnitude m: Double) -> Double { max(0.4, min(1, 1 - 0.12 * (m - 0.5))) }

    /// Цвет точки: почти белый с лёгким оттенком по спектральному классу. Нет класса — белый. Числа `0…1`.
    public static func tint(spectralClass c: Character?) -> (red: Double, green: Double, blue: Double) {
        switch c.map({ String($0).uppercased() }) ?? "" {
        case "O", "B": return (0.80, 0.86, 1.00)
        case "A": return (0.90, 0.93, 1.00)
        case "F": return (0.98, 0.97, 1.00)
        case "G": return (1.00, 0.96, 0.88)
        case "K": return (1.00, 0.88, 0.74)
        case "M": return (1.00, 0.80, 0.66)
        default: return (1, 1, 1)
        }
    }
}

// MARK: - Расчёт и сцена

public enum StarSkyAR {
    /// Положения всех звёзд каталога на момент «день плюс минуты шкалы» по часам места — геометрические, без рефракции.
    /// Считается один раз на момент и место; от поворота телефона не зависит.
    public static func horizontals(catalog: StarCatalogAR = .current, day: CivilDate, minutes: Minutes,
                                   in place: Place) -> [HorizontalPoint] {
        let d = Sky.days(date: day, minutes: minutes, utcOffsetHours: place.zone.utcOffsetHours(on: day))
        return catalog.stars.map {
            Sky.horizontal(ra: $0.ra * Double.pi / 12, dec: Sky.rad($0.dec), days: d,
                           latitude: place.latitude, longitude: place.longitude)
        }
    }

    /// Фигура рисует подпись, только если над горизонтом не меньше этой доли её звёзд: полфигуры у горизонта читается
    /// как другая фигура.
    public static let figureLabelShare = 0.6

    public static func make(catalog: StarCatalogAR = .current, positions: [HorizontalPoint],
                            basis: CameraBasis, optics: CameraOptics, viewport: ScreenViewport,
                            stars showStars: Bool, constellations showFigures: Bool) -> StarSkyARScene {
        func proj(_ p: HorizontalPoint) -> ScreenPoint? {
            SkyProjection.project(azimuth: p.azimuth, altitude: p.altitude, basis: basis, optics: optics, viewport: viewport)
        }
        // Видимая высота — как у луны и солнца. Под горизонтом звезда не рисуется.
        let seen: [HorizontalPoint] = positions.map {
            HorizontalPoint(altitude: SunTrack.apparent(altitude: $0.altitude), azimuth: $0.azimuth)
        }
        let up = seen.map { $0.altitude >= 0 }

        var dots: [StarSkyARScene.Dot] = []
        if showStars {
            for (i, s) in catalog.stars.enumerated() where up[i] {
                guard let p = proj(seen[i]) else { continue }
                dots.append(.init(index: i, point: p, magnitude: s.magnitude, radius: StarLook.radius(magnitude: s.magnitude),
                                  brightness: StarLook.brightness(magnitude: s.magnitude),
                                  spectralClass: s.spectralClass, nameKey: s.nameKey,
                                  azimuth: positions[i].azimuth, altitude: positions[i].altitude))
            }
        }

        var segments: [StarSkyARScene.Segment] = []
        var marks: [StarSkyARScene.FigureMark] = []
        if showFigures {
            for fig in catalog.figures {
                for ln in fig.lines {
                    let a = ln[0], b = ln[1]
                    guard up[a] || up[b] else { continue }
                    var ends = (seen[a], seen[b])
                    if !up[a] || !up[b] {
                        // Один конец под горизонтом: линия обрывается на горизонте, а не уходит под него.
                        let high = up[a] ? seen[a] : seen[b], low = up[a] ? seen[b] : seen[a]
                        let h = SkyVector(azimuth: high.azimuth, altitude: high.altitude)
                        let l = SkyVector(azimuth: low.azimuth, altitude: low.altitude)
                        let t = h.up / (h.up - l.up)
                        let m = SkyVector(east: h.east + (l.east - h.east) * t, north: h.north + (l.north - h.north) * t, up: 0)
                        let cut = HorizontalPoint(altitude: 0, azimuth: m.horizontal.azimuth)
                        ends = up[a] ? (high, cut) : (cut, high)
                    }
                    if let p = proj(ends.0), let q = proj(ends.1) { segments.append(.init(from: p, to: q)) }
                }
                // Подпись — у центра фигуры по небу (среднее направлений звёзд над горизонтом), а не по экрану:
                // она не прыгает, когда часть фигуры уходит за край кадра.
                let above = fig.stars.filter { up[$0] }
                guard above.count >= 2, Double(above.count) >= figureLabelShare * Double(fig.stars.count) else { continue }
                var e = 0.0, n = 0.0, u = 0.0
                for i in above {
                    let v = SkyVector(azimuth: seen[i].azimuth, altitude: seen[i].altitude)
                    e += v.east; n += v.north; u += v.up
                }
                let len = (e * e + n * n + u * u).squareRoot()
                guard len > 1e-9 else { continue }
                let c = SkyVector(east: e / len, north: n / len, up: u / len).horizontal
                guard c.altitude > 0, let p = proj(c) else { continue }
                marks.append(.init(code: fig.code, point: p, azimuth: c.azimuth, altitude: c.altitude))
            }
        }
        return StarSkyARScene(dots: dots, segments: segments, figures: marks,
                              starsOn: showStars, constellationsOn: showFigures)
    }
}

/// Всё, что экран AR рисует для звёзд и созвездий, в точках окна. Чистая функция, как `NightSkyARScene`. Что выключено
/// переключателем, во вход не подаётся — и в сцене пусто.
public struct StarSkyARScene: Sendable, Equatable {
    public struct Dot: Sendable, Equatable {
        /// Номер звезды в каталоге слоя.
        public let index: Int
        public let point: ScreenPoint
        public let magnitude: Double
        public let radius: Double
        /// Яркость по величине `0,4 … 1`. От солнца и засветки не зависит: слой рисуется всегда (29.8в.18).
        public let brightness: Double
        public let spectralClass: Character?
        public let nameKey: String?
        public let azimuth: Degrees
        /// Геометрическая высота.
        public let altitude: Degrees
    }

    public struct Segment: Sendable, Equatable {
        public let from: ScreenPoint
        public let to: ScreenPoint
    }

    /// Подпись созвездия: центр фигуры на экране (может лежать за краем кадра — решает тот, кто рисует).
    public struct FigureMark: Sendable, Equatable {
        public let code: String
        public let point: ScreenPoint
        public let azimuth: Degrees
        public let altitude: Degrees
    }

    public let dots: [Dot]
    public let segments: [Segment]
    public let figures: [FigureMark]
    public let starsOn: Bool
    public let constellationsOn: Bool

    /// Что-то включено.
    public var isOn: Bool { starsOn || constellationsOn }
}
