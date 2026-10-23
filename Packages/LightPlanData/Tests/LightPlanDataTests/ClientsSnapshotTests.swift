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
}
