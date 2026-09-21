import Foundation

extension MilkyWay {
    /// Рабочая высота ядра для астропейзажа (`MW_WORK_LO`, `MW_WORK_HI`). Ниже
    /// десяти градусов снимать нечего: атмосфера съедает свет по касательной,
    /// снизу подмешивается засветка и дымка. Выше пятнадцати — уже честно.
    /// Между ними зона «как повезёт».
    public static let workLow: Degrees = 10
    public static let workHigh: Degrees = 15
}

/// Окно астросъёмки Млечного Пути одних суток: пересечение трёх условий —
/// ядро выше рабочей высоты, солнце ниже −18°, луна не светит в кадр.
///
/// Порт `mwWindow` веба. Шаг 5 минут от начала до конца шкалы суток — поведение
/// продукта, не оптимизация. Значение-тип: солнце суток — свой `SolarDay`, а не
/// глобалы `MINT`, `MAXT`, `decl`, которые веб берёт от выбранного дня.
public struct MilkyWayWindow: Sendable, Equatable {

    /// Настоящий отрезок окна: часы, в которые все три условия держатся.
    public struct Span: Sendable, Equatable {
        public let from: Minutes
        public let to: Minutes
    }

    /// Момент, когда ядро стоит выше всего за сутки. `minute` — `nil`, пока
    /// не нашлось ни одного отсчёта (у веба тогда `t: null`, высота −99).
    public struct Best: Sendable, Equatable {
        public let altitude: Degrees
        public let minute: Minutes?
    }

    public let best: Best
    /// Оболочка окна — первая и последняя годная минута. Строка «Съёмка»
    /// показывает именно её: «с 20:39 до 3:00» читается, а перечень отрезков
    /// нет. Внутри оболочки бывают дыры (луна взошла и села, ядро нырнуло под
    /// рабочую высоту) — их видно только в `spans`.
    public let from: Minutes?
    public let to: Minutes?
    /// Настоящие отрезки: нужны тому, кто по окну считает, а не показывает
    /// (погода над окном, итерация 10).
    public let spans: [Span]
    /// Было ли за сутки хоть одно тёмное время (солнце ≤ −18°).
    public let dark: Bool
    /// Луна хоть раз закрыла минуту, в остальном годную.
    public let moonBlocks: Bool

    // MARK: - Входы

    public init(date: CivilDate, latitude: Double, longitude: Double, utcOffsetHours: Double) {
        let sun = SolarDay(date: date, latitude: latitude, longitude: longitude, utcOffsetHours: utcOffsetHours)

        var bestAltitude = -99.0
        var bestMinute: Minutes?
        var from: Minutes?, to: Minutes?
        var moonBlocks = false, darkAny = false
        var spans: [Span] = []
        var open: Minutes?, previous: Minutes?

        var x = Sky.jsRound(sun.mint)
        let last = Sky.jsRound(sun.maxt)
        while x <= last {
            let core = MilkyWay.corePosition(
                date: date, minutes: x,
                latitude: latitude, longitude: longitude, utcOffsetHours: utcOffsetHours
            )
            if core.altitude > bestAltitude { bestAltitude = core.altitude; bestMinute = x }
            let dark = sun.elevation(at: x) <= -18
            if dark { darkAny = true }
            var ok = dark && core.altitude >= MilkyWay.workLow
            if ok {
                let moon = MoonSample(
                    date: date, minutes: x,
                    latitude: latitude, longitude: longitude, utcOffsetHours: utcOffsetHours
                )
                // Луна мешает, если над горизонтом и освещена больше чем на 40 %.
                if moon.altitude > 0 && moon.phase.fraction > 0.4 { moonBlocks = true; ok = false }
            }
            if ok {
                if from == nil { from = x }
                to = x
                if open == nil { open = x }
                previous = x
            } else if let start = open, let end = previous {
                spans.append(Span(from: start, to: end))
                open = nil
            }
            x += 5
        }
        if let start = open, let end = previous { spans.append(Span(from: start, to: end)) }

        self.best = Best(altitude: bestAltitude, minute: bestMinute)
        self.from = from
        self.to = to
        self.spans = spans
        self.dark = darkAny
        self.moonBlocks = moonBlocks
    }

    public init(date: CivilDate, place: Place) {
        self.init(
            date: date,
            latitude: place.latitude, longitude: place.longitude,
            utcOffsetHours: place.zone.utcOffsetHours(on: date)
        )
    }
}
