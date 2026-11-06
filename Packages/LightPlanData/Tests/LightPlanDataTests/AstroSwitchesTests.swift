import Testing
import Foundation
@testable import LightPlanData

/// 30г.4: пять переключателей «Астро» (`docs/30g2_modes_table.md` § 2, § 4) и как они переживают файл из веба.
struct AstroSwitchesTests {

    private func file(_ json: String) throws -> Snapshot {
        try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
    }

    /// Ни ключа, ни памяти: новый человек, первый вход в «Астро», старые данные «Астро» — все пять включены.
    @Test func nothingWrittenMeansAllFiveOn() throws {
        #expect(AstroSwitches.read(file: nil, remembered: nil) == .allOn)
        let old = AppSettings(snapshot: try file(#"{"pro":true}"#))
        #expect(old.mode == .astro)
        for sw in AstroSwitch.allCases { #expect(old.astro[sw], "\(sw)") }
        #expect(AppSettings().astro == .allOn)
    }

    /// Ключ файла сильнее памяти; файл без ключа (веб пересохранил) — решает память, а не «все включены».
    @Test func fileKeyThenMemoryThenAllOn() {
        let termsOff = AstroSwitches(off: [.terms])
        #expect(AstroSwitches.read(file: nil, remembered: termsOff) == termsOff)
        #expect(AstroSwitches.read(file: [], remembered: termsOff) == .allOn)
        #expect(AstroSwitches.read(file: ["moon", "turbo"], remembered: termsOff) == AstroSwitches(off: [.moon]))
    }

    /// Запись: ключ всегда, в порядке строк настроек; через JSON и обратно — то же, а файл из веба ключа не несёт.
    @Test func keyRoundTripsThroughTheFile() throws {
        var a = AppSettings(mode: .astro)
        a.astro[.terms] = false
        a.astro[.moon] = false
        var s = Snapshot()
        a.apply(to: &s)
        #expect(s.astroOff == ["moon", "terms"])
        let back = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(s))
        #expect(back.astroOff == ["moon", "terms"])
        #expect(AppSettings(snapshot: back).astro == a.astro)
        var on = Snapshot()
        AppSettings(mode: .astro).apply(to: &on)
        #expect(on.astroOff == [])
        #expect(try file(#"{"pro":true}"#).astroOff == nil)
    }

    /// Переключатель действует только в «Астро» и только включённый.
    @Test func seesOnlyInAstroAndOnlyWhenOn() {
        for mode in AppMode.allCases {
            var s = AppSettings(mode: mode)
            #expect(s.sees(.terms) == (mode == .astro), "\(mode)")
            s.astro[.terms] = false
            #expect(!s.sees(.terms), "\(mode)")
            #expect(s.sees(.moon) == (mode == .astro), "\(mode): прочие не задеты")
        }
    }

    @Test func deviceMemoryKeepsSwitches() throws {
        let suite = "lp-astro-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = DeviceAppModeMemory(defaults: defaults)
        #expect(memory.astro == nil)
        memory.astro = .allOn
        #expect(DeviceAppModeMemory(defaults: defaults).astro == .allOn)
        memory.astro = AstroSwitches(off: [.terms, .milkyWay])
        #expect(DeviceAppModeMemory(defaults: defaults).astro == AstroSwitches(off: [.terms, .milkyWay]))
        memory.astro = nil
        #expect(defaults.object(forKey: DeviceAppModeMemory.astroKey) == nil)
    }
}
