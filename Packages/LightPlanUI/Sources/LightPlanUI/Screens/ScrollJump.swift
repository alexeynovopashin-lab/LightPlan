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
/// Вид мудборда сохранён как был: у галереи 40 pt и `ink4` (`.standard`), у папки 38 pt и `ink3` (`.folder`).
struct ScrollJump: ViewModifier {
    struct Look {
        var size: CGFloat = 40
        var strong = false          // `ink3` вместо `ink4`
        var trailing: CGFloat = 20
        var bottom: CGFloat = 24
        static let standard = Look()
        static let folder = Look(size: 38, strong: true, trailing: 24)
    }

    let lexicon: Lexicon
    let node: String
    var look: Look = .standard
    /// `false` — кнопки нет (вид, где прокрутка не страница: лента дня).
    var enabled = true
    @Environment(\.colorScheme) private var scheme
    @State private var scrollable: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var window: CGFloat = 800
    @State private var position = ScrollPosition(edge: .top)

    private struct Metrics: Equatable { var offset: CGFloat; var scrollable: CGFloat; var window: CGFloat }

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: Metrics.self) {
                Metrics(offset: $0.contentOffset.y, scrollable: max(0, $0.contentSize.height - $0.containerSize.height),
                        window: $0.containerSize.height)
            } action: { _, m in
                offset = m.offset; scrollable = m.scrollable; window = m.window
                Self.log(node, m.scrollable, m.window)
            }
            .overlay(alignment: .bottomTrailing) { jump(Palette(scheme)) }
    }

    @ViewBuilder private func jump(_ pal: Palette) -> some View {
        if enabled, Moodboard.jumpVisible(scrollable: scrollable, screen: window) {
            let down = Moodboard.jumpGoesDown(offset: offset, scrollable: scrollable)
            Button {
                withAnimation(.easeInOut(duration: 0.35)) { position.scrollTo(edge: down ? .bottom : .top) }
            } label: {
                Icon("chevron", size: 18, line: 2.2).rotationEffect(.degrees(down ? 90 : -90))
                    .foregroundStyle(look.strong ? pal.ink3 : pal.ink4)
                    .frame(width: look.size, height: look.size)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lexicon.t(down ? "mb.jumpEnd" : "mb.jumpTop"))
            .padding(.trailing, look.trailing).padding(.bottom, look.bottom)
            .shotNode(node, text: down ? "down" : "up")
        }
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
    func scrollJump(_ lexicon: Lexicon, node: String, look: ScrollJump.Look = .standard, enabled: Bool = true) -> some View {
        modifier(ScrollJump(lexicon: lexicon, node: node, look: look, enabled: enabled))
    }
}
