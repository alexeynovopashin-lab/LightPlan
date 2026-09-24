import Foundation
import Testing
@testable import LightPlanCore

/// Засветка против веба (итерация 20б): ячейка атласа, чтение знаковых
/// приращений, развёртка сжатия, ступени и звёздные величины. Плитка
/// синтетическая — та же формула, что в `Tools/parity/generate.js`.
struct GlowParityTests {
    struct Cell: Decodable {
        let lat: Double
        let lon: Double
        let at: [Int]?
        let v: Double?
    }
    struct Step: Decodable {
        let r: Double
        let level: String
        let mag: Double
    }
    struct File: Decodable {
        let cells: [Cell]
        let scale: [Step]
    }

    static func tile() -> [UInt8] {
        (0..<Glow.size).map { i in
            if i == 0 { return 1 }
            let h = UInt32(truncatingIfNeeded: i + 1) &* 2654435761
            return UInt8(truncatingIfNeeded: Int(h >> 24) % 21 - 10)
        }
    }

    @Test("glow.json: ячейка и значение точка в точку")
    func cells() throws {
        let f = try ParityFixtures.load("glow.json", as: File.self)
        let raw = Self.tile()
        var cellMiss = 0, worst = 0.0, inside = 0
        for c in f.cells {
            let ix = Glow.index(latitude: c.lat, longitude: c.lon)
            let got = ix.map { [$0.tx, $0.ty, $0.ix, $0.iy] }
            if got != c.at { cellMiss += 1; continue }
            guard let ix, let want = c.v else { continue }
            inside += 1
            let v = try #require(Glow.read(raw, ix: ix.ix, iy: ix.iy))
            worst = max(worst, want == 0 ? abs(v) : abs(v - want) / want)
        }
        print("glow: \(f.cells.count) точек, в атласе \(inside), ячейка не та \(cellMiss), значение \(worst)")
        #expect(cellMiss == 0)
        #expect(worst <= 1e-12)
    }

    @Test("glow.json: ступени и mag/arcsec²")
    func scale() throws {
        let f = try ParityFixtures.load("glow.json", as: File.self)
        for s in f.scale {
            #expect(Glow.level(s.r)?.rawValue == s.level, "ratio \(s.r)")
            #expect(abs(Glow.magnitude(s.r) - s.mag) <= 1e-12, "ratio \(s.r)")
        }
        #expect(Glow.level(nil) == nil)
    }

    @Test("Плитка короче сетки не читается")
    func shortTile() {
        #expect(Glow.read([UInt8](repeating: 0, count: Glow.size - 1), ix: 1, iy: 1) == nil)
    }
}
