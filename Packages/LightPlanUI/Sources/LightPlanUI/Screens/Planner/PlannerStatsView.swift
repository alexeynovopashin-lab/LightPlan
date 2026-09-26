import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Статистика года (веб `#statsOverlay`, итерация 22): перегруз, занятость по
/// месяцам, жанры, прибыль по валютам, сроки сдачи. Въезжает справа, как
/// страница года. Считается при каждом показе — у веба только при входе в
/// год, и после правки мог показать старое.
struct PlannerStatsView: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Bindable var nav: PlannerNav
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let y = nav.year
        let all = YearMath.work(app.sessions, year: y)
        let bars = YearMath.monthBars(app.sessions, year: y, status: app.deliveryStatus)
        let hasBars = bars.contains { $0.count > 0 }
        let over = YearMath.overload(app.sessions, now: app.now(), zone: .current, deadline: deadline)
        let late = YearMath.lateGenres(app.sessions, zone: .current, deadline: deadline)
        let empty = over == nil && !hasBars && all.isEmpty && late.isEmpty
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverlayBack(title: f.t.t("year.one"), node: "st.back") {
                    withAnimation(.timingCurve(0.25, 1, 0.4, 1, duration: 0.36)) { nav.statsOpen = false }
                }
                if empty {
                    Text(f.t.t("stats.empty")).font(webFont(14)).foregroundStyle(pal.ink7)
                        .padding(.vertical, 20).shotNode("st.empty")
                }
                if let over { overload(over, pal) }
                if hasBars {
                    label("year.months", node: "st.months", top: 30)
                    Text(f.t.t("year.monthsNote")).font(webFont(12)).foregroundStyle(pal.ink6)
                        .lineSpacing(18 - 14.3).padding(.vertical, (18 - 14.3) / 2)
                        .padding(.horizontal, 24).padding(.top, 10 - 4).padding(.bottom, 10)
                        .shotNode("st.monthsNote")
                    monthBars(bars, pal).padding(.top, 10)
                }
                genres(all, pal).padding(.top, 18)
                if !all.isEmpty {
                    label("year.profit", node: "st.profit", top: 22 + 30)
                    ProfitPlate(profit: YearMath.profit(app.sessions, year: y, home: app.settings.currency),
                                year: y, home: app.settings.currency, money: money)
                        .padding(.top, 12)
                }
                if !late.isEmpty {
                    label("year.delivery", node: "st.delv", top: 22 + 30)
                    lateRows(late, pal).padding(.top, 12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(pal.surface.ignoresSafeArea())
    }

    private func deadline(_ s: Session) -> CivilDate? {
        Delivery.deadline(for: s, setting: app.delivery, prefs: app.genrePrefs)
    }

    private func money(_ v: Decimal, _ c: Currency) -> String {
        NumberText(language: app.language).money(NSDecimalNumber(decimal: v).doubleValue, c.rawValue)
    }

    /// `.sec-label` без левого поля.
    private func label(_ key: String, node: String, top: CGFloat) -> some View {
        Text(f.t.t(key))
            .font(.system(size: 10, weight: .semibold)).tracking(1.2).textCase(.uppercase)
            .foregroundStyle(Palette(scheme).ink7)
            .frame(height: 12)
            .shotNode(node, text: f.t.t(key))
            .padding(.top, top).padding(.bottom, 8)
    }

    /// `.say.bad`: терракотовый знак, факты без совета, свечение по периметру.
    private func overload(_ o: (overdue: Int, upcoming: Int), _ pal: Palette) -> some View {
        let t = f.t
        let up = "\(o.upcoming)"
        let text = t.t("year.overload", ["overdue": "\u{1}\(o.overdue)\u{2}",
                                         "upcoming": "\u{1}\(up)\u{2}" + t.sep("unit.shoot") + t.word("unit.shoot", o.upcoming)])
        return HStack(alignment: .top, spacing: 9) {
            Icon("warn", size: 16, line: 1.5).foregroundStyle(pal.terra).padding(.top, 1)
            Text(Self.bold(text, ink: pal.ink)).font(webFont(13.5)).foregroundStyle(pal.ink3)
                .lineSpacing(13.5 * 0.45 - 3)
        }
        .padding(.vertical, 11).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .modifier(WarnGlow(rgb: (201, 102, 61), alpha: scheme == .light ? 0.55 : 0.32))
        .padding(.top, 9)
        .shotNode("st.overload")
    }

    /// Куски между `\u{1}` и `\u{2}` — чернилами (веб `<b>` без жирного).
    static func bold(_ s: String, ink: Color) -> AttributedString {
        var out = AttributedString()
        for (i, part) in s.split(separator: "\u{1}", omittingEmptySubsequences: false).enumerated() {
            if i == 0 { out += AttributedString(String(part)); continue }
            let pieces = part.split(separator: "\u{2}", maxSplits: 1, omittingEmptySubsequences: false)
            var b = AttributedString(String(pieces[0]))
            b.foregroundColor = ink
            out += b
            if pieces.count > 1 { out += AttributedString(String(pieces[1])) }
        }
        return out
    }

    private func monthBars(_ bars: [YearMath.MonthBar], _ pal: Palette) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<12, id: \.self) { m in
                let b = bars[m]
                HStack(spacing: 12) {
                    Text(f.dates.monthTitleN(m))
                        .font(webFont(13.5, b.count > 0 ? 600 : 500))
                        .foregroundStyle(b.count > 0 ? pal.ink : pal.ink7)
                        .lineLimit(1)
                        .frame(width: 70, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(pal.meterOff)
                            if let w = b.worst, b.count > 0 {
                                Capsule().fill(f.deliveryColor(w))
                                    .frame(width: g.size.width * CGFloat(b.percent) / 100)
                            }
                        }
                    }
                    .frame(height: 4)
                    Text(b.count > 0 ? "\(b.count)" : "")
                        .font(webFont(12.5).monospacedDigit()).foregroundStyle(pal.ink4)
                        .frame(width: 16, alignment: .trailing)
                }
                .padding(.vertical, 8).padding(.horizontal, 2)
                .overlay(alignment: .bottom) { if m < 11 { Rectangle().fill(pal.hair).frame(height: 1) } }
                .shotNode("st.bar.\(m)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(f.dates.monthTitleN(m))
                .accessibilityValue(f.t.count("unit.shoot", b.count))
            }
        }
    }

    /// «Отснято» и «Предстоит» по жанрам; сегодняшняя — ещё впереди.
    @ViewBuilder private func genres(_ all: [Session], _ pal: Palette) -> some View {
        let today = f.today
        let shot = all.filter { $0.day < today }, todo = all.filter { $0.day >= today }
        VStack(alignment: .leading, spacing: 0) {
            if !shot.isEmpty { genreLine("year.shot", shot, pal).shotNode("st.shot") }
            if !todo.isEmpty { genreLine("year.todo", todo, pal).shotNode("st.todo") }
        }
    }

    private func genreLine(_ key: String, _ list: [Session], _ pal: Palette) -> some View {
        var s = AttributedString(f.t.t(key).uppercased())
        s.font = .system(size: 10, weight: .semibold)
        s.foregroundColor = pal.ink7
        s.kern = 1.1
        s += AttributedString("  ")
        let words = PlannerWords(lexicon: f.t, orgs: [])
        for (i, g) in YearMath.genreCounts(list).enumerated() {
            if i > 0 { s += AttributedString(" · ") }
            var n = AttributedString("\(g.count)")
            n.foregroundColor = pal.ink3
            n.font = webFont(13, 600).monospacedDigit()
            s += n
            let k = "genreN." + g.genre.rawValue
            let w = f.t.word(k, g.count)
            s += AttributedString(f.t.sep(k) + (w == k ? words.genreName(g.genre) : w))
        }
        return Text(s).font(webFont(13)).foregroundStyle(pal.ink6)
            .lineSpacing(13)
            .padding(.vertical, 6.5)
    }

    private func lateRows(_ rows: [(genre: Genre, days: Int)], _ pal: Palette) -> some View {
        let words = PlannerWords(lexicon: f.t, orgs: [])
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                let frac = min(1, Double(r.days) / 10)
                HStack(spacing: 14) {
                    HalfGauge(frac: frac, color: Color(rgb: Urgency.rgb(frac, dark: f.dark)), track: pal.sheet3)
                        .frame(width: 52, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("«" + words.genreName(r.genre) + "»").font(webFont(14, 600)).foregroundStyle(pal.ink)
                        Text(f.t.t("year.lateBy", ["days": f.t.count("unit.day", r.days)]))
                            .font(webFont(12)).foregroundStyle(pal.ink4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10).padding(.horizontal, 2)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(pal.hair).frame(height: 1) } }
                .shotNode("st.late.\(i)")
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Плашка прибыли (веб `renderProfitPlate`): год, крупная сумма домашней
/// валюты, спарклайн нарастающим итогом, другие валюты строками.
private struct ProfitPlate: View {
    let profit: YearMath.Profit
    let year: Int
    let home: Currency
    let money: (Decimal, Currency) -> String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let neg = profit.amount < 0
        let tone = neg ? pal.terra : pal.green
        VStack(alignment: .leading, spacing: 0) {
            Text(String(year)).font(webFont(11, 600)).tracking(1.3).foregroundStyle(pal.ink4)
            Text(money(profit.amount, home)).font(webFont(30, 300)).tracking(-0.5).monospacedDigit()
                .foregroundStyle(tone).padding(.top, 6)
                .shotNode("st.profitNum")
            Spark(points: YearMath.sparkPoints(profit.cumulative.map { NSDecimalNumber(decimal: $0).doubleValue }))
                .stroke(tone, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .overlay { SparkDot(points: YearMath.sparkPoints(profit.cumulative.map { NSDecimalNumber(decimal: $0).doubleValue })).fill(tone) }
                .frame(height: 42)
                .padding(.top, 14)
            if !profit.others.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(profit.others, id: \.currency) { o in
                        Text(money(o.sum, o.currency)).font(webFont(14).monospacedDigit())
                            .foregroundStyle(o.sum < 0 ? pal.terra : pal.ink3)
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pal.sheet2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shotNode("st.plate")
    }
}

/// Линия спарклайна: точки в поле 320 × 42, растянутом на ширину (у веба
/// `preserveAspectRatio="none"`).
private struct Spark: Shape {
    let points: [CGPoint]
    func path(in r: CGRect) -> Path {
        var p = Path()
        let sx = r.width / 320, sy = r.height / 42
        for (i, q) in points.enumerated() {
            let pt = CGPoint(x: r.minX + q.x * sx, y: r.minY + q.y * sy)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// Точка на конце спарклайна, радиус 3,2. У веба она тянется вместе с полем
/// (эллипс); здесь круглая.
private struct SparkDot: Shape {
    let points: [CGPoint]
    func path(in r: CGRect) -> Path {
        guard let q = points.last else { return Path() }
        let c = CGPoint(x: r.minX + q.x * r.width / 320, y: r.minY + q.y * r.height / 42)
        return Path(ellipseIn: CGRect(x: c.x - 3.2, y: c.y - 3.2, width: 6.4, height: 6.4))
    }
}

/// Полукруглый манометр (веб `halfGaugeSVG`): поле 56 × 32, центр (28, 28),
/// радиус 24, трасса и закрашенная дуга толщиной 4, точка радиусом 3.
struct HalfGauge: View {
    let frac: Double
    let color: Color
    let track: Color

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 56, size.height / 32)
            let c = CGPoint(x: 28 * s, y: 28 * s), r = 24 * s
            var arc = Path()
            arc.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            ctx.stroke(arc, with: .color(track), style: StrokeStyle(lineWidth: 4 * s, lineCap: .round))
            let th = Double.pi * (1 - frac)
            let end = CGPoint(x: c.x + r * cos(th), y: c.y - r * sin(th))
            if frac > 0.03 {
                var fill = Path()
                fill.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .radians(-th), clockwise: false)
                ctx.stroke(fill, with: .color(color), style: StrokeStyle(lineWidth: 4 * s, lineCap: .round))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 3 * s, y: end.y - 3 * s, width: 6 * s, height: 6 * s)), with: .color(color))
        }
    }
}

/// Ровное свечение по периметру (веб `glow-flow`, 14 с): центр тени обходит
/// круг радиусом 3, яркость дышит ×0,85…1,15. Без движения, если система
/// просит меньше движения.
struct WarnGlow: ViewModifier {
    let rgb: (Double, Double, Double)
    let alpha: Double
    @Environment(\.accessibilityReduceMotion) private var still

    func body(content: Content) -> some View {
        let c = Color(.sRGB, red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255)
        if still {
            content.shadow(color: c.opacity(alpha), radius: 8)
        } else {
            TimelineView(.animation) { tl in
                let ph = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 14) / 14 * 2 * .pi
                content.shadow(color: c.opacity(alpha * (1 + 0.15 * sin(2 * ph))), radius: 8,
                               x: 3 * cos(ph), y: 3 * sin(ph))
            }
        }
    }
}
