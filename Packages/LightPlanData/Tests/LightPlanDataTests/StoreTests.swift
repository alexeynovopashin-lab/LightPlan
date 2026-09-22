import Testing
import Foundation
@testable import LightPlanData
import LightPlanDomain
import LightPlanCore

/// Итерация 12: хранилище и импорт живых данных. Проверки из плана —
/// круговой прогон, миграции (тех, что остались — `docs/17` § 6), обрезанные
/// и повреждённые файлы, файл на 1 000 съёмок.
struct StoreTests {
    private func tempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("light-plan-store-tests-\(UUID().uuidString)", isDirectory: true)
        return dir
    }

    private func sampleSession(id: String = "s1") -> Session {
        var s = Session(id: id, kind: .shoot, day: CivilDate(year: 2026, month: 9, day: 21), start: 600,
                        end: 720, duration: 120, genre: .wedding)
        s.subGenre = .engagement
        s.contact = "Аня"
        s.clientPhone = "+7 900 000-00-00"
        s.persons = [Person(name: "Аня", phone: "1"), Person(name: "Пётр", phone: "2")]
        s.place = "Томсон"
        s.placeTown = "Томск"
        s.latitude = 56.47
        s.longitude = 84.97
        s.wishes = [.sunset, .stars]
        s.wishWarning = WishWarning(title: "Ждали заката", message: "прогноз обещает другое")
        s.deadline = .days(14)
        s.delivered = true
        s.deliveredAt = Date(timeIntervalSince1970: 1_758_000_000)
        s.pay = .hourly
        s.rate = Decimal(string: "1234.56")
        s.units = 2
        s.expense = Decimal(string: "300.5")!
        s.prepay = 5000
        s.currency = .rub
        s.guests = 8
        s.docs = [Attachment(source: .link, path: nil, name: "Договор", size: nil, url: "https://disk", kind: .contract)]
        s.route = [RoutePoint(start: 600, end: 660, name: "Сборы", placeText: "дома")]
        s.telLog = [TelLogEntry(field: "clientTel", phone: "+7 911", name: "старый", retiredAt: "2026-01-01T00:00:00.000Z")]
        s.modifiedAt = 1_758_000_000_000
        return s
    }

    // MARK: - Круговой прогон

    @Test func roundTripPreservesSession() async throws {
        let dir = tempDirectory()
        let store = Store(directory: dir)
        var snapshot = Snapshot()
        snapshot.sessions = [sampleSession()]
        snapshot.currency = .rub
        snapshot.genres = [.wedding, .portrait]
        snapshot.genrePrefs = [.wedding: GenrePrefs(pay: .hourly, duration: .some(nil), rate: 1500)]
        snapshot.delivery = DeliverySetting(mode: .single, days: 10)
        snapshot.cardOrder = [.event: [.deal, .day, .money]]
        snapshot.extra = ["shots": .array([.string("sd_1")])]

        try await store.saveNow(snapshot)
        let loaded = try await store.load()
        #expect(loaded == snapshot)
    }

    @Test func roundTripEmptySnapshotOnFirstLaunch() async throws {
        let store = Store(directory: tempDirectory())
        let loaded = try await store.load()
        #expect(loaded == Snapshot())
    }

    @Test func largeFixtureOfAThousandSessions() async throws {
        let store = Store(directory: tempDirectory())
        var snapshot = Snapshot()
        snapshot.sessions = (0..<1000).map { i in
            var s = sampleSession(id: "s\(i)")
            s.day = CivilDate(year: 2026, month: 9, day: 1).adding(days: i % 90)
            return s
        }
        try await store.saveNow(snapshot)
        let loaded = try await store.load()
        #expect(loaded.sessions.count == 1000)
        #expect(loaded.sessions[999].id == "s999")
    }

    // MARK: - Деньги без потерь (`docs/17` § 6, «сверить»)

    /// Первая редакция этого теста ловила настоящую порчу: `Store.load`
    /// разбирал файл через `JSONValue` (там число — `Double`) и терял хвост
    /// точного `Decimal`. Причина была в этом перегоне, не в `Codable`
    /// `Decimal` — прямой круг `JSONEncoder`/`JSONDecoder` точен и на
    /// куда менее ровном числе, чем деньги (ниже). Правка —
    /// `ImportedFile.decode` больше не заворачивает в `JSONValue`, когда
    /// знает форму снимка. Проверяем то, что реально лежит в записи.
    @Test func decimalRoundTripsWithoutPrecisionLoss() async throws {
        let store = Store(directory: tempDirectory())
        var snapshot = Snapshot()
        var s = sampleSession()
        s.rate = Decimal(string: "1234.56")
        s.expense = Decimal(string: "300.07")!
        s.prepay = Decimal(string: "5000.99")!
        s.units = Decimal(string: "2.5")!
        snapshot.sessions = [s]
        snapshot.defaultRate = Decimal(string: "999.01")!
        try await store.saveNow(snapshot)
        let loaded = try await store.load()
        #expect(loaded.sessions[0].rate == s.rate)
        #expect(loaded.sessions[0].expense == s.expense)
        #expect(loaded.sessions[0].prepay == s.prepay)
        #expect(loaded.sessions[0].units == s.units)
        #expect(loaded.defaultRate == snapshot.defaultRate)
    }

    /// Даже деление, которое `Decimal` считает точно до знака, которого у
    /// денег не бывает, переживает `Store` без потерь — регресс на случай,
    /// если разбор файла снова заведёт скрытый перегон через `Double`
    /// (`Money.swift`: такие числа не хранятся, здесь — только страховка).
    @Test func decimalPastMoneyPrecisionStillRoundTrips() async throws {
        let store = Store(directory: tempDirectory())
        var snapshot = Snapshot()
        var s = sampleSession()
        s.rate = Decimal(1234) * Decimal(50) / Decimal(60)
        snapshot.sessions = [s]
        try await store.saveNow(snapshot)
        let loaded = try await store.load()
        #expect(loaded.sessions[0].rate == s.rate)
    }

    // MARK: - Незнакомый код не роняет запись

    @Test func unknownGenreCodeBecomesNilNotThrow() async throws {
        let dir = tempDirectory()
        let store = Store(directory: dir)
        let json = """
        {"sessions":[{"id":"x","kind":"shoot","date":"2026-09-21","min":600,"type":"underwater_yoga"}]}
        """
        let fileURL = dir.appendingPathComponent("light-plan.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json.data(using: .utf8)!.write(to: fileURL)
        let loaded = try await store.load()
        #expect(loaded.sessions.count == 1)
        #expect(loaded.sessions[0].genre == nil)
    }

    // MARK: - Обрезанные и повреждённые файлы

    @Test func corruptedFileThrowsInsteadOfCrashing() async throws {
        let dir = tempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("не json вовсе { [ ".utf8).write(to: dir.appendingPathComponent("light-plan.json"))
        let store = Store(directory: dir)
        await #expect(throws: StoreError.self) { try await store.load() }
    }

    @Test func fileWithoutSessionsKeyIsNotAStoreFile() async throws {
        let dir = tempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{\"hello\":\"world\"}".utf8).write(to: dir.appendingPathComponent("light-plan.json"))
        let store = Store(directory: dir)
        await #expect(throws: StoreError.self) { try await store.load() }
    }

    @Test func truncatedFileThrows() async throws {
        let dir = tempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent("light-plan.json"))
        let store = Store(directory: dir)
        await #expect(throws: StoreError.self) { try await store.load() }
    }

    // MARK: - Импорт архива

    @Test func importReadsSourceButNeverWritesIt() async throws {
        let dir = tempDirectory()
        let store = Store(directory: dir)

        var initial = Snapshot()
        initial.sessions = [sampleSession(id: "old")]
        try await store.saveNow(initial)

        let sourceURL = tempDirectory().appendingPathComponent("export.json")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var incoming = Snapshot()
        incoming.sessions = [sampleSession(id: "new")]
        let envelope = try JSONSerialization.data(withJSONObject: [
            "app": "Light Plan", "format": 1, "exported": "2026-09-21T00:00:00.000Z",
            "data": try JSONSerialization.jsonObject(with: JSONEncoder().encode(incoming)),
        ])
        try envelope.write(to: sourceURL)
        let sourceBefore = try Data(contentsOf: sourceURL)

        let imported = try await store.importArchive(from: sourceURL)
        #expect(imported.sessions.map(\.id) == ["new"])

        let sourceAfter = try Data(contentsOf: sourceURL)
        #expect(sourceBefore == sourceAfter)

        let reloaded = try await store.load()
        #expect(reloaded.sessions.map(\.id) == ["new"])
    }

    @Test func importMakesABackupOfTheOldStoreFirst() async throws {
        let dir = tempDirectory()
        let store = Store(directory: dir)
        var initial = Snapshot()
        initial.sessions = [sampleSession(id: "old")]
        try await store.saveNow(initial)

        let sourceURL = tempDirectory().appendingPathComponent("export.json")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var incoming = Snapshot()
        incoming.sessions = [sampleSession(id: "new")]
        try JSONEncoder().encode(incoming).write(to: sourceURL)

        _ = try await store.importArchive(from: sourceURL)

        let backups = try FileManager.default.contentsOfDirectory(at: dir.appendingPathComponent("backups"), includingPropertiesForKeys: nil)
        #expect(!backups.isEmpty)
        let backedUp = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: backups[0]))
        #expect(backedUp.sessions.map(\.id) == ["old"])
    }

    @Test func exportArchiveWrapsInBackupEnvelope() async throws {
        let store = Store(directory: tempDirectory())
        var snapshot = Snapshot()
        snapshot.sessions = [sampleSession()]
        try await store.saveNow(snapshot)

        let data = try await store.exportArchive()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["app"] as? String == "Light Plan")
        #expect(object?["format"] as? Int == 1)
        #expect(object?["data"] != nil)
    }

    // MARK: - Голый дамп веба (без конверта)

    @Test func bareDataDumpIsAcceptedLikeWeb() async throws {
        let store = Store(directory: tempDirectory())
        let json = """
        {"sessions":[{"id":"a","kind":"shoot","date":"2026-09-21","min":540}]}
        """
        let dir = tempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sourceURL = dir.appendingPathComponent("bare.json")
        try json.data(using: .utf8)!.write(to: sourceURL)
        let imported = try await store.importArchive(from: sourceURL)
        #expect(imported.sessions.map(\.id) == ["a"])
    }
}
