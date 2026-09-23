import Testing
@testable import LightPlanCore

/// Облако точек прибора карты против веба (итерация 20а): те же точки неба,
/// того же калибра, с тем же порогом угасания, в том же порядке.
struct MilkyWayDustParityTests {
    struct File: Decodable {
        let haze: Double
        let points: [[Double]]
    }

    @Test("mw_dust.json: облако точка в точку")
    func dust() throws {
        let f = try ParityFixtures.load("mw_dust.json", as: File.self)
        #expect(MilkyWayDust.haze == f.haze)
        #expect(MilkyWayDust.points.count == f.points.count)
        var worst = 0.0, tiers = 0, fades = 0
        for (i, row) in f.points.enumerated() where i < MilkyWayDust.points.count {
            let p = MilkyWayDust.points[i]
            worst = max(worst, abs(p.equatorial.ra - row[0]), abs(p.equatorial.dec - row[1]))
            if p.tier != Int(row[2]) { tiers += 1 }
            if p.fade != row[3] { fades += 1 }
        }
        print("mw_dust: \(f.points.count) точек, координаты \(worst), ярус не тот \(tiers), порог не тот \(fades)")
        #expect(worst <= 1e-12)
        #expect(tiers == 0)
        #expect(fades == 0)
    }

    @Test("Точка в дымке гаснет по своему порогу, под горизонтом — всегда")
    func visibility() {
        let p = MilkyWayDust.Point(equatorial: .init(ra: 0, dec: 0), tier: 2, fade: 0.5)
        #expect(!MilkyWayDust.visible(p, altitude: -0.1))
        #expect(!MilkyWayDust.visible(p, altitude: 3.9))
        #expect(MilkyWayDust.visible(p, altitude: 4.1))
        #expect(MilkyWayDust.visible(p, altitude: 30))
    }
}
