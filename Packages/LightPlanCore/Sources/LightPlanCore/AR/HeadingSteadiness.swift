import Foundation

/// Устойчивость курса для слоя AR (шаг 29.8в): когда компас «дрожит» и стоит попросить телефон повести восьмёркой.
///
/// Критерий — из «Солнечного компаса» (`isHeadingStable`): за окно 0,5 с разброс курса меньше 5° и не меньше пяти
/// отсчётов. Разница одна, и она по делу: в компасе окно судит неподвижного, а здесь телефон водят за солнцем.
/// Обычный поворот на 30°/с даёт разброс 15° за 0,5 с — это не неисправность. Поэтому из разброса вычитается то,
/// что объясняет гироскоп (средняя скорость поворота × окно): остаток больше 5° — курс прыгает при телефоне,
/// который почти не вращается.
public struct HeadingSteadiness: Sendable {
    public static let window: TimeInterval = 0.5
    public static let tolerance: Degrees = 5
    public static let minSamples = 5
    /// Раз поднятое предупреждение держится не меньше, чтобы не мигать на границе порога.
    public static let hold: TimeInterval = 1.5

    private struct Reading: Sendable {
        let time: TimeInterval
        let heading: Degrees
        let rate: Double
    }

    private var readings: [Reading] = []
    private var unsteadyUntil: TimeInterval = -.infinity

    public init() {}

    /// Занести отсчёт. `rate` — скорость вращения телефона целиком, градусы в секунду (модуль угловой скорости).
    public mutating func add(time: TimeInterval, heading: Degrees, rate: Double) {
        readings.append(Reading(time: time, heading: heading, rate: rate))
        readings.removeAll { time - $0.time > Self.window }
        if let excess = excess, excess > Self.tolerance {
            unsteadyUntil = time + Self.hold
        }
        lastTime = time
    }

    private var lastTime: TimeInterval = 0

    /// Курс прыгает — показывать подсказку.
    public var isUnsteady: Bool { lastTime < unsteadyUntil }

    /// Разброс курса в окне минус объяснённый поворотом; `nil` — отсчётов мало.
    public var excess: Degrees? {
        guard readings.count >= Self.minSamples else { return nil }
        let spread = Self.circularSpread(readings.map(\.heading))
        let meanRate = readings.map(\.rate).reduce(0, +) / Double(readings.count)
        return max(0, spread - meanRate * Self.window)
    }

    public mutating func reset() {
        readings.removeAll()
        unsteadyUntil = -.infinity
    }

    /// Разброс углов по кругу: 360° минус самый большой промежуток между соседними. У `359°` и `1°` — 2°,
    /// а не 358°, как дал бы `max − min` в «Солнечном компасе» у самого севера.
    public static func circularSpread(_ angles: [Degrees]) -> Degrees {
        guard angles.count > 1 else { return 0 }
        let sorted = angles.map { ($0.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }.sorted()
        var largestGap = sorted[0] + 360 - sorted[sorted.count - 1]
        for i in 1..<sorted.count { largestGap = max(largestGap, sorted[i] - sorted[i - 1]) }
        return 360 - largestGap
    }
}
