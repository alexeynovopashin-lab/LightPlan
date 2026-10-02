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

    /// Пара снимков (28е): `-LPShotSpoiler 1` — раскрыт сразу и прокручен к плашке неба.
    private static let shotOpen = UserDefaults.standard.bool(forKey: "LPShotSpoiler")
    @State private var expanded = LightSpoilerView.shotOpen
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme)
        if open {
            ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // `#spoilerBtn`: отступ 6 сверху, поле 13, по центру столбики
                // 17 (`--ink-4`), подпись 14/600 (`--ink-2`), шеврон 16 вниз
                // (`--ink-4`, линия 2,4), зазоры 8.
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        BarsGlyph()
                            .stroke(pal.ink4, style: StrokeStyle(lineWidth: 1.6 * 17 / 24, lineCap: .round, lineJoin: .round))
                            .frame(width: 17, height: 17)
                        Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(pal.ink2)
                        Icon("chevron", size: 16, line: 2.4)
                            .foregroundStyle(pal.ink4)
                            .rotationEffect(.degrees(expanded ? -90 : 90))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .shotNode("spoiler")
                .padding(.top, 6)

                if expanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            groupView(group, pal)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .task {
                guard Self.shotOpen else { return }
                try? await Task.sleep(for: .seconds(1))
                withAnimation(nil) { proxy.scrollTo("swatch", anchor: .center) }
            }
            }
        }
    }

    /// `.sky-swatch`: высота 92, скругление 14, 20 сверху, поля 12/14, слово
    /// 13/600 с разрядкой 0,2 цветом `--overlay` и тенью `0 1px 0 --hair-5`;
    /// градиент сверху вниз: зенит 0, высокий 38 %, средний 72 %, горизонт 100 %.
    private func swatchView(_ swatch: LightTelemetry.Swatch, _ pal: Palette) -> some View {
        let p = swatch.palette
        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(stops: [
                .init(color: Color(p.zenith), location: 0), .init(color: Color(p.high), location: 0.38),
                .init(color: Color(p.mid), location: 0.72), .init(color: Color(p.horizon), location: 1)
            ], startPoint: .top, endPoint: .bottom))
            .frame(height: 92)
            .overlay(alignment: .bottomLeading) {
                Text(swatch.word).font(.system(size: 13, weight: .semibold)).tracking(0.2)
                    .foregroundStyle(pal.overlay)
                    .shadow(color: pal.hair5, radius: 0, x: 0, y: 1)
                    .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .shotNode("spoiler.swatch")
            .id("swatch")
            .padding(.top, 20)
    }

    /// `.pro-group`: 20 сверху, 4 снизу, знак 15 (`--ink-4`), подпись 10/600
    /// прописными, разрядка 1,2, `--ink-7`. `.p-row`: поля 8, волосок
    /// `--hair-3`, ключ 13 (`--ink-4`), значение 13/500 (`--ink-2`, цифры
    /// одной ширины).
    private func groupView(_ group: LightTelemetry.ProGroup, _ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let swatch = group.swatch { swatchView(swatch, pal) }
            HStack(spacing: 8) {
                Icon(group.iconName, size: 15, line: 1.6).foregroundStyle(pal.ink4)
                Text(group.title).font(.system(size: 10, weight: .semibold)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(pal.ink7)
            }
            .padding(.top, 20).padding(.bottom, 4)

            ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    Text(row.label).font(.system(size: 13)).foregroundStyle(pal.ink4)
                    Spacer(minLength: 0)
                    Text(row.value).font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(row.value == "—" ? pal.ink4 : pal.ink2)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 8)
                .padding(.bottom, 1)
                .overlay(alignment: .bottom) { Rectangle().fill(pal.hair3).frame(height: 1) }
            }
        }
    }
}

/// Столбики кнопки «Подробно» — свой SVG в разметке веба (`M5 20V11M10 20V4
/// M15 20v-6M20 20V8`), не из `icons.js`.
private struct BarsGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        var p = Path()
        for (x, top) in [(5.0, 11.0), (10, 4), (15, 14), (20, 8)] {
            p.move(to: CGPoint(x: x, y: 20)); p.addLine(to: CGPoint(x: x, y: top))
        }
        return p.applying(CGAffineTransform(scaleX: k, y: k)).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
