import SwiftUI

/// 30и.6 (эскиз `sketches_2026-11-14`, «контур города», вариант 2): на листе «Откуда вы работаете» над полем города стоит линия крыш
/// города одной непрерывной линией. По умолчанию — общий силуэт, для Москвы, Петербурга, Новосибирска и Томска — своя линия. Когда город
/// выбран из подсказки, линия рисуется заново за 1,2 с (без движения — сразу). Цвет — знак приложения (`Palette.brass`).
/// Всё нарисовано самим: пути в коде, чужих картинок нет.
enum CityOutline: CaseIterable, Equatable {
    case generic, moscow, petersburg, novosibirsk, tomsk

    /// Рисуется за столько секунд; при «Уменьшении движения» — 0 (линия сразу целиком).
    static let drawDuration = 1.2
    /// Рамка путей: `viewBox 0 0 320 70`, линия идёт слева направо от x = 4 до x = 316 по крышам.
    static let viewBox = CGSize(width: 320, height: 70)

    /// Какая линия у города с таким именем: по словам имени (русское, латинское, «Санкт-Петербург»); остальные — общая.
    static func of(city name: String) -> CityOutline {
        let words = Set(name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
            .split(whereSeparator: { !$0.isLetter }).map(String.init))
        func has(_ keys: [String]) -> Bool { keys.contains { words.contains($0) } }
        if has(["москва", "moscow", "moskva", "mosca", "moscu", "moskau"]) { return .moscow }
        if has(["петербург", "peterburg", "petersburg", "pietroburgo", "petersburgo", "питер", "санкт-петербург"]) { return .petersburg }
        if has(["новосибирск", "novosibirsk"]) { return .novosibirsk }
        if has(["томск", "tomsk"]) { return .tomsk }
        return .generic
    }

    /// Путь в записи SVG (`M H V L Q`, абсолютные координаты).
    var svg: String {
        switch self {
        case .generic:
            "M4 62 H30 V44 H44 V30 H52 V22 L56 12 L60 22 V30 H68 V50 H84 V36 H98 V24 Q112 6 126 24 V50 H140 V28 H152 V16 H164 V28 H176 V48 H192 V38 H204 V20 L212 10 L220 20 V38 H232 V52 H250 V34 H262 V44 H278 V56 H300 V62 H316"
        case .moscow:
            // Высотка со шпилем, зубцы кремлёвской стены, Спасская башня, купола Василия Блаженного.
            "M4 62 H22 V52 H34 V46 H44 V52 H56 V40 H64 V32 H70 V22 L73 8 L76 22 V32 H82 V40 H90 V52 H104 V44 H112 V36 H120 V44 H128 V36 H136 V44 H144 V50 H156 V30 H162 L170 14 L178 30 H184 V50 H196 V40 Q196 30 204 28 Q208 18 212 8 Q216 18 220 28 Q228 30 228 40 H236 V30 Q236 22 242 20 Q246 12 250 4 Q254 12 258 20 Q264 22 264 30 V44 H276 V36 Q276 28 284 26 Q288 18 292 14 Q296 18 300 26 Q308 28 308 36 V62 H316"
        case .petersburg:
            // Низкая набережная, Адмиралтейство с тонким шпилем, купол Исаакия, игла Петропавловского собора.
            "M4 62 H24 V50 H40 V46 H56 V50 H72 V40 H84 V50 H96 V54 H116 V46 H128 V40 H134 V46 H150 V50 H160 V28 H166 L168 6 L170 28 H176 V50 H190 V44 H206 V40 Q206 24 224 22 Q242 24 242 40 V44 H258 V50 H268 L270 20 L272 50 H284 V48 H292 V54 H316"
        case .novosibirsk:
            // Купол оперного театра, арки Октябрьского моста, башни.
            "M4 62 H24 V48 H36 V40 H48 V48 H60 V30 H72 V38 H84 V52 H96 V46 H110 V40 Q110 14 150 14 Q190 14 190 40 H200 V46 H210 V52 Q232 28 254 52 Q268 36 282 52 H296 V44 H306 V54 H316"
        case .tomsk:
            // Деревянные дома с крышами-щипцами, пожарная каланча, шпиль церкви.
            "M4 62 H16 V50 L26 42 L36 50 V54 H46 V46 L56 38 L66 46 V54 H80 V30 H84 V24 H96 V30 H100 V54 H112 V48 L122 40 L132 48 V52 H146 V36 L150 30 V16 L154 8 L158 16 V30 L162 36 V52 H176 V46 L186 38 L196 46 V54 H212 Q212 38 222 36 Q226 26 230 18 Q234 26 238 36 Q248 38 248 54 H262 V48 L272 40 L282 48 V56 H296 V50 L306 44 L316 52"
        }
    }

    /// Путь в рамке `rect` (рамка `viewBox` вписана по ширине, высота пропорциональна).
    func path(in rect: CGRect) -> Path {
        let k = rect.width / Self.viewBox.width
        let dy = rect.minY + (rect.height - Self.viewBox.height * k) / 2
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + CGFloat(x) * k, y: dy + CGFloat(y) * k) }
        var path = Path()
        var cur = (x: 0.0, y: 0.0)
        var tokens = svg.split(separator: " ").map(String.init)
        var i = 0
        func num() -> Double { defer { i += 1 }; return Double(tokens[i]) ?? 0 }
        while i < tokens.count {
            let t = tokens[i]
            // Команда и число могут стоять слитно: «M4», «H30».
            let cmd = t.first!
            let rest = String(t.dropFirst())
            if rest.isEmpty { i += 1 } else { tokens[i] = rest }
            switch cmd {
            case "M": let x = num(), y = num(); cur = (x, y); path.move(to: pt(x, y))
            case "L": let x = num(), y = num(); cur = (x, y); path.addLine(to: pt(x, y))
            case "H": let x = num(); cur.x = x; path.addLine(to: pt(cur.x, cur.y))
            case "V": let y = num(); cur.y = y; path.addLine(to: pt(cur.x, cur.y))
            case "Q":
                let cx = num(), cy = num(), x = num(), y = num()
                cur = (x, y)
                path.addQuadCurve(to: pt(x, y), control: pt(cx, cy))
            default: break
            }
        }
        return path
    }

    /// Все точки пути в рамке `viewBox` — для проверки границ и непрерывности.
    var points: [CGPoint] {
        var out: [CGPoint] = []
        path(in: CGRect(origin: .zero, size: Self.viewBox)).forEach { el in
            switch el {
            case .move(let p), .line(let p): out.append(p)
            case .quadCurve(let p, let c): out.append(c); out.append(p)
            default: break
            }
        }
        return out
    }
}

/// Форма линии города: `trim` ведёт её слева направо.
private struct CityOutlineShape: Shape {
    let outline: CityOutline
    func path(in rect: CGRect) -> Path { outline.path(in: rect) }
}

/// Линия города на листе «Откуда вы работаете». `drawn` меняется, когда выбран город: линия стирается и рисуется заново за 1,2 с.
struct CityOutlineView: View {
    let outline: CityOutline
    /// Счётчик выборов города: каждый выбор — новая отрисовка.
    let drawn: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

    var body: some View {
        let pal = Palette(colorScheme)
        CityOutlineShape(outline: outline)
            .trim(from: 0, to: progress)
            .stroke(pal.brass, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .aspectRatio(CityOutline.viewBox.width / CityOutline.viewBox.height, contentMode: .fit)
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            .shotNode("city.outline", text: "\(outline)")
            .onChange(of: drawn) { _, _ in redraw() }
            .onChange(of: outline) { _, _ in if progress < 1 { progress = 1 } }
    }

    private func redraw() {
        progress = 0
        guard !reduceMotion else { progress = 1; return }
        withAnimation(.easeInOut(duration: CityOutline.drawDuration)) { progress = 1 }
    }
}
