import Testing
import SwiftUI
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData

/// Слой «Планеты» на экране AR (шаг 29.8в.15): строка списка «Слоёв» и флаг, слова на пяти языках, момент и «Сейчас»,
/// «рядом с Солнцем», подписи не лежат на чужом (в том числе на подписях звёзд).
@MainActor
struct SunARPlanetsTests {

    private let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    private let viewport = ScreenViewport(width: 393, height: 852)
    private let size = CGSize(width: 393, height: 852)
    private final class MemoryFlag: ARCalibrationFlag { var seen = true }
    private final class MemoryBodies: ARBodiesSettings {
        var moon = false, milkyWay = false, stars = false, constellations = false, planets = false
    }
    private func moment(_ iso: String) -> Moment { Moment(ISO8601DateFormatter().date(from: iso)!) }
    private func model(_ iso: String, now: String? = nil, bodies: ARBodiesSettings = MemoryBodies()) -> SunARModel {
        let n = moment(now ?? iso)
        return SunARModel(target: SunARTarget(place: tomsk, moment: moment(iso)), source: nil, camera: nil,
                          clock: { n }, calibrationFlag: MemoryFlag(), bodies: bodies)
    }

    // MARK: Список «Слоёв» и флаг

    @Test("«Планеты» — строка списка со своим флагом устройства; по умолчанию выключена; помнится; планеты не считаются, пока слой выключен")
    func rowAndFlag() {
        let defaults = UserDefaults(suiteName: "sunar-planets-\(UUID().uuidString)")!
        let first = model("2026-10-20T14:00:00Z", bodies: DeviceBodiesSettings(defaults: defaults))
        #expect(!first.planetsOn && !first.layersOn.contains(.planets))
        #expect(first.planetScene(basis: CameraBasis(azimuth: 180, altitude: 30), optics: .typical, viewport: viewport) == nil)
        first.set(.planets, on: true)
        #expect(defaults.bool(forKey: "lightplan.native.sunar.planets") && DeviceBodiesSettings.planetsKey == "lightplan.native.sunar.planets")
        #expect(!defaults.bool(forKey: "lightplan.native.sunar.stars"), "флаг планет не должен трогать звёзды")
        #expect(model("2026-10-20T14:00:00Z", bodies: DeviceBodiesSettings(defaults: defaults)).planetsOn)
        #expect(SunARSkyLayer.allCases.last == .planets && SunARSkyLayer.planets.labelKey == "layer.planets")
        #expect(SunARSkyLayer.planets.node == "ar.layer.planets")
        #expect(!SunARSkyLayer.allCases.filter { $0 != .planets }.map { "\($0.tint)" }.contains("\(SunARSkyLayer.planets.tint)"))
    }

    @Test("слова слоя, «рядом с Солнцем» и пяти планет есть на всех пяти языках; подпись подставляет имя")
    func wordsInFiveLanguages() {
        let keys = ["layer.planets", "ar.planetNearSun"] + Planet.allCases.map(\.nameKey)
        for code in ["ru", "en", "es", "ja", "zh"] {
            let lexicon = Lexicon(code)
            for k in keys { #expect(lexicon.t(k) != k && !lexicon.t(k).isEmpty, "\(code): нет слова \(k)") }
            let line = lexicon.t("ar.planetNearSun", ["name": lexicon.t("planet.venus")])
            #expect(line.contains(lexicon.t("planet.venus")) && !line.contains("{name}"), "\(code): \(line)")
        }
        #expect(Lexicon("ru").t("ar.planetNearSun", ["name": "Венера"]) == "Венера: рядом с Солнцем")
        #expect(Lexicon("ru").t("planet.jupiter") == "Юпитер" && Lexicon("en").t("planet.saturn") == "Saturn")
    }

    // MARK: Момент, день, «рядом с Солнцем»

    @Test("слой идёт за выбранным моментом и местом; «Сейчас» возвращает на текущий момент")
    func pickedMomentAndNow() {
        let m = model("2026-10-20T14:00:00Z", now: "2026-10-20T17:00:00Z")
        m.setPlanets(true)
        let basis = CameraBasis(azimuth: 180, altitude: 30)
        let picked = m.planetScene(basis: basis, optics: .typical, viewport: viewport)!
        let samples = PlanetSkyAR.samples(day: m.day, minutes: m.minutes, in: tomsk)
        #expect(picked == PlanetSkyAR.make(samples: samples, basis: basis, optics: .typical, viewport: viewport))
        m.jumpToNow()
        let now = m.planetScene(basis: basis, optics: .typical, viewport: viewport)!
        #expect(now != picked, "после «Сейчас» небо не сдвинулось")
        let wall = SunTrack.wallClock(of: moment("2026-10-20T17:00:00Z"), in: tomsk)
        #expect(now == PlanetSkyAR.make(samples: PlanetSkyAR.samples(day: wall.day, minutes: wall.minutes, in: tomsk),
                                        basis: basis, optics: .typical, viewport: viewport))
    }

    @Test("список «Слоёв»: планета в 15° от Солнца подписана «Венера: рядом с Солнцем», остальные — нет")
    func statusLines() {
        // Ночь 19.10.2026: Венера в 10° от Солнца (замер против Horizons), Сатурн в противостоянии.
        let night = model("2026-10-19T16:00:00Z")
        let status = night.planetsNearSun
        #expect(status == [.venus], "рядом с Солнцем: \(status)")
        // Те же числа, что видит сцена: Венера не нарисована.
        night.setPlanets(true)
        let scene = night.planetScene(basis: CameraBasis(azimuth: 180, altitude: 30), optics: .typical, viewport: viewport)!
        #expect(scene.nearSun == [.venus] && !scene.dots.map(\.planet).contains(.venus))
    }

    // MARK: Подписи

    private let busy = CGRect(x: 0, y: 220, width: 393, height: 480)

    @Test("подпись планеты, которой сесть бы на занятое, уходит на другое место или не рисуется; подписи друг на друга не ложатся")
    func labelsNeverLandOnTheTaken() {
        let taken = [CGRect(x: 150, y: 380, width: 60, height: 60), CGRect(x: 280, y: 500, width: 44, height: 44)]
        let cands = [
            SunARPlanetLabels.Candidate(planet: .venus, text: "Венера", anchor: CGPoint(x: 180, y: 410), radius: 4.6),
            SunARPlanetLabels.Candidate(planet: .jupiter, text: "Юпитер", anchor: CGPoint(x: 100, y: 300), radius: 3.6),
            SunARPlanetLabels.Candidate(planet: .saturn, text: "Сатурн", anchor: CGPoint(x: 112, y: 330), radius: 2),
        ]
        let placed = SunARPlanetLabels.place(cands, taken: taken, window: busy)
        #expect(!placed.contains { $0.planet == .venus }, "Венера окружена занятым")
        for p in placed {
            #expect(busy.contains(p.rect))
            for t in taken { #expect(!p.rect.insetBy(dx: -SunARStarLabels.gap, dy: -SunARStarLabels.gap).intersects(t), "\(p.planet)") }
        }
        for (i, a) in placed.enumerated() { for b in placed[(i + 1)...] { #expect(!a.rect.intersects(b.rect), "\(a.planet) на \(b.planet)") } }
        #expect(placed.count == 2)
        #expect(SunARPlanetLabels.place([cands[0]], taken: [busy], window: busy).isEmpty)
        let edge = SunARPlanetLabels.Candidate(planet: .mars, text: "Марс", anchor: CGPoint(x: busy.minX + 2, y: busy.midY), radius: 2)
        #expect(SunARPlanetLabels.place([edge], taken: [CGRect(x: 0, y: busy.midY - 40, width: 40, height: 80)], window: busy).allSatisfy { busy.contains($0.rect) })
    }

    @Test("подпись одной планеты не ложится на точку другой, даже если подпись той ещё не поставлена (Марс и Юпитер рядом)")
    func labelNeverLandsOnAnotherPlanetsDot() {
        let mars = SunARPlanetLabels.Candidate(planet: .mars, text: "Марс", anchor: CGPoint(x: 200, y: 400), radius: 2)
        let jupiter = SunARPlanetLabels.Candidate(planet: .jupiter, text: "Юпитер", anchor: CGPoint(x: 214, y: 400), radius: 3.6)
        // Марс ставится первым: его первое место справа — ровно на точке Юпитера.
        let placed = SunARPlanetLabels.place([mars, jupiter], taken: [], window: busy)
        #expect(placed.count == 2)
        for p in placed {
            for c in [mars, jupiter] where c.planet != p.planet {
                #expect(!p.rect.intersects(SunARPlanetLabels.dotRect(c)), "подпись \(p.planet) на точке \(c.planet)")
            }
        }
        for (i, a) in placed.enumerated() { for b in placed[(i + 1)...] { #expect(!a.rect.intersects(b.rect), "\(a.planet) на \(b.planet)") } }
        // Без точек соседей та же подпись встала бы справа — на точку Юпитера (проверка, что тест про то).
        let alone = SunARPlanetLabels.place([mars], taken: [], window: busy)
        #expect(alone.first?.rect.intersects(SunARPlanetLabels.dotRect(jupiter)) == true)
    }

    @Test("подписи звёзд обходят подписи и точки планет: планета, чья подпись стоит на месте звёздной, оттесняет звёздную")
    func starLabelsAvoidPlanets() {
        // Венера и Сириус в одной точке: звезда выбирает первое место справа, планета — тоже справа.
        let dot = PlanetSkyARScene.Dot(planet: .venus, point: ScreenPoint(x: 200, y: 400), magnitude: -4.4, radius: 4.6,
                                       brightness: 1, azimuth: 150, altitude: 30)
        let scene = PlanetSkyARScene(dots: [dot], nearSun: [])
        let cands = SunARPlanetLabels.candidates(scene: scene, window: busy, name: { _ in "Венера" })
        let planetLabels = SunARPlanetLabels.place(cands, taken: [], window: busy)
        #expect(planetLabels.count == 1)
        let extra = SunARPlanetLabels.occupied(scene: scene, labels: planetLabels)
        #expect(extra.count == 2, "рамка подписи и пятно точки")
        let star = SunARStarLabels.Candidate(id: "star.sirius", kind: .star, text: "Сириус", anchor: CGPoint(x: 200, y: 400), radius: 3)
        let withPlanet = SunARStarLabels.place([star], taken: extra, window: busy)
        for p in withPlanet {
            for r in extra { #expect(!p.rect.insetBy(dx: -SunARStarLabels.gap, dy: -SunARStarLabels.gap).intersects(r), "звезда на планете") }
        }
        // Без планеты та же звезда встала бы на первое место справа — то самое, что занято подписью планеты.
        let without = SunARStarLabels.place([star], taken: [], window: busy)
        #expect(without.count == 1 && without[0].rect.intersects(planetLabels[0].rect.insetBy(dx: -SunARStarLabels.gap, dy: -SunARStarLabels.gap)))
        #expect(withPlanet.first?.center != without.first?.center)
    }

    /// Стек так, как его собирает экран, со звёздами и планетами.
    private func stack(_ m: SunARModel, aim: CameraBasis, planets override: PlanetSkyARScene? = nil,
                       pointerRects: [CGRect] = []) -> SunARSkyStack {
        let scene = SunARScene.make(basis: aim, optics: .typical, viewport: viewport, arc: m.arc, sun: m.sun, now: m.sunNow,
                                    pickedIsNow: m.pickedIsNow, solar: m.solar)
        let night = m.nightScene(basis: aim, optics: .typical, viewport: viewport)
        let marks = SunARMarks.make(sun: scene, night: night, screen: size)
        return SunARSkyStack(scene: scene, night: night, marks: marks, size: size, clock: ClockText(language: "ru"),
                             cardinals: ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"], coreLabel: "Ядро",
                             eventText: { _ in "закат" }, pickedText: nil, sky: nil,
                             starName: { Lexicon("ru").t($0) },
                             planets: override ?? m.planetScene(basis: aim, optics: .typical, viewport: viewport),
                             starWindow: CGRect(x: 0, y: 140, width: 393, height: 520), pointerRects: pointerRects)
    }

    @Test("на экране: подписи планеты, звёзд и созвездий вместе не накладываются друг на друга и на занятое — Сатурн в противостоянии, Томск, 21:00")
    func noOverlapOnTheRealSky() throws {
        let m = model("2026-10-20T14:00:00Z")
        m.setPlanets(true); m.setStars(true); m.setConstellations(true); m.setMoon(true)
        let saturn = PlanetSkyAR.samples(day: m.day, minutes: m.minutes, in: tomsk).first { $0.planet == .saturn }!
        #expect(saturn.horizontal.altitude > 5, "Сатурн над горизонтом: \(saturn.horizontal)")
        let aim = CameraBasis(azimuth: saturn.horizontal.azimuth, altitude: saturn.horizontal.altitude + 4)
        let st = stack(m, aim: aim)
        let planets = try #require(st.planets)
        #expect(planets.dots.map(\.planet).contains(.saturn))
        let planetLabels = st.planetLabels(planets)
        #expect(planetLabels.contains { $0.planet == .saturn }, "подпись Сатурна не поставлена")
        let stars = try #require(m.starScene(basis: aim, optics: .typical, viewport: viewport))
        let starLabels = st.starLabels(stars, extraTaken: SunARPlanetLabels.occupied(scene: planets, labels: planetLabels))
        let taken = st.starTaken
        for p in planetLabels {
            for t in taken { #expect(!p.rect.intersects(t), "планета \(p.planet) на занятом") }
            for s in starLabels { #expect(!p.rect.intersects(s.rect), "планета \(p.planet) на подписи \(s.id)") }
        }
        for s in starLabels {
            for d in planets.dots {
                let r = CGRect(x: d.point.x - d.radius, y: d.point.y - d.radius, width: 2 * d.radius, height: 2 * d.radius)
                #expect(!s.rect.intersects(r), "подпись \(s.id) на точке \(d.planet)")
            }
        }
    }

    @Test("подпись планеты в стеке обходит стрелки и диски меток: то, что занято у звёзд, занято и у планет")
    func planetLabelsAvoidThePointersAndDiscs() throws {
        let m = model("2026-11-04T20:00:00Z"); m.setPlanets(true)
        let dot = PlanetSkyARScene.Dot(planet: .jupiter, point: ScreenPoint(x: 200, y: 400), magnitude: -2, radius: 3.6,
                                       brightness: 1, azimuth: 92, altitude: 18)
        let scene = PlanetSkyARScene(dots: [dot], nearSun: [])
        let free = stack(m, aim: CameraBasis(azimuth: 93, altitude: 20), planets: scene)
        let first = try #require(free.planetLabels(scene).first)
        // Стрелка ровно там, где подпись встала сама: теперь она должна уйти.
        let pointer = first.rect.insetBy(dx: -3, dy: -3)
        let blocked = stack(m, aim: CameraBasis(azimuth: 93, altitude: 20), planets: scene, pointerRects: [pointer])
        for p in blocked.planetLabels(scene) {
            #expect(!p.rect.insetBy(dx: -SunARStarLabels.gap, dy: -SunARStarLabels.gap).intersects(pointer), "подпись легла на стрелку")
        }
        #expect(blocked.planetLabels(scene).first?.center != first.center, "подпись осталась на стрелке")
    }

    @Test("проводка стека: подписи звёзд получают занятое планетами; копия слоя лежит и под линзой своего стекла")
    func stackWiring() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LightPlanUI/Screens/SunAR/SunARSkyStack.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("starLabels(stars, extraTaken: planets.map { SunARPlanetLabels.occupied(scene: $0, labels: planetPlaced) } ?? [])"),
                "подписи звёзд не обходят планеты")
        #expect(text.contains("SunARPlanetCanvas(scene: planets, origin: o)"), "под линзой нет копии слоя планет")
        #expect(text.contains("return SunARPlanetLabels.place(cands, taken: starTaken, window: window)"), "планеты не обходят занятое")
    }

    @Test("слой стоит над звёздами и под дугой")
    func layerOrder() {
        let order = SunARLayers.order
        let st = order.firstIndex(of: .stars)!, pl = order.firstIndex(of: .planets)!, arc = order.firstIndex(of: .arc)!
        #expect(st < pl && pl < arc)
    }

    @Test("цена кадра слоя: сцена планет + раскладка подписей — доли миллисекунды, печатается")
    func frameCost() {
        let m = model("2026-10-20T14:00:00Z")
        m.setPlanets(true)
        var total = 0.0
        let runs = 200
        for i in 0..<runs {
            let aim = CameraBasis(azimuth: Double(i) * 1.7, altitude: 20 + Double(i % 40))
            let t0 = CFAbsoluteTimeGetCurrent()
            let scene = m.planetScene(basis: aim, optics: .typical, viewport: viewport)!
            let cands = SunARPlanetLabels.candidates(scene: scene, window: busy, name: { $0 })
            _ = SunARPlanetLabels.place(cands, taken: [], window: busy)
            total += (CFAbsoluteTimeGetCurrent() - t0) * 1000
        }
        print(String(format: "planet frame cost: mean %.3f ms over %d frames", total / Double(runs), runs))
        #expect(total / Double(runs) < 2)
    }
}
