import SwiftUI
import LightPlanDomain

/// Большой виджет (30б.2в, `systemLarge`; выбор Алексея 26.10: «большой день со съёмкой»). Слова Алексея 25.10: «Таймлайн дня» — дата и «12:00–22:00 · жанр · N точек»,
/// точки с временем и названием как в блоке маршрута карточки, внизу свет (рассвет, золотой час, закат); в день без съёмок — только свет.
/// Плашка 364 × 382 на Pro Max, 338 × 354 на iPhone 14.
struct LargeView: View {
    let frame: WidgetFrame
    var alpha = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Inner(frame: frame, alpha: alpha, st: WidgetStyle(dark: scheme == .dark))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private struct Inner: View {
        let frame: WidgetFrame
        let alpha: Bool
        let st: WidgetStyle
        @Environment(\.dynamicTypeSize) private var type

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if let plan = DayPlan(frame) { day(plan) } else { lightOnly }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        // MARK: День со съёмкой: таймлайн и свет

        private func dateLine(_ zone: TimeZone) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: frame.lang)
            f.timeZone = zone
            f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
            return f.string(from: frame.now).prefix(1).uppercased() + f.string(from: frame.now).dropFirst()
        }

        /// Дата и свет — того дня, который рисует съёмка (`DayPlan.dateLine`, `ShootFrame.day`): накануне это завтрашний день.
        @ViewBuilder private func day(_ plan: DayPlan) -> some View {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.dateLine).font(.caption.weight(.semibold)).foregroundStyle(st.ink2).lineLimit(1)
                Spacer(minLength: 0)
                if alpha { AlphaBadge() }
            }
            Text("\(plan.shootRange) · \(plan.title) · \(plan.stops.count) \(plan.words[.points])")
                .font(.subheadline.weight(.semibold)).foregroundStyle(st.ink).lineLimit(1).minimumScaleFactor(0.7).padding(.top, 2)
            timeline(plan).padding(.top, 10)
            Spacer(minLength: 6)
            if let d = plan.primary.day { lightStrip(d, in: plan.zone) }
        }

        /// Вертикальная линия дня: пройденное тусклое, текущая точка — янтарная, будущее — серое; линия заполнена до «сейчас».
        private func timeline(_ plan: DayPlan) -> some View {
            let rows = type.rows(normal: 6, large: 5, huge: 4)
            let first = max(0, min(plan.currentIndex ?? 0, plan.stops.count - rows))
            let shown = Array(plan.stops.enumerated()).dropFirst(first).prefix(rows)
            return VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown), id: \.offset) { i, s in
                    let isCurrent = i == plan.currentIndex
                    let past = plan.currentIndex.map { i < $0 } ?? false
                    HStack(alignment: .center, spacing: 8) {
                        ZStack {
                            Rectangle().fill(past || isCurrent ? st.amber.opacity(0.55) : st.ink.opacity(0.15)).frame(width: 2)
                            Circle().fill(isCurrent ? st.amber : (past ? st.amber.opacity(0.55) : st.surface))
                                .overlay(Circle().strokeBorder(isCurrent || past ? Color.clear : st.ink.opacity(0.3), lineWidth: 1.2))
                                .frame(width: isCurrent ? 10 : 7, height: isCurrent ? 10 : 7)
                        }
                        .frame(width: 12)
                        StopLine(plan: plan, stop: s, isCurrent: isCurrent, past: past, signSize: 16, withPlace: true, st: st)
                        Spacer(minLength: 0)
                        if isCurrent, let end = plan.pointEnd {
                            Text(plan.words[.until].replacingOccurrences(of: "{t}", with: plan.frame.clock(end, in: plan.zone))).font(.caption2.weight(.semibold)).foregroundStyle(st.amber)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                if plan.stops.count > first + rows {
                    Text(plan.words[.more].replacingOccurrences(of: "{n}", with: "\(plan.stops.count - first - rows)")).font(.caption2).foregroundStyle(st.ink2).padding(.leading, 20)
                }
            }
        }

        // MARK: Свет

        private func lightStrip(_ d: WidgetFeed.DayLight, in zone: TimeZone) -> some View {
            VStack(spacing: 6) {
                Rectangle().fill(st.ink.opacity(0.12)).frame(height: 1)
                if d.sunrise == nil && d.sunset == nil {
                    Text(d.polar == .night ? frame.words[.polarNight] : frame.words[.polarDay])
                        .font(.subheadline.weight(.semibold)).foregroundStyle(st.ink).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        lightCell(frame.words[.sunrise], d.sunrise, in: zone, sign: "sunrise", accent: false)
                        lightCell(frame.words[.golden], d.golden, in: zone, sign: "sun", accent: true)
                        lightCell(frame.words[.sunset], d.sunset, in: zone, sign: "sunset", accent: false)
                    }
                }
            }
        }

        private func lightCell(_ name: String, _ at: Date?, in zone: TimeZone, sign: String, accent: Bool) -> some View {
            let passed = at.map { $0 < frame.now } ?? false
            return VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    WidgetIcon(name: sign, size: 13).foregroundStyle(accent ? st.amber : st.ink2)
                    Text(name).font(.caption).foregroundStyle(accent ? st.amber : st.ink2).lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(at.map { frame.clock($0, in: zone) } ?? "—")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
                    .foregroundStyle(st.ink.opacity(passed ? 0.5 : 1))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // MARK: День без съёмок: только свет

        @ViewBuilder private var lightOnly: some View {
            let zone = frame.zone
            HStack(alignment: .firstTextBaseline) {
                Text(dateLine(zone)).font(.caption.weight(.semibold)).foregroundStyle(st.ink2).lineLimit(1)
                Spacer(minLength: 0)
                if alpha { AlphaBadge() }
            }
            Text(frame.place.name.isEmpty ? "Light Plan" : frame.place.name)
                .font(.subheadline.weight(.semibold)).foregroundStyle(st.ink).lineLimit(1).padding(.top, 2)
            if let d = frame.day, let rise = d.sunrise, let set = d.sunset {
                SunArc(rise: rise, set: set, golden: d.golden, now: frame.now, st: st)
                    .frame(minHeight: 90, maxHeight: .infinity).padding(.top, 10)
                Spacer(minLength: 6)
                Text("\(frame.words[.dayLength]) \(RemainText(words: frame.words).long(set.timeIntervalSince(rise)))")
                    .font(.footnote).foregroundStyle(st.ink2).lineLimit(1).padding(.bottom, 6)
                lightStrip(d, in: zone)
            } else if let d = frame.day {
                Spacer(minLength: 0)
                lightStrip(d, in: zone)
            } else {
                Spacer(minLength: 0)
                Text("—").font(.title).foregroundStyle(st.ink)
            }
        }
    }
}

/// Дуга солнца за день: от восхода к закату, золотой час закрашен янтарём, точка — «сейчас» (до восхода и после заката стоит у края).
struct SunArc: View {
    let rise: Date
    let set: Date
    let golden: Date?
    let now: Date
    let st: WidgetStyle

    var body: some View {
        Canvas { ctx, size in
            let base = size.height - 6
            let rx = (size.width - 12) / 2, ry = base - 6
            func point(_ f: Double) -> CGPoint {
                let a = Double.pi * (1 - f)
                return CGPoint(x: size.width / 2 + rx * CGFloat(cos(a)), y: base - ry * CGFloat(sin(a)))
            }
            func frac(_ d: Date) -> Double { min(1, max(0, d.timeIntervalSince(rise) / set.timeIntervalSince(rise))) }
            var horizon = Path()
            horizon.move(to: CGPoint(x: 0, y: base)); horizon.addLine(to: CGPoint(x: size.width, y: base))
            ctx.stroke(horizon, with: .color(st.ink.opacity(0.18)), lineWidth: 1)
            func arc(_ a: Double, _ b: Double) -> Path {
                var p = Path()
                p.move(to: point(a))
                for i in 1...40 { p.addLine(to: point(a + (b - a) * Double(i) / 40)) }
                return p
            }
            ctx.stroke(arc(0, 1), with: .color(st.ink.opacity(0.28)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            if let g = golden { ctx.stroke(arc(frac(g), 1), with: .color(st.amber), style: StrokeStyle(lineWidth: 3, lineCap: .round)) }
            let f = frac(now)
            let p = point(f)
            let day = now >= rise && now <= set
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)),
                     with: .color(day ? st.amber : st.ink.opacity(0.4)))
        }
    }
}
