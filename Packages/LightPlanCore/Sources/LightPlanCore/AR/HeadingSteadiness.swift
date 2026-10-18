import Foundation

/// Устойчивость курса для слоя AR (шаг 29.8в): когда компас «дрожит» и стоит попросить телефон повести восьмёркой.
///
/// Критерий — из «Солнечного компаса» (`isHeadingStable`): за окно 0,5 с разброс курса меньше 5° и не меньше пяти
/// отсчётов. Разница одна, и она по делу: в компасе окно судит неподвижного, а здесь телефон водят за солнцем.
/// Обычный поворот на 30°/с даёт разброс 15° за 0,5 с — это не неисправность. Поэтому из разброса вычитается то,
/// что объясняет гироскоп (средняя скорость поворота × окно): остаток больше 5° — курс прыгает при телефоне,
/// который почти не вращается.
///
/// Вычитается не полная угловая скорость телефона, а та её часть, что двигает курс (`headingRate`, шаг 29.8в.6):
/// крен вокруг оси камеры и наклон вверх-вниз курс не меняют, и полная скорость списывала бы на них настоящий
/// скачок компаса (ревью GPT к 29.8в.3–4).
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

    /// Занести отсчёт. `rate` — скорость, с которой вращение телефона двигает курс, градусы в секунду (`headingRate`);
    /// без датчика, где известна только полная скорость, — она (верхняя оценка: тише предупреждение, не громче).
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

    /// Скорость изменения азимута оси камеры при вращении телефона, °/с (модуль).
    ///
    /// Ось камеры `p`, высота `a`, угловая скорость `ω`: `ṗ = ω × p`, азимут идёт по горизонтальной части `ṗ`, откуда
    /// `Ȧ = (ω_вверх − (ω·p) sin a) / cos² a`. В осях устройства (камера смотрит вдоль −Z, строка 3 матрицы —
    /// ось Z устройства в системе «север, запад, вверх») `ω_вверх = ωx·m13 + ωy·m23 + ωz·m33`, `ω·p = −ωz`,
    /// `sin a = −m33`, и компонента `ωz` сокращается: `Ȧ = (ωx·m13 + ωy·m23) / (1 − m33²)`.
    /// Крен (ω вдоль оси камеры) и наклон при горизонтальной камере дают 0. Около зенита знаменатель → 0, поэтому
    /// он не меньше 0,067 (высота 75°, выше отсчёты в окно не берутся).
    /// - Parameter angularVelocity: `CMDeviceMotion.rotationRate`, радианы в секунду, оси устройства.
    public static func headingRate(angularVelocity w: (x: Double, y: Double, z: Double), rotation m: DeviceRotation) -> Double {
        let denominator = max(1 - m.m33 * m.m33, 0.067)
        return abs(w.x * m.m13 + w.y * m.m23) / denominator * 180 / Double.pi
    }

    /// Скорость вращения телефона вокруг вертикали со знаком, °/с: проекция угловой скорости на «вверх» мира
    /// (`ω_вверх = ωx·m13 + ωy·m23 + ωz·m33`, см. вывод выше). Крен и наклон её не дают; поворот на месте даёт полную.
    /// Магнитная поправка положения сюда не попадает: это гироскоп.
    public static func verticalRate(angularVelocity w: (x: Double, y: Double, z: Double), rotation m: DeviceRotation) -> Double {
        (w.x * m.m13 + w.y * m.m23 + w.z * m.m33) * 180 / Double.pi
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
