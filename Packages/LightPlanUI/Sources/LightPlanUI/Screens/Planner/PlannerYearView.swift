import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Слои «Съёмок» поверх календаря (итерация 22): лента месяцев года, «Год
/// целиком», статистика, поиск, корзина. У веба это отдельные `.overlay`, а не
/// масштабы `calScope` — здесь так же: календарь под ними стоит, где стоял.
@Observable @MainActor
final class PlannerNav {
    /// Показанный год (веб `yearShown`): общий у ленты, «Года целиком» и
    /// статистики. Ставится от месяца календаря при входе.
    var year = 2026
    var lentaOpen = false
    var year12Open = false
    var statsOpen = false
    var searchOpen = false
    var binOpen = false
    /// Лента должна встать на этот месяц (первое число): имя месяца — на 8 ниже
    /// верха прокрутки (веб `scrollYearTo`).
    var lentaTarget: CivilDate?
    /// Зум «Год целиком» → лента (веб `zoomYear12ToMonth`), пока идёт.
    var zoom: YearZoom?
    /// Рамки сеток дней в общем пространстве слоёв года: у «Года целиком» —
    /// по месяцу показанного года, у ленты — по месяцу обоих её лет.
    var tileGrids: [CivilDate: CGRect] = [:]
    var lentaGrids: [CivilDate: CGRect] = [:]

    func openLenta(from month: CivilDate) {
        year = month.year
        lentaTarget = month
        lentaOpen = true
    }
}

/// Ход зума. Оба слоя едут от одного хода `e` одной кривой: так нажатое число
/// на обоих слоях совпадает в каждом кадре (проверено алгеброй в справке, § 5).
struct YearZoom: Equatable {
    let k: CGFloat
    let t: CGSize
    var e: CGFloat = 0
    var lentaAlpha: Double = 0
    var sourceAlpha: Double = 1

    /// Лента в начале — обратное преобразование: `translate(−t/k) scale(1/k)`.
    var u: CGSize { CGSize(width: -t.width / k, height: -t.height / k) }

    /// Кривая и длительность веба: 460 мс, `cubic-bezier(0.3, 0.7, 0.1, 1)`.
    static let motion = Animation.timingCurve(0.3, 0.7, 0.1, 1, duration: 0.46)
}

/// Пространство, в котором меряются сетки обоих слоёв года.
let yearStageSpace = "yearStage"

// MARK: - Сцена года

/// Лента и «Год целиком» в одной сцене: зуму нужны рамки обоих слоёв в одних
/// координатах. Под сценой — панель вкладок (веб: `z-index: 25` у слоёв, 30 у
/// панели).
struct YearStage: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Bindable var nav: PlannerNav

    var body: some View {
        let z = nav.zoom
        ZStack {
            if nav.lentaOpen {
                YearLentaView(app: app, f: f, nav: nav)
                    .scaleEffect(z.map { 1 / $0.k + (1 - 1 / $0.k) * $0.e } ?? 1, anchor: .topLeading)
                    .offset(z.map { CGSize(width: $0.u.width * (1 - $0.e), height: $0.u.height * (1 - $0.e)) } ?? .zero)
                    .opacity(z?.lentaAlpha ?? 1)
                    .zIndex(z == nil ? 1 : 3)
                    .transition(.move(edge: .bottom))
            }
            if nav.year12Open {
                Year12View(app: app, f: f, nav: nav)
                    .scaleEffect(z.map { 1 + ($0.k - 1) * $0.e } ?? 1, anchor: .topLeading)
                    .offset(z.map { CGSize(width: $0.t.width * $0.e, height: $0.t.height * $0.e) } ?? .zero)
                    .zIndex(2)
                    .transition(.move(edge: .bottom))
            }
        }
        .coordinateSpace(name: yearStageSpace)
    }
}

/// Выезд слоя снизу (веб `.overlay`: 0,42 с, `cubic-bezier(0.25, 1, 0.4, 1)`).
let overlaySlide = Animation.timingCurve(0.25, 1, 0.4, 1, duration: 0.42)

// MARK: - Общие куски слоёв

/// `.back`: шеврон влево и слово, 15 pt `--ink-4`, поле 8 сверху и снизу.
struct OverlayBack: View {
    let title: String
    var node = "ov.back"
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        Button(action: action) {
            HStack(spacing: 7) {
                Icon("chevron", size: 16, line: 2.4).rotationEffect(.degrees(180))
                Text(title).font(webFont(15))
            }
            .foregroundStyle(pal.ink4)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode(node, text: title)
    }
}

/// `.icon-btn` шапки года: знак 22 линией 1,6 и поле 6.
struct OverlayIconButton: View {
    let kind: PlanGlyph.Kind
    let color: Color
    let label: String
    var node = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PlanGlyph(kind: kind)
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(width: 22, height: 22)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .shotNode(node)
    }
}

/// «↺ сегодня» капсулой на стекле над панелью вкладок (`.now-back.day-float`).
struct NowPill: View {
    let text: String
    var node = "year.now"
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(text).font(webFont(12.5, 600)).tracking(0.4).foregroundStyle(Palette(scheme).brassDeep)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .glassEffect(.regular, in: Capsule())
        }
        .buttonStyle(.plain)
        .shotNode(node, text: text)
        .padding(.bottom, 12)
    }
}

// MARK: - Лента месяцев

/// Лента месяцев (веб `#yearOverlay`): 24 месяца — показанный год и следующий,
/// только числа и сегодняшний круг, «чистая навигация». Тап по числу — в
/// день, по имени месяца — в месяц, по году — «Год целиком».
struct YearLentaView: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Bindable var nav: PlannerNav
    @Environment(\.colorScheme) private var scheme
    @State private var position = ScrollPosition(idType: String.self)
    /// Верх каждого месяца в координатах содержимого ленты.
    @State private var tops: [CivilDate: CGFloat] = [:]
    /// Год, до которого долистали (веб `#yTitle` по прокрутке).
    @State private var seenYear: Int?
    /// Верх блока второго года (его разделителя) в координатах содержимого.
    @State private var dividerTop: CGFloat?

    var body: some View {
        let pal = Palette(scheme)
        let today = f.today
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach([nav.year, nav.year + 1], id: \.self) { y in
                    if y != nav.year { divider(y, pal) }
                    ForEach(1...12, id: \.self) { m in
                        month(CivilDate(year: y, month: m, day: 1), today: today, pal: pal)
                    }
                }
                sum(pal)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .coordinateSpace(name: "lenta")
        }
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
            // Заголовок — год последнего блока, чей верх уже у края (веб: ≤ 4).
            seenYear = dividerTop.map { $0 - y <= 4 ? nav.year + 1 : nav.year } ?? nav.year
        }
        .safeAreaInset(edge: .top, spacing: 0) { head(pal) }
        .overlay(alignment: .bottom) {
            if nav.year != today.year, nav.zoom == nil {
                NowPill(text: f.t.t("today.backToday")) {
                    nav.year = today.year
                    nav.lentaTarget = PlannerState.first(of: today)
                }
            }
        }
        .background(nav.zoom == nil ? pal.surface : .clear)
        .onChange(of: nav.lentaTarget, initial: true) { _, _ in jump() }
        .onChange(of: tops) { _, _ in if nav.lentaTarget != nil { jump() } }
    }

    /// Встать на месяц цели: имя месяца на 8 ниже верха прокрутки. Рамки
    /// месяцев приходят после раскладки — цель ждёт их.
    private func jump() {
        guard let m = nav.lentaTarget, let top = tops[m] else { return }
        position.scrollTo(y: max(0, top - 8))
        nav.lentaTarget = nil
    }

    private func head(_ pal: Palette) -> some View {
        let shown = seenYear ?? nav.year
        return VStack(spacing: 0) {
            HStack {
                OverlayBack(title: f.t.t("nav.shoots"), node: "year.back") {
                    withAnimation(overlaySlide) { nav.lentaOpen = false }
                }
                Spacer()
                HStack(spacing: 2) {
                    OverlayIconButton(kind: .add, color: pal.brass, label: f.t.t("plan.newShoot"), node: "year.add") {
                        // Веб закрывает ленту и открывает форму на выбранном дне
                        // календаря, с начала его окна света.
                        withAnimation(overlaySlide) { nav.lentaOpen = false }
                        app.openForm(day: app.planner.selected)
                    }
                    if YearMath.work(app.sessions, year: nav.year).count > 0 {
                        OverlayIconButton(kind: .stats, color: pal.brass, label: f.t.t("plan.stats"), node: "year.stats") {
                            withAnimation(statsSlide) { nav.statsOpen = true }
                        }
                    }
                    OverlayIconButton(kind: .search, color: pal.brass, label: f.t.t("plan.search"), node: "year.search") {
                        withAnimation(overlaySlide) { nav.searchOpen = true }
                    }
                }
            }
            Button {
                withAnimation(overlaySlide) { nav.year12Open = true }
            } label: {
                Text(String(shown))
                    .font(webFont(30, 650)).tracking(-0.5).monospacedDigit()
                    .foregroundStyle(pal.ink)
                    .shotNode("year.title", text: String(shown))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .accessibilityHint(f.t.t("year.one"))
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .background(nav.zoom == nil ? pal.surface : .clear)
    }

    private func divider(_ y: Int, _ pal: Palette) -> some View {
        Text(String(y))
            .font(webFont(26, 650)).tracking(-0.5).monospacedDigit()
            .foregroundStyle(pal.ink4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
            .overlay(alignment: .top) { Rectangle().fill(pal.hair).frame(height: 1) }
            .padding(.top, 6).padding(.bottom, 24)
            .shotNode("year.divider", text: String(y))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("lenta")).minY - 6 } action: { dividerTop = $0 }
    }

    private func month(_ first: CivilDate, today: CivilDate, pal: Palette) -> some View {
        let (lead, days) = YearMath.monthShape(year: first.year, month: first.month)
        let now = PlannerState.sameMonth(first, today)
        let first1 = first.year == nav.year
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                app.planner.enterMonth(first, today: today)
                withAnimation(overlaySlide) { nav.lentaOpen = false }
            } label: {
                Text(f.dates.monthTitleN(first.month - 1))
                    .font(webFont(15, 600)).tracking(-0.1)
                    .foregroundStyle(now ? pal.brass : pal.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .shotNode(first1 ? "ym.name.\(first.month - 1)" : "")
            HStack(spacing: 0) {
                ForEach(Array(f.dates.weekdayRow().enumerated()), id: \.offset) { _, w in
                    Text(w.uppercased()).font(webFont(10)).tracking(0.5).foregroundStyle(pal.ink7)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 3) {
                ForEach(0..<lead, id: \.self) { i in Color.clear.aspectRatio(1, contentMode: .fit).id("pad\(i)") }
                ForEach(1...days, id: \.self) { d in
                    let day = CivilDate(year: first.year, month: first.month, day: d)
                    let isToday = day == today
                    Button {
                        withAnimation(nil) { nav.lentaOpen = false }
                        app.planner.enterDay(day)
                    } label: {
                        Text("\(d)")
                            .font(webFont(13.5, isToday ? 700 : 400)).monospacedDigit()
                            .foregroundStyle(isToday ? pal.onBrass : pal.ink3)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background { if isToday { Circle().fill(pal.brass).frame(width: 30, height: 30) } }
                            .contentShape(Circle())
                    }
                    .buttonStyle(YearDayPress())
                    .accessibilityLabel(f.dates.dMonYear(f.date(day)))
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(yearStageSpace)) } action: { nav.lentaGrids[first] = $0 }
            .shotNode(first1 ? "ym.grid.\(first.month - 1)" : "")
        }
        .padding(.bottom, 26)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("lenta")).minY } action: { tops[first] = $0 }
    }

    private func sum(_ pal: Palette) -> some View {
        let (n, next) = YearMath.summary(app.sessions, year: nav.year, today: f.today)
        let t = f.t
        var s = AttributedString()
        if n == 0 {
            s = AttributedString(t.t("year.free"))
        } else {
            var b = AttributedString("\(n)")
            b.foregroundColor = pal.ink3
            b.font = webFont(13, 600).monospacedDigit()
            s += b
            s += AttributedString(t.sep("unit.shoot") + t.word("unit.shoot", n))
            if let next {
                // «{date}» в середине строки словаря — жирным, как у веба.
                let parts = t.t("year.next").components(separatedBy: "{date}")
                s += AttributedString(parts.first ?? "")
                var d = AttributedString(f.dates.dMon(f.date(next)))
                d.foregroundColor = pal.ink3
                d.font = webFont(13, 600)
                s += d
                s += AttributedString(parts.count > 1 ? parts[1] : "")
            }
        }
        return Text(s)
            .font(webFont(13)).foregroundStyle(pal.ink6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
            .overlay(alignment: .top) { Rectangle().fill(pal.hair).frame(height: 1) }
            .padding(.top, 34 - 26)
            .shotNode("year.sum")
    }
}

/// Нажатая клетка ленты — круг `--sheet` (веб `:active`).
private struct YearDayPress: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { if configuration.isPressed { Circle().fill(Palette(scheme).sheet) } }
    }
}

// MARK: - Год целиком

/// «Год целиком» (веб `#year12Overlay`): 3 × 4 месяца показанного года,
/// точка — съёмка в дне, крупная латунная и жирное число — две и больше.
/// Тап по месяцу — зум в ленту на этот месяц; свайп — соседний год.
struct Year12View: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Bindable var nav: PlannerNav
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let today = f.today
        ZStack {
            pal.surface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    OverlayBack(title: f.t.t("year.one"), node: "y12.back") {
                        withAnimation(overlaySlide) { nav.year12Open = false }
                    }
                    HStack {
                        arrow(-1, pal)
                        Spacer()
                        Text(String(nav.year))
                            .font(webFont(30, 650)).tracking(-0.5).monospacedDigit()
                            .foregroundStyle(nav.year == today.year ? pal.brass : pal.ink)
                            .shotNode("y12.title", text: String(nav.year))
                        Spacer()
                        arrow(1, pal)
                    }
                    .padding(.top, 14)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 22) {
                        ForEach(1...12, id: \.self) { m in
                            tile(CivilDate(year: nav.year, month: m, day: 1), today: today, pal: pal)
                        }
                    }
                    .padding(.top, 4).padding(.bottom, 20)
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
            .opacity(nav.zoom?.sourceAlpha ?? 1)
            .overlay(alignment: .bottom) {
                if nav.year != today.year, nav.zoom == nil {
                    NowPill(text: f.t.t("today.backToday"), node: "y12.now") { nav.year = today.year }
                }
            }
        }
        .simultaneousGesture(swipe)
    }

    private func arrow(_ dir: Int, _ pal: Palette) -> some View {
        Button { nav.year += dir } label: {
            Icon("chevron", size: 16, line: 2.4)
                .rotationEffect(.degrees(dir < 0 ? 180 : 0))
                .foregroundStyle(pal.ink4)
                .padding(.vertical, 9).padding(.horizontal, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // У веба «вперёд» читается строкой итога года (`year.next`) — своя подпись.
        .accessibilityLabel(f.t.t(dir < 0 ? "year.prev" : "year.nextYear"))
        .shotNode(dir < 0 ? "y12.prev" : "y12.next")
    }

    /// Свайп по слою (веб: |dx| ≥ 60, |dy| ≤ 40) — соседний год, без движения.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20).onEnded { g in
            let dx = g.translation.width, dy = g.translation.height
            guard abs(dx) >= 60, abs(dy) <= 40, nav.zoom == nil else { return }
            nav.year += dx < 0 ? 1 : -1
        }
    }

    private func tile(_ first: CivilDate, today: CivilDate, pal: Palette) -> some View {
        let (lead, days) = YearMath.monthShape(year: first.year, month: first.month)
        let counts = YearMath.dayCounts(app.sessions, year: first.year, month: first.month)
        let now = PlannerState.sameMonth(first, today)
        let i = first.month - 1
        return VStack(spacing: 0) {
            Text(f.dates.monthTitleN(i))
                .font(webFont(12.5, 650)).tracking(0.1)
                .foregroundStyle(now ? pal.brass : pal.ink)
                .padding(.bottom, 7)
                .shotNode("y12.name.\(i)")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(0..<lead, id: \.self) { k in Color.clear.frame(height: 16.15).id("pad\(k)") }
                ForEach(1...days, id: \.self) { d in
                    let n = counts[d] ?? 0
                    let isToday = today == CivilDate(year: first.year, month: first.month, day: d)
                    Text("\(d)")
                        .font(webFont(8.5, isToday || n >= 2 ? 700 : 400)).monospacedDigit()
                        .foregroundStyle(isToday ? pal.onBrass : n >= 2 ? pal.ink : pal.ink4)
                        .frame(maxWidth: .infinity).frame(height: 16.15)
                        .background { if isToday { Circle().fill(pal.brass).frame(width: 14, height: 14) } }
                        .overlay(alignment: .bottom) {
                            if n > 0 {
                                Circle().fill(n >= 2 ? pal.brass : pal.brassSoft)
                                    .frame(width: n >= 2 ? 4.5 : 3, height: n >= 2 ? 4.5 : 3)
                                    .padding(.bottom, 1)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { zoom(first, day: d) }
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(yearStageSpace)) } action: { nav.tileGrids[first] = $0 }
            .shotNode("y12.grid.\(i)")
        }
        .contentShape(Rectangle())
        .onTapGesture { zoom(first, day: 0) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(f.dates.monthTitleN(i) + ", " + f.t.count("unit.shoot", counts.values.reduce(0, +)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { zoom(first, day: 0) }
    }

    /// Зум в ленту (веб `zoomYear12ToMonth`). Лента встаёт на месяц, кадр
    /// ждёт её раскладку, потом оба слоя едут от одного хода. Нажатое число
    /// едет на своё место в ленте; тап мимо чисел — центр сетки в центр сетки.
    private func zoom(_ first: CivilDate, day: Int) {
        guard nav.zoom == nil else { return }
        nav.lentaTarget = first
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(34))
            guard let src = nav.tileGrids[first], let dst = nav.lentaGrids[first] else {
                nav.year12Open = false
                return
            }
            let k = dst.width / max(1, src.width)
            let (lead, _) = YearMath.monthShape(year: first.year, month: first.month)
            let from = day > 0 ? Self.cell(src, index: lead + day - 1, rowH: 16.15, gap: 2) : src
            let to = day > 0 ? Self.cell(dst, index: lead + day - 1, rowH: dst.width / 7, gap: 3) : dst
            let t = CGSize(width: to.midX - k * from.midX, height: to.midY - k * from.midY)
            var z = YearZoom(k: k, t: t)
            nav.zoom = z
            try? await Task.sleep(for: .milliseconds(16))
            z.e = 1
            withAnimation(YearZoom.motion) { nav.zoom?.e = 1 }
            withAnimation(.linear(duration: 0.16)) { nav.zoom?.lentaAlpha = 1 }
            withAnimation(.linear(duration: 0.2).delay(0.06)) { nav.zoom?.sourceAlpha = 0 }
            try? await Task.sleep(for: .milliseconds(480))
            var off = Transaction()
            off.disablesAnimations = true
            withTransaction(off) {
                nav.year12Open = false
                nav.zoom = nil
            }
        }
    }

    /// Клетка числа в сетке по номеру (ряды с понедельника).
    static func cell(_ grid: CGRect, index: Int, rowH: CGFloat, gap: CGFloat) -> CGRect {
        let w = grid.width / 7
        return CGRect(x: grid.minX + CGFloat(index % 7) * w, y: grid.minY + CGFloat(index / 7) * (rowH + gap),
                      width: w, height: rowH)
    }
}
