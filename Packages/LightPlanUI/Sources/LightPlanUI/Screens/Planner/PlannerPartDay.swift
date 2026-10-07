import SwiftUI
import LightPlanCore
#if os(iOS)
import UIKit
#endif

/// Разрез месяца при входе в день (29.2а; веб `partMonthIntoDay`, `index.html`, аудит C1). Строка выбранной недели
/// остаётся, месяц над ней уезжает вверх, под ней — вниз, семь ячеек недели едут на места дат ленты дня, а под
/// разрезом уже стоит день. Входы: второй тап по выбранному числу месяца и «День» в веере видов; лента года — 29.2б.
///
/// Как у беты (DECISIONS «…анимацию вешают на переход», «Как Apple режет вид календаря»): половины — снимки
/// экрана, обрезанные по строке недели, непрозрачные; ячейки — настоящие (`MonthCell`), не снимки, иначе с ними
/// летел бы прямоугольник стеклянной подложки; лента дат дня спрятана, пока ячейки не приехали. На каждом кадре
/// каждая неделя видна ровно в одном виде — защита от «призрака».
///
/// Числа — из кода беты: переезд 0,34 с `cubic-bezier(0.4, 0, 0.2, 1)`; гашение половин 0,1 с `ease` с задержкой
/// 0,24, ячеек — с задержкой 0,26; лента дат открывается в 280 мс, снимки сняты в 400 мс; половины уходят за край
/// с запасом 12 pt. «Уменьшение движения» — вход без разреза, мгновенно.
enum PartDayTiming {
    static let move = 0.34
    static let moveCurve = CubicCurve(0.4, 0, 0.2, 1)
    /// CSS `ease`.
    static let fadeCurve = CubicCurve(0.25, 0.1, 0.25, 1)
    static let fade = 0.1
    static let halfFadeDelay = 0.24
    static let cellFadeDelay = 0.26
    static let stripAt = 0.28
    static let end = 0.40
    static let overshoot: CGFloat = 12

    static var moveAnimation: Animation { .timingCurve(0.4, 0, 0.2, 1, duration: move) }
    static var halfFadeAnimation: Animation { .timingCurve(0.25, 0.1, 0.25, 1, duration: fade).delay(halfFadeDelay) }
    static var cellFadeAnimation: Animation { .timingCurve(0.25, 0.1, 0.25, 1, duration: fade).delay(cellFadeDelay) }

    /// Кадр разреза через `t` с от старта: доля пути, непрозрачность половин и ячеек, видна ли лента дат.
    /// Им же рисуется замороженный кадр пары снимков (`part:<мс>`), живой разрез ведут анимации SwiftUI с теми же кривыми.
    struct Frame: Equatable {
        var move: Double
        var halves: Double
        var cells: Double
        var stripShown: Bool
    }

    static func frame(at t: Double) -> Frame {
        func fadeOut(_ delay: Double) -> Double { 1 - fadeCurve.y(atX: (t - delay) / fade) }
        return Frame(move: moveCurve.y(atX: t / move), halves: fadeOut(halfFadeDelay), cells: fadeOut(cellFadeDelay),
                     stripShown: t >= stripAt)
    }
}

/// Кривая CSS `cubic-bezier(x1, y1, x2, y2)`: `y` по `x` (решение по `x` — Ньютон, затем деление пополам, как в WebKit).
struct CubicCurve: Equatable {
    let x1, y1, x2, y2: Double
    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) { (self.x1, self.y1, self.x2, self.y2) = (x1, y1, x2, y2) }

    private func bez(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    func y(atX x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var t = x
        for _ in 0..<8 {
            let e = bez(t, x1, x2) - x
            if abs(e) < 1e-7 { return bez(t, y1, y2) }
            let u = 1 - t
            let d = 3 * u * u * x1 + 6 * u * t * (x2 - x1) + 3 * t * t * (1 - x2)
            if abs(d) < 1e-6 { break }
            t -= e / d
        }
        var lo = 0.0, hi = 1.0
        t = x
        while hi - lo > 1e-7 {
            if bez(t, x1, x2) < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return bez(t, y1, y2)
    }
}

/// Где что лежит в разрезе. Всё в координатах окна (`.global`).
enum PartDayGeometry {
    /// Ячейки строки месяца: семь колонок через `MonthMetrics.colGap`.
    static func cells(row: CGRect) -> [CGRect] {
        let w = (row.width - 6 * MonthMetrics.colGap) / 7
        return (0..<7).map { CGRect(x: row.minX + CGFloat($0) * (w + MonthMetrics.colGap), y: row.minY, width: w, height: row.height) }
    }

    /// Даты ленты дня (`PlannerDaySticky`): семь колонок через 2 pt.
    static func dates(strip: CGRect) -> [CGRect] {
        let w = (strip.width - 6 * PlannerDaySticky.dateGap) / 7
        return (0..<7).map { CGRect(x: strip.minX + CGFloat($0) * (w + PlannerDaySticky.dateGap), y: strip.minY, width: w, height: strip.height) }
    }

    /// Куда уходят половины: верх — выше верха экрана на запас, низ — ниже низа (веб: `-(rowTop - devTop + 12)`,
    /// `devBottom - rowBot + 12`).
    static func halves(row: CGRect, screen: CGRect) -> (up: CGFloat, down: CGFloat) {
        (-(row.minY - screen.minY + PartDayTiming.overshoot), screen.maxY - row.maxY + PartDayTiming.overshoot)
    }

    /// Перелёт ячейки на дату: сдвиг левого верхнего угла и масштаб по осям (веб `translate(…) scale(…)`,
    /// `transform-origin: top left`).
    struct Fly: Equatable { var dx, dy, sx, sy: CGFloat }

    static func fly(_ from: CGRect, _ to: CGRect) -> Fly {
        Fly(dx: to.minX - from.minX, dy: to.minY - from.minY,
            sx: from.width > 0 ? to.width / from.width : 1, sy: from.height > 0 ? to.height / from.height : 1)
    }

    /// Рамка ячейки на доле пути `p`: каждая составляющая преобразования идёт по одной кривой, как у CSS.
    static func rect(_ from: CGRect, _ f: Fly, at p: CGFloat) -> CGRect {
        CGRect(x: from.minX + f.dx * p, y: from.minY + f.dy * p,
               width: from.width * (1 + (f.sx - 1) * p), height: from.height * (1 + (f.sy - 1) * p))
    }
}

/// Машина разреза — без экрана, её держат тесты. `idle` → `cut` (снимки легли, день уже под ними, лента дат
/// спрятана, ждём её раскладку) → `moving` (пошло движение) → `revealed` (с 280 мс лента дат видна) → `idle` (400 мс).
/// Касание, смена вида или вкладки посреди — сразу `idle`: конечный кадр, лента видна, снимков нет.
struct PartDayMachine: Equatable {
    enum Phase: Equatable { case idle, cut, moving, revealed }
    private(set) var phase = Phase.idle
    private(set) var start: Double?
    /// Номер разреза: таймер прерванного разреза новый не трогает.
    private(set) var run = 0

    var showsLayer: Bool { phase != .idle }
    var stripHidden: Bool { phase == .cut || phase == .moving }

    /// Тап: снимки положены, день под ними. Идущий разрез обрывается.
    @discardableResult
    mutating func cut() -> Int {
        phase = .cut
        start = nil
        run += 1
        return run
    }

    /// Лента дат разложилась (веб: следующий кадр после `commit`) — пошли.
    mutating func go(at t: Double) {
        guard phase == .cut else { return }
        phase = .moving
        start = t
    }

    /// Часы разреза `r`: с 280 мс лента дат видна, с 400 мс снимков нет.
    mutating func tick(at t: Double, run r: Int) {
        guard r == run, let s = start else { return }
        // Допуск: таймер ставит `t0 + 0,28`, а `(t0 + 0,28) − t0` в двоичных дробях бывает 0,27999…
        let e = t - s + 1e-6
        if e >= PartDayTiming.end { phase = .idle; start = nil }
        else if e >= PartDayTiming.stripAt { phase = .revealed }
    }

    mutating func interrupt() {
        phase = .idle
        start = nil
    }
}

/// Разрез на экране «Съёмки». Рамки строк месяца, ленты дат и экрана сюда пишут виды (`onGeometryChange`) мимо
/// наблюдения — их запись не пересчитывает экран.
@MainActor @Observable
final class PartDay {
    private(set) var machine = PartDayMachine()
    /// Доля пути и непрозрачность — их ведут анимации (`PartDayTiming`).
    private(set) var move: CGFloat = 0
    private(set) var halfAlpha: Double = 1
    private(set) var cellAlpha: Double = 1
    /// Замороженный кадр (пара снимков `part:<мс>`): время от старта, движение не идёт.
    private(set) var frozen: Double?

    @ObservationIgnored var rows: [Int: CGRect] = [:]
    @ObservationIgnored var screen: CGRect = .zero
    @ObservationIgnored private(set) var strip: CGRect = .zero

    struct Cut: Equatable {
        var row: CGRect
        var days: [CivilDate]
        var cells: [CGRect]
        var targets: [CGRect]?
        var screen: CGRect
    }
    private(set) var cut: Cut?
    #if os(iOS)
    @ObservationIgnored private(set) var upper: UIView?
    @ObservationIgnored private(set) var lower: UIView?
    #endif

    /// Вход в день из месяца. Строку недели не нашли, нет окна, «Уменьшение движения» — вход без разреза.
    func enter(_ app: AppModel, still: Bool, frozenAt: Double? = nil) {
        #if os(iOS)
        let commit = {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { app.planner.enterSelectedDay() }
        }
        let grid = app.planner.monthGrid
        guard !still, let i = grid.firstIndex(of: app.planner.selected), let row = rows[i / 7], row.height > 0,
              screen.height > 0, let window = Self.window() else { finish(); commit(); return }
        let r = row.intersection(screen)
        guard !r.isNull, r.height > 0 else { finish(); commit(); return }
        let wb = window.bounds
        let c0 = Self.cpu
        upper = window.resizableSnapshotView(from: CGRect(x: 0, y: 0, width: wb.width, height: max(1, row.minY)),
                                             afterScreenUpdates: false, withCapInsets: .zero)
        lower = window.resizableSnapshotView(from: CGRect(x: 0, y: row.maxY, width: wb.width, height: max(1, screen.maxY - row.maxY)),
                                             afterScreenUpdates: false, withCapInsets: .zero)
        let run = machine.cut()
        move = 0; halfAlpha = 1; cellAlpha = 1; frozen = frozenAt
        cut = Cut(row: row, days: Array(grid[(i / 7 * 7)..<(i / 7 * 7 + 7)]), cells: PartDayGeometry.cells(row: row),
                  targets: nil, screen: CGRect(x: 0, y: 0, width: wb.width, height: screen.maxY))
        let c1 = Self.cpu
        commit()
        PartDayLog.note(String(format: "cut run=%d row=%@ screen=%@ cpu snap=%.1f commit=%.1f", run, Self.f(row), Self.f(screen),
                               Double(c1 &- c0) / 1e6, Double(Self.cpu &- c1) / 1e6))
        // Лента дат могла не разложиться (вид дня собирается в следующем такте) — запасной старт без её рамки.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            if machine.run == run, machine.phase == .cut { begin(run) }
        }
        #else
        withAnimation(.snappy(duration: 0.25)) { app.planner.enterSelectedDay() }
        #endif
    }

    /// Лента дат дня встала на место — отсюда рамки целей и старт движения.
    func stripLaid(_ rect: CGRect) {
        strip = rect
        guard machine.phase == .cut, rect.width > 0 else { return }
        begin(machine.run)
    }

    private func begin(_ run: Int) {
        guard machine.run == run, machine.phase == .cut, var c = cut else { return }
        if strip.width > 0 { c.targets = PartDayGeometry.dates(strip: strip) }
        cut = c
        let t0 = Self.now
        machine.go(at: t0)
        PartDayLog.note("go run=\(run) strip=\(Self.f(strip))")
        if let at = frozen {
            let fr = PartDayTiming.frame(at: at)
            move = fr.move; halfAlpha = fr.halves; cellAlpha = fr.cells
            machine.tick(at: t0 + min(at, PartDayTiming.end - 0.001), run: run)
            return
        }
        withAnimation(PartDayTiming.moveAnimation) { move = 1 }
        withAnimation(PartDayTiming.halfFadeAnimation) { halfAlpha = 0 }
        withAnimation(PartDayTiming.cellFadeAnimation) { cellAlpha = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(PartDayTiming.stripAt))
            machine.tick(at: max(Self.now, t0 + PartDayTiming.stripAt), run: run)
            try? await Task.sleep(for: .seconds(PartDayTiming.end - PartDayTiming.stripAt))
            machine.tick(at: max(Self.now, t0 + PartDayTiming.end), run: run)
            if machine.run == run, machine.phase == .idle { drop(); PartDayLog.note("done run=\(run)") }
        }
    }

    /// Касание, смена вида или вкладки посреди разреза: сразу конечный кадр.
    func interrupt(_ why: String) {
        guard machine.showsLayer, frozen == nil else { return }
        PartDayLog.note("interrupt \(why) run=\(machine.run) phase=\(machine.phase)")
        finish()
    }

    private func finish() {
        machine.interrupt()
        drop()
    }

    private func drop() {
        cut = nil
        frozen = nil
        #if os(iOS)
        upper = nil; lower = nil
        #endif
    }

    nonisolated static var now: Double { ProcessInfo.processInfo.systemUptime }
    /// Процессорное время главного потока, нс (журнал разреза).
    nonisolated static var cpu: UInt64 { clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) }

    private static func f(_ r: CGRect) -> String {
        String(format: "%.1f,%.1f %.1fx%.1f", r.minX, r.minY, r.width, r.height)
    }

    #if os(iOS)
    private static func window() -> UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
    }
    #endif
}

/// Слой разреза над экраном «Съёмок»: половины-снимки и семь ячеек недели. Касаний не принимает — касание
/// доходит до дня под ним и обрывает разрез (`PartDay.interrupt`).
struct PartDayLayer: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    let part: PartDay

    var body: some View {
        GeometryReader { geo in
            let o = geo.frame(in: .global).origin
            if part.machine.showsLayer, let c = part.cut {
                let (up, down) = PartDayGeometry.halves(row: c.row, screen: c.screen)
                ZStack(alignment: .topLeading) {
                    #if os(iOS)
                    if let v = part.upper {
                        half(v, top: 0, height: c.row.minY, o: o, dy: up, name: "part.up")
                    }
                    if let v = part.lower {
                        half(v, top: c.row.maxY, height: c.screen.maxY - c.row.maxY, o: o, dy: down, name: "part.down")
                    }
                    #endif
                    ForEach(0..<7, id: \.self) { i in cell(c, i, o) }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    #if os(iOS)
    private func half(_ v: UIView, top: CGFloat, height: CGFloat, o: CGPoint, dy: CGFloat, name: String) -> some View {
        SnapView(view: v)
            .frame(width: v.bounds.width, height: height)
            .opacity(part.halfAlpha)
            .offset(x: -o.x, y: top - o.y + dy * part.move)
            .background(alignment: .topLeading) {
                // Узел пары: рамка сдвинутой половины (`.offset` рамку не двигает — ставим `.position`).
                Color.clear.frame(width: v.bounds.width, height: height)
                    .shotNode(name)
                    .position(x: v.bounds.width / 2 - o.x, y: top - o.y + dy * part.move + height / 2)
                    .hidden()
            }
    }
    #endif

    @ViewBuilder
    private func cell(_ c: PartDay.Cut, _ i: Int, _ o: CGPoint) -> some View {
        let from = c.cells[i]
        if let to = c.targets?[i] {
            let fly = PartDayGeometry.fly(from, to)
            let p = part.move
            MonthCell(app: app, f: f, day: c.days[i], part: nil)
                .frame(width: from.width, height: from.height)
                .scaleEffect(x: 1 + (fly.sx - 1) * p, y: 1 + (fly.sy - 1) * p, anchor: .topLeading)
                .opacity(part.cellAlpha)
                .offset(x: from.minX - o.x + fly.dx * p, y: from.minY - o.y + fly.dy * p)
                .background(alignment: .topLeading) {
                    let r = PartDayGeometry.rect(from, fly, at: p)
                    Color.clear.frame(width: r.width, height: r.height)
                        .shotNode("part.c.\(i)")
                        .position(x: r.midX - o.x, y: r.midY - o.y)
                        .hidden()
                }
        } else {
            // Лента дат ещё не разложилась: ячейка стоит на месте, а без цели (веб `!t`) гаснет.
            MonthCell(app: app, f: f, day: c.days[i], part: nil)
                .frame(width: from.width, height: from.height)
                .opacity(part.machine.phase == .cut ? 1 : part.cellAlpha)
                .offset(x: from.minX - o.x, y: from.minY - o.y)
        }
    }
}

#if os(iOS)
/// Снимок экрана (`resizableSnapshotView`) внутри SwiftUI.
private struct SnapView: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView {
        let box = UIView()
        box.isUserInteractionEnabled = false
        box.clipsToBounds = true
        view.frame = CGRect(origin: .zero, size: view.bounds.size)
        box.addSubview(view)
        return box
    }

    func updateUIView(_ box: UIView, context: Context) {
        guard view.superview !== box else { return }
        box.subviews.forEach { $0.removeFromSuperview() }
        view.frame = CGRect(origin: .zero, size: view.bounds.size)
        box.addSubview(view)
    }
}
#endif

/// Журнал разреза (Debug, `-LPPartLog <файл>`): рез, старт, конец, прерывание, строка замера кадров.
enum PartDayLog {
    #if DEBUG
    nonisolated(unsafe) static let url = UserDefaults.standard.string(forKey: "LPPartLog").map { URL(fileURLWithPath: $0) }
    #endif
    static func note(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let url, let data = (String(format: "%.3f ", PartDay.now) + line() + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
        #endif
    }
}

#if DEBUG && os(iOS)
/// Стенд без пальца (`-LPPartBench 1` с `-LPPartLog`): вход в день разрезом трижды тапом месяца и трижды веером,
/// на каждом — замер кадров (`EdgeBackMeter`: интервалы и процессорное время главного потока на кадр). Между
/// входами — назад в месяц без движения. Сначала дата ленты вперёд: направление въезда должно погаснуть.
@MainActor
enum PartDayBench {
    static var on: Bool { UserDefaults.standard.bool(forKey: "LPPartBench") }
    /// `-LPPartBenchOld 1`: тот же стенд, но вход прежний (до 29.2а) — без разреза, `.snappy(0.25)`. Для сравнения кадров.
    static var old: Bool { UserDefaults.standard.bool(forKey: "LPPartBenchOld") }
    /// `-LPPartBenchStill 1`: вход как при «Уменьшении движения» — мгновенно, без разреза.
    static var still: Bool { UserDefaults.standard.bool(forKey: "LPPartBenchStill") }

    static func run(_ app: AppModel, part: PartDay, fan: @escaping () -> Void) async {
        try? await Task.sleep(for: .seconds(4))
        let meter = EdgeBackMeter { PartDayLog.note($0) }
        for k in 0..<6 {
            var t = Transaction()
            t.disablesAnimations = true
            if k == 0 {
                withTransaction(t) { app.planner.setScope(.day) }
                try? await Task.sleep(for: .seconds(1))
                PartDayLog.note("bench strip +1")
                withAnimation(PlannerDayBody.slide) { _ = app.planner.pickInStrip(app.planner.selected.adding(days: 1)) }
                try? await Task.sleep(for: .seconds(1))
                PartDayLog.note("bench shift after strip=\(app.planner.dayShift)")
            }
            withTransaction(t) { app.planner.setScope(.month) }
            try? await Task.sleep(for: .seconds(1.5))
            let way = old ? "old" : k < 3 ? "month" : "fan"
            // Замер — с двух кадров до входа: кадр самого входа должен попасть в счёт.
            meter.start()
            try? await Task.sleep(for: .milliseconds(100))
            PartDayLog.note("bench enter \(way) shift=\(app.planner.dayShift)")
            if old { withAnimation(.snappy(duration: 0.25)) { _ = app.planner.tapMonthCell(app.planner.selected) } }
            else if k < 3 { part.enter(app, still: still) } else { fan() }
            try? await Task.sleep(for: .seconds(0.6))
            meter.stop()
            PartDayLog.note("bench after scope=\(app.planner.scope) shift=\(app.planner.dayShift) phase=\(part.machine.phase)")
            try? await Task.sleep(for: .seconds(1))
        }
        PartDayLog.note("bench done")
    }
}
#endif
