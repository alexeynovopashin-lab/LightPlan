import Foundation
import Testing
import LightPlanCore
@testable import LightPlanData

/// Сверка с бетой: `Fixtures/location.json` собирает `Tools/parity/location.js`,
/// вырезая правила прямо из `beta/index.html`. Не сошлось — ошибка переноса,
/// пока не доказано обратное.
enum LocationOracle {
    static var url: URL {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        return u.appendingPathComponent("Fixtures/location.json")
    }

    struct Clean: Decodable { let `in`: String; let out: String }
    struct Fixed: Decodable { let lat, lon: Double; let text, key3: String }
    struct Same: Decodable { let a, b: [Double]; let same: Bool }
    struct ZoneKey: Decodable { let lat, lon: Double; let key: String }
    struct TzFor: Decodable { let lon: Double; let tz: Int }
    struct Unique: Decodable { let base: String; let names: [String]; let out: String }
    struct Home: Decodable { let lon: Double; let tz: Int }
    struct File: Decodable {
        let home: Home
        let clean: [Clean]
        let cleanNull: [Clean]
        let fixed: [Fixed]
        let same: [Same]
        let zoneKey: [ZoneKey]
        let tzFor: [TzFor]
        let unique: [Unique]
    }

    static let file: File = {
        do { return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)) }
        catch { fatalError("нет или не читается \(url.path): \(error). Собрать: node Tools/parity/location.js") }
    }()
}

struct LocationOracleTests {
    let f = LocationOracle.file

    @Test func cleanPlaceMatchesBeta() {
        #expect(f.clean.count > 50)
        for c in f.clean { #expect(PlaceNameRules.cleanPlace(c.in) == c.out, "«\(c.in)»") }
        for c in f.cleanNull { #expect(PlaceNameRules.cleanPlace(nil) == c.out) }
    }

    @Test func coordinateTextAndKeyMatchBeta() {
        for x in f.fixed {
            let c = GeoCoordinate(latitude: x.lat, longitude: x.lon)
            #expect(c.text == x.text, "\(x.lat) \(x.lon)")
            #expect(c.nameKey == x.key3, "\(x.lat) \(x.lon)")
        }
    }

    @Test func sameSpotMatchesBeta() {
        #expect(f.same.count > 150)
        for s in f.same {
            let a = GeoCoordinate(latitude: s.a[0], longitude: s.a[1])
            let b = GeoCoordinate(latitude: s.b[0], longitude: s.b[1])
            #expect(a.isSameSpot(as: b) == s.same, "\(s.a) \(s.b)")
        }
    }

    @Test func zoneEstimateMatchesBeta() {
        #expect(ZoneEstimate.homeLongitude == f.home.lon)
        #expect(ZoneEstimate.homeOffsetHours == f.home.tz)
        for z in f.tzFor { #expect(ZoneEstimate.offsetHours(longitude: z.lon) == z.tz, "lon \(z.lon)") }
        for k in f.zoneKey {
            #expect(ZoneEstimate.cacheKey(GeoCoordinate(latitude: k.lat, longitude: k.lon)) == k.key, "\(k.lat) \(k.lon)")
        }
    }

    @Test func uniqueNameMatchesBeta() {
        for u in f.unique { #expect(SavedPoints.uniqueName(u.base, existing: u.names) == u.out, "\(u.base) \(u.names)") }
    }
}
