import Testing
import Foundation
@testable import LightPlanCore

/// Единое звёздное время слоёв AR (шаг 29.8в.21) против JPL Horizons: Солнце, Луна, Юпитер, Сириус на десяти парах
/// «место, момент» 2026–2030. Эталон — `Fixtures/sky_time_horizons.json`, собирается `python3 Tools/sky_time_ref.py`.
/// Замеры идут через настоящие входы слоёв AR (`SunTrack`, `MoonTrack`, `PlanetSkyAR`, `StarSkyAR`), а «до» — через
/// прежние функции веба, которые остались для паритета.
struct SkyTimeTests {

    struct Reference: Decodable {
        struct Body: Decodable { let ra, dec, az, el: Double }
        struct Case: Decodable {
            let place: String
            let latitude, longitude: Double
            let utc: [Int]
            let jd: Double
            let lastHours: Double
            let bodies: [String: Body]
            enum CodingKeys: String, CodingKey { case place, latitude, longitude, utc, jd, bodies, lastHours = "last_hours" }
        }
        let cases: [Case]
    }

    static let loaded: Result<Reference, Error> = Result { try ParityFixtures.load("sky_time_horizons.json", as: Reference.self) }
    static var reference: Reference { get throws { try loaded.get() } }

    static func separation(_ a: HorizontalPoint, _ b: HorizontalPoint) -> Double {
        let u = SkyVector(azimuth: a.azimuth, altitude: a.altitude), v = SkyVector(azimuth: b.azimuth, altitude: b.altitude)
        return acos(min(1, max(-1, u.dot(v)))) * 180 / Double.pi
    }

    static func truth(_ b: Reference.Body) -> HorizontalPoint { HorizontalPoint(altitude: b.el, azimuth: b.az) }

    static let utc = ZoneID(fixedOffsetHours: 0)

    /// Что слои AR дают на момент эталона: через входы слоёв (после) и через прежние функции веба (до).
    struct Layers {
        let after: [String: HorizontalPoint]
        let before: [String: HorizontalPoint]
    }

    static func layers(_ c: Reference.Case) -> Layers {
        let place = Place(latitude: c.latitude, longitude: c.longitude, zone: utc)
        let days = c.jd - 2_451_545.0
        let day = CivilDate(daysSince1970: Int((c.jd - 2_440_587.5).rounded(.down)))
        let minutes = ((c.jd - 2_440_587.5) - Double(day.daysSince1970)) * 1440
        let sunNow = SunTrack.sample(day: day, minutes: minutes, in: place)
        let solar = SolarDay(date: day, place: place)
        let moonNow = MoonTrack.sample(day: day, minutes: minutes, in: place)
        let moonWeb = MoonSample(date: day, minutes: minutes, place: place)
        let jupiter = PlanetSkyAR.samples(day: day, minutes: minutes, in: place).first { $0.planet == .jupiter }!
        let jp = PlanetEphemeris.position(.jupiter, days: days)
        let sir = StarName.brightest[0]
        let sirius = SkyStar(ra: sir.ra, dec: sir.dec, magnitude: -1.46)
        let sky = StarSkyAR.horizontals(catalog: StarCatalogAR(stars: [sirius], figures: []), day: day, minutes: minutes, in: place)[0]
        let after: [String: HorizontalPoint] = [
            "sun": HorizontalPoint(altitude: sunNow.altitude, azimuth: sunNow.azimuth),
            "moon": HorizontalPoint(altitude: moonNow.altitude, azimuth: moonNow.azimuth),
            "jupiter": jupiter.horizontal, "sirius": sky]
        let before: [String: HorizontalPoint] = [
            "sun": HorizontalPoint(altitude: solar.elevation(at: minutes), azimuth: solar.azimuth(at: minutes)),
            "moon": HorizontalPoint(altitude: moonWeb.altitude, azimuth: moonWeb.azimuth),
            "jupiter": Sky.horizontal(jp.point, days: days, latitude: c.latitude, longitude: c.longitude),
            "sirius": Sky.horizontal(ra: sir.ra * Double.pi / 12, dec: Sky.rad(sir.dec), days: days,
                                     latitude: c.latitude, longitude: c.longitude)]
        return Layers(after: after, before: before)
    }

    /// Допуск шага против Horizons, градусы (Луна — геоцентрическая, без параллакса, как в приложении).
    static let tolerance: [String: Double] = ["sun": 0.05, "moon": 0.1, "jupiter": 0.05, "sirius": 0.05]

    // MARK: - Звёздное время

    @Test("GMST: J2000 — 18h41m50,55s; формула сходится с Horizons на десяти моментах 2026–2030 до 0,006° (нутация)")
    func greenwichMean() throws {
        // 18h 41m 50,54841s = 280,46061837° (Astronomical Almanac): ровно константа формулы.
        #expect(abs(SiderealTime.greenwichMean(days: 0) - (18 + 41.0 / 60 + 50.54841 / 3600) * 15) < 1e-6)
        #expect(SiderealTime.greenwichMean(days: -1e6) >= 0 && SiderealTime.greenwichMean(days: 1e6) < 360)
        for c in try Self.reference.cases {
            let local = SiderealTime.localMean(days: c.jd - 2_451_545.0, longitude: c.longitude)
            let diff = abs((local - c.lastHours * 15 + 540).truncatingRemainder(dividingBy: 360) - 180)
            #expect(diff < 0.006, "\(c.place) \(c.utc): \(diff)°")
        }
    }

    @Test("веб-формула `Sky.horizontal` осталась: на 2026 год отстаёт от IAU на 0,5° (паритет держится на ней)")
    func webTimeKept() throws {
        let d = 9_788.0   // 2026-10-19
        let web = 280.16 + 360.9856235 * d
        let lag = SiderealTime.greenwichMean(days: d) - web.truncatingRemainder(dividingBy: 360)
        #expect(abs(lag - 0.53) < 0.03, "\(lag)")
    }

    // MARK: - Против Horizons

    @Test("Солнце ≤ 0,05°, Юпитер ≤ 0,05°, Сириус ≤ 0,05°, Луна ≤ 0,1° — на десяти моментах, через входы слоёв AR")
    func againstHorizons() throws {
        for c in try Self.reference.cases {
            let l = Self.layers(c)
            for (body, tol) in Self.tolerance {
                let err = Self.separation(l.after[body]!, Self.truth(c.bodies[body]!))
                #expect(err <= tol, "\(body) \(c.place) \(c.utc): \(err)° > \(tol)°")
            }
        }
    }

    @Test("в одном кадре Солнце, Луна, Юпитер и Сириус стоят друг от друга как на самом деле: расхождение пар ≤ 0,05°")
    func relativeFrame() throws {
        let names = ["sun", "moon", "jupiter", "sirius"]
        for c in try Self.reference.cases {
            let l = Self.layers(c)
            for i in names.indices { for j in names.indices where j > i {
                let got = Self.separation(l.after[names[i]]!, l.after[names[j]]!)
                let want = Self.separation(Self.truth(c.bodies[names[i]]!), Self.truth(c.bodies[names[j]]!))
                #expect(abs(got - want) <= 0.05, "\(names[i])–\(names[j]) \(c.place) \(c.utc): \(got) против \(want)")
            } }
        }
    }

    @Test("до исправления: планеты и звёзды стояли на 0,2–0,55° мимо (то, что чинит шаг) — защита от тихого возврата")
    func beforeWasWorse() throws {
        var worstJupiter = 0.0, worstSirius = 0.0
        for c in try Self.reference.cases {
            let l = Self.layers(c)
            worstJupiter = max(worstJupiter, Self.separation(l.before["jupiter"]!, Self.truth(c.bodies["jupiter"]!)))
            worstSirius = max(worstSirius, Self.separation(l.before["sirius"]!, Self.truth(c.bodies["sirius"]!)))
        }
        #expect(worstJupiter > 0.45 && worstSirius > 0.2)
    }

    // MARK: - Маршрутизация: каждый слой AR идёт через `SkyFrame`

    static let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    static let day = CivilDate(year: 2026, month: 10, day: 19)

    static func frame(minutes: Minutes) -> SkyFrame {
        let d = Sky.days(date: day, minutes: minutes, utcOffsetHours: tomsk.zone.utcOffsetHours(on: day))
        return SkyFrame(days: d, latitude: tomsk.latitude, longitude: tomsk.longitude)
    }

    static func days(_ minutes: Minutes) -> Double {
        Sky.days(date: day, minutes: minutes, utcOffsetHours: tomsk.zone.utcOffsetHours(on: day))
    }

    @Test("Солнце AR — SunMoonTheory.sun через SkyFrame; дуга той же формулы")
    func sunRouting() {
        let m = 15 * 60.0
        let want = Self.frame(minutes: m).horizontal(ofDate: SunMoonTheory.sun(days: Self.days(m)))
        let got = SunTrack.sample(day: Self.day, minutes: m, in: Self.tomsk)
        #expect(got.altitude == want.altitude && got.azimuth == want.azimuth)
        let arc = SunTrack.arc(day: Self.day, in: Self.tomsk)
        #expect(arc[90].altitude == SunTrack.sample(day: Self.day, minutes: 900, in: Self.tomsk).altitude)
    }

    @Test("Луна AR — MoonSample(time: .iau): теория Меёса и SkyFrame; без параметра остаётся веб")
    func moonRouting() {
        let m = 21 * 60.0
        let want = Self.frame(minutes: m).horizontal(ofDate: SunMoonTheory.moon(days: Self.days(m)).point)
        let got = MoonTrack.sample(day: Self.day, minutes: m, in: Self.tomsk)
        #expect(got.altitude == want.altitude && got.azimuth == want.azimuth)
        let web = MoonSample(date: Self.day, minutes: m, place: Self.tomsk)
        #expect(web.altitude != got.altitude, "по умолчанию — веб-модель, паритет «Света» не тронут")
    }

    @Test("планеты AR — SkyFrame в координатах даты")
    func planetRouting() {
        let m = 22 * 60.0, d = Self.days(m)
        let p = PlanetEphemeris.position(.saturn, days: d)
        let want = Self.frame(minutes: m).horizontal(ofDate: p.point)
        let got = PlanetEphemeris.horizontal(p, days: d, latitude: Self.tomsk.latitude, longitude: Self.tomsk.longitude)
        #expect(got == want)
    }

    @Test("звёзды AR — SkyFrame с прецессией J2000; веб-функция даёт другое число")
    func starRouting() {
        let m = 23 * 60.0
        let star = SkyStar(ra: 14.261, dec: 19.18, magnitude: -0.05)
        let got = StarSkyAR.horizontals(catalog: StarCatalogAR(stars: [star], figures: []), day: Self.day, minutes: m, in: Self.tomsk)[0]
        let point = EquatorialPoint(ra: star.ra * Double.pi / 12, dec: Sky.rad(star.dec))
        #expect(got == Self.frame(minutes: m).horizontal(j2000: point))
        let web = Sky.horizontal(point, days: Self.days(m), latitude: Self.tomsk.latitude, longitude: Self.tomsk.longitude)
        #expect(Self.separation(got, web) > 0.05)
    }

    @Test("Млечный Путь AR: ядро, середина и края полосы, оси кадра — SkyFrame в координатах J2000")
    func milkyWayRouting() throws {
        let m = 23 * 60.0
        let f = Self.frame(minutes: m)
        #expect(MilkyWayAR.core(day: Self.day, minutes: m, in: Self.tomsk) == f.horizontal(j2000: MilkyWay.core))
        let center = MilkyWayAR.center(day: Self.day, minutes: m, in: Self.tomsk)
        #expect(center.indices.allSatisfy { center[$0] == f.horizontal(j2000: MilkyWay.band[$0].center) })
        let band = MilkyWayAR.band(day: Self.day, minutes: m, in: Self.tomsk)
        let edge = MilkyWay.equatorial(galacticLongitude: MilkyWay.band[10].longitude, galacticLatitude: MilkyWay.band[10].halfWidth)
        #expect(band[10].left == f.horizontal(j2000: edge))
        let look = MilkyWayLook.frame(day: Self.day, minutes: m, in: Self.tomsk)
        let x = f.horizontal(j2000: MilkyWay.equatorial(galacticLongitude: 0, galacticLatitude: 0))
        #expect(look.x == SkyVector(azimuth: x.azimuth, altitude: x.altitude))
    }

    @Test("слои веба на старом времени: Sky.horizontal, MilkyWay.corePosition и MoonSample по умолчанию не изменились")
    func webLayersUntouched() {
        let m = 23 * 60.0, d = Self.days(m)
        let web = MilkyWay.corePosition(date: Self.day, minutes: m, place: Self.tomsk)
        #expect(web == Sky.horizontal(MilkyWay.core, days: d, latitude: Self.tomsk.latitude, longitude: Self.tomsk.longitude))
        #expect(Self.separation(web, MilkyWay.corePosition(date: Self.day, minutes: m, place: Self.tomsk, time: .iau)) > 0.02,
                "прецессия гасит часть отставания веб-времени: у ядра разница мала, но не нулевая")
    }
}
