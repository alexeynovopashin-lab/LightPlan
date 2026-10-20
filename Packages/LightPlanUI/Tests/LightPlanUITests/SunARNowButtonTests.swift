import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData

/// Одна кнопка «Сейчас» на все слои экрана AR (шаг 29.8в.5, слово Алексея 15.10: «для солнца, луны, млечного пути,
/// звёзд кнопка сейчас должна быть одна… одна, которая сбивает все слои на ноль»).
@MainActor
struct SunARNowButtonTests {

    private let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    private final class MemoryBodies: ARBodiesSettings {
        var moon = false
        var milkyWay = false
        var stars = false
        var constellations = false
        var planets = false
    }
    private final class MemoryFlag: ARCalibrationFlag { var seen = true }
    private func moment(_ iso: String) -> Moment { Moment(ISO8601DateFormatter().date(from: iso)!) }

    @Test("в разметке экрана AR одна кнопка «Сейчас» — у таймбара; своих у солнца, луны и Млечного Пути нет")
    func exactlyOneNowControl() throws {
        // …/Tests/LightPlanUITests/<файл> → …/Sources/LightPlanUI/Screens/SunAR
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/LightPlanUI/Screens/SunAR")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 8, "не нашёл исходники AR в \(dir.path)")
        var handlers = 0, perLayer = 0
        for f in files {
            let code = try String(contentsOf: f, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
                .joined(separator: "\n")
            // Слово целиком: `moonNow:` — свойство модели, не обработчик кнопки.
            handlers += (try NSRegularExpression(pattern: "\\bonNow:")).numberOfMatches(
                in: code, range: NSRange(code.startIndex..., in: code))
            // Своя кнопка «сейчас» у слоя: ключи слов или вызов перехода к «сейчас» вне таймбара.
            for needle in ["ar.nowTag", "layer.now", ".jumpToNow()"] {
                perLayer += code.components(separatedBy: needle).count - 1
            }
        }
        #expect(handlers == 1, "обработчиков кнопки таймбара «Сейчас»: \(handlers)")
        #expect(perLayer == 0, "у слоёв нашлись свои «сейчас»: \(perLayer)")
    }

    @Test("«Сейчас» одним шагом сбрасывает выбранный момент всех слоёв: солнце, луна и Млечный Путь возвращаются к текущему моменту")
    func nowResetsEveryLayer() throws {
        let now = moment("2026-10-20T14:00:00Z")       // 21:00 в Томске
        let picked = moment("2026-10-20T10:00:00Z")    // 17:00
        let model = SunARModel(target: SunARTarget(place: tomsk, moment: picked), source: nil, camera: nil,
                               clock: { now }, calibrationFlag: MemoryFlag(), bodies: MemoryBodies())
        model.setMoon(true)
        model.setMilkyWay(true)
        let basis = CameraBasis(azimuth: 183, altitude: 18)
        let viewport = ScreenViewport(width: 393, height: 852)
        let before = model.nightScene(basis: basis, optics: .typical, viewport: viewport)
        #expect(!model.pickedIsNow)
        #expect(before.now != nil, "до «Сейчас» у луны две метки: выбранная и текущая")
        let pickedMoon = try #require(before.picked)

        model.jumpToNow()

        #expect(model.pickedIsNow)
        let n = model.nowTarget(now: now)
        #expect(model.day == n.day && abs(model.minutes - n.minutes) < 1)
        let after = model.nightScene(basis: basis, optics: .typical, viewport: viewport)
        #expect(after.now == nil, "после «Сейчас» метки слились")
        let current = try #require(after.picked)
        #expect(current.azimuth != pickedMoon.azimuth || current.altitude != pickedMoon.altitude)
        #expect(after.milkyWayOn)
        let core = MilkyWay.corePosition(date: n.day, minutes: n.minutes, place: tomsk, time: .iau)
        #expect(abs(after.coreAzimuth - core.azimuth) < 0.01 && abs(after.coreAltitude - core.altitude) < 0.01,
                "ядро Млечного Пути не вернулось к текущему моменту")
        let scene = SunARScene.make(basis: basis, optics: .typical, viewport: viewport, arc: model.arc, sun: model.sun,
                                    now: model.sunNow, pickedIsNow: model.pickedIsNow, solar: model.solar)
        #expect(scene.markerIsNow && scene.nowMarker == nil)
    }
}
