import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Слои «Съёмок» над календарём (итерация 22): год, поиск, статистика —
/// в порядке веба (`#yearOverlay` 25 < `#searchOverlay` 80 < `#statsOverlay`
/// 85). Панель вкладок остаётся видна над всеми.
struct PlannerLayers: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Bindable var nav: PlannerNav

    var body: some View {
        ZStack {
            YearStage(app: app, f: f, nav: nav).zIndex(1)
            if nav.searchOpen {
                PlannerSearchView(app: app, f: f, nav: nav)
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }
            if nav.statsOpen {
                PlannerStatsView(app: app, f: f, nav: nav)
                    .transition(.move(edge: .trailing))
                    .zIndex(3)
            }
        }
    }
}

/// Слой статистики въезжает справа (`.overlay-right`: 0,36 с).
let statsSlide = Animation.timingCurve(0.25, 1, 0.4, 1, duration: 0.36)

// MARK: - Веер удержания

/// Что держат пальцем (веб `openEvFan`): запись и её рамка на экране.
struct FanTarget: Equatable {
    let id: String
    let anchor: CGRect
}

/// Пространство, в котором меряются строки и ставится веер.
let plannerFanSpace = "plannerFan"

/// Удержание строки 0,45 с при сдвиге не больше 8 pt (веб `holdForFan`) —
/// открыть веер у этой строки.
struct FanHold: ViewModifier {
    let id: String
    @Binding var fan: FanTarget?
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(plannerFanSpace)) } action: { frame = $0 }
            .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 8) {
                fan = FanTarget(id: id, anchor: frame)
            }
    }
}

/// Веер записи (`.spot-fan`): «Заполнить» и «Удалить» — удалить без вопроса,
/// вернуть можно сразу после (полоса «Вернуть», корзина).
struct EventFan: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Binding var fan: FanTarget?
    @State private var size = CGSize(width: 216, height: 120)
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            if let target = fan, let s = app.sessions.first(where: { $0.id == target.id }) {
                let pal = Palette(scheme)
                let w = geo.size.width, h = geo.size.height, a = target.anchor
                let left = min(max(a.minX, 10), w - size.width - 10)
                let below = a.maxY + 6
                let top = below + size.height > h - 10 ? max(10, a.minY - size.height - 6) : below
                ZStack(alignment: .topLeading) {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { fan = nil }
                    VStack(spacing: 0) {
                        item("note_edit", f.t.t("card.fill"), who(s), del: false, pal) {
                            fan = nil
                            app.openForm(editing: s.id)
                        }
                        .shotNode("fan.fill")
                        item("trash", f.t.t("swipe.del"), f.t.t("swipe.delSub"), del: true, pal) {
                            fan = nil
                            withAnimation(.easeOut(duration: 0.2)) { app.trashSession(id: s.id) }
                        }
                        .shotNode("fan.del")
                    }
                    .padding(6)
                    .frame(minWidth: 216, maxWidth: 280, alignment: .leading)
                    .fixedSize()
                    .background(pal.sheet, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.55), radius: 20, y: 18)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                    .offset(x: left, y: top)
                    .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
                    .shotNode("fan")
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: fan?.id) { _, new in new != nil }
        .animation(.easeOut(duration: 0.16), value: fan)
    }

    private func who(_ s: Session) -> String {
        let n = f.words.clientName(s)
        return n.isEmpty ? f.words.typeName(s) : n
    }

    private func item(_ icon: String, _ t1: String, _ t2: String, del: Bool, _ pal: Palette,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(icon, size: 18, line: 1.6).foregroundStyle(del ? pal.badInk : pal.ink4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t1).font(webFont(15)).foregroundStyle(del ? pal.badInk : pal.ink).lineLimit(1)
                    if !t2.isEmpty { Text(t2).font(webFont(11)).foregroundStyle(pal.ink4).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 11).padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(FanPress())
    }
}

private struct FanPress: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Palette(scheme).press : .clear,
                                       in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

// MARK: - Полоса «Вернуть»

/// Полоса отмены (веб `#undoBar`): стекло над панелью вкладок, 14 от краёв,
/// 6 секунд. Лежит над любой вкладкой — удаляют и из «Съёмок», и из формы.
struct UndoBar: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        ZStack {
            if let u = app.undo {
                HStack(spacing: 12) {
                    Text(u.text).font(.system(size: 13)).foregroundStyle(pal.ink4).lineLimit(1)
                        .shotNode("undo.text", text: u.text)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { app.takeUndo() }
                    } label: {
                        Text(app.lexicon.t("plan.undo")).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(pal.brass).padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .shotNode("undo.btn")
                }
                .padding(.vertical, 12).padding(.horizontal, 15)
                // Матовая, а не прозрачная (Алексей, 26.09): тон веба `--overlay-3` поверх
                // стекла, кант `--hairline` и тень `--glass-cast` — как `.undo` веба.
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.overlay3))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(pal.hairline, lineWidth: 1))
                .shadow(color: pal.glassCast, radius: 15, y: 10)
                .padding(.horizontal, 14).padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: u.token) {
                    try? await Task.sleep(for: .seconds(UndoOffer.seconds))
                    withAnimation(.timingCurve(0.25, 1, 0.4, 1, duration: 0.32)) { app.expireUndo(u.token) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.timingCurve(0.25, 1, 0.4, 1, duration: 0.32), value: app.undo?.token)
    }
}

// MARK: - Корзина

/// Лист «Корзина» (веб `#binSheet`): новые сверху, у каждой — «Вернуть»;
/// «Очистить корзину» стирает насовсем только после «Стереть».
struct BinSheet: View {
    @Bindable var app: AppModel
    let windowHeight: CGFloat
    @State private var asking = false
    @State private var contentHeight: CGFloat = 300
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
                Text(t.t("card.bin")).font(.system(size: 19, weight: .semibold)).tracking(-0.2).foregroundStyle(pal.ink)
                    .shotNode("bin.title")
                Text(t.t("bin.sub")).font(.system(size: 13)).foregroundStyle(pal.ink4).padding(.top, 5)
                if app.trashed.isEmpty {
                    Text(t.t("bin.empty")).font(.system(size: 14)).foregroundStyle(pal.ink5)
                        .padding(.top, 16).padding(.bottom, 4)
                        .shotNode("bin.empty")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(app.trashed.enumerated()), id: \.element.record.id) { i, item in
                            row(item.record, f, pal).shotNode("bin.row.\(i)")
                        }
                    }
                    Button { asking = true } label: {
                        // `.ghost` веба: 14, `--ink-4`.
                        Text(t.t("bin.clear")).font(.system(size: 14)).foregroundStyle(pal.ink4)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .shotNode("bin.clear")
                    .padding(.top, 14)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .shotNode("bin.sheet")
        .presentationDetents([.height(min(contentHeight, windowHeight * 0.86))])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $asking) {
            AskYesSheet(title: t.t("bin.clear"),
                        sub: t.t("bin.wipeAsk", ["n": t.count("unit.shoot", app.trashed.count)]),
                        ok: t.t("ask.wipe"), cancel: t.t("ask.cancel")) { yes in
                asking = false
                if yes { withAnimation(.easeOut(duration: 0.2)) { app.clearBin() } }
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.trashed.count)
    }

    private func row(_ s: Session, _ f: PlannerFacts, _ pal: Palette) -> some View {
        let who = f.words.clientName(s)
        return HStack(spacing: 12) {
            Group {
                if let n = f.words.iconName(s) { Icon(n, size: 18, line: 1.5) }
                else { Icon(genre: s.genre?.rawValue ?? "", size: 18, line: 1.5) }
            }
            .foregroundStyle(pal.brass)
            VStack(alignment: .leading, spacing: 2) {
                Text(who.isEmpty ? f.words.typeName(s) : who).font(.system(size: 15)).foregroundStyle(pal.ink).lineLimit(1)
                Text(f.dates.dMonShort(f.date(s.day)) + " · " + f.fmt(Double(s.start)) + " – " + f.fmt(Double(s.endMinute)))
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(pal.ink5)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { app.restoreSession(id: s.id) }
            } label: {
                Text(f.t.t("plan.undo")).font(.system(size: 13)).foregroundStyle(pal.brassDeep)
                    .padding(.vertical, 8).padding(.horizontal, 14)
                    .background(pal.press, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(pal.hair2).frame(height: 1) }
    }
}

/// Лист-вопрос (веб `#yesSheet`, `askYes`): заголовок, пояснение,
/// терракотовое «Стереть» и «Отмена». Подложка — тоже «Отмена».
struct AskYesSheet: View {
    let title: String
    let sub: String
    let ok: String
    let cancel: String
    let answer: (Bool) -> Void
    @State private var contentHeight: CGFloat = 240
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(pal.edge).frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10).padding(.bottom, 18)
            Text(title).font(.system(size: 19, weight: .semibold)).tracking(-0.2).foregroundStyle(pal.ink)
            Text(sub).font(.system(size: 13)).foregroundStyle(pal.ink4).padding(.top, 5)
                .fixedSize(horizontal: false, vertical: true)
            Button { answer(true) } label: {
                Text(ok).font(.system(size: 15, weight: .semibold)).foregroundStyle(pal.terra2)
                    .frame(maxWidth: .infinity).padding(.vertical, 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 26)
            .shotNode("ask.ok")
            Button { answer(false) } label: {
                Text(cancel).font(.system(size: 15)).foregroundStyle(pal.ink3)
                    .frame(maxWidth: .infinity).padding(.vertical, 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 34)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.hidden)
    }
}
