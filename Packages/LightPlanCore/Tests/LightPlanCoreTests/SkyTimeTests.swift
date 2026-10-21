import Testing
import Foundation
@testable import LightPlanCore

/// Единое звёздное время слоёв AR (шаг 29.8в.21) против JPL Horizons: Солнце, Луна, Юпитер, Сириус на десяти парах
/// «место, момент» 2026–2030. Эталон — `Fixtures/sky_time_horizons.json`, собирается `python3 Tools/sky_time_ref.py`.
/// Замеры идут через настоящие входы слоёв AR (`SunTrack`, `MoonTrack`, `PlanetSkyAR`, `StarSkyAR`), а «до» — через
/// прежние функции веба, которые остались для паритета.
struct SkyTimeTests {

    struct Reference: Decodable {
        struct Body: Decodable {
            let ra, dec, az, el: Double
            /// Горизонт места по Horizons (не из центра Земли), без рефракции; у звезды нет.
            let azTopo, elTopo: Double?
            enum CodingKeys: String, CodingKey { case ra, dec, az, el, azTopo = "az_topo", elTopo = "el_topo" }
        }
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

    /// Эталон: где тело видно с поверхности Земли (топоцентрически); у Сириуса — своя математика, параллакса нет.
    static func truth(_ b: Reference.Body) -> HorizontalPoint {
        HorizontalPoint(altitude: b.elTopo ?? b.el, azimuth: b.azTopo ?? b.az)
    }

    /// Луна из центра Земли: то, что слой AR показывал до шага 29.8в.23.
    static func geocentricMoon(_ c: Reference.Case) -> HorizontalPoint {
        let days = c.jd - 2_451_545.0
        return SkyFrame(days: days, latitude: c.latitude, longitude: c.longitude)
            .horizontal(ofDate: SunMoonTheory.moon(days: days).point)
    }

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

    /// Допуск шага против Horizons, градусы; Луна — топоцентрическая (шаг 29.8в.23: было 0,1 против центра Земли).
    static let tolerance: [String: Double] = ["sun": 0.05, "moon": 0.05, "jupiter": 0.05, "sirius": 0.05]

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

    @Test("Солнце, Луна (с параллаксом), Юпитер, Сириус ≤ 0,05° против Horizons — на десяти моментах, через входы слоёв AR")
    func againstHorizons() throws {
        for c in try Self.reference.cases {
            let l = Self.layers(c)
            for (body, tol) in Self.tolerance {
                let err = Self.separation(l.after[body]!, Self.truth(c.bodies[body]!))
                #expect(err <= tol, "\(body) \(c.place) \(c.utc): \(err)° > \(tol)°")
            }
        }
    }

    @Test("Луна: ошибка против Horizons топоцентрической до (из центра Земли) и после параллакса — таблица на десяти моментах")
    func moonParallaxTable() throws {
        var worstBefore = 0.0, worstAfter = 0.0
        var table = "\nместо / момент UTC         до°     после°   параллакс°  высота°\n"
        for c in try Self.reference.cases {
            let truth = Self.truth(c.bodies["moon"]!)
            let before = Self.separation(Self.geocentricMoon(c), truth)
            let after = Self.separation(Self.layers(c).after["moon"]!, truth)
            let shift = Self.separation(Self.geocentricMoon(c), Self.layers(c).after["moon"]!)
            worstBefore = max(worstBefore, before); worstAfter = max(worstAfter, after)
            table += String(format: "%@ %@  %.3f   %.3f   %.3f   %.1f\n", c.place, "\(c.utc)", before, after, shift, truth.altitude)
        }
        print(table)
        #expect(worstAfter <= 0.05, "после: \(worstAfter)°")
        #expect(worstBefore > 0.5, "до параллакса Луна стояла на ~1° мимо: \(worstBefore)° — иначе проверка ничего не доказывает")
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

    @Test("Луна AR — MoonSample(time: .iau): теория Меёса, SkyFrame и параллакс; без параметра остаётся веб")
    func moonRouting() {
        let m = 21 * 60.0
        let theory = SunMoonTheory.moon(days: Self.days(m))
        let want = Self.frame(minutes: m).horizontal(ofDate: theory.point, distanceKm: theory.distance)
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

/// Суточный параллакс Луны (шаг 29.8в.23): сдвиг вниз на `asin(R / расстояние) · cos(высота)`, в зените нуля.
struct MoonParallaxTests {

    static let day = CivilDate(year: 2026, month: 10, day: 19)

    /// Луна в заданной высоте и азимуте (геоцентрически) → её же с поверхности Земли.
    static func shift(altitude: Double, azimuth: Double = 150, latitude: Double = 56.5, distance: Double = 384_400)
        -> (geo: HorizontalPoint, topo: HorizontalPoint, sep: Double) {
        let frame = SkyFrame(days: 9_788.3, latitude: latitude, longitude: 85)
        // Точка неба → экваториальные координаты даты через обратный перевод (поиск по сетке не нужен: сфера в векторах).
        let phi = Sky.rad(latitude), a = Sky.rad(azimuth), h = Sky.rad(altitude)
        let dec = asin(sin(phi) * sin(h) + cos(phi) * cos(h) * cos(a))
        let hourAngle = atan2(-sin(a) * cos(h), sin(h) * cos(phi) - cos(h) * cos(a) * sin(phi))
        let lst = Sky.rad(SiderealTime.localMean(days: 9_788.3, longitude: 85))
        let point = EquatorialPoint(ra: lst - hourAngle, dec: dec)
        let geo = frame.horizontal(ofDate: point)
        let topo = frame.horizontal(ofDate: point, distanceKm: distance)
        return (geo, topo, SkyTimeTests.separation(geo, topo))
    }

    @Test("в зените параллакса нет, на горизонте ≈ 0,95°, между ними — cos высоты")
    func zenithAndHorizon() {
        let pi = Sky.deg(asin(SkyFrame.earthEquatorialRadiusKm / 384_400))   // горизонтальный параллакс, ≈ 0,951°
        #expect(abs(pi - 0.951) < 0.002)
        #expect(Self.shift(altitude: 89.99).sep < 0.01)
        let horizon = Self.shift(altitude: 0.0).sep
        #expect(abs(horizon - pi) < 0.01, "\(horizon)")
        for alt in [15.0, 30, 45, 60] {
            let s = Self.shift(altitude: alt, latitude: 0).sep
            #expect(abs(s - pi * cos(Sky.rad(alt))) < 0.01, "\(alt)°: \(s)")
        }
    }

    @Test("Луна уходит вниз к горизонту, азимут почти не меняется; на полюсе Земли — только вниз по высоте")
    func direction() {
        let s = Self.shift(altitude: 20)
        #expect(s.topo.altitude < s.geo.altitude)
        #expect(abs(s.topo.azimuth - s.geo.azimuth) < 0.1)
        let pole = Self.shift(altitude: 30, latitude: 89.9)
        #expect(pole.topo.altitude < pole.geo.altitude - 0.7)
    }

    @Test("расстояние всерьёз: в перигее сдвиг больше, в апогее меньше")
    func distanceMatters() {
        let near = Self.shift(altitude: 5, distance: 356_500).sep, far = Self.shift(altitude: 5, distance: 406_700).sep
        #expect(near > far + 0.1)
    }

    @Test("высота наблюдателя 3 км меняет Луну не больше чем на 0,005°")
    func height() {
        let frame = SkyFrame(days: 9_788.3, latitude: 30, longitude: 85)
        let p = EquatorialPoint(ra: 1.0, dec: 0.2)
        let a = frame.horizontal(ofDate: p, distanceKm: 384_400), b = frame.horizontal(ofDate: p, distanceKm: 384_400, heightMeters: 3000)
        #expect(SkyTimeTests.separation(a, b) < 0.005)
    }

    @Test("AR-Луна — топоцентрическая, Луна «Света» (веб) осталась геоцентрической; Солнце, планеты, звёзды прежние")
    func onlyMoonMoved() {
        let place = SkyTimeTests.tomsk, m = 21 * 60.0, d = SkyTimeTests.days(m)
        let ar = MoonTrack.sample(day: SkyTimeTests.day, minutes: m, in: place)
        let geo = SkyTimeTests.frame(minutes: m).horizontal(ofDate: SunMoonTheory.moon(days: d).point)
        #expect(ar.altitude < geo.altitude, "AR-Луна опустилась на параллакс")
        let web = MoonSample(date: SkyTimeTests.day, minutes: m, place: place)
        #expect(web == MoonSample(date: SkyTimeTests.day, minutes: m, place: place, time: .web))
        let f = SkyTimeTests.frame(minutes: m)
        // Вход без расстояния (Солнце, планеты, каталожные точки) параллакса не получает.
        let sun = SunMoonTheory.sun(days: d)
        let got = SunTrack.sample(day: SkyTimeTests.day, minutes: m, in: place)
        #expect(got.azimuth == f.horizontal(ofDate: sun).azimuth && got.altitude == f.horizontal(ofDate: sun).altitude)
    }
}
