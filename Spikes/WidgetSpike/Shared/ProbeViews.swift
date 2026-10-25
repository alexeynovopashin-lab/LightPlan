import AppIntents
import SwiftUI

// The lock-screen views live in Shared/ so the app can draw the same view for a layout check (`-ProbePreview`).

struct ProbeLockView: View {
    let state: ProbeAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                ProbeNextLabel(state: state).font(.subheadline.weight(.semibold))
                Spacer()
                ProbeCountdown(state: state).font(.title3.weight(.semibold))
            }
            if state.mode == .wedding { ProbeTimeline(state: state) }
            ProbeRequested(state: state)
            ProbeButtons()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Wedding: «до <next point>»; studio: «аренда до HH:mm». The label is as of the last update.
struct ProbeNextLabel: View {
    let state: ProbeAttributes.ContentState
    var body: some View {
        if state.mode == .studio {
            Text("Студия · аренда до \(state.rentEnd.formatted(date: .omitted, time: .shortened))")
        } else if state.next < state.points.count {
            Text("до \(state.points[state.next].name)")
        } else {
            Text("День закончился")
        }
    }
}

/// Ticks by itself. One `now`, a target checked to still lie ahead — a past one is an inverted range (crash).
struct ProbeCountdown: View {
    let state: ProbeAttributes.ContentState
    var body: some View {
        let now = Date()
        let target: Date? = state.mode == .studio
            ? state.rentEnd
            : (state.next < state.points.count ? state.points[state.next].at : nil)
        if let target, target > now {
            Text(timerInterval: now...target, countsDown: true).monospacedDigit()
        } else {
            Text("0:00").monospacedDigit()
        }
    }
}

/// The bar fills by itself from the first to the last point; dots and labels sit by time.
struct ProbeTimeline: View {
    let state: ProbeAttributes.ContentState

    var body: some View {
        if let first = state.points.first?.at, let last = state.points.last?.at, last > first {
            let span = last.timeIntervalSince(first)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    ProgressView(timerInterval: first...last, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.linear)
                        .frame(height: 6)
                        .offset(y: 3)
                    ForEach(Array(state.points.enumerated()), id: \.offset) { i, p in
                        let x = p.at.timeIntervalSince(first) / span * (w - 12)
                        let current = i == state.next - 1
                        Circle()
                            .fill(i < state.next ? Color.white : Color.white.opacity(0.35))
                            .frame(width: current ? 12 : 8, height: current ? 12 : 8)
                            .offset(x: x + (current ? 0 : 2), y: current ? 0 : 2)
                        VStack(spacing: 0) {
                            Text(p.name)
                            Text(p.at, format: .dateTime.hour().minute()).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 10))
                        .frame(width: 70)
                        .position(x: min(max(x + 6, 35), w - 35), y: 32)
                    }
                }
            }
            .frame(height: 44)
        }
    }
}

/// The visible proof that «+1 час» worked while the app stayed closed.
struct ProbeRequested: View {
    let state: ProbeAttributes.ContentState
    var body: some View {
        if let at = state.requestedAt {
            Text("✓ запрошено +1 час · \(at.formatted(date: .omitted, time: .standard)) · ×\(state.requests)")
                .font(.caption.weight(.semibold))
        }
    }
}

struct ProbeButtons: View {
    var body: some View {
        HStack(spacing: 8) {
            Link(destination: ProbeURL.admin) { label("Админ", "phone.fill") }
            Button(intent: PlusHourIntent()) { label("+1 час", "plus.circle.fill") }
            Link(destination: ProbeURL.music) { label("Плейлист", "music.note") }
        }
        .buttonStyle(.plain)
    }

    private func label(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(Capsule().fill(Color.white.opacity(0.2)))
    }
}
