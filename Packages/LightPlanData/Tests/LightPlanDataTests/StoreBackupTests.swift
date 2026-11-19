import Testing
import Foundation
@testable import LightPlanData
import LightPlanDomain
import LightPlanCore

/// 31.11 «Копия перед перезаписью данных». До шага повреждённый файл данных читался на старте как пустой снимок,
/// и первая же запись старта клала пустой поверх без копии. Здесь — что хранилище делает с таким файлом: копия
/// исходных байтов рядом до любой записи, не больше `Store.brokenKept` копий, щадящее чтение одной битой записи,
/// последний хороший вид файла (`light-plan.prev.json`) раз за запуск, отказ писать поверх нечитаемого файла.
///
/// Проверки без `damage` собираются и на коде до шага (`1843bd47`): там 10 из 13 красные, зелёные — «файла нет»,
/// «новые ключи», «исправный файл» (они стерегут, что хороший файл читается как раньше).
struct StoreBackupTests {
    private let fm = FileManager.default

    private func newDir() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("lp-31-11-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func file(_ dir: URL) -> URL { dir.appendingPathComponent("light-plan.json") }
    private func prev(_ dir: URL) -> URL { dir.appendingPathComponent("light-plan.prev.json") }

    private func brokenCopies(_ dir: URL) -> [URL] {
        ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasPrefix("light-plan.broken-") && $0.hasSuffix(".json") }
            .sorted().map { dir.appendingPathComponent($0) }
    }

    private func session(_ id: String) -> Session {
        Session(id: id, kind: .shoot, day: CivilDate(year: 2026, month: 11, day: 19), start: 600, end: 720,
                duration: 120, genre: .wedding)
    }

    private func snapshot(_ ids: [String]) -> Snapshot {
        var s = Snapshot()
        s.sessions = ids.map(session)
        s.orgs = [Org(id: "o1", name: "Студия")]
        return s
    }

    /// Хороший файл с тремя съёмками — байты, как их пишет `Store`.
    private func goodBytes(_ ids: [String] = ["a", "b", "c"]) async throws -> Data {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        try await Store(directory: dir).saveNow(snapshot(ids))
        return try Data(contentsOf: file(dir))
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Нет файла — не порча

    @Test func absentFileIsAnEmptyStartWithoutCopies() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        let store = Store(directory: dir)
        #expect(try await store.load() == Snapshot())
        #expect(await store.damage == nil)
        #expect(brokenCopies(dir).isEmpty)
        try await store.saveNow(snapshot(["a"]))
        #expect(!fm.fileExists(atPath: prev(dir).path), "прежнего файла не было — и прежнего вида нет")
    }

    // MARK: - Повреждённый файл: копия до любой записи

    @Test func truncatedFileIsCopiedAndLeftInPlace() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        let good = try await goodBytes()
        let cut = good.prefix(good.count / 2)
        try cut.write(to: file(dir))

        let store = Store(directory: dir)
        await #expect(throws: (any Error).self) { try await store.load() }

        let copies = brokenCopies(dir)
        #expect(copies.count == 1)
        #expect(try copies.first.map { try Data(contentsOf: $0) } == cut, "в копии — исходные байты, как были")
        #expect(try Data(contentsOf: file(dir)) == cut, "сам файл не тронут")
    }

    @Test func fileWithoutSessionsKeyIsCopiedAndLeftInPlace() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        var top = try json(try await goodBytes())
        top["sessions"] = nil
        let bytes = try JSONSerialization.data(withJSONObject: top)
        try bytes.write(to: file(dir))

        let store = Store(directory: dir)
        await #expect(throws: (any Error).self) { try await store.load() }
        #expect(try brokenCopies(dir).map { try Data(contentsOf: $0) } == [bytes])
        #expect(try Data(contentsOf: file(dir)) == bytes)
    }

    @Test func damageSaysWhatHappenedAndWhereTheCopyIs() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        try Data("{\"sessions\": [".utf8).write(to: file(dir))
        let store = Store(directory: dir)
        _ = try? await store.load()
        let damage = try #require(await store.damage)
        #expect(damage.kind == .damaged)
        #expect(damage.copy == brokenCopies(dir).first)
        #expect(!damage.writesHeld, "копия есть — новые правки писать можно")
    }

    /// Копия есть — правки человека пишутся в файл данных, а копия остаётся как была.
    @Test func laterSavesNeverTouchTheCopy() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        let broken = Data("{\"sessions\": [{\"id\": ".utf8)
        try broken.write(to: file(dir))
        let store = Store(directory: dir)
        _ = try? await store.load()
        try await store.saveNow(snapshot(["new"]))
        try await store.saveNow(snapshot(["new", "newer"]))
        #expect(try brokenCopies(dir).map { try Data(contentsOf: $0) } == [broken])
        #expect(try await Store(directory: dir).load().sessions.map(\.id) == ["new", "newer"])
        #expect(!fm.fileExists(atPath: prev(dir).path), "повреждённый файл — не «последний хороший»")
    }

    // MARK: - Новые ключи — не порча

    @Test func newerUnknownKeysAreNotDamage() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        var top = try json(try await goodBytes())
        top["futureSection"] = ["k": [1, 2, 3]]
        top["format"] = 7
        try JSONSerialization.data(withJSONObject: top).write(to: file(dir))

        let store = Store(directory: dir)
        let loaded = try await store.load()
        #expect(loaded.sessions.map(\.id) == ["a", "b", "c"])
        #expect(loaded.extra["futureSection"] != nil)
        #expect(loaded.extra["format"] == .number(7))
        #expect(await store.damage == nil)
        #expect(brokenCopies(dir).isEmpty)
    }

    // MARK: - Повторные запуски не множат копии

    @Test func repeatedLaunchesKeepOneCopyOfTheSameBytes() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        try Data("{ не json".utf8).write(to: file(dir))
        for _ in 0..<5 { _ = try? await Store(directory: dir).load() }
        #expect(brokenCopies(dir).count == 1)
    }

    @Test func differentBrokenFilesKeepOnlyTheNewestThree() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        var written: [Data] = []
        for i in 0..<5 {
            let bytes = Data("{ битый \(i)".utf8)
            written.append(bytes)
            try bytes.write(to: file(dir))
            _ = try? await Store(directory: dir).load()
        }
        let kept = try brokenCopies(dir).map { try Data(contentsOf: $0) }
        #expect(kept.count == 3)
        #expect(Set(kept) == Set(written.suffix(3)), "остаются три последних")
    }

    // MARK: - Одна битая запись — остальные на месте

    @Test func oneBrokenShootKeepsTheOthers() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        var top = try json(try await goodBytes())
        var list = try #require(top["sessions"] as? [Any])
        list[1] = ["id": 5, "kind": ["не", "то"]]
        top["sessions"] = list
        top["theme"] = 42
        let bytes = try JSONSerialization.data(withJSONObject: top)
        try bytes.write(to: file(dir))

        let store = Store(directory: dir)
        let loaded = try await store.load()
        #expect(loaded.sessions.map(\.id) == ["a", "c"])
        #expect(loaded.orgs.map(\.id) == ["o1"])
        #expect(loaded.theme == nil)
        #expect(try brokenCopies(dir).map { try Data(contentsOf: $0) } == [bytes], "исходник целиком — в копии")
    }

    @Test func salvageCountsWhatFellOut() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        var top = try json(try await goodBytes())
        var list = try #require(top["sessions"] as? [Any])
        list[1] = ["id": 5]
        top["sessions"] = list
        top["theme"] = 42
        try JSONSerialization.data(withJSONObject: top).write(to: file(dir))
        let store = Store(directory: dir)
        _ = try await store.load()
        #expect(await store.damage?.kind == .salvaged(dropped: 2), "одна съёмка и одно поле")
    }

    /// Раздел съёмок не массивом — это не «часть не прочиталась»: все съёмки пропали бы, снимок не годится.
    @Test func lostShootSectionIsDamageNotSalvage() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        var top = try json(try await goodBytes())
        top["sessions"] = "сломано"
        let bytes = try JSONSerialization.data(withJSONObject: top)
        try bytes.write(to: file(dir))
        let store = Store(directory: dir)
        await #expect(throws: (any Error).self) { try await store.load() }
        #expect(await store.damage?.kind == .damaged)
        #expect(try brokenCopies(dir).map { try Data(contentsOf: $0) } == [bytes])
    }

    /// Хороший файл не идёт щадящим путём: те же байты читаются, как раньше, и ничего не выпадает.
    @Test func goodFileReadsStrictlyAsBefore() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        try await goodBytes().write(to: file(dir))
        let store = Store(directory: dir)
        #expect(try await store.load() == snapshot(["a", "b", "c"]))
        #expect(await store.damage == nil)
    }

    // MARK: - Нечитаемый файл — не пишем поверх

    @Test func unreadableFileIsNeverOverwritten() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        let good = try await goodBytes()
        try good.write(to: file(dir))
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file(dir).path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file(dir).path) }

        let store = Store(directory: dir)
        await #expect(throws: (any Error).self) { try await store.load() }
        await #expect(throws: (any Error).self) { try await store.saveNow(Snapshot()) }
        await store.save(Snapshot())
        await store.flush()

        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file(dir).path)
        #expect(try Data(contentsOf: file(dir)) == good)
        #expect(await store.damage == StoreDamage(kind: .unreadable, copy: nil))
    }

    // MARK: - Последний хороший вид файла

    @Test func lastGoodCopyRotatesOncePerLaunch() async throws {
        let dir = try newDir(); defer { try? fm.removeItem(at: dir) }
        try await Store(directory: dir).saveNow(snapshot(["a"]))
        let a = try Data(contentsOf: file(dir))
        #expect(!fm.fileExists(atPath: prev(dir).path))

        let second = Store(directory: dir)
        _ = try await second.load()
        try await second.saveNow(snapshot(["b"]))
        try await second.saveNow(snapshot(["c"]))
        let c = try Data(contentsOf: file(dir))
        #expect(try Data(contentsOf: prev(dir)) == a, "вид, с которым запуск открылся, — а не прошлая запись")

        let third = Store(directory: dir)
        _ = try await third.load()
        try await third.saveNow(snapshot(["d"]))
        #expect(try Data(contentsOf: prev(dir)) == c)
        #expect(try await Store(directory: dir).load().sessions.map(\.id) == ["d"])
        #expect(brokenCopies(dir).isEmpty)
    }
}
