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

    /// Ждёт условия, а не срока: в полном наборе главный поток занят другими тестами, фиксированный сон не держит.
    private func wait(until done: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while !done(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func playsAnglesInOrderAndStops() async throws {
        let src = ScriptedHeading(angles: [0, 45, 90, 135], hold: .milliseconds(30))
        #expect(src.isAvailable, "в симуляторе кнопка компаса должна работать")
        var got: [Double] = []
        src.start { got.append($0) }
        try await wait { got.count >= 4 }
        #expect(got == [0, 45, 90, 135])

        // Остановленный молчит, как живой после `stopUpdatingHeading`.
        let slow = ScriptedHeading(angles: [10, 20, 30], hold: .milliseconds(500))
        var heard: [Double] = []
        slow.start { heard.append($0) }
        try await wait { !heard.isEmpty }
        slow.stop()
        // Ждём дольше удержания: без остановки вторая отметка пришла бы.
        try await Task.sleep(for: .milliseconds(700))
        #expect(heard == [10])
    }
}
