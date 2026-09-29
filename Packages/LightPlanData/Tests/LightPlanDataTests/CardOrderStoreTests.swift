import Testing
import Foundation
@testable import LightPlanData
import LightPlanDomain

/// Итерация 26, шаг 2: порядок блоков карточки в снимке. Веб сохраняет
/// порядок по всем детям контейнера, а у не-блоков (тревоги, студийный час) и
/// у блоков, которых в той съёмке не было, ключа нет — в файл уходит `null`
/// (`JSON.stringify({event:[undefined,"day"]})` → `{"event":[null,"day"]}`,
/// опыт шага 1). Такой файл не должен ронять весь снимок.
struct CardOrderStoreTests {

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("light-plan-card-order-\(UUID().uuidString)", isDirectory: true)
    }

    /// Файл веба после перестановки: `null` на местах не-блоков и в выключенных.
    private let webFile = #"""
    {"sessions":[],"theme":"dark","practice":"ru",
     "cardOrder":{"event":[null,null,null,null,"day","deal","clash"],"client":["brief",null,"money"]},
     "cardOff":{"people":[null,"money"]}}
    """#

    @Test func webOrderWithNullsReadsWholeSnapshot() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(webFile.utf8).write(to: dir.appendingPathComponent("light-plan.json"))

        let loaded = try await Store(directory: dir).load()
        #expect(loaded.theme == "dark")
        #expect(loaded.cardOrder == [.event: [.day, .deal, .clash], .client: [.brief, .money]])
        #expect(loaded.cardOff == [.people: [.money]])
    }

    /// Группа, записанная целиком как `null`, — как будто правки не было.
    @Test func nullGroupIsNoEdit() throws {
        let json = #"{"cardOrder":{"own":null,"people":["money"]}}"#
        let snap = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        #expect(snap.cardOrder == [.people: [.money]])
    }
}
