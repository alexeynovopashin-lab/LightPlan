import SwiftUI

/// Песочница передачи разряда. Всё, что не край суток, нарочно отсутствует:
/// ни солнца, ни погоды, ни записей — иначе непонятно, что именно проверяем.
struct SpikeScreen: View {
    @State private var model = TimebarModel()
    @State private var snapKind = Haptics.Snap.sharp
    @State private var windBuzz = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            haptics
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

    /// Отдачи в вебе на iPhone нет вовсе, поэтому её характер выбирается здесь
    /// же пальцем, а не в следующей сборке.
    private var haptics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Удар на срыве", selection: $snapKind) {
                ForEach(Haptics.Snap.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: snapKind) { _, kind in
                model.haptics.snapKind = kind
                model.haptics.snap()          // сразу дать пощупать
            }

            HStack {
                Toggle("Гудение на взводе", isOn: $windBuzz)
                    .font(.caption)
                    .onChange(of: windBuzz) { _, on in model.haptics.windBuzz = on }
                Button("Ударить") { model.haptics.snap() }
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
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
