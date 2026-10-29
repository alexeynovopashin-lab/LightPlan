import SwiftUI
import LightPlanCore
import LightPlanDomain

#if DEBUG && os(iOS)
/// Стенд закреплённой шапки ленты года (30.1б, Debug): `-LPPinLog <файл>` пишет на каждое изменение прокрутки строку
/// «время, прокрутка, месяц шапки, рамки шапки / названия / линейки / первого ряда»; `-LPPinScript scroll|today|open` ведёт ленту
/// сам (тем же `scrollTo`, что и кнопка прыжка), чтобы кадры снимались без пальца.
enum PinBench {
    nonisolated(unsafe) static var geo: [String: CGRect] = [:]
    nonisolated(unsafe) private static var t0 = Date()
    static var path: String? { UserDefaults.standard.string(forKey: "LPPinLog") }
    static var script: String? { UserDefaults.standard.string(forKey: "LPPinScript") }

    static func note(_ s: String) {
        guard let path else { return }
        let line = String(format: "%7.0f ", Date().timeIntervalSince(t0) * 1000) + s + "\n"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: URL(fileURLWithPath: path)) }
    }

    static func frame(scrolled: CGFloat, pinned: CivilDate?) {
        func r(_ k: String) -> String { geo[k].map { String(format: "%.1f,%.1f,%.1f,%.1f", $0.minX, $0.minY, $0.width, $0.height) } ?? "-" }
        note(String(format: "scroll=%.1f pinned=%@ head=%@ month=%@ ruler=%@", scrolled,
                    pinned.map { "\($0.year)-\($0.month)" } ?? "-", r("head"), r("month"), r("ruler")))
    }
}

extension PinBench {
    /// Цепочка видов (Debug, `-LPPinScript chain`): день → месяц → лента года → месяц → «сегодня» с другого дня; метки в журнале.
    nonisolated(unsafe) private static var chainStarted = false
    @MainActor static func chain(_ app: AppModel, nav: PlannerNav) async {
        guard !chainStarted else { return }
        chainStarted = true
        func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        await wait(2.5)
        note("chain day"); PlanMotion.setScope(app, .day); await wait(1.2)
        note("chain month"); PlanMotion.setScope(app, .month); await wait(1.2)
        note("chain year open"); PlanMotion.lenta(app, nav, open: true); await wait(2.2)
        note("chain year close"); PlanMotion.lenta(app, nav, open: false); await wait(1.2)
        note("chain month away"); app.planner.setScope(.month); app.planner.enterMonth(CivilDate(year: 2027, month: 3, day: 1), today: app.today); await wait(1.2)
        note("chain today"); app.planner.goToday(app.today); await wait(1.2)
        note("chain year open 2"); PlanMotion.lenta(app, nav, open: true); await wait(2.2)
        note("script chain done")
    }
}

extension View {
    /// Рамка узла шапки для журнала стенда.
    func pinGeo(_ key: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            PinBench.geo[key] = $0
            PinBench.note(String(format: "geo %@ %.1f,%.1f,%.1f,%.1f", key, $0.minX, $0.minY, $0.width, $0.height))
        }
    }
}
#else
extension View { func pinGeo(_ key: String) -> some View { self } }
#endif
