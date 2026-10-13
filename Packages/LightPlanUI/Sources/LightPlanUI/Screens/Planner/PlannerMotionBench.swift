#if DEBUG && os(iOS)
import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Стенд малых движений «Съёмок» (29.2в): `-LPMotionBench month|week|day|bar|fan|tab|tabs|ring`. Делает то же, что палец,
/// теми же функциями, а кадры снимает `xcrun simctl io recordVideo` (`Tools/motion_bench.js` меряет по ним числа).
/// Метки со временем — в файл `-LPPartLog`. Не часть приложения: только Debug.
@MainActor
enum MotionBench {
    static var name: String? { UserDefaults.standard.string(forKey: "LPMotionBench") }
    static var on: Bool { name != nil }

    /// Что стенду нужно от экрана «Съёмок»: тот же `flip`, веер видов, веер удержания и вход в день, что у пальца (29.2ж).
    struct Rig {
        let nav: PlannerNav
        let evFan: (Bool) -> Void
        let enterDay: () -> Void
    }

    /// Лист «Занять время» (`block`): тот же стенд выставляет строки даты внутри листа (`BlockSheet.task`).
    static var isBlock: Bool { name == "block" }

    static func run(_ app: AppModel, flip: @escaping (Int) -> Void, fan: @escaping () -> Void, rig: Rig) async {
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
        case "day":
            // День листается тем же `flip`, что свайп (29.2е): три шага вправо, влево, вправо.
            for dir in [1, -1, 1] { mark("flip \(dir)"); flip(dir); await wait(1.6) }
        case "bar":
            for _ in 0..<2 { mark("fold"); PlannerDayPanel.fold(app, still: UIAccessibility.isReduceMotionEnabled); await wait(1.6) }
        case "fan":
            for _ in 0..<2 { mark("fan"); fan(); await wait(1.6) }
        case "tab":
            for t in [AppTab.light, .planner, .light, .planner] { mark("tab \(t)"); app.tab = t; await wait(1.6) }
        case "tabs":
            // Все двенадцать переходов между четырьмя вкладками, в обе стороны: обход полного графа K4 за 12 шагов.
            let walk: [AppTab] = [.light, .map, .planner, .settings, .light, .planner, .map, .settings, .planner, .light, .settings, .map, .light]
            app.tab = walk[0]; await wait(2)
            for t in walk.dropFirst() { mark("tab \(t)"); app.tab = t; await wait(1.6) }
        case "card", "stats", "search", "year", "year12", "evfan", "undo", "bin", "block", "cell", "wcell", "scope", "m2d":
            await moves(name, app, rig, wait: wait, mark: mark)
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

    /// Движения «Съёмок» 29.2ж: каждое — то же именованное действие `PlanMotion`, что у пальца. Разминка (первая пара)
    /// не меряется: стенд берёт последние `trig` событий.
    private static func moves(_ name: String, _ app: AppModel, _ rig: Rig, wait: (Double) async -> Void, mark: (String) -> Void) async {
        let nav = rig.nav
        let sid = app.sessions.first?.id ?? ""
        let st = app.planner
        let days = st.monthGrid.filter { PlannerState.sameMonth($0, st.month) }
        let d1 = days.first { $0.day == 10 } ?? days[0], d2 = days.first { $0.day == 17 } ?? days[1]
        // Разминка: первое открытие тянет за собой содержимое, замеру нужно чистое движение.
        func pair(_ n: Int, _ on: () -> Void, _ off: () -> Void, _ a: String, _ b: String) async {
            for _ in 0..<n { mark(a); on(); await wait(1.6); mark(b); off(); await wait(1.6) }
        }
        switch name {
        case "card":
            await pair(3, { PlanMotion.openCard(app, id: sid) }, { PlanMotion.closeCard(app) }, "card open", "card close")
        case "stats":
            await pair(3, { PlanMotion.stats(nav, open: true) }, { PlanMotion.stats(nav, open: false) }, "stats open", "stats close")
        case "search":
            await pair(3, { PlanMotion.search(nav, open: true) }, { PlanMotion.search(nav, open: false) }, "search open", "search close")
        case "year":
            await pair(3, { PlanMotion.lenta(app, nav, open: true) }, { PlanMotion.lenta(app, nav, open: false) }, "year open", "year close")
        case "year12":
            PlanMotion.lenta(app, nav, open: true); await wait(2)
            await pair(3, { PlanMotion.year12(nav, open: true) }, { PlanMotion.year12(nav, open: false) }, "year12 open", "year12 close")
        case "evfan":
            await pair(3, { rig.evFan(true) }, { rig.evFan(false) }, "evfan open", "evfan close")
        case "undo":
            let ids = app.sessions.prefix(3).map(\.id)
            for id in ids {
                mark("undo show"); app.trashSession(id: id); await wait(1.6)
                mark("undo take"); PlanMotion.takeUndo(app); await wait(1.6)
            }
        case "bin":
            let ids = Array(app.sessions.prefix(4).map(\.id))
            for id in ids { app.trashSession(id: id); await wait(0.3) }
            await wait(7)   // полоса «Вернуть» ушла сама
            app.binOpen = true; await wait(3)
            for id in ids { mark("bin restore"); PlanMotion.restore(app, id: id); await wait(1.6) }
        case "block":
            app.openBlockSheet(day: app.planner.selected)
            await wait(15)   // строки листа выставляет `BlockSheet.task` (6 раз с паузой 1,6 с)
        case "cell":
            for d in [d1, d2, d1, d2] { mark("cell tap"); PlanMotion.tapMonthCell(app, d); await wait(1.6) }
        case "wcell":
            // Строки недели на экране — дни выбранной недели: стучим по соседям выбранного дня (ревью GPT к fbc0826).
            let w1 = st.selected.adding(days: -1), w2 = st.selected.adding(days: 1)
            for d in [w1, w2, w1, w2] { mark("wcell tap"); PlanMotion.tapWeekRow(app, d); await wait(1.6) }
        case "scope":
            for s in [CalScope.week, .month, .week, .month] { mark("scope \(s)"); PlanMotion.setScope(app, s); await wait(1.6) }
        case "m2d":
            for _ in 0..<3 {
                mark("m2d enter"); rig.enterDay(); await wait(2.4)
                mark("m2d exit"); PlanMotion.setScope(app, .month); await wait(1.6)
            }
        default: break
        }
    }
}

extension MotionBench {
    /// Лист «Занять время»: шесть переключений строки даты «С» — те же `toggle`, что тап по капсуле.
    static func blockRows(_ log: (String) -> Void, toggle: @MainActor () -> Void) async {
        try? await Task.sleep(for: .seconds(3))
        for _ in 0..<6 {   // шесть: меряются последние четыре — раскрыть, закрыть, раскрыть, закрыть
            log("block row"); toggle()
            try? await Task.sleep(for: .seconds(1.6))
        }
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
