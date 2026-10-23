import Testing
import Foundation
import LightPlanCore
import LightPlanDomain
@testable import LightPlanData

/// Шаг К1 «Клиенты»: раздел `clients` в снимке и `clientId` в записи живут в том же файле и переживают чтение-запись.
struct ClientsSnapshotTests {

    static func sample() -> Snapshot {
        var s = Snapshot()
        var c = Client(id: "c1", kind: .couple)
        c.people = [ClientPerson(name: "Аня", phone: "+7 913 555-66-77"), ClientPerson(name: "Марк", phone: "+7 913 555-66-78")]
        c.modifiedAt = 42
        s.clients = [c]
        var rec = Session(id: "a", kind: .shoot, day: CivilDate(year: 2026, month: 9, day: 5), start: 600, end: 690, duration: 90, genre: .wedding)
        rec.clientId = "c1"
        s.sessions = [rec]
        s.clientsAssembled = true
        return s
    }

    @Test func clientsAndTheShootsClientIdSurviveARoundTrip() throws {
        let s = Self.sample()
        let back = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(s))
        #expect(back.clients == s.clients)
        #expect(back.sessions.first?.clientId == "c1")
        #expect(back.clientsAssembled)
    }

    @Test func aFileFromBeforeClientsOpensWithNoneAndWithoutThePassDone() throws {
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"sessions":[],"orgs":[]}"#.utf8))
        #expect(s.clients.isEmpty && !s.clientsAssembled, "нет раздела — проход ещё не сделан")
    }

    @Test func aSnapshotWithoutClientsWritesNoClientKeys() throws {
        let text = String(decoding: try JSONEncoder().encode(Snapshot()), as: UTF8.self)
        #expect(!text.contains("clients"), "пока клиентов нет, файл такой же, как до шага К1")
    }

    @Test func clientsAreKnownKeysNotLeftoversInExtra() throws {
        let data = try JSONEncoder().encode(Self.sample())
        let back = try JSONDecoder().decode(Snapshot.self, from: data)
        #expect(back.extra["clients"] == nil && back.extra["clientsAssembled"] == nil)
    }

    @Test func unknownKeysAndOrgsStillSurviveNextToClients() throws {
        var s = Self.sample()
        s.orgs = [Org(id: "o1", name: "Отдел культуры")]
        s.extra["notif"] = .string("kept")
        let back = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(s))
        #expect(back.orgs.map(\.name) == ["Отдел культуры"] && back.extra["notif"] == .string("kept") && back.clients.count == 1)
    }

    @Test func theStoreWritesAndReadsClientsFromTheSameFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-k1-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir)
        try await store.saveNow(Self.sample())
        let back = try await Store(directory: dir).load()
        #expect(back.clients.first?.people.map(\.name) == ["Аня", "Марк"])
        #expect(back.sessions.first?.clientId == "c1")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("light-plan.json").path), "тот же файл `light-plan.json`")
    }

    // MARK: карточка клиента (К2)

    /// Объединение в снимке: второй клиент исчез, его съёмка — живая и в корзине — у первого, ссылки и прежние номера
    /// записаны; файл после записи и чтения тот же.
    @Test func aMergedClientSurvivesTheStoreWithLinksArchiveAndTheBin() async throws {
        var s = Self.sample()
        var b = Client(id: "c2", kind: .person)
        b.people = [ClientPerson(name: "Марк П.", phone: "8 903 444-55-66")]
        b.links = [Attachment.link("vk.com/mark", kind: nil)!]
        b.telLog = [TelLogEntry(field: "p1", phone: "8 903 000-00-01", name: "Марк", retiredAt: "2026-10-01T00:00:00Z")]
        s.clients.append(b)
        var p = Session(id: "p", kind: .shoot, day: CivilDate(year: 2026, month: 3, day: 1), start: 600, end: 690, duration: 90, genre: .portrait)
        p.clientId = "c2"
        s.trashed = [TrashedItem(record: p, index: 1, deletedAt: 5)]
        var q = p; q.id = "q"
        s.sessions.append(q)
        #expect(ClientBook.merge("c2", into: "c1", clients: &s.clients, sessions: &s.sessions, trashed: &s.trashed,
                                 country: .fallback, nowMs: 77))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-k2-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await Store(directory: dir).saveNow(s)
        let back = try await Store(directory: dir).load()
        #expect(back.clients == s.clients && back.clients.map(\.id) == ["c1"])
        #expect(back.clients[0].people.count == 3 && back.clients[0].links.count == 1 && back.clients[0].telLog.count == 1)
        #expect(back.sessions.allSatisfy { $0.clientId == "c1" } && back.trashed.first?.record.clientId == "c1")
    }

    /// Удаление клиента в снимке: съёмка остаётся и в файле без `clientId`.
    @Test func aDeletedClientLeavesItsShootsInTheFileWithoutTheKey() throws {
        var s = Self.sample()
        #expect(ClientBook.delete("c1", clients: &s.clients, sessions: &s.sessions, trashed: &s.trashed, nowMs: 9))
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Snapshot.self, from: data)
        #expect(back.clients.isEmpty && back.sessions.count == 1 && back.sessions[0].clientId == nil)
        #expect(!String(decoding: data, as: UTF8.self).contains("clientId"), "ключ снят, не пустая строка")
    }
}
