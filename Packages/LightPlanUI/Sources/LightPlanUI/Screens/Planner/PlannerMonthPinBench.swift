import SwiftUI
import LightPlanCore
import LightPlanDomain

#if DEBUG && os(iOS)
/// Стенд закреплённой линейки месяца (30.2, Debug): в тот же журнал, что у ленты года (`-LPPinLog <файл>`), идут рамки названия шапки
/// (`mtitle`), линейки (`mruler`), сетки (`mgrid`), панели дня (`mpanel`), низа шапки (`mhead`) и прокрутка экрана (`mscroll=`);
/// `-LPMonthScript scroll|jump|fold|scopes|today` ведёт экран сам теми же действиями, что палец (`PlanMotion.setScope`, `scrollTo`,
/// `app.dayFold`, `goToday`), чтобы кадры снимались без пальца.
enum MonthPinBench {
    static var script: String? { UserDefaults.standard.string(forKey: "LPMonthScript") }

    static func scroll(_ y: CGFloat) { PinBench.note(String(format: "mscroll=%.1f", y)) }

    @MainActor static func run(_ app: AppModel, nav: PlannerNav, scrollTo: @escaping (CGFloat) -> Void, scrollEdge: @escaping (Edge) -> Void) async {
        guard let name = script else { return }
        func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        await wait(2.5)
        switch name {
        case "scroll":
            // Вниз на 520 pt и назад линейно по 3 с: линейка и название стоят, сетка и список едут.
            PinBench.note("script scroll down")
            withAnimation(PlanMotion.pick(.linear(duration: 3))) { scrollTo(520) }
            await wait(3.6)
            PinBench.note("script scroll up")
            withAnimation(PlanMotion.pick(.linear(duration: 3))) { scrollTo(0) }
            await wait(3.4)
        case "hold":
            // Неподвижный кадр с прокруткой на 400 pt (картинки «было / стало»).
            var off = Transaction(); off.disablesAnimations = true
            withTransaction(off) { scrollTo(400) }
            await wait(30)
        case "jump":
            // То же, что кнопка «Наверх»: `scrollTo(edge:)` по `easeInOut` 0,35 с.
            PinBench.note("script jump down")
            withAnimation(PlanMotion.pick(PlanMotion.jump)) { scrollEdge(.bottom) }
            await wait(1.2)
            PinBench.note("script jump up")
            withAnimation(PlanMotion.pick(PlanMotion.jump)) { scrollEdge(.top) }
            await wait(1.2)
        case "fold":
            PinBench.note("script fold shut")
            withAnimation(PlanMotion.pick(Motion.fold)) { app.dayFold = true }
            await wait(1.2)
            PinBench.note("script fold open")
            withAnimation(PlanMotion.pick(Motion.fold)) { app.dayFold = false }
            await wait(1.2)
        case "scopes":
            // месяц → неделя → месяц → день → месяц → (прокрутка) → неделя → месяц
            for (n, s) in [("week", CalScope.week), ("month", .month), ("day", .day), ("month", .month)] {
                PinBench.note("script scope \(n)"); PlanMotion.setScope(app, s); await wait(1.4)
            }
            PinBench.note("script scroll 300"); withAnimation(PlanMotion.pick(.linear(duration: 0.5))) { scrollTo(300) }; await wait(1)
            PinBench.note("script scope week"); PlanMotion.setScope(app, .week); await wait(1.4)
            PinBench.note("script scope month"); PlanMotion.setScope(app, .month); await wait(1.4)
        case "today":
            PinBench.note("script away")
            app.planner.enterMonth(CivilDate(year: 2027, month: 3, day: 1), today: app.today); await wait(1.4)
            PinBench.note("script today"); app.planner.goToday(app.today); await wait(1.4)
        default: break
        }
        PinBench.note("script \(name) done")
    }
}
#endif
