import SwiftUI

/// Спойлер «Подробно» — порт `.pro`/`#spoilerBtn`/`#proBody` веба. `open`
/// (Просто/Астро) — режим экрана: `false` прячет спойлер целиком, как
/// `body:not(.pro-mode) .pro { display: none }` в CSS. Разворот/сворачивание
/// самого спойлера — отдельный, локальный `@State`: кнопка не завязана на
/// Просто/Астро, только на то, нажал ли Алексей по ней сейчас.
struct LightSpoilerView: View {
    let groups: [LightTelemetry.ProGroup]
    /// Режим экрана — Просто/Астро. Имя внутри повторяет то, что снаружи
    /// зовётся `proMode`, здесь короче, конфликта нет: это разные типы.
    let open: Bool
    let title: String

    @State private var expanded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if open {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { expanded.toggle() }
                } label: {
                    HStack {
                        Spacer()
                        // Веб рисует у кнопки свой значок — четыре столбика
                        // разной высоты, набранные прямо в разметке, а не из
                        // `icons.js`. В библиотеке знаков (итерация 15) такого
                        // столбчатого глифа нет — заводить его ради одной
                        // кнопки не тот масштаб; текст и шеврон говорят то же.
                        Text(title)
                        Icon("chevron", size: 14, line: 1.8)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                        Spacer()
                    }
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LightScreenTheme.ink4(colorScheme))

                if expanded {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            groupView(group)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func groupView(_ group: LightTelemetry.ProGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Icon(group.iconName, size: 15, line: 1.6)
                Text(group.title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(LightScreenTheme.ink4(colorScheme))

            VStack(spacing: 0) {
                ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.label).font(.system(size: 13))
                            .foregroundStyle(LightScreenTheme.ink4(colorScheme))
                        Spacer()
                        Text(row.value).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(row.value == "—" ? LightScreenTheme.ink4(colorScheme) : LightScreenTheme.ink(colorScheme))
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }
}
