import SwiftUI
import LightPlanCore
import LightPlanDomain
#if canImport(UIKit)
import UIKit
#endif

/// Прыжок по длинной странице (Алексей, 28.10: «кнопка наверх… договорились добавить на все длинные страницы»). Одна тихая
/// стеклянная кнопка с шевроном на оба конца (веб `jumpAttach`): у начала ведёт вниз, за серединой — вверх. Нужна, только
/// пока есть что листать: `Moodboard.jumpVisible` (прокрутка не короче 0,6 высоты окна). Стоит поверх содержимого справа
/// внизу, прокрутку держит сама — экрану нужен лишь `ScrollView`: `.scrollJump(app.lexicon, node: "…")`.
///
/// Два места кнопки. `.floating` — поверх содержимого справа внизу (мудборд, вид сохранён как был: у галереи 40 pt и `ink4`
/// (`.standard`), у папки 38 pt и `ink3` (`.folder`)). `.strip` — своя полоса 56 pt под прокруткой, пока кнопка нужна:
/// содержимое кончается над полосой и ничего под кнопкой не прячет (значок звонка в «Контактах», шеврон в карточке).
struct ScrollJump: ViewModifier {
    struct Look {
        var size: CGFloat = 40
        var strong = false          // `ink3` вместо `ink4`
        var trailing: CGFloat = 20
        var bottom: CGFloat = 24
        static let standard = Look()
        static let folder = Look(size: 38, strong: true, trailing: 24)
    }

    enum Placement { case floating, strip }
    /// Высота полосы под прокруткой.
    static let stripHeight: CGFloat = 56

    let lexicon: Lexicon
    let node: String
    var look: Look = .standard
    var placement: Placement = .strip
    /// `false` — кнопки нет (вид, где прокрутка не страница: лента дня).
    var enabled = true
    @Environment(\.colorScheme) private var scheme
    @State private var scrollable: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var window: CGFloat = 800
    /// Крайние смещения прокрутки — только для журнала нажатий (Debug).
    @State private var topY: CGFloat = 0
    @State private var bottomY: CGFloat = 0
    @State private var position = ScrollPosition(edge: .top)
    /// Полоса показана. Решает она сама по высоте окна **без** полосы, иначе окно, сжатое полосой, мигало бы на пороге.
    @State private var stripShown = false

    private struct Metrics: Equatable { var offset: CGFloat; var content: CGFloat; var container: CGFloat; var top: CGFloat; var bottom: CGFloat }

    /// Debug `-LPScrollJumpFloating YES` ставит кнопку поверх содержимого (прежнее место) — кадр «до» для сравнения с полосой.
    private var place: Placement {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "LPScrollJumpFloating") { return .floating }
        #endif
        return placement
    }

    @ViewBuilder func body(content: Content) -> some View {
        let placement = place
        let tracked = content
            .scrollPosition($position)
            .onScrollGeometryChange(for: Metrics.self) {
                Metrics(offset: $0.contentOffset.y, content: $0.contentSize.height, container: $0.containerSize.height,
                        top: -$0.contentInsets.top, bottom: $0.contentSize.height - $0.containerSize.height + $0.contentInsets.bottom)
            } action: { _, m in
                let full = m.container + (placement == .strip && stripShown ? Self.stripHeight : 0)
                topY = m.top; bottomY = m.bottom
                offset = m.offset; window = full; scrollable = max(0, m.content - full)
                if placement == .strip { stripShown = enabled && Self.stripVisible(content: m.content, container: m.container, shown: stripShown) }
                Self.log(node, scrollable, full)
            }
        switch placement {
        case .floating:
            tracked.overlay(alignment: .bottomTrailing) { jump(Palette(scheme)) }
        case .strip:
            VStack(spacing: 0) {
                tracked
                if stripShown {
                    HStack(spacing: 0) { Spacer(minLength: 0); jump(Palette(scheme)) }
                        .frame(height: Self.stripHeight)
                }
            }
        }
    }

    @ViewBuilder private func jump(_ pal: Palette) -> some View {
        let placement = place
        if enabled, placement == .strip || Moodboard.jumpVisible(scrollable: scrollable, screen: window) {
            let down = Moodboard.jumpGoesDown(offset: offset, scrollable: scrollable)
            Button {
                Self.logTap(node, down: down, offset: offset, topY: topY, bottomY: bottomY)
                withAnimation(.easeInOut(duration: 0.35)) { position.scrollTo(edge: down ? .bottom : .top) }
            } label: {
                Icon("chevron", size: 18, line: 2.2).rotationEffect(.degrees(down ? 90 : -90))
                    .foregroundStyle(look.strong ? pal.ink3 : pal.ink4)
                    .frame(width: look.size, height: look.size)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lexicon.t(down ? "mb.jumpEnd" : "mb.jumpTop"))
            .padding(.trailing, look.trailing).padding(.bottom, placement == .floating ? look.bottom : 0)
            .shotNode(node, text: down ? "down" : "up")
        }
    }

    private static func logTap(_ node: String, down: Bool, offset: CGFloat, topY: CGFloat, bottomY: CGFloat) {
        #if DEBUG
        guard let path = UserDefaults.standard.string(forKey: "LPScrollJumpLog") else { return }
        let line = String(format: "tap\t%@\tdown=%d offset=%.0f top=%.0f bottom=%.0f\n", node, down ? 1 : 0, offset, topY, bottomY)
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        #endif
    }

    /// Нужна ли полоса: правило мудборда по окну **без** полосы (`container` — окно как оно сейчас, `shown` — полоса уже стоит и
    /// съела `stripHeight`), поэтому при любых `shown` ответ один и тот же и на пороге ничего не мигает.
    static func stripVisible(content: CGFloat, container: CGFloat, shown: Bool) -> Bool {
        let full = container + (shown ? stripHeight : 0)
        return Moodboard.jumpVisible(scrollable: max(0, content - full), screen: full)
    }

    /// Стенд высот (Debug): `-LPScrollJumpLog <файл>` дописывает «узел  прокрутка  окно  во скольких окнах».
    private static func log(_ node: String, _ scrollable: CGFloat, _ window: CGFloat) {
        #if DEBUG
        guard let path = UserDefaults.standard.string(forKey: "LPScrollJumpLog"), window > 0 else { return }
        let line = String(format: "%@\t%.0f\t%.0f\t%.2f\n", node, scrollable, window, (scrollable + window) / window)
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
        #endif
    }
}

extension View {
    /// Кнопка прыжка на длинную прокрутку; `node` — имя узла для снимков и отчёта высот.
    func scrollJump(_ lexicon: Lexicon, node: String, look: ScrollJump.Look = .standard, placement: ScrollJump.Placement = .strip,
                    enabled: Bool = true) -> some View {
        modifier(ScrollJump(lexicon: lexicon, node: node, look: look, placement: placement, enabled: enabled))
    }
}
