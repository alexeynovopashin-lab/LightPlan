import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Пульт «Съёмок» (30и.4 + 30и.8)
//
// Стеклянный пульт висит над панелью вкладок, как пульт «Света» (та же плашка `glassPlate`, те же стеклянные кнопки высотой 40):
// «Съёмка · Встреча · Занять · Поиск». «Съёмка» в светлой теме — чёрная с белым знаком (палитра Д), в тёмной — стекло с латунным
// знаком, как капсула «Запланировать съёмку». Лупа — круг справа. Нажатие на лупу разворачивает пульт в плашку поиска над
// клавиатурой (как в Настройках iOS), «✕» сворачивает её обратно в круг; результаты лежат над плашкой, календарь не пропадает.
// В мудборде (прокрутили от календаря к полосе подборок) кнопки другие: «Подборка · Референс · Поиск», и обратно.
// Схема: `light_plan:Light_Plan/docs/sketches_2026-11-14/index.html`, разделы «поиск» и «пульт «Съёмок»» (вариант В для мудборда).

/// Числа пульта. Строка, поле плашки и круг лупы — те же, что у пульта «Света» (`TimebarView.consoleHeight` = 40).
enum ConsoleMetrics {
    static let row: CGFloat = 40   // = TimebarView.consoleHeight
    /// Поле внутри плашки (схема: `padding: 6px`).
    static let inner: CGFloat = 6
    static let plate: CGFloat = row + 2 * inner
    /// От краёв экрана и от панели вкладок — обычный зазор между плашками «Света» (`LightScreenView.plateGap`).
    static let margin: CGFloat = 8
    /// Сколько снизу занимает пульт вместе с зазором: на столько кнопка «Наверх» стоит выше обычного.
    static let height: CGFloat = plate + margin
    /// Плашка поиска над клавиатурой и «✕» рядом (схема: 44).
    static let searchBar: CGFloat = 44
    /// «Наверх» над пультом справа: обычная кнопка, но её отступ снизу считается от верха пульта.
    static let jumpGap: CGFloat = 8
    static var jumpLook: ScrollJump.Look { ScrollJump.Look(size: 40, strong: false, trailing: 20, bottom: height + jumpGap) }
    /// Строка кнопок и плашка растут за 0,3 с (схема: «лупа расширяется в плашку 0,3 с»).
    static let morph = Animation.timingCurve(0.25, 1, 0.4, 1, duration: 0.3)
    /// Полоса мудборда выше этой доли окна — кнопки мудборда.
    static let moodboardAt: CGFloat = 0.5

    /// Какой набор кнопок виден: верх полосы мудборда ушёл выше середины окна — набор мудборда.
    static func set(stripTop: CGFloat, window: CGFloat) -> ConsoleSet {
        window > 0 && stripTop < window * moodboardAt ? .moodboard : .calendar
    }
}

enum ConsoleSet: Equatable { case calendar, moodboard }

struct PlannerConsole: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Bindable var nav: PlannerNav
    let set: ConsoleSet
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool
    @Namespace private var lens

    var body: some View {
        let pal = Palette(scheme)
        VStack(spacing: 8) {
            if nav.searchOpen { PlannerSearchView(app: app, f: f, nav: nav) }
            if nav.searchOpen { searchBar(pal) } else { plate(pal) }
        }
        .padding(.bottom, ConsoleMetrics.margin)
        .animation(PlanMotion.pick(ConsoleMetrics.morph), value: nav.searchOpen)
        .animation(PlanMotion.pick(ConsoleMetrics.morph), value: set)
        .task(id: nav.searchOpen) {
            guard nav.searchOpen else { focused = false; return }
            // Клавиатура — когда плашка почти доехала.
            try? await Task.sleep(for: .milliseconds(300))
            focused = true
        }
        #if DEBUG
        // Стенд и тесты: `-LPSearchQuery <слово>` вводит запрос без клавиатуры, как только плашка развернулась.
        .onChange(of: nav.searchOpen, initial: true) { _, open in
            if open, nav.searchQuery.isEmpty, let q = UserDefaults.standard.string(forKey: "LPSearchQuery") { nav.searchQuery = q }
        }
        #endif
    }

    // MARK: Плашка с кнопками

    private func plate(_ pal: Palette) -> some View {
        HStack(spacing: ConsoleMetrics.inner) {
            switch set {
            case .calendar:
                key(.add, f.t.t("plan.shortShoot"), black: true, node: "pl.shoot", pal) {
                    app.openForm(day: app.planner.selected)
                }
                key(.meet, f.t.t("plan.shortMeet"), node: "pl.meet", pal) {
                    // Встреча — та же форма в режиме встречи, 14:00 («в кафе идут к двум», не свет; веб `#planMeet`).
                    app.openForm(day: app.planner.selected, start: 14 * 60, fromLight: false, mode: .meet)
                }
                key(.lock, f.t.t("plan.shortBlock"), node: "pl.busy", pal) {
                    app.openBlockSheet(day: app.planner.selected)
                }
            case .moodboard:
                key(icon: "plus", f.t.t("plan.mbSet"), black: true, node: "pl.mbSet", pal) { app.openMbNew() }
                key(icon: "camera", f.t.t("plan.mbRef"), node: "pl.mbRef", pal) { withAnimation(overlaySlide) { app.openMbGallery() } }
            }
            lensCircle(pal)
        }
        .padding(ConsoleMetrics.inner)
        .glassPlate(pal, radius: 22, hush: 0.7)
        .padding(.horizontal, ConsoleMetrics.margin)
        .shotNode("pl.console", text: set == .calendar ? "calendar" : "moodboard")
    }

    private func lensCircle(_ pal: Palette) -> some View {
        Button { PlanMotion.search(nav, open: true) } label: {
            PlanGlyph(kind: .search)
                .stroke(pal.ink, style: StrokeStyle(lineWidth: 1.7 * 22 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 22, height: 22)
                .frame(width: ConsoleMetrics.row, height: ConsoleMetrics.row)
                .glassEffect(.regular, in: Circle())
                .flatGlass(Circle(), light: !pal.dark)
                .overlay { if !pal.dark { Circle().strokeBorder(pal.hair4, lineWidth: 1).allowsHitTesting(false) } }
                .contentShape(Circle())
                .matchedGeometryEffect(id: "lens", in: lens)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(f.t.t("plan.search"))
        .shotNode("pl.search")
    }

    /// Кнопка пульта: знак и подпись в строку, высота 40, скругление 14 (схема `.cb`). «Съёмка» — главная: в светлой чёрная
    /// с белым знаком, в тёмной стекло с латунным знаком.
    private func key(_ kind: PlanGlyph.Kind? = nil, icon: String? = nil, _ title: String, black: Bool = false, node: String,
                     _ pal: Palette, _ action: @escaping () -> Void) -> some View {
        let solid = black && !pal.dark
        let glyph: Color = solid ? .white : black ? pal.brass : pal.ink2
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button(action: action) {
            HStack(spacing: 6) {
                if let kind {
                    PlanGlyph(kind: kind).stroke(glyph, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 18, height: 18)
                } else if let icon {
                    Icon(icon, size: 18, line: 1.6).foregroundStyle(glyph)
                }
                Text(title).font(webFont(13, 600)).foregroundStyle(solid ? Color.white : pal.ink)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: ConsoleMetrics.row)
            .background {
                if solid { shape.fill(PlateTokens.blackFill) }
                else { Color.clear.glassEffect(.regular, in: shape).flatGlass(shape, light: !pal.dark) }
            }
            .overlay { if !pal.dark && !solid { shape.strokeBorder(pal.hair4, lineWidth: 1).allowsHitTesting(false) } }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .shotNode(node, text: title)
    }

    // MARK: Плашка поиска

    private func searchBar(_ pal: Palette) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                PlanGlyph(kind: .search)
                    .stroke(pal.ink4, style: StrokeStyle(lineWidth: 1.7 * 20 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: 20, height: 20)
                TextField("", text: $nav.searchQuery, prompt: Text(f.t.t("search.ph")).foregroundStyle(pal.ink8))
                    .font(webFont(16)).foregroundStyle(pal.ink)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .tint(pal.ink)   // каретка веба — цвет текста, не системный синий
                    .shotNode("se.field", text: nav.searchQuery)
                if !nav.searchQuery.isEmpty {
                    Button { nav.searchQuery = "" } label: {
                        Icon("close", size: 14, line: 2).foregroundStyle(pal.ink4)
                            .frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .shotNode("se.clear")
                }
            }
            .padding(.leading, 14).padding(.trailing, nav.searchQuery.isEmpty ? 14 : 8)
            .frame(height: ConsoleMetrics.searchBar)
            .glassEffect(.regular, in: Capsule())
            .flatGlass(Capsule(), light: !pal.dark)
            .overlay { if !pal.dark { Capsule().strokeBorder(pal.hair4, lineWidth: 1).allowsHitTesting(false) } }
            .matchedGeometryEffect(id: "lens", in: lens)
            Button { PlanMotion.search(nav, open: false) } label: {
                Icon("close", size: 18, line: 2.2).foregroundStyle(pal.ink3)
                    .frame(width: ConsoleMetrics.searchBar, height: ConsoleMetrics.searchBar)
                    .glassEffect(.regular, in: Circle())
                    .flatGlass(Circle(), light: !pal.dark)
                    .overlay { if !pal.dark { Circle().strokeBorder(pal.hair4, lineWidth: 1).allowsHitTesting(false) } }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(f.t.t("nav.back"))
            .shotNode("se.back")
        }
        .padding(.horizontal, 12)
        .shotNode("pl.searchBar")
    }
}
