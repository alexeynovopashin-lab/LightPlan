import SwiftUI
import LightPlanCore
import LightPlanDomain

// 30и.14 — два вида большого виджета, пока съёмка идёт (третий, «съёмка не идёт», — `LargeIdleView`). Эскиз: `docs/30i13_big_widget.html` § 9.

// MARK: - Шапка: знак жанра, имена, окошко Braun «осталось»

/// Шапка идущей съёмки: знак жанра и имена слева, справа окошко Braun с красным флажком — сколько осталось до конца съёмки (то же окошко и тот же
/// живой таймер, что у среднего Braun: `BraunNotchWindow`, `BraunWindowTimer`). Высота 18, как окошко.
struct LargeShootHeader: View {
    let plan: DayPlan
    let pal: BraunPalette
    let width: CGFloat

    /// Окошко: ширина по «00:00:00», чтобы рамка не прыгала (как у среднего: `BraunLayout`).
    static var windowWidth: CGFloat { CGFloat(BraunText.width(BraunLayout.windowText, size: 13, semibold: true, mono: true) + 2 + 12 + BraunWindow.notchExtra) }

    private var names: String {
        let named = (plan.shoot.names ?? "").trimmingCharacters(in: .whitespaces)
        return named.isEmpty ? plan.shoot.title : named
    }

    var body: some View {
        let window = Self.windowWidth
        ZStack(alignment: .topLeading) {
            HStack(spacing: 6) {
                WidgetIcon(name: plan.shoot.genre, size: 16, line: 1.5, genre: true).foregroundStyle(pal.text).frame(width: 16, height: 16)
                Text(names).font(.system(size: 15, weight: .semibold)).tracking(-0.1).foregroundStyle(pal.text).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: width - window - 10, height: 18, alignment: .leading)
            BraunNotchWindow(pal: pal).frame(width: window, height: 18).offset(x: width - window)
            BraunWindowTimer(end: plan.shoot.endDate, now: plan.frame.now, pal: pal)
                .frame(width: window - BraunWindow.notchExtra, height: 18).offset(x: width - window + BraunWindow.notchExtra)
        }
        .frame(width: width, height: 18, alignment: .topLeading)
    }
}

// MARK: - Фотосессия: съёмка идёт, маршрута нет

/// Идёт съёмка без маршрута: шапка с окошком, купол «Света» чуть меньше (90 %: место нужно блоку), ножки с оценкой, а под ними блок Braun —
/// кольцо на всю съёмку («1 ч 12 мин · до конца съёмки», как у среднего Б) и следующие съёмки справа; других съёмок нет — сводка этой.
struct LargePhotoView: View {
    let plan: DayPlan
    let alpha: Bool
    let pal: BraunPalette
    let st: WidgetStyle
    let size: CGSize
    static let pad: CGFloat = 16
    static let domeScale: CGFloat = 0.9

    private var iw: CGFloat { size.width - 2 * Self.pad }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LargeShootHeader(plan: plan, pal: pal, width: iw)
            Spacer().frame(height: 4)
            LargeDome(frame: plan.frame, pal: pal, st: st, iw: iw, scale: Self.domeScale)
                // Метка тестовой сборки — в пустом верхнем углу под шапкой (справа сверху стоит окошко, внизу — ножки).
                .overlay(alignment: .topTrailing) { if alpha { AlphaBadge() } }
            Spacer().frame(height: 2)
            LargeFeet(frame: plan.frame, pal: pal, iw: iw, inset: 18 * iw / DomeFit.canvasWidth).frame(height: 38)
            Spacer().frame(height: 8)
            PhotoBlock(plan: plan, pal: pal).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(Self.pad)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// Нижний блок фотосессии: слева кольцо (60 точек, горят `round(60 × осталось / вся съёмка)`, как у среднего Б), справа — что дальше.
struct PhotoBlock: View {
    let plan: DayPlan
    let pal: BraunPalette

    /// Следующие съёмки недели без идущей; ближайшая из них — на подложке, как у блока «съёмки есть».
    private var others: [(BraunIdle.WeekRow, WidgetFrame.ShootFrame)] {
        let rows = BraunIdle.weekRows(plan.frame)
        return Array(rows.enumerated().compactMap { i, r -> (BraunIdle.WeekRow, WidgetFrame.ShootFrame)? in
            guard r.id != plan.shoot.id, i < plan.frame.week.count else { return nil }
            return (r, plan.frame.week[i])
        }.enumerated().map { j, pair in
            var row = pair.0
            row.near = j == 0
            return (row, pair.1)
        })
    }

    var body: some View {
        GeometryReader { g in
            let inner = g.size.height - 16
            let dia = min(inner, 104)
            let n = max(1, min(2, Int(inner / 34)))
            let rh = min(40, inner / CGFloat(n))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.dial)
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(pal.dialEdge, lineWidth: 0.5)
                HStack(alignment: .center, spacing: 14) {
                    dial(diameter: dia)
                    VStack(alignment: .leading, spacing: 0) {
                        let list = others
                        if list.isEmpty {
                            summary
                        } else {
                            let block = CountdownBlock(frame: plan.frame, pal: pal)
                            ForEach(Array(list.prefix(n).enumerated()), id: \.offset) { _, pair in
                                block.shootRow(pair.0, pair.1, height: rh)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .frame(width: g.size.width, height: g.size.height)
            }
        }
    }

    /// Других съёмок на неделе нет: справа сводка этой — часы и название.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(plan.shootRange).font(.system(size: 17, weight: .semibold)).monospacedDigit().foregroundStyle(pal.text).lineLimit(1)
            Text(plan.title).font(.system(size: 13)).foregroundStyle(pal.muted).lineLimit(2)
        }
        .padding(.horizontal, 8)
    }

    private func dial(diameter d: CGFloat) -> some View {
        let total = plan.shoot.endDate.timeIntervalSince(plan.shoot.startDate)
        let lit = BraunIdle.wholeShootLit(left: plan.shootLeft, total: total)
        let minutes = Int((plan.shootLeft / 60).rounded(.up))
        let parts = BraunDial.countdown(minutes: minutes)
        let sizes = BraunIdle.countdownSizes(diameter: Double(d), parts: parts)
        return ZStack {
            BraunDotLayer(diameter: Double(d), minutes: lit, lit: false).fill(pal.dotOff)
            BraunDotLayer(diameter: Double(d), minutes: lit, lit: true).fill(pal.dot)
            VStack(spacing: 1) {
                WidgetIcon(name: plan.shoot.genre, size: 20, line: 1.5, genre: true).foregroundStyle(pal.amber).frame(width: 20, height: 20)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    ForEach(parts.indices, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(parts[i].value)").font(.system(size: sizes.number, weight: .semibold)).monospacedDigit().tracking(-0.3)
                                .foregroundStyle(minutes == 0 ? pal.muted : pal.text)
                            Text(plan.words[parts[i].unit == .hour ? .hourShort : .minShort]).font(.system(size: sizes.unit, weight: .medium)).foregroundStyle(pal.muted)
                        }
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                Text(plan.untilShoot).font(.system(size: 9)).foregroundStyle(pal.muted).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
            }
            .frame(width: CGFloat(2 * BraunDial.dotRadius(diameter: Double(d))) - 4)
        }
        .frame(width: d, height: d)
    }
}

// MARK: - Свадьба с маршрутом: таймлайн и риски-таймер

/// Идёт съёмка с маршрутом: шапка с окошком, строка «12:00–00:30 · 6 точек», блок — часы текущей точки и таймлайн точек из прежнего большого
/// (золотая рельса, прошедшие тусклые, текущая на подложке со сроком), щель и ножки со светом. Купола нет: его место занял маршрут.
/// **Риски по краю плашки — таймер всей съёмки**, тот же, что у среднего Braun (`BraunTicksView`).
struct LargeRouteView: View {
    let plan: DayPlan
    let alpha: Bool
    let pal: BraunPalette
    let st: WidgetStyle
    let size: CGSize
    static let pad: CGFloat = 16

    private var iw: CGFloat { size.width - 2 * Self.pad }

    /// Сколько строк маршрута помещается в блок: не больше шести и не меньше 34 pt на строку. От размера текста не зависит: шрифты заданы в pt,
    /// плашка не растёт и не обрезается (прежний большой считал строки по Dynamic Type — 6 / 5 / 4).
    static func rows(blockHeight h: CGFloat) -> Int { max(1, min(6, Int((h - 8) / 34))) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            BraunTicksView(shoot: plan.shoot, now: plan.frame.now, zone: plan.zone, size: size,
                           radius: BraunPlate.cornerRadius(plateHeight: Double(size.height)), pal: pal)
            VStack(alignment: .leading, spacing: 0) {
                LargeShootHeader(plan: plan, pal: pal, width: iw)
                HStack(alignment: .center) {
                    Text("\(plan.shootRange) · \(plan.stops.count) \(plan.words[.points])")
                        .font(.system(size: 12)).foregroundStyle(pal.muted).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if alpha { AlphaBadge() }
                }
                .frame(height: 18)
                Spacer().frame(height: 8)
                RouteBlock(plan: plan, pal: pal, width: iw, rows: { Self.rows(blockHeight: $0) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Spacer().frame(height: 8)
                Rectangle().fill(pal.text.opacity(0.12)).frame(height: 1)
                Spacer().frame(height: 8)
                LargeFeet(frame: plan.frame, pal: pal, iw: iw, inset: 0).frame(height: 38)
            }
            .padding(Self.pad)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// Блок маршрута: слева часы текущей точки (60 точек, горят оставшиеся минуты — правило А среднего Braun), справа точки на золотой рельсе.
struct RouteBlock: View {
    let plan: DayPlan
    let pal: BraunPalette
    let width: CGFloat
    let rows: (CGFloat) -> Int

    var body: some View {
        GeometryReader { g in
            let d = min(92, (width * 0.26).rounded(.down))
            let n = rows(g.size.height)
            let window = BigWidget.routeWindow(count: plan.stops.count, current: plan.currentIndex, rows: n)
            let hidden = plan.stops.count - window.upperBound
            let more: CGFloat = hidden > 0 ? 16 : 0
            // Не выше 44: у короткого маршрута (3 точки) строки не растягиваются на весь блок, а стоят сверху, как рельса.
            let rh = min(44, (g.size.height - 8 - more) / CGFloat(max(1, window.count)))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.dial)
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(pal.dialEdge, lineWidth: 0.5)
                HStack(alignment: .top, spacing: 10) {
                    dial(diameter: d).padding(.top, 8)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(window), id: \.self) { i in
                            RouteRow(plan: plan, index: i, first: i == window.lowerBound && window.lowerBound == 0,
                                     last: i == window.upperBound - 1 && hidden == 0, pal: pal, height: rh,
                                     width: width - 16 - d - 10)
                        }
                        if hidden > 0 {
                            Text(plan.words[.more].replacingOccurrences(of: "{n}", with: "\(hidden)"))
                                .font(.system(size: 11)).foregroundStyle(pal.muted).padding(.leading, 28).frame(height: more, alignment: .center)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 8)
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            }
        }
    }

    /// Часы того, что считает `DayPlan.dialLeft`: текущей точки; ждут первую, если она начнётся до конца съёмки; иначе считают всю съёмку (знак жанра).
    private func dial(diameter d: CGFloat) -> some View {
        let minutes = Int((plan.dialLeft / 60).rounded(.up))
        let parts = BraunDial.countdown(minutes: minutes)
        return ZStack {
            BraunDotLayer(diameter: Double(d), minutes: minutes, lit: false).fill(pal.dotOff)
            BraunDotLayer(diameter: Double(d), minutes: minutes, lit: true).fill(pal.dot)
            VStack(spacing: 1) {
                WidgetIcon(name: plan.dialSign, size: 18, line: 1.5, genre: plan.dialSignIsGenre).foregroundStyle(pal.amber).frame(width: 18, height: 18)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    ForEach(parts.indices, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(parts[i].value)").font(.system(size: BraunDial.numberSize(diameter: Double(d)), weight: .semibold)).monospacedDigit().tracking(-0.3)
                                .foregroundStyle(minutes == 0 ? pal.muted : pal.text)
                            Text(plan.words[parts[i].unit == .hour ? .hourShort : .minShort])
                                .font(.system(size: BraunDial.unitSize(diameter: Double(d)), weight: .medium)).foregroundStyle(pal.muted)
                        }
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(width: CGFloat(2 * BraunDial.dotRadius(diameter: Double(d))) - 6)
        }
        .frame(width: d, height: d)
    }
}

/// Строка точки: рельса и кружок, знак, время, название; у текущей — подложка Braun и срок «до 15:00» (справа от названия, а если название не влезает —
/// второй строкой под ним). Прошедшие точки тусклые, будущие — серые.
struct RouteRow: View {
    let plan: DayPlan
    let index: Int
    /// Первая строка таймлайна и первая точка маршрута (рельса начинается с её кружка), последняя строка и последняя точка (рельса кончается кружком).
    let first: Bool
    let last: Bool
    let pal: BraunPalette
    let height: CGFloat
    let width: CGFloat

    private var stop: WidgetFeed.Stop { plan.stops[index] }
    private var current: Bool { index == plan.currentIndex }
    private var past: Bool { plan.currentIndex.map { index < $0 } ?? false }

    private var until: String? {
        guard current, let end = plan.pointEnd else { return nil }
        return plan.words[.until].replacingOccurrences(of: "{t}", with: plan.frame.clock(end, in: plan.zone))
    }

    /// Хвост «до 15:00» стоит справа, пока название при 13 pt остаётся целым; иначе уходит под название.
    private var tagBelow: Bool {
        guard let until else { return false }
        let timeW = 38.0, signW = 15.0 + 6, rail = 12.0 + 8, pad = 16.0
        let nameAvail = Double(width) - pad - rail - signW - timeW - 6 - BraunText.width(until, size: 11, semibold: true) - 6
        return BraunText.width(stop.name, size: 13, semibold: current) > nameAvail
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            rail
            WidgetIcon(name: stop.sign, size: 15, line: 1.5).foregroundStyle(current ? pal.amber : (past ? pal.muted.opacity(0.6) : pal.muted)).frame(width: 15, height: 15)
            Text(plan.frame.clock(stop.date, in: plan.zone))
                .font(.system(size: 13, weight: .semibold)).monospacedDigit().lineLimit(1).fixedSize()
                .foregroundStyle(current ? pal.amber : (past ? pal.muted.opacity(0.6) : pal.text))
                .frame(width: 38, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(stop.name).font(.system(size: 13, weight: current ? .semibold : .regular))
                    .foregroundStyle(current ? pal.amber : (past ? pal.muted.opacity(0.7) : pal.text)).lineLimit(1).minimumScaleFactor(0.8)
                if tagBelow, let until { tag(until) }
            }
            Spacer(minLength: 0)
            if !tagBelow, let until { tag(until) }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        .background { if current { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(pal.pill) } }
    }

    private func tag(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(pal.amber).lineLimit(1).fixedSize()
    }

    /// Золотая рельса через строку и кружок: пройденное и текущее — латунь (пройденное тусклее), будущее — серая, кружок текущей крупнее.
    private var rail: some View {
        let lit = past || current
        let line = lit ? pal.amber.opacity(past ? 0.55 : 1) : pal.muted.opacity(0.35)
        let r: CGFloat = current ? 10 : 7
        return ZStack {
            VStack(spacing: 0) {
                Rectangle().fill(first ? Color.clear : line).frame(width: 2)
                Rectangle().fill(last ? Color.clear : line).frame(width: 2)
            }
            Circle().fill(lit ? pal.amber.opacity(past ? 0.55 : 1) : pal.dial)
                .overlay(Circle().strokeBorder(lit ? Color.clear : pal.muted.opacity(0.7), lineWidth: 1.2))
                .frame(width: r, height: r)
        }
        .frame(width: 12)
    }
}
