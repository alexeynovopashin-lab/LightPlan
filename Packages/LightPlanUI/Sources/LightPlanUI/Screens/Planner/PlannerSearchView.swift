import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Результаты поиска по съёмкам (веб `#searchOverlay`, итерация 22): клиент, имя съёмки, место, город. Ищет на каждой букве.
/// С 30и.4 отдельного окна нет: запрос вводят в плашку пульта (`PlannerConsole`), а найденное лежит стеклянной панелью над
/// плашкой — календарь под ней не пропадает. Тап по найденному открывает карточку (25); «Съёмки» под ней встают на день записи.
struct PlannerSearchView: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Bindable var nav: PlannerNav
    @Environment(\.colorScheme) private var scheme
    /// Высота списка, как он есть: панель по ней не выше `maxHeight` и не пустая.
    @State private var listHeight: CGFloat = 0

    /// Выше панель не растёт: дальше список листается внутри неё.
    static let maxHeight: CGFloat = 340

    var body: some View {
        let pal = Palette(scheme)
        let words = f.words
        let query = nav.searchQuery
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let hits = YearMath.search(query, in: app.sessions, eventsLayer: app.eventsLayer, typeName: words.typeName)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if hits.isEmpty {
                        Text(f.t.t("search.nothing")).font(webFont(14)).foregroundStyle(pal.ink7)
                            .padding(.vertical, 8)
                            .shotNode("se.empty")
                    } else {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { i, s in row(s, words, pal).shotNode("se.row.\(i)") }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .frame(height: min(max(listHeight, 44), Self.maxHeight))
            .scrollDismissesKeyboard(.interactively)
            .glassPlate(pal, radius: 22, hush: 0.7)
            .padding(.horizontal, ConsoleMetrics.margin)
            .shotNode("se.panel", text: "\(hits.count)")
            #if os(iOS)
            // Касание мимо строк закрывает открытую кнопку «Удалить» (29.3г), как в «Съёмках».
            .gesture(TouchProbe { stamp in Task { @MainActor in app.rowSwipe.outsideTouch(stamp: stamp) } })
            #endif
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func close() {
        PlanMotion.search(nav, open: false)
    }

    /// `.plan-row`: дата латунью и «кто · часы», волосок снизу (у веба белый
    /// 4 % в обеих темах — перенесено как есть).
    private func row(_ s: Session, _ words: PlannerWords, _ pal: Palette) -> some View {
        let who = words.clientName(s)
        let name = !who.isEmpty ? who
            : s.kind == .meet ? f.t.t("day.meet") : s.kind == .event ? f.t.t("day.event") : words.typeName(s)
        return Button {
            if app.rowSwipe.takesTap("s." + s.id) { return }
            close()
            app.planner.enterDay(s.day)
            nav.lentaOpen = false
            nav.year12Open = false
            nav.statsOpen = false
            PlanMotion.openCard(app, id: s.id)
        } label: {
            HStack(spacing: 10) {
                Text(f.dates.dMonShort(f.date(s.day))).font(webFont(16).monospacedDigit()).foregroundStyle(pal.brassInk)
                    .lineLimit(1)
                Text(name + " · " + f.fmt(Double(s.start)) + "–" + f.fmt(Double(s.endMinute)))
                    .font(webFont(16)).foregroundStyle(pal.ink).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { Rectangle().fill(pal.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Свайп влево «Удалить» (29.3г).
        .rowSwipe(app, key: "s." + s.id, id: s.id, corner: 10, word: f.t.t("swipe.del"))
    }
}
