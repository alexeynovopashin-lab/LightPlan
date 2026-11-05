import Testing
import Foundation
@testable import LightPlanData

/// 30г.3: режим из трёх значений вместо галочки (`docs/30g2_modes_table.md` § 4).
struct AppModeTests {

    private func file(_ json: String) throws -> Snapshot {
        try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
    }

    // MARK: - Как встают старые данные

    @Test func newPersonStartsInSimple() {
        let s = AppSettings(snapshot: Snapshot())
        #expect(s.mode == .simple)
        #expect(!s.pro)
        #expect(AppSettings().mode == .simple)
    }

    @Test func oldFileKeepsWhatItWas() throws {
        #expect(AppSettings(snapshot: try file(#"{"pro":true}"#)).mode == .astro)
        #expect(AppSettings(snapshot: try file(#"{"pro":false}"#)).mode == .simple)
        #expect(AppSettings(snapshot: try file("{}")).mode == .simple)
    }

    // MARK: - Как читается

    /// Вся таблица правила: ключ файла, память, галочка — 4 × 4 × 2 случая.
    @Test func keyBeatsMemoryAndMemoryBeatsTheFlag() {
        for key in [nil, "simple", "pro", "astro", "turbo"] as [String?] {
            for memory in [nil, .simple, .pro, .astro] as [AppMode?] {
                for flag in [false, true] {
                    let want = key.flatMap(AppMode.init(rawValue:)) ?? memory ?? (flag ? AppMode.astro : .simple)
                    #expect(AppMode.read(file: key, webPro: flag, remembered: memory) == want,
                            "ключ \(key ?? "нет"), память \(memory?.rawValue ?? "нет"), галочка \(flag)")
                }
            }
        }
        #expect(AppMode.read(file: "pro", webPro: false, remembered: .astro) == .pro)
        #expect(AppMode.read(file: nil, webPro: true, remembered: .pro) == .pro)
        #expect(AppMode.read(file: nil, webPro: false, remembered: .astro) == .astro)
        #expect(AppMode.read(file: nil, webPro: true, remembered: nil) == .astro)
        #expect(AppMode.read(file: nil, webPro: false, remembered: nil) == .simple)
    }

    @Test func oddKeyInFileBreaksNothing() throws {
        #expect(AppSettings(snapshot: try file(#"{"pro":true,"appMode":7}"#)).mode == .astro)
        #expect(AppSettings(snapshot: try file(#"{"pro":false,"appMode":"turbo"}"#)).mode == .simple)
        #expect(AppSettings(snapshot: try file(#"{"pro":true,"appMode":7}"#), remembered: .pro).mode == .pro)
    }

    // MARK: - Как пишется

    /// Просто → Про → Астро → Просто через настоящий файл: галочка для веба и ключ идут вровень.
    @Test func everyStepOfTheCycleSurvivesTheFile() throws {
        var snap = Snapshot()
        for (mode, flag) in [(AppMode.simple, false), (.pro, true), (.astro, true), (.simple, false)] {
            var s = AppSettings(snapshot: snap)
            s.mode = mode
            s.apply(to: &snap)
            let raw = try JSONEncoder().encode(snap)
            let top = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
            #expect(top["pro"] as? Bool == flag, "\(mode)")
            #expect(top["appMode"] as? String == mode.rawValue, "\(mode)")
            snap = try JSONDecoder().decode(Snapshot.self, from: raw)
            let back = AppSettings(snapshot: snap)
            #expect(back.mode == mode)
            #expect(back.pro == flag)
        }
    }

    /// Файл без ключа остаётся без ключа, пока режим никто не записал: чистый снимок веба не меняется от чтения.
    @Test func snapshotWithoutKeyEncodesWithoutKey() throws {
        let raw = try JSONEncoder().encode(try file(#"{"pro":true}"#))
        let top = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect(top["appMode"] == nil)
        #expect(top["pro"] as? Bool == true)
    }

    /// Ключ и галочка спорят (руками правленный файл): стоит ключ, запись их выравнивает.
    @Test func writingLinesTheFlagUpWithTheKey() throws {
        var snap = try file(#"{"pro":false,"appMode":"astro"}"#)
        let s = AppSettings(snapshot: snap)
        #expect(s.mode == .astro)
        #expect(s.pro)
        s.apply(to: &snap)
        #expect(snap.pro)
    }

    // MARK: - Память телефона

    @Test func deviceMemoryKeepsAChoiceAndIgnoresJunk() throws {
        let suite = "lp-mode-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = DeviceAppModeMemory(defaults: defaults)
        #expect(memory.mode == nil)
        for mode in AppMode.allCases {
            memory.mode = mode
            #expect(DeviceAppModeMemory(defaults: defaults).mode == mode)
        }
        defaults.set("turbo", forKey: DeviceAppModeMemory.key)
        #expect(memory.mode == nil)
        memory.mode = nil
        #expect(defaults.object(forKey: DeviceAppModeMemory.key) == nil)
    }
}
