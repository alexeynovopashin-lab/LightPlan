import Foundation

/// Загрузчик фикстур паритета.
///
/// Фикстуры лежат в `Fixtures/` в корне нативного репозитория, а не внутри
/// пакета: их читают тесты нескольких пакетов, а считает их узел из беты
/// (`Tools/parity/`). Класть в ресурсы пакета значило бы держать копию.
///
/// Пересобрать: `make parity` в корне.
enum ParityFixtures {

    /// Корень репозитория — от этого файла на пять уровней вверх:
    /// LightPlanCoreTests → Tests → LightPlanCore → Packages → корень.
    static var root: URL {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        return u
    }

    static var directory: URL { root.appendingPathComponent("Fixtures") }

    enum Failure: Error, CustomStringConvertible {
        case missing(String)
        var description: String {
            switch self {
            case .missing(let name):
                return "нет фикстуры \(name). Собрать: make parity (в корне \(ParityFixtures.root.path))"
            }
        }
    }

    static func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { throw Failure.missing(name) }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    // MARK: - Общее

    /// Паспорт фикстуры: чем посчитана и сколько в ней точек.
    /// `cut` — отпечаток вырезанного из беты кода: по нему видно, что все
    /// файлы посчитаны одним и тем же состоянием эталона.
    struct Meta: Decodable {
        let source: String
        let cut: String
        let what: String
        let count: Int
    }

    // MARK: - Солнце

    struct SolarDay: Decodable {
        let lat, lon, tz: Double
        let date: String
        let decl, solarNoon, mint, maxt: Double
        let rise, set: Double?
        let goldA, goldB, blueA, blueB, civA, civB, nauA, nauB, astA, astB: Double?
        let maxElev: Double
        /// 0 — обычные сутки, 1 — солнце не заходит, −1 — не восходит.
        let polar: Int
        let arcA, arcB: Double
    }
    struct SolarDayFile: Decodable { let meta: Meta; let days: [SolarDay] }

    struct SolarSeries: Decodable {
        let lat, lon, tz: Double
        let date: String
        let t, elev, az: [Double]
        /// Длина тени: null там, где солнце ниже 0.5° или тень длиннее сорока ростов.
        let shadow: [Double?]
    }
    struct SolarSampleFile: Decodable { let meta: Meta; let series: [SolarSeries] }

    // MARK: - Свет

    /// Отрезок состояния: с минуты `t` и до начала следующего отрезка
    /// состояние, уровень прибора, тон и зарево не меняются.
    struct StateRun: Decodable {
        let t: Int
        let code: String
        let level: Int?
        let tone: String
        let glow: Double
        let stars: Bool
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            t = try c.decode(Int.self)
            code = try c.decode(String.self)
            level = try c.decodeIfPresent(Int.self)
            tone = try c.decode(String.self)
            glow = try c.decode(Double.self)
            stars = try c.decode(Bool.self)
        }
    }
    struct WordRun: Decodable {
        let t: Int
        let key: String
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            t = try c.decode(Int.self)
            key = try c.decode(String.self)
        }
    }
    /// Ближайшее световое событие: ключ подписи и минута цели.
    /// Остаток считается на месте: `target − t`. Цель `nil` — полярные сутки.
    struct NextRun: Decodable {
        let t: Int
        let key: String
        let target: Double?
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            t = try c.decode(Int.self)
            key = try c.decode(String.self)
            target = try c.decodeIfPresent(Double.self)
        }
    }
    struct StateDay: Decodable {
        let lat, lon, tz: Double
        let date: String
        let t0, t1: Int
        let runs: [StateRun]
        let shadow: [WordRun]
        let next: [NextRun]
        /// Цвет неба каждые 10 минут: [минута, r, g, b].
        let sky: [[Int]]
    }
    /// Момент, когда солнце стоит ровно на пороге состояния. Сторона порога
    /// здесь не определена: её выбирает последний бит высоты — см. `StateGuard`.
    struct StateMark: Decodable {
        let lat, lon, tz: Double
        let date: String
        let h: Double
        let rising: Bool
        let t, elev: Double
        let k: String
        let level: Int?
        let tone: String
        let glow: Double
    }
    /// Проба в сотой градуса от порога: `side` −1 — ниже, +1 — выше.
    /// Здесь сторона определена, и коды сверяются строго.
    struct StateGuard: Decodable {
        let lat, lon, tz: Double
        let date: String
        let h: Double
        let side: Int
        let rising: Bool
        let t, elev: Double
        let k: String
        let level: Int?
        let tone: String
        let glow: Double
    }
    struct LightStateFile: Decodable {
        let meta: Meta
        let days: [StateDay]
        let marks: [StateMark]
        let guards: [StateGuard]
    }

    // MARK: - Закатный балл

    struct AirScore: Decodable {
        let low, mid, high, hum: Int
        let aod: Double?
        let score: Int
    }
    struct SunsetScoreFile: Decodable {
        let meta: Meta
        let axis: [Int]
        /// Порядок обхода сетки: low, mid, high, hum.
        let order: String
        let scores: [Int]
        let air: [AirScore]
    }

    // MARK: - Слияние снимков

    /// Снимок устройства — произвольный JSON: у книги фотографа не один тип.
    /// Разбирать его здесь незачем, задача фикстуры — сравнение целиком.
    indirect enum JSONValue: Decodable, Equatable {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null; return }
            if let v = try? c.decode(Bool.self) { self = .bool(v); return }
            if let v = try? c.decode(Double.self) { self = .number(v); return }
            if let v = try? c.decode(String.self) { self = .string(v); return }
            if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
            if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "не JSON")
        }

        /// Вид, в котором порядок записей в списках не считается разницей.
        /// Нужен ровно для одного вопроса: «стороны слияния не важны?»
        var canonical: String {
            switch self {
            case .null: return "null"
            case .bool(let v): return v ? "true" : "false"
            case .number(let v): return String(v)
            case .string(let v): return "\"\(v)\""
            case .array(let v): return "[" + v.map(\.canonical).sorted().joined(separator: ",") + "]"
            case .object(let v):
                return "{" + v.keys.sorted().map { "\($0):\(v[$0]!.canonical)" }.joined(separator: ",") + "}"
            }
        }
    }

    struct MergePair: Decodable {
        let name: String
        let a, b: JSONValue
        /// Результат слияния «a затем b» и обратного порядка.
        let ab, ba: JSONValue
    }
    struct MergePairsFile: Decodable { let meta: Meta; let pairs: [MergePair] }

    // MARK: - Луна и Млечный Путь

    struct MoonSeries: Decodable {
        let lat, lon, tz: Double
        let date: String
        let t: [Int]
        let alt, az, dist: [Double]
    }
    struct MoonFile: Decodable { let meta: Meta; let series: [MoonSeries] }

    struct CoreAltAz: Decodable {
        let lat, lon, tz: Double
        let date: String
        let t: Int
        let d, alt, az: Double
    }
    struct MilkyWayFile: Decodable {
        let meta: Meta
        /// Полоса: [галактическая долгота, полуширина, RA, Dec] — RA и Dec в радианах.
        let band: [[Double]]
        let core: [String: Double]
        let coreAltAz: [CoreAltAz]
    }
}
