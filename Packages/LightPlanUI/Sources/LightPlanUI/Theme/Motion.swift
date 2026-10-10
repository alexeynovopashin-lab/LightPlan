import SwiftUI
import LightPlanCore

/// Малые движения «Съёмок» и оболочки (29.2в; аудит `anim_audit_reference.md` C5, C7, C8, S1 и слово Алексея 07.10
/// «скольжение сбоку»). Числа беты — здесь, чтобы тест держал их без экрана; экраны берут готовое.
enum Motion {
    /// E1 беты: `cubic-bezier(0.25, 1, 0.4, 1)`.
    static func e1(_ seconds: Double) -> Animation { .timingCurve(0.25, 1, 0.4, 1, duration: seconds) }
    /// CSS `ease`: `cubic-bezier(0.25, 0.1, 0.25, 1)`.
    static func ease(_ seconds: Double) -> Animation { .timingCurve(0.25, 0.1, 0.25, 1, duration: seconds) }

    /// Листание месяца и недели сбоку (~0,3 с, как в календаре iPhone; слово Алексея 07.10, кривая E1 как у въезда ленты дня).
    static let flip = e1(0.3)
    /// Сводка дня `.dp-bar`: `max-width` и `padding` 0,45 с E1 (`index.html` 3640–3643).
    static let fold = e1(0.45)
    /// Прозрачность основной части сводки 0,25 с `ease`.
    static let foldFade = ease(0.25)
    /// Поворот шеврона 0,35 с `ease` (`.dp-b-chev`).
    static let foldChevron = ease(0.35)
    /// Рамка и фон ручки 0,3 с `ease` (`.dp-bar` `box-shadow`).
    static let foldFrame = ease(0.3)
    /// `rise` экрана при смене вкладки: 0,45 с E1, сдвиг 8 pt (`.screen.active`, `index.html` 1533–1534).
    static let rise = e1(0.45)
    static let riseShift: CGFloat = 8
}

/// Экран сейчас перед глазами (вкладка выбрана). Спрятанные вкладки живут в дереве всегда: бесконечное
/// движение на них не крутим (дыхание кольца берёт отсюда).
extension EnvironmentValues {
    @Entry var screenShown = true
}

// MARK: - Листание сбоку

/// Дорожка листания: страница — месяц или неделя под целым номером, позиция `pos` между номерами — страницы
/// на ходу. Позицию SwiftUI интерполирует сам (`Animatable`), поэтому направление выходит из самой разницы
/// номеров и не зависит от того, какой переход «запомнил» уходящий вид.
enum FlipTrack {
    struct Sheet: Equatable {
        let index: Int
        /// Сдвиг страницы по x от места покоя, pt.
        let x: CGFloat
        /// Страница, к которой идём (ближайшая к позиции): ей принадлежат рамки узлов и замеры.
        let lead: Bool
    }

    /// Ближе этого к целому — страница стоит.
    static let rest = 0.0005

    /// Страницы на позиции `pos`. На целом номере — одна. Между `n` и `n+1`: `n` едет влево на `f·ширину`,
    /// `n+1` въезжает справа (`pos` растёт — листаем вперёд); при убывании тот же ряд кадров идёт задом наперёд.
    static func sheets(at pos: Double, width: CGFloat) -> [Sheet] {
        let lo = pos.rounded(.down), f = pos - lo
        if f < rest { return [Sheet(index: Int(lo), x: 0, lead: true)] }
        if f > 1 - rest { return [Sheet(index: Int(lo) + 1, x: 0, lead: true)] }
        return [
            Sheet(index: Int(lo), x: -CGFloat(f) * width, lead: f < 0.5),
            Sheet(index: Int(lo) + 1, x: CGFloat(1 - f) * width, lead: f >= 0.5),
        ]
    }

    /// Куда листаем: +1 — вперёд (новая страница справа), −1 — назад, 0 — стоим.
    static func direction(from a: Double, to b: Double) -> Int { b > a ? 1 : b < a ? -1 : 0 }

    /// Прыжок дальше соседней страницы (год, «сегодня» через полгода) не листается — встаёт сразу.
    static func jumps(from a: Double, to b: Double) -> Bool { abs(b - a) > 1.0 + rest }

    /// Высота стойки между двумя страницами: плавно от одной к другой, пока обе известны (месяц на 5 и 6 рядов).
    static func height(at pos: Double, of known: (Int) -> CGFloat?) -> CGFloat? {
        let lo = pos.rounded(.down), f = CGFloat(pos - lo)
        if pos - lo < rest { return nil }
        guard let a = known(Int(lo)), let b = known(Int(lo) + 1) else { return nil }
        return a + (b - a) * f
    }

    // Номера страниц.
    static func monthIndex(_ d: CivilDate) -> Int { d.year * 12 + d.month - 1 }
    static func monthStart(_ index: Int) -> CivilDate {
        let y = index >= 0 ? index / 12 : (index - 11) / 12
        return CivilDate(year: y, month: index - y * 12 + 1, day: 1)
    }
    private static let epochMonday = CivilDate(year: 1970, month: 1, day: 5)
    static func weekIndex(_ d: CivilDate) -> Int {
        let n = PlannerState.weekStart(d).days(since: epochMonday)
        return n >= 0 ? n / 7 : (n - 6) / 7
    }
    static func weekStart(_ index: Int) -> CivilDate { epochMonday.adding(days: index * 7) }
}

/// Стойка листания: держит страницы рядом и подгоняет высоту. Прыжок дальше соседней страницы и «Уменьшение
/// движения» гасят анимацию — страница встаёт сразу.
struct FlipStage<Content: View>: View {
    let pos: Double
    /// Высота страницы, если известна (месяц знает её по числу рядов); без неё стойка берёт высоту большей.
    let height: (Int) -> CGFloat?
    @ViewBuilder let content: (_ index: Int, _ lead: Bool) -> Content
    @Environment(\.accessibilityReduceMotion) private var still
    /// Позиция, которую вид показывал до этого прохода: по разнице видно прыжок.
    @State private var seen: Double
    @State private var width: CGFloat = 0

    init(pos: Double, height: @escaping (Int) -> CGFloat? = { _ in nil },
         @ViewBuilder content: @escaping (_ index: Int, _ lead: Bool) -> Content) {
        self.pos = pos
        self.height = height
        self.content = content
        _seen = State(initialValue: pos)
    }

    var body: some View {
        FlipSheets(pos: pos, width: width, height: height, content: content)
            .transaction { t in
                if still || FlipTrack.jumps(from: seen, to: pos) { t.animation = nil }
            }
            .onChange(of: pos) { _, new in seen = new }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

private struct FlipSheets<Content: View>: View, @preconcurrency Animatable {
    var pos: Double
    let width: CGFloat
    let height: (Int) -> CGFloat?
    let content: (Int, Bool) -> Content
    var animatableData: Double {
        get { pos }
        set { pos = newValue }
    }

    var body: some View {
        let sheets = FlipTrack.sheets(at: pos, width: width)
        let moving = sheets.count > 1
        ZStack(alignment: .top) {
            ForEach(sheets, id: \.index) { s in
                content(s.index, s.lead).offset(x: s.x)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: FlipTrack.height(at: pos, of: height), alignment: .top)
        // Края стойки режут страницы только на ходу: в покое ничего не обрезано (тени, кольца).
        .mask(Rectangle().padding(moving ? 0 : -2000))
    }
}

// MARK: - Дыхание кольца просроченной сдачи (C8)

/// `ringBreath` беты: 3,6 с, `ease-in-out`, прозрачность 1 ↔ 0,55, бесконечно (`index.html` 4432–4433).
enum RingBreath {
    static let period = 3.6
    static let low = 0.55

    /// Прозрачность подложки на секунде `t`: полпериода вниз и полпериода вверх, каждая — `ease-in-out`.
    static func opacity(at t: TimeInterval) -> Double {
        let ph = (t.truncatingRemainder(dividingBy: period) + period).truncatingRemainder(dividingBy: period) / period
        let half = ph < 0.5 ? ph * 2 : (1 - ph) * 2
        return 1 - (1 - low) * easeInOut(half)
    }

    /// `cubic-bezier(0.42, 0, 0.58, 1)`.
    static func easeInOut(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var t = x
        for _ in 0..<20 {
            let e = ((3 * 0.42 - 3 * 0.58 + 1) * t + (3 * 0.58 - 6 * 0.42)) * t * t + 3 * 0.42 * t - x
            let d = 3 * (3 * 0.42 - 3 * 0.58 + 1) * t * t + 2 * (3 * 0.58 - 6 * 0.42) * t + 3 * 0.42
            if abs(e) < 1e-7 || abs(d) < 1e-7 { break }
            t -= e / d
        }
        return (3 * t * t) * (1 - t) + t * t * t
    }
}

/// Подложка числа с просроченной сдачей: дышит, пока вкладка перед глазами и приложение на экране.
/// «Уменьшение движения» — стоит. На спрятанной вкладке цикла нет совсем (`TimelineView` не создаётся).
struct BreathDisc: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var still
    @Environment(\.screenShown) private var shown
    @Environment(\.scenePhase) private var phase

    var body: some View {
        if still || !shown || phase != .active {
            Circle().fill(color)
        } else {
            TimelineView(.animation) { ctx in
                Circle().fill(color).opacity(RingBreath.opacity(at: ctx.date.timeIntervalSinceReferenceDate))
            }
        }
    }
}

// MARK: - Сводка дня: схлопывание (C7)

/// Раскладка панели сводки при `t` от 0 (раскрыта) до 1 (свёрнута): рамка сжимается к правому краю до ручки
/// 40 × 22 и садится на черту (`.dp-bar.shut`: `right: 4`, `translateY(−50%)`), основная часть сжимается вместе с
/// рамкой. Свободное место под панелью уходит в той же кривой.
enum FoldGeometry {
    static let barHeight: CGFloat = 38, shutHeight: CGFloat = 22, gap: CGFloat = 8
    static let chevronWidth: CGFloat = 40, inset: CGFloat = 4, bleed: CGFloat = 20

    struct Frames: Equatable {
        var line, bar, main, chevron: CGRect
        var height: CGFloat
    }

    static func frames(t: Double, width w: CGFloat) -> Frames {
        let t = CGFloat(min(1, max(0, t)))
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        let barW = lerp(w - 2 * inset, chevronWidth), right = w - inset
        let barH = lerp(barHeight, shutHeight)
        let barY = lerp(1 + gap, 0.5 - shutHeight / 2)
        let bar = CGRect(x: right - barW, y: barY, width: barW, height: barH)
        return Frames(
            line: CGRect(x: -bleed, y: 0, width: w + 2 * bleed, height: 1),
            bar: bar,
            main: CGRect(x: bar.minX, y: barY, width: max(0, barW - chevronWidth), height: barH),
            chevron: CGRect(x: right - chevronWidth, y: barY, width: chevronWidth, height: barH),
            height: lerp(1 + gap + barHeight, 1))
    }
}

private struct FoldLayout: Layout {
    var t: Double
    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 0
        return CGSize(width: w, height: FoldGeometry.frames(t: t, width: w).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 4 else { return }
        let f = FoldGeometry.frames(t: t, width: bounds.width)
        // Порядок: черта, рамка, основная часть, шеврон.
        for (view, r) in zip(subviews, [f.line, f.bar, f.main, f.chevron]) {
            view.place(at: CGPoint(x: bounds.minX + r.minX, y: bounds.minY + r.minY), proposal: ProposedViewSize(r.size))
        }
    }
}

/// Панель сводки: четыре части кладутся раскладкой `FoldLayout`, `t` ведёт SwiftUI по кривой переключения.
struct FoldPanel<Line: View, Frame: View, Main: View, Chevron: View>: View, @preconcurrency Animatable {
    var t: Double
    let line: Line, frame: Frame, main: Main, chevron: Chevron
    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    var body: some View {
        FoldLayout(t: t) {
            line
            frame
            main
            chevron
        }
    }
}

// MARK: - Веер видов (C5)

/// `scopeIn` беты: от `scale(0.94) translateY(−6px)` и прозрачности 0 к покою, точка роста `20px −10px` от угла веера
/// (`index.html` 4295, 4306). Масштаб вокруг точки (20, −10) — это масштаб вокруг угла плюс сдвиг `(20, −10)·(1−s)`.
enum ScopeIn {
    static let from: CGFloat = 0.94
    static let lift: CGFloat = -6
    static let origin = CGPoint(x: 20, y: -10)

    struct Pose: Equatable {
        var scale: CGFloat, dx: CGFloat, dy: CGFloat, opacity: Double
    }

    /// Поза на доле пути `p` (0 — начало, 1 — покой). Под «Уменьшением движения» — только прозрачность.
    static func pose(_ p: Double, still: Bool = false) -> Pose {
        let p = min(1, max(0, p))
        if still { return Pose(scale: 1, dx: 0, dy: 0, opacity: p) }
        let s = from + (1 - from) * CGFloat(p)
        return Pose(scale: s, dx: origin.x * (1 - s), dy: origin.y * (1 - s) + lift * CGFloat(1 - p), opacity: p)
    }
}

struct ScopeInModifier: ViewModifier, @preconcurrency Animatable {
    var p: Double
    var still = false
    var animatableData: Double {
        get { p }
        set { p = newValue }
    }

    func body(content: Content) -> some View {
        let q = ScopeIn.pose(p, still: still)
        MotionLog.pose("scopeIn", p)
        return content
            .scaleEffect(q.scale, anchor: .topLeading)
            .offset(x: q.dx, y: q.dy)
            .opacity(q.opacity)
    }
}

extension AnyTransition {
    static func scopeIn(still: Bool) -> AnyTransition {
        .modifier(active: ScopeInModifier(p: 0, still: still), identity: ScopeInModifier(p: 1, still: still))
    }
}

// MARK: - Появление экрана при смене вкладки (S1)

/// `.screen.active { animation: rise 0.45s E1 }`: вкладка, ставшая выбранной, проявляется и поднимается на 8 pt;
/// уходящая гаснет сразу (у беты она `display: none`). «Уменьшение движения» не гасит (аудит S1).
struct TabRise: ViewModifier {
    let shown: Bool
    func body(content: Content) -> some View {
        content
            .modifier(RiseEffect(p: shown ? 1 : 0))
            .animation(shown ? Motion.rise : nil, value: shown)
    }
}

/// Содержимое вкладки под шапкой: проявление и подъём S1 по `screenShown`; шапка стоит на месте и не гаснет.
private struct TabRiseBody: ViewModifier {
    @Environment(\.screenShown) private var shown
    func body(content: Content) -> some View { content.modifier(TabRise(shown: shown)) }
}

extension View {
    func tabRise() -> some View { modifier(TabRiseBody()) }
}

/// Доля пути `p` проявления (0 — спрятана, 1 — на месте): прозрачность `p` и сдвиг вниз `8 · (1 − p)`.
struct RiseEffect: ViewModifier, @preconcurrency Animatable {
    var p: Double
    var animatableData: Double {
        get { p }
        set { p = newValue }
    }

    nonisolated static func pose(_ p: Double) -> (opacity: Double, dy: CGFloat) { (p, Motion.riseShift * CGFloat(1 - p)) }

    func body(content: Content) -> some View {
        let q = Self.pose(p)
        MotionLog.pose("rise", p)
        return content.opacity(q.opacity).offset(y: q.dy)
    }
}

/// Журнал стенда: доля пути на каждом кадре, как её отдал SwiftUI (`-LPMotionBench`, Debug). Вне стенда — ничего.
@MainActor
enum MotionLog {
    static func pose(_ name: String, _ p: Double) {
        #if DEBUG && os(iOS)
        if MotionBench.on { PartDayLog.note("pose \(name) \(p)") }
        #endif
    }
}
