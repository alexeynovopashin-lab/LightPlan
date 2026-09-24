import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Закреплённый блок дня (`.day-sticky.on`): неделя дат и сводка. Лента часов
/// едет под ним.
struct PlannerDaySticky: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(Array(app.planner.week.enumerated()), id: \.element) { i, d in
                    date(d, pal).shotNode("dd.\(i)")
                }
            }
            .padding(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
            .background(pal.surface)
            .shotNode("dates")
            PlannerDayPanel(app: app, f: f)
        }
    }

    /// Дата недели (`.dd-day`): день недели, число в круге, до трёх знаков
    /// записей и счётчик; день только с занятостью — замок.
    private func date(_ d: CivilDate, _ pal: Palette) -> some View {
        let sel = d == app.planner.selected, today = d == f.today
        let marks = f.shown(on: d)
        return Button {
            withAnimation(.snappy(duration: 0.22)) { _ = app.planner.pickInStrip(d) }
        } label: {
            VStack(spacing: 4) {
                Text(f.dates.wdShort(f.date(d))).font(webFont(10)).tracking(0.5).foregroundStyle(pal.ink7)
                    .frame(height: 12)
                Text("\(d.day)")
                    .font(webFont(15, sel || today ? 650 : 400)).monospacedDigit()
                    .foregroundStyle(sel ? pal.onBrass : today ? pal.brass : pal.ink2)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(sel ? pal.brass : .clear))
                HStack(spacing: 3) {
                    ForEach(marks.prefix(3), id: \.id) { s in
                        Group {
                            if !s.kind.isWork { Icon(s.kind == .meet ? "guests" : "view_month", size: 11, line: 1.8) }
                            else if let n = f.words.iconName(s) { Icon(n, size: 11, line: 1.8) }
                            else { Icon(genre: s.genre?.rawValue ?? "", size: 11, line: 1.8) }
                        }
                        .foregroundStyle(s.kind.isWork ? pal.brassSoft : pal.ink6)
                    }
                    if marks.count > 3 {
                        Text("+\(marks.count - 3)").font(webFont(9)).foregroundStyle(pal.ink6)
                    }
                    if marks.isEmpty, !f.blocks(on: d).isEmpty { Icon("lock", size: 11, line: 1.8).foregroundStyle(pal.ink6) }
                }
                .frame(height: 12)
            }
            .padding(.top, 4).padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Лента дня (веб, дневная ветка `renderDayPanel`): часовая сетка с 00:00 до
/// 00:00 следующих суток, ось окрашена светом дня, съёмки и занятость —
/// блоками в колонках (`DayLanes`), отметки восхода, заката и «сейчас».
/// Пустой час — слот: тап даёт три действия (формы — итерации 23–24).
struct PlannerDayBody: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Environment(\.colorScheme) private var scheme

    /// Высота заголовка загрузки: поле 16 + строка 12 + поле 7.
    static let loadHeight: CGFloat = 35
    /// Поле ленты сверху (`--dl-top`).
    static let lineTop: CGFloat = 8
    static let hourH = CGFloat(DayLanes.hourHeight)
    /// Колонка часов кончается на 70 pt от края экрана: там начинаются блоки.
    static let lane: CGFloat = 70
    /// Середина оси — 24 поля + 46 часов + 9.
    static let axis: CGFloat = 79

    var body: some View {
        let d = app.planner.selected
        let items = f.items(on: d)
        VStack(spacing: 0) {
            PlannerLoadLabel(f: f, items: items)
            timeline(d, items)
                .padding(.top, Self.lineTop)
                .padding(.bottom, 20)
                .shotNode("line")
                .id(d)
                .transition(.asymmetric(insertion: .offset(x: 18 * CGFloat(app.planner.dayShift)).combined(with: .opacity),
                                        removal: .identity))
        }
    }

    private func timeline(_ d: CivilDate, _ items: [DayItem]) -> some View {
        let pal = Palette(scheme)
        let sky = f.sky(d)
        let isToday = d == f.today
        let nowMin = app.nowMinute
        let slots = DayLanes.layout(items)
        return ZStack(alignment: .topLeading) {
            // Сетка часов.
            VStack(spacing: 0) {
                ForEach(0...24, id: \.self) { h in
                    slot(h, pal: pal, sky: sky, hushed: isToday && Self.hushed(h, now: nowMin))
                        .shotNode("slot.\(h)")
                }
            }
            .padding(.horizontal, 24)
            // Блоки.
            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                event(it, index: i, slot: slots[i], pal: pal)
            }
            // Узлы начала — после всех блоков, чтобы ранний не ушёл под поздний.
            ForEach(Array(items.enumerated()), id: \.element.id) { _, it in dot(it, pal) }
            // Восход и закат — всегда, в любую погоду.
            let lights = [(sky.rise, "sunrise", "win.dawn"), (sky.set, "sunset", "win.sunset")]
                .compactMap { m in m.0.map { ($0, m.1, m.2) } }
            ForEach(Array(lights.enumerated()), id: \.offset) { k, m in
                lightMark(top: Self.top(m.0.rounded()), icon: m.1, word: f.t.t(m.2), node: "mark.\(k)", pal: pal)
            }
            if isToday {
                nowMark(nowMin, node: "mark.\(lights.count)", pal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 25 * Self.hourH, alignment: .top)
    }

    nonisolated static func top(_ m: Double) -> CGFloat { CGFloat(m) / 60 * hourH }

    /// Подпись часа прячется, когда её достаёт капсула «сейчас»: подходя снизу
    /// — за 12,2 pt до черты, уходя вверх — через 15,7 (веб `HUSH_UP/DN`,
    /// выведены из его вёрстки; своя вёрстка цифр здесь та же — 12 pt,
    /// приподнята на 6).
    nonisolated static func hushed(_ h: Int, now: Int) -> Bool {
        let dh = top(Double(now)) - top(Double(h * 60))
        return dh > -12.2 && dh < 15.7
    }

    private func slot(_ h: Int, pal: Palette, sky: SolarDay, hushed: Bool) -> some View {
        let label = String(format: "%02d:00", h % 24)
        return Menu {
            Section(f.fmt(Double(h % 24 * 60))) {
                Button(f.t.t("day.actShoot")) {}
                Button(f.t.t("day.actMeet")) {}
                Button(f.t.t("day.actBusy")) {}
            }
        } label: {
            HStack(spacing: 0) {
                Text(label).font(webFont(12)).tracking(0.2).monospacedDigit()
                    .foregroundStyle(pal.ink7)
                    .opacity(hushed ? 0 : 1)
                    .frame(width: 46, height: Self.hourH, alignment: .topLeading)
                    .offset(y: -6)
                // Ось: своя полоса у каждого часа, от цвета его начала к цвету конца.
                let a = h >= 24 ? 1439.0 : Double(h % 24 * 60), b = h >= 24 ? 1439.0 : a + 59
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [Self.phase(a, sky), Self.phase(b, sky)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3)
                    .frame(width: 18)
                Rectangle().fill(.clear)
                    .overlay(alignment: .top) { Rectangle().fill(pal.hairline).frame(height: 1) }
                    .overlay {
                        Line().stroke(pal.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).opacity(0.55)
                            .frame(height: 1)
                    }
                    .padding(.leading, 10)
            }
            .frame(height: Self.hourH)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    /// Цвет оси в минуту дня (веб `phaseCol`): ночь, синий час, рассвет,
    /// золотой, день, золотой, закат, синий — приглушено до половины.
    static func phase(_ m: Double, _ sky: SolarDay) -> Color {
        typealias C = (Double, Double, Double)
        let deep: C = (61, 88, 120), blue: C = (91, 119, 160), gold: C = (226, 164, 76)
        let silver: C = (239, 234, 224), scarlet: C = (216, 80, 47)
        func lerp(_ a: C, _ b: C, _ k: Double) -> C {
            let k = min(1, max(0, k))
            return ((a.0 + (b.0 - a.0) * k).rounded(), (a.1 + (b.1 - a.1) * k).rounded(), (a.2 + (b.2 - a.2) * k).rounded())
        }
        let c: C
        if let rise = sky.rise, let set = sky.set, let ba = sky.blueA, let bb = sky.blueB,
           let ga = sky.goldenA, let gb = sky.goldenB {
            if m < ba || m > bb { c = deep }
            else if m < rise { c = lerp(deep, blue, (m - ba) / max(1, rise - ba)) }
            else if m < ga { c = lerp(gold, silver, (m - rise) / max(1, ga - rise)) }
            else if m < gb { c = silver }
            else if m < set { c = lerp(silver, gold, (m - gb) / max(1, set - gb)) }
            else { c = lerp(scarlet, blue, (m - set) / max(1, bb - set)) }
        } else {
            c = sky.rise == nil ? deep : silver
        }
        return Color(.sRGB, red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, opacity: 0.5)
    }

    // MARK: Блоки

    private func event(_ it: DayItem, index: Int, slot: DayLanes.Slot?, pal: Palette) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let cols = slot?.columns ?? 1, col = slot?.column ?? 0
            let top = Self.top(Double(it.start))
            let hgt = max(CGFloat(DayLanes.minHeight), Self.top(Double(it.end)) - top)
            let x = cols > 1 ? Self.lane + (w - Self.lane) * CGFloat(col) / CGFloat(cols) : Self.lane
            let width = cols > 1 ? (w - Self.lane) / CGFloat(cols) - CGFloat(DayLanes.gap) : w - Self.lane
            eventBody(it, index: index, height: hgt, cols: cols, pal: pal)
                .frame(width: width, height: hgt, alignment: .topLeading)
                .clipped()
                .position(x: x + width / 2, y: top + hgt / 2)
        }
        .frame(height: 25 * Self.hourH)
        .allowsHitTesting(true)
    }

    private func eventBody(_ it: DayItem, index: Int, height hgt: CGFloat, cols: Int, pal: Palette) -> some View {
        let busy = it.kind == .busy, soft = it.kind == .meet || it.kind == .event
        let ink = pal.ink
        let (fill, stop, topA, botA): (Color, Double, Double, Double) = busy ? (ink, 0.70, 0.12, 0.08)
            : soft ? (ink, 0.78, 0.24, 0.12) : (Color(hex: 0xE2A44C), 0.92, 0.55, 0.30)
        let bg: LinearGradient = busy || soft
            ? LinearGradient(stops: [.init(color: fill.opacity(busy ? 0.08 : 0.10), location: 0),
                                     .init(color: fill.opacity(0), location: stop)], startPoint: .leading, endPoint: .trailing)
            : LinearGradient(stops: [.init(color: fill.opacity(0.16), location: 0), .init(color: fill.opacity(0.05), location: 0.58),
                                     .init(color: fill.opacity(0), location: 0.92)], startPoint: .leading, endPoint: .trailing)
        let tight = hgt < Self.hourH, room = hgt >= 2 * Self.hourH
        let (title, sub, due) = words(it)
        return HStack(alignment: .top, spacing: 8) {
            if cols <= 2 {
                icon(it, pal).frame(width: 16, height: 16)
            }
            let t = Text(title).font(webFont(14, busy ? 500 : 600)).foregroundStyle(busy ? pal.ink3 : pal.ink).lineLimit(1)
            let s = Text(sub).font(webFont(12)).monospacedDigit().foregroundStyle(pal.ink4).lineLimit(1)
            if tight {
                HStack(alignment: .firstTextBaseline, spacing: 8) { t; if cols <= 1 { s } }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    t
                    if cols <= 2 { s }
                    if room, cols <= 1, let due { Text(due.0).font(webFont(12)).foregroundStyle(due.1) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 3, leading: cols > 2 ? 14 : cols > 1 ? 20 : 28, bottom: 3, trailing: 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(bg)
        .overlay(alignment: .top) { Rectangle().fill((busy || soft ? ink : fill).opacity(topA)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill((busy || soft ? ink : fill).opacity(botA)).frame(height: 1) }
        .contentShape(Rectangle())
        .shotNode("ev.\(index)")
    }

    private func icon(_ it: DayItem, _ pal: Palette) -> some View {
        Group {
            if let b = it.block { Icon(b.kind.iconName, size: 16, line: 1.5) }
            else if it.kind == .meet { Icon("guests", size: 16, line: 1.5) }
            else if it.kind == .event { Icon("view_month", size: 16, line: 1.5) }
            else if let s = it.session, let n = f.words.iconName(s) { Icon(n, size: 16, line: 1.5) }
            else { Icon(genre: it.session?.genre?.rawValue ?? "", size: 16, line: 1.5) }
        }
        .foregroundStyle(it.kind == .shoot ? pal.brass : pal.ink5)
    }

    /// Имя, вторая строка и срок сдачи блока (веб `name`, `sub`, `.dl-due`).
    private func words(_ it: DayItem) -> (String, String, (String, Color)?) {
        if let b = it.block {
            return (f.blockLabel(b), b.allDay ? f.t.t("day.allDay") : f.range(Double(it.start), Double(it.end)), nil)
        }
        guard let s = it.session else { return ("", "", nil) }
        let who = f.words.clientName(s)
        let name = !who.isEmpty ? who : it.kind == .meet ? f.t.t("day.meet") : it.kind == .event ? f.t.t("day.event") : f.words.typeName(s)
        let sub: String
        switch it.kind {
        case .meet: sub = f.t.t("day.meetLower", ["genre": f.words.shortType(s).lowercased()])
        case .event: sub = f.t.t("day.eventLower", ["genre": f.words.shortType(s).lowercased()])
        default:
            sub = it.fromYesterday
                ? f.t.t("day.fromDate", ["date": f.dates.dMonShort(f.date(s.day))]) + f.t.t("day.tillTime", ["t": f.fmt(Double(s.endMinute))])
                : f.fmt(Double(s.start)) + " – " + f.fmt(Double(s.endMinute))
        }
        let st = app.deliveryStatus(s)
        let due = st.rank >= 2 ? (f.deliveryWords(st).label, f.deliveryColor(st)) : nil
        return (name, sub, due)
    }

    private func dot(_ it: DayItem, _ pal: Palette) -> some View {
        let top = Self.top(Double(it.start))
        return Group {
            if it.kind == .busy {
                RoundedRectangle(cornerRadius: 1).fill(pal.ink6).frame(width: 11, height: 2)
            } else {
                Circle().fill(it.kind == .shoot ? pal.brass : pal.surface)
                    .overlay(Circle().strokeBorder(pal.brass, lineWidth: 1.5))
                    .frame(width: 9, height: 9)
            }
        }
        .position(x: Self.axis, y: top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Отметка света: пунктир от оси до слова у правого края ленты.
    private func lightMark(top: CGFloat, icon: String, word: String, node: String, pal: Palette) -> some View {
        HStack(spacing: 0) {
            Line().stroke(pal.brassDeep, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).opacity(0.5).frame(height: 1)
            HStack(spacing: 5) {
                Icon(icon, size: 13).foregroundStyle(pal.brass)
                Text(word).font(webFont(11)).foregroundStyle(pal.brassDeep)
            }
            .padding(.leading, 8)
            .shotNode(node)
            .shadow(color: pal.surface, radius: 3)
        }
        .padding(.leading, Self.axis)
        .padding(.trailing, 24)
        .frame(height: 13)
        .padding(.top, top - 6.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// «Сейчас»: капсула со временем в колонке часов и сплошная черта.
    private func nowMark(_ m: Int, node: String, _ pal: Palette) -> some View {
        let top = Self.top(Double(m))
        return ZStack(alignment: .leading) {
            Rectangle().fill(pal.brass.opacity(0.85)).frame(height: 1)
                .padding(.leading, 24)
            Circle().fill(pal.brass).frame(width: 6, height: 6).offset(x: Self.axis - 3)
            Text(f.fmt(Double(m)))
                .font(webFont(12, 650)).tracking(0.2).monospacedDigit()
                .foregroundStyle(pal.onBrass)
                .padding(.horizontal, 8).frame(height: 19)
                .background(Capsule().fill(pal.brass))
                .shotNode(node)
                .padding(.leading, 12)
        }
        .padding(.trailing, 24)
        .frame(height: 19)
        .padding(.top, top - 9.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Горизонталь на всю ширину — для пунктира.
private struct Line: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}
