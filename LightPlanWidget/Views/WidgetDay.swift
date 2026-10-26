import SwiftUI
import LightPlanDomain

// 30б.2в — общие кирпичи живого дня (малый и средний с кольцом, большой, экран блокировки). Виды рисуются в настоящем SwiftUI
// виджета: те же файлы собирает и набор UI-тестов (ссылка `WidgetViews`), поэтому снимки в тестах — это то, что видит расширение.

/// День съёмки, разобранный для видов: точки по времени, текущая точка и до какого часа она идёт.
/// Текущая — последняя точка, начавшаяся не позже «сейчас»; кончается она студийным часом (пока он идёт), иначе началом
/// следующей точки, иначе концом съёмки.
struct DayPlan {
    let frame: WidgetFrame
    let shoot: WidgetFeed.Shoot
    let zone: TimeZone
    let stops: [WidgetFeed.Stop]
    let currentIndex: Int?
    let pointEnd: Date?

    init?(_ frame: WidgetFrame) {
        guard let p = frame.primary else { return nil }
        self.frame = frame
        shoot = p.shoot
        zone = p.zone
        stops = p.shoot.stops.sorted { $0.at < $1.at }
        let cur = stops.lastIndex { $0.date <= frame.now }
        currentIndex = cur
        if cur == nil { pointEnd = nil }
        else if let c = p.countdown, c.kind == .studio { pointEnd = c.to }
        else if let i = cur, i + 1 < stops.count { pointEnd = stops[i + 1].date }
        else { pointEnd = p.shoot.endDate }
    }

    var current: WidgetFeed.Stop? { currentIndex.map { stops[$0] } }
    var upcomingStops: [WidgetFeed.Stop] { stops.filter { $0.date > frame.now } }
    var pointStart: Date? { current?.date }

    var shootLeft: TimeInterval { max(0, shoot.endDate.timeIntervalSince(frame.now)) }
    var pointLeft: TimeInterval? { pointEnd.map { max(0, $0.timeIntervalSince(frame.now)) } }

    var shootProgress: Double { Self.fraction(frame.now, shoot.startDate, shoot.endDate) }
    var pointProgress: Double? {
        guard let a = pointStart, let b = pointEnd else { return nil }
        return Self.fraction(frame.now, a, b)
    }

    /// Доли шкалы кольца, где стоят «часовые» деления внешнего слоя: каждый целый час съёмки от её начала.
    var shootHourMarks: [Double] {
        let total = shoot.endDate.timeIntervalSince(shoot.startDate)
        guard total > 0 else { return [] }
        return stride(from: 3600.0, to: total, by: 3600).map { $0 / total }
    }

    /// Доли внутреннего слоя: каждые 15 минут точки.
    var pointQuarterMarks: [Double] {
        guard let a = pointStart, let b = pointEnd, b > a else { return [] }
        let total = b.timeIntervalSince(a)
        return stride(from: 900.0, to: total, by: 900).map { $0 / total }
    }

    func range(_ from: Date, _ to: Date) -> String { "\(frame.clock(from, in: zone))–\(frame.clock(to, in: zone))" }
    var shootRange: String { range(shoot.startDate, shoot.endDate) }

    /// Заголовок съёмки на домашнем экране: жанр и имена («Свадьба Анна+Игорь»); имён нет — один жанр. Имена берут только виды
    /// «Домой» (малый, средний, большой); виды экрана блокировки это свойство не читают.
    var title: String {
        guard let n = shoot.names, !n.isEmpty else { return shoot.title }
        return "\(shoot.title) \(n)"
    }

    private static func fraction(_ now: Date, _ a: Date, _ b: Date) -> Double {
        let total = b.timeIntervalSince(a)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(a) / total))
    }

    // MARK: Слова об остатке

    var words: WidgetFeed.Words { frame.words }
    private var text: RemainText { RemainText(words: words) }
    private var isWedding: Bool { shoot.genre == "wedding" }
    /// «до конца свадьбы» — у свадьбы, у остальных жанров «до конца съёмки» (родительных падежей жанров в словаре нет).
    var untilShoot: String { words[isWedding ? .untilWedding : .untilShoot] }
    /// «свадьба» / «съёмка».
    var shootNoun: String { words[isWedding ? .wedding : .shoot] }

    func short(_ s: TimeInterval) -> String { text.short(s) }
    func long(_ s: TimeInterval) -> String { text.long(s) }
    func hours(_ s: TimeInterval) -> String { text.hours(s) }
}

/// Остаток времени словами на языке приложения (единицы «ч» и «мин» — из слов файла).
struct RemainText {
    let words: WidgetFeed.Words
    private var h: String { words[.hourShort] }
    private var m: String { words[.minShort] }

    /// «62 мин» до ста минут, дальше «2 ч 05 мин» (минуты вверх, чтобы 0 не показывался, пока идёт точка).
    func short(_ s: TimeInterval) -> String {
        let n = Int((s / 60).rounded(.up))
        if n < 100 { return "\(n) \(m)" }
        return String(format: "%d %@ %02d %@", n / 60, h, n % 60, m)
    }

    /// «11 ч 38 мин», в последний час — «54 мин».
    func long(_ s: TimeInterval) -> String {
        let n = Int((s / 60).rounded(.up))
        if n < 60 { return "\(n) \(m)" }
        if n % 60 == 0 { return "\(n / 60) \(h)" }
        return String(format: "%d %@ %02d %@", n / 60, h, n % 60, m)
    }

    /// Внешний слой кольца: целые часы вниз («12 ч, 11 ч, 10 ч…», слово Алексея 25.10), в последний час — минуты.
    func hours(_ s: TimeInterval) -> String {
        if s < 3600 { return "\(Int((s / 60).rounded(.up))) \(m)" }
        return "\(Int(s / 3600)) \(h)"
    }
}

// MARK: - Двоеточие отсчёта

/// «4:10» часы и минуты остатка одной строкой. Двоеточие «как у часов iOS» (слово Алексея 25.10: нижняя точка заметно над строкой,
/// середина двоеточия — середина цифр) даёт сам шрифт: SF в строке «цифра:цифра» ставит двоеточие по середине цифр. Это ломается,
/// когда двоеточие — отдельный вид или кусок другого стиля (так стояло в студийном таймере карточки: +2,67 pt). Поэтому часы, минуты и
/// двоеточие здесь — один `Text`, без своих `baselineOffset` и стилей на двоеточии. Мерено по пикселям: `WidgetSketchTests`.
/// Цифры статичные: лента виджета меняет запись раз в минуту; системный `Text(timerInterval:)` двоеточие ставит так же (мерено).
struct ColonCount: View {
    let text: String
    var size: CGFloat = 20

    init(seconds: TimeInterval, size: CGFloat = 20) { self.init(text: Self.text(seconds), size: size) }
    /// Готовая строка: вид, у которого текст сверяется тестом (`LockCircularView.label`), рисует именно её.
    init(text: String, size: CGFloat = 20) { self.text = text; self.size = size }

    static func text(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded(.up))
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
    }
}

// MARK: - Деления по периметру («Часы» Apple)

/// Обход скруглённого прямоугольника по часовой стрелке от середины верхней стороны: точка и направление внутрь на пройденном пути.
struct PerimeterWalker {
    private enum Seg {
        case line(from: CGPoint, dir: CGVector, len: CGFloat)
        case arc(center: CGPoint, r: CGFloat, start: CGFloat)
        var length: CGFloat {
            switch self {
            case .line(_, _, let l): return l
            case .arc(_, let r, _): return r * .pi / 2
            }
        }
    }

    private let segs: [Seg]
    let length: CGFloat

    init(rect: CGRect, radius: CGFloat) {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let top = (rect.width - 2 * r) / 2, side = rect.height - 2 * r, bottom = rect.width - 2 * r
        var s: [Seg] = [
            .line(from: CGPoint(x: rect.midX, y: rect.minY), dir: CGVector(dx: 1, dy: 0), len: top),
            .arc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), r: r, start: -.pi / 2),
            .line(from: CGPoint(x: rect.maxX, y: rect.minY + r), dir: CGVector(dx: 0, dy: 1), len: side),
            .arc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), r: r, start: 0),
            .line(from: CGPoint(x: rect.maxX - r, y: rect.maxY), dir: CGVector(dx: -1, dy: 0), len: bottom),
            .arc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), r: r, start: .pi / 2),
            .line(from: CGPoint(x: rect.minX, y: rect.maxY - r), dir: CGVector(dx: 0, dy: -1), len: side),
            .arc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), r: r, start: .pi),
            .line(from: CGPoint(x: rect.minX + r, y: rect.minY), dir: CGVector(dx: 1, dy: 0), len: top),
        ]
        s.removeAll { $0.length <= 0 }
        segs = s
        length = s.reduce(0) { $0 + $1.length }
    }

    /// Точка на пути `d` (0…length) и единичный вектор внутрь фигуры.
    func sample(_ d: CGFloat) -> (point: CGPoint, inward: CGVector) {
        var left = d
        for seg in segs {
            if left <= seg.length {
                switch seg {
                case .line(let from, let dir, _):
                    // Внутрь — поворот направления обхода на 90° по часовой стрелке (экранные оси: y вниз).
                    return (CGPoint(x: from.x + dir.dx * left, y: from.y + dir.dy * left), CGVector(dx: -dir.dy, dy: dir.dx))
                case .arc(let c, let r, let a0):
                    let a = a0 + left / r
                    return (CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)), CGVector(dx: -cos(a), dy: -sin(a)))
                }
            }
            left -= seg.length
        }
        return (CGPoint(x: 0, y: 0), CGVector(dx: 0, dy: 1))
    }
}

/// Деления одного слоя: путь всех делений с нужной яркостью (`on` — пройденные, иначе остаток) и длиной (`major` — «круглые»).
/// Это `Shape`, а не `Canvas`: путь виджет архивирует как есть, ему не нужно исполнять замыкание рисования.
struct TicksShape: Shape {
    let inset: CGFloat
    let length: CGFloat
    let corner: CGFloat
    let spacing: CGFloat
    let progress: Double
    let majors: [Double]
    let on: Bool
    let major: Bool

    func path(in bounds: CGRect) -> Path {
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let walker = PerimeterWalker(rect: rect, radius: max(corner - inset, 3))
        let n = max(Int((walker.length / spacing).rounded()), 12)
        var path = Path()
        for i in 0..<n {
            let t = Double(i) / Double(n)
            guard (t < progress) == on, majors.contains(where: { abs($0 - t) < 0.5 / Double(n) }) == major else { continue }
            let (p, inward) = walker.sample(CGFloat(t) * walker.length)
            let l = major ? length + 3 : length
            path.move(to: p)
            path.addLine(to: CGPoint(x: p.x + inward.dx * l, y: p.y + inward.dy * l))
        }
        return path
    }
}

/// Один слой делений по периметру плашки (как у виджета «Часы» Apple): пройденная часть горит, остаток тусклый, на «круглых»
/// отметках деление длиннее. Рисуется поверх всей плашки, в её полях — полезного места не занимает.
struct PerimeterTicks: View {
    /// Расстояние от края плашки до внешнего конца деления.
    let inset: CGFloat
    let length: CGFloat
    /// Радиус скругления плашки (виджет iPhone ≈ 22 pt): деления идут по контуру с тем же центром скругления.
    var corner: CGFloat = 22
    let progress: Double
    var majors: [Double] = []
    let on: Color
    let off: Color
    var spacing: CGFloat = 7.5
    var width: CGFloat = 1.6

    private func layer(on isOn: Bool, major: Bool) -> some View {
        TicksShape(inset: inset, length: length, corner: corner, spacing: spacing, progress: progress, majors: majors, on: isOn, major: major)
            .stroke(isOn ? on : off, style: StrokeStyle(lineWidth: major ? width + 0.6 : width, lineCap: .round))
    }

    var body: some View {
        ZStack {
            layer(on: false, major: false)
            layer(on: false, major: true)
            layer(on: true, major: false)
            layer(on: true, major: true)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Строка маршрута

/// Строка точки маршрута: знак, время, название. Текущая — янтарная, с часом конца.
struct StopLine: View {
    let plan: DayPlan
    let stop: WidgetFeed.Stop
    var isCurrent = false
    var past = false
    var signSize: CGFloat = 15
    var withPlace = false
    let st: WidgetStyle

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            WidgetIcon(name: stop.sign, size: signSize)
                .foregroundStyle(isCurrent ? st.amber : (past ? st.ink.opacity(0.35) : st.ink2))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(plan.frame.clock(stop.date, in: plan.zone))
                        .font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1).fixedSize()
                        .foregroundStyle(isCurrent ? st.amber : (past ? st.ink.opacity(0.4) : st.ink2))
                    Text(stop.name).font(.footnote.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(past ? st.ink.opacity(0.45) : st.ink).lineLimit(1).minimumScaleFactor(0.8)
                }
                if withPlace, !stop.place.isEmpty {
                    Text(stop.place).font(.caption2).foregroundStyle(st.ink2).lineLimit(1)
                }
            }
        }
    }
}

extension DynamicTypeSize {
    /// Сколько строк маршрута помещается при таком размере текста: подбирается по числам теста (`WidgetSketchTests`).
    func rows(normal: Int, large: Int, huge: Int) -> Int {
        if self <= .large { return normal }
        if self <= .xxLarge { return large }
        return huge
    }
}
