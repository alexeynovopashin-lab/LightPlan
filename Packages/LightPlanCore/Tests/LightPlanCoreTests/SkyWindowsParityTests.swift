import Testing
import Foundation
@testable import LightPlanCore

/// Сверка окон неба с вебом (итерация 9а): восход и заход луны, окно
/// Млечного Пути, помеха луны звёздам. Эталон — `Fixtures/sky_windows.json`,
/// посчитанный из живой беты стендом `Tools/parity/`.
///
/// Минуты — строго: округление `moonCross` ровно на половине минуты решает
/// последний бит высоты, и «почти» здесь значит «другая минута». Градусы и
/// доли — `1e-9`, как у солнца и фазы.
struct SkyWindowsParityTests {

    static let tol = 1e-9

    private static func load() throws -> [ParityFixtures.SkyRecord] {
        let f = try ParityFixtures.load("sky_windows.json", as: ParityFixtures.SkyWindowsFile.self)
        return f.grid + f.sweep
    }

    private static func label(_ r: ParityFixtures.SkyRecord) -> String {
        "\(r.date) lat \(r.lat) lon \(r.lon) tz \(r.tz)"
    }

    // MARK: - Восход и заход луны

    @Test("sky_windows.json: дуги луны и ответы moonArc на моменты вокруг них — строго")
    func moonArcs() throws {
        let records = try Self.load()
        var failures = 0, arcsChecked = 0, queries = 0, none = 0
        for r in records {
            let day = MoonDay(date: CivilDate(iso: r.date), latitude: r.lat, longitude: r.lon, utcOffsetHours: r.tz)
            let got = day.arcs.map { [$0.rise, $0.set] }
            if got != r.arcs {
                failures += 1
                if failures <= 20 { Issue.record("\(Self.label(r)): дуги JS \(r.arcs), Swift \(got)") }
                continue
            }
            arcsChecked += r.arcs.count
            for i in 0..<r.qt.count {
                let a = day.arc(at: r.qt[i])
                let wantRise = r.qr[i], wantSet = r.qs[i]
                queries += 1
                if wantRise == nil { none += 1 }
                if a?.rise != wantRise || a?.set != wantSet {
                    failures += 1
                    if failures <= 20 {
                        Issue.record("\(Self.label(r)) t=\(r.qt[i]): JS \(String(describing: wantRise))…\(String(describing: wantSet)), Swift \(String(describing: a?.rise))…\(String(describing: a?.set))")
                    }
                }
            }
        }
        print("moonArc: \(records.count) дней, \(arcsChecked) дуг, \(queries) вопросов (из них «не всходит» — \(none))")
        #expect(failures == 0, "\(failures) расхождений с вебом")
    }

    // MARK: - Окно Млечного Пути

    @Test("sky_windows.json: окно Млечного Пути — оболочка, отрезки, лучшая высота, темнота, помеха луны")
    func milkyWayWindows() throws {
        let records = try Self.load()
        var failures = 0
        var failedLats: [Double: Int] = [:]
        var worstAlt = 0.0, worstAt = ""
        for r in records {
            let w = MilkyWayWindow(date: CivilDate(iso: r.date), latitude: r.lat, longitude: r.lon, utcOffsetHours: r.tz)
            let e = r.win
            let spans = w.spans.map { [$0.from, $0.to] }
            let diff = abs(w.best.altitude - e.bestAlt)
            if diff > worstAlt { worstAlt = diff; worstAt = Self.label(r) }
            /* На самом полюсе высота ядра плоская до 1e-14° (cos φ = 6e-17), и
               «лучшую минуту» там выбирает последний бит библиотечных sin/cos —
               у V8 и у Darwin он разный. Замер 21 сентября 2026: 111 суток на
               −90°, высота сходится на 1.4e-14°, минута — нет. Это плоский
               максимум, а не ошибка переноса (как порог в § 5.2 плана): высоту
               проверяем, минуту — нет. Везде, где максимум острый, строго. */
            let flat = abs(r.lat) == 90
            let minuteOK = flat || w.best.minute == e.bestT
            let same = diff <= Self.tol && minuteOK && w.from == e.from && w.to == e.to
                && spans == e.spans && w.dark == e.dark && w.moonBlocks == e.moonBlocks
            if !same {
                failures += 1
                failedLats[r.lat, default: 0] += 1
                if failures <= 20 {
                    Issue.record("\(Self.label(r)): JS best \(e.bestAlt)@\(String(describing: e.bestT)) \(String(describing: e.from))…\(String(describing: e.to)) \(e.spans) dark \(e.dark) moon \(e.moonBlocks); Swift best \(w.best.altitude)@\(String(describing: w.best.minute)) \(String(describing: w.from))…\(String(describing: w.to)) \(spans) dark \(w.dark) moon \(w.moonBlocks)")
                }
            }
        }
        print("mwWindow: \(records.count) дней, наибольшее расхождение высоты ядра \(worstAlt) (\(worstAt)); расхождения по широтам: \(failedLats.sorted { $0.key < $1.key })")
        #expect(failures == 0, "\(failures) расхождений с вебом")
    }

    // MARK: - Помеха луны

    @Test("sky_windows.json: помеха луны звёздам — доля, освещённость, процент, уровень")
    func moonVsStars() throws {
        let records = try Self.load()
        var failures = 0
        var worstLit = 0.0, worstAt = ""
        for r in records {
            let v = MoonVsStars(date: CivilDate(iso: r.date), latitude: r.lat, longitude: r.lon, utcOffsetHours: r.tz)
            let e = r.vs
            let diff = abs(v.lit - e.lit)
            if diff > worstLit { worstLit = diff; worstAt = Self.label(r) }
            let same = v.dark == e.dark && diff <= Self.tol && v.share == e.share
                && v.percent == e.pct && v.level?.rawValue == e.level
            if !same {
                failures += 1
                if failures <= 20 {
                    Issue.record("\(Self.label(r)): JS dark \(e.dark) lit \(e.lit) share \(e.share) \(String(describing: e.pct))% уровень \(String(describing: e.level)); Swift dark \(v.dark) lit \(v.lit) share \(v.share) \(String(describing: v.percent))% уровень \(String(describing: v.level?.rawValue))")
                }
            }
        }
        print("moonVsStars: \(records.count) дней, наибольшее расхождение освещённости \(worstLit) (\(worstAt))")
        #expect(failures == 0, "\(failures) расхождений с вебом")
    }

    // MARK: - Фикстура покрывает то, что обещала

    /// Сетка, которая ни разу не дошла до края, ничего не доказывает. Здесь —
    /// что в ней есть все случаи, названные в плане: луна не всходит, всходит
    /// и заходит, две и три дуги, окно с дырой внутри оболочки, помеха луны,
    /// уровни 0/1/2, дни без темноты, полюса.
    @Test("sky_windows.json: в сетке есть каждый край — полюса, дни без темноты, дыры окна, все три уровня помехи")
    func fixtureCoversEdges() throws {
        let records = try Self.load()
        let byArcCount = Dictionary(grouping: records, by: { $0.arcs.count })
        #expect((byArcCount[0]?.count ?? 0) > 0, "нет дней без единой дуги")
        #expect((byArcCount[1]?.count ?? 0) > 0)
        #expect((byArcCount[2]?.count ?? 0) > 0)
        #expect((byArcCount[3]?.count ?? 0) > 0, "нет дней с тремя дугами в окне")

        for pole in [-90.0, 90.0] {
            #expect(records.contains { $0.lat == pole && $0.arcs.isEmpty }, "нет ответа «не всходит» на \(pole)°")
            #expect(records.contains { $0.lat == pole && !$0.win.dark }, "нет полярного дня без тёмной части на \(pole)°")
        }
        #expect(records.contains { !$0.win.dark }, "нет дней без астрономической темноты")
        #expect(records.contains { $0.win.dark && $0.win.spans.isEmpty }, "нет тёмных суток с пустым окном")
        #expect(records.contains { $0.win.spans.count >= 2 }, "нет окна с дырой внутри оболочки")
        #expect(records.contains { $0.win.moonBlocks }, "луна нигде не закрыла окно")
        #expect(records.contains { $0.win.dark && !$0.win.moonBlocks && !$0.win.spans.isEmpty })
        for level in 0...2 {
            #expect(records.contains { $0.vs.level == level }, "нет помехи уровня \(level)")
        }
        #expect(records.contains { $0.vs.dark == false && $0.vs.pct == nil && $0.vs.level == nil })
        // Дробный пояс и антимеридиан — те же места, что у луны: там ломается Int.
        #expect(records.contains { $0.tz == 5.75 } && records.contains { $0.tz == 12.75 })
    }

    // MARK: - Округление веба

    @Test("Math.round веба: половина уходит вверх, на отрицательных минутах тоже")
    func jsRounding() {
        // Swift-овское `.rounded()` увело бы `-2.5` в `-3` и `-0.5` в `-1`.
        #expect(Sky.jsRound(2.5) == 3)
        #expect(Sky.jsRound(-2.5) == -2)
        #expect(Sky.jsRound(-0.5) == 0)
        #expect(Sky.jsRound(0.49999999999999994) == 0)
        #expect(Sky.jsRound(-0.6) == -1)
        #expect(Sky.jsRound(1439.5) == 1440)
    }
}
