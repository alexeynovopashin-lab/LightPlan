import SwiftUI
import UIKit
import Testing
@testable import LightPlanUI

/// Хвост 29.3а: плашка с предупреждением в покое пересчитывала свечение на каждом кадре экрана (замер до правки:
/// 181 пересчёт за 3 с при 181 кадре, 0,26 мс главного потока на кадр против 0,09 у неподвижной). Теперь —
/// десять в секунду; дыхание не убрано (поведение беты `glow-flow`): пересчёты идут, и тень движется.
@MainActor
struct WarnGlowRestMeterTests {

    private struct Plate: View {
        let glow: Bool
        var body: some View {
            let plate = Text("Предупреждение").padding(14).frame(width: 300)
                .background(Color.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(20)
            if glow { plate.modifier(WarnGlow(rgb: (201, 102, 61), alpha: 0.32)) } else { plate }
        }
    }

    private func measure(glow: Bool, seconds: Double) async -> (frames: Int, hits: Int, cpuMs: Double) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 400)
        let host = UIHostingController(rootView: Plate(glow: glow))
        window.rootViewController = host
        window.makeKeyAndVisible()
        try? await Task.sleep(for: .milliseconds(600))          // прогрев: первая отрисовка
        let probe = FrameProbe()
        let hits0 = EdgeBackMeter.snapshot()["WarnGlow", default: 0]
        let cpu0 = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        probe.start()
        try? await Task.sleep(for: .seconds(seconds))
        probe.stop()
        let cpu1 = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        let hits = EdgeBackMeter.snapshot()["WarnGlow", default: 0] - hits0
        window.isHidden = true
        return (probe.frames, hits, Double(cpu1 &- cpu0) / 1e6)
    }

    @MainActor private final class FrameProbe: NSObject {
        var frames = 0
        private var link: CADisplayLink?
        func start() {
            let l = CADisplayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common); link = l
        }
        func stop() { link?.invalidate(); link = nil }
        @objc private func tick() { frames += 1 }
    }

    @Test func glowRecalculatesTenTimesASecondNotEveryFrame() async throws {
        // Прогон под нагрузкой (параллельные сборки, два полных набора подряд) голодает: дисплейная ссылка отдаёт
        // единицы кадров вместо 180, и счёт «пересчётов на кадр» теряет смысл (29.8в.22: красный при hits=1, 34 с
        // вместо 6; в покое три прогона — frames=180 hits=30, 7,3 с). Замер, в котором кадров меньше двух третей
        // нормы, не считается: повторяем до четырёх раз и судим по последнему.
        var moving = await measure(glow: true, seconds: 3)
        var attempts = 1
        while moving.frames < 120, attempts < 4 { moving = await measure(glow: true, seconds: 3); attempts += 1 }
        let still = await measure(glow: false, seconds: 3)
        let line = "attempts=\(attempts) moving frames=\(moving.frames) hits=\(moving.hits) cpu=\(String(format: "%.1f", moving.cpuMs))ms"
            + " per-frame=\(String(format: "%.2f", moving.cpuMs / Double(max(1, moving.frames))))ms"
            + " | static frames=\(still.frames) cpu=\(String(format: "%.1f", still.cpuMs))ms"
            + " per-frame=\(String(format: "%.2f", still.cpuMs / Double(max(1, still.frames))))ms\n"
        try? line.write(toFile: "/tmp/cc-warn-meter.txt", atomically: true, encoding: .utf8)
        // Не каждый кадр (на 60 Гц было 181 из 181) и не замерло: ~30 за 3 с; запас на нагрузку полного прогона.
        #expect(moving.hits >= 8, "\(line)")
        #expect(moving.hits <= moving.frames / 3, "\(line)")
    }
}
