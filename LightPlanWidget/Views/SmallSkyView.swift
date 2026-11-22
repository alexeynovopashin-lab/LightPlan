import SwiftUI
import LightPlanDomain
import LightPlanCore

/// Малый виджет «окно неба» (30и.15, вариант Н2 листа `docs/30i13_big_widget.html` § 12; Алексей 16.11 «Н2, в код»). Правила — `SmallSky` (Domain).
///
/// Рисунок на холсте 170 × 170 (плашка Pro Max) и масштабом на другие размеры, как эскиз: сверху небо во всю ширину, два холма-горизонта
/// (левый — восход, правый — закат, на них время и балл), золотая линия горизонта; внизу утопленное окошко календаря с красным указателем.
/// Подложка и цвета Braun. Рисок нет: риски бывают только таймером (у идущей съёмки — `SmallLiveView`).
struct SmallSkyView: View {
    let frame: WidgetFrame
    let alpha: Bool
    @Environment(\.colorScheme) private var scheme

    static let canvas: CGFloat = 170

    var body: some View {
        GeometryReader { g in
            let k = min(g.size.width, g.size.height) / Self.canvas
            SmallSkyCanvas(frame: frame, alpha: alpha, pal: BraunPalette(dark: scheme == .dark))
                .frame(width: Self.canvas, height: Self.canvas)
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Небо, холмы, окошко — в точках холста 170 × 170.
struct SmallSkyCanvas: View {
    let frame: WidgetFrame
    let alpha: Bool
    let pal: BraunPalette

    // Геометрия холста (числа эскиза Н2).
    static let horizon: CGFloat = 90
    static let hill: CGFloat = 42.5
    static let sunOrbit: CGFloat = 68, sunR: CGFloat = 9
    static let moonOrbit: CGFloat = 50, moonR: CGFloat = 24
    static let window = CGRect(x: 14, y: 114, width: 142, height: 42)

    private var look: SmallSky.Look { SmallSky.look(frame) }
    private var gold: Color { SkyInk.c(0xF4B400) }

    var body: some View {
        let l = look
        ZStack(alignment: .topLeading) {
            Rectangle().fill(pal.bg)
            sky(l)
            hillLabels
            window
            corner(l)
        }
        .frame(width: SmallSkyView.canvas, height: SmallSkyView.canvas, alignment: .topLeading)
    }

    // MARK: Небо

    private static func skyColors(_ s: SmallSky.Sky) -> (UInt32, UInt32) { SkyInk.sky(s) }

    /// Звёзды: доля ширины, доля высоты неба, крупная ли (золотая звезда) — рисунок постоянный.
    static let stars: [(Double, Double, Bool)] = [(0.06, 0.46, true), (0.2, 0.66, false), (0.29, 0.2, false), (0.36, 0.47, true), (0.47, 0.08, false),
                                                 (0.55, 0.36, false), (0.62, 0.33, true), (0.72, 0.54, false), (0.84, 0.4, false), (0.93, 0.52, true),
                                                 (0.97, 0.3, false), (0.4, 0.72, false), (0.58, 0.12, false), (0.5, 0.6, true)]

    private func sky(_ look: SmallSky.Look) -> some View {
        let W = SmallSkyView.canvas, H = Self.horizon
        let c = Self.skyColors(look.sky)
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [SkyInk.c(c.0), SkyInk.c(c.1)], startPoint: .top, endPoint: .bottom)
            if look.sky != .day {
                ForEach(Self.stars.indices, id: \.self) { i in
                    let s = Self.stars[i]
                    if look.sky == .night || i % 2 == 0 {
                        let o = look.sky == .night ? 1.0 : 0.5
                        let p = CGPoint(x: s.0 * W, y: s.1 * H)
                        if s.2 { StarShape().fill(gold).frame(width: 6.4, height: 6.4).position(p).opacity(o) }
                        else { Circle().fill(gold).frame(width: 2, height: 2).position(p).opacity(o * 0.9) }
                    }
                }
            }
            if let path = look.sun { sun(at: Self.sunPoint(path)) }
            if look.sky == .night { moon(at: Self.moonPoint(look.moonCycle)) }
            // Холмы — та же подложка, что плашка, с тенью на небо.
            ZStack(alignment: .topLeading) {
                Circle().fill(pal.bg).frame(width: 2 * Self.hill, height: 2 * Self.hill).position(x: Self.hill, y: H)
                Circle().fill(pal.bg).frame(width: 2 * Self.hill, height: 2 * Self.hill).position(x: W - Self.hill, y: H)
            }
            .shadow(color: .black.opacity(0.5), radius: 1.7, x: 0, y: -1)
            HorizonLine(hill: Self.hill, y: H).stroke(gold, lineWidth: 1.6)
        }
        .frame(width: W, height: H)
        .clipped()
    }

    /// Центр Солнца на пути `p`: 0 — на кромке левого холма, 1 — правого (по дуге радиуса 68 вокруг середины горизонта).
    static func sunPoint(_ p: Double) -> CGPoint {
        let cx = Double(SmallSkyView.canvas) / 2, cy = Double(horizon), R = Double(sunOrbit)
        // Кромка холма: точка дуги на расстоянии `hill` от центра холма — cos θ₀ = R / (2 · hill).
        let t0 = acos(R / (2 * Double(hill)))
        let th = t0 + p * (Double.pi - 2 * t0)
        return CGPoint(x: cx - R * cos(th), y: cy - R * sin(th))
    }

    /// Центр Луны по возрасту, как на часах: новолуние — за левым холмом, полнолуние — в середине, к концу цикла — за правым.
    static func moonPoint(_ cycle: Double) -> CGPoint {
        let cx = Double(SmallSkyView.canvas) / 2, cy = Double(horizon), R = Double(moonOrbit)
        let th = Double.pi * min(1, max(0, cycle))
        return CGPoint(x: cx - R * cos(th), y: cy - R * sin(th))
    }

    private func sun(at p: CGPoint) -> some View {
        ZStack {
            Circle().fill(SkyInk.c(0xFFD75A)).opacity(0.3).frame(width: Self.sunR * 4.6, height: Self.sunR * 4.6)
            Circle().fill(gold).frame(width: 2 * Self.sunR, height: 2 * Self.sunR)
            Circle().stroke(SkyInk.c(0xD99A00), lineWidth: 0.8).frame(width: 2 * Self.sunR, height: 2 * Self.sunR)
        }
        .position(p)
    }

    /// Луна целиком, как диск на механике: фазу показывает холм, точный процент — подпись в углу.
    private func moon(at p: CGPoint) -> some View {
        let r = Self.moonR
        return ZStack {
            Circle().fill(RadialGradient(colors: [SkyInk.c(0xFBDD77), SkyInk.c(0xE0A21A)], center: UnitPoint(x: 0.38, y: 0.34), startRadius: 0, endRadius: 1.6 * r))
            ForEach(Self.craters.indices, id: \.self) { i in
                let c = Self.craters[i]
                Circle().fill(SkyInk.c(0xC48A12)).opacity(0.3).frame(width: 2 * c.2 * r, height: 2 * c.2 * r).offset(x: c.0 * r, y: c.1 * r)
            }
        }
        .frame(width: 2 * r, height: 2 * r)
        .position(p)
    }
    static let craters: [(CGFloat, CGFloat, CGFloat)] = [(-0.3, -0.18, 0.2), (0.28, 0.32, 0.15), (0.22, -0.42, 0.09)]

    // MARK: Холмы: восход и закат

    private var hillLabels: some View {
        let h = SmallSky.hills(frame)
        let l = Self.hill, r = SmallSkyView.canvas - Self.hill
        return ZStack(alignment: .topLeading) {
            WidgetIcon(name: BraunSign.light(.sunrise), size: 12, line: 1.5).foregroundStyle(pal.muted).position(x: l, y: 58)
            WidgetIcon(name: BraunSign.light(.sunset), size: 12, line: 1.5).foregroundStyle(pal.muted).position(x: r, y: 58)
            text(h.rise.time, 15.5, .semibold, color: pal.text).position(x: l, y: 81 - 0.36 * 15.5)
            text(h.set.time, 15.5, .semibold, color: pal.text).position(x: r, y: 81 - 0.36 * 15.5)
            if let s = h.rise.score { score(s).position(x: l, y: 105 - 0.36 * 10.5) }
            if let s = h.set.score { score(s).position(x: r, y: 105 - 0.36 * 10.5) }
        }
    }

    /// «62 / 100»: балл полужирным (от 75 — янтарём, как «красивый» в приложении), «/ 100» мельче и тусклее.
    private func score(_ s: Int) -> some View {
        (Text("\(s)").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(s >= 75 ? pal.amber : pal.text)
         + Text(" / 100").font(.system(size: 8.4, weight: .medium)).foregroundStyle(pal.muted))
            .monospacedDigit().lineLimit(1).fixedSize()
    }

    private func text(_ s: String, _ size: CGFloat, _ w: Font.Weight, color: Color) -> some View {
        Text(s).font(.system(size: size, weight: w)).monospacedDigit().foregroundStyle(color).lineLimit(1).fixedSize()
    }

    // MARK: Окошко календаря

    private var window: some View {
        let R = Self.window
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(pal.dial)
                LinearGradient(colors: [.black.opacity(0.3), .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 7)
                windowContent
            }
            .frame(width: R.width, height: R.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(pal.dialEdge, lineWidth: 0.6))
            .offset(x: R.minX, y: R.minY)
            pointer
        }
    }

    /// Координаты внутри окошка (от его левого верхнего угла).
    @ViewBuilder private var windowContent: some View {
        let R = Self.window
        switch SmallSky.window(frame) {
        case .shoot(let c):
            ZStack(alignment: .topLeading) {
                text("\(c.before)", 15, .regular, color: pal.text).opacity(0.3).position(x: 24, y: 120.5 - R.minY - 0.36 * 15)
                text("\(c.day)", 19, .bold, color: pal.text).position(x: 24, y: 142 - R.minY - 0.36 * 19)
                text("\(c.after)", 15, .regular, color: pal.text).opacity(0.3).position(x: 24, y: 163 - R.minY - 0.36 * 15)
                divider(x: 44)
                Text(c.line).font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(pal.text).lineLimit(1)
                    .minimumScaleFactor(0.7).frame(width: R.width - 56, alignment: .leading).position(x: 52 + (R.width - 56) / 2, y: 133 - R.minY - 0.36 * 15)
                HStack(spacing: 3) {
                    WidgetIcon(name: c.genre, size: 11.5, line: 1.5, genre: true).foregroundStyle(pal.muted)
                    Text(c.names).font(.system(size: 11, weight: .medium)).foregroundStyle(pal.muted).lineLimit(1)
                }
                .frame(width: R.width - 56, alignment: .leading).position(x: 52 + (R.width - 56) / 2, y: 148 - R.minY - 0.36 * 11)
            }
        case .sunsets(let cells, let best):
            // 31.7 (Алексей 19.11, вопрос 1 «А»): у дня пара «рассвет · закат». Пара 11 pt не влезала в колонку 38 pt рядом с клеткой знака (замер
            // «48 · 72» = 38,8 pt), поэтому клетки знака больше нет: три колонки по 47 pt (`Pairs`). До 31.7 — знак заката 21 pt и закаты 16 pt.
            // Золотой знак (Алексей 16.11 «солнышко крупнее и цветным») встал на место красного флажка: над лучшим числом, ↑ или ↓ (оркестратор 19.11).
            ZStack(alignment: .topLeading) {
                ForEach(Pairs.dividers, id: \.self) { divider(x: $0) }
                ForEach(cells.indices, id: \.self) { i in
                    let cx = Pairs.centre(i), c = cells[i], p = Pairs.layout(c)
                    let mark = Pairs.mark(c, best: best?.day == i ? best?.event : nil)
                    text(c.day, 9, .medium, color: pal.muted).position(x: cx + mark.labelX, y: Pairs.labelY)
                    if let e = best?.day == i ? best?.event : nil, let sx = mark.signX {
                        WidgetIcon(name: BraunSign.light(e == .dawn ? .sunrise : .sunset), size: Pairs.sign, line: 1.7).foregroundStyle(gold)
                            .frame(width: Pairs.sign, height: Pairs.sign).position(x: cx + sx, y: Pairs.signY)
                    }
                    ForEach(p.items.indices, id: \.self) { k in
                        let it = p.items[k]
                        text(it.text, p.size, it.dot ? .regular : .semibold, color: it.dot ? pal.muted : it.color(pal))
                            .position(x: cx + it.x, y: 148 - R.minY - 0.36 * p.size)
                    }
                }
            }
        }
    }

    /// Пары окошка: где стоят балл рассвета, точка и балл заката в колонке дня. Считает по замеру шрифта (`BraunText`), чтобы флажок встал
    /// ровно над лучшим числом, а «100 · 100» — не вышел за черту (тогда точка без пробелов).
    enum Pairs {
        static let size = 11.0
        static let column: CGFloat = 142.0 / 3   // ширина окошка `SmallSkyCanvas.window` на три дня
        static var dividers: [CGFloat] { [column, 2 * column] }
        static func centre(_ i: Int) -> CGFloat { column * (CGFloat(i) + 0.5) }

        struct Item {
            var text: String
            var x: CGFloat
            var dot: Bool
            var score: Int?
            func color(_ pal: BraunPalette) -> Color { score == nil ? pal.dim : ((score ?? 0) >= 75 ? pal.amber : pal.text) }
        }

        struct Layout {
            var items: [Item]
            var width: CGFloat
            /// Кегль пары: 11, а в колонке, где и с точкой без пробелов не влезает («100 · 100» = 49,2 pt), — меньше, но не ниже `minSize`.
            var size: CGFloat = 11
            /// Центр числа события от центра колонки — над ним флажок.
            var dawnX: CGFloat
            var sunsetX: CGFloat
        }

        /// Нижний предел кегля пары (оркестратор 19.11: «нижний предел ~0,9 — 11 → 10 pt»).
        static let minSize = 10.0

        static func layout(_ c: SmallSky.SunsetCell) -> Layout {
            let a = c.dawn.map(String.init) ?? "—", b = c.score.map(String.init) ?? "—"
            // 11 pt с пробелами у точки → 11 pt без них (поле 2 pt до черты) → 10,5 → 10 pt без них (поле ≥ 0,75 pt; «100 · 100» в 10 pt = 45,3 pt, поле 0,99): ужимается только эта колонка.
            let tries: [(Double, Bool, CGFloat)] = [(size, true, 4), (size, false, 4), (10.5, false, 1.5), (minSize, false, 1.5)]
            func width(_ k: Double, _ roomy: Bool) -> CGFloat {
                let w = { (t: String) in CGFloat(BraunText.width(t, size: k, semibold: true, mono: true)) }
                return w(a) + w(b) + CGFloat(BraunText.width("·", size: k, semibold: false)) + 2 * gap(roomy)
            }
            let pick = tries.first { width($0.0, $0.1) <= column - $0.2 } ?? tries[tries.count - 1]
            let k = pick.0, roomy = pick.1
            func w(_ t: String) -> CGFloat { CGFloat(BraunText.width(t, size: k, semibold: true, mono: true)) }
            let dot = CGFloat(BraunText.width("·", size: k, semibold: false))
            let g = gap(roomy)
            let total = w(a) + g + dot + g + w(b)
            let left = -total / 2
            let ax = left + w(a) / 2, dx = left + w(a) + g + dot / 2, bx = left + w(a) + g + dot + g + w(b) / 2
            return Layout(items: [Item(text: a, x: ax, dot: false, score: c.dawn), Item(text: "·", x: dx, dot: true, score: nil),
                                  Item(text: b, x: bx, dot: false, score: c.score)],
                          width: total, size: CGFloat(k), dawnX: ax, sunsetX: bx)
        }

        /// Зазор вокруг точки: 3 pt, а если пара так не влезает (балл 100) — 1 pt.
        static func gap(_ roomy: Bool) -> CGFloat { roomy ? 3 : 1 }

        /// Золотой знак лучшего события: 21 pt, как знак заката до 31.7. Предел — ширина колонки, не высота окошка: рисунок знака занимает
        /// 0,79 размера в ширину (x 2,5…21,5 из 24) и 0,52 в высоту; над «100 · 100» (центр числа в 13,4 pt от середины колонки) при 21 pt
        /// до черты остаётся 2 pt, при 24 — 0,7 pt.
        static let sign: CGFloat = 21
        /// Центр рамки знака: середина рисунка (y 4…16,5 из 24) — на 12 pt от верха окошка, над цифрами (их верх ≈ 26 pt).
        static let signY: CGFloat = 12 + (0.5 - 10.25 / 24) * sign
        static let labelY: CGFloat = 129 - 114 - 0.36 * 9   // 114 = верх окошка `SmallSkyCanvas.window`

        /// Половина рисунка знака с половиной линии 1,7 (в pt).
        static let signHalf: CGFloat = (21.5 - 2.5) / 24 / 2 * sign + 0.75

        /// Где в колонке стоят подпись дня и знак (от середины колонки): у лучшего дня знак — над лучшим числом, подпись — над другим.
        /// Оба не подходят к черте ближе 1,5 / 1 pt: рядом с «100» число стоит в 13,8 pt от середины, знак тогда сдвинут к середине на ≤ 0,7 pt.
        static func mark(_ c: SmallSky.SunsetCell, best: SkyEvent?) -> (labelX: CGFloat, signX: CGFloat?) {
            guard let best else { return (0, nil) }
            let p = layout(c)
            let (l, s) = best == .dawn ? (p.sunsetX, p.dawnX) : (p.dawnX, p.sunsetX)
            func clamp(_ x: CGFloat, _ lim: CGFloat) -> CGFloat { min(lim, max(-lim, x)) }
            let lw = CGFloat(BraunText.width(c.day, size: 9, semibold: true)) / 2
            return (clamp(l, column / 2 - 1 - lw), clamp(s, column / 2 - 1.5 - signHalf))
        }
    }

    private func divider(x: CGFloat) -> some View {
        Rectangle().fill(pal.hairline).frame(width: 0.8, height: Self.window.height - 14).position(x: x, y: Self.window.height / 2)
    }

    /// Красный указатель Braun: у даты — слева на краю окошка, у закатов — сверху над лучшим днём.
    @ViewBuilder private var pointer: some View {
        let R = Self.window
        switch SmallSky.window(frame) {
        case .shoot:
            Pointer(down: false).fill(pal.flag).frame(width: 8, height: 12).position(x: R.minX + 5, y: R.minY + 21)
        case .sunsets:
            // 31.7: у дней вместо красного флажка — золотой знак лучшего события внутри окошка (`Pairs.mark`).
            EmptyView()
        }
    }

    // MARK: Угол: Луна процентом и «α»

    /// Подпись Луны в углу неба (значок фазы и «60 %»); ночью растущая Луна стоит слева — подпись уходит вправо. «α» — в другом углу.
    private func corner(_ look: SmallSky.Look) -> some View {
        let right = look.sky == .night && look.moonWaxing
        let label = HStack(spacing: 3) {
            MoonPhaseDot(fraction: look.moonFraction, waxing: look.moonWaxing, shade: SkyInk.c(Self.skyColors(look.sky).0)).frame(width: 8.4, height: 8.4)
            Text(SmallSky.moonPercent(look)).font(.system(size: 9.5, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.9)).fixedSize()
        }
        return ZStack(alignment: .topLeading) {
            label.frame(width: SmallSkyView.canvas - 28, alignment: right ? .trailing : .leading).offset(x: 14, y: 11)
            if alpha { AlphaBadge().frame(width: SmallSkyView.canvas - 20, alignment: right ? .leading : .trailing).offset(x: 10, y: 8) }
        }
    }
}

// MARK: - Фигуры

/// Две верхние полуокружности холмов — золотая линия горизонта.
struct HorizonLine: Shape {
    let hill: CGFloat
    let y: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: hill, y: y), radius: hill, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        p.addArc(center: CGPoint(x: 3 * hill, y: y), radius: hill, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        return p
    }
}

/// Пятиконечная звезда.
struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<10 {
            let a = -Double.pi / 2 + Double(i) * Double.pi / 5, q = i % 2 == 1 ? r * 0.42 : r
            let pt = CGPoint(x: c.x + q * cos(a), y: c.y + q * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Треугольник указателя: `down` — остриём вниз (над окошком), иначе остриём вправо (на левом краю окошка).
struct Pointer: Shape {
    let down: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if down { p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)) }
        else { p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)) }
        p.closeSubpath()
        return p
    }
}

/// Маленький значок фазы: освещённая часть золотая, тень — цвет неба под ним.
struct MoonPhaseDot: View {
    let fraction: Double
    let waxing: Bool
    let shade: Color
    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2
            let d = 2 * r * fraction * (waxing ? -1 : 1)
            ZStack {
                Circle().fill(SkyInk.c(0xFBDD77))
                Circle().fill(shade).offset(x: d).clipShape(Circle())
                Circle().stroke(.white.opacity(0.7), lineWidth: 0.7)
            }
        }
    }
}

/// Цвет из `0xRRGGBB` (sRGB). Своё имя: у `LightPlanUI` есть `Color(hex:)`, а виды расширения собираются и в его тестах.
enum SkyInk {
    static func c(_ v: UInt32) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: 1)
    }

    /// Небо виджетов сверху вниз — одно на малый «окно неба» и купол большого (30и.16, Алексей 16.11: «цвет неба как у малого»). Какое небо —
    /// решает высота Солнца (`SmallSky.look`: выше +6° день, −6…+6° закатное, ниже ночь), тема плашки на него не влияет.
    static func sky(_ s: SmallSky.Sky) -> (UInt32, UInt32) {
        switch s {
        case .day: (0x4F8FD8, 0xBBD9F6)
        case .twilight: (0x2B3664, 0xE58F66)
        case .night: (0x0F1C50, 0x22408C)
        }
    }
}
