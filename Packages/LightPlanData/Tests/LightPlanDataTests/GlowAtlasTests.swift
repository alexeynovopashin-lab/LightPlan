import Foundation
import Testing
import LightPlanCore
@testable import LightPlanData

/// Загрузчик атласа засветки (итерация 20б): распаковка, кэш, смена места.
/// Арифметика атласа сверена с вебом в `GlowParityTests` (ядро).
@MainActor
struct GlowAtlasTests {

    /// Gzip в том виде, в каком его отдаёт атлас: с именем файла в заголовке;
    /// здесь ещё и с полем FEXTRA — его пропуск тоже должен сработать.
    static func gzip(_ raw: [UInt8], name: String = "binary_tile_44_25.dat", extra: Bool = true) -> Data {
        let body = try! (Data(raw) as NSData).compressed(using: .zlib) as Data
        var h: [UInt8] = [0x1F, 0x8B, 8, 0x08 | (extra ? 0x04 : 0), 0, 0, 0, 0, 0, 3]
        if extra { h += [3, 0, 0xAA, 0xBB, 0xCC] }
        h += Array(name.utf8) + [0]
        return Data(h) + body + Data([0, 0, 0, 0]) + Data([0, 0, 0, 0])
    }

    /// Плитка, у которой в каждой ячейке своё значение: первая точка 1·128,
    /// приращения +1 по столбцу и +2 по строке — v = 128 + (iy − 1) + 2·(ix − 1).
    static func ramp() -> [UInt8] {
        var raw = [UInt8](repeating: 0, count: Glow.size)
        raw[0] = 1
        for i in 1..<Glow.row { raw[Glow.row * i + 1] = 1 }
        for r in 0..<Glow.row { for c in 2..<Glow.row { raw[Glow.row * r + c] = 2 } }
        return raw
    }

    static func expected(ix: Int, iy: Int) -> Double {
        let v = 128 + (iy - 1) + 2 * (ix - 1)
        return (5.0 / 195) * (exp(0.0195 * Double(v)) - 1)
    }

    final class Source: GlowTileSource, @unchecked Sendable {
        var tiles: [String: Data] = [:]
        var asked: [String] = []
        func tile(tx: Int, ty: Int) async throws -> Data {
            asked.append("\(tx)_\(ty)")
            guard let d = tiles["\(tx)_\(ty)"] else { throw URLError(.notConnectedToInternet) }
            return d
        }
    }

    @Test("Gzip: заголовок с именем файла и FEXTRA, поток распакован байт в байт")
    func inflate() throws {
        let raw = Self.ramp()
        #expect(try Gzip.inflate(Self.gzip(raw)) == raw)
        #expect(try Gzip.inflate(Self.gzip(raw, extra: false)) == raw)
        #expect(throws: Gzip.Failure.self) { try Gzip.inflate(Data([1, 2, 3])) }
    }

    @Test("Место в атласе: значение прочитано, та же плитка второй раз не спрашивается")
    func readsAndCaches() async {
        let src = Source()
        let moscow = Glow.index(latitude: 55.7539, longitude: 37.6208)!
        src.tiles[moscow.tile] = Self.gzip(Self.ramp())
        let store = GlowStore(place: Place(latitude: 55.7539, longitude: 37.6208, zone: ZoneID(fixedOffsetHours: 3)),
                              source: src, debounce: .zero)
        await store.settled()
        #expect(store.ratio == Self.expected(ix: moscow.ix, iy: moscow.iy))
        store.move(to: Place(latitude: 55.9, longitude: 37.5, zone: ZoneID(fixedOffsetHours: 3)))
        await store.settled()
        let near = Glow.index(latitude: 55.9, longitude: 37.5)!
        #expect(near.tile == moscow.tile)
        #expect(store.ratio == Self.expected(ix: near.ix, iy: near.iy))
        #expect(src.asked == [moscow.tile])
    }

    @Test("Вне атласа, офлайн, короткая плитка — строки нет")
    func silentFailures() async {
        let src = Source()
        let store = GlowStore(place: Place(latitude: 78.2, longitude: 15.6, zone: ZoneID(fixedOffsetHours: 1)),
                              source: src, debounce: .zero)
        await store.settled()
        #expect(store.ratio == nil)
        #expect(src.asked.isEmpty)                                    // Шпицберген: в сеть не ходим

        store.move(to: Place(latitude: 55.75, longitude: 37.62, zone: ZoneID(fixedOffsetHours: 3)))
        await store.settled()
        #expect(store.ratio == nil)                                   // офлайн

        let ix = Glow.index(latitude: 45, longitude: 37)!
        src.tiles[ix.tile] = Self.gzip([UInt8](repeating: 0, count: Glow.size - 1))
        store.move(to: Place(latitude: 45, longitude: 37, zone: ZoneID(fixedOffsetHours: 3)))
        await store.settled()
        #expect(store.ratio == nil)                                   // короткая плитка
    }

    @Test("Ответ про прежнее место не пишется поверх нового")
    func staleAnswer() async {
        final class Slow: GlowTileSource, @unchecked Sendable {
            let data: Data
            init(_ d: Data) { data = d }
            func tile(tx: Int, ty: Int) async throws -> Data {
                if tx == 44 { try await Task.sleep(for: .milliseconds(200)) }
                return data
            }
        }
        let gz = Self.gzip(Self.ramp())
        let store = GlowStore(place: Place(latitude: 55.75, longitude: 37.62, zone: ZoneID(fixedOffsetHours: 3)),
                              source: Slow(gz), debounce: .zero)
        try? await Task.sleep(for: .milliseconds(20))              // Москва в пути
        store.move(to: Place(latitude: 40, longitude: 10, zone: ZoneID(fixedOffsetHours: 1)))
        try? await Task.sleep(for: .milliseconds(400))
        let rome = Glow.index(latitude: 40, longitude: 10)!
        #expect(store.ratio == Self.expected(ix: rome.ix, iy: rome.iy))
    }

    /// Настоящие плитки атласа на местах замеров веба (DECISIONS «Засветка
    /// неба…», итерация 20б). Нужна сеть: `LIGHT_PLAN_NET=1 swift test`.
    @Test("Атлас на известных точках — как веб", .enabled(if: ProcessInfo.processInfo.environment["LIGHT_PLAN_NET"] == "1"))
    func knownPlaces() async throws {
        // Числа — веб (`glowRead` беты) на тех же плитках 2025 года, 23.09.2026.
        let places: [(String, Double, Double, Double, Glow.Level)] = [
            ("Москва", 55.7539, 37.6208, 165.88317790095843, .none),
            ("Петербург", 59.9386, 30.3141, 156.4559468763359, .none),
            ("Лобня", 56.0130, 37.4820, 39.16501508546004, .none),
            ("Териберка", 69.1653, 35.1386, 0.7992024425878614, .dark),
            ("Гёреме", 38.6431, 34.8289, 11.007883849736656, .city),
            ("Паранал", -24.6272, -70.4042, 0.008712121450356207, .dark),
        ]
        for (name, lat, lon, want, level) in places {
            let ix = try #require(Glow.index(latitude: lat, longitude: lon))
            let raw = try Gzip.inflate(try await LorenzAtlas().tile(tx: ix.tx, ty: ix.ty))
            let v = try #require(Glow.read(raw, ix: ix.ix, iy: ix.iy))
            print("атлас: \(name) ×\(v) \(String(format: "%.2f", Glow.magnitude(v))) mag")
            #expect(abs(v - want) <= 1e-9 * max(1, want), "\(name)")
            #expect(Glow.level(v) == level, "\(name)")
        }
    }
}
