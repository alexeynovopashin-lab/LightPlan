import CoreGraphics
import LightPlanCore

/// Светило пальцем по куполу — порт `domeDrag` веба (итерация 19в). Здесь
/// только числа: какая ось у жеста, где на дуге палец и какая это минута.
/// Распознаватель (`DomeDragGesture`) спрашивает их и больше ничего не решает.
enum DomeDrag {

    /// Жест не определился, пока палец не ушёл на 6 pt ни по одной оси
    /// (`THRESH` веба): касание само солнце не двигает.
    static let threshold: CGFloat = 6
    /// Ниже горизонта не наша зона (`vy > cy + 8`): там строки под куполом.
    static let belowHorizon: Double = 8

    enum Axis: Equatable {
        /// Ещё не ясно — ждём движения.
        case pending
        /// Горизонталь: тянем светило.
        case drag
        /// Вертикаль или диагональ поровну: это прокрутка страницы, не наше.
        case scroll
    }

    /// Ось по первому движению. Поровну — прокрутка (`|dx| <= |dy|` веба):
    /// страница важнее, светило подождёт осознанного горизонтального жеста.
    static func axis(dx: CGFloat, dy: CGFloat) -> Axis {
        if abs(dx) < threshold && abs(dy) < threshold { return .pending }
        return abs(dx) > abs(dy) ? .drag : .scroll
    }

    /// Точка рамки купола → точка `viewBox` 390×240. Обратное `DomeFit`:
    /// холст вписан по меньшей стороне, и палец ложится на нарисованное
    /// светило. Веб делит на ширину рамки (`/ rect.width * 390`) при том
    /// же вписывании — на 440 pt палец и солнце у него расходятся до 25 pt
    /// у краёв дуги (DECISIONS, 19в).
    static func viewPoint(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let fit = DomeFit(size: size)
        guard fit.scale > 0 else { return .zero }
        return CGPoint(x: (p.x - fit.origin.x) / fit.scale, y: (p.y - fit.origin.y) / fit.scale)
    }

    /// Доля дуги под точкой `viewBox`: 0 — восход слева, 1 — закат справа;
    /// `nil` — ниже горизонта. Угол берётся на эллипсе дуги, как у веба.
    /// Чуть ниже горизонта (до 8) угол отрицательный: слева это восход, справа
    /// закат. Веб прижимает любой отрицательный угол к нулю, и палец чуть ниже
    /// горизонта слева уводил солнце к закату (DECISIONS, 19в).
    static func fraction(at v: CGPoint) -> Double? {
        let g = DomeGeometry.self
        let vx = Double(v.x), vy = Double(v.y)
        if vy > g.cy + belowHorizon { return nil }
        var deg = atan2((g.cy - vy) / g.ry, (vx - g.cx) / g.rx) * 180 / .pi
        if deg < 0 { deg = deg < -90 ? 180 : 0 }
        return (180 - deg) / 180
    }

    /// Минута под долей дуги: восход…закат светила, прижатая к окну суток.
    /// Округление до минуты — как у веба (`Math.round`).
    static func minute(fraction f: Double, arcStart a: Minutes, arcEnd b: Minutes,
                       mint: Minutes, maxt: Minutes) -> Minutes {
        DomeGeometry.clamp((a + f * (b - a)).rounded(), mint, maxt)
    }

    /// Дуга светила, по которой ведёт палец: у солнца — `arcA…arcB` суток
    /// (восход…закат, в полярные сутки — всё окно), у луны — её дуга вокруг
    /// минуты на экране; луна не всходит — всё окно (`MINT…MAXT` веба).
    static func arc(moon: Bool, sun: SolarDay, date: CivilDate, place: Place, at t: Minutes,
                    mint: Minutes, maxt: Minutes) -> (start: Minutes, end: Minutes) {
        guard moon else { return (sun.arcA, sun.arcB) }
        guard let arc = MoonDay(date: date, place: place).arc(at: t) else { return (mint, maxt) }
        return (arc.rise, arc.set)
    }
}
