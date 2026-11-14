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

        /// Слово в центре купола: ближайшее событие света дня (рассвет → золотой час → закат), после заката — снова рассвет.
        /// Эскиз 14.11 ставит сюда слово «Света» («ВЕЧЕРЕЕТ»), но состояния света виджет не получает — берём то, что в его данных есть.
        private func lightWord(_ d: WidgetFeed.DayLight) -> String {
            let next: [(Date?, WidgetFeed.Words.Key)] = [(d.sunrise, .sunrise), (d.golden, .golden), (d.sunset, .sunset)]
            for (t, key) in next where (t.map { $0 > frame.now } ?? false) { return frame.words[key].uppercased() }
            return frame.words[.sunrise].uppercased()
        }

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
                SunArc(rise: rise, set: set, now: frame.now, clock: frame.clock(frame.now, in: zone), word: lightWord(d), st: st)
                    .frame(minHeight: 90, maxHeight: .infinity).padding(.top, 6)
                lightStrip(d, in: zone).padding(.top, 6)
                Text("\(frame.words[.dayLength]) \(RemainText(words: frame.words).long(set.timeIntervalSince(rise)))")
                    .font(.footnote).foregroundStyle(st.ink2).lineLimit(1).padding(.top, 10)
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

/// Геометрия купола приложения (`DomeGeometry`: полуэллипс 163 × 148 на холсте 390 × 240, горизонт на y = 196), вписанная в плашку.
/// Расширение не видит `LightPlanUI`, поэтому числа скопированы (как `WidgetIcons.generated.swift`); сверка — `WidgetDomeTests`.
/// Пропорции фиксированы: форма не зависит от размера плашки, зависит только масштаб.
struct DomeFit: Equatable {
    static let rx: CGFloat = 163, ry: CGFloat = 148, canvasWidth: CGFloat = 390
    /// От макушки (с запасом на линию) до пояса под горизонтом, в единицах холста: y = 44 … 202.
    static let topUnits: CGFloat = 44, bottomUnits: CGFloat = 202, horizonUnits: CGFloat = 196

    let scale: CGFloat
    let centerX: CGFloat
    let horizonY: CGFloat
    var rx: CGFloat { Self.rx * scale }
    var ry: CGFloat { Self.ry * scale }

    /// Масштаб — по ширине плашки (как холст приложения); если не хватает высоты, меньше. Купол по центру плашки.
    init(in size: CGSize) {
        let boxH = Self.bottomUnits - Self.topUnits
        scale = max(0.01, min(size.width / Self.canvasWidth, size.height / boxH))
        centerX = size.width / 2
        horizonY = (size.height - boxH * scale) / 2 + (Self.horizonUnits - Self.topUnits) * scale
    }

    /// Точка дуги при доле дня `f` (0 — восход слева, 1 — закат справа).
    func point(_ f: Double) -> CGPoint {
        let a = Double.pi * (1 - f)
        return CGPoint(x: centerX + rx * CGFloat(cos(a)), y: horizonY - ry * CGFloat(sin(a)))
    }
}

/// Купол дня как на экране «Свет» (эскиз 14.11): небо внутри, дуга латунь → серый → латунь, диск солнца с кольцом, пунктир горизонта,
/// время и слово света в центре. Ночной вид — позже; сейчас небо одно, дневное и вечернее.
struct SunArc: View {
    let rise: Date
    let set: Date
    let now: Date
    let clock: String
    let word: String
    let st: WidgetStyle

    /// Небо: тёмная плашка — синее из эскиза (#101B33 → #2A3550), светлая — дневное небо палитры Д (#86BAEC → #DCEBF9).
    private var sky: Gradient {
        st.dark ? Gradient(colors: [Color(red: 0x10 / 255, green: 0x1B / 255, blue: 0x33 / 255), Color(red: 0x2A / 255, green: 0x35 / 255, blue: 0x50 / 255)])
                : Gradient(colors: [Color(red: 0x86 / 255, green: 0xBA / 255, blue: 0xEC / 255), Color(red: 0xDC / 255, green: 0xEB / 255, blue: 0xF9 / 255)])
    }
    private var grey: Color { Color(red: 0x8A / 255, green: 0x8A / 255, blue: 0x92 / 255) }

    var body: some View {
        GeometryReader { g in
            let fit = DomeFit(in: g.size)
            ZStack {
                Canvas { ctx, size in draw(ctx, fit: fit, size: size) }
                VStack(spacing: 2 * fit.scale) {
                    Text(clock).font(.system(size: 40 * fit.scale, weight: .ultraLight)).monospacedDigit().foregroundStyle(st.dark ? st.ink : Color.black)
                    Text(word).font(.system(size: 13 * fit.scale, weight: .semibold)).tracking(1.6).lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(st.dark ? st.ink : Color.black)
                }
                .frame(width: fit.rx * 1.1)
                .position(x: fit.centerX, y: fit.horizonY - fit.ry * 0.40)
            }
        }
    }

    private func draw(_ ctx: GraphicsContext, fit: DomeFit, size: CGSize) {
        func frac(_ d: Date) -> Double { min(1, max(0, d.timeIntervalSince(rise) / set.timeIntervalSince(rise))) }
        let left = CGPoint(x: fit.centerX - fit.rx, y: fit.horizonY), right = CGPoint(x: fit.centerX + fit.rx, y: fit.horizonY)
        func arc() -> Path {
            var p = Path()
            p.move(to: fit.point(0))
            for i in 1...80 { p.addLine(to: fit.point(Double(i) / 80)) }
            return p
        }
        // Небо внутри купола.
        var dome = arc(); dome.closeSubpath()
        ctx.fill(dome, with: .linearGradient(sky, startPoint: CGPoint(x: 0, y: fit.horizonY - fit.ry), endPoint: CGPoint(x: 0, y: fit.horizonY)))
        // Дуга.
        let grad = Gradient(colors: [st.amber, grey, st.amber])
        ctx.stroke(arc(), with: .linearGradient(grad, startPoint: left, endPoint: right), style: StrokeStyle(lineWidth: 3 * max(fit.scale, 0.8), lineCap: .round))
        // Пунктир горизонта чуть шире купола.
        var horizon = Path()
        let pad = 14 * fit.scale
        horizon.move(to: CGPoint(x: max(0, left.x - pad), y: fit.horizonY)); horizon.addLine(to: CGPoint(x: min(size.width, right.x + pad), y: fit.horizonY))
        ctx.stroke(horizon, with: .color(st.ink.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        // Солнце: ореол, тёмное кольцо, ядро; до восхода и после заката стоит у края серым.
        let p = fit.point(frac(now))
        let day = now >= rise && now <= set
        let core = day ? st.amber : st.ink.opacity(0.4)
        func disc(_ r: CGFloat, _ c: Color) { ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(c)) }
        if day { disc(16.5 * fit.scale, st.amber.opacity(0.18)) }
        disc(9.4 * fit.scale, st.dark ? Color(red: 0x0C / 255, green: 0x0B / 255, blue: 0x0A / 255) : Color.white)
        disc(6.5 * fit.scale, core)
    }
}
