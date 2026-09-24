import Foundation
import Observation
import LightPlanCore

/// Плитка атласа засветки за протоколом: приложение берёт её у атласа
/// Лоренца, тесты — из памяти.
public protocol GlowTileSource: Sendable {
    /// Сжатая плитка `binary_tile_{tx}_{ty}.dat.gz` как есть.
    func tile(tx: Int, ty: Int) async throws -> Data
}

/// Атлас Дэвида Лоренца: статический хостинг, ключа и лимитов нет, `fetchGlow`
/// веба. Сервер отдаёт `application/gzip` без `Content-Encoding` — распаковка
/// своя (`Gzip`).
public struct LorenzAtlas: GlowTileSource {
    public init() {}

    public func tile(tx: Int, ty: Int) async throws -> Data {
        let url = URL(string: "https://djlorenz.github.io/astronomy/binary_tiles/\(Glow.year)/binary_tile_\(tx)_\(ty).dat.gz")!
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// Засветка текущего места (веб `glowVal`). Правила веба:
/// - спрашивается вместе с погодой, после паузы — карту тащат, `moveend`
///   сыплется часто;
/// - то же место с точностью до тысячной градуса — второй раз не спрашиваем;
/// - вне атласа, офлайн, короткая плитка — `nil`: строки засветки просто нет;
/// - ответ про место, откуда уже ушли, ничего не меняет;
/// - в памяти две распакованные плитки (треть мегабайта каждая): своя и
///   соседняя за границей в пяти градусах.
@MainActor
@Observable
public final class GlowStore {
    /// Превышение искусственного свечения зенита над природным фоном.
    public private(set) var ratio: Double?

    private var key = ""
    private var tiles: [(key: String, raw: [UInt8])] = []
    private let source: any GlowTileSource
    private let debounce: Duration
    private var task: Task<Void, Never>?

    public init(place: Place, source: any GlowTileSource, debounce: Duration = .milliseconds(500)) {
        self.source = source
        self.debounce = debounce
        move(to: place)
    }

    /// Дождаться текущего вопроса (тесты).
    public func settled() async { await task?.value }

    public func move(to place: Place) {
        let k = String(format: "%.3f,%.3f", place.latitude, place.longitude)
        guard k != key else { return }
        key = k
        task?.cancel()
        task = Task { [weak self, debounce] in
            do { try await Task.sleep(for: debounce) } catch { return }
            await self?.load(place, key: k)
        }
    }

    private func load(_ place: Place, key k: String) async {
        guard let ix = Glow.index(latitude: place.latitude, longitude: place.longitude) else {
            ratio = nil
            return
        }
        if let raw = tiles.first(where: { $0.key == ix.tile })?.raw {
            ratio = Glow.read(raw, ix: ix.ix, iy: ix.iy)
            return
        }
        do {
            let gz = try await source.tile(tx: ix.tx, ty: ix.ty)
            let raw = try Gzip.inflate(gz)
            guard k == key else { return }                      // место успело смениться
            guard raw.count >= Glow.size else { ratio = nil; return }
            tiles.append((ix.tile, raw))
            if tiles.count > 2 { tiles.removeFirst(tiles.count - 2) }
            ratio = Glow.read(raw, ix: ix.ix, iy: ix.iy)
        } catch {
            if k == key { ratio = nil }
        }
    }
}

/// Распаковка gzip (RFC 1952) поверх raw DEFLATE из Foundation: заголовок с
/// необязательными полями (у плиток атласа есть имя файла), затем поток,
/// затем CRC и длина — они не сверяются: короткая плитка отсекается длиной.
public enum Gzip {
    public enum Failure: Error { case notGzip, truncated }

    public static func inflate(_ data: Data) throws -> [UInt8] {
        let b = [UInt8](data)
        guard b.count >= 18, b[0] == 0x1F, b[1] == 0x8B, b[2] == 8 else { throw Failure.notGzip }
        let flags = b[3]
        var i = 10
        if flags & 0x04 != 0 {                                  // FEXTRA
            guard i + 2 <= b.count else { throw Failure.truncated }
            i += 2 + Int(b[i]) + Int(b[i + 1]) << 8
        }
        if flags & 0x08 != 0 { i = try zeroEnd(b, from: i) }    // FNAME
        if flags & 0x10 != 0 { i = try zeroEnd(b, from: i) }    // FCOMMENT
        if flags & 0x02 != 0 { i += 2 }                         // FHCRC
        guard i < b.count - 8 else { throw Failure.truncated }
        let body = Data(b[i..<(b.count - 8)]) as NSData
        return [UInt8](try body.decompressed(using: .zlib) as Data)
    }

    private static func zeroEnd(_ b: [UInt8], from i: Int) throws -> Int {
        guard let z = b[i...].firstIndex(of: 0) else { throw Failure.truncated }
        return z + 1
    }
}
