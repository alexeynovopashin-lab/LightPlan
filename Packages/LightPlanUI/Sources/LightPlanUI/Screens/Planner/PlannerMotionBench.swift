#if DEBUG && os(iOS)
import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Стенд малых движений «Съёмок» (29.2в): `-LPMotionBench month|week|bar|fan|tab|ring`. Делает то же, что палец,
/// теми же функциями, а кадры снимает `xcrun simctl io recordVideo` (`Tools/motion_bench.js` меряет по ним числа).
/// Метки со временем — в файл `-LPPartLog`. Не часть приложения: только Debug.
@MainActor
enum MotionBench {
    static var name: String? { UserDefaults.standard.string(forKey: "LPMotionBench") }
    static var on: Bool { name != nil }

    static func run(_ app: AppModel, flip: @escaping (Int) -> Void, fan: @escaping () -> Void) async {
        guard let name else { return }
        func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        func mark(_ s: String) { PartDayLog.note("motion \(name) \(s)") }
        mark("start still=\(UIAccessibility.isReduceMotionEnabled)")
        await wait(5)   // видео уже идёт, экран успел нарисоваться и успокоиться
        switch name {
        case "month", "week":
            // Первый шаг — разминка: от «сегодня» уходит подпись «↺ сегодня» под шапкой и всё едет по вертикали,
            // замеру нужно чистое горизонтальное движение.
            mark("warmup"); flip(1); await wait(2.5)
            for dir in [1, -1, 1] { mark("flip \(dir)"); flip(dir); await wait(1.6) }
        case "bar":
            for _ in 0..<2 { mark("fold"); PlannerDayPanel.fold(app, still: UIAccessibility.isReduceMotionEnabled); await wait(1.6) }
        case "fan":
            for _ in 0..<2 { mark("fan"); fan(); await wait(1.6) }
        case "tab":
            for t in [AppTab.light, .planner, .light, .planner] { mark("tab \(t)"); app.tab = t; await wait(1.6) }
        case "ring":
            // Дни месяца с рангом «просрочено» — кольцо дышит только у них.
            let st = app.planner
            let lit = st.monthGrid.filter {
                PlannerState.sameMonth($0, st.month) && (Urgency.dayMark($0, sessions: app.sessions, status: app.deliveryStatus)?.rank ?? 0) >= 3
            }
            mark("lit " + lit.map { String($0.day) }.joined(separator: ","))
            await wait(9)
        default: break
        }
        mark("done")
    }
}
#endif

/// Рамка узла в журнал стенда на каждое изменение (пока движение идёт, раскладка пересчитывается по кадрам).
/// Вне стенда и в Release — ничего.
extension View {
    @ViewBuilder
    func motionGeo(_ name: String) -> some View {
        #if DEBUG && os(iOS)
        if MotionBench.on {
            onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                PartDayLog.note("geo \(name) \($0.minX) \($0.minY) \($0.width) \($0.height)")
            }
        } else { self }
        #else
        self
        #endif
    }
}

/// Узкий экран без узкого телефона: `-LPPanelWidth 320` (ширина экрана, pt) сажает сводку дня в панель такой ширины.
/// Симуляторов iPhone SE 1-го поколения (320 pt) в iOS 26 нет. Вне стенда и в Release — ничего.
extension View {
    @ViewBuilder
    func benchPanelWidth() -> some View {
        #if DEBUG && os(iOS)
        if let w = UserDefaults.standard.string(forKey: "LPPanelWidth").flatMap(Double.init) {
            frame(width: CGFloat(w) - 40).frame(maxWidth: .infinity, alignment: .leading)
        } else { self }
        #else
        self
        #endif
    }
}
