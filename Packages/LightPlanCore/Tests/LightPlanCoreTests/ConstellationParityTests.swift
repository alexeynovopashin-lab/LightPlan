import Testing
import Foundation
@testable import LightPlanCore

/// Небо при включении «Астро» (шаг 29.9). Эталон — `Fixtures/constellations.json`:
/// каталог из живого `beta/sky.js`, alt/az каждой звезды и разметка, которую
/// кладёт `buildAstroSky` беты, посчитанные стендом `Tools/parity/sky_stars.js`.
struct ConstellationParityTests {

    struct File: Decodable {
        struct Entry: Decodable {
            let n: String
            let s: [[Double]]
            let l: [[Int]]
        }
        struct Case: Decodable {
            let place: String
            let lat: Double, lon: Double
            let at: String
            let ms: Double
            let d: Double
            let up: [String]
            let altaz: [[Double]]
            let stars: [[Double]]
            let lines: [[Double]]
            let moon: [Double]?
        }
        let catalog: [Entry]
        let cases: [Case]
    }

    static let altAzTol = 1e-9

    @Test("каталог Swift равен window.SKY беты: коды, звёзды, величины, линии")
    func catalogEqualsBeta() throws {
        let f = try ParityFixtures.load("constellations.json", as: File.self)
        let swift = ConstellationCatalog.all
        #expect(swift.count == f.catalog.count)
        for (c, e) in zip(swift, f.catalog) {
            #expect(c.code == e.n)
            #expect(c.stars.count == e.s.count, "\(e.n): звёзд")
            for (st, raw) in zip(c.stars, e.s) {
                #expect(st.ra == raw[0] && st.dec == raw[1] && st.magnitude == raw[2], "\(e.n): звезда \(raw)")
            }
            #expect(c.lines == e.l, "\(e.n): линии")
        }
    }

    @Test("alt/az каждой звезды и список созвездий над горизонтом — как у беты, 30 случаев")
    func positionsAndVisibleList() throws {
        let f = try ParityFixtures.load("constellations.json", as: File.self)
        var worst = 0.0
        var checkedStars = 0
        for c in f.cases {
            let days = AstroSky.days(unixMilliseconds: c.ms)
            #expect(days == c.d, "\(c.place) \(c.at): дни от J2000")
            var k = 0
            for con in ConstellationCatalog.all {
                for st in con.stars {
                    let p = Sky.horizontal(ra: st.ra * Double.pi / 12, dec: Sky.rad(st.dec),
                                           days: days, latitude: c.lat, longitude: c.lon)
                    let dAlt = abs(p.altitude - c.altaz[k][0])
                    let dAz = SkyParityTests.circular(p.azimuth, c.altaz[k][1])
                    worst = max(worst, dAlt, dAz)
                    if !(dAlt <= Self.altAzTol && dAz <= Self.altAzTol) {
                        Issue.record("\(c.place) \(c.at) \(con.code)[\(k)]: alt Δ\(dAlt) az Δ\(dAz)")
                    }
                    k += 1
                    checkedStars += 1
                }
            }
            let up = AstroSky.visible(days: days, latitude: c.lat, longitude: c.lon).map(\.constellation.code)
            #expect(up == c.up, "\(c.place) \(c.at): созвездия над горизонтом")
        }
        print("созвездия: \(f.cases.count) случаев, \(checkedStars) звёзд, наибольшее расхождение alt/az \(worst)°")
    }

    @Test("сцена: точки, нити и луна — те же числа, что buildAstroSky в беты")
    func sceneMatchesBeta() throws {
        let f = try ParityFixtures.load("constellations.json", as: File.self)
        for c in f.cases {
            let days = AstroSky.days(unixMilliseconds: c.ms)
            // Луна по минуте суток, как у беты (часы телефона и места совпадают, пояс 0).
            let secs = c.ms / 1000
            let dayStart = (secs / 86_400).rounded(.down)
            let civil = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: Date(timeIntervalSince1970: secs))
            let date = CivilDate(year: civil.year!, month: civil.month!, day: civil.day!)
            let minute = Double(Int((secs - dayStart * 86_400) / 60))
            let m = MoonSample(date: date, minutes: minute, latitude: c.lat, longitude: c.lon, utcOffsetHours: 0)
            let scene = AstroSky.scene(days: days, latitude: c.lat, longitude: c.lon,
                                       moon: HorizontalPoint(altitude: m.altitude, azimuth: m.azimuth))
            let label = "\(c.place) \(c.at)"
            #expect(scene.constellations == c.up, "\(label)")
            #expect(scene.stars.count == c.stars.count, "\(label): звёзд")
            for (s, w) in zip(scene.stars, c.stars) {
                #expect(abs(s.x - w[0]) < 1e-9 && abs(s.y - w[1]) < 1e-9 && abs(s.radius - w[2]) < 1e-9
                        && abs(s.delay - w[3]) < 1e-9, "\(label): звезда \(w) → \(s)")
            }
            #expect(scene.lines.count == c.lines.count, "\(label): линий")
            for (l, w) in zip(scene.lines, c.lines) {
                #expect(abs(l.x1 - w[0]) < 1e-9 && abs(l.y1 - w[1]) < 1e-9 && abs(l.x2 - w[2]) < 1e-9
                        && abs(l.y2 - w[3]) < 1e-9, "\(label): нить \(w) → \(l)")
            }
            switch (scene.moon, c.moon) {
            case (nil, nil): break
            case let (a?, b?):
                // translate(m − 13) округлён беты до 0,1 отдельно: допуск одно деление округления.
                #expect(abs(a.x - b[0]) < 0.11 && abs(a.y - b[1]) < 0.11, "\(label): луна \(b) → \(a)")
            default:
                Issue.record("\(label): луна на небе беты \(String(describing: c.moon)), у Swift \(String(describing: scene.moon))")
            }
        }
    }

    // MARK: - Правило «целиком или никак»

    /// Звезда нужной высоты: на широте 0 и долготе 0 при `dec = 0` высота звезды
    /// — `asin(cos H)`, поэтому прямое восхождение выбирается по часовому углу.
    private func star(altitude: Double, days: Double) -> CatalogStar {
        let h = acos(sin(Sky.rad(altitude)))               // часовой угол, рад
        let theta = Sky.rad(280.16 + 360.9856235 * days)   // долгота 0
        let ra = theta - h
        return CatalogStar(ra: ra * 12 / Double.pi, dec: 0, magnitude: 2)
    }

    @Test("созвездие с одной звездой под горизонтом не рисуется целиком")
    func halfConstellationIsNotDrawn() {
        let d = 1234.5
        func up(_ second: Double) -> Int {
            let con = Constellation(code: "T", stars: [star(altitude: 60, days: d), star(altitude: second, days: d)], lines: [[0, 1]])
            let s = AstroSky.scene(days: d, latitude: 0, longitude: 0, moon: nil, catalog: [con])
            return s.stars.count + s.lines.count
        }
        #expect(up(60) == 3, "обе звезды высоко: две точки и нить")
        #expect(up(1.5) == 3, "вторая на 1,5°: выше порога — рисуется")
        #expect(up(0.5) == 0, "вторая на 0,5°: ниже порога — нет ни точек, ни нити")
        #expect(up(-20) == 0, "вторая под горизонтом: целиком нет")
    }

    @Test("проекция: зенит — центр, север вверху, восток слева, горизонт — радиус 300")
    func projection() {
        let z = AstroSky.point(altitude: 90, azimuth: 0)
        #expect(z.x == 100 && z.y == 215)
        let n = AstroSky.point(altitude: 30, azimuth: 0)
        #expect(abs(n.x - 100) < 1e-9 && abs(n.y - (215 - 200)) < 1e-9, "север вверху")
        let e = AstroSky.point(altitude: 30, azimuth: 90)
        #expect(abs(e.x - (100 - 200)) < 1e-9 && abs(e.y - 215) < 1e-9, "восток слева")
        let h = AstroSky.point(altitude: 0, azimuth: 180)
        #expect(abs(h.y - (215 + 300)) < 1e-9, "юг на горизонте внизу")
    }
}
