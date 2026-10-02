import Testing
import Foundation
@testable import LightPlanData

/// Шаг 28с: сводка «Карты» стартует свёрнутой (слово Алексея 01.10); явный выбор запоминается.
struct MapFoldDefaultTests {

    @Test func freshSnapshotStartsShut() {
        #expect(Snapshot().mapFold == true)
    }

    @Test func missingKeyMeansShut() throws {
        let s = try JSONDecoder().decode(Snapshot.self, from: Data("{}".utf8))
        #expect(s.mapFold == true)
    }

    @Test func explicitChoiceSurvivesRoundTrip() throws {
        for shut in [true, false] {
            var s = Snapshot()
            s.mapFold = shut
            let back = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(s))
            #expect(back.mapFold == shut)
        }
    }

    @Test func explicitOpenIsNotOverriddenByDefault() throws {
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"mapFold":false}"#.utf8))
        #expect(s.mapFold == false)
    }
}
