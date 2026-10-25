import SwiftUI
import LightPlanDomain
#if canImport(LightPlanUI) && !LP_WIDGET_EXTENSION
import LightPlanUI
#endif

// 30б.2в-1 — общие кирпичи новых видов (живой день: средний, малый, большой, экран блокировки). Виды рисуются в
// настоящем SwiftUI виджета, чтобы вторая часть достроила выбранный вариант, а не рисовала заново; в ленту и в
// `supportedFamilies` они пока не подключены (слово Алексея: «Сначала картинки»).

/// Вариант оформления отсчётов на выбор Алексею: «простой» (отсчёты текстом) или «кольцо» (два слоя делений по периметру).
enum WidgetLook: Equatable { case plain, ring }

/// Слова новых видов. Русские, как запасные слова ленты: во второй части они переедут в `WidgetFeed.Words` (с языком приложения);
/// «до конца свадьбы» — родительный падеж жанра, для других жанров вторая часть берёт «съёмки», если словарь приложения не знает формы.
enum WidgetSketchWords {
    static let toPoint = "до конца точки"
    static let toShoot = "до конца свадьбы"
    static let shoot = "свадьба"
    static let point = "точка"
    static let route = "Дальше"
    static let points = "точек"
    static let hourShort = "ч"
    static let minShort = "мин"
}

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

    /// Заголовок съёмки на домашнем экране: жанр и имена («Свадьба Анна+Игорь»); имён нет — один жанр.
    func title(names: String?) -> String {
        guard let n = names, !n.isEmpty else { return shoot.title }
        return "\(shoot.title) \(n)"
    }

    private static func fraction(_ now: Date, _ a: Date, _ b: Date) -> Double {
        let total = b.timeIntervalSince(a)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(a) / total))
    }

    // MARK: Слова об остатке

    /// «62 мин» до ста минут, дальше «2 ч 05 мин» (минуты вверх, чтобы 0 не показывался, пока идёт точка).
    static func short(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded(.up))
        if m < 100 { return "\(m) \(WidgetSketchWords.minShort)" }
        return String(format: "%d %@ %02d %@", m / 60, WidgetSketchWords.hourShort, m % 60, WidgetSketchWords.minShort)
    }

    /// «11 ч 38 мин», в последний час — «54 мин».
    static func long(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded(.up))
        if m < 60 { return "\(m) \(WidgetSketchWords.minShort)" }
        if m % 60 == 0 { return "\(m / 60) \(WidgetSketchWords.hourShort)" }
        return String(format: "%d %@ %02d %@", m / 60, WidgetSketchWords.hourShort, m % 60, WidgetSketchWords.minShort)
    }

    /// Внешний слой кольца: целые часы вниз («12 ч, 11 ч, 10 ч…», слово Алексея 25.10), в последний час — минуты.
    static func hours(_ s: TimeInterval) -> String {
        if s < 3600 { return "\(Int((s / 60).rounded(.up))) \(WidgetSketchWords.minShort)" }
        return "\(Int(s / 3600)) \(WidgetSketchWords.hourShort)"
    }
}

// MARK: - Знак точки

/// Знак точки из библиотеки приложения (`Icon(point:)`, `ICONS.forPoint`). Расширение виджета `LightPlanUI` не подключает,
/// поэтому там стоит кружок-заглушка: во второй части нужные пути знаков переезжают в расширение (генератор, см. DECISIONS).
struct WidgetSign: View {
    let title: String
    var place: String = ""
    var studio = false
    var size: CGFloat = 16

    var body: some View {
        #if canImport(LightPlanUI) && !LP_WIDGET_EXTENSION
        Icon(point: title, place: place, studio: studio, size: size, line: 1.7)
        #else
        Circle().strokeBorder(lineWidth: 1.4).frame(width: size * 0.5, height: size * 0.5).frame(width: size, height: size)
        #endif
    }
}

/// Знак жанра съёмки («Свадьба» → кольца) из той же библиотеки.
struct WidgetGenreSign: View {
    let code: String
    var size: CGFloat = 16
    var body: some View {
        #if canImport(LightPlanUI) && !LP_WIDGET_EXTENSION
        Icon(genre: code, size: size, line: 1.7)
        #else
        Circle().strokeBorder(lineWidth: 1.4).frame(width: size * 0.5, height: size * 0.5).frame(width: size, height: size)
        #endif
    }
}

// MARK: - Двоеточие отсчёта

/// «4:10» часы и минуты остатка одной строкой. Двоеточие «как у часов iOS» (слово Алексея 25.10: нижняя точка заметно над строкой,
/// середина двоеточия — середина цифр) даёт сам шрифт: SF в строке «цифра:цифра» ставит двоеточие по середине цифр. Это ломается,
/// когда двоеточие — отдельный вид или кусок другого стиля (так стояло в студийном таймере карточки: +2,67 pt). Поэтому часы, минуты и
/// двоеточие здесь — один `Text`, без своих `baselineOffset` и стилей на двоеточии. Мерено по пикселям: `WidgetSketchTests`.
/// Цифры статичные: лента виджета меняет запись раз в минуту; системный `Text(timerInterval:)` двоеточие ставит так же (мерено).
struct ColonCount: View {
    let seconds: TimeInterval
    var size: CGFloat = 20

    var body: some View {
        let m = Int((seconds / 60).rounded(.up))
        Text(String(format: "%d:%02d", m / 60, m % 60))
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

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            let walker = PerimeterWalker(rect: rect, radius: max(corner - inset, 3))
            let n = max(Int((walker.length / spacing).rounded()), 12)
            for i in 0..<n {
                let t = Double(i) / Double(n)
                let major = majors.contains { abs($0 - t) < 0.5 / Double(n) }
                let (p, inward) = walker.sample(CGFloat(t) * walker.length)
                let l = major ? length + 3 : length
                var path = Path()
                path.move(to: p)
                path.addLine(to: CGPoint(x: p.x + inward.dx * l, y: p.y + inward.dy * l))
                ctx.stroke(path, with: .color(t < progress ? on : off), style: StrokeStyle(lineWidth: major ? width + 0.6 : width, lineCap: .round))
            }
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
            WidgetSign(title: stop.name, place: stop.place, size: signSize)
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
