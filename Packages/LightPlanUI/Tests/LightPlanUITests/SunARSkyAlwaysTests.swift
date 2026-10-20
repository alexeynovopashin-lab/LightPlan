import Testing
import SwiftUI
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData

/// Шаг 29.8в.18: слои неба рисуются всегда — днём, при солнце +60°, тоже; видимость глазом — справка со словами; затемняющая
/// маска идёт от разности выбранного момента и настоящего неба.
@MainActor
struct SunARSkyAlwaysTests {

    private let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    /// Сочи: в июне солнце в полдень выше 69° (Томск до 57°).
    private let sochi = Place(latitude: 43.585, longitude: 39.72, zone: ZoneID("Europe/Moscow")!)
    private let viewport = ScreenViewport(width: 393, height: 852)
    private let size = CGSize(width: 393, height: 852)
    private final class MemoryFlag: ARCalibrationFlag { var seen = true }
    private final class MemoryBodies: ARBodiesSettings {
        var moon = false, milkyWay = false, stars = false, constellations = false, planets = false
    }
    private func moment(_ iso: String) -> Moment { Moment(ISO8601DateFormatter().date(from: iso)!) }
    private func model(_ iso: String, now: String? = nil, place: Place? = nil) -> SunARModel {
        let n = moment(now ?? iso)
        return SunARModel(target: SunARTarget(place: place ?? tomsk, moment: moment(iso)), source: nil, camera: nil,
                          clock: { n }, calibrationFlag: MemoryFlag(), bodies: MemoryBodies())
    }

    // MARK: Слои рисуются при солнце +60°

    @Test("солнце +60°: звёзды, созвездия, подписи и планеты нарисованы так же, как ночью; в списке — «днём не видно» с высотой солнца")
    func drawnAtSunPlus60() throws {
        let m = model("2026-06-21T09:20:00Z", place: sochi)
        #expect(m.sun.altitude > 60, "солнце \(m.sun.altitude)°")
        m.setStars(true); m.setConstellations(true); m.setPlanets(true)
        let basis = CameraBasis(azimuth: 180, altitude: 35)
        let stars = try #require(m.starScene(basis: basis, optics: .typical, viewport: viewport))
        #expect(!stars.dots.isEmpty && !stars.segments.isEmpty && !stars.figures.isEmpty,
                "точек \(stars.dots.count), линий \(stars.segments.count), фигур \(stars.figures.count)")
        // Яркость точки — по величине звезды, без множителя «день»: у самой яркой точки полная.
        #expect(stars.dots.contains { $0.brightness == StarLook.brightness(magnitude: $0.magnitude) })
        #expect(stars.dots.allSatisfy { $0.brightness >= 0.4 }, "днём яркость точек осталась как ночью")

        // Подписи слоя ставятся днём (раньше при дне их не было вовсе).
        let st = stack(m, aim: basis)
        #expect(!st.starLabels(stars).isEmpty, "днём нет ни одной подписи звезды или созвездия")

        // Планеты: берём первую над горизонтом и не ближе 15° к Солнцу — она в сцене.
        let samples = PlanetSkyAR.samples(day: m.day, minutes: m.minutes, in: sochi)
        let up = samples.filter { !PlanetVisibility.isNearSun(elongation: $0.elongation) && $0.horizontal.altitude > 8 }
        let pick = try #require(up.first, "в этот день ни одна планета не стоит над горизонтом")
        let aimed = CameraBasis(azimuth: pick.horizontal.azimuth, altitude: pick.horizontal.altitude)
        let planets = try #require(m.planetScene(basis: aimed, optics: .typical, viewport: viewport))
        #expect(planets.dots.map(\.planet).contains(pick.planet), "днём планета \(pick.planet) не нарисована")

        // Справка: слово «днём не видно» и высота солнца, число с настоящим минусом/плюсом.
        let line = try #require(SunARSkyNotes.eyeLine(m.skyEyeCauses, Lexicon("ru")))
        #expect(line == "днём не видно: солнце +\(Int(m.sun.altitude.rounded()))°", "\(line)")
    }

    @Test("тот же вид ночью — тот же рисунок: сцена звёзд не знает про солнце, меняется только положение неба")
    func sceneIgnoresTheSun() {
        // Один и тот же список положений даёт одну и ту же сцену, как бы ни стояло солнце: у `StarSkyAR.make` и `PlanetSkyAR.make`
        // входа «высота солнца» больше нет.
        let pos = StarSkyAR.horizontals(day: CivilDate(year: 2026, month: 10, day: 20), minutes: 1260, in: tomsk)
        let a = StarSkyAR.make(positions: pos, basis: CameraBasis(azimuth: 30, altitude: 40), optics: .typical,
                               viewport: viewport, stars: true, constellations: true)
        let b = StarSkyAR.make(positions: pos, basis: CameraBasis(azimuth: 30, altitude: 40), optics: .typical,
                               viewport: viewport, stars: true, constellations: true)
        #expect(a == b && !a.dots.isEmpty)
    }

    /// Стек так, как его собирает экран.
    private func stack(_ m: SunARModel, aim: CameraBasis) -> SunARSkyStack {
        let scene = SunARScene.make(basis: aim, optics: .typical, viewport: viewport, arc: m.arc, sun: m.sun, now: m.sunNow,
                                    pickedIsNow: m.pickedIsNow, solar: m.solar)
        let night = m.nightScene(basis: aim, optics: .typical, viewport: viewport)
        let marks = SunARMarks.make(sun: scene, night: night, screen: size)
        return SunARSkyStack(scene: scene, night: night, marks: marks, size: size, clock: ClockText(language: "ru"),
                             cardinals: ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"], coreLabel: "Ядро",
                             eventText: { _ in "закат" }, pickedText: nil, sky: nil,
                             starName: { Lexicon("ru").t($0) },
                             starWindow: CGRect(x: 0, y: 140, width: 393, height: 520))
    }

    // MARK: Справка словами

    @Test("справка под словами слоёв: день, сумерки и засветка — на пяти языках, число подставлено; ничто не мешает — строки нет")
    func eyeLineWords() {
        let causes: [SkyEyeNote.Cause] = [.twilight(sun: -9), .glow(.city, value: 12)]
        for code in ["ru", "en", "es", "ja", "zh"] {
            let t = Lexicon(code)
            let day = SunARSkyNotes.eyeLine([.daylight(sun: 35)], t)!
            #expect(day.contains("+35") && !day.contains("{"), "\(code): \(day)")
            let tw = SunARSkyNotes.eyeLine(causes, t)!
            #expect(tw.contains("−9") && tw.contains("12") && !tw.contains("{"), "\(code): \(tw)")
        }
        #expect(SunARSkyNotes.eyeLine([], Lexicon("ru")) == nil)
        #expect(SunARSkyNotes.eyeLine([.daylight(sun: 35)], Lexicon("ru")) == "днём не видно: солнце +35°")
        #expect(SunARSkyNotes.eyeLine([.twilight(sun: -9), .glow(.city, value: 12)], Lexicon("ru")) == "сумерки, солнце −9° · город, засветка 12")
        #expect(SunARSkyNotes.eyeLine([.glow(.faint, value: 4.2)], Lexicon("ru")) == "слабая засветка 4.2")
    }

    // MARK: Маска в модели

    @Test("маска: выбрана ночь, настоящее небо светлое, слой включён — полная; слоёв нет, только Луна или настоящая ночь — нет")
    func maskInModel() {
        // Выбран вечер 21:00 (солнце глубоко под горизонтом), «сейчас» — полдень.
        let night = "2026-10-20T14:00:00Z", noon = "2026-10-20T06:00:00Z"
        let m = model(night, now: noon)
        #expect(m.sun.altitude < -18 && m.sunNow.altitude > 15, "выбрано \(m.sun.altitude)°, сейчас \(m.sunNow.altitude)°")
        #expect(m.maskOpacity == 0, "слоёв нет — маски нет")
        m.setMoon(true)
        #expect(m.maskOpacity == 0, "Луна — не слой неба для маски")
        for on in [{ m.setStars(true) }, { m.setStars(false); m.setConstellations(true) },
                   { m.setConstellations(false); m.setPlanets(true) }, { m.setPlanets(false); m.setMilkyWay(true) }] {
            on()
            #expect(m.skyLayerOn && m.maskOpacity == SkyMask.maxOpacity)
        }
        m.setMilkyWay(false)
        #expect(!m.skyLayerOn && m.maskOpacity == 0)
        // Настоящая ночь: те же слои и тот же выбранный момент, маски нет.
        let real = model(night, now: night)
        real.setStars(true)
        #expect(real.maskOpacity == 0)
        // Выбран день при светлом настоящем небе: маски нет.
        let dayPick = model(noon, now: noon)
        dayPick.setStars(true)
        #expect(dayPick.maskOpacity == 0)
        // Ползунок едет к ночи: непрозрачность только растёт и не превышает потолок.
        var last = -1.0
        for hour in 6...14 {
            let x = model(String(format: "2026-10-20T%02d:00:00Z", hour), now: noon)
            x.setStars(true)
            #expect(x.maskOpacity >= last - 1e-12 && x.maskOpacity <= SkyMask.maxOpacity)
            last = x.maskOpacity
        }
    }
}
