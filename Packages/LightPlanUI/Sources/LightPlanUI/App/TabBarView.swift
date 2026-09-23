import SwiftUI

/// Панель вкладок — `.tabbar` веба, а не системная `TabView`. 19б оставила
/// системную, прочитав решение 21 сентября «стекло в нативе — системное»
/// как «панель — системная»; Алексей: «неверно истолкована запись, там тоже
/// была речь о стекле. мы много где использовали визуальные костыли,
/// понимая, что в будущем отбросим их, будем использовать "встроенное
/// стекло"» (DECISIONS «Панель вкладок — вид прототипа на встроенном
/// стекле», 23 сентября 2026). Значит: вид и состав — веба, подложка —
/// системное стекло вместо `backdrop-filter: blur(20px) saturate(1.5)`.
///
/// Числа веба (`tools/shot.js`, узлы `tab.*`): высота 84 вместе с полосой
/// «домой» (правило `env(safe-area-inset-bottom) + 12` в вебе перебито
/// общим `padding: 9px 6px 24px` ниже по файлу — в PWA на телефоне тоже 84),
/// волосок `--hair` сверху (1, занимает место), поле 9, вкладка — поле 5, знак 24 с линией 1,5,
/// зазор 4, подпись 10/500. Активная: знак `--brass`, подпись `--ink`;
/// прочие — `--ink-6`.
///
/// «Карта» (итерация 20) и «Съёмки» (21) стоят на местах веба, но ещё не
/// нажимаются — экранов нет (решение исполнителя, обратимое).
struct TabBarView: View {
    @Binding var tab: AppTab
    let lexicon: Lexicon
    @Environment(\.colorScheme) private var colorScheme

    static let height: CGFloat = 84

    var body: some View {
        let pal = Palette(colorScheme)
        HStack(spacing: 0) {
            item(.light, glyph: .light, title: "nav.light", node: "light", pal: pal)
            item(nil, glyph: .map, title: "nav.map", node: "map", pal: pal)
            item(nil, glyph: .shoots, title: "nav.shoots", node: "shoots", pal: pal)
            item(.settings, glyph: .settings, title: "nav.settings", node: "settings", pal: pal)
        }
        .padding(.horizontal, 6)
        // 9 поля и 1 волоска: у веба `border-top` занимает место.
        .padding(.top, 10)
        .frame(height: Self.height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background {
            // Края стекла — за экраном: системное стекло светит кромкой по
            // всему контуру, а у веба край один — волосок сверху.
            Rectangle().fill(pal.bar).glassEffect(.regular, in: Rectangle())
                .padding(.horizontal, -4).padding(.bottom, -4)
        }
        .overlay(alignment: .top) { Rectangle().fill(pal.hair).frame(height: 1) }
    }

    private func item(_ target: AppTab?, glyph: TabGlyph.Kind, title: String, node: String, pal: Palette) -> some View {
        let active = target != nil && target == tab
        return Button {
            if let target { tab = target }
        } label: {
            VStack(spacing: 4) {
                TabGlyph(kind: glyph)
                    .stroke(active ? pal.brass : pal.ink6,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 24, height: 24)
                    .shotNode("tab." + node)
                Text(lexicon.t(title))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(active ? pal.ink : pal.ink6)
                    .lineLimit(1)
                    .fixedSize()
                    .shotNode("tab." + node + ".label", text: lexicon.t(title))
                    .frame(height: 12)
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Не `.disabled`: система гасит недоступную кнопку, а у веба все
        // четыре одного серого.
        .allowsHitTesting(target != nil)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Знаки вкладок — буквально из разметки `.tabbar` веба (`viewBox 0 0 24 24`),
/// а не из библиотеки знаков: там похожие `sun`, `pin`, `sliders`, но
/// другие по рисунку.
struct TabGlyph: Shape {
    enum Kind { case light, map, shoots, settings }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let line = { (a: CGPoint, b: CGPoint) in p.move(to: a); p.addLine(to: b) }
        let pt = { (x: CGFloat, y: CGFloat) in CGPoint(x: x, y: y) }
        switch kind {
        case .light:
            // <circle r=4.5/> и восемь лучей.
            p.addEllipse(in: CGRect(x: 7.5, y: 7.5, width: 9, height: 9))
            line(pt(12, 2), pt(12, 4.5)); line(pt(12, 19.5), pt(12, 22))
            line(pt(4.2, 4.2), pt(6, 6)); line(pt(18, 18), pt(19.8, 19.8))
            line(pt(2, 12), pt(4.5, 12)); line(pt(19.5, 12), pt(22, 12))
            line(pt(4.2, 19.8), pt(6, 18)); line(pt(18, 6), pt(19.8, 4.2))
        case .map:
            // M21 10c0 6-9 12-9 12s-9-6-9-12a9 9 0 0 1 18 0z + <circle cx=12 cy=10 r=3/>
            p.move(to: pt(21, 10))
            p.addCurve(to: pt(12, 22), control1: pt(21, 16), control2: pt(12, 22))
            p.addCurve(to: pt(3, 10), control1: pt(12, 22), control2: pt(3, 16))
            p.addArc(center: pt(12, 10), radius: 9, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            p.closeSubpath()
            p.addEllipse(in: CGRect(x: 9, y: 7, width: 6, height: 6))
        case .shoots:
            // <rect x=3 y=4.5 w=18 h=17 rx=2.5/> M3 9.5h18 M8 2.5v4 M16 2.5v4 M8 14h3 M8 17.5h6
            p.addRoundedRect(in: CGRect(x: 3, y: 4.5, width: 18, height: 17), cornerSize: CGSize(width: 2.5, height: 2.5))
            line(pt(3, 9.5), pt(21, 9.5))
            line(pt(8, 2.5), pt(8, 6.5)); line(pt(16, 2.5), pt(16, 6.5))
            line(pt(8, 14), pt(11, 14)); line(pt(8, 17.5), pt(14, 17.5))
        case .settings:
            // M4 7h9 M17 7h3 M4 17h3 M11 17h9 + <circle 15,7 r2/> <circle 9,17 r2/>
            line(pt(4, 7), pt(13, 7)); line(pt(17, 7), pt(20, 7))
            line(pt(4, 17), pt(7, 17)); line(pt(11, 17), pt(20, 17))
            p.addEllipse(in: CGRect(x: 13, y: 5, width: 4, height: 4))
            p.addEllipse(in: CGRect(x: 7, y: 15, width: 4, height: 4))
        }
        return p.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
