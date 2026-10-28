import SwiftUI
import LightPlanDomain

/// Экран активности (30б.3): плитка дня карточки без числа слева — строка состояния, диапазон времени, горизонтальная лента точек
/// (знак над точкой, время и слово под ней), растянутая на ширину плашки. Студия — та же лента плюс выход из зала и кнопки.
///
/// Вид берёт один `ActivityFrame` (Domain): расширение и тест рисуют одним кодом. Само идёт только то, что умеет система без
/// обновлений: `Text(timerInterval:)` и `ProgressView(timerInterval:)` — часы «до следующей точки» и полоса между точками;
/// подсветка точки и строка состояния обновляются, когда приложение открыто. Палитра — тёмная всегда (плитка карточки тёмная,
/// подложку плашки красит расширение), шрифты — свои размеры: плашка ограничена по высоте (около 160 pt по документации),
/// Dynamic Type её бы выдавил.
enum ActivityMetrics {
    /// Поля плашки.
    static let side: CGFloat = 16, vertical: CGFloat = 12
    /// Лента: знак в клетке 26, дорожка 14, время 11, слово 9.5 — как `CardLane` карточки.
    static let sign: CGFloat = 26, rail: CGFloat = 14
    static let lane: CGFloat = 26 + 14 + 6 + 13 + 2 + 12
    /// Края ленты прижаты: точка и дорожка — в 13 pt от края плитки (как на карточке).
    static let edge: CGFloat = 13
    static let button: CGFloat = 30
}

/// Часы до `to`, идущие сами. Один `now` на сборку, и цель проверяется: прошедшая — перевёрнутый диапазон, а он валит расширение
/// при следующей перерисовке (разбор GPT спайка 30б).
struct ActivityTimer: View {
    let to: Date
    var body: some View {
        let now = Date()
        if to > now {
            Text(timerInterval: now...to, countsDown: true, showsHours: to.timeIntervalSince(now) >= 3600).monospacedDigit()
        } else {
            Text("0:00").monospacedDigit()
        }
    }
}

/// Стоп-кадр для картинок и тестов: системная полоса (`ProgressView(timerInterval:)`) в `ImageRenderer` не рисуется, поэтому там, где
/// задан момент, полоса — обычная ёмкость на этот момент. В расширении значения нет, и полоса настоящая.
private struct ActivityStillKey: EnvironmentKey { static let defaultValue: Date? = nil }
extension EnvironmentValues {
    var activityStill: Date? {
        get { self[ActivityStillKey.self] }
        set { self[ActivityStillKey.self] = newValue }
    }
}

/// Лента точек: клетки поровну, концы прижаты к краям; между точками — полоса, которая заполняется сама по времени.
struct ActivityLane: View {
    let frame: ActivityFrame
    let st: WidgetStyle
    /// Слова под точками; без них лента ниже на 14 pt (студия в стиле `compact`).
    var words = true
    @Environment(\.activityStill) private var still

    static let green = Color(red: 0xA8 / 255, green: 0xB4 / 255, blue: 0x9B / 255)

    /// Центры точек по ширине `width`: концы — в `edge` от края, остальные поровну между ними.
    static func xs(count n: Int, width: CGFloat) -> [CGFloat] {
        guard n > 0 else { return [] }
        guard n > 1 else { return [width / 2] }
        let step = (width - 2 * ActivityMetrics.edge) / CGFloat(n - 1)
        return (0..<n).map { ActivityMetrics.edge + CGFloat($0) * step }
    }

    var body: some View {
        GeometryReader { g in
            let n = frame.points.count
            let xs = Self.xs(count: n, width: g.size.width)
            // Подписи делят клетку точки; тесная лента показывает время через одну / через две точки.
            let cell = n > 1 ? (g.size.width - 2 * ActivityMetrics.edge) / CGFloat(n - 1) : 80
            let every = cell >= 34 ? 1 : cell >= 22 ? 2 : 3
            ZStack(alignment: .topLeading) {
                ForEach(0..<max(0, n - 1), id: \.self) { i in
                    segment(i).frame(width: max(1, xs[i + 1] - xs[i]))
                        .position(x: (xs[i] + xs[i + 1]) / 2, y: ActivityMetrics.sign + ActivityMetrics.rail / 2)
                }
                ForEach(0..<n, id: \.self) { i in
                    column(i, x: xs[i], cell: cell, width: g.size.width, labels: i % every == 0)
                }
            }
        }
        .frame(height: words ? ActivityMetrics.lane : ActivityMetrics.lane - 14)
    }

    private func isPast(_ i: Int) -> Bool { !frame.points[i].gold && i < frame.current || (frame.points[i].gold && frame.points[i].at <= frame.asOf) }

    /// Полоса между точками `i` и `i+1`: системная, идёт сама от времени первой до времени второй (`ProgressView(timerInterval:)`).
    @ViewBuilder private func segment(_ i: Int) -> some View {
        let a = frame.points[i].date, b = frame.points[i + 1].date
        if let still {
            let f = b > a ? min(1, max(0, still.timeIntervalSince(a) / b.timeIntervalSince(a))) : (b <= still ? 1 : 0)
            Capsule().fill(st.ink.opacity(0.18)).frame(height: 4)
                .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(st.amber).frame(width: g.size.width * f) } }
        } else if b > a {
            ProgressView(timerInterval: a...b, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear).tint(st.amber)
        } else {
            // Две точки в одну минуту: полосе нечего заполнять — стоит полной, если час наступил.
            Capsule().fill(b <= Date() ? st.amber : st.ink.opacity(0.18)).frame(height: 4)
        }
    }

    private func column(_ i: Int, x: CGFloat, cell: CGFloat, width: CGFloat, labels: Bool) -> some View {
        let p = frame.points[i]
        let now = i == frame.current
        let past = !now && isPast(i)
        let w = min(max(cell, 30), 76)
        return ZStack {
            Group {
                if p.gold { WidgetIcon(name: "golden", size: 20, line: 1.4) } else { WidgetIcon(name: p.sign, size: 20, line: 1.4) }
            }
            .foregroundStyle(now ? st.ink : past || p.gold ? st.amber : st.ink.opacity(0.5))
            .frame(width: ActivityMetrics.sign, height: ActivityMetrics.sign)
            .overlay(Circle().strokeBorder(now ? Self.green : .clear, lineWidth: 1.4))
            .position(x: x, y: ActivityMetrics.sign / 2)

            Circle().fill(now ? Self.green : past ? st.amber : st.ink.opacity(0.28))
                .frame(width: 8, height: 8)
                .position(x: x, y: ActivityMetrics.sign + ActivityMetrics.rail / 2)

            if labels {
                VStack(spacing: 2) {
                    Text(p.time).font(.system(size: 11)).monospacedDigit().lineLimit(1)
                        .foregroundStyle(now ? st.ink : p.gold ? st.amber : st.ink2)
                    if words {
                        Text(p.word).font(.system(size: 9.5)).lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(st.ink.opacity(0.5))
                    }
                }
                .frame(width: w)
                .position(x: min(max(x, w / 2), width - w / 2), y: ActivityMetrics.sign + ActivityMetrics.rail + 6 + (words ? 14 : 7))
            }
        }
    }
}

/// Плашка экрана блокировки.
struct ActivityLockView: View {
    let frame: ActivityFrame
    private let st = WidgetStyle(dark: true)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            top
            if hasSecond { second.padding(.top, 2) }
            if !frame.points.isEmpty { ActivityLane(frame: frame, st: st, words: !compact).padding(.top, 8) }
            if inStudio, frame.call != nil || frame.playlist != nil { buttons.padding(.top, 8) }
        }
        .padding(.horizontal, ActivityMetrics.side)
        .padding(.vertical, ActivityMetrics.vertical)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inStudio: Bool { frame.mode == .studio }
    /// Студия (слово Алексея 28.10, «кнопки с подписями»): с лентой, часами выхода и подписанными кнопками плашка 181 pt — выше потолка в 160 pt
    /// (по документации), поэтому лента без слов под точками, а второй строки (диапазон, студия) нет: подпись часов стоит перед ними.
    private var compact: Bool { inStudio }
    private var hasSecond: Bool { !compact }

    /// Состояние слева, главные часы справа: в ленте — до следующей точки, в студии — до выхода из зала.
    private var top: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 7) {
                if !isDone {
                    Circle().fill(ActivityLane.green).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                }
                Text(frame.status).font(.system(size: 15)).foregroundStyle(st.ink).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if compact, let exit = frame.exit {
                // Без второй строки подпись часов стоит перед ними.
                Text(exit.label).font(.system(size: 12.5)).foregroundStyle(st.ink2).lineLimit(1).minimumScaleFactor(0.7)
                ActivityTimer(to: exit.date).font(.system(size: 15, weight: .semibold)).foregroundStyle(st.amber)
                    .frame(width: 70, alignment: .trailing)
            } else if let main {
                ActivityTimer(to: main.date).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(inStudio ? st.amber : st.ink)
                    .frame(width: 84, alignment: .trailing)
            }
        }
    }

    private var isDone: Bool { frame.endsAt.map { $0 <= frame.asOf } ?? false }
    private var main: ActivityFrame.Countdown? { inStudio ? frame.exit : frame.next }

    /// Вторая строка (только в ленте). Слева диапазон времени (а у съёмки со студией — выход из зала, часы аренды стоят на ленте с самого
    /// начала), справа подпись главных часов («до Прогулка»).
    private var second: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let exit = frame.exit {
                HStack(spacing: 6) {
                    Text(exit.label).font(.system(size: 12.5)).foregroundStyle(st.ink2).lineLimit(1).minimumScaleFactor(0.7)
                    ActivityTimer(to: exit.date).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(st.amber)
                        .frame(width: 60, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(frame.range).font(.system(size: 12.5)).foregroundStyle(st.ink2).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let main {
                Text(main.label).font(.system(size: 12.5)).foregroundStyle(st.ink2).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if let call = frame.call { button(call, "phone.fill", .admin) }
            if let list = frame.playlist { button(list, "music.note", .playlist) }
        }
    }

    private func button(_ title: String, _ icon: String, _ link: ActivityLink) -> some View {
        Link(destination: link.url) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(st.ink).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: ActivityMetrics.button)
                .background(Capsule().fill(st.ink.opacity(0.14)))
        }
    }
}

// MARK: - Dynamic Island

/// Значок точки для острова: знак последней начатой (или первой), иначе камера.
struct ActivityGlyph: View {
    let frame: ActivityFrame
    var size: CGFloat = 16
    var body: some View {
        let i = frame.current >= 0 ? frame.current : 0
        let sign = frame.points.indices.contains(i) ? (frame.points[i].gold ? "golden" : frame.points[i].sign) : "camera"
        WidgetIcon(name: sign, size: size, line: 1.5)
    }
}

/// Свёрнутый остров, правая часть: часы (до следующей точки / до золотого часа за час до него).
struct ActivityIslandTimer: View {
    let frame: ActivityFrame
    var body: some View {
        if let t = frame.island {
            ActivityTimer(to: t.date).font(.system(size: 13, weight: .semibold)).minimumScaleFactor(0.7).lineLimit(1)
                .frame(maxWidth: 58, alignment: .trailing)
        } else {
            Text("·")
        }
    }
}

/// Раскрытый остров, низ: лента на ширину острова и, в студии, кнопки.
struct ActivityIslandBottom: View {
    let frame: ActivityFrame
    private let st = WidgetStyle(dark: true)
    var body: some View {
        VStack(spacing: 8) {
            if !frame.points.isEmpty { ActivityLane(frame: frame, st: st) }
            if frame.mode == .studio {
                HStack(spacing: 8) {
                    if let call = frame.call { link(call, "phone.fill", .admin) }
                    if let list = frame.playlist { link(list, "music.note", .playlist) }
                }
            }
        }
    }

    private func link(_ title: String, _ icon: String, _ l: ActivityLink) -> some View {
        Link(destination: l.url) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: ActivityMetrics.button)
                .background(Capsule().fill(st.ink.opacity(0.14)))
        }
    }
}
