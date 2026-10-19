import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData

/// Одна кнопка «Слои» и настоящее стекло кнопок AR (шаг 29.8в.9б; слова Алексея 18.10: «одна кнопка слоёв»,
/// «кнопки сейчас на чёрных подложках, надо переделать на стеклянные»).
@MainActor
struct SunARLayersButtonTests {

    private let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    private final class MemoryFlag: ARCalibrationFlag { var seen = true }
    private func moment(_ iso: String) -> Moment { Moment(ISO8601DateFormatter().date(from: iso)!) }
    private func model(_ defaults: UserDefaults) -> SunARModel {
        SunARModel(target: SunARTarget(place: tomsk, moment: moment("2026-10-20T14:00:00Z")), source: nil, camera: nil,
                   calibrationFlag: MemoryFlag(), bodies: DeviceBodiesSettings(defaults: defaults))
    }
    private var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/LightPlanUI/Screens/SunAR")
    }
    /// Код файла без комментариев.
    private func code(_ name: String) throws -> String {
        try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    @Test("переключатель слоя пишет те же флаги устройства, что и раньше; по умолчанию всё выключено; помнится между входами")
    func layerSwitchesKeepTheOldFlags() {
        let defaults = UserDefaults(suiteName: "sunar-layers-\(UUID().uuidString)")!
        let first = model(defaults)
        #expect(first.layersOn.isEmpty)
        #expect(!defaults.bool(forKey: "lightplan.native.sunar.moon") && !defaults.bool(forKey: "lightplan.native.sunar.milkyWay"))
        first.set(.moon, on: true)
        #expect(defaults.bool(forKey: "lightplan.native.sunar.moon") && !defaults.bool(forKey: "lightplan.native.sunar.milkyWay"))
        first.set(.milkyWay, on: true)
        #expect(defaults.bool(forKey: "lightplan.native.sunar.milkyWay"))
        let again = model(defaults)
        #expect(again.layersOn == [.moon, .milkyWay] && again.moonOn && again.milkyWayOn)
        again.set(.moon, on: false)
        #expect(again.layersOn == [.milkyWay] && !again.isOn(.moon))
        #expect(!model(defaults).moonOn && model(defaults).milkyWayOn)
    }

    @Test("у каждого слоя в списке есть настоящий флаг и слово; строк для слоёв без флага нет")
    func everyRowIsARealLayer() {
        let defaults = UserDefaults(suiteName: "sunar-layers-\(UUID().uuidString)")!
        let m = model(defaults)
        let lexicon = Lexicon("ru")
        for layer in SunARSkyLayer.allCases {
            #expect(!m.isOn(layer))
            m.set(layer, on: true)
            #expect(m.isOn(layer), "слой \(layer) не включился")
            #expect(lexicon.t(layer.labelKey) != layer.labelKey, "нет слова слоя \(layer)")
        }
        #expect(SunARSkyLayer.allCases.map(\.rawValue) == ["moon", "milkyWay", "stars", "constellations"])
        #expect(lexicon.t("ar.layers") == "Слои")
    }

    @Test("экран AR: одна кнопка слоёв со списком, круглых включателей луны и Млечного Пути больше нет")
    func oneLayersButton() throws {
        let screen = try code("SunARScreen.swift")
        #expect(screen.components(separatedBy: ".popover(").count - 1 == 1, "список слоёв — один поповер")
        #expect(screen.contains("SunARLayersList("), "в поповере нет списка слоёв")
        for gone in ["bodyToggle", "ar.moonToggle", "ar.mwToggle"] {
            #expect(!screen.contains(gone), "остался прежний включатель: \(gone)")
        }
        // Касание 44 pt, не меньше, при любом числе включённых слоёв.
        let label = try code("SunARLayersButton.swift")
        #expect(label.contains(".frame(width: SunARInk.touch, height: SunARInk.touch)"))
    }

    @Test("стекло кнопок — настоящее: чёрного оттенка нет ни у вида кнопок, ни в разметке AR")
    func buttonsAreGlassNotBlackPlates() throws {
        let look = SunARButtonLook.standard
        #expect(look.tint <= 0.15, "оттенок кнопок \(look.tint) темнее 0,15 — это снова чёрная плашка")
        #expect(!look.clear)
        #expect(look.ink == .adaptive, "белые чернила тонут на светлом стекле над белым небом (1,02 : 1)")
        // Прежний вид 29.8в.4 разбирается, но в выпуск не идёт.
        #expect(SunARButtonLook.parse("black70")?.tint == 0.7)
        #expect(SunARButtonLook.parse("regular.p")?.ink == .adaptive)
        #expect(SunARButtonLook.parse("clear.t20.s") == SunARButtonLook(clear: true, tint: 0.2, shadow: true))
        #expect(SunARButtonLook.parse("мусор") == nil)
        for file in try FileManager.default.contentsOfDirectory(atPath: sources.path) where file.hasSuffix(".swift") {
            let text = try code(file)
            let blackTint = try NSRegularExpression(pattern: "tint\\(\\s*Color\\.black")
            let n = blackTint.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            // Единственное место, где чёрный оттенок собирается из числа вида, — сам вид кнопок.
            #expect(n == (file == "SunARButtonLook.swift" ? 1 : 0), "\(file): чёрный оттенок стекла")
        }
    }
}
