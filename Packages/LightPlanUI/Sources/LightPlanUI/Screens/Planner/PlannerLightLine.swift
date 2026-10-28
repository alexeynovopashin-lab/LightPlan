import SwiftUI
import LightPlanCore

/// Строка света дня («Съёмки», день): восход, закат, золотой час, погода. С 28.10 без подложки-капсулы
/// (слово Алексея: «убираем подложку-капсулу, строка просто схлопывается и раздвигается; иконки отцентруем») —
/// веб оставляет капсулу, натив расходится с ним осознанно.
///
/// Показания лежат на странице как есть. Знаки встают чернилами на ось цифр времени (`LightLine.iconShift`),
/// а не рамкой знака, потому что чернила у знаков лежат по-разному: у восхода и заката — низко, у часов золотого
/// часа и облака с каплями — по всей рамке.
enum LightLine {
    /// Кегль и вес цифр строки (веб `.dp-bar`).
    static let digitSize: CGFloat = 13
    static let digitWeight = 600
    /// Сторона знака в строке и промежуток знак — подпись.
    static let iconSize: CGFloat = 17
    static let iconGap: CGFloat = 3
    /// Зазор между знаком погоды и градусами сверх `iconGap` (веб `.dp-wx i { margin-right: 8px }`).
    static let weatherGap: CGFloat = 8
    /// Сторона нажимаемого квадрата шеврона (не меньше 44 pt).
    static let tapSide: CGFloat = 44
    /// Слева показания не ближе, чем на 12 pt от края рамки: так было и в капсуле.
    static let leadingMin: CGFloat = 12

    /// Середина чернил знака на холсте 24 × 24 (по контурам библиотеки; ширина линии середину не двигает).
    @MainActor
    static func inkMidY(_ name: String) -> CGFloat {
        let r = Icon.common(name).parts.map { $0.path.boundingRect }.filter { !$0.isNull }.reduce(CGRect.null) { $0.union($1) }
        return r.isNull ? 12 : r.midY
    }

    /// Насколько середина цифр времени ниже середины строки текста: строка считается от ascent до descent,
    /// а цифры стоят от базовой линии на высоту заглавной.
    static var digitBias: CGFloat {
        let f = webPlatformFont(digitSize, digitWeight)
        return (f.ascender + f.descender) / 2 - f.capHeight / 2
    }

    /// Сдвиг знака по y, при котором середина его чернил стоит на середине цифр: рамка знака центрована в строке
    /// вместе с текстом, чернила в рамке — на `inkMidY − 12` холста.
    @MainActor
    static func iconShift(_ name: String, size: CGFloat = iconSize) -> CGFloat {
        digitBias - (inkMidY(name) - 12) * size / 24
    }

    /// Левый край показаний при ширине рамки `width`: середина показаний (ширины `content`) стоит на оси экрана
    /// `axis` (в координатах рамки); не помещается — прижато влево с полем `leadingMin` (лишнее срежется, как в капсуле).
    static func originX(content: CGFloat, width: CGFloat, axis: CGFloat?) -> CGFloat {
        guard let axis else { return leadingMin }
        return max(leadingMin, min(axis - content / 2, width - content))
    }
}

/// Раскладка: показания по своей ширине, середина — на оси экрана (`axis`), по высоте — на середине рамки.
struct LightLineCentre: Layout {
    /// Ось экрана в координатах рамки; `nil` — панель ещё не измерена, всё слева, как было.
    var axis: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: proposal.width ?? s.width + LightLine.leadingMin, height: proposal.height ?? s.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let v = subviews.first else { return }
        let ideal = v.sizeThatFits(.unspecified)
        let room = bounds.width - LightLine.leadingMin
        // Не помещается — слову «прогноза нет» отдаётся только место, что есть (оно одно сжимается).
        let s = ideal.width > room ? v.sizeThatFits(ProposedViewSize(width: max(0, room), height: ideal.height)) : ideal
        let x = LightLine.originX(content: s.width, width: bounds.width, axis: axis)
        v.place(at: CGPoint(x: bounds.minX + x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(s))
    }
}

/// Показания строки: значки и подписи в ряд, делитель, погода (или слово «прогноза нет»).
struct LightLineRow: View {
    struct Weather: Equatable {
        let icon: String
        let temp: String
    }

    let rise: String
    let set: String
    let setColor: Color
    /// Длина золотого часа («57 мин»); `nil` — золотого часа нет, места под него тоже.
    let golden: String?
    let weather: Weather?
    /// Слово вместо погоды, когда прогноза нет.
    let note: String
    let pal: Palette

    var body: some View {
        HStack(spacing: 8) {
            item("sunrise", rise, pal.ink2, node: "dp.rise")
            item("sunset", set, setColor, node: "dp.set")
            if let golden { item("golden", golden, pal.ink4, weight: 500, node: "dp.gold") }
            Rectangle().fill(pal.hairline).frame(width: 1, height: 12).fixedSize()
            if let weather {
                weatherGroup(weather)
            } else {
                // Прогноза нет — надпись на месте знака и градусов; выдумки нет (28ж).
                Text(note).font(webFont(12)).foregroundStyle(pal.ink4)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .shotNode("dp.wxnone", text: note)
            }
        }
    }

    /// Знак погоды и градусы: между ними 3 + 8 pt (веб `.dp-wx`).
    func weatherGroup(_ weather: Weather) -> some View {
        HStack(spacing: LightLine.iconGap) {
            Icon(weather.icon, size: LightLine.iconSize, line: 1.5).foregroundStyle(pal.ink)
                .offset(y: LightLine.iconShift(weather.icon))
                .padding(.trailing, LightLine.weatherGap)
            Text(weather.temp).font(webFont(LightLine.digitSize, 600)).monospacedDigit().foregroundStyle(pal.ink)
                .shotNode("dp.temp", text: weather.temp)
        }
        .fixedSize()
    }

    /// Знак и подпись показания в ряд, рамка строки 20 pt.
    func item(_ icon: String, _ text: String, _ color: Color, weight: Int = LightLine.digitWeight, node: String) -> some View {
        HStack(spacing: LightLine.iconGap) {
            Icon(icon, size: LightLine.iconSize, line: 1.6).foregroundStyle(pal.brass)
                .offset(y: LightLine.iconShift(icon))
            Text(text).font(webFont(LightLine.digitSize, weight)).monospacedDigit().foregroundStyle(color)
                .shotNode(node, text: text)
        }
        .fixedSize()
        .frame(height: 20)
    }
}

/// Черта сводки с вырезом под шеврон: свёрнутая сводка — шеврон сидит на черте без плашки, и черта не должна идти
/// сквозь него. Вырез растёт с долей пути `t` (0 раскрыта — сплошная, 1 свёрнута — выемка на всю ширину значка).
struct LightLineRule: View {
    let color: Color
    let t: Double
    /// Центр шеврона от правого края черты (от рамки панели: правый край − `FoldGeometry.inset` − половина ручки, плюс вылет черты).
    static var chevronFromRight: CGFloat { FoldGeometry.inset + FoldGeometry.chevronWidth / 2 + FoldGeometry.bleed }
    /// Половина выреза в pt: значок шеврона 16 + по 6 с каждой стороны.
    static let halfGap: CGFloat = 14

    var body: some View {
        Rectangle().fill(color)
            .mask {
                GeometryReader { g in
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: g.size))
                        let c = g.size.width - Self.chevronFromRight, h = Self.halfGap * CGFloat(min(1, max(0, t)))
                        p.addRect(CGRect(x: c - h, y: 0, width: 2 * h, height: g.size.height))
                    }
                    .fill(style: FillStyle(eoFill: true))
                }
            }
    }
}
