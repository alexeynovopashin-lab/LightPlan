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
    @Environment(\.colorScheme) private var colorScheme

    public init(_ state: TimebarState, showRibbon: Bool = true) {
        self.state = state
        self.showRibbon = showRibbon
    }

    public var body: some View {
        let pal = Palette(colorScheme)
        VStack(spacing: 8) {
            edges(pal)
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
        .background(pal.surface)
        .overlay(alignment: .top) { Rectangle().fill(pal.hair).frame(height: 1) }
    }

    // MARK: - Края: восход, «сейчас», закат

    private func edges(_ pal: Palette) -> some View {
        ZStack {
            HStack(spacing: 0) {
                edge(state.riseEdge, pal).shotNode("edge.rise")
                Spacer(minLength: 24)
                if let setEdge = state.setEdge { edge(setEdge, pal).shotNode("edge.set") }
            }
            if state.nowButtonVisible {
                // `.now-tick`: 11/600, разрядка 0,4, `--brass-deep`; поле
                // 9 · 14 — для пальца, а не для глаза.
                Button { state.jumpToNow() } label: {
                    Text(state.nowButtonLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(pal.brassDeep)
                        .padding(.vertical, 9).padding(.horizontal, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .shotNode("now", text: state.nowButtonLabel)
            }
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
