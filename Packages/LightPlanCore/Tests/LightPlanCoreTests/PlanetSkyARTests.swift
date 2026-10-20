import Testing
import Foundation
import LightPlanCore

/// Слой планет в AR (шаг 29.8в.15): «рядом с Солнцем», горизонт, вид точки.
struct PlanetSkyARTests {

    static let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    static let viewport = ScreenViewport(width: 393, height: 852)

    /// Планета на заданных высоте и азимуте, с заданными блеском и удалением от Солнца.
    private func sample(_ p: Planet, alt: Double, az: Double = 150, mag: Double = -2, elong: Double = 60) -> PlanetSample {
        PlanetSample(planet: p, horizontal: HorizontalPoint(altitude: alt, azimuth: az), magnitude: mag, elongation: elong)
    }

    private func scene(_ samples: [PlanetSample], aimAz: Double = 150, aimAlt: Double = 30) -> PlanetSkyARScene {
        PlanetSkyAR.make(samples: samples, basis: CameraBasis(azimuth: aimAz, altitude: aimAlt),
                         optics: .typical, viewport: Self.viewport)
    }

    @Test("планета ближе 15° к Солнцу не рисуется и попадает в «рядом с Солнцем»; ровно 15° и дальше — рисуется")
    func nearTheSun() {
        let s = scene([sample(.venus, alt: 30, elong: 14.9), sample(.mercury, alt: 30, az: 160, elong: 15.0),
                       sample(.mars, alt: 30, az: 140, elong: 90)])
        #expect(s.dots.map(\.planet).contains(.mercury) && s.dots.map(\.planet).contains(.mars))
        #expect(!s.dots.map(\.planet).contains(.venus))
        #expect(s.nearSun == [.venus])
        // Подпись «рядом с Солнцем» не зависит от горизонта: под горизонтом планета тоже в лучах.
        #expect(scene([sample(.venus, alt: -20, elong: 5)]).nearSun == [.venus])
    }

    @Test("под горизонтом планета не рисуется; на горизонте и выше — рисуется (видимая высота, с рефракцией, как у звёзд)")
    func horizon() {
        let s = scene([sample(.jupiter, alt: -5), sample(.saturn, alt: 10, az: 155), sample(.mars, alt: -0.2, az: 145)], aimAlt: 5)
        #expect(!s.dots.map(\.planet).contains(.jupiter))
        #expect(s.dots.map(\.planet).contains(.saturn))
        // −0,2° геометрических — над горизонтом после рефракции (≈ +0,5° у горизонта).
        #expect(SunTrack.apparent(altitude: -0.2) >= 0 && s.dots.map(\.planet).contains(.mars))
    }

    @Test("настоящий момент: Венера 19.10.2026 в 10° от Солнца — рядом с Солнцем; Сатурн в противостоянии виден всю ночь")
    func realMoment() {
        let day = CivilDate(year: 2026, month: 10, day: 19)
        let s = PlanetSkyAR.samples(day: day, minutes: 23 * 60, in: Self.tomsk)
        #expect(s.count == 5 && Set(s.map(\.planet)) == Set(Planet.allCases))
        let venus = s.first { $0.planet == .venus }!, saturn = s.first { $0.planet == .saturn }!
        #expect(venus.elongation < PlanetVisibility.nearSun)
        #expect(saturn.elongation > 150)
        let sc = PlanetSkyAR.make(samples: s, basis: CameraBasis(azimuth: saturn.horizontal.azimuth, altitude: max(5, saturn.horizontal.altitude)),
                                  optics: .typical, viewport: Self.viewport)
        #expect(sc.nearSun.contains(.venus) && !sc.dots.map(\.planet).contains(.venus))
        #expect(saturn.horizontal.altitude > 0 ? sc.dots.map(\.planet).contains(.saturn) : true)
    }

    @Test("слой идёт за выбранным моментом: через три часа небо повернулось, планета на другой высоте и в другом азимуте")
    func followsTheMoment() {
        let day = CivilDate(year: 2026, month: 10, day: 19)
        let a = PlanetSkyAR.samples(day: day, minutes: 21 * 60, in: Self.tomsk).first { $0.planet == .saturn }!
        let b = PlanetSkyAR.samples(day: day, minutes: 24 * 60, in: Self.tomsk).first { $0.planet == .saturn }!
        #expect(a.horizontal != b.horizontal)
        #expect(abs(a.horizontal.azimuth - b.horizontal.azimuth) > 20)
        // Тот же момент и место дают тот же результат.
        #expect(PlanetSkyAR.samples(day: day, minutes: 21 * 60, in: Self.tomsk).first { $0.planet == .saturn }! == a)
    }

    @Test("вид точки: Венера крупнее и ярче Марса, не больше 5 pt и не меньше 1,6 pt; цвета — Венера белая, Марс красный, Меркурий серый")
    func look() {
        #expect(PlanetLook.radius(magnitude: -4.4) > PlanetLook.radius(magnitude: 1.0))
        #expect(PlanetLook.radius(magnitude: -9) == 5 && PlanetLook.radius(magnitude: 6) == 1.6)
        #expect(abs(PlanetLook.radius(magnitude: -4.4) - 4.6) < 1e-9)
        #expect(PlanetLook.brightness(magnitude: -4) == 1 && PlanetLook.brightness(magnitude: 6) == 0.4)
        let v = PlanetLook.tint(.venus), m = PlanetLook.tint(.mars), me = PlanetLook.tint(.mercury)
        let j = PlanetLook.tint(.jupiter), s = PlanetLook.tint(.saturn)
        #expect(min(v.red, v.green, v.blue) > 0.94)
        #expect(m.red - m.blue > 0.5 && m.red - m.green > 0.4)
        #expect(max(me.red, me.green, me.blue) - min(me.red, me.green, me.blue) < 0.05 && me.red < 0.8)
        #expect(j.red > j.green && j.green > j.blue && j.red - j.blue < 0.35)
        #expect(s.red - s.blue > 0.3 && s.green > s.blue && s.green - m.green > 0.3)
        #expect(Set(Planet.allCases.map { "\(PlanetLook.tint($0))" }).count == 5)
    }

    @Test("слова: ключ имени у каждой планеты свой и в формате planet.<имя>")
    func keys() {
        #expect(Planet.allCases.map(\.nameKey) == ["planet.mercury", "planet.venus", "planet.mars", "planet.jupiter", "planet.saturn"])
    }
}
