import SwiftUI

/// Песочница передачи разряда. Всё, что не край суток, нарочно отсутствует:
/// ни солнца, ни погоды, ни записей — иначе непонятно, что именно проверяем.
struct SpikeScreen: View {
    @State private var model = TimebarModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Spacer(minLength: 0)

            // Ярус: натяжение и срыв двигают его целиком.
            ScrubView(model: model)
                .offset(x: model.laneShift)
                .opacity(model.laneOpacity)

            numbers
            journal
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(white: 0.05).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(model.clock)
                .font(.system(size: 54, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private var numbers: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
            GridRow {
                cell("взвод", String(format: "%3.0f%%", model.wind.progress * 100))
                cell("сторона", model.wind.side == 0 ? "—" : (model.wind.side > 0 ? "вперёд" : "назад"))
                cell("срывов", "\(model.snaps) / \(model.grabs)")
            }
            GridRow {
                cell("худший кадр", String(format: "%.1f мс", model.meter.worstMs))
                cell("средне", String(format: "%.0f к/с", model.meter.averageFps))
                cell("дольше 16 мс", "\(model.meter.late)")
            }
        }
        .font(.caption.monospacedDigit())
    }

    private func cell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).foregroundStyle(.tertiary)
            Text(value).foregroundStyle(.primary)
        }
    }

    private var journal: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.journal, id: \.self) { line in
                    Text(line)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 150)
    }
}

#Preview {
    SpikeScreen()
}
