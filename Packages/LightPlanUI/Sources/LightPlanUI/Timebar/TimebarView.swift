import SwiftUI

/// Таймбар — общий орган экранов «Свет» и «Карта» (план, § D.3): один
/// ползунок и одна лента на оба. Порт вёрстки веба (`#timebar`): строка
/// краёв (восход · «сейчас» · закат) → лента/барабан → ярус со слайдером.
///
/// Итерация 17 переносит прототип 3 в продукт: механика передачи разряда не
/// переизобретается, только подключается к настоящим суткам, погоде и луне.
public struct TimebarView: View {
    let state: TimebarState
    /// Лента суток — второй контроль, только в «Астро» (веб: `.ribbon-wrap`
    /// скрыт без `body.pro-mode`). До 19б приложение показывало её всегда
    /// (найдено 19а).
    let showRibbon: Bool
    /// На карте таймбар лежит на общем стекле дока: ни поверхности, ни
    /// волоска (`body[data-tab="s-map"] .timebar` веба).
    let bare: Bool
    /// Свой ответ кнопке «↺ сейчас»: экран AR (29.8в.3) возвращает ручку плавно, кадр за кадром. `nil` — как у
    /// «Света» и «Карты»: `jumpToNow()`.
    let onNow: (() -> Void)?
    /// Свой цвет слова «Сейчас»: экран AR кладёт панель с таймбаром на стекло, тёмное над любым небом (замер 29.8в.10:
    /// яркость стекла под словом 0,056 над белым и 0,036 над голубым), и латунь `brassDeep` держит там 3,26 и 4,01 к 1.
    /// `nil` — цвет «Света» и «Карты».
    let nowInk: Color?
    /// 30з.1: на «Свете» время рассвета и заката стоит у оснований дуги, строки краёв над лентой нет.
    let showEdges: Bool
    @Environment(\.colorScheme) private var colorScheme

    public init(_ state: TimebarState, showRibbon: Bool = true, bare: Bool = false, nowInk: Color? = nil, showEdges: Bool = true,
                onNow: (() -> Void)? = nil) {
        self.state = state
        self.showRibbon = showRibbon
        self.bare = bare
        self.nowInk = nowInk
        self.showEdges = showEdges
        self.onNow = onNow
    }

    public var body: some View {
        let pal = Palette(colorScheme)
        VStack(spacing: 8) {
            if showEdges { edges(pal) }
            if showRibbon {
                RibbonView(state: state).shotNode("ribbon")
            }
            ScrubView(state: state)
                .offset(x: state.laneShift)
                .opacity(state.laneOpacity)
                .shotNode("track")
        }
        // `.timebar`: поля 12 · 24 · 14, поверхность экрана, волосок сверху.
        .padding(EdgeInsets(top: 13, leading: 24, bottom: 14, trailing: 24))   // 1 — волосок `border-top`
        .background(bare ? .clear : pal.surface)
        // 30з.1: строки краёв нет — «↺ Сейчас» плавает над правым краем верхней кромки таймбара и места не занимает (высота шкалы та же).
        .overlay(alignment: .topTrailing) {
            if !showEdges && state.nowButtonVisible { nowButton(pal).padding(.trailing, 10).offset(y: -26) }
        }
        .overlay(alignment: .top) { Rectangle().fill(bare ? .clear : pal.hair).frame(height: 1) }
    }

    // MARK: - Края: восход, «сейчас», закат

    /// `.now-tick`: 11/600, разрядка 0,4, `--brass-deep`; поле
    /// 9 · 14 — для пальца, а не для глаза.
    private func nowButton(_ pal: Palette) -> some View {
        Button { if let onNow { onNow() } else { state.jumpToNow() } } label: {
            Text(state.nowButtonLabel)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(nowInk ?? pal.brassDeep)
                .padding(.vertical, 9).padding(.horizontal, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("now", text: state.nowButtonLabel)
    }

    private func edges(_ pal: Palette) -> some View {
        ZStack {
            HStack(spacing: 0) {
                edge(state.riseEdge, pal).shotNode("edge.rise")
                Spacer(minLength: 24)
                if let setEdge = state.setEdge { edge(setEdge, pal).shotNode("edge.set") }
            }
            if state.nowButtonVisible { nowButton(pal) }
        }
        .frame(height: 19)
    }

    /// `.edge`: знак 19 (`--brass-deep`, линия 1,6), зазор 7, время 11/500
    /// цифрами одной ширины, `--ink-4`.
    @ViewBuilder
    private func edge(_ content: TimebarState.EdgeContent, _ pal: Palette) -> some View {
        switch content {
        case .time(let icon, let minutes):
            HStack(spacing: 7) {
                Icon(icon, size: 19, line: 1.6).foregroundStyle(pal.brassDeep)
                Text(state.clockString(minutes))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(pal.ink4)
            }
        case .text(let text):
            Text(text)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(pal.ink4)
        }
    }
}
