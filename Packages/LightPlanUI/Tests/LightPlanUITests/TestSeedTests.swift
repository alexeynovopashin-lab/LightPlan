import Testing
import Foundation
@testable import LightPlanUI
import LightPlanData

/// Тестовый засев копии ветки (Алексей, 29.09): лежит в пакете и читается как снимок.
struct TestSeedTests {
    @Test func seedDecodesAsSnapshot() throws {
        let snap = try #require(TestSeed.snapshot())
        #expect(snap.sessions.count == 23)
        #expect(snap.sessions.contains { $0.id == "sd_sep_inter" })
    }
}
