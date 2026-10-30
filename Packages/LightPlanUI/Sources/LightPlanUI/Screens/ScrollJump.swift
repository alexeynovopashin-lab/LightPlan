import SwiftUI
import LightPlanCore
import LightPlanDomain
#if canImport(UIKit)
import UIKit
#endif

/// Прыжок по длинной странице (Алексей, 28.10: «кнопка наверх… договорились добавить на все длинные страницы»). Одна тихая
/// стеклянная кнопка с шевроном на оба конца (веб `jumpAttach`): у начала ведёт вниз, за серединой — вверх. Нужна, только
/// пока есть что листать: `Moodboard.jumpVisible` (прокрутка не короче 0,6 высоты окна). Парит поверх содержимого справа
/// внизу, как в мудборде (галерея 40 pt и `ink4` — `.standard`, папка 38 pt и `ink3` — `.folder`), прокрутку держит сама —
/// экрану нужен лишь `ScrollView`: `.scrollJump(app.lexicon, node: "…")`.
///
/// Своей полосы под прокруткой нет (Алексей, 30.10: «у Apple полно парящих кнопок… удаляй черную плашку»). Чтобы кнопка не
/// закрыла нижнее (значок звонка в «Контактах», шеврон в «Клиентах»), низ прокрутки получает запас `reserve` — кнопка с её
/// отступом снизу: последняя строка доезжает выше кнопки. Запас стоит всегда, а не с порогом кнопки: порог считается по окну
/// вместе с запасом и по содержимому без него, так что запас его не трогает, и низ страницы не прыгает, когда кнопка
/// появляется или гаснет. Мудборд запаса не берёт (`reserve: false`) — его вид сохранён пиксель в пиксель.
struct ScrollJump: ViewModifier {
    struct Look {
        var size: CGFloat = 40
        var strong = false          // `ink3` вместо `ink4`
        var trailing: CGFloat = 20
        var bottom: CGFloat = 24
        static let standard = Look()
        static let folder = Look(size: 38, strong: true, trailing: 24)
    }

    /// Запас низа прокрутки под кнопку: сама кнопка и её отступ снизу (64 pt у `.standard`).
    static func reserve(_ look: Look) -> CGFloat { look.size + look.bottom }

    let lexicon: Lexicon
    let node: String
    var look: Look = .standard
    /// Низ прокрутки получает запас `reserve` (все страницы, кроме мудборда).
    var reserves = true
    /// `false` — кнопки нет (вид, где прокрутка не страница: лента дня).
    var enabled = true
    /// Позиция прокрутки самого экрана. Если экран листает программно (`scrollTo`), он отдаёт её сюда: два `.scrollPosition` на одной
    /// прокрутке не уживаются — внутренний, этот, перекрывал внешнюю, и экранный `scrollTo` молча не доходил (30.1: лента года
    /// открывалась на январе, лента дня — на 00:00).
    var screenPosition: Binding<ScrollPosition>?
    @Environment(\.colorScheme) private var scheme
    @State private var scrollable: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var window: CGFloat = 800
    /// Крайние смещения прокрутки — только для журнала нажатий (Debug).
    @State private var topY: CGFloat = 0
    @State private var bottomY: CGFloat = 0
    @State private var ownPosition = ScrollPosition(edge: .top)

    private var position: Binding<ScrollPosition> { screenPosition ?? $ownPosition }

    private struct Metrics: Equatable { var offset: CGFloat; var content: CGFloat; var container: CGFloat; var top: CGFloat; var bottom: CGFloat }

    func body(content: Content) -> some View {
        // Запас — отступом безопасной области самой прокрутки (её `contentInsets`), а не полями содержимого: вложенные прокрутки
        // его не наследуют, высота содержимого не меняется. Кнопка висит снаружи и запаса не видит.
        let reserve = enabled && reserves ? Self.reserve(look) : 0
        return content
            .safeAreaPadding(.bottom, reserve)
            .scrollPosition(position)
            .onScrollGeometryChange(for: Metrics.self) {
                Metrics(offset: $0.contentOffset.y, content: $0.contentSize.height, container: $0.containerSize.height,
                        top: -$0.contentInsets.top, bottom: $0.contentSize.height - $0.containerSize.height + $0.contentInsets.bottom)
            } action: { _, m in
                topY = m.top; bottomY = m.bottom
                offset = m.offset
                (scrollable, window) = Self.measure(content: m.content, container: m.container, reserve: reserve)
                Self.log(node, scrollable, window)
            }
            .overlay(alignment: .bottomTrailing) { jump(Palette(scheme)) }
    }

    @ViewBuilder private func jump(_ pal: Palette) -> some View {
        if enabled, Moodboard.jumpVisible(scrollable: scrollable, screen: window) {
            let down = Moodboard.jumpGoesDown(offset: offset, scrollable: scrollable)
            Button {
                Self.logTap(node, down: down, offset: offset, topY: topY, bottomY: bottomY)
                withAnimation(.easeInOut(duration: 0.35)) { position.wrappedValue.scrollTo(edge: down ? .bottom : .top) }
            } label: {
                Icon("chevron", size: 18, line: 2.2).rotationEffect(.degrees(down ? 90 : -90))
                    .foregroundStyle(look.strong ? pal.ink3 : pal.ink4)
                    .frame(width: look.size, height: look.size)
                    .glassEffect(.regular, in: Circle())
                    // У `.plain` нажимается только нарисованное — штрих шеврона, а стекло нет: парящий круг пропускал тап в
                    // плитку или строку под собой (замер 30.10 в симуляторе, и у мудборда до правки). Нажимается весь круг.
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lexicon.t(down ? "mb.jumpEnd" : "mb.jumpTop"))
            .padding(.trailing, look.trailing).padding(.bottom, look.bottom)
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

    /// Прокрутка и окно для порога кнопки. Окно прокрутки приходит уже без запаса (замер 30.10: 783 → 719 pt у «Съёмок») —
    /// запас возвращаем, иначе порог сдвинулся бы на 64 pt против мудборда и прежней полосы.
    static func measure(content: CGFloat, container: CGFloat, reserve: CGFloat) -> (scrollable: CGFloat, window: CGFloat) {
        let full = container + reserve
        return (max(0, content - full), full)
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
    /// Кнопка прыжка на длинную прокрутку; `node` — имя узла для снимков и отчёта высот; `reserve: false` — без запаса низа
    /// (мудборд). Экран со своим `scrollTo` отдаёт позицию сюда (`position:`), а не вешает свой `.scrollPosition` рядом.
    func scrollJump(_ lexicon: Lexicon, node: String, look: ScrollJump.Look = .standard, reserve: Bool = true,
                    enabled: Bool = true, position: Binding<ScrollPosition>? = nil) -> some View {
        modifier(ScrollJump(lexicon: lexicon, node: node, look: look, reserves: reserve, enabled: enabled, screenPosition: position))
    }
}
