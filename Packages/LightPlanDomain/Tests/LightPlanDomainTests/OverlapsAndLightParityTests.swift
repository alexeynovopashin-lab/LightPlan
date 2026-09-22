import Foundation
import Testing
import LightPlanCore
@testable import LightPlanDomain

/// Наложения и свет против беты. Наложения — полный перебор взаимных положений
/// двух съёмок, места и дорога, пояса, занятость, порядок по тяжести; свет —
/// пять мест, шесть дней, маршруты с точками второго дня.
struct OverlapsAndLightParityTests {
    let f = DomainOracle.file

    @Test func clashesMatchBeta() {
        var bad: [String] = [], total = 0, said = 0
        var kinds: [String: Int] = [:]
        for sc in f["clashes"].array! {
            let sessions = sc["sessions"].array!.map(DomainOracle.session)
            let blocks = sc["blocks"].array!.map(DomainOracle.block)
            let ctx = ClashContext(zones: DomainOracle.Zones(), appOffsetHours: DomainOracle.appOffset,
                                   travel: DomainOracle.travel, travelThreshold: sc["travelMin"].int!,
                                   eventsLayer: sc["icsLayer"].bool!)
            for (i, want) in sc["clashes"].array!.enumerated() {
                total += 1
                let got = Overlaps.clashes(ofSessionAt: i, sessions: sessions, blocks: blocks, context: ctx)
                let rows = got.map { c -> [String] in
                    let name: String
                    switch c.subject {
                    case .session(let k): name = sessions[k].id
                    case .block(let k): name = blocks[k].note.isEmpty ? "{\"k\":\"blkKind.\(blocks[k].kind.rawValue)\"}" : blocks[k].note
                    }
                    return [c.kind.rawValue, "\(c.weight)", name, text(c.from), text(c.to), text(c.travel), text(c.gap)]
                }
                let wantRows = want.array!.map { w in
                    [w[0].string!, "\(w[1].int!)", w[2].string!, text(w[3].int), text(w[4].int), text(w[5].int), text(w[6].int)]
                }
                said += wantRows.count
                for r in wantRows { kinds[r[0], default: 0] += 1 }
                if rows != wantRows {
                    bad.append("\(sc["tag"].string!) \(sessions[i].id) в \(sessions.map { "\($0.id)@\($0.start)-\($0.endMinute)" }): \(rows) вместо \(wantRows)")
                }
            }
        }
        #expect(total > 3000)
        #expect(bad.isEmpty, "наложения: \(bad.count) расхождений из \(total)\n  \(bad.prefix(5).joined(separator: "\n  "))")
        /* Сетка обязана задевать каждый род наложения, иначе совпадение ничего не доказывает */
        for k in ClashKind.allCases { #expect((kinds[k.rawValue] ?? 0) > 0, "в эталоне нет ни одного «\(k)»") }
        #expect(said > 3000)
    }

    func text(_ v: Int?) -> String { v.map(String.init) ?? "-" }

    /// Вечернее окно по солнцу ядра (итерация 7) с тем же поясом, что у эталона.
    static func evening(_ p: GeoPoint?, _ day: CivilDate) -> EveningLight {
        let at = p ?? DomainOracle.app
        let tz = p == nil ? DomainOracle.appOffset
            : DomainOracle.Zones().utcOffsetHours(latitude: at.latitude, longitude: at.longitude, on: day)
        let sd = SolarDay(date: day, latitude: at.latitude, longitude: at.longitude, utcOffsetHours: tz)
        return EveningLight(goldenB: sd.goldenB, blueB: sd.blueB)
    }

    @Test func lightCaseMatchesBeta() {
        var bad: [String] = [], counts: [String: Int] = [:]
        let rows = f["lights"].array!
        for r in rows {
            let s = DomainOracle.session(r["s"])
            let route = s.kind.isWork ? s.timedRoute : []
            let got = LightCase.of(s, route: route, spots: DomainOracle.spots, studios: DomainOracle.studios,
                                   evening: Self.evening, skyIsBad: DomainOracle.skyIsBad)
            let w = r["light"]
            counts[w["k"].string ?? "null", default: 0] += 1
            let ok: Bool
            switch got {
            case nil: ok = w.isNull
            case .badSky(let p, _)?: ok = w["k"].string == "light.waitedSunset" && p?.name == w["name"].string
            case .inGolden(let p, let win)?:
                ok = w["k"].string == "light.inGolden" && p?.name == w["name"].string && same(win, w["range"])
            case .nearGolden(let p, let win, let gap)?:
                ok = w["k"].string == "light.missGolden" && p?.name == w["name"].string && same(win, w["range"]) && gap == w["gap"].int
            }
            if !ok { bad.append("\(r["s"]): \(String(describing: got)) вместо \(w)") }
        }
        #expect(bad.isEmpty, "свет: \(bad.count) расхождений из \(rows.count)\n  \(bad.prefix(5).joined(separator: "\n  "))")
        for k in ["null", "light.waitedSunset", "light.inGolden", "light.missGolden"] {
            #expect((counts[k] ?? 0) > 20, "в эталоне мало случаев «\(k)»: \(counts[k] ?? 0)")
        }
    }

    func same(_ w: GoldenWindow, _ j: J) -> Bool {
        abs(w.start - j[0].double!) <= 1e-9 && abs(w.end - j[1].double!) <= 1e-9
    }

    /// Ворота правила — солнце в месте съёмки в её день — сверены отдельно: без
    /// них «света нет» могло бы совпасть по другой причине.
    @Test func gateSunMatchesBeta() {
        var bad = 0
        let rows = f["lights"].array!
        for r in rows {
            let s = DomainOracle.session(r["s"])
            let e = Self.evening(Stops.skyPoint(of: s, spots: DomainOracle.spots, studios: DomainOracle.studios), s.day)
            let want = r["sun"]
            func eq(_ a: Double?, _ b: J) -> Bool { a == nil ? b.isNull : (b.double.map { abs($0 - a!) <= 1e-9 } ?? false) }
            if !eq(e.goldenB, want[0]) || !eq(e.blueB, want[1]) { bad += 1 }
        }
        #expect(bad == 0, "вечернее окно разошлось в \(bad) случаях из \(rows.count)")
        #expect(rows.contains { $0["sun"][0].isNull }, "в сетке нет места без золотого часа (полярный день)")
    }
}
