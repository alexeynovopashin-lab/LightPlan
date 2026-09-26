import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Месяц (веб `renderCal`): строка дней недели, сетка с понедельника,
/// легенда, под ней — панель выбранного дня: сводка, загрузка, список и три
/// действия.
struct PlannerMonthBody: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Binding var fan: FanTarget?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let st = app.planner
        let grid = st.monthGrid
        let hasShoots = grid.contains { PlannerState.sameMonth($0, st.month) && !f.shown(on: $0).isEmpty }
        VStack(spacing: 0) {
            head(pal)
            VStack(spacing: 2) {
                ForEach(0..<(grid.count / 7), id: \.self) { r in
                    // Клетки ряда тянутся на его высоту, как в сетке веба.
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(0..<7, id: \.self) { c in
                            let i = r * 7 + c
                            MonthCell(app: app, f: f, day: grid[i])
                                .frame(maxHeight: .infinity, alignment: .top)
                                .shotNode("cal.\(i)")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .shotNode("cal")
            if hasShoots { legend(pal) }
            PlannerDayPanel(app: app, f: f)
            PlannerDayList(app: app, f: f, fan: $fan)
            PlannerDayStates(f: f)
        }
    }

    /// `.cal-head`: слова недели от понедельника, выходные светлее.
    private func head(_ pal: Palette) -> some View {
        let week = PlannerState.week(of: app.planner.month)
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let w = f.dates.wdShort(f.date(week[i]))
                Text(w)
                    .font(webFont(12.5, 600)).tracking(0.6)
                    .foregroundStyle(i >= 5 ? pal.ink4 : pal.ink7)
                    .shotNode("head.\(i)", text: w)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .shotNode("cal.head")
    }

    /// Легенда объясняет цвет подписей — только когда в месяце есть съёмки.
    private func legend(_ pal: Palette) -> some View {
        HStack(spacing: 16) {
            ForEach([("plan.legendGood", 0xE2A44C), ("plan.legendOk", 0xA8B49B), ("plan.legendBad", 0x7C9CC4)], id: \.0) { k, c in
                HStack(spacing: 7) {
                    Circle().fill(Color(hex: UInt32(c))).frame(width: 6, height: 6)
                    Text(f.t.t(k)).font(webFont(12)).foregroundStyle(pal.ink4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .shotNode("legend")
    }
}

/// Клетка месяца (веб `cell`): число в круге срочности сдачи, до двух подписей
/// (третья и дальше — счётчиком). Подпись съёмки красится качеством дня,
/// встреча и занятость — без цвета.
private struct MonthCell: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    let day: CivilDate
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let st = app.planner
        let out = !PlannerState.sameMonth(day, st.month)
        let today = f.today
        let isToday = day == today, sel = day == st.selected, past = day < today
        let labels = self.labels(pal, out: out)
        let show = labels.count > 2 ? Array(labels.prefix(1)) : Array(labels.prefix(2))
        let mark = out ? nil : f.mark(day)
        let lit = mark.map { $0.rank >= 3 } ?? false
        let ink: Color = isToday ? pal.brass : out ? pal.ink10 : past ? pal.ink5 : pal.ink

        Button {
            withAnimation(.snappy(duration: 0.25)) { _ = app.planner.tapMonthCell(day) }
        } label: {
            VStack(spacing: 1) {
                Text("\(day.day)")
                    .font(webFont(16.5, isToday ? 650 : 400)).monospacedDigit()
                    .foregroundStyle(ink)
                    .frame(width: 26, height: 26)
                    .background {
                        if lit, let mark { Circle().fill(f.deliveryColor(mark).opacity(0.32)) }
                    }
                ForEach(show.indices, id: \.self) { i in label(show[i], pal) }
                if labels.count > show.count { label(.init(text: "+\(labels.count - show.count)", color: pal.ink7, busy: false), pal) }
            }
            .padding(labels.isEmpty ? EdgeInsets() : EdgeInsets(top: 4, leading: 1, bottom: 5, trailing: 1))
            .frame(width: labels.isEmpty ? 40 : nil, height: labels.isEmpty ? 40 : nil)
            .frame(maxWidth: labels.isEmpty ? nil : .infinity)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(sel ? pal.press : .clear))
            .opacity(1)
            .padding(.horizontal, 1)
            .padding(.top, 3)
            .frame(maxWidth: .infinity, minHeight: 47, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    struct Label: Hashable { let text: String; let color: Color; let busy: Bool }

    private func labels(_ pal: Palette, out: Bool) -> [Label] {
        let shoots = f.shown(on: day).enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map(\.element)
        var out1: [Label] = shoots.map { s in
            if !s.kind.isWork {
                return Label(text: f.t.t(s.kind == .meet ? "plan.meet" : "plan.event"), color: pal.ink5, busy: true)
            }
            let q = f.weather(s.day).quality
            return Label(text: f.words.shortType(s), color: q.dot ?? Color(hex: 0xA8B49B), busy: false)
        }
        if !out { out1 += f.blocks(on: day).map { Label(text: f.blockLabel($0), color: pal.ink5, busy: true) } }
        return out1.map { out ? Label(text: $0.text, color: $0.color.opacity(0.45), busy: $0.busy) : $0 }
    }

    private func label(_ l: Label, _ pal: Palette) -> some View {
        Text(l.text)
            .font(webFont(8.5)).tracking(-0.1)
            .italic(l.busy)
            .foregroundStyle(l.color)
            .lineLimit(1).truncationMode(.tail)
            .frame(height: 10.625)
    }
}

// MARK: - Панель выбранного дня

/// `.day-panel`: латунная черта и приборная строка дня (восход, закат, длина
/// золотого часа, погода), сворачивается шевроном (`dayFold` снимка).
struct PlannerDayPanel: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let open = !app.dayFold
        VStack(spacing: 0) {
            Rectangle().fill(pal.brass.opacity(0.35)).frame(height: 1)
                .padding(.horizontal, -20)
                .padding(.bottom, open ? 8 : 0)
                .overlay(alignment: .trailing) {
                    if !open { chevron(pal, open: false).padding(.trailing, 4) }
                }
            if open { bar(pal) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private func bar(_ pal: Palette) -> some View {
        let d = app.planner.selected
        let sky = f.sky(d), wx = f.weather(d)
        let fog = wx.quality == .fog
        let goldenMin: Double? = fog
            ? sky.rise.flatMap { r in sky.goldenA.map { r - $0 } }
            : sky.set.flatMap { s in sky.goldenB.map { s - $0 } }
        let sc = wx.real ? wx.sunset : nil
        let setColor: Color = sc.map { $0 >= 75 ? pal.brass : $0 >= 50 ? pal.green : $0 >= 28 ? pal.ink : pal.blue } ?? pal.brass
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                item("sunrise", f.fmt(sky.rise), pal.ink2, node: "dp.rise", pal: pal)
                item("sunset", f.fmt(sky.set), setColor, node: "dp.set", pal: pal)
                if let g = goldenMin, g > 0 {
                    item("golden", f.durShort(Int(g.rounded())), pal.ink4, weight: 500, node: "dp.gold", pal: pal)
                }
                Rectangle().fill(pal.hairline).frame(width: 1, height: 12)
                HStack(spacing: 3) {
                    Icon(wx.quality.signIconName, size: 17, line: 1.5).foregroundStyle(pal.ink)
                        .padding(.trailing, 8)
                    let temp = "\(f.temp(d))°"
                    Text(temp).font(webFont(13, 600)).monospacedDigit().foregroundStyle(pal.ink)
                        .shotNode("dp.temp", text: temp)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .frame(height: 38)
            chevron(pal, open: true)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(pal.hairline, lineWidth: 1))
        .shotNode("dp.bar")
        .padding(.horizontal, 4)
    }

    private func item(_ icon: String, _ text: String, _ color: Color, weight: Int = 600, node: String, pal: Palette) -> some View {
        HStack(spacing: 3) {
            Icon(icon, size: 17, line: 1.6).foregroundStyle(pal.brass).offset(y: 17 * 0.073)
            Text(text).font(webFont(13, weight)).monospacedDigit().foregroundStyle(color)
                .shotNode(node, text: text)
        }
        .frame(height: 20)
    }

    /// Шеврон: раскрыто — остриём вверх, свёрнуто — вниз, и тогда он висит
    /// капсулой на черте (`.dp-bar.shut`).
    private func chevron(_ pal: Palette, open: Bool) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.35)) { app.dayFold.toggle() }
        } label: {
            Icon("chevron", size: 16, line: 1.6)
                .rotationEffect(.degrees(open ? -90 : 90))
                .foregroundStyle(pal.ink4)
                .padding(.horizontal, 12).padding(.vertical, open ? 11 : 3)
                .background {
                    if !open {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.bar)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(pal.hairline, lineWidth: 1))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("dp.chev")
        .accessibilityLabel(f.t.t(open ? "today.hide" : "today.details"))
    }
}

/// Загрузка дня заголовком списка (веб `#dpLoad`): «1 съёмка · 1 встреча ·
/// занято 2,5 часа». Отрезки слипаются, наложение не считается дважды.
struct PlannerLoadLabel: View {
    let f: PlannerFacts
    let items: [DayItem]
    @Environment(\.colorScheme) private var scheme

    static func text(_ items: [DayItem], _ f: PlannerFacts) -> String {
        var busy = 0, allDay = false
        var run: (a: Int, b: Int)?
        for x in items {
            if x.isAllDayBusy { allDay = true; continue }
            if x.end <= x.start { continue }
            if let r = run, x.start <= r.b { run = (r.a, max(r.b, x.end)); continue }
            if let r = run { busy += r.b - r.a }
            run = (x.start, x.end)
        }
        if let r = run { busy += r.b - r.a }
        if allDay { return f.t.t("day.busyDay") }
        if items.isEmpty { return f.t.t("day.freeDay") }
        let meets = items.filter { $0.kind == .meet }.count
        let evs = items.filter { $0.kind == .event }.count
        let shoots = items.filter { $0.kind == .shoot }.count
        var parts: [String] = []
        if shoots > 0 { parts.append(f.t.count("unit.shoot", shoots)) }
        if meets > 0 { parts.append(f.t.count("unit.meet", meets)) }
        if evs > 0 { parts.append(f.t.count("unit.event", evs)) }
        if items.contains(where: { $0.kind == .busy }) { parts.append(f.t.t("day.blockedTime")) }
        if busy > 0 { parts.append(f.t.t("day.busyFor", ["dur": f.durLabel(busy)])) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let pal = Palette(scheme)
        let raw = Self.text(items, f), s = raw.uppercased()
        Text(s)
            .font(webFont(10, 600)).tracking(1.2)
            .foregroundStyle(pal.ink4)
            .lineLimit(1)
            .shotNode("dp.load", text: raw)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 16, leading: 24, bottom: 7, trailing: 24))
    }
}

/// Список дня в месяце (веб `.plan-row`): время и имя одной строкой.
/// Предстоящая съёмка — начало и длительность; прошедшая — имя и отсчёт до
/// сдачи; встреча и событие — отрезок и слово.
struct PlannerDayList: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Binding var fan: FanTarget?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let items = f.items(on: app.planner.selected)
        VStack(spacing: 0) {
            PlannerLoadLabel(f: f, items: items)
            VStack(spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                    row(it, pal).shotNode("row.\(i)")
                }
                if items.isEmpty { free(pal) }
            }
            .padding(EdgeInsets(top: 8, leading: 24, bottom: 20, trailing: 24))
            .shotNode("line")
        }
    }

    private func row(_ it: DayItem, _ pal: Palette) -> some View {
        HStack(spacing: 10) {
            if let b = it.block {
                // Занятость тише съёмки (`.plan-row.busy`).
                Icon(b.kind.iconName, size: 17, line: 1.6).foregroundStyle(pal.ink4)
                Text(b.allDay ? f.t.t("day.allDay") : f.range(Double(it.start), Double(it.end)))
                    .font(webFont(14)).monospacedDigit().foregroundStyle(pal.ink4)
                Text(f.blockLabel(b)).font(webFont(15, 500)).foregroundStyle(pal.ink3).lineLimit(1)
                Spacer(minLength: 0)
            } else if let s = it.session {
                let soft = it.kind != .shoot
                let past = !soft && EventPhase.of(s, now: WallTime(day: f.today, minutes: app.nowMinute), manualEnd: false) == .after
                icon(s, it, pal)
                if !past {
                    Text(f.fmt(Double(it.start)) + (soft ? " – " + f.fmt(Double(it.end)) : ""))
                        .font(webFont(16)).monospacedDigit().foregroundStyle(pal.brass)
                }
                Text(name(s, it)).font(webFont(16, 500)).foregroundStyle(pal.ink).lineLimit(1)
                Spacer(minLength: 0)
                if soft {
                    Text(f.t.t(it.kind == .meet ? "plan.meet" : "plan.event").lowercased())
                        .font(webFont(12)).foregroundStyle(pal.ink)
                } else if past {
                    let st = app.deliveryStatus(s)
                    if let short = f.deliveryWords(st).short {
                        Text(short).font(webFont(12)).monospacedDigit()
                            .foregroundStyle(f.deliveryColor(st))
                            .padding(.horizontal, st.rank >= 3 ? 6 : 0).padding(.vertical, st.rank >= 3 ? 2 : 0)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(st.rank >= 3 ? f.deliveryColor(st).opacity(0.32) : .clear))
                            .padding(.trailing, st.rank >= 3 ? -2 : 0)
                    }
                } else {
                    Text(f.durShort(max(0, it.end - it.start))).font(webFont(12)).monospacedDigit().foregroundStyle(pal.ink4)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.sheet4))
        .contentShape(Rectangle())
        // Занятость — тапом в свой лист; запись — удержанием в веер (у
        // занятости веера нет, веб `if (b.dataset.b) return`).
        .modifier(RowAct(app: app, it: it, fan: $fan))
    }

    private func icon(_ s: Session, _ it: DayItem, _ pal: Palette) -> some View {
        Group {
            if it.kind == .meet { Icon("partner", size: 17, line: 1.6) }
            else if it.kind == .event { Icon("view_month", size: 17, line: 1.6) }
            else if let n = f.words.iconName(s) { Icon(n, size: 17, line: 1.6) }
            else { Icon(genre: s.genre?.rawValue ?? "", size: 17, line: 1.6) }
        }
        // Знак строки — всегда чернилами (`.pr-ic svg`): цвет в строке у времени.
        .foregroundStyle(pal.ink4)
    }

    private func name(_ s: Session, _ it: DayItem) -> String {
        let n = f.words.clientName(s)
        if !n.isEmpty { return n }
        return it.kind == .meet ? f.t.t("day.meet") : it.kind == .event ? f.t.t("day.event") : f.words.typeName(s)
    }

    /// Свободный день — не «пусто», а час, ради которого его открывают.
    private func free(_ pal: Palette) -> some View {
        let sky = f.sky(app.planner.selected)
        let say: String = if let a = sky.goldenB, let b = sky.blueB {
            f.t.t("day.goldenSpan", ["a": f.fmt(a), "b": f.fmt(b)])
        } else if let t = sky.goldenB ?? sky.set {
            f.t.t("week.goldenAt", ["t": f.fmt(t)])
        } else {
            f.t.t("day.freeDay")
        }
        return HStack(spacing: 10) {
            Icon("golden", size: 17).foregroundStyle(pal.brass)
            Text(say).font(webFont(13)).foregroundStyle(pal.ink3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.sheet4))
    }
}

/// Три действия дня (веб `#dayStates`) — в месяце, под списком. «Занять» —
/// лист занятости на весь выбранный день (22); формы съёмки и встречи —
/// итерации 23–24.
struct PlannerDayStates: View {
    let f: PlannerFacts
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        HStack(spacing: 6) {
            state(.add, "plan.shortShoot", on: true, ink: pal.brass, label: pal.ink, weight: 600, node: "st.shoot", pal)
            state(.meet, "plan.shortMeet", on: false, ink: pal.brass, label: pal.ink2, weight: 500, node: "st.meet", pal)
            state(.lock, "plan.shortBlock", on: false, ink: pal.ink5, label: pal.ink4, weight: 500, node: "st.block", pal)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }

    private func state(_ k: PlanGlyph.Kind, _ key: String, on: Bool, ink: Color, label: Color, weight: Int,
                       node: String, _ pal: Palette) -> some View {
        Button {
            if k == .lock { f.app.openBlockSheet(day: f.app.planner.selected) }
        } label: {
            VStack(spacing: 2) {
                PlanGlyph(kind: k)
                    .stroke(ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 18)
                Text(f.t.t(key)).font(webFont(11, weight)).foregroundStyle(label).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? pal.sheet4 : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(pal.hairline, lineWidth: 1))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode(node)
    }
}

/// Действие строки дня: занятость открывается тапом, запись держат для веера.
struct RowAct: ViewModifier {
    let app: AppModel
    let it: DayItem
    @Binding var fan: FanTarget?

    func body(content: Content) -> some View {
        if let b = it.block {
            content.onTapGesture { app.openBlockSheet(editing: b.id) }
        } else if let s = it.session {
            content.modifier(FanHold(id: s.id, fan: $fan))
        } else {
            content
        }
    }
}
