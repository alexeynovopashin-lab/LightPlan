import SwiftUI

/// Вид настроек веба (`#s-set`, итерация 19б): шапка, сегмент, строки
/// разделов. До 19б экран был системным списком — 19а сослалась на решение
/// «стекло в нативе системное», но оно про стекло, а не про список и
/// сегменты; эталон вида — веб (§ 5.4 плана).

/// Шапка экрана настроек: имя приложения 16/600 и строка сборки 11/500
/// прописными, как у шапки «Света».
struct SetHeader: View {
    let title: String
    let sub: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 16, weight: .semibold)).tracking(-0.2)
                .foregroundStyle(pal.ink)
                .shotNode("header.name", text: title)
                .frame(height: 18)
            Text(sub).font(.system(size: 11, weight: .medium)).tracking(0.6).textCase(.uppercase)
                .foregroundStyle(pal.ink4)
                .shotNode("header.date", text: sub)
                .frame(height: 13)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }
}

/// `.seg`: подложка `--sheet` со скруглением 12 и полем 3, кнопки 14/550 с
/// полем 11 и скруглением 10; выбранная — `--seg-on` и `--ink`, прочие —
/// `--ink-4`.
struct WebSeg<V: Hashable>: View {
    let options: [(label: String, value: V)]
    @Binding var selection: V
    /// Имена узлов пары по кнопкам (`mode.simple`, `mode.pro`).
    var nodes: [String] = []
    var sky: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme)
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].value == selection
                Button { withAnimation(.easeInOut(duration: 0.3)) { selection = options[i].value } } label: {
                    Text(options[i].label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(on ? pal.ink : pal.ink4)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(11)
                        .background(on ? pal.segOn : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .shotNode(i < nodes.count ? nodes[i] : "", text: options[i].label)
            }
        }
        .padding(3)
        .background(pal.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .trailing) {
            if sky {
                GeometryReader { g in SegSky().frame(width: g.size.width / 2 - 3).frame(maxWidth: .infinity, alignment: .trailing) }
                    .padding(3)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }
}

/// Небо на кнопке «Астро» (`.seg-sky`): Большая Медведица и Орион латунью —
/// звёзды 0,8, линии 1 pt на 0,28. Рисунок и места — из разметки веба.
struct SegSky: View {
    @Environment(\.colorScheme) private var colorScheme

    private static let ursa: (lines: [[CGPoint]], stars: [(CGPoint, CGFloat)]) = (
        [[CGPoint(x: 8, y: 26), CGPoint(x: 24, y: 20), CGPoint(x: 39, y: 20), CGPoint(x: 52, y: 26),
          CGPoint(x: 56, y: 40), CGPoint(x: 86, y: 44), CGPoint(x: 88, y: 26), CGPoint(x: 52, y: 26)]],
        [(CGPoint(x: 8, y: 26), 3), (CGPoint(x: 24, y: 20), 2.4), (CGPoint(x: 39, y: 20), 2.7), (CGPoint(x: 52, y: 26), 2.1),
         (CGPoint(x: 56, y: 40), 2.6), (CGPoint(x: 86, y: 44), 2.6), (CGPoint(x: 88, y: 26), 3.1)])
    private static let orion: (lines: [[CGPoint]], stars: [(CGPoint, CGFloat)]) = (
        [[CGPoint(x: 18, y: 28), CGPoint(x: 62, y: 24)], [CGPoint(x: 18, y: 28), CGPoint(x: 30, y: 60)],
         [CGPoint(x: 62, y: 24), CGPoint(x: 56, y: 55)], [CGPoint(x: 30, y: 60), CGPoint(x: 43, y: 58), CGPoint(x: 56, y: 55)],
         [CGPoint(x: 30, y: 60), CGPoint(x: 26, y: 98)], [CGPoint(x: 56, y: 55), CGPoint(x: 66, y: 94)]],
        [(CGPoint(x: 18, y: 28), 4.2), (CGPoint(x: 62, y: 24), 3.4), (CGPoint(x: 30, y: 60), 3.2), (CGPoint(x: 43, y: 58), 3.2),
         (CGPoint(x: 56, y: 55), 3.2), (CGPoint(x: 26, y: 98), 3), (CGPoint(x: 66, y: 94), 4.2)])

    var body: some View {
        let brass = Palette(colorScheme).brass
        Canvas { ctx, size in
            // `.ss-ursa { left: 4%; top: 30%; width: 30% }`, viewBox 100×56;
            // `.ss-orion { right: 6%; top: 14%; width: 13% }`, viewBox 84×116.
            draw(Self.ursa, in: &ctx, origin: CGPoint(x: size.width * 0.04, y: size.height * 0.30),
                 scale: size.width * 0.30 / 100, brass: brass)
            let ow = size.width * 0.13
            draw(Self.orion, in: &ctx, origin: CGPoint(x: size.width * 0.94 - ow, y: size.height * 0.14),
                 scale: ow / 84, brass: brass)
        }
    }

    private func draw(_ c: (lines: [[CGPoint]], stars: [(CGPoint, CGFloat)]), in ctx: inout GraphicsContext,
                      origin: CGPoint, scale: CGFloat, brass: Color) {
        let at = { (p: CGPoint) in CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
        for line in c.lines {
            var path = Path()
            path.addLines(line.map(at))
            ctx.stroke(path, with: .color(brass.opacity(0.28)), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        }
        for (p, r) in c.stars {
            let q = at(p), rr = r * scale
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2)), with: .color(brass.opacity(0.8)))
        }
    }
}

/// `.seg-note`: 12 pt, строка 18, `--ink-6`, поля 10 · 24 · 0.
struct SetNote: View {
    let text: String
    var node: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .lineSpacing(18 - 14.3)
            .foregroundStyle(Palette(colorScheme).ink6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .shotNode(node ?? "", text: text)
            // Строка 18 у веба делит лишнюю высоту поровну сверху и снизу
            // строки; межстрочный интервал даёт её только между строками.
            .padding(.vertical, (18 - 14.3) / 2)
            .padding(.horizontal, 24)
            .padding(.top, 10)
    }
}

/// `.item`: поля 15 · 24, 15 pt, волосок `--hair-2` снизу; слева знак 17
/// (`--ink-4`, линия 1,6) и зазор 11, справа значение 14 (`--ink-4`, цифры
/// одной ширины) и шеврон 16 (линия 2,4).
struct SetItemRow: View {
    let icon: String?
    let title: String
    let value: String
    var chevron = true
    var dim = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme)
        HStack(spacing: 12) {
            HStack(spacing: 11) {
                if let icon { Icon(icon, size: 17, line: 1.6).foregroundStyle(pal.ink4) }
                Text(title).font(.system(size: 15)).foregroundStyle(pal.ink)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                if !value.isEmpty {
                    Text(value).font(.system(size: 14).monospacedDigit()).foregroundStyle(pal.ink4).lineLimit(1)
                }
                if chevron {
                    Icon("chevron", size: 16, line: 2.4).foregroundStyle(pal.ink4)
                        .padding(.trailing, -4)
                }
            }
        }
        .frame(minHeight: 18)
        .padding(.horizontal, 24)
        .padding(.top, 15).padding(.bottom, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(pal.hair2).frame(height: 1) }
        .opacity(dim ? 0.4 : 1)
        .contentShape(Rectangle())
    }
}

/// `.sec-label`: 10/600 прописными, разрядка 1,2, `--ink-7`; поля 6 · 24 · 8
/// у первой подписи главы и 30 · 24 · 8 у следующих.
struct SecLabel: View {
    let text: String
    var first = false
    var node: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold)).tracking(1.2).textCase(.uppercase)
            .foregroundStyle(Palette(colorScheme).ink7)
            .shotNode(node ?? "", text: text)
            .frame(height: 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, first ? 6 : 30)
            .padding(.bottom, 8)
    }
}

/// `.chips`: фишки с переносом, зазор 8, отступ 12 и поле 12 · 24 сверху. Выбранная —
/// 13/600 латунью на `--press-brass`, прочие — 13 `--ink-3` на `--press`;
/// поле 10 · 15, скругление 20.
struct Chips<V: Hashable>: View {
    let options: [(label: String, value: V)]
    @Binding var selection: V
    var node: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme)
        FlowLayout(spacing: 8) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].value == selection
                Button { selection = options[i].value } label: {
                    Text(options[i].label)
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? pal.brass : pal.ink3)
                        .padding(.vertical, 10).padding(.horizontal, 15)
                        .background(on ? pal.pressBrass : pal.press, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        // `.chips { margin-top: 12 }` и своё поле 12 сверху у каждой строки
        // фишек главы (`style="padding: 12px 24px 0"`) — вместе 24.
        .padding(.top, 12)
        .shotNode(node ?? "")
        .padding(.top, 12)
    }
}

/// Раскладка с переносом строк — `flex-wrap: wrap` веба.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { y += row + spacing; x = 0; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}

/// Страница главы: заголовок 15/700 (`.grp-label`, поле 26 сверху) и
/// содержимое; кнопка «назад» — системная (жест смахивания сохраняется),
/// вкладки на время главы скрыты, как их закрывает лист главы у веба.
struct ChapterPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 15, weight: .bold)).tracking(-0.2)
                    .foregroundStyle(pal.ink)
                    .shotNode("title", text: title)
                    .frame(height: 18)
                    .padding(.horizontal, 24)
                    // 26 у веба от его строки «назад» (34); системная панель
                    // навигации на 6 выше, заголовок встаёт туда же на 20.
                    .padding(.top, 20)
                content()
            }
            .padding(.bottom, 34)
        }
        .background(pal.surface)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #endif
    }
}

/// `.set-in`: поле 16 pt на `--sheet`, поле 14 · 15, скругление 12, отступ
/// 12 сверху.
struct SetInputStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        let pal = Palette(colorScheme)
        content
            .font(.system(size: 16))
            .foregroundStyle(pal.ink)
            .padding(.vertical, 14).padding(.horizontal, 15)
            .background(pal.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.top, 12)
    }
}

/// `.data-btn`: 15/600 латунью на `--press-warm`, поле 13 · 15, скругление
/// 12, отступ 10 сверху.
struct DataButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        let pal = Palette(colorScheme)
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(pal.brass)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 13).padding(.horizontal, 15)
            .background(pal.pressWarm, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .padding(.horizontal, 24)
            .padding(.top, 10)
    }
}
