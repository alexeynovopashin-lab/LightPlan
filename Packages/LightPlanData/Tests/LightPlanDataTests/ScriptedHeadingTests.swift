import Foundation
import Testing
@testable import LightPlanData

/// Подставной компас (итерация 21а): углы из аргумента запуска и их порядок —
/// тем же `start`, которым ротор слушает живой магнитометр.
@MainActor
struct ScriptedHeadingTests {
    @Test func parsesLaunchList() {
        #expect(ScriptedHeading.angles("0, 45,90") == [0, 45, 90])
        #expect(ScriptedHeading.angles("158") == [158])
        #expect(ScriptedHeading.angles("") == nil)
        #expect(ScriptedHeading.angles("север") == nil)
    }

    @Test func playsAnglesInOrderAndStops() async throws {
        let src = ScriptedHeading(angles: [0, 45, 90, 135], hold: .milliseconds(30))
        #expect(src.isAvailable, "в симуляторе кнопка компаса должна работать")
        var got: [Double] = []
        src.start { got.append($0) }
        try await Task.sleep(for: .milliseconds(400))
        #expect(got == [0, 45, 90, 135])

        // Остановленный молчит, как живой после `stopUpdatingHeading`.
        let slow = ScriptedHeading(angles: [10, 20, 30], hold: .milliseconds(100))
        var heard: [Double] = []
        slow.start { heard.append($0) }
        try await Task.sleep(for: .milliseconds(30))
        slow.stop()
        try await Task.sleep(for: .milliseconds(300))
        #expect(heard == [10])
    }
}
