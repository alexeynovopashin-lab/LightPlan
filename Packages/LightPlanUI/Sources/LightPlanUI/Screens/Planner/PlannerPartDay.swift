import SwiftUI
import LightPlanCore
#if os(iOS)
import UIKit
#endif

/// Разрез месяца при входе в день (29.2а; веб `partMonthIntoDay`, `index.html`, аудит C1). Строка выбранной недели
/// остаётся, месяц над ней уезжает вверх, под ней — вниз, семь ячеек недели едут на места дат ленты дня, а под
/// разрезом уже стоит день. Входы: второй тап по выбранному числу месяца и «День» в веере видов (29.2а), тап по
/// числу в ленте года (29.2б; веб зовёт ту же `partMonthIntoDay` с источником `#yearOverlay`).
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
    /// Ячейки строки: семь колонок через `gap` (месяц — `MonthMetrics.colGap`, лента года — без зазора).
    static func cells(row: CGRect, gap: CGFloat = MonthMetrics.colGap) -> [CGRect] {
        let w = (row.width - 6 * gap) / 7
        return (0..<7).map { CGRect(x: row.minX + CGFloat($0) * (w + gap), y: row.minY, width: w, height: row.height) }
    }

    /// Строка ленты года с числом `day` по рамке сетки его месяца (веб `.year-cal-grid`: `repeat(7, 1fr)`, `row-gap: 3px`,
    /// клетка — квадрат). Дни семи колонок; `nil` — пусто: до первого числа и после последнего (хвоста у сетки нет).
    static func yearRow(grid: CGRect, day: CivilDate) -> (row: CGRect, days: [CivilDate?]) {
        let (lead, n) = YearMath.monthShape(year: day.year, month: day.month)
        let i = lead + day.day - 1
        let side = grid.width / 7
        let row = CGRect(x: grid.minX, y: grid.minY + CGFloat(i / 7) * (side + YearLentaView.rowGap), width: grid.width, height: side)
        let days = (0..<7).map { c -> CivilDate? in
            let d = i / 7 * 7 + c - lead + 1
            return (1...n).contains(d) ? CivilDate(year: day.year, month: day.month, day: d) : nil
        }
        return (row, days)
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
/// Движение идёт только к разложенной ленте дат: без неё ячейкам некуда лететь — запасной срок снимает разрез
/// (вход без движения), а не гасит ячейки на месте (ревью GPT к 29.2а).
struct PartDayMachine: Equatable {
    enum Phase: Equatable { case idle, cut, moving, revealed }
    private(set) var phase = Phase.idle
    private(set) var start: Double?
    /// Номер разреза: таймер прерванного разреза новый не трогает.
    private(set) var run = 0
    /// Рамка ленты дат этого разреза есть: лента разложилась после реза или уже стояла на экране (вход из ленты года,
    /// когда под ней день).
    private(set) var laid = false

    var showsLayer: Bool { phase != .idle }
    var stripHidden: Bool { phase == .cut || phase == .moving }

    /// Тап: снимки положены, день под ними. Идущий разрез обрывается.
    @discardableResult
    mutating func cut(stripLive: Bool = false) -> Int {
        phase = .cut
        start = nil
        laid = stripLive
        run += 1
        return run
    }

    /// Рамка ленты дат пришла.
    mutating func lay() {
        if phase != .idle { laid = true }
    }

    /// Пошли (веб: следующий кадр после `commit`) — только к разложенной ленте дат.
    mutating func go(at t: Double) {
        guard phase == .cut, laid else { return }
        phase = .moving
        start = t
    }

    /// Запасной срок вышел, а движения нет. Лента дат есть — `true`, стартуем; нет — разрез снят: вход без движения.
    mutating func late() -> Bool {
        guard phase == .cut else { return false }
        if laid { return true }
        interrupt()
        return false
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
    /// Лента года (29.2б): сетки месяцев и видимая часть прокрутки — от низа шапки ленты до её низа.
    @ObservationIgnored var yearGrids: [CivilDate: CGRect] = [:]
    @ObservationIgnored var yearTop: CGFloat = 0
    @ObservationIgnored var yearBottom: CGFloat = 0

    /// Откуда режем: месяц (второй тап, веер) или лента года (тап по числу) — от этого вид летящей ячейки.
    enum From: Equatable { case month, year }

    struct Cut: Equatable {
        var from: From
        var row: CGRect
        /// Дни семи колонок; `nil` — пустая клетка ленты года.
        var days: [CivilDate?]
        var cells: [CGRect]
        var targets: [CGRect]?
        var screen: CGRect
    }
    private(set) var cut: Cut?
    #if os(iOS)
    @ObservationIgnored private(set) var upper: UIView?
    @ObservationIgnored private(set) var lower: UIView?
    #endif

    /// Вход в день из месяца. Строку недели не нашли или она не целиком на экране, нет окна, «Уменьшение
    /// движения» — вход без разреза.
    func enter(_ app: AppModel, still: Bool, frozenAt: Double? = nil) {
        #if os(iOS)
        let grid = app.planner.monthGrid
        let i = grid.firstIndex(of: app.planner.selected)
        split(app, from: .month, row: i.flatMap { rows[$0 / 7] }, days: i.map { i in grid[(i / 7 * 7)..<(i / 7 * 7 + 7)].map { $0 } } ?? [],
              gap: MonthMetrics.colGap, view: screen, still: still, frozenAt: frozenAt) { app.planner.enterSelectedDay() }
        #else
        withAnimation(.snappy(duration: 0.25)) { app.planner.enterSelectedDay() }
        #endif
    }

    /// Вход в день тапом по числу в ленте года (веб `buildMonthEl` → `partMonthIntoDay(…, #yearOverlay, …)`): строка
    /// этого числа в сетке его месяца, лента закрывается без своего выезда. Строка под шапкой ленты или идёт зум
    /// «Года целиком» — вход без разреза, как прежде.
    func enter(_ app: AppModel, nav: PlannerNav, day: CivilDate, still: Bool, frozenAt: Double? = nil) {
        let commit = {
            nav.lentaOpen = false
            app.planner.enterDay(day)
        }
        #if os(iOS)
        let grid = nav.zoom == nil ? yearGrids[PlannerState.first(of: day)] : nil
        let at = grid.map { PartDayGeometry.yearRow(grid: $0, day: day) }
        let view = CGRect(x: 0, y: yearTop, width: screen.width, height: max(0, min(yearBottom, screen.maxY) - yearTop))
        split(app, from: .year, row: at?.row, days: at?.days ?? [], gap: 0, view: view, still: still, frozenAt: frozenAt, commit: commit)
        #else
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, commit)
        #endif
    }

    #if os(iOS)
    /// Общий рез трёх входов: снимки над и под строкой `row`, семь ячеек, `commit` под ними. `view` — где строка
    /// должна стоять целиком: частично ушедшую под шапку прокруткой ячейки нарисовали бы поверх шапки.
    private func split(_ app: AppModel, from: From, row: CGRect?, days: [CivilDate?], gap: CGFloat, view: CGRect,
                       still: Bool, frozenAt: Double?, commit: @escaping () -> Void) {
        let quiet = {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t, commit)
        }
        guard !still, let row, row.height > 0, days.count == 7, screen.height > 0, let window = Self.window(),
              row.minY >= view.minY, row.maxY <= view.maxY else { finish(); quiet(); return }
        // Под лентой года уже стоит день — его лента дат разложена и после входа не сдвинется, нового отчёта не будет.
        let live = app.planner.scope == .day && strip.width > 0
        if !live { strip = .zero }
        let wb = window.bounds
        let c0 = Self.cpu
        upper = window.resizableSnapshotView(from: CGRect(x: 0, y: 0, width: wb.width, height: max(1, row.minY)),
                                             afterScreenUpdates: false, withCapInsets: .zero)
        lower = window.resizableSnapshotView(from: CGRect(x: 0, y: row.maxY, width: wb.width, height: max(1, screen.maxY - row.maxY)),
                                             afterScreenUpdates: false, withCapInsets: .zero)
        let run = machine.cut(stripLive: live)
        move = 0; halfAlpha = 1; cellAlpha = 1; frozen = frozenAt
        cut = Cut(from: from, row: row, days: days, cells: PartDayGeometry.cells(row: row, gap: gap),
                  targets: nil, screen: CGRect(x: 0, y: 0, width: wb.width, height: screen.maxY))
        let c1 = Self.cpu
        quiet()
        PartDayLog.note(String(format: "cut %@ run=%d row=%@ screen=%@ live=%d cpu snap=%.1f commit=%.1f", "\(from)", run,
                               Self.f(row), Self.f(screen), live ? 1 : 0, Double(c1 &- c0) / 1e6, Double(Self.cpu &- c1) / 1e6))
        if live {
            Task { @MainActor in begin(run, "live") }
        }
        // Запасной срок: лента дат так и не разложилась — разрез снимается, день уже под ним (вход без движения).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard machine.run == run, machine.phase == .cut else { return }
            if machine.late() { begin(run, "fallback") } else { PartDayLog.note("late run=\(run): no strip, still"); drop() }
        }
    }
    #endif

    /// Лента дат дня встала на место — отсюда рамки целей и старт движения.
    func stripLaid(_ rect: CGRect) {
        #if DEBUG && os(iOS)
        // Замедленная раскладка (`-LPPartStripLag <мс>`): рамка ленты дат приходит позже — проверка запасного старта.
        if PartDayBench.stripLag > 0, machine.phase == .cut {
            let run = machine.run
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(PartDayBench.stripLag))
                if machine.run == run { laid(rect) }
            }
            return
        }
        #endif
        laid(rect)
    }

    private func laid(_ rect: CGRect) {
        PartDayLog.note("laid run=\(machine.run) phase=\(machine.phase) strip=\(Self.f(rect))")
        strip = rect
        guard machine.phase == .cut, rect.width > 0 else { return }
        machine.lay()
        begin(machine.run, "laid")
    }

    private func begin(_ run: Int, _ why: String) {
        guard machine.run == run, machine.phase == .cut, machine.laid, strip.width > 0, var c = cut else { return }
        c.targets = PartDayGeometry.dates(strip: strip)
        cut = c
        let t0 = Self.now
        machine.go(at: t0)
        PartDayLog.note("go \(why) run=\(run) strip=\(Self.f(strip))")
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
            face(c, i)
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
            // Лента дат ещё не разложилась (`cut`): ячейка стоит на месте. Без ленты движение не начинается вовсе.
            face(c, i)
                .frame(width: from.width, height: from.height)
                .offset(x: from.minX - o.x, y: from.minY - o.y)
        }
    }

    /// Ячейка своего источника: клетка месяца или число ленты года; пустая клетка ленты — пусто (веб: `span.pad`).
    @ViewBuilder
    private func face(_ c: PartDay.Cut, _ i: Int) -> some View {
        if let day = c.days[i] {
            switch c.from {
            case .month: MonthCell(app: app, f: f, day: day, part: nil)
            case .year: YearDayFace(day: day.day, today: day == f.today)
            }
        } else {
            Color.clear
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
/// Стенд без пальца (`-LPPartBench 1` с `-LPPartLog`): вход в день разрезом трижды тапом месяца, трижды веером и
/// трижды числом ленты года (29.2б; третий — когда под лентой уже день), на каждом — замер кадров (`EdgeBackMeter`:
/// интервалы и процессорное время главного потока на кадр). Между входами — назад в месяц без движения. Первым —
/// холодный вход (день ещё не раскладывался), затем дата ленты вперёд: направление въезда должно погаснуть.
@MainActor
enum PartDayBench {
    static var on: Bool { UserDefaults.standard.bool(forKey: "LPPartBench") }
    /// `-LPPartBenchOld 1`: тот же стенд, но вход прежний (до 29.2а/б) — без разреза: из месяца `.snappy(0.25)`, из ленты мгновенно.
    static var old: Bool { UserDefaults.standard.bool(forKey: "LPPartBenchOld") }
    /// `-LPPartBenchStill 1`: вход как при «Уменьшении движения» — мгновенно, без разреза.
    static var still: Bool { UserDefaults.standard.bool(forKey: "LPPartBenchStill") }
    /// `-LPPartStripLag <мс>`: рамка ленты дат дня доходит до разреза на столько позже.
    static var stripLag: Int { UserDefaults.standard.integer(forKey: "LPPartStripLag") }

    static func run(_ app: AppModel, part: PartDay, nav: PlannerNav, fan: @escaping () -> Void) async {
        try? await Task.sleep(for: .seconds(4))
        let meter = EdgeBackMeter { PartDayLog.note($0) }
        // Холодный вход: день ещё ни разу не раскладывался, рамки ленты дат нет.
        PartDayLog.note("bench enter cold scope=\(app.planner.scope)")
        if app.planner.scope == .month { part.enter(app, still: still) }
        try? await Task.sleep(for: .seconds(1))
        for k in 0..<9 {
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
            withTransaction(t) { app.planner.setScope(k == 8 ? .day : .month) }
            if k >= 6 { withTransaction(t) { nav.openLenta(from: app.planner.month) } }
            try? await Task.sleep(for: .seconds(1.5))
            let way = old ? "old" : k < 3 ? "month" : k < 6 ? "fan" : "year"
            // Замер — с двух кадров до входа: кадр самого входа должен попасть в счёт.
            meter.start()
            try? await Task.sleep(for: .milliseconds(100))
            PartDayLog.note("bench enter \(way) shift=\(app.planner.dayShift)")
            if old, k >= 6 { withAnimation(nil) { nav.lentaOpen = false }; app.planner.enterDay(app.planner.selected) }
            else if old { withAnimation(.snappy(duration: 0.25)) { _ = app.planner.tapMonthCell(app.planner.selected) } }
            else if k < 3 { part.enter(app, still: still) } else if k < 6 { fan() }
            else { part.enter(app, nav: nav, day: app.planner.selected, still: still) }
            try? await Task.sleep(for: .seconds(0.6))
            meter.stop()
            PartDayLog.note("bench after scope=\(app.planner.scope) shift=\(app.planner.dayShift) phase=\(part.machine.phase)")
            try? await Task.sleep(for: .seconds(1))
        }
        PartDayLog.note("bench done")
    }
}
#endif
