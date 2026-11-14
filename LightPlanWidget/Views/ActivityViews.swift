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
    /// Поля плашки (эскиз 14.11: 12 / 10, ужато на 2 ради ≈ 120 pt).
    static let side: CGFloat = 16, top: CGFloat = 10, bottom: CGFloat = 8
    /// Лента — кружки со знаком на линии, как на эскизе: кружок 28, время 11 под ним, слово 11.
    static let ring: CGFloat = 28
    static let lane: CGFloat = 28 + 3 + 12 + 12
    /// Края ленты прижаты: центр крайнего кружка — в 14 pt (полкружка) от края плитки.
    static let edge: CGFloat = 14
    static let button: CGFloat = 30
    /// Подложка плашки (эскиз 14.11): #2E2A26, прозрачность 0,90 — было #0F0E0C / 0,92.
    static let tint = Color(red: 0x2E / 255, green: 0x2A / 255, blue: 0x26 / 255).opacity(0.90)
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

/// Лента окна из четырёх точек (эскиз 14.11): кружок со знаком на линии, время и слово под ним целиком, без «через одну». Прошедшая точка
/// одна и бледная, «сейчас» залита латунью, за окном — пунктирный кружок «+N» и слово «ещё». Между кружками линия, что заполняется сама
/// по времени (`ProgressView(timerInterval:)`). Концы прижаты к краям, остальные поровну.
struct ActivityLane: View {
    let frame: ActivityFrame
    let st: WidgetStyle
    /// Слова под кружками; без них лента ниже на 13 pt (студия в стиле `compact`).
    var words = true
    @Environment(\.activityStill) private var still

    static let green = Color(red: 0xA8 / 255, green: 0xB4 / 255, blue: 0x9B / 255)

    /// Центры колонок по ширине `width`: концы — в `edge` от края, остальные поровну между ними.
    static func xs(count n: Int, width: CGFloat) -> [CGFloat] {
        guard n > 0 else { return [] }
        guard n > 1 else { return [width / 2] }
        let step = (width - 2 * ActivityMetrics.edge) / CGFloat(n - 1)
        return (0..<n).map { ActivityMetrics.edge + CGFloat($0) * step }
    }

    var body: some View {
        let win = frame.laneWindow
        let ids = Array(win.range)
        let n = ids.count + (win.more > 0 ? 1 : 0)
        GeometryReader { g in
            let xs = Self.xs(count: n, width: g.size.width)
            let cell = n > 1 ? (g.size.width - 2 * ActivityMetrics.edge) / CGFloat(n - 1) : 80
            ZStack(alignment: .topLeading) {
                ForEach(0..<max(0, ids.count - 1), id: \.self) { k in
                    segment(ids[k]).frame(width: max(1, xs[k + 1] - xs[k]))
                        .position(x: (xs[k] + xs[k + 1]) / 2, y: ActivityMetrics.ring / 2)
                }
                if win.more > 0, !ids.isEmpty {
                    // Хвост к «+N»: тусклая линия, времени там нет.
                    Capsule().fill(st.ink.opacity(0.18)).frame(width: max(1, xs[ids.count] - xs[ids.count - 1]), height: 4)
                        .position(x: (xs[ids.count - 1] + xs[ids.count]) / 2, y: ActivityMetrics.ring / 2)
                }
                ForEach(0..<ids.count, id: \.self) { k in
                    column(ids[k], x: xs[k], cell: cell, width: g.size.width)
                }
                if win.more > 0 { moreColumn(win.more, x: xs[ids.count], cell: cell, width: g.size.width) }
            }
        }
        .frame(height: words ? ActivityMetrics.lane : ActivityMetrics.lane - 12)
    }

    private func isPast(_ i: Int) -> Bool { !frame.points[i].gold && i < frame.current || (frame.points[i].gold && frame.points[i].at <= frame.asOf) }

    /// Линия между точками `i` и `i+1`: системная, идёт сама от времени первой до времени второй (`ProgressView(timerInterval:)`).
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

    /// Подпись колонки: время и слово, середина — на `x`, но не за край плашки.
    private func label(_ time: String, _ word: String, x: CGFloat, cell: CGFloat, width: CGFloat, timeColor: Color, wordColor: Color, bold: Bool = false) -> some View {
        let w = min(max(cell, 30), 80)
        return VStack(spacing: 0) {
            Text(time).font(.system(size: 11)).monospacedDigit().lineLimit(1).foregroundStyle(timeColor).frame(height: 12)
            if words {
                Text(word).font(.system(size: 11, weight: bold ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(wordColor).frame(height: 12)
            }
        }
        .frame(width: w)
        .position(x: min(max(x, w / 2), width - w / 2), y: ActivityMetrics.ring + 3 + (words ? 12 : 6))
    }

    private func column(_ i: Int, x: CGFloat, cell: CGFloat, width: CGFloat) -> some View {
        let p = frame.points[i]
        let now = i == frame.current
        let past = !now && isPast(i)
        // Прошедшая бледнее всех (эскиз: .38 кружка, .45 подписей).
        let fade: Double = past ? 0.4 : 1
        return ZStack {
            ZStack {
                Circle().fill(now ? st.amber : st.surfaceOnPlate)
                Circle().strokeBorder(st.amber, lineWidth: 1.5)
                Group {
                    if p.gold { WidgetIcon(name: "golden", size: 17, line: 1.4) } else { WidgetIcon(name: p.sign, size: 17, line: 1.4) }
                }
                .foregroundStyle(now ? st.surfaceOnPlate : st.amber)
            }
            .frame(width: ActivityMetrics.ring, height: ActivityMetrics.ring)
            .opacity(fade)
            .position(x: x, y: ActivityMetrics.ring / 2)

            label(p.time, p.word, x: x, cell: cell, width: width,
                  timeColor: (now ? st.ink : st.ink2).opacity(past ? 0.45 : 1), wordColor: st.ink.opacity(past ? 0.45 : 1), bold: now)
        }
    }

    /// Хвост окна: пунктирный кружок «+N» и слово «и ещё».
    private func moreColumn(_ n: Int, x: CGFloat, cell: CGFloat, width: CGFloat) -> some View {
        ZStack {
            Circle().strokeBorder(st.ink.opacity(0.36), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .overlay(Text("+\(n)").font(.system(size: 11)).monospacedDigit().foregroundStyle(st.ink2).minimumScaleFactor(0.7).lineLimit(1))
                .frame(width: ActivityMetrics.ring, height: ActivityMetrics.ring)
                .position(x: x, y: ActivityMetrics.ring / 2)
            label(" ", frame.moreWord ?? "и ещё", x: x, cell: cell, width: width, timeColor: .clear, wordColor: st.ink2)
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
            if hasSecond { second.padding(.top, 1) }
            if !frame.points.isEmpty { ActivityLane(frame: frame, st: st, words: !compact).padding(.top, 8) }
            if inStudio, frame.call != nil || frame.playlist != nil { buttons.padding(.top, 8) }
        }
        .padding(.horizontal, ActivityMetrics.side)
        .padding(.top, ActivityMetrics.top)
        .padding(.bottom, ActivityMetrics.bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Highlight() }
    }

    /// Тонкий верхний блик плашки (эскиз 14.11: `inset 0 1px 0 rgba(255,255,255,.10)`): край гаснет к углам, чтобы не торчать из скругления.
    private struct Highlight: View {
        var body: some View {
            LinearGradient(stops: [.init(color: .white.opacity(0), location: 0), .init(color: .white.opacity(0.10), location: 0.08),
                                   .init(color: .white.opacity(0.10), location: 0.92), .init(color: .white.opacity(0), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
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
                ActivityTimer(to: main.date).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(inStudio ? st.amber : st.ink)
                    .frame(width: 84, alignment: .trailing)
            }
        }
    }

    private var isDone: Bool { frame.endsAt.map { $0 <= frame.asOf } ?? false }
    private var main: ActivityFrame.Countdown? { inStudio ? frame.exit : frame.next }

    /// Вторая строка (только в ленте). Слева диапазон времени (а у съёмки со студией — выход из зала, часы аренды стоят на ленте с самого
    /// начала), справа подпись главных часов («Далее: Прогулка»).
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

/// Свёрнутый остров, правая часть: часы до следующей точки (за час до золотого часа — до него), на последней точке — до конца съёмки.
/// Пустой она не бывает (`ActivityFrame.islandTimer`): без конца съёмки часы идут вверх от начала, у законченной — галочка.
struct ActivityIslandTimer: View {
    let frame: ActivityFrame
    var body: some View {
        Group {
            switch frame.islandTimer {
            case .down(let t):
                ActivityTimer(to: t.date)
            case .up(let since):
                // Конца нет: считаем, сколько уже идёт. Системные часы вверх — диапазон «от начала», хвост с запасом на неделю.
                Text(timerInterval: since...since.addingTimeInterval(7 * 86_400), pauseTime: nil, countsDown: false, showsHours: true).monospacedDigit()
            case .done:
                Text("✓")
            }
        }
        .font(.system(size: 13, weight: .semibold)).minimumScaleFactor(0.7).lineLimit(1)
        .frame(maxWidth: 58, alignment: .trailing)
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
