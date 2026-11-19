import SwiftUI
import UIKit
import XCTest
@testable import LightPlanUI

/// Живой экран свечения (хвост 29.3а, перенесено из `WarnGlowRestMeterTests` в 31.10): плашка с предупреждением в покое
/// пересчитывает свечение по расписанию (10 в секунду), не на каждом кадре и не замирает.
///
/// Почему XCTest, а не Swift Testing. Замер живой: его ведут настоящие кадры экрана, подставить часы некуда. В полном
/// прогоне тесты Swift Testing идут параллельно и держат главный поток без просвета — 19.11 за 114 с ожидания один
/// пересчёт, сон 300 мс длился 43 с: экран не рисуется вовсе, и никакое ожидание не делает замер честным. XCTest того же
/// пакета xcodebuild запускает раньше, по одному тесту, пока Swift Testing ещё не начался (журнал полного прогона:
/// «Test Suite 'All tests'» перед «Test run with … tests»). Тест пишет, насколько опоздал сон, — видно, что поток был свободен.
final class WarnGlowLiveScreenTests: XCTestCase {

    private struct Plate: View {
        let name: String
        var body: some View {
            Text("Предупреждение").padding(14).frame(width: 300)
                .background(Color.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(20)
                .modifier(WarnGlow(rgb: (201, 102, 61), alpha: 0.32, meterName: name))
        }
    }

    /// Окно с плашкой; пока жив результат, плашка на экране.
    @MainActor private func host(name: String) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 400)
        window.rootViewController = UIHostingController(rootView: Plate(name: name))
        window.makeKeyAndVisible()
        return window
    }

    private func hits(_ name: String) -> Int { EdgeBackMeter.snapshot()[name, default: 0] }

    /// Ждём восемь пересчётов (до 60 с — зависший экран всё равно красный), считаем, сколько их влезало во время.
    @MainActor func testGlowRecalculatesOnScheduleNotEveryFrame() async throws {
        let name = "WarnGlow.test.\(UUID().uuidString)"       // свой счёт: другие экраны со свечением не в зачёте
        let window = host(name: name)
        defer { window.isHidden = true }
        let clock = ContinuousClock()
        let s0 = clock.now
        try? await Task.sleep(for: .milliseconds(300))      // первая отрисовка
        let lag = ((clock.now - s0) - .milliseconds(300)).seconds
        let hits0 = hits(name)
        let t0 = clock.now
        var got = 0
        while got < 8, clock.now - t0 < .seconds(60) {
            try? await Task.sleep(for: .milliseconds(20))
            got = hits(name) - hits0
        }
        let elapsed = (clock.now - t0).seconds
        let line = "hits=\(got) за \(String(format: "%.2f", elapsed)) с, расписание даёт не больше \(Int(elapsed / WarnGlow.step) + 2); сон 300 мс опоздал на \(String(format: "%.3f", lag)) с"
        print("WARNGLOW live \(line)")
        try? (line + "\n").write(toFile: "/tmp/cc-warn-meter.txt", atomically: true, encoding: .utf8)
        XCTAssertGreaterThanOrEqual(got, 8, "свечение замерло: \(line)")
        XCTAssertLessThanOrEqual(got, Int(elapsed / WarnGlow.step) + 2, "пересчётов больше, чем отпускает расписание: \(line)")
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
