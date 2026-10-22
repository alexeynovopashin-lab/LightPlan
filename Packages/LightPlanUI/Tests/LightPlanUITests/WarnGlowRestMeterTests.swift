import SwiftUI
import UIKit
import Testing
@testable import LightPlanUI

/// Хвост 29.3а: плашка с предупреждением в покое пересчитывала свечение на каждом кадре экрана (замер до правки:
/// 181 пересчёт за 3 с при 181 кадре, 0,26 мс главного потока на кадр против 0,09 у неподвижной). Теперь —
/// десять в секунду; дыхание не убрано (поведение беты `glow-flow`): пересчёты идут, и тень движется.
///
/// 29.8в.28: тесты не меряют кадры и миллисекунды. Раньше три секунды живого экрана с дисплейной ссылкой падали, когда
/// главный поток занимали соседние тесты полного прогона (кадров 162 из 180, пересчётов 1 при ожидаемых 30; ещё один
/// замер в покое — 0,14 мс на кадр, в полном прогоне — 5,15). Теперь: (1) расписание — чистая последовательность дат
/// без часов и экрана; (2) на живом экране — условие, а не время: ждём восьмой пересчёт сколько понадобится и
/// проверяем, что их не больше, чем помещается в прошедшее время (нагрузка может только замедлить, не ускорить).
@MainActor
struct WarnGlowRestMeterTests {

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
    private func host(name: String) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 400)
        window.rootViewController = UIHostingController(rootView: Plate(name: name))
        window.makeKeyAndVisible()
        return window
    }

    private func hits(_ name: String) -> Int { EdgeBackMeter.snapshot()[name, default: 0] }

    /// Записи расписания за три секунды от любой точки: ровно по `step`, не по кадру (без `minimumInterval` там было
    /// бы 361 запись на 120 Гц; на 60 Гц — 181, как в замере до правки).
    @Test func scheduleGivesTenEntriesASecond() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        var dates: [Date] = []
        for d in WarnGlow.schedule.entries(from: start, mode: .normal) {
            if d > start.addingTimeInterval(3) { break }
            dates.append(d)
            if dates.count > 1000 { break }                 // защита от бесконечной последовательности
        }
        #expect(dates.count >= 29 && dates.count <= 31, "записей за 3 с: \(dates.count)")
        let gaps = zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) }
        #expect((gaps.min() ?? 0) >= WarnGlow.step - 0.001, "самый короткий зазор \(gaps.min() ?? 0) с")
    }

    /// На экране свечение пересчитывается и не чаще расписания: ждём восемь пересчётов (до 60 с — под нагрузкой
    /// полного прогона хватает и секунд, а зависший экран всё равно красный), считаем, сколько их влезало в время.
    @Test func glowRecalculatesOnScheduleNotEveryFrame() async {
        let name = "WarnGlow.test.\(UUID().uuidString)"       // свой счёт: другие экраны со свечением не в зачёте
        let window = host(name: name)
        defer { window.isHidden = true }
        try? await Task.sleep(for: .milliseconds(300))      // первая отрисовка
        let clock = ContinuousClock()
        let hits0 = hits(name)
        let t0 = clock.now
        var got = 0
        while got < 8, clock.now - t0 < .seconds(60) {
            try? await Task.sleep(for: .milliseconds(20))
            got = hits(name) - hits0
        }
        let elapsed = (clock.now - t0).seconds
        let line = "hits=\(got) за \(String(format: "%.2f", elapsed)) с, расписание даёт не больше \(Int(elapsed / WarnGlow.step) + 2)"
        try? (line + "\n").write(toFile: "/tmp/cc-warn-meter.txt", atomically: true, encoding: .utf8)
        #expect(got >= 8, "свечение замерло: \(line)")
        #expect(got <= Int(elapsed / WarnGlow.step) + 2, "пересчётов больше, чем отпускает расписание: \(line)")
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
