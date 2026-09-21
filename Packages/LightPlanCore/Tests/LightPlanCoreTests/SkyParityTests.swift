import Testing
import Foundation
import LightPlanCore

/// Сверка луны и Млечного Пути с вебом (итерация 9). Эталон — `Fixtures/`,
/// посчитанные из живой беты стендом `Tools/parity/`. Допуски — те, что стоят в
/// `meta.tolerance` фикстур: градусы и километры `1e-7` (луна), `1e-9`
/// (Млечный Путь, фаза), имена фаз — строго. Точность самой луны не
/// улучшается: веб заявляет её низкой, и «исправить» её значило бы изменить
/// продукт.
struct SkyParityTests {

    static let moonTol = 1e-7
    static let tightTol = 1e-9

    /// Наибольшее расхождение по полю и где оно случилось: в отчёт итерации.
    struct Worst {
        var value = 0.0
        var where_ = ""
        mutating func note(_ diff: Double, _ label: @autoclosure () -> String) {
            if diff > value { value = diff; where_ = label() }
        }
    }

    /// Азимут замкнут в круг: 359.9999999° и 0.0000001° — соседи.
    static func circular(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    // MARK: - Луна

    @Test("moon.json: положение, расстояние, доля диска, фаза и её имя — ряды и «страшные» минуты")
    func moonFixtures() throws {
        let f = try ParityFixtures.load("moon.json", as: ParityFixtures.MoonFile.self)
        var worst: [String: Worst] = [:]
        var failures = 0
        var checked = 0

        func check(_ name: String, _ want: Double, _ got: Double, tol: Double, _ label: @autoclosure () -> String) {
            let diff = name == "az" ? Self.circular(want, got) : abs(want - got)
            worst[name, default: Worst()].note(diff, label())
            if !(diff <= tol) {
                failures += 1
                if failures <= 20 { Issue.record("\(name) \(label()): JS \(want), Swift \(got), разница \(diff)") }
            }
        }

        for (kind, list) in [("series", f.series), ("probes", f.probes)] {
            for s in list {
                let date = CivilDate(iso: s.date)
                for i in 0..<s.t.count {
                    let m = MoonSample(date: date, minutes: s.t[i], latitude: s.lat, longitude: s.lon, utcOffsetHours: s.tz)
                    let label = "\(kind) \(s.date) t=\(s.t[i]) lat \(s.lat) lon \(s.lon) tz \(s.tz)"
                    check("alt", s.alt[i], m.altitude, tol: Self.moonTol, label)
                    check("az", s.az[i], m.azimuth, tol: Self.moonTol, label)
                    check("dist", s.dist[i], m.distance, tol: Self.moonTol, label)
                    check("frac", s.frac[i], m.phase.fraction, tol: Self.tightTol, label)
                    check("cycle", s.phase[i], m.phase.cycle, tol: Self.tightTol, label)
                    if s.name[i] != m.phase.name.rawValue {
                        failures += 1
                        if failures <= 20 { Issue.record("\(label): имя фазы JS \(s.name[i]), Swift \(m.phase.name.rawValue)") }
                    }
                    checked += 1
                }
            }
        }
        let report = worst.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.value) (\($0.value.where_))" }
        print("moon: \(checked) точек, наибольшее расхождение — \(report.joined(separator: "; "))")
        #expect(checked == f.meta.count - f.phaseSweep.t.count)
        #expect(failures == 0, "\(failures) расхождений с вебом")
    }

    @Test("moon.json: фаза по трём годам, четыре отсчёта в сутки, имена строго")
    func phaseSweep() throws {
        let w = try ParityFixtures.load("moon.json", as: ParityFixtures.MoonFile.self).phaseSweep
        var worstFrac = 0.0, worstCycle = 0.0, nameFailures = 0
        for i in 0..<w.t.count {
            let p = MoonPhase(date: CivilDate(year: w.y[i], month: w.m[i], day: w.d[i]), minutes: w.t[i], utcOffsetHours: w.tz)
            worstFrac = max(worstFrac, abs(p.fraction - w.frac[i]))
            worstCycle = max(worstCycle, abs(p.cycle - w.phase[i]))
            if p.name.rawValue != w.codes[w.code[i]] {
                nameFailures += 1
                if nameFailures <= 10 { Issue.record("\(w.y[i])-\(w.m[i])-\(w.d[i]) t=\(w.t[i]): JS \(w.codes[w.code[i]]), Swift \(p.name.rawValue)") }
            }
        }
        print("phase: \(w.t.count) отсчётов, доля диска \(worstFrac), цикл \(worstCycle), имён не совпало \(nameFailures)")
        #expect(worstFrac <= Self.tightTol)
        #expect(worstCycle <= Self.tightTol)
        #expect(nameFailures == 0)
    }

    /// Границы имён фаз — физика продукта, «причёсывать» их нельзя. Ровно на
    /// границе фаза уже следующая: сравнение строгое «меньше», как в вебе.
    @Test("Границы фаз луны: 0.02 / 0.24 / 0.28 / 0.48 / 0.52 / 0.72 / 0.76 / 0.98 / 1.01")
    func phaseBounds() {
        let cases: [(Double, MoonPhaseName)] = [
            (0, .new), (0.0199, .new), (0.02, .waxingCrescent),
            (0.2399, .waxingCrescent), (0.24, .firstQuarter),
            (0.2799, .firstQuarter), (0.28, .waxingGibbous),
            (0.4799, .waxingGibbous), (0.48, .full),
            (0.5199, .full), (0.52, .waningGibbous),
            (0.7199, .waningGibbous), (0.72, .lastQuarter),
            (0.7599, .lastQuarter), (0.76, .waningCrescent),
            (0.9799, .waningCrescent), (0.98, .new),
            (1.0099, .new), (1.01, .new), (7, .new), (.nan, .new),
        ]
        for (p, want) in cases {
            #expect(MoonPhaseName(phase: p) == want, "фаза \(p): ждали \(want), вышло \(MoonPhaseName(phase: p))")
        }
        #expect(MoonPhaseName.allCases.count == 8)
    }

    /// Дробные миллисекунды: веб собирает момент через `new Date(мс)`, и та
    /// обрезает их к нулю. Луна уходит на 4·10⁻⁶° за миллисекунду — больше
    /// допуска, — поэтому обрезка входит в паритет. Тест сам по себе падал
    /// бы без обрезки; см. отчёт итерации 9 (проверено на старом коде).
    @Test("Дробные миллисекунды обрезаются, как в new Date(мс)")
    func fractionalMillisecondsAreTruncated() {
        let date = CivilDate(year: 2026, month: 3, day: 20)
        // 0.5 мин = 30 000 мс ровно; 0.5 + 0.00001 мин = 30 000.6 мс → 30 000.
        let whole = Sky.days(date: date, minutes: 0.5, utcOffsetHours: 0)
        let frac = Sky.days(date: date, minutes: 0.5 + 0.00001, utcOffsetHours: 0)
        #expect(frac == whole, "0.6 мс сверх целых обязано отбрасываться")
        // Абсолютный момент положителен, и «к нулю» значит «вниз»: −30 000.6 мс от
        // полуночи — это 30 001 мс до неё, а не 30 000.
        let before = Sky.days(date: date, minutes: -0.5, utcOffsetHours: 0)
        let beforeFrac = Sky.days(date: date, minutes: -0.5 - 0.00001, utcOffsetHours: 0)
        #expect(beforeFrac < before)
    }

    @Test("Тонкий вход с зоной месте равен ядру с тем же смещением")
    func thinInputMatchesCore() throws {
        let moscow = try #require(ZoneID("Europe/Moscow"))
        let place = Place(latitude: 55.75, longitude: 37.62, zone: moscow)
        for (m, minutes) in [(3, 0.0), (6, 725.5), (9, 1439.0), (12, -30.0)] {
            let date = CivilDate(year: 2026, month: m, day: 15)
            let thin = MoonSample(date: date, minutes: minutes, place: place)
            let core = MoonSample(date: date, minutes: minutes, latitude: 55.75, longitude: 37.62, utcOffsetHours: 3)
            #expect(thin == core)
            #expect(MoonPhase(date: date, minutes: minutes, zone: moscow) == core.phase)
        }
    }

    /// Луна на ленте ищет восход перебором: сотни отсчётов на каждое движение
    /// пальца. Тест печатает число; порог только в релизе — в debug оптимизации
    /// нет: `swift test -c release --filter SkyParityTests/speed`.
    @Test("10 000 отсчётов луны — быстрее кадра на 120 Гц")
    func speed() {
        let n = 10_000
        let frame = 1000.0 / 120
        var sink = 0.0
        let date = CivilDate(year: 2026, month: 6, day: 21)
        let clock = ContinuousClock()
        let position = clock.measure {
            for i in 0..<n {
                let m = MoonSample(date: date, minutes: Double(i % 2900) - 720, latitude: 55.03, longitude: 83, utcOffsetHours: 7)
                sink += m.altitude
            }
        }
        let withPhase = clock.measure {
            for i in 0..<n {
                let m = MoonSample(date: date, minutes: Double(i % 2900) - 720, latitude: 55.03, longitude: 83, utcOffsetHours: 7)
                sink += m.altitude + m.phase.fraction
            }
        }
        func ms(_ d: Duration) -> Double {
            Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        }
        print("speed: 10000 MoonSample, положение \(ms(position)) мс, с фазой \(ms(withPhase)) мс (кадр 120 Гц: \(frame) мс), контрольная сумма \(sink)")
        #if !DEBUG
        #expect(ms(position) < frame, "положение: \(ms(position)) мс, кадр \(frame) мс")
        #endif
    }

    // MARK: - Млечный Путь

    @Test("milkyway.json: полоса и поворот ядра над головой")
    func milkyWayFixtures() throws {
        let f = try ParityFixtures.load("milkyway.json", as: ParityFixtures.MilkyWayFile.self)
        #expect(MilkyWay.band.count == f.band.count)
        var worstBand = 0.0, worstAlt = 0.0, worstAz = 0.0
        for (i, row) in f.band.enumerated() {
            let p = MilkyWay.band[i]
            #expect(p.longitude == row[0], "l строки \(i)")
            worstBand = max(worstBand, abs(p.halfWidth - row[1]), abs(p.center.ra - row[2]), abs(p.center.dec - row[3]))
        }
        #expect(MilkyWay.core.ra == f.core["ra"] && MilkyWay.core.dec == f.core["dec"])
        for c in f.coreAltAz {
            let p = MilkyWay.corePosition(date: CivilDate(iso: c.date), minutes: Double(c.t),
                latitude: c.lat, longitude: c.lon, utcOffsetHours: c.tz)
            worstAlt = max(worstAlt, abs(p.altitude - c.alt))
            worstAz = max(worstAz, Self.circular(p.azimuth, c.az))
        }
        print("milkyway: полоса \(f.band.count) точек, расхождение \(worstBand); ядро \(f.coreAltAz.count) точек, высота \(worstAlt), азимут \(worstAz)")
        #expect(worstBand <= Self.tightTol)
        #expect(worstAlt <= Self.tightTol)
        #expect(worstAz <= Self.tightTol)
    }

    /// Контрольные точки из комментария к `galToEq` в вебе — не из его кода, а из
    /// астрономии: центр Галактики (Sgr A*) и антицентр.
    @Test("Млечный Путь: l=0 → 266.405 / −28.936, l=180 → 86.405 / +28.936")
    func checkpoints() {
        let deg = 180.0 / Double.pi
        func inDegrees(_ l: Double) -> (ra: Double, dec: Double) {
            let p = MilkyWay.equatorial(galacticLongitude: l, galacticLatitude: 0)
            return ((p.ra * deg).truncatingRemainder(dividingBy: 360), p.dec * deg)
        }
        let c = inDegrees(0), a = inDegrees(180)
        #expect(abs(c.ra - 266.405) < 1e-3 && abs(c.dec + 28.936) < 1e-3)
        #expect(abs(a.ra - 86.405) < 1e-3 && abs(a.dec - 28.936) < 1e-3)
    }

    @Test("Полуширина полосы: у ядра 11.5° (балдж расширен на 15 %), у антицентра 3°")
    func halfWidth() {
        #expect(MilkyWay.halfWidth(galacticLongitude: 0) == 11.5)
        #expect(MilkyWay.halfWidth(galacticLongitude: 180) == 3)
        #expect(MilkyWay.halfWidth(galacticLongitude: 360) == 11.5)
        #expect(MilkyWay.band.first?.longitude == 0 && MilkyWay.band.last?.longitude == 0)
        #expect(MilkyWay.band.count == 121)
    }
}
