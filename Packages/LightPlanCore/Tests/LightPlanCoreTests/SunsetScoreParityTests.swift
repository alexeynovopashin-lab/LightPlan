import Testing
import Foundation
@testable import LightPlanCore

/// Сверка закатного балла с вебом (итерация 10, «Готово когда» плана:
/// «sunsetScore совпадает строго»). Эталон — `Fixtures/sunset_score.json`,
/// уже собранный стендом до этой итерации (§ 5.3 плана): три яруса облаков и
/// влажность по 10 %, плюс отдельная сетка с аэрозолем.
struct SunsetScoreParityTests {

    @Test("sunset_score.json: балл по трём ярусам и влажности — строго, целое")
    func gridWithoutAir() throws {
        let f = try ParityFixtures.load("sunset_score.json", as: ParityFixtures.SunsetScoreFile.self)
        let axis = f.axis
        var i = 0
        var failures = 0
        for low in axis {
            for mid in axis {
                for high in axis {
                    for hum in axis {
                        let got = SunsetScore.score(low: Double(low), mid: Double(mid), high: Double(high),
                                                     humidity: Double(hum))
                        let want = f.scores[i]
                        if got != want {
                            failures += 1
                            if failures <= 20 {
                                Issue.record("low \(low) mid \(mid) high \(high) hum \(hum): JS \(want), Swift \(got)")
                            }
                        }
                        i += 1
                    }
                }
            }
        }
        #expect(i == f.scores.count)
        #expect(failures == 0, "\(failures) расхождений с вебом")
    }

    @Test("sunset_score.json: поправка на аэрозоль — строго, целое")
    func airGrid() throws {
        let f = try ParityFixtures.load("sunset_score.json", as: ParityFixtures.SunsetScoreFile.self)
        var failures = 0
        for row in f.air {
            let air = row.aod.map { AirSample(aod: $0, dust: nil) }
            let got = SunsetScore.score(low: Double(row.low), mid: Double(row.mid), high: Double(row.high),
                                         humidity: Double(row.hum), air: air)
            if got != row.score {
                failures += 1
                if failures <= 20 {
                    Issue.record("low \(row.low) mid \(row.mid) high \(row.high) hum \(row.hum) aod \(String(describing: row.aod)): JS \(row.score), Swift \(got)")
                }
            }
        }
        #expect(failures == 0, "\(failures) расхождений с вебом")
    }
}
