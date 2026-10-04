import Testing
import Foundation
@testable import LightPlanMapCanvas

/// 28л.3: ключ CARTO в адресах стиля и сторож первой плитки.
@MainActor
struct MapFallbackGateTests {
    /// Источник, который молчит: не зовёт `tileArrived` — сторож срабатывает ровно один раз.
    @Test func silentSourceTriggersFallbackOnce() async throws {
        var fired = 0
        let gate = MapFallbackGate(timeout: .milliseconds(60)) { fired += 1 }
        gate.start()
        gate.start()
        try await Task.sleep(for: .milliseconds(250))
        #expect(gate.outcome == .silent && fired == 1 && gate.firstTileMs == nil)
        gate.tileArrived()   // плитка после срока — поздно, исход не меняется
        #expect(gate.outcome == .silent)
    }

    @Test func tileInTimeKeepsCarto() async throws {
        var fired = 0
        let gate = MapFallbackGate(timeout: .seconds(2)) { fired += 1 }
        gate.start()
        try await Task.sleep(for: .milliseconds(20))
        gate.tileArrived()
        try await Task.sleep(for: .milliseconds(100))
        #expect(gate.outcome == .arrived && fired == 0)
        #expect((gate.firstTileMs ?? -1) >= 15 && (gate.firstTileMs ?? 9999) < 2000)
    }

    @Test func cancelledGateStaysQuiet() async throws {
        var fired = 0
        let gate = MapFallbackGate(timeout: .milliseconds(40)) { fired += 1 }
        gate.start()
        gate.cancel()
        try await Task.sleep(for: .milliseconds(150))
        #expect(fired == 0 && gate.outcome == .waiting)
    }

    @Test func realTimeoutIsFourSeconds() { #expect(MapFallbackGate.timeout == .seconds(4)) }
}

struct CartoKeyTests {
    private let style = #"""
    {"glyphs":"https://tiles.basemaps.cartocdn.com/fonts/{fontstack}/{range}.pbf",
     "sprite":"https://tiles.basemaps.cartocdn.com/gl/voyager-gl-style/sprite",
     "sources":{"carto":{"type":"vector","tiles":["https://tiles-a.basemaps.cartocdn.com/vectortiles/carto.streets/v1/{z}/{x}/{y}.mvt","https://other.example/{z}.mvt"]}},
     "layers":[]}
    """#

    @Test func keyGoesToTilesAndGlyphsOnly() throws {
        let out = try #require(MapStyle.keyed(Data(style.utf8), key: "AB 12&x"))
        let obj = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        #expect((obj["glyphs"] as? String)?.hasSuffix(".pbf?key=AB%2012%26x") == true)
        #expect(obj["sprite"] as? String == "https://tiles.basemaps.cartocdn.com/gl/voyager-gl-style/sprite")
        let tiles = try #require(((obj["sources"] as? [String: Any])?["carto"] as? [String: Any])?["tiles"] as? [String])
        #expect(tiles[0].hasSuffix("{y}.mvt?key=AB%2012%26x"))
        #expect(tiles[1] == "https://other.example/{z}.mvt")
    }

    @Test func bundledStylesKeepWorkingWithAndWithoutKey() throws {
        for dark in [false, true] {
            let plain = try #require(MapStyle.url(dark: dark, cartoKey: nil))
            #expect(!(try String(contentsOf: plain, encoding: .utf8)).contains("key="))
            let keyed = try #require(MapStyle.url(dark: dark, labels: true, cartoKey: "K1"))
            let text = try String(contentsOf: keyed, encoding: .utf8)
            #expect(text.contains("{y}.mvt?key=K1") && text.contains(".pbf?key=K1"))
        }
    }

    @Test func missingOrEmptyKeyFileMeansNoKeyNoCrash() throws {
        #expect(CartoKey.load(bundle: Bundle(for: Probe.self)) == nil)
        // Своя папка на случай: Bundle запоминает содержимое папки при первом обращении.
        func bundle(_ plist: String?) throws -> (Bundle, URL) {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-carto-\(UUID().uuidString).bundle")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let plist {
                try Data("""
                <?xml version="1.0"?><plist version="1.0"><dict><key>LPCartoKey</key><string>\(plist)</string></dict></plist>
                """.utf8).write(to: dir.appendingPathComponent("carto.plist"))
            }
            return (try #require(Bundle(url: dir)), dir)
        }
        for (plist, want) in [(nil, nil), ("  ", nil), (" k9 ", "k9")] as [(String?, String?)] {
            let (b, dir) = try bundle(plist)
            defer { try? FileManager.default.removeItem(at: dir) }
            #expect(CartoKey.load(bundle: b) == want)
        }
    }

    private final class Probe {}
}
