import SwiftUI

/// Таймбар — общий орган экранов «Свет» и «Карта» (план, § D.3): один
/// ползунок и одна лента на оба. Порт вёрстки веба (`#timebar`): строка
/// краёв (восход · «сейчас» · закат) → лента/барабан → ярус со слайдером.
///
/// Итерация 17 переносит прототип 3 в продукт: механика передачи разряда не
/// переизобретается, только подключается к настоящим суткам, погоде и луне.
public struct TimebarView: View {
    let state: TimebarState

    public init(_ state: TimebarState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 6) {
            edges
            RibbonView(state: state)
            ScrubView(state: state)
                .offset(x: state.laneShift)
                .opacity(state.laneOpacity)
        }
    }

    // MARK: - Края: восход, «сейчас», закат

    private var edges: some View {
        ZStack {
            HStack {
                edge(state.riseEdge)
                Spacer(minLength: 24)
                if let setEdge = state.setEdge { edge(setEdge) }
            }
            if state.nowButtonVisible {
                Button(state.nowButtonLabel) { state.jumpToNow() }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func edge(_ content: TimebarState.EdgeContent) -> some View {
        switch content {
        case .time(let icon, let minutes):
            Label {
                Text(state.clockString(minutes))
            } icon: {
                Icon(icon, size: 19, line: 1.6)
            }
        case .text(let text):
            Text(text)
        }
    }
}
