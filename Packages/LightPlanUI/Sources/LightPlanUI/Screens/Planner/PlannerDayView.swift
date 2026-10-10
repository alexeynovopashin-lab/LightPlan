import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Закреплённый блок дня (`.day-sticky.on`): неделя дат и сводка. Лента часов
/// едет под ним.
struct PlannerDaySticky: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    /// Разрез месяца (29.2а): лента дат — цель семи ячеек недели и прячется, пока они летят.
    let part: PartDay
    @Environment(\.colorScheme) private var scheme
    /// Зазор между датами недели.
    static let dateGap: CGFloat = 2

    var body: some View {
        let pal = Palette(scheme)
        VStack(spacing: 0) {
            HStack(spacing: Self.dateGap) {
                ForEach(Array(app.planner.week.enumerated()), id: \.element) { i, d in
                    date(d, pal).shotNode("dd.\(i)")
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { part.stripLaid($0) }
            .opacity(part.machine.stripHidden ? 0 : 1)
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
            withAnimation(PlannerDayBody.slide) { _ = app.planner.pickInStrip(d) }
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
    @Binding var fan: FanTarget?
    /// Выделение и жест времени рукой (29а).
    let grip: DayGrip
    @Environment(\.colorScheme) private var scheme
    /// Открытое меню часа: номер часа и минута с получасом (веб `.armed`).
    @State private var armed: (hour: Int, at: Int)?
    /// Ширина ленты — для рамок событий под пальцем.
    @State private var laneWidth: CGFloat = 0

    /// Высота заголовка загрузки: поле 16 + строка 12 + поле 7.
    static let loadHeight: CGFloat = 35
    /// Поле ленты сверху (`--dl-top`).
    static let lineTop: CGFloat = 8
    static let hourH = CGFloat(DayLanes.hourHeight)
    /// Колонка часов кончается на 70 pt от края экрана: там начинаются блоки.
    static let lane: CGFloat = 70
    /// Середина оси — 24 поля + 46 часов + 9.
    static let axis: CGFloat = 79
    /// Въезд ленты при смене дня (веб `.day-line.slide-l/-r`): 0,22 с, E1 `cubic-bezier(0.25, 1, 0.4, 1)`.
    static let slide = Animation.timingCurve(0.25, 1, 0.4, 1, duration: 0.22)

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
                .onChange(of: d) { _, _ in
                    armed = nil; grip.deselect(); closeLaneFan()
                    // Лента въехала — направление прочитано, гасим (веб обнуляет `dayShift` после каждого въезда).
                    _ = app.planner.consumeDayShift()
                }
                .onChange(of: items.map(\.id)) { _, ids in
                    // Выделенное ушло с ленты — удалено или перенесено формой на другой день.
                    if let sel = grip.selected, !ids.contains(sel + "@shoot"), !ids.contains(sel + "@meet"),
                       !ids.contains(sel + "@event") { grip.deselect() }
                }
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
                    slot(h, pal: pal, sky: sky, hushed: isToday && Self.hushed(h, now: nowMin),
                         half: armed?.hour == h ? armed!.at % 60 : nil)
                        .shotNode("slot.\(h)")
                }
            }
            .padding(.horizontal, 24)
            // Блоки. Выделенное — над соседями, поднятое — ещё выше (веб `.sel` 2, `.lift` 3).
            ForEach(DayLanes.drawOrder(items), id: \.self) { i in
                event(items[i], index: i, slot: slots[i], pal: pal)
                    .zIndex(isSelected(items[i]) ? (grip.live?.lifted == true ? 3 : 2) : 0)
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
            if let k = selectedIndex(items) { handles(items[k], slot: slots[k], pal: pal).zIndex(4) }
            if let l = grip.live, l.moved { dragMark(l, pal).zIndex(5) }
            if let a = armed { slotMenu(a, pal).zIndex(6) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 25 * Self.hourH, alignment: .top)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(plannerFanSpace)) } action: {
            grip.laneFrame = $0
            laneWidth = $0.width
        }
        .modifier(DayGripMod(gesture: gripGesture(items, slots)))
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

    /// Час сетки. Тап по верхней половине — «:00», по нижней — «:30» (веб: на
    /// получас пальцем попадают, точнее правят в форме); повторный — закрыть.
    private func slot(_ h: Int, pal: Palette, sky: SolarDay, hushed: Bool, half: Int?) -> some View {
        let label = String(format: "%02d:00", h % 24)
        return HStack(spacing: 0) {
                Text(label).font(webFont(12)).tracking(0.2).monospacedDigit()
                    .foregroundStyle(half == 0 ? pal.brassDeep : pal.ink7)
                    .opacity(hushed ? 0 : 1)
                    .frame(width: 46, height: Self.hourH, alignment: .topLeading)
                    .offset(y: -6)
                // Ось: своя полоса у каждого часа, от цвета его начала к цвету конца.
                let a = h >= 24 ? 1439.0 : Double(h % 24 * 60), b = h >= 24 ? 1439.0 : a + 59
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [Self.phase(a, sky), Self.phase(b, sky)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3)
                    .frame(width: 18)
                Rectangle().fill(half == 30
                        ? AnyShapeStyle(LinearGradient(stops: [.init(color: .clear, location: 0.5),
                                                               .init(color: Color(hex: 0xE2A44C, alpha: 0.10), location: 1)],
                                                       startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color.clear))
                    .overlay(alignment: .top) { Rectangle().fill(half == 0 ? pal.brassDark : pal.hairline).frame(height: 1) }
                    .overlay {
                        Line().stroke(half == 30 ? pal.brassDark : pal.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .opacity(half == 30 ? 1 : 0.55)
                            .frame(height: 1)
                    }
                    .padding(.leading, 10)
            }
            .frame(height: Self.hourH)
            .contentShape(Rectangle())
            .onTapGesture { p in
                // Касание после сдвига или снявшее выделение меню часа не открывает.
                if grip.swallows { DayGripLog.note("swallow slot \(h)"); return }
                if armed?.hour == h { armed = nil; return }
                armed = (h, h * 60 + (p.y > Self.hourH / 2 ? 30 : 0))
            }
    }

    /// Меню часа (`.slot-menu`): время и три действия под выбранным часом; у
    /// последних часов опустить некуда — встаёт над ним. Сетку не сдвигает.
    private func slotMenu(_ a: (hour: Int, at: Int), _ pal: Palette) -> some View {
        let top = Self.menuTop(hour: a.hour)
        let acts: [(String, String, SlotAct)] = [("camera", "day.actShoot", .shoot), ("guests", "day.actMeet", .meet),
                                                 ("lock", "day.actBusy", .busy)]
        return HStack(spacing: 8) {
            Text(f.fmt(Double(a.at % 1440))).font(webFont(13, 650)).monospacedDigit().foregroundStyle(pal.brass)
            ForEach(acts, id: \.1) { ic, key, act in
                Button {
                    armed = nil
                    DayGripLog.note("slot menu \(act) at=\(a.at)")
                    app.openFromSlot(act, day: app.planner.selected, at: a.at)
                } label: {
                    VStack(spacing: 4) {
                        Icon(ic, size: 19, line: 1.5).foregroundStyle(pal.brass)
                        Text(f.t.t(key)).font(webFont(11)).foregroundStyle(pal.ink3).lineLimit(1)
                    }
                    .padding(.vertical, 9).padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.sheet))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4).padding(.bottom, 8)
        .background(pal.surface)
        .padding(.leading, 24 + 64).padding(.trailing, 24)
        .padding(.top, top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static let menuH: CGFloat = 66
    /// Верх меню часа: под часом, у последних часов — над ним.
    nonisolated static func menuTop(hour: Int) -> CGFloat {
        let gridH = 25 * hourH, below = CGFloat(hour + 1) * hourH
        return below + menuH > gridH ? max(0, CGFloat(hour) * hourH - menuH) : below
    }

    /// Рамка меню часа на ленте: касание в ней — кнопкам меню, не жесту ленты.
    nonisolated static func menuFrame(hour: Int, width: CGFloat) -> CGRect {
        CGRect(x: 24 + 64, y: menuTop(hour: hour), width: max(0, width - 24 - 64 - 24), height: menuH)
    }

    /// Час и получас под точкой ленты — как у тапа: верх часа «:00», низ «:30».
    nonisolated static func slotAt(y: CGFloat) -> (hour: Int, at: Int) {
        let h = min(24, max(0, Int((y / hourH).rounded(.down))))
        return (h, h * 60 + (y - CGFloat(h) * hourH > hourH / 2 ? 30 : 0))
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
        let span = shown(it)
        let sel = isSelected(it), lifted = sel && grip.live?.lifted == true
        return GeometryReader { geo in
            let r = Self.rect(start: span.start, end: span.end, slot: slot, width: geo.size.width)
            eventBody(it, index: index, height: r.height, cols: slot?.columns ?? 1, sel: sel, pal: pal)
                .frame(width: r.width, height: r.height, alignment: .topLeading)
                // Поднятое едет поверх сетки, а не прорастает сквозь неё: подложка
                // непрозрачная и тень `0 8 22 rgba(0,0,0,.35)` — тёмная в обеих темах.
                .background(lifted ? pal.surface : .clear)
                .clipped()
                .shadow(color: .black.opacity(lifted ? 0.35 : 0), radius: 11, y: 8)
                .contentShape(Rectangle())
                .modifier(RowAct(app: app, it: it, fan: $fan, grip: grip, lane: Self.grabbable(it)))
                .position(x: r.midX, y: r.midY)
        }
        .frame(height: 25 * Self.hourH)
        .allowsHitTesting(true)
    }

    /// Рамка блока на ленте (веб: `top`, `height` не меньше 34, колонки сцепки
    /// от черты в 70 pt).
    nonisolated static func rect(start: Int, end: Int, slot: DayLanes.Slot?, width w: CGFloat) -> CGRect {
        let cols = slot?.columns ?? 1, col = slot?.column ?? 0
        let top = top(Double(start))
        let hgt = max(CGFloat(DayLanes.minHeight), self.top(Double(end)) - top)
        let x = cols > 1 ? lane + (w - lane) * CGFloat(col) / CGFloat(cols) : lane
        let width = cols > 1 ? (w - lane) / CGFloat(cols) - CGFloat(DayLanes.gap) : w - lane
        return CGRect(x: x, y: top, width: width, height: hgt)
    }

    private func eventBody(_ it: DayItem, index: Int, height hgt: CGFloat, cols: Int, sel: Bool, pal: Palette) -> some View {
        let busy = it.kind == .busy, soft = it.kind == .meet || it.kind == .event
        let ink = pal.ink
        let (fill, stop, topA, botA): (Color, Double, Double, Double) = busy ? (ink, 0.70, 0.12, 0.08)
            : soft ? (ink, 0.78, 0.24, 0.12) : (Color(hex: 0xE2A44C), 0.92, 0.55, 0.30)
        // Выделенное (`.dl-ev.sel`): обе кромки — полной латунью (у встречи и события —
        // чернилами .40), заливка — та же, что под пальцем.
        let bg: LinearGradient = busy || soft
            ? LinearGradient(stops: [.init(color: fill.opacity(busy ? 0.08 : sel ? 0.20 : 0.10), location: 0),
                                     .init(color: fill.opacity(0), location: stop)], startPoint: .leading, endPoint: .trailing)
            : LinearGradient(stops: [.init(color: fill.opacity(sel ? 0.26 : 0.16), location: 0),
                                     .init(color: fill.opacity(sel ? 0.09 : 0.05), location: 0.58),
                                     .init(color: fill.opacity(0), location: 0.92)], startPoint: .leading, endPoint: .trailing)
        let edgeTop: Color = sel ? (soft ? ink.opacity(0.40) : pal.brass) : (busy || soft ? ink : fill).opacity(topA)
        let edgeBot: Color = sel ? (soft ? ink.opacity(0.40) : pal.brass) : (busy || soft ? ink : fill).opacity(botA)
        let tight = hgt < Self.hourH, room = hgt >= 2 * Self.hourH
        let (title, said, due) = words(it)
        var sub = said
        // Пока тянут, подпись называет время — и у встречи: сейчас вопрос «когда», а не «что».
        if let l = grip.live, l.moved, it.session?.id == l.id, !it.fromYesterday {
            sub = f.fmt(Double(l.start)) + " – " + f.fmt(Double(l.end))
        }
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
        .overlay(alignment: .top) { Rectangle().fill(edgeTop).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(edgeBot).frame(height: 1) }
        .contentShape(Rectangle())
        .shotNode("ev.\(index)")
    }

    // MARK: Время рукой (29а)

    /// Берётся ли блок пальцем: запись этих суток, не занятость и не продолжение
    /// ночной съёмки из вчера (её начало лежит в других сутках). Непустую
    /// съёмку удержание тоже берёт — для ручек и веера («матрёшка»).
    nonisolated static func grabbable(_ it: DayItem) -> Bool {
        it.kind != .busy && it.session != nil && !it.fromYesterday
    }

    private func isSelected(_ it: DayItem) -> Bool {
        Self.grabbable(it) && grip.selected != nil && it.session?.id == grip.selected
    }

    private func selectedIndex(_ items: [DayItem]) -> Int? {
        grip.selected == nil ? nil : items.firstIndex(where: isSelected)
    }

    /// Время блока на ленте: у того, что ведёт палец, — время под пальцем
    /// (конец — не дальше полуночи этих суток), у остальных — записанное.
    private func shown(_ it: DayItem) -> (start: Int, end: Int) {
        if let l = grip.live, Self.grabbable(it), it.session?.id == l.id { return (l.start, min(1440, l.end)) }
        return (it.start, it.end)
    }

    /// Ручки выделенного (`.dl-selbox`): начало — точка на верхней кромке
    /// справа, конец — на нижней слева, как в календаре телефона. Точка 10 pt,
    /// ловит квадрат 36×36 вокруг неё (`gripDown`). У съёмки через полночь
    /// нижней нет — конец лежит на другом дне.
    private func handles(_ it: DayItem, slot: DayLanes.Slot?, pal: Palette) -> some View {
        let span = shown(it)
        let ink = it.kind == .shoot ? pal.brass : pal.ink3
        return GeometryReader { geo in
            let r = Self.rect(start: span.start, end: span.end, slot: slot, width: geo.size.width)
            ZStack(alignment: .topLeading) {
                // Узел снимка — поле касания 36×36, как `.dl-h` веба.
                handleDot(ink, pal).frame(width: 36, height: 36).shotNode("grip.a").position(x: r.maxX - 22, y: r.minY)
                if !it.intoTomorrow {
                    handleDot(ink, pal).frame(width: 36, height: 36).shotNode("grip.b").position(x: r.minX + 22, y: r.maxY)
                }
            }
        }
        .frame(height: 25 * Self.hourH)
        .allowsHitTesting(false)
    }

    private func handleDot(_ ink: Color, _ pal: Palette) -> some View {
        Circle().fill(pal.surface)
            .overlay(Circle().strokeBorder(ink, lineWidth: 2))
            .frame(width: 10, height: 10)
    }

    /// Капсула на оси — минута той кромки, которую ведёт палец (`.dl-mark.drag`):
    /// та же форма, что у «сейчас», только без линии через ленту.
    private func dragMark(_ l: DayGrip.Live, _ pal: Palette) -> some View {
        let at = l.mode == .end ? l.end : l.start
        return Text(f.fmt(Double(at)))
            .font(webFont(12)).tracking(0.2).monospacedDigit()
            .foregroundStyle(pal.onBrass)
            .padding(.horizontal, 8).frame(height: 19)
            .background(Capsule().fill(pal.brass))
            .shotNode("grip.mark")
            .padding(.leading, 12)
            .padding(.top, Self.top(Double(min(1440, at))) - 9.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
    }

    /// Веер ленты (`dlOpenFan`) — тот же «Заполнить / Удалить», но без затемнения
    /// и ниже на 14, чтобы не лечь на нижнюю ручку.
    private func openLaneFan(_ id: String, _ items: [DayItem], _ slots: [DayLanes.Slot?]) {
        guard let k = items.firstIndex(where: { Self.grabbable($0) && $0.session?.id == id }) else { return }
        let span = shown(items[k])
        let r = Self.rect(start: span.start, end: span.end, slot: slots[k], width: laneWidth)
        fan = FanTarget(id: id, anchor: r.offsetBy(dx: grip.laneFrame.minX, dy: grip.laneFrame.minY), lane: true)
    }

    private func closeLaneFan() {
        if fan?.lane == true { fan = nil }
    }

    /// Жест ленты: что под пальцем на касании, подъём, ход, отпускание.
    private func gripGesture(_ items: [DayItem], _ slots: [DayLanes.Slot?]) -> DayGripGesture {
        DayGripGesture(
            down: { p, stamp in gripDown(p, stamp, items, slots) },
            began: { _ in gripBegan(items, slots) },
            moved: { p in gripMoved(p) },
            ended: { cancelled in gripEnded(cancelled, items, slots) },
            reset: { if !grip.armed { grip.hand = nil; grip.slotHold = nil } },
            autoScroll: { grip.live != nil })
    }

    /// Касание ленты (веб `pointerdown` документа + `dlGrip` + ручки). Любое
    /// касание здесь закрывает веер ленты (сам веер лежит выше и сюда не
    /// попадает). Выделено что-то и палец мимо него — выделение снимается, и
    /// тап меню часа или чужой карточки не открывает.
    private func gripDown(_ p: CGPoint, _ stamp: TimeInterval, _ items: [DayItem],
                          _ slots: [DayLanes.Slot?]) -> DayGripStart {
        grip.laneTouch = stamp
        grip.hand = nil
        grip.slotHold = nil
        closeLaneFan()
        let w = laneWidth
        // Меню часа лежит над лентой: его кнопки жест ленты не трогает.
        if let a = armed, Self.menuFrame(hour: a.hour, width: w).contains(p) {
            DayGripLog.note("down x=\(Int(p.x)) y=\(Int(p.y)) menu")
            return .none
        }
        var deselected = false
        if let k = selectedIndex(items) {
            let it = items[k], span = shown(it)
            let r = Self.rect(start: span.start, end: span.end, slot: slots[k], width: w)
            func spot(_ x: CGFloat, _ y: CGFloat) -> CGRect { CGRect(x: x - 18, y: y - 18, width: 36, height: 36) }
            DayGripLog.note("down x=\(Int(p.x)) y=\(Int(p.y)) sel=\(it.session?.id ?? "") box=\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width))x\(Int(r.height))")
            if spot(r.maxX - 22, r.minY).contains(p) { return take(it, .start, hold: false, p) }
            if !it.intoTomorrow, spot(r.minX + 22, r.maxY).contains(p) { return take(it, .end, hold: false, p) }
            // Выделенное тянется за тело сразу; непустую съёмку — снова только удержанием.
            if r.contains(p) { return take(it, .move, hold: it.session.map { Nest.span(of: $0) != nil } ?? true, p) }
            grip.deselect()
            grip.swallowTill = DayGrip.clock + 0.45
            deselected = true
            DayGripLog.note("deselect lane")
        }
        // Верхний блок под пальцем решает: занятость или вчерашний хвост сверху
        // палец не отдают тому, что под ними.
        for i in DayLanes.drawOrder(items).reversed() {
            let it = items[i]
            guard Self.rect(start: it.start, end: it.end, slot: slots[i], width: w).contains(p) else { continue }
            if !Self.grabbable(it) { DayGripLog.note("down x=\(Int(p.x)) y=\(Int(p.y)) none(\(it.kind.rawValue))"); return .none }
            return take(it, .move, hold: true, p)
        }
        // Пустой час: удержание открывает меню часа, как тап (багфикс 10.10 — раньше
        // удержание не делало ничего). Касание, снявшее выделение, — нет.
        if deselected { DayGripLog.note("down x=\(Int(p.x)) y=\(Int(p.y)) none"); return .none }
        grip.slotHold = Self.slotAt(y: p.y)
        DayGripLog.note("down x=\(Int(p.x)) y=\(Int(p.y)) slot \(grip.slotHold!.at)")
        return .slot
    }

    private func take(_ it: DayItem, _ mode: DayDrag.Mode, hold: Bool, _ p: CGPoint) -> DayGripStart {
        // Время — из самой записи, а не из нарисованной ленты: касание сразу после
        // сдвига приходит раньше перерисовки и взяло бы прежнее время (замер 29а).
        guard let id = it.session?.id, let s = app.sessions.first(where: { $0.id == id }),
              DayDrag.grip(s, fromYesterday: it.fromYesterday) != .none else { return .none }
        let nest = Nest.span(of: s)
        grip.hand = DayGrip.Hand(id: s.id, mode: mode, pinned: nest != nil && mode == .move, hold: hold,
                                 a0: s.start, b0: s.endMinute, nest: nest, step: app.dayDragStep, y0: p.y)
        DayGripLog.note("take \(s.id) \(mode) \(hold ? "hold" : "now")\(nest != nil ? " nest" : "") x=\(Int(p.x)) y=\(Int(p.y)) \(s.start)-\(s.endMinute)")
        return hold ? .hold : .now
    }

    /// Подъём (веб `dlArm`). Удержание выделяет и щёлкает; непустую съёмку не
    /// поднимает — ручки и веер встают сразу.
    private func gripBegan(_ items: [DayItem], _ slots: [DayLanes.Slot?]) {
        if grip.hand == nil, let s = grip.slotHold {
            grip.armed = true
            grip.swallowTill = .infinity
            grip.tapLift()
            armed = s
            DayGripLog.note("slot hold \(s.at)")
            return
        }
        guard let h = grip.hand else { return }
        grip.armed = true
        grip.swallowTill = .infinity
        if h.hold {
            grip.selected = h.id
            grip.tapLift()
        }
        if h.pinned {
            openLaneFan(h.id, items, slots)
            return
        }
        grip.live = DayGrip.Live(id: h.id, mode: h.mode, start: h.a0, end: h.b0, lifted: h.hold)
    }

    /// Ход пальца (веб `dlTrack`): время — по пути от точки касания на ленте;
    /// лента, уехавшая автопрокруткой, уже учтена в точке.
    private func gripMoved(_ p: CGPoint) {
        guard let h = grip.hand, !h.pinned, var l = grip.live else { return }
        let r = DayDrag.track(h.mode, a0: h.a0, b0: h.b0, minutes: Double((p.y - h.y0) / Self.hourH * 60),
                              step: h.step, nest: h.nest)
        guard r.start != l.start || r.end != l.end else { return }
        if !l.moved {
            l.moved = true
            l.lifted = true
            closeLaneFan()
        }
        l.start = r.start
        l.end = r.end
        grip.live = l
        grip.tapNotch()
        DayGripLog.note("move dy=\(String(format: "%.1f", p.y - h.y0)) -> \(l.start)-\(l.end)")
    }

    /// Отпускание (веб `dlUp`). Двигали — запись и след; удержали на месте —
    /// веер; тап по выделенному — карточка. Касание отняла система — ничего не
    /// пишем. После жеста тап 0,45 с не открывает ни карточку, ни меню часа.
    private func gripEnded(_ cancelled: Bool, _ items: [DayItem], _ slots: [DayLanes.Slot?]) {
        if grip.hand == nil, grip.slotHold != nil {
            // Меню уже открыто удержанием; отпускание его не закрывает тапом часа.
            grip.slotHold = nil
            grip.armed = false
            grip.armedEnd = DayGrip.clock
            grip.swallowTill = DayGrip.clock + 0.45
            return
        }
        guard let h = grip.hand else { return }
        let l = grip.live
        grip.hand = nil
        grip.armed = false
        grip.armedEnd = DayGrip.clock
        grip.swallowTill = DayGrip.clock + 0.45
        if cancelled { grip.live = nil; DayGripLog.note("cancel \(h.id)"); return }
        if let l, l.moved {
            let ok = app.moveOnDay(id: h.id, start: l.start, end: l.end)
            DayGripLog.note("commit \(h.id) \(h.a0)-\(h.b0) -> \(l.start)-\(l.end) \(ok)")
            grip.live = nil
            return
        }
        grip.live = nil
        if h.pinned { DayGripLog.note("release pinned"); return }
        if h.hold { openLaneFan(h.id, items, slots); DayGripLog.note("fan \(h.id)") }
        else if h.mode == .move { DayGripLog.note("card \(h.id)"); withAnimation(overlaySlide) { app.openCard(id: h.id) } }
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
        let top = Self.top(Double(shown(it).start))
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

/// Жест ленты подключается только на iOS: на Mac ленту листают колесом, делить нечего.
private struct DayGripMod: ViewModifier {
    let gesture: DayGripGesture
    func body(content: Content) -> some View {
        #if os(iOS)
        content.gesture(gesture)
        #else
        content
        #endif
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
