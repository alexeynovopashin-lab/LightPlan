import SwiftUI
import LightPlanCore

/// Экран «Съёмки» — порт `#s-plan` веба (итерация 21): месяц, неделя, день.
///
/// Три вида читают одно состояние (`AppModel.planner`, веб `calScope` +
/// `calSel` + `calMonth`). Шапка закреплена и лежит на стекле, как у веба
/// (`position: sticky` + `backdrop-filter`); в дне к ней прилипают даты недели
/// и сводка (`.day-sticky.on`), а лента часов едет под ними.
///
/// Заголовок открывает ленту года, статистика и поиск — свои слои поверх
/// (итерация 22, `PlannerLayers`); удержание съёмки — веер «Заполнить /
/// Удалить». Тап по съёмке (→ карточка, 25) пока ничего не открывает. Веер видов и меню часа — виды веба на встроенном стекле, не
/// системные меню (NEXT_SESSION: «не системные компоненты»); их движение —
/// итерация 29.
public struct PlannerScreenView: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var position = ScrollPosition(edge: .top)
    /// Наводка ленты на 09:00 — одна на день (веб `dayScrollDay`).
    @State private var aimedDay: CivilDate?
    /// Веер видов открыт (веб `#scopeMenu`).
    @State private var scopeOpen = false
    /// Слои года, статистики и поиска (итерация 22).
    @State private var nav = PlannerNav()
    /// Веер удержанной записи.
    @State private var fan: FanTarget?

    public init(app: AppModel) { self.app = app }

    public var body: some View {
        let pal = Palette(scheme)
        let f = PlannerFacts(app: app, dark: scheme != .light)
        let st = app.planner
        ScrollView {
            VStack(spacing: 0) {
                switch st.scope {
                case .month: PlannerMonthBody(app: app, f: f, fan: $fan)
                case .week: PlannerWeekBody(app: app, f: f)
                case .day: PlannerDayBody(app: app, f: f, fan: $fan)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollPosition($position)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                PlanTop(app: app, f: f, scopeOpen: $scopeOpen, nav: nav)
                if st.scope == .day { PlannerDaySticky(app: app, f: f) }
                if st.scope != .day, st.isAway(from: f.today) { nowBack(pal, f) }
            }
            .background {
                Rectangle().fill(pal.bar).glassEffect(.regular, in: Rectangle())
                    .padding(.horizontal, -4).padding(.top, -4)
                    .ignoresSafeArea(edges: .top)
            }
        }
        .overlay(alignment: .bottom) {
            // В дне возврат висит капсулой над панелью (`.now-back.day-float`).
            if st.scope == .day, st.isAway(from: f.today) {
                Button { app.planner.goToday(f.today) } label: {
                    Text(f.t.t("today.backToday")).font(webFont(12.5)).foregroundStyle(pal.brassDeep)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)
                .shotNode("plan.now")
                .padding(.bottom, 12)
            }
        }
        .overlay(alignment: .topLeading) {
            if scopeOpen { scopeMenu(pal, f) }
        }
        .background(pal.surface.ignoresSafeArea())
        .simultaneousGesture(swipe)
        .coordinateSpace(name: plannerFanSpace)
        .overlay { EventFan(app: app, f: f, fan: $fan) }
        .overlay { PlannerLayers(app: app, f: f, nav: nav) }
        .onAppear { openStartLayer() }
        .onChange(of: nav.statsOpen || nav.searchOpen, initial: true) { _, open in app.plannerPageOpen = open }
        .onChange(of: st.scope, initial: true) { _, _ in aim() }
        .onChange(of: st.selected) { _, _ in aim() }
        // Смена вкладки закрывает слои (веб: `.overlay-right.open` и прочие).
        .onChange(of: app.tab) { _, _ in
            var off = Transaction()
            off.disablesAnimations = true
            withTransaction(off) {
                nav.lentaOpen = false; nav.year12Open = false
                nav.statsOpen = false; nav.searchOpen = false
                fan = nil
            }
        }
    }

    /// Слой при запуске сценария снимка (22): `LPShotSheet year | year12 |
    /// stats | search` — как тап по заголовку, «Год целиком» или кнопкам шапки.
    private func openStartLayer() {
        guard let layer = app.startChapter else { return }
        let month = app.planner.month
        switch layer {
        case "year": nav.openLenta(from: month)
        case "year12": nav.openLenta(from: month); nav.year12Open = true
        case "stats": nav.year = month.year; nav.statsOpen = true
        case "search": nav.searchOpen = true
        default: return
        }
        app.startChapter = nil
    }

    /// Веер видов (`.scope-menu`): под кнопкой вида на 8 pt, три строки —
    /// галочка текущего, знак, имя. Тап мимо закрывает.
    private func scopeMenu(_ pal: Palette, _ f: PlannerFacts) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                .onTapGesture { scopeOpen = false }
            VStack(spacing: 0) {
                ForEach(CalScope.allCases, id: \.self) { s in
                    let on = s == app.planner.scope
                    Button {
                        scopeOpen = false
                        withAnimation(.snappy(duration: 0.25)) { app.planner.setScope(s) }
                    } label: {
                        HStack(spacing: 10) {
                            Icon("check", size: 16, line: 2.2).foregroundStyle(pal.brass).opacity(on ? 1 : 0)
                            Icon(PlanTop.icon(s), size: 19, line: 1.5).foregroundStyle(on ? pal.ink : pal.ink4)
                            Text(f.t.t(PlanTop.menuKey(s))).font(webFont(15)).foregroundStyle(pal.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .frame(minWidth: 208, alignment: .leading)
            .fixedSize()
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.sheetGlass))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.55), radius: 20, y: 18)
            .padding(.leading, 16)
            .padding(.top, 12 + 44 + 8)
            .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
        }
    }

    /// «↺ сегодня» строкой под шапкой в месяце и неделе (`.now-back.show`).
    private func nowBack(_ pal: Palette, _ f: PlannerFacts) -> some View {
        Button { app.planner.goToday(f.today) } label: {
            Text(f.t.t("today.backToday")).font(webFont(12.5)).foregroundStyle(pal.brass)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
        .shotNode("plan.now")
    }

    /// Свайп по экрану (веб: |dx| ≥ 60, |dy| ≤ 40) — листает вид.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { g in
                let dx = g.translation.width, dy = g.translation.height
                guard abs(dx) >= 60, abs(dy) <= 40 else { return }
                withAnimation(.snappy(duration: 0.22)) { app.planner.step(dx < 0 ? 1 : -1) }
            }
    }

    /// Первый показ дня ставит 09:00 на 10 pt ниже закреплённого блока (веб:
    /// `target.top − sticky.bottom − 10`). Сверху ленты — заголовок загрузки
    /// (35) и поле ленты (8), час — 38. Наводка одна на день и смену вида
    /// переживает (веб `dayScrollDay` не сбрасывается): вернувшись в тот же
    /// день из недели, лента стоит там, куда её привела смена вида.
    private func aim() {
        let st = app.planner
        guard st.scope == .day else { position.scrollTo(edge: .top); return }
        guard aimedDay != st.selected else { return }
        aimedDay = st.selected
        position.scrollTo(y: PlannerDayBody.loadHeight + PlannerDayBody.lineTop + 9 * DayLanes.hourHeight - 10)
    }
}

// MARK: - Шапка

/// `.plan-top`: вид слева (44), заголовок по центру, три действия справа
/// (по 34 через 8). Поле сверху — 12 от выреза, снизу 6.
private struct PlanTop: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Binding var scopeOpen: Bool
    let nav: PlannerNav
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let st = app.planner
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { scopeOpen.toggle() }
            } label: {
                Icon(Self.icon(st.scope), size: 21, line: 1.6)
                    .foregroundStyle(pal.brass)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(pal.sheet))
            }
            .buttonStyle(.plain)
            .shotNode("plan.scope")
            .accessibilityLabel(f.t.t("plan.viewPick"))

            Button {
                withAnimation(overlaySlide) { nav.openLenta(from: app.planner.month) }
            } label: {
                // Шеврон веба стоит в строке с полями −5 и −3 и пробелом
                // перед словом (`.pt-chev`): группа центрируется со сдвигом.
                HStack(spacing: 3.9) {
                    Icon("chevron", size: 16, line: 1.6)
                        .rotationEffect(.degrees(180))
                        .foregroundStyle(pal.ink4)
                        .shotNode("plan.chev")
                        .padding(.leading, -5).padding(.trailing, -3)
                    Text(title)
                        .font(webFont(18, 650)).tracking(-0.3)
                        .foregroundStyle(pal.ink)
                        .lineLimit(1)
                        .shotNode("plan.title", text: title)
                }
                .padding(4)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button { app.openForm(day: app.planner.selected) } label: { action(.add, pal.brass, "plan.add") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(f.t.t("plan.newShoot"))
                Button {
                    nav.year = app.planner.month.year
                    withAnimation(statsSlide) { nav.statsOpen = true }
                } label: { action(.stats, pal.brass, "plan.stats") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(f.t.t("plan.stats"))
                Button { withAnimation(overlaySlide) { nav.searchOpen = true } } label: { action(.search, pal.ink, "plan.search") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(f.t.t("plan.search"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func action(_ k: PlanGlyph.Kind, _ c: Color, _ node: String) -> some View {
        PlanGlyph(kind: k)
            .stroke(c, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            .frame(width: 22, height: 22)
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
            .shotNode(node)
    }

    /// Заголовок по виду (веб `setPlanTitle`): год — только чужой.
    private var title: String {
        let st = app.planner, d = f.dates, now = f.today
        func yr(_ c: CivilDate) -> String { c.year == now.year ? "" : " \(c.year)" }
        switch st.scope {
        case .day:
            return d.dMon(f.date(st.selected)) + yr(st.selected)
        case .week:
            let a = PlannerState.weekStart(st.selected), b = a.adding(days: 6)
            if a.month == b.month { return d.monthTitle(f.date(a)) + yr(a) }
            return Self.abbr3(d.monthTitle(f.date(a))) + " – " + Self.abbr3(d.monthTitle(f.date(b))) + yr(a)
        case .month:
            return d.monthTitle(f.date(st.month)) + yr(st.month)
        }
    }

    static func abbr3(_ s: String) -> String { s.count > 3 ? String(s.prefix(3)) : s }

    static func icon(_ s: CalScope) -> String {
        switch s { case .month: "view_month"; case .week: "view_week"; case .day: "view_day" }
    }

    static func menuKey(_ s: CalScope) -> String {
        switch s { case .month: "plan.viewMonth"; case .week: "plan.viewWeek"; case .day: "plan.viewDay" }
    }
}

/// Знаки, которые веб набирает прямо в разметке «Съёмок», а не из библиотеки
/// (`viewBox 0 0 24 24`): «новая съёмка», статистика, поиск, встреча и замок
/// кнопок дня.
struct PlanGlyph: Shape {
    enum Kind { case add, stats, search, meet, lock }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let pt = { (x: CGFloat, y: CGFloat) in CGPoint(x: x, y: y) }
        let line = { (a: CGPoint, b: CGPoint) in p.move(to: a); p.addLine(to: b) }
        switch kind {
        case .add:
            p.addRoundedRect(in: CGRect(x: 3, y: 4.5, width: 18, height: 17), cornerSize: CGSize(width: 2.5, height: 2.5))
            line(pt(3, 9.5), pt(21, 9.5)); line(pt(8, 2.5), pt(8, 6.5)); line(pt(16, 2.5), pt(16, 6.5))
            line(pt(12, 12.5), pt(12, 17.5)); line(pt(9.5, 15), pt(14.5, 15))
        case .stats:
            line(pt(6, 20), pt(6, 13)); line(pt(12, 20), pt(12, 8)); line(pt(18, 20), pt(18, 4))
        case .search:
            p.addEllipse(in: CGRect(x: 4, y: 4, width: 14, height: 14))
            line(pt(16.5, 16.5), pt(21, 21))
        case .meet:
            // <circle 9,9 r3.2/> M3.5 19.5c0-3 2.5-5 5.5-5s5.5 2 5.5 5 <circle 17,10.5 r2.4/>
            // M15 19.5c0-2.2 1.4-3.8 3.4-3.8 1.1 0 2.1.5 2.6 1.3
            p.addEllipse(in: CGRect(x: 5.8, y: 5.8, width: 6.4, height: 6.4))
            p.move(to: pt(3.5, 19.5))
            p.addCurve(to: pt(9, 14.5), control1: pt(3.5, 16.5), control2: pt(6, 14.5))
            p.addCurve(to: pt(14.5, 19.5), control1: pt(12, 14.5), control2: pt(14.5, 16.5))
            p.addEllipse(in: CGRect(x: 14.6, y: 8.1, width: 4.8, height: 4.8))
            p.move(to: pt(15, 19.5))
            p.addCurve(to: pt(18.4, 15.7), control1: pt(15, 17.3), control2: pt(16.4, 15.7))
            p.addCurve(to: pt(21, 17), control1: pt(19.5, 15.7), control2: pt(20.5, 16.2))
        case .lock:
            // <rect 4.5,10.5 15×10.5 rx2.2/> M8.2 10.5V7.8a3.8 3.8 0 0 1 7.6 0v2.7
            p.addRoundedRect(in: CGRect(x: 4.5, y: 10.5, width: 15, height: 10.5), cornerSize: CGSize(width: 2.2, height: 2.2))
            p.move(to: pt(8.2, 10.5)); p.addLine(to: pt(8.2, 7.8))
            p.addArc(center: pt(12, 7.8), radius: 3.8, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            p.addLine(to: pt(15.8, 10.5))
        }
        return p.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
