import SwiftUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

// Чужие календари призраками на ленте дня и в неделе (шаг 30.5, `docs/14`).
//
// Призрак — пунктирная полупрозрачная рамка цвета чернил (не латунь: съёмки латунные). Его нельзя тянуть, нельзя
// выделить, удержание на нём ничего не делает; тап на ленте дня открывает лист со сведениями (`GhostSheet`), в неделе строки раскрываются на месте.
// В месяце призраков нет (решение Алексея 22.10, «2А»).

// MARK: - Что читают виды

extension PlannerFacts {
    /// Части призраков по часам в сутках `d` (пояс — места приложения). Выключено — пусто.
    func ghostParts(on d: CivilDate) -> [GhostPart] {
        app.ghostsOn ? GhostDay.timed(on: d, zone: app.place.zone, ghosts: app.ghostList) : []
    }

    /// Призраки «на весь день», стоящие в сутках `d`.
    func ghostAllDay(on d: CivilDate) -> [Ghost] {
        app.ghostsOn ? GhostDay.allDay(on: d, ghosts: app.ghostList) : []
    }

    /// Название: пустое — «Без названия».
    func ghostTitle(_ g: Ghost) -> String { g.title.isEmpty ? t.t("ghost.untitled") : g.title }

    /// Время части на ленте: «10:00–11:45»; продолжение из вчера и уход в завтра называют свои края.
    func ghostRange(_ p: GhostPart) -> String { range(Double(p.start), Double(p.end)) }
}

// MARK: - Полоса призраков справа от съёмок

/// Раскладка призраков на ленте дня: свои колонки у правого края, ширина — от измеренной ширины ленты.
///
/// Съёмки, встречи и занятость остаются слева и сужаются **только рядом с призраком** (по высоте): день без призраков
/// и часы между ними рисуются как раньше, до пикселя. Колонок столько, сколько нужно самой плотной сцепке, но не
/// больше, чем влезает: полоса не занимает больше 40 % ленты (после черты часов), колонка — не уже `minColumn`.
/// Не влезло — лишние призраки сцепки схлопываются в один блок «+N», тап по нему открывает список.
struct GhostRail: Equatable {
    struct Cell: Identifiable, Equatable {
        let id: String
        let column: Int
        let top: Double
        let bottom: Double
        /// Один призрак — обычный блок; несколько — схлопнувшееся «+N».
        let parts: [GhostPart]
        var height: Double { bottom - top }
        var collapsed: Bool { parts.count > 1 }
    }

    let columns: Int
    let colWidth: CGFloat
    let cells: [Cell]

    /// Ширина всей полосы.
    var width: CGFloat { CGFloat(columns) * colWidth }

    /// На сколько сужается блок съёмки, занимающий по высоте `[top, bottom]`: только рядом с призраками. Блок, возле
    /// которого призраков нет, остаётся во всю ширину; рядом с одним левым — уже на одну колонку, не на всю полосу.
    func reserve(top: CGFloat, bottom: CGFloat) -> CGFloat {
        guard let c = cells.filter({ CGFloat($0.top) < bottom && CGFloat($0.bottom) > top }).map(\.column).min() else { return 0 }
        return CGFloat(columns - c) * colWidth
    }

    static let empty = GhostRail(columns: 0, colWidth: 0, cells: [])
    /// Уже колонка не читается: «Матч» ещё влезает, «Тренировка» уже переносится по слогам.
    static let minColumn: CGFloat = 56
    /// Доля ленты после черты часов, которую полоса не переступает.
    static let share: CGFloat = 0.4

    /// Сколько колонок влезает при этой ширине ленты (не меньше одной).
    static func capacity(width: CGFloat) -> Int {
        max(1, Int(((width - PlannerDayBody.lane) * share / minColumn).rounded(.down)))
    }

    /// `parts` — уже по началу (так отдаёт `GhostDay.timed`).
    static func layout(_ parts: [GhostPart], width: CGFloat) -> GhostRail {
        guard !parts.isEmpty, width > PlannerDayBody.lane else { return .empty }
        let cap = capacity(width: width)
        let top = parts.map { DayLanes.top($0.start) }
        let bot = parts.indices.map { top[$0] + max(DayLanes.minHeight, DayLanes.top(parts[$0].end) - top[$0]) }
        let placed = DayLanes.place(top: top, bottom: bot)
        var cells: [Cell] = []
        var used = 0
        let clusters = Dictionary(grouping: parts.indices, by: { placed[$0].cluster })
        for key in clusters.keys.sorted() {
            let idx = clusters[key] ?? []
            let cols = placed[idx[0]].columns
            if cols <= cap {
                used = max(used, cols)
                for k in idx { cells.append(Cell(id: parts[k].id, column: placed[k].column, top: top[k], bottom: bot[k], parts: [parts[k]])) }
            } else {
                used = max(used, cap)
                let keep = idx.filter { placed[$0].column < cap - 1 }
                let rest = idx.filter { placed[$0].column >= cap - 1 }
                for k in keep { cells.append(Cell(id: parts[k].id, column: placed[k].column, top: top[k], bottom: bot[k], parts: [parts[k]])) }
                cells.append(Cell(id: "more#" + rest.map { parts[$0].id }.joined(separator: "|"), column: cap - 1,
                                  top: rest.map { top[$0] }.min() ?? 0, bottom: rest.map { bot[$0] }.max() ?? 0,
                                  parts: rest.map { parts[$0] }))
            }
        }
        cells.sort { ($0.top, $0.column) < ($1.top, $1.column) }
        return GhostRail(columns: used, colWidth: (width - PlannerDayBody.lane) * share / CGFloat(cap), cells: cells)
    }

    /// Рамка блока в координатах ленты шириной `width`.
    func frame(of c: Cell, width w: CGFloat) -> CGRect {
        CGRect(x: w - self.width + CGFloat(c.column) * colWidth, y: CGFloat(c.top),
               width: colWidth - CGFloat(DayLanes.gap), height: CGFloat(c.height))
    }

    /// Рамка, в которую попадает точка `p` ленты, — палец лежит на призраке, а не на пустом часе.
    func hit(_ p: CGPoint, width w: CGFloat) -> Cell? {
        cells.first { frame(of: $0, width: w).contains(p) }
    }
}

/// Один блок полосы: пунктирная рамка, название и время.
struct GhostBlock: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    let cell: GhostRail.Cell
    let index: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let h = cell.height
        let first = cell.parts[0]
        // Строки по измеренной высоте блока: заголовок и время, а если места нет — только заголовок в столько
        // строк, сколько влезает.
        let showTime = !cell.collapsed && h >= 46
        let lines = max(1, Int((h - 8 - (showTime ? 13 : 0)) / 14))
        VStack(alignment: .leading, spacing: 1) {
            if cell.collapsed {
                Text("+\(cell.parts.count)").font(webFont(14, 600)).monospacedDigit().foregroundStyle(pal.ink3)
            } else {
                Text(f.ghostTitle(first.ghost)).font(webFont(11.5, 500)).foregroundStyle(pal.ink3).lineLimit(lines)
                if showTime {
                    // Узкая колонка: промежуток не влезает — остаётся начало, а не «10:00 – 1…».
                    ViewThatFits(in: .horizontal) {
                        Text(f.ghostRange(first)).fixedSize()
                        Text(f.fmt(Double(first.start))).fixedSize()
                    }
                    .font(webFont(10.5)).monospacedDigit().foregroundStyle(pal.ink5).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(GhostOutline(radius: 8, pal: pal))
        .contentShape(Rectangle())
        .onTapGesture { app.ghostSheet = GhostSheetTarget(ghosts: cell.parts.map(\.ghost)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cell.collapsed
            ? f.t.t("ghost.a11yMany", ["n": "\(cell.parts.count)"])
            : f.t.t("ghost.a11y", ["cal": first.ghost.calendarTitle, "name": f.ghostTitle(first.ghost), "when": f.ghostRange(first)]))
        .accessibilityAddTraits(.isButton)
        .shotNode("ghost.\(index)", text: cell.collapsed ? "+\(cell.parts.count)" : first.ghost.title)
    }
}

/// Вид призрака: еле заметная заливка и пунктир чернилами — «здесь что-то есть, но оно не твоё».
struct GhostOutline: ViewModifier {
    let radius: CGFloat
    let pal: Palette

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(pal.ink.opacity(0.04)))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(pal.ink.opacity(0.38), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
    }
}

// MARK: - «На весь день» над лентой

/// Тонкая полоса над лентой часов: события «на весь день» не ложатся на ленту и не закрывают её. До двух плашек
/// по ширине экрана, остальные — «+N».
struct GhostAllDayBand: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    let day: CivilDate
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let list = f.ghostAllDay(on: day)
        if !list.isEmpty {
            let pal = Palette(scheme)
            let shown = Array(list.prefix(2)), more = list.count - shown.count
            HStack(spacing: 6) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, g in
                    Button { app.ghostSheet = GhostSheetTarget(ghosts: [g]) } label: {
                        Text(f.ghostTitle(g)).font(webFont(12, 500)).foregroundStyle(pal.ink3).lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .modifier(GhostOutline(radius: 12, pal: pal))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(f.t.t("ghost.a11yDay", ["cal": g.calendarTitle, "name": f.ghostTitle(g)]))
                    .shotNode("ghost.day.\(i)", text: g.title)
                }
                if more > 0 {
                    Button { app.ghostSheet = GhostSheetTarget(ghosts: list) } label: {
                        Text("+\(more)").font(webFont(12, 600)).monospacedDigit().foregroundStyle(pal.ink3)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .modifier(GhostOutline(radius: 12, pal: pal))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(f.t.t("ghost.a11yMany", ["n": "\(list.count)"]))
                    .shotNode("ghost.day.more", text: "+\(more)")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .shotNode("ghost.band")
        }
    }
}

// MARK: - Неделя

/// Призраки дня в строке недели (30.5в, слово Алексея): слева время, потом пунктирная чёрточка и название; сначала
/// «на весь день», потом по часам. Больше трёх строк — две и «Ещё N ⌄»: тап раскрывает остальные тут же, в карточке
/// дня, «Свернуть ⌃» прячет обратно. Раскрытие — по дням, в памяти запуска. Листа из недели нет: строки не нажимаются.
struct GhostWeekRows: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    let day: CivilDate
    @Environment(\.colorScheme) private var scheme

    /// Столько строк призраков ставится сразу под съёмками: неделя не растёт без меры из-за рабочего календаря.
    static let rowCap = 3

    struct Row: Identifiable {
        let ghost: Ghost
        let time: String
        var id: String { ghost.id + time }
    }

    /// Что внизу списка: «Ещё N» (свёрнуто) или «Свернуть» (развёрнуто); `nil` — всё влезло, переключателя нет.
    enum Footer: Equatable { case more(Int), less }

    static func rows(_ f: PlannerFacts, _ day: CivilDate) -> [Row] {
        f.ghostAllDay(on: day).map { Row(ghost: $0, time: f.t.t("day.allDay")) }
            + f.ghostParts(on: day).map { Row(ghost: $0.ghost, time: f.ghostRange($0)) }
    }

    /// День без съёмок и без событий чужих календарей — только такой подписан «свободно». Призрак занятостью не считается
    /// нигде, кроме этой подписи (слово Алексея 30.5в).
    static func isFree(shoots: Int, _ f: PlannerFacts, _ day: CivilDate) -> Bool {
        shoots == 0 && rows(f, day).isEmpty
    }

    /// Какие строки видны и какой переключатель под ними.
    static func plan<T>(_ rows: [T], open: Bool) -> (shown: [T], toggle: Footer?) {
        guard rows.count > rowCap else { return (rows, nil) }
        if open { return (rows, .less) }
        let shown = Array(rows.prefix(rowCap - 1))
        return (shown, .more(rows.count - shown.count))
    }

    var body: some View {
        let rows = Self.rows(f, day)
        if !rows.isEmpty {
            let pal = Palette(scheme)
            let open = app.ghostWeekOpen.contains(day)
            let (shown, toggle) = Self.plan(rows, open: open)
            // Ширина колонки времени — по самому широкому промежутку, чтобы названия стояли ровно.
            let sample = f.range(Double(8 * 60 + 8), Double(20 * 60 + 20))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, r in
                    HStack(spacing: 8) {
                        ZStack(alignment: .leading) {
                            Text(sample).hidden()
                            Text(r.time)
                        }
                        .font(webFont(12.5)).monospacedDigit().foregroundStyle(pal.ink5).lineLimit(1).fixedSize()
                        VLine().stroke(pal.ink.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
                            .frame(width: 1, height: 15)
                        Text(f.ghostTitle(r.ghost)).font(webFont(13.5)).foregroundStyle(pal.ink3).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(f.t.t("ghost.a11y", ["cal": r.ghost.calendarTitle, "name": f.ghostTitle(r.ghost), "when": r.time]))
                    .shotNode("wk.ghost.\(i)", text: r.ghost.title)
                }
                if let toggle {
                    Button { app.toggleGhostWeek(day) } label: {
                        HStack(spacing: 5) {
                            Text(toggle == .less ? f.t.t("ghost.weekLess") : f.t.t("ghost.weekMore", ["n": "\(rows.count - shown.count)"]))
                            Icon("chevron", size: 11, line: 1.8).rotationEffect(.degrees(toggle == .less ? -90 : 90))
                            Spacer(minLength: 0)
                        }
                        .font(webFont(12.5)).foregroundStyle(pal.ink5)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .shotNode("wk.ghost.more", text: toggle == .less ? "less" : "more")
                }
            }
            .padding(.bottom, 2)
        }
    }
}

/// Вертикаль по центру — для пунктирной чёрточки.
private struct VLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}

// MARK: - Лист и вопрос

/// Лист призрака и вопрос «показывать другие календари?» — отдельным модификатором, чтобы корень не разбухал.
struct GhostPresenters: ViewModifier {
    @Bindable var app: AppModel
    let windowHeight: CGFloat

    func body(content: Content) -> some View {
        let t = app.lexicon
        content
            // При открытой форме или листе занятого времени призраков на экране нет.
            .sheet(item: Binding(get: { app.form == nil && app.blockSheet == nil ? app.ghostSheet : nil },
                                 set: { app.ghostSheet = $0 })) { d in
                GhostSheet(app: app, target: d, windowHeight: windowHeight)
            }
            // Прежде чем показать системный запрос к Календарю, объясняем, зачем.
            .alert(t.t("ghost.askT"), isPresented: $app.ghostAsk) {
                Button(t.t("ghost.askYes")) { app.answerGhostAsk(yes: true) }
                Button(t.t("ghost.askNo"), role: .cancel) { app.answerGhostAsk(yes: false) }
            } message: {
                Text(t.t("ghost.askM"))
            }
    }
}

// MARK: - Лист призрака

/// Что нажато на призраке на ленте дня: название, время, место, календарь. Только сведения: править и занимать нечем — событие чужое.
struct GhostSheet: View {
    @Bindable var app: AppModel
    let target: GhostSheetTarget
    let windowHeight: CGFloat
    @State private var contentHeight: CGFloat = 320
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let f = PlannerFacts(app: app, dark: scheme != .light)
        let t = f.t
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(pal.edge).frame(width: 38, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10).padding(.bottom, 18)
                if target.ghosts.count == 1, let g = target.ghosts.first {
                    one(g, f, pal)
                } else {
                    Text(t.t("ghost.listTitle")).font(.system(size: 19, weight: .semibold)).tracking(-0.2).foregroundStyle(pal.ink)
                        .shotNode("ghost.title")
                    Text(t.t("ghost.readOnly")).font(.system(size: 13)).foregroundStyle(pal.ink4).padding(.top, 5)
                    VStack(spacing: 0) {
                        ForEach(Array(target.ghosts.enumerated()), id: \.element.id) { i, g in
                            row(g, f, pal, index: i)
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .shotNode("ghost.sheet")
        .presentationDetents([.height(min(contentHeight, windowHeight * 0.86))])
        .presentationDragIndicator(.hidden)
    }

    // MARK: Одно событие

    private func one(_ g: Ghost, _ f: PlannerFacts, _ pal: Palette) -> some View {
        let t = f.t
        return VStack(alignment: .leading, spacing: 0) {
            Text(t.t("ghost.fromCal", ["cal": g.calendarTitle])).font(.system(size: 13)).foregroundStyle(pal.ink4)
                .shotNode("ghost.cal", text: g.calendarTitle)
            Text(f.ghostTitle(g)).font(.system(size: 19, weight: .semibold)).tracking(-0.2).foregroundStyle(pal.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
                .shotNode("ghost.title", text: g.title)
            Text(when(g, f)).font(.system(size: 15)).monospacedDigit().foregroundStyle(pal.ink2).padding(.top, 10)
                .shotNode("ghost.when")
            if let place = g.location {
                HStack(alignment: .top, spacing: 8) {
                    Icon("pin", size: 16, line: 1.5).foregroundStyle(pal.ink5).padding(.top, 1)
                    Text(place).font(.system(size: 15)).foregroundStyle(pal.ink3).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                .shotNode("ghost.place", text: place)
            }
            Text(t.t("ghost.readOnly")).font(.system(size: 13)).foregroundStyle(pal.ink5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
    }

    // MARK: Несколько событий

    private func row(_ g: Ghost, _ f: PlannerFacts, _ pal: Palette, index: Int) -> some View {
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.ghostTitle(g)).font(.system(size: 15, weight: .medium)).foregroundStyle(pal.ink).lineLimit(2)
                Text(when(g, f) + " · " + g.calendarTitle).font(.system(size: 12)).monospacedDigit().foregroundStyle(pal.ink4).lineLimit(2)
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(pal.hair2).frame(height: 1) }
        .shotNode("ghost.row.\(index)", text: g.title)
    }

    // MARK: Слова

    /// «24 окт. 2026 · 10:00–11:45»; через полночь — «24 окт. 2026, 22:00 – 25 окт. 2026, 06:00»; на весь день — дни.
    private func when(_ g: Ghost, _ f: PlannerFacts) -> String {
        let zone = app.place.zone
        func day(_ d: CivilDate) -> String { f.dates.dMonShortYear(f.date(d)) }
        if g.allDay, let a = g.firstDay {
            let b = g.lastDay ?? a
            return (a == b ? day(a) : day(a) + " – " + day(b)) + " · " + f.t.t("day.allDay")
        }
        let r = g.wallRange(in: zone)
        if r.start.day == r.end.day {
            return day(r.start.day) + " · " + f.range(Double(r.start.minutes), Double(r.end.minutes))
        }
        return day(r.start.day) + ", " + f.fmt(Double(r.start.minutes)) + " – " + day(r.end.day) + ", " + f.fmt(Double(r.end.minutes))
    }
}
