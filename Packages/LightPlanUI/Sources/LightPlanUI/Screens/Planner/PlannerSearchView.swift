import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Поиск по съёмкам (веб `#searchOverlay`, итерация 22): клиент, имя съёмки,
/// место, город. Ищет на каждой букве. Тап по найденному у веба открывает
/// карточку — её ещё нет (итерация 25), до неё открывается день записи.
struct PlannerSearchView: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Bindable var nav: PlannerNav
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @FocusState private var focused: Bool
    @State private var position = ScrollPosition(edge: .top)
    /// Прокрутка: сколько прокручено, сколько всего лишнего, высота окна.
    @State private var scroll = (offset: CGFloat(0), overflow: CGFloat(0), visible: CGFloat(1))

    var body: some View {
        let pal = Palette(scheme)
        let words = f.words
        let hits = YearMath.search(query, in: app.sessions, eventsLayer: app.eventsLayer, typeName: words.typeName)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverlayBack(title: f.t.t("nav.back"), node: "se.back") { close() }
                TextField("", text: $query, prompt: Text(f.t.t("search.ph")).foregroundStyle(pal.ink8))
                    .font(webFont(16)).foregroundStyle(pal.ink)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .tint(pal.ink) // каретка веба — цвет текста, не системный синий
                    .padding(.vertical, 14).padding(.horizontal, 15)
                    .background(focused ? pal.press : pal.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shotNode("se.field")
                    .padding(.top, 14)
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    empty("search.startTyping", pal)
                } else if hits.isEmpty {
                    empty("search.nothing", pal)
                } else {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { i, s in row(s, words, pal).shotNode("se.row.\(i)") }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .scrollPosition($position)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: [CGFloat].self) {
            [$0.contentOffset.y, max(0, $0.contentSize.height - $0.containerSize.height), $0.containerSize.height]
        } action: { _, v in scroll = (v[0], v[1], max(1, v[2])) }
        .overlay(alignment: .bottomTrailing) { jump(pal) }
        .background(pal.surface.ignoresSafeArea())
        .task {
            // Клавиатура — когда слой почти доехал (веб: 350 мс).
            try? await Task.sleep(for: .milliseconds(350))
            focused = true
        }
    }

    private func close() {
        focused = false
        withAnimation(overlaySlide) { nav.searchOpen = false }
    }

    private func empty(_ key: String, _ pal: Palette) -> some View {
        Text(f.t.t(key)).font(webFont(14)).foregroundStyle(pal.ink7)
            .padding(.vertical, 8).padding(.top, 0)
            .shotNode("se.empty")
    }

    /// `.plan-row`: дата латунью и «кто · часы», волосок снизу (у веба белый
    /// 4 % в обеих темах — перенесено как есть).
    private func row(_ s: Session, _ words: PlannerWords, _ pal: Palette) -> some View {
        let who = words.clientName(s)
        let name = !who.isEmpty ? who
            : s.kind == .meet ? f.t.t("day.meet") : s.kind == .event ? f.t.t("day.event") : words.typeName(s)
        return Button {
            close()
            app.planner.enterDay(s.day)
            nav.lentaOpen = false
            nav.year12Open = false
            nav.statsOpen = false
        } label: {
            HStack(spacing: 10) {
                Text(f.dates.dMonShort(f.date(s.day))).font(webFont(16).monospacedDigit()).foregroundStyle(pal.brass)
                    .lineLimit(1)
                Text(name + " · " + f.fmt(Double(s.start)) + "–" + f.fmt(Double(s.endMinute)))
                    .font(webFont(16)).foregroundStyle(pal.ink).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Кнопка «в конец / в начало» (веб `jumpAttach`): видна, когда лишнего не
    /// меньше 0,6 окна; до середины ведёт вниз, дальше — вверх.
    @ViewBuilder private func jump(_ pal: Palette) -> some View {
        if scroll.overflow >= 0.6 * scroll.visible {
            let down = scroll.offset < scroll.overflow / 2
            Button {
                withAnimation(.easeInOut(duration: 0.35)) {
                    if down { position.scrollTo(edge: .bottom) } else { position.scrollTo(edge: .top) }
                }
            } label: {
                Icon("chevron", size: 16, line: 2.4)
                    .rotationEffect(.degrees(down ? 90 : -90))
                    .foregroundStyle(pal.ink3)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(f.t.t(down ? "mb.jumpEnd" : "mb.jumpTop"))
            .padding(.trailing, 24).padding(.bottom, 10)
            .shotNode("se.jump")
        }
    }
}
