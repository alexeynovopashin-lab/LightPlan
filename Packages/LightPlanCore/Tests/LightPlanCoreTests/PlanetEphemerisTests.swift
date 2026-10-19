import Testing
import Foundation
import LightPlanCore

/// Расчёт планет (шаг 29.8в.15) против JPL Horizons: пять планет на восьми моментах 2024–2030.
/// Эталон — `Fixtures/planets_horizons.json`, собирается `python3 Tools/planets_ref.py`. Допуск шага: 0,5° для
/// Венеры, Марса, Юпитера и Сатурна, 1° для Меркурия, видимая величина — 0,3.
struct PlanetEphemerisTests {

    struct Reference: Decodable {
        struct Moment: Decodable { let utc: String; let jd: Double }
        struct Row: Decodable { let ra, dec, mag, elong, az, el: Double }
        struct Place: Decodable { let latitude, longitude: Double }
        let source: String
        let place: Place
        let moments: [Moment]
        let planets: [String: [Row]]
        struct DenseRow: Decodable { let ra, dec, mag, elong: Double }
        struct Dense: Decodable { let jds: [Double]; let planets: [String: [DenseRow]] }
        let dense: Dense
    }

    /// Эталон или причина, по которой его нет (`ParityFixtures.Failure` называет файл и команду сборки).
    static let loaded: Result<Reference, Error> = Result { try ParityFixtures.load("planets_horizons.json", as: Reference.self) }

    static var reference: Reference {
        get throws { try loaded.get() }
    }

    static func tolerance(_ p: Planet) -> Double { p == .mercury ? 1.0 : 0.5 }

    /// Угол между двумя точками неба, градусы.
    static func separation(_ a: HorizontalPoint, _ b: HorizontalPoint) -> Double {
        let u = SkyVector(azimuth: a.azimuth, altitude: a.altitude), v = SkyVector(azimuth: b.azimuth, altitude: b.altitude)
        return acos(min(1, max(-1, u.dot(v)))) * 180 / Double.pi
    }

    struct Sample {
        let planet: Planet
        let utc: String
        let equatorial: Double
        let horizontal: Double
        let magnitude: Double
        let elongation: Double
    }

    static func measure() throws -> [Sample] {
        let ref = try reference
        var out: [Sample] = []
        for planet in Planet.allCases {
            let rows = ref.planets[planet.rawValue]!
            for (m, row) in zip(ref.moments, rows) {
                let days = m.jd - 2_451_545.0
                let got = PlanetEphemeris.position(planet, days: days)
                // Экваториальная пара: расхождение как угол на небе.
                let a = HorizontalPoint(altitude: got.point.dec * 180 / .pi, azimuth: got.point.ra * 180 / .pi)
                let b = HorizontalPoint(altitude: row.dec, azimuth: row.ra)
                let h = PlanetEphemeris.horizontal(got, days: days, latitude: ref.place.latitude, longitude: ref.place.longitude)
                out.append(Sample(planet: planet, utc: m.utc, equatorial: separation(a, b),
                                  horizontal: separation(h, HorizontalPoint(altitude: row.el, azimuth: row.az)),
                                  magnitude: abs(got.magnitude - row.mag), elongation: abs(got.elongation - row.elong)))
            }
        }
        return out
    }

    @Test("эталон: 5 планет × 8 моментов, разные годы 2024–2030")
    func referenceShape() throws {
        let r = try Self.reference
        #expect(r.moments.count == 8)
        #expect(Set(r.moments.map { $0.utc.prefix(4) }).count >= 6)
        #expect(Set(r.planets.keys) == Set(Planet.allCases.map(\.rawValue)))
        #expect(r.planets.values.allSatisfy { $0.count == 8 })
    }

    @Test("положение на небе: до 0,5° у Венеры, Марса, Юпитера и Сатурна и до 1° у Меркурия — и по восхождению/склонению, и после перевода в азимут и высоту")
    func positionsMatchHorizons() throws {
        let s = try Self.measure()
        for x in s {
            let tol = Self.tolerance(x.planet)
            #expect(x.equatorial <= tol, "\(x.planet) \(x.utc): RA/Dec \(x.equatorial)°")
            #expect(x.horizontal <= tol, "\(x.planet) \(x.utc): Az/El \(x.horizontal)°")
        }
        for p in Planet.allCases {
            let m = s.filter { $0.planet == p }
            print("planet-check \(p.rawValue): max RA/Dec \(String(format: "%.4f", m.map(\.equatorial).max()!))°, max Az/El \(String(format: "%.4f", m.map(\.horizontal).max()!))°")
        }
    }

    @Test("видимая величина: в пределах 0,3 от Horizons; удаление от Солнца — в пределах 0,5°")
    func magnitudeAndElongation() throws {
        let s = try Self.measure()
        for x in s {
            #expect(x.magnitude <= 0.3, "\(x.planet) \(x.utc): величина \(x.magnitude)")
            #expect(x.elongation <= 0.5, "\(x.planet) \(x.utc): удаление от Солнца \(x.elongation)°")
        }
        for x in s { print("planet-row \(x.planet) \(x.utc) mag \(String(format: "%.3f", x.magnitude)) elong \(String(format: "%.3f", x.elongation)) eq \(String(format: "%.4f", x.equatorial)) hor \(String(format: "%.4f", x.horizontal))") }
        for p in Planet.allCases {
            let m = s.filter { $0.planet == p }
            print("planet-check \(p.rawValue): max mag \(String(format: "%.3f", m.map(\.magnitude).max()!)), max elong \(String(format: "%.3f", m.map(\.elongation).max()!))°")
        }
    }

    @Test("густая сетка: 60 моментов через 42 суток (2024–2030), 300 строк — положение до 0,1° и блеск до 0,3, пока планета дальше 15° от Солнца")
    func denseGrid() throws {
        let dense = try Self.reference.dense
        var worstPosition = 0.0, worstMagnitude = 0.0, tested = 0
        var worstByPlanet: [Planet: Double] = [:]
        for planet in Planet.allCases {
            for (jd, row) in zip(dense.jds, dense.planets[planet.rawValue]!) {
                let got = PlanetEphemeris.position(planet, days: jd - 2_451_545.0)
                let a = HorizontalPoint(altitude: got.point.dec * 180 / .pi, azimuth: got.point.ra * 180 / .pi)
                let sep = Self.separation(a, HorizontalPoint(altitude: row.dec, azimuth: row.ra))
                worstPosition = max(worstPosition, sep)
                #expect(sep <= 0.1, "\(planet) jd \(jd): \(sep)°")
                guard row.elong >= PlanetVisibility.nearSun else { continue }
                tested += 1
                let dm = abs(got.magnitude - row.mag)
                worstMagnitude = max(worstMagnitude, dm)
                worstByPlanet[planet] = max(worstByPlanet[planet] ?? 0, dm)
                #expect(dm <= 0.3, "\(planet) jd \(jd): величина \(got.magnitude) против \(row.mag)")
            }
        }
        #expect(tested > 200)
        print("planet-dense: строк \(tested), положение до \(String(format: "%.4f", worstPosition))°, блеск до \(String(format: "%.3f", worstMagnitude)); по планетам: \(Planet.allCases.map { "\($0.rawValue) \(String(format: "%.3f", worstByPlanet[$0] ?? 0))" })")
    }
}
