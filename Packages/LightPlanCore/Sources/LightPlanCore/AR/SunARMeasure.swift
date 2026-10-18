import Foundation

#if DEBUG
/// Измеритель отклонения компаса в AR (шаг 29.8в.11). Только измерение: поправки курса, подгонки и правок расчёта
/// светил здесь нет. Нужен, чтобы сравнивать чехлы числом, а не словами «чуть влево»: наводят прицел (центр кадра)
/// на настоящее солнце или луну, нажимают «Замер», 2,5 с собираются отсчёты, из них — медиана и размах.
///
/// Только отладочная сборка: в выпуске этого файла нет. Ничего не знает о датчиках и экране — получает готовые
/// отсчёты (`MeasureSample`), поэтому весь счёт проверяется юнит-тестами на подставных потоках.

/// Чем мерим: солнцем или луной. Расчётная точка луны — та же, что рисует диск луны в AR (`MoonTrack`).
public enum MeasureBody: String, Sendable, Codable, CaseIterable {
    case sun, moon

    /// Куда это тело по расчёту в момент: азимут от истинного севера и видимая высота — ровно то, что рисует диск.
    public func expected(at moment: Moment, in place: Place) -> HorizontalPoint {
        switch self {
        case .sun:
            let s = SunTrack.sample(at: moment, in: place)
            return HorizontalPoint(altitude: s.apparentAltitude, azimuth: s.azimuth)
        case .moon:
            let m = MoonTrack.sample(at: moment, in: place)
            return HorizontalPoint(altitude: m.apparentAltitude, azimuth: m.azimuth)
        }
    }
}

/// Один отсчёт замера: что показывают датчики и где тело по расчёту в тот же миг.
public struct MeasureSample: Sendable, Equatable {
    public let time: TimeInterval
    /// Центр кадра по ориентации CoreMotion (`xTrueNorthZVertical`): азимут и высота.
    public let aim: HorizontalPoint
    /// `CLHeading.trueHeading`, градусы; `nil` — свежего значения нет.
    public let compassHeading: Degrees?
    /// Расчётное положение тела на этот миг.
    public let expected: HorizontalPoint
    /// Погрешность курса от системы (`CLHeading.headingAccuracy`), градусы.
    public let headingAccuracy: Degrees?
    /// Ступень точности магнитного поля (`CMDeviceMotion.magneticField.accuracy`).
    public let magneticLevel: MagneticAccuracy?

    public init(time: TimeInterval, aim: HorizontalPoint, compassHeading: Degrees?, expected: HorizontalPoint,
                headingAccuracy: Degrees? = nil, magneticLevel: MagneticAccuracy? = nil) {
        self.time = time
        self.aim = aim
        self.compassHeading = compassHeading
        self.expected = expected
        self.headingAccuracy = headingAccuracy
        self.magneticLevel = magneticLevel
    }
}

/// Медиана отклонения и размах (max − min) за время замера, градусы.
public struct MeasureSpread: Sendable, Equatable, Codable {
    public let median: Degrees
    public let range: Degrees

    public init(median: Degrees, range: Degrees) {
        self.median = median
        self.range = range
    }
}

/// Итог замера. Отклонение = расчёт − датчик: `+` значит тело правее (по курсу) или выше (по высоте) центра кадра.
public struct MeasureResult: Sendable, Equatable, Codable {
    public let body: MeasureBody
    public let samples: Int
    /// Расчётное положение тела (медианы за замер).
    public let expectedAzimuth: Degrees
    public let expectedAltitude: Degrees
    /// Курс центра кадра по CoreMotion и по `CLHeading.trueHeading` (медианы).
    public let motionHeading: Degrees
    public let compassHeading: Degrees?
    /// Высота центра кадра (медиана).
    public let centerAltitude: Degrees
    /// Отклонение по курсу — отдельно для каждого источника курса.
    public let motionAzimuth: MeasureSpread
    public let compassAzimuth: MeasureSpread?
    public let altitude: MeasureSpread
    /// Погрешность курса от системы на момент замера (последний отсчёт), градусы.
    public let headingAccuracy: Degrees?
    /// Ступень точности поля (`MagneticAccuracy.rawValue`) на момент замера.
    public let magneticLevel: Int?

    /// Разброс одним числом, как на плашке: размах курса по CoreMotion — тому, чем рисуется диск.
    public var scatter: Degrees { motionAzimuth.range }
}

/// Почему замер не принят.
public enum MeasureRefusal: String, Sendable, Equatable, Codable {
    /// Тело ниже горизонта (высота < −1°): мерить нечего.
    case belowHorizon
    /// По расчёту тело дальше 30° от центра кадра по любой оси: прицел наведён не туда.
    case offAim
    /// Отсчётов нет: датчик замолчал.
    case noData
    /// Датчика нет (симулятор без позы, Mac): центр кадра ведёт палец, а не телефон.
    case noSensor
}

public enum MeasureOutcome: Sendable, Equatable {
    case result(MeasureResult)
    case refused(MeasureRefusal)
}

/// Копилка замера: принимает отсчёты 10 Гц в окне 2,5 с, потом отдаёт итог.
public struct SunARMeasurer: Sendable {
    public static let duration: TimeInterval = 2.5
    public static let interval: TimeInterval = 0.1
    /// Ниже этой высоты тело считается под горизонтом.
    public static let horizonLimit: Degrees = -1
    /// Дальше этого от центра кадра (по любой оси) замер не имеет смысла.
    public static let aimLimit: Degrees = 30

    public private(set) var samples: [MeasureSample] = []
    private var first: TimeInterval?
    private var last: TimeInterval?

    public init() {}

    /// Доля собранного окна `0 … 1`.
    public var progress: Double {
        guard let first, let last else { return 0 }
        return min(1, max(0, (last - first) / Self.duration))
    }

    /// Окно закрыто: последний принятый отсчёт лёг не раньше конца окна.
    public var isComplete: Bool { progress >= 1 }

    /// Принять отсчёт: из быстрого потока берётся не чаще 10 Гц. `true` — отсчёт принят.
    @discardableResult
    public mutating func add(_ s: MeasureSample) -> Bool {
        if let last, s.time - last < Self.interval - 1e-9 { return false }
        if first == nil { first = s.time }
        last = s.time
        samples.append(s)
        return true
    }

    /// Разность углов `a − b` в `[−180, 180)`: курс переходит через 0°/360°, отклонение — нет.
    public static func signed(_ a: Degrees, minus b: Degrees) -> Degrees {
        let d = (a - b).truncatingRemainder(dividingBy: 360)
        return d >= 180 ? d - 360 : (d < -180 ? d + 360 : d)
    }

    static func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    private static func spread(_ v: [Double]) -> MeasureSpread {
        MeasureSpread(median: median(v), range: (v.max() ?? 0) - (v.min() ?? 0))
    }

    /// Круговая медиана курса: курс у севера (359°, 1°) средним по числам дал бы юг. Берётся относительно первого
    /// отсчёта, как отклонение.
    private static func medianHeading(_ v: [Double]) -> Double {
        guard let ref = v.first else { return 0 }
        let m = median(v.map { signed($0, minus: ref) })
        return (ref + m + 360).truncatingRemainder(dividingBy: 360)
    }

    public func finish(body: MeasureBody) -> MeasureOutcome {
        guard !samples.isEmpty else { return .refused(.noData) }
        let expAlt = Self.median(samples.map { $0.expected.altitude })
        if expAlt < Self.horizonLimit { return .refused(.belowHorizon) }

        let motionAz = samples.map { Self.signed($0.expected.azimuth, minus: $0.aim.azimuth) }
        let alt = samples.map { $0.expected.altitude - $0.aim.altitude }
        let azSpread = Self.spread(motionAz), altSpread = Self.spread(alt)
        if abs(azSpread.median) > Self.aimLimit || abs(altSpread.median) > Self.aimLimit {
            return .refused(.offAim)
        }

        // Курс системного компаса: нужен не один отсчёт, иначе размах 0° — не разброс, а нехватка данных.
        let compass = samples.compactMap { s in s.compassHeading.map { Self.signed(s.expected.azimuth, minus: $0) } }
        let compassHeadings = samples.compactMap(\.compassHeading)
        let lastSample = samples[samples.count - 1]
        return .result(MeasureResult(
            body: body, samples: samples.count,
            expectedAzimuth: Self.medianHeading(samples.map { $0.expected.azimuth }),
            expectedAltitude: expAlt,
            motionHeading: Self.medianHeading(samples.map { $0.aim.azimuth }),
            compassHeading: compass.count >= 3 ? Self.medianHeading(compassHeadings) : nil,
            centerAltitude: Self.median(samples.map { $0.aim.altitude }),
            motionAzimuth: azSpread,
            compassAzimuth: compass.count >= 3 ? Self.spread(compass) : nil,
            altitude: altSpread,
            headingAccuracy: lastSample.headingAccuracy,
            magneticLevel: lastSample.magneticLevel?.rawValue))
    }
}

/// Замер вместе с обстановкой — строка журнала и строка истории на плашке.
public struct MeasureRecord: Sendable, Equatable, Codable {
    /// Когда нажали «Замер» (системные часы).
    public let time: Date
    /// Мгновение по часам приложения, для которого считалось расчётное положение.
    public let moment: Date
    /// Откуда место: `phone` или `chosen`.
    public let placeSource: String
    public let latitude: Double
    public let longitude: Double
    /// `true` — отсчёты от истинного севера, `false` — от магнитного.
    public let trueNorth: Bool?
    public let caseLabel: String
    public let phone: String
    public let systemVersion: String
    public let result: MeasureResult

    public init(time: Date, moment: Date, placeSource: String, latitude: Double, longitude: Double, trueNorth: Bool?,
                caseLabel: String, phone: String, systemVersion: String, result: MeasureResult) {
        self.time = time
        self.moment = moment
        self.placeSource = placeSource
        self.latitude = latitude
        self.longitude = longitude
        self.trueNorth = trueNorth
        self.caseLabel = caseLabel
        self.phone = phone
        self.systemVersion = systemVersion
        self.result = result
    }
}

/// CSV журнала замеров: одна строка на замер, разделитель — запятая, десятичная — точка, время — UTC.
public enum MeasureCSV {
    public static let columns = [
        "time_utc", "moment_utc", "body", "place_source", "lat", "lon",
        "expected_az", "expected_alt", "heading_motion", "heading_compass", "center_alt",
        "dev_az_motion", "dev_az_compass", "dev_alt",
        "range_az_motion", "range_az_compass", "range_alt",
        "samples", "accuracy_deg", "mag_level", "north", "case", "phone", "ios",
    ]

    public static var header: String { columns.joined(separator: ",") }

    static func quote(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }

    private static func num(_ v: Double?, _ digits: Int = 2) -> String {
        v.map { String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
    }

    public static func row(_ r: MeasureRecord) -> String {
        let m = r.result
        let north = r.trueNorth.map { $0 ? "true" : "magnetic" } ?? ""
        let fields: [String] = [
            iso(r.time), iso(r.moment), m.body.rawValue, r.placeSource, num(r.latitude, 5), num(r.longitude, 5),
            num(m.expectedAzimuth), num(m.expectedAltitude), num(m.motionHeading), num(m.compassHeading), num(m.centerAltitude),
            num(m.motionAzimuth.median), num(m.compassAzimuth?.median), num(m.altitude.median),
            num(m.motionAzimuth.range), num(m.compassAzimuth?.range), num(m.altitude.range),
            String(m.samples), num(m.headingAccuracy, 1), m.magneticLevel.map(String.init) ?? "", north,
            quote(r.caseLabel), quote(r.phone), quote(r.systemVersion),
        ]
        return fields.joined(separator: ",")
    }
}
#endif
