import Foundation

/// Ядро Млечного Пути на сутки (шаг 29.8в.17б): где оно идёт по небу выбранной даты, когда восходит и когда заходит.
///
/// Слово Алексея 20.10: «мне важно знать в котором часу и откуда появится млечный путь или куда он уйдет».
/// Положение ядра — `MilkyWay.corePosition` (то же, что у полосы и окна съёмки), второго расчёта неба здесь нет.
/// Восход и заход — там, где **видимая** высота ядра (с рефракцией, `SunTrack.apparent`) пересекает линию горизонта,
/// которую рисует AR: точка события лежит на линии, а не в 0,5° ниже. Геометрически это высота ≈ −0,57°, как у
/// звёзд в навигационных таблицах (34′ рефракции).
public enum MilkyWayCoreTrack {

    /// Точка суточной дуги ядра: минуты по часам места и положение.
    public struct Sample: Sendable, Equatable {
        public let minutes: Minutes
        public let azimuth: Degrees
        /// Геометрическая высота центра.
        public let altitude: Degrees
        /// Высота, как её видит камера.
        public var apparentAltitude: Degrees { SunTrack.apparent(altitude: altitude) }
    }

    /// Восход или заход ядра на линии горизонта.
    public struct Event: Sendable, Equatable {
        public enum Kind: Sendable { case rise, set }
        public let kind: Kind
        /// Минуты по часам места, `0 … 1440`.
        public let minutes: Minutes
        /// От севера по часовой.
        public let azimuth: Degrees
    }

    /// Что ядро делает в эти сутки на этой широте.
    public enum Passage: Sendable, Equatable {
        /// Пересекает горизонт: события в порядке времени (восход и заход; бывает только один из них — второй
        /// уходит в соседние сутки).
        case crossing([Event])
        /// Ниже горизонта все сутки: на этой широте не восходит (склонение ядра −29°, сутки его не меняют).
        case neverRises
        /// Над горизонтом все сутки: на этой широте не заходит.
        case neverSets

        public var events: [Event] {
            if case .crossing(let e) = self { return e }
            return []
        }
        public var rise: Event? { events.first { $0.kind == .rise } }
        public var set: Event? { events.first { $0.kind == .set } }
    }

    /// Шаг точек дуги, минуты: как у дуги солнца и луны.
    public static let arcStep: Minutes = SunTrack.arcStep

    /// Ниже этой видимой высоты дуга не рисуется (как у луны и солнца).
    public static let arcFrom: Degrees = SunTrack.arcFrom

    public static func sample(day: CivilDate, minutes: Minutes, in place: Place) -> Sample {
        sample(day: day, minutes: minutes, latitude: place.latitude, longitude: place.longitude,
               utcOffsetHours: place.zone.utcOffsetHours(on: day))
    }

    private static func sample(day: CivilDate, minutes: Minutes, latitude: Double, longitude: Double,
                               utcOffsetHours: Double) -> Sample {
        let p = MilkyWay.corePosition(date: day, minutes: minutes, latitude: latitude, longitude: longitude,
                                      utcOffsetHours: utcOffsetHours, time: .iau)
        return Sample(minutes: minutes, azimuth: p.azimuth, altitude: p.altitude)
    }

    /// Дуга суток: точки через `step` минут от полуночи до полуночи по часам места, все, не только видимые.
    public static func arc(day: CivilDate, in place: Place, step: Minutes = arcStep) -> [Sample] {
        let offset = place.zone.utcOffsetHours(on: day)
        var out: [Sample] = []
        var t = 0.0
        while t <= 1440 + 1e-9 {
            out.append(sample(day: day, minutes: t, latitude: place.latitude, longitude: place.longitude,
                              utcOffsetHours: offset))
            t += step
        }
        return out
    }

    /// Восходы и заходы суток: смена знака видимой высоты на шаге `scan` минут, затем деление пополам до 0,01 мин.
    /// Ядро идёт по небу не быстрее 15° в час, шаг 3 минуты пропустит пересечение только у ядра, едва задевающего
    /// горизонт сверху (высота в кульминации в пределах 0,4° от нуля) — там события нет в любом смысле.
    public static func passage(day: CivilDate, in place: Place, scan: Minutes = 3) -> Passage {
        let offset = place.zone.utcOffsetHours(on: day)
        func apparent(_ t: Minutes) -> Degrees {
            sample(day: day, minutes: t, latitude: place.latitude, longitude: place.longitude,
                   utcOffsetHours: offset).apparentAltitude
        }
        var events: [Event] = []
        var t = 0.0
        var prev = apparent(0)
        let first = prev
        while t < 1440 {
            let next = min(t + scan, 1440)
            let cur = apparent(next)
            if (prev < 0) != (cur < 0) {
                var lo = t, hi = next
                let rising = cur >= 0
                while hi - lo > 0.01 {
                    let mid = (lo + hi) / 2
                    if (apparent(mid) >= 0) == rising { hi = mid } else { lo = mid }
                }
                let at = (lo + hi) / 2
                let az = sample(day: day, minutes: at, latitude: place.latitude, longitude: place.longitude,
                                utcOffsetHours: offset).azimuth
                events.append(Event(kind: rising ? .rise : .set, minutes: at, azimuth: az))
            }
            prev = cur
            t = next
        }
        if events.isEmpty { return first >= 0 ? .neverSets : .neverRises }
        return .crossing(events)
    }
}

/// Что сказать фотографу о Млечном Пути на выбранные сутки (строки списка «Слоёв», 29.8в.17б): когда ядро над
/// горизонтом, когда темно и окно съёмки. Своих расчётов нет: проход ядра — `MilkyWayCoreTrack`, темнота — `SolarDay`
/// (солнце ниже −18°), окно — `MilkyWayWindow` (ядро выше `MilkyWay.workLow`, темно, Луна не мешает) без изменений.
public struct MilkyWayPlan: Sendable, Equatable {
    public enum Dark: Sendable, Equatable {
        /// Темнеет в это время вечером (минуты по часам места, `0 ..< 1440`).
        case from(Minutes)
        /// Солнце всё время ниже −18°.
        case allDay
        /// Солнце не уходит ниже −18°: темноты нет.
        case never
    }

    public let passage: MilkyWayCoreTrack.Passage
    public let dark: Dark
    /// Окно съёмки суток: часы, в которые ядро выше рабочей высоты, темно и Луна не мешает. Строже «над горизонтом»:
    /// сюда не попадает низкое ядро, сумерки и ночь с яркой Луной.
    public let window: MilkyWayWindow
    /// Отрезки окна для показа: те же, что `window.spans`, но отрезки, сросшиеся на стыке солнечных суток (окно считается
    /// от солнечной полуночи до следующей, и ночь, идущая через полночь, лежит в двух концах шкалы), склеены в один.
    /// Минуты — шкала суток окна, `to` может быть больше 1440; в часы места их переводит `ClockText`.
    public let shooting: [MilkyWayWindow.Span]

    public init(day: CivilDate, place: Place) {
        passage = MilkyWayCoreTrack.passage(day: day, in: place)
        window = MilkyWayWindow(date: day, place: place)
        shooting = Self.joinedAcrossSeam(window.spans)
        let sun = SolarDay(date: day, place: place)
        if let b = sun.astroB {
            dark = .from(((b.truncatingRemainder(dividingBy: 1440)) + 1440).truncatingRemainder(dividingBy: 1440))
        } else {
            dark = window.dark ? .allDay : .never
        }
    }

    /// Конец шкалы суток и её начало — один и тот же момент (`+1440`): отрезок, упирающийся в конец, и отрезок,
    /// начинающийся с начала, — один отрезок. Шаг окна — 5 минут, так что «упирается» значит «не дальше шага».
    static func joinedAcrossSeam(_ spans: [MilkyWayWindow.Span]) -> [MilkyWayWindow.Span] {
        guard spans.count >= 2, let first = spans.first, let last = spans.last,
              last.to + 5 >= first.from + 1440 else { return spans }
        return Array(spans.dropFirst().dropLast()) + [MilkyWayWindow.Span(from: last.from, to: first.to + 1440)]
    }
}
