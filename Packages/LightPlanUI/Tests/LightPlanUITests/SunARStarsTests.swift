import Testing
import SwiftUI
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData

/// Слои «Звёзды» и «Созвездия» на экране AR (шаг 29.8в.13): строки в списке «Слоёв» и флаги, слова на пяти языках,
/// момент, подписи не лежат на чужом. Слои рисуются всегда (29.8в.18, `SunARSkyAlwaysTests`).
@MainActor
struct SunARStarsTests {

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
    private func lit(_ m: SunARModel) { m.setStars(true); m.setConstellations(true) }

    // MARK: Список «Слоёв» и флаги

    @Test("«Звёзды» и «Созвездия» — отдельные строки списка со своими флагами устройства; по умолчанию выключены; помнятся")
    func rowsAndFlags() {
        #expect(SunARSkyLayer.allCases.map(\.rawValue) == ["moon", "milkyWay", "stars", "constellations", "planets"])
        let defaults = UserDefaults(suiteName: "sunar-stars-\(UUID().uuidString)")!
        let first = model("2026-10-20T14:00:00Z", bodies: DeviceBodiesSettings(defaults: defaults))
        #expect(first.layersOn.isEmpty && !first.starsOn && !first.constellationsOn)
        #expect(first.starScene(basis: CameraBasis(azimuth: 30, altitude: 40), optics: .typical, viewport: viewport) == nil)
        first.set(.stars, on: true)
        #expect(defaults.bool(forKey: "lightplan.native.sunar.stars") && !defaults.bool(forKey: "lightplan.native.sunar.constellations"))
        first.set(.constellations, on: true)
        #expect(defaults.bool(forKey: "lightplan.native.sunar.constellations"))
        let again = model("2026-10-20T14:00:00Z", bodies: DeviceBodiesSettings(defaults: defaults))
        #expect(again.layersOn == [.stars, .constellations])
        again.set(.stars, on: false)
        #expect(again.layersOn == [.constellations] && !model("2026-10-20T14:00:00Z", bodies: DeviceBodiesSettings(defaults: defaults)).starsOn)
        // У слоёв свои значки и точки на кнопке: тона различаются, строки — свои узлы.
        let tints = SunARSkyLayer.allCases.map { "\($0.tint)" }
        #expect(Set(tints).count == tints.count)
        #expect(Set(SunARSkyLayer.allCases.map(\.node)).count == 5)
    }

    @Test("слова слоёв, 24 созвездий и 22 звёзд есть на всех пяти языках")
    func wordsInFiveLanguages() {
        var keys = ["layer.stars", "layer.constellations"]
        keys += ConstellationCatalog.all.map { "con." + $0.code }
        keys += StarName.brightest.map(\.key)
        #expect(keys.count == 2 + 24 + 22)
        for code in ["ru", "en", "es", "ja", "zh"] {
            let lexicon = Lexicon(code)
            for k in keys { #expect(lexicon.t(k) != k && !lexicon.t(k).isEmpty, "\(code): нет слова \(k)") }
        }
        #expect(Lexicon("ru").t("con.UMa") == "Большая Медведица" && Lexicon("en").t("star.sirius") == "Sirius")
    }

    // MARK: Момент и солнце

    @Test("положение — на выбранный момент и место приложения; «Сейчас» возвращает на текущий момент")
    func pickedMomentAndNow() {
        // Выбран вечер 21:00 (14:00 UTC), «сейчас» — на три часа позже.
        let m = model("2026-10-20T14:00:00Z", now: "2026-10-20T17:00:00Z")
        lit(m)
        let basis = CameraBasis(azimuth: 30, altitude: 40)
        let picked = m.starScene(basis: basis, optics: .typical, viewport: viewport)!
        // Те же точки, что у ядра на ту же минуту и место: свой расчёт слой не заводит.
        let direct = StarSkyAR.horizontals(day: m.day, minutes: m.minutes, in: tomsk)
        let expected = StarSkyAR.make(positions: direct, basis: basis, optics: .typical,
                                      viewport: viewport, stars: true, constellations: true)
        #expect(picked == expected)
        m.jumpToNow()
        let now = m.starScene(basis: basis, optics: .typical, viewport: viewport)!
        #expect(now != picked, "после «Сейчас» небо не сдвинулось")
        let wall = SunTrack.wallClock(of: moment("2026-10-20T17:00:00Z"), in: tomsk)
        let atNow = StarSkyAR.make(positions: StarSkyAR.horizontals(day: wall.day, minutes: wall.minutes, in: tomsk),
                                   basis: basis, optics: .typical, viewport: viewport,
                                   stars: true, constellations: true)
        #expect(now == atNow)
        // Звёзды не стоят на месте: за три часа небо повернулось на 45°.
        #expect(picked.dots.first!.point != now.dots.first { $0.index == picked.dots.first!.index }?.point)
    }

    // MARK: Подписи

    /// Стек так, как его собирает экран: метки солнца и луны, подписи, плашка выбранного момента.
    private func stack(_ m: SunARModel, aim: CameraBasis, pointerRects: [CGRect] = []) -> (SunARSkyStack, [SunARMark], SunARScene) {
        let scene = SunARScene.make(basis: aim, optics: .typical, viewport: viewport, arc: m.arc, sun: m.sun, now: m.sunNow,
                                    pickedIsNow: m.pickedIsNow, solar: m.solar)
        let night = m.nightScene(basis: aim, optics: .typical, viewport: viewport)
        let marks = SunARMarks.make(sun: scene, night: night, screen: size)
        let clock = ClockText(language: "ru")
        let picked = SunARLabelLayout.pickedText(scene: scene, pickedIsNow: m.pickedIsNow, pickedMinutes: m.minutes, clock: clock,
                                                 dayCaption: nil, eventText: { _ in "закат" })
        let stack = SunARSkyStack(scene: scene, night: night, marks: marks, size: size, clock: clock,
                                  cardinals: ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"], coreLabel: "Ядро",
                                  eventText: { _ in "закат" }, pickedText: picked, sky: nil,
                                  pointerRects: pointerRects)
        return (stack, marks, scene)
    }

    @Test("занятое для подписей слоя: диски солнца и луны, плашка выбранного момента, часы и стороны света, стрелки")
    func takenCoversSunMoonAndPointers() {
        let m = model("2026-10-14T05:00:00Z", now: "2026-10-14T04:00:00Z")
        m.setMoon(true); lit(m)
        let aim = CameraBasis(azimuth: 162, altitude: 24)
        let pointer = CGRect(x: 20, y: 600, width: 44, height: 44)
        let (stack, marks, scene) = stack(m, aim: aim, pointerRects: [pointer])
        let taken = stack.starTaken
        #expect(!marks.isEmpty)
        for mk in marks {
            let disc = CGRect(x: mk.center.x - mk.radius, y: mk.center.y - mk.radius, width: mk.diameter, height: mk.diameter)
            #expect(taken.contains { $0.contains(disc) }, "диск \(mk.id) не занят")
        }
        let plate = SunARLabelLayout.pickedPill(text: "12:00", scene: scene)
        #expect(plate != nil && taken.contains(plate!), "плашка выбранного момента не занята")
        #expect(taken.contains(pointer), "стрелка не занята")
        // Часы дуги стоят в кадре: их плашки тоже в занятом.
        let hours = SunARLabelLayout.make(scene: scene, cardinals: ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"], eventText: { _ in "закат" },
                                          clock: ClockText(language: "ru"), bounds: CGRect(origin: .zero, size: size).insetBy(dx: -40, dy: -40),
                                          merged: nil, pickedText: "12:00")
        #expect(!hours.isEmpty && hours.allSatisfy { h in taken.contains(h.pill) })
    }

    @Test("подпись звезды или созвездия, которой сесть бы на диск, подпись или стрелку, уходит на другое место или не рисуется — наложений нет")
    func labelsNeverLandOnTheTaken() {
        let window = CGRect(x: 0, y: 220, width: 393, height: 480)
        let taken = [CGRect(x: 150, y: 380, width: 60, height: 60),      // диск метки
                     CGRect(x: 160, y: 300, width: 80, height: 20),      // плашка подписи
                     CGRect(x: 280, y: 500, width: 44, height: 44)]      // стрелка
        let cands = [
            SunARStarLabels.Candidate(id: "con.Ori", kind: .figure, text: "Орион", anchor: CGPoint(x: 180, y: 410), radius: 0),
            SunARStarLabels.Candidate(id: "star.vega", kind: .star, text: "Вега", anchor: CGPoint(x: 190, y: 310), radius: 2),
            SunARStarLabels.Candidate(id: "star.sirius", kind: .star, text: "Сириус", anchor: CGPoint(x: 300, y: 520), radius: 3),
            SunARStarLabels.Candidate(id: "con.Lyr", kind: .figure, text: "Лира", anchor: CGPoint(x: 200, y: 600), radius: 0),
            SunARStarLabels.Candidate(id: "star.altair", kind: .star, text: "Альтаир", anchor: CGPoint(x: 80, y: 450), radius: 2),
        ]
        let placed = SunARStarLabels.place(cands, taken: taken, window: window)
        // Свободные встали, окружённые занятым — нет: ни на диске, ни на стрелке они не лежат.
        #expect(Set(placed.map(\.id)) == ["con.Lyr", "star.altair"], "поставлены: \(placed.map(\.id))")
        for p in placed {
            #expect(window.contains(p.rect), "\(p.id) вне окна")
            for t in taken { #expect(!p.rect.insetBy(dx: -SunARStarLabels.gap, dy: -SunARStarLabels.gap).intersects(t), "\(p.id) лежит на занятом \(t)") }
        }
        for (i, a) in placed.enumerated() { for b in placed[(i + 1)...] { #expect(!a.rect.intersects(b.rect), "\(a.id) на \(b.id)") } }
        // Подпись, вокруг которой всё занято, не рисуется, а не ложится сверху.
        let boxed = SunARStarLabels.place([cands[0]], taken: [window], window: window)
        #expect(boxed.isEmpty)
        // Подпись, которой не хватает окна (центр у самого края — текст вылез бы за него), не рисуется, а не уезжает за экран.
        let edge = SunARStarLabels.Candidate(id: "con.UMa", kind: .figure, text: "Большая Медведица",
                                             anchor: CGPoint(x: window.minX + 3, y: window.midY), radius: 0)
        #expect(SunARStarLabels.place([edge], taken: [], window: window).isEmpty)
    }

    @Test("плашка выбранного момента у края кадра занята там, где её рисует вид (сдвинута внутрь на 8 pt), и подпись звезды на неё не садится")
    func pickedPlateNearEdgeIsTakenWhereDrawn() throws {
        let m = model("2026-10-14T05:00:00Z", now: "2026-10-14T04:00:00Z")
        m.setMoon(true); lit(m)
        // Камера, при которой метка выбранного момента стоит в 10…16 pt от левого края.
        var found: (aim: CameraBasis, scene: SunARScene)?
        for tenth in 0..<7200 {
            let aim = CameraBasis(azimuth: Double(tenth) / 20, altitude: 24)
            let sc = SunARScene.make(basis: aim, optics: .typical, viewport: viewport, arc: m.arc, sun: m.sun, now: m.sunNow,
                                     pickedIsNow: m.pickedIsNow, solar: m.solar)
            if let mk = sc.marker, mk.x >= 10, mk.x <= 16, mk.y > 250, mk.y < 600 { found = (aim, sc); break }
        }
        let f = try #require(found, "метка у левого края не найдена")
        let (st, _, scene) = stack(m, aim: f.aim)
        let text = try #require(st.pickedText, "подписи метки нет")
        let drawn = try #require(SunARLabelLayout.pickedPill(text: text, scene: scene, screenWidth: size.width))
        let unshifted = try #require(SunARLabelLayout.pickedPill(text: text, scene: scene))
        print(String(format: "ARLAY плашка метки у края: метка x %.1f, нарисована с x %.1f, без сдвига стояла бы с x %.1f", scene.marker!.x, drawn.minX, unshifted.minX))
        #expect(drawn.minX - unshifted.minX > 15, "контроль: без сдвига плашка стояла бы больше чем на 15 pt левее нарисованной — сцена не воспроизводит замечание")
        #expect(drawn.minX >= 7.5, "плашка вида не сдвинута внутрь: \(drawn)")
        let taken = st.starTaken
        #expect(taken.contains(drawn), "плашка, как её рисует вид, не занята: \(drawn)")
        // Подпись звезды, якорь которой стоит у правого края плашки, не ложится на неё.
        let window = CGRect(origin: .zero, size: size)
        let cand = SunARStarLabels.Candidate(id: "star.vega", kind: .star, text: "Вега",
                                             anchor: CGPoint(x: drawn.maxX - 4, y: drawn.midY), radius: 2)
        for p in SunARStarLabels.place([cand], taken: taken, window: window) {
            #expect(!p.rect.intersects(drawn), "подпись звезды \(p.rect) лежит на плашке \(drawn)")
        }
    }

    @Test("кандидаты подписей: созвездия — у центра фигуры, звёзды — только из пятнадцати названных; за окном и без имени — нет")
    func candidatesFromScene() {
        let m = model("2026-10-20T14:00:00Z"); lit(m)
        let scene = m.starScene(basis: CameraBasis(azimuth: 240, altitude: 52), optics: .typical, viewport: viewport)!
        let window = CGRect(origin: .zero, size: size)
        let cands = SunARStarLabels.candidates(scene: scene, window: window, name: { Lexicon("ru").t($0) })
        #expect(!cands.isEmpty)
        for c in cands {
            #expect(window.contains(c.anchor))
            #expect(c.kind == .figure ? c.id.hasPrefix("con.") : c.id.hasPrefix("star."), "\(c.id)")
            #expect(c.text != c.id, "нет слова \(c.id)")
        }
        let lyra = cands.first { $0.id == "con.Lyr" }, vega = cands.first { $0.id == "star.vega" }
        #expect(lyra != nil && vega != nil && lyra!.text == "Лира" && vega!.text == "Вега")
        // Центр фигуры — это точка фигуры из сцены, а не звезды.
        #expect(lyra!.anchor == scene.figures.first { $0.code == "Lyr" }.map { CGPoint(x: $0.point.x, y: $0.point.y) })
        let off = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(SunARStarLabels.candidates(scene: scene, window: off, name: { $0 }).allSatisfy { off.contains($0.anchor) })
    }

    @Test("цена кадра слоя на главной нитке: сцена звёзд + занятое + раскладка подписей — миллисекунды, печатается")
    func frameCost() {
        let m = model("2026-10-20T14:00:00Z", now: "2026-10-20T13:00:00Z")
        m.setMoon(true); lit(m)
        let window = CGRect(x: 0, y: 200, width: 393, height: 500)
        var total = 0.0, worst = 0.0
        let runs = 200
        for i in 0..<runs {
            // Камера ведёт по небу: каждый кадр — новый поворот, положения звёзд на момент кэшируются.
            let aim = CameraBasis(azimuth: Double(i) * 1.7, altitude: 20 + Double(i % 40))
            let t0 = CFAbsoluteTimeGetCurrent()
            let scene = m.starScene(basis: aim, optics: .typical, viewport: viewport)!
            let (st, _, _) = stack(m, aim: aim)
            let taken = st.starTaken
            let cands = SunARStarLabels.candidates(scene: scene, window: window, name: { $0 })
            _ = SunARStarLabels.place(cands, taken: taken, window: window)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            total += ms; worst = max(worst, ms)
        }
        print(String(format: "star frame cost: mean %.3f ms, worst %.3f ms over %d frames", total / Double(runs), worst, runs))
        // Кадр 60 Гц — 16,7 мс: слой не должен съедать больше трети.
        #expect(total / Double(runs) < 5)
    }

    @Test("слой стоит между полосой Млечного Пути и дугой; в списке слоёв отладки он есть")
    func layerOrder() {
        let order = SunARLayers.order
        let mw = order.firstIndex(of: .milkyWay)!, st = order.firstIndex(of: .stars)!, arc = order.firstIndex(of: .arc)!
        #expect(mw < st && st < arc)
    }
}
