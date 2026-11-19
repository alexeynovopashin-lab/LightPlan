import Testing
import Foundation
@testable import LightPlanUI
import LightPlanData
import LightPlanCore
import LightPlanDomain

/// 31.11: запуск над повреждённым файлом данных. До шага `live()` читал его как пустой снимок, а запись пустых
/// жанровых папок мудборда тут же клала этот снимок поверх файла — без копии. Здесь тот же путь старта
/// (`startSnapshot` + `settleStart`) и слова окна, которое человек видит вместо молча пустого приложения.
@MainActor
struct DataDamageTests {
    private let fm = FileManager.default

    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    private func newDir() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("lp-31-11-ui-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func file(_ dir: URL) -> URL { dir.appendingPathComponent("light-plan.json") }

    private func copies(_ dir: URL) -> [URL] {
        ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasPrefix("light-plan.broken-") }.sorted().map { dir.appendingPathComponent($0) }
    }

    /// Старт, как в `live()`: снимок, что не так с файлом, записи старта.
    private func launch(_ dir: URL) async -> (Snapshot, StoreDamage?) {
        let store = Store(directory: dir)
        var snap = await AppModel.startSnapshot(store: store, fresh: false, bundleID: ClientContacts.mainBundleID)
        let damage = await store.damage
        await AppModel.settleStart(&snap, store: store, damage: damage)
        return (snap, damage)
    }

    private func goodBytes(_ ids: [String]) async throws -> Data {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        var s = Snapshot()
        s.sessions = ids.map {
            Session(id: $0, kind: .shoot, day: CivilDate(year: 2026, month: 11, day: 19), start: 600, end: 720,
                    duration: 120, genre: .wedding)
        }
        try await Store(directory: dir).saveNow(s)
        return try Data(contentsOf: file(dir))
    }

    private func app(_ snap: Snapshot = Snapshot()) -> AppModel {
        AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                 locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
    }

    // MARK: - Старт не пишет поверх

    @Test func launchOverATruncatedFileLeavesItAndKeepsACopy() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        let good = try await goodBytes(["a", "b"])
        let cut = good.prefix(good.count - 7)
        try cut.write(to: file(dir))

        let (snap, damage) = await launch(dir)
        #expect(snap.sessions.isEmpty)
        #expect(damage?.kind == .damaged)
        #expect(try Data(contentsOf: file(dir)) == cut, "старт не положил пустой снимок поверх")
        #expect(try copies(dir).map { try Data(contentsOf: $0) } == [cut])
    }

    @Test func launchOverAFileWithoutShootsKeyLeavesIt() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        let bytes = Data(#"{"orgs": [], "theme": "dark", "genres": ["wedding"]}"#.utf8)
        try bytes.write(to: file(dir))

        let (_, damage) = await launch(dir)
        #expect(damage?.kind == .damaged)
        #expect(try Data(contentsOf: file(dir)) == bytes)
        #expect(copies(dir).count == 1)
    }

    /// Проверка не пустая: тот же старт над исправным файлом без жанровых папок пишет файл (папки), то есть
    /// запись старта есть, и держит её именно порча.
    @Test func launchOverAGoodFileStillWritesItsStartRecords() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        let bytes = Data(#"{"sessions": []}"#.utf8)
        try bytes.write(to: file(dir))
        let (_, damage) = await launch(dir)
        #expect(damage == nil)
        #expect(try Data(contentsOf: file(dir)) != bytes)
        #expect(copies(dir).isEmpty)
    }

    @Test func launchWithOneBrokenShootKeepsTheOthersAndHealsTheFile() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        var top = try #require(try JSONSerialization.jsonObject(with: try await goodBytes(["a", "b", "c"])) as? [String: Any])
        var list = try #require(top["sessions"] as? [Any])
        list[2] = ["id": ["не строка"]]
        top["sessions"] = list
        let bytes = try JSONSerialization.data(withJSONObject: top)
        try bytes.write(to: file(dir))

        let (snap, damage) = await launch(dir)
        #expect(snap.sessions.map(\.id) == ["a", "b"])
        #expect(damage?.kind == .salvaged(dropped: 1))
        #expect(try copies(dir).map { try Data(contentsOf: $0) } == [bytes], "исходник целиком — в копии")

        // Прочитанное записано: следующий запуск открывает файл без окна и с теми же двумя съёмками.
        let (again, damageAgain) = await launch(dir)
        #expect(damageAgain == nil)
        #expect(again.sessions.map(\.id) == ["a", "b"])
        #expect(copies(dir).count == 1)
    }

    // MARK: - Окно

    @Test func noDamageNoWindow() {
        #expect(app().dataDamageWords == nil)
    }

    @Test func windowWordsFollowWhatHappened() {
        let a = app()
        let t = a.lexicon
        let copy = URL(fileURLWithPath: "/tmp/light-plan.broken-2026-11-19-120000.json")

        a.dataDamage = StoreDamage(kind: .damaged, copy: copy)
        #expect(a.dataDamageWords?.title == t.t("data.brokenT"))
        #expect(a.dataDamageWords?.message == t.t("data.brokenM"))

        a.dataDamage = StoreDamage(kind: .salvaged(dropped: 3), copy: copy)
        #expect(a.dataDamageWords?.title == t.t("data.partT"))
        #expect(a.dataDamageWords?.message == t.t("data.partM", ["n": "3"]))

        // Копии нет — главное, что поверх не пишется, и нужен перезапуск.
        a.dataDamage = StoreDamage(kind: .unreadable, copy: nil)
        #expect(a.dataDamageWords?.title == t.t("data.unreadT"))
        a.dataDamage = StoreDamage(kind: .damaged, copy: nil)
        #expect(a.dataDamageWords?.title == t.t("data.unreadT"))

        a.dismissDataDamage()
        #expect(a.dataDamage == nil)
        #expect(a.dataDamageWords == nil)
    }

    /// «Восстановить из облака» — только когда Диск подключён и его глава видна (Про, Астро); в «Просто» её нет.
    @Test func cloudHintOnlyWhereTheRestoreButtonIs() {
        var pro = Snapshot()
        pro.appMode = "pro"
        let a = app(pro)
        let t = a.lexicon
        a.dataDamage = StoreDamage(kind: .damaged, copy: URL(fileURLWithPath: "/tmp/x.json"))
        #expect(a.dataDamageWords?.message == t.t("data.brokenM"), "облако не подключено")
        a.cloud.record = CloudRecord(kind: .yandex)
        #expect(a.dataDamageWords?.message == t.t("data.brokenM") + " " + t.t("data.brokenCloud"))

        var simple = Snapshot()
        simple.appMode = "simple"
        let b = app(simple)
        b.cloud.record = CloudRecord(kind: .yandex)
        b.dataDamage = StoreDamage(kind: .damaged, copy: URL(fileURLWithPath: "/tmp/x.json"))
        #expect(b.dataDamageWords?.message == t.t("data.brokenM"))
    }

    /// Слова окна есть на всех пяти языках, без сырых `{…}`; число записей подставлено.
    @Test(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
    func windowWordsInEveryLanguage() {
        let keys = ["data.brokenT", "data.brokenM", "data.partT", "data.unreadT", "data.unreadM", "data.brokenCloud",
                    "data.brokenOk"]
        for lang in ["ru", "en", "es", "ja", "zh"] {
            let t = Lexicon(lang)
            for key in keys {
                let s = t.t(key)
                #expect(s != key && !s.isEmpty, "\(lang) \(key)")
                #expect(!s.contains("{"), "\(lang) \(key): «\(s)»")
            }
            let part = t.t("data.partM", ["n": "4"])
            #expect(part.contains("4") && !part.contains("{"), "\(lang): «\(part)»")
        }
        #expect(Lexicon("ru").t("data.brokenT") == "Файл данных повреждён")
    }
}
