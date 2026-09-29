import Foundation
import LightPlanCore

/// Ночь одного места в одни сутки для строки «Звёзды»: отрезки окна Млечного
/// Пути (`MilkyWayWindow.spans`) и почему окна может не быть.
public struct StarNight: Hashable, Sendable {
    /// Отрезки окна, минуты шкалы этих суток.
    public let spans: [ClosedRange<Int>]
    /// Была ли за сутки астрономическая темнота (солнце ≤ −18°).
    public let dark: Bool
    /// Луна закрыла хоть одну минуту, в остальном годную.
    public let moonBlocks: Bool
    /// Наибольшая освещённость луны над горизонтом в тёмное время, %.
    public let moonPercent: Int?

    public init(spans: [ClosedRange<Int>], dark: Bool, moonBlocks: Bool, moonPercent: Int?) {
        self.spans = spans
        self.dark = dark
        self.moonBlocks = moonBlocks
        self.moonPercent = moonPercent
    }
}

/// Что карточка скажет съёмке звёзд или луны. У веба этой строки нет: он судил
/// «Звёзды» и «Луну» по золотому часу. Алексей 29.09: «сразу — В» — своя строка
/// в 26; «звёздам не нужен свет» — о золотом часе говорит только «Закат»
/// (DECISIONS 29.09, итерация 26, шаг 1). Правило и слова — шаг 3.
///
/// Точки — те же, что у `LightCase`: маршрут, без маршрута — часы съёмки; у
/// каждой своё место и свои сутки. Мимо — строка говорит всегда (веб у золотого
/// часа молчит дальше трёх часов): пожелание заказано, и ответ «окно в 01:10 –
/// 03:40» нужен и съёмке в 20:00.
public enum NightLight: Hashable, Sendable {
    /// Точка в окне Млечного Пути (минуты от полуночи первого дня).
    case starsIn(point: LightPoint?, window: ClosedRange<Int>)
    /// Окно есть, точка мимо на `gap` минут.
    case starsNear(point: LightPoint?, window: ClosedRange<Int>, gap: Int)
    /// Окна нет: темнота есть, ядро высоко, но луна светит.
    case starsMoon(percent: Int)
    /// Окна нет: ядро в тёмное время ниже рабочей высоты.
    case starsLow
    /// Окна нет: небо не темнеет (белые ночи).
    case starsNoDark
    /// Точка — когда луна над горизонтом; освещена на `percent` %.
    case moonUp(point: LightPoint?, arc: ClosedRange<Int>, percent: Int)
    /// Луна над горизонтом не в точку: ближайшая дуга и насколько мимо.
    case moonNear(point: LightPoint?, arc: ClosedRange<Int>, gap: Int)
    /// Луна в эти сутки не всходит.
    case moonNone

    struct Probe { let point: LightPoint; let at: GeoPoint?; let day: Int }

    static func probes(_ s: Session, route: [RoutePoint], spots: [Spot], studios: [Studio]) -> [Probe] {
        let at = Stops.skyPoint(of: s, spots: spots, studios: studios)
        if route.isEmpty {
            return LightCase.hours(of: s).map { Probe(point: LightPoint(minute: $0, name: nil), at: at, day: Session.floorDiv($0, 1440)) }
        }
        return route.map { r in
            let t = r.start ?? 0
            return Probe(point: LightPoint(minute: t, name: r.name),
                         at: Stops.place(of: r, spots: spots, studios: studios)?.point ?? at,
                         day: Session.floorDiv(t, 1440))
        }
    }

    /// Строка «Звёзды» (пожелание `stars`); `nil` — пожелания нет.
    ///
    /// Окно суток кончается около полуночи, следующее начинается с неё: ночь с
    /// 23:00 до 02:00 лежит в двух сутках. Отрезки соседних суток сшиваются,
    /// если между ними не больше шага окна (5 мин), — иначе «окно 21:40 –
    /// 23:59» обрывалось бы на полуночи.
    public static func stars(_ s: Session, route: [RoutePoint], spots: [Spot], studios: [Studio],
                             night: (GeoPoint?, CivilDate) -> StarNight) -> NightLight? {
        guard s.wishes.contains(.stars) else { return nil }
        let ps = probes(s, route: route, spots: spots, studios: studios)
        func spans(_ p: Probe) -> [ClosedRange<Int>] {
            var all: [ClosedRange<Int>] = []
            for k in (p.day - 1)...(p.day + 1) {
                let shift = k * 1440
                all += night(p.at, s.date(ofDay: k)).spans.map { ($0.lowerBound + shift)...($0.upperBound + shift) }
            }
            return merge(all)
        }
        var near: (Probe, ClosedRange<Int>, Int)?
        for p in ps {
            let t = p.point.minute
            for w in spans(p) {
                if w.contains(t) { return .starsIn(point: p.point, window: w) }
                let d = min(abs(t - w.lowerBound), abs(t - w.upperBound))
                if near == nil || d < near!.2 { near = (p, w, d) }
            }
        }
        if let (p, w, d) = near { return .starsNear(point: p.point, window: w, gap: d) }
        let n = night(ps.first?.at ?? Stops.skyPoint(of: s, spots: spots, studios: studios), s.day)
        if !n.dark { return .starsNoDark }
        if n.moonBlocks { return .starsMoon(percent: n.moonPercent ?? 0) }
        return .starsLow
    }

    /// Строка «Луна» (пожелание `moon`); `nil` — пожелания нет.
    ///
    /// - Parameters:
    ///   - arcs: дуги луны над горизонтом этих суток (`MoonDay.arcs`, минуты шкалы суток).
    ///   - lit: освещённость диска, %, в минуту шкалы этих суток.
    public static func moon(_ s: Session, route: [RoutePoint], spots: [Spot], studios: [Studio],
                            arcs: (GeoPoint?, CivilDate) -> [ClosedRange<Int>],
                            lit: (GeoPoint?, CivilDate, Int) -> Int) -> NightLight? {
        guard s.wishes.contains(.moon) else { return nil }
        var near: (Probe, ClosedRange<Int>, Int)?
        var any = false
        for p in probes(s, route: route, spots: spots, studios: studios) {
            let t = p.point.minute, shift = p.day * 1440
            for a in arcs(p.at, s.date(ofDay: p.day)) {
                any = true
                let w = (a.lowerBound + shift)...(a.upperBound + shift)
                if w.contains(t) {
                    return .moonUp(point: p.point, arc: w, percent: lit(p.at, s.date(ofDay: p.day), t - shift))
                }
                let d = min(abs(t - w.lowerBound), abs(t - w.upperBound))
                if near == nil || d < near!.2 { near = (p, w, d) }
            }
        }
        if let (p, w, d) = near { return .moonNear(point: p.point, arc: w, gap: d) }
        return any ? nil : .moonNone
    }

    /// Отрезки по началу, соседние с зазором не больше 5 минут — в один.
    static func merge(_ xs: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        var out: [ClosedRange<Int>] = []
        for x in xs.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = out.last, x.lowerBound <= last.upperBound + 5 {
                out[out.count - 1] = last.lowerBound...max(last.upperBound, x.upperBound)
            } else {
                out.append(x)
            }
        }
        return out
    }
}
