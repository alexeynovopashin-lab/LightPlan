import Testing
import Foundation
import LightPlanCore

/// Сверка солнечного движка с вебом (итерация 7). Эталон — `Fixtures/`,
/// посчитанные из живой беты стендом `Tools/parity/`. Допуски § 5.2 плана:
/// времена событий `1e-6` минуты, градусы `1e-9`, полярность и «нет события» —
/// строго. Допуск не двигаем: расхождение — ошибка переноса, пока не доказано
/// иное.
struct SolarParityTests {

    static let timeTol = 1e-6
    static let degTol = 1e-9

    /// Наибольшее расхождение по полю и где оно случилось: в отчёт итерации.
    struct Worst {
        var value = 0.0
        var where_ = ""
        mutating func note(_ diff: Double, _ label: @autoclosure () -> String) {
            if diff > value { value = diff; where_ = label() }
        }
    }

    // MARK: - Сутки целиком

    @Test("solar_day.json: все сутки, все поля")
    func dayFixtures() throws {
        let f = try ParityFixtures.load("solar_day.json", as: ParityFixtures.SolarDayFile.self)
        var worst: [String: Worst] = [:]
        var failures = 0

        func time(_ name: String, _ want: Double?, _ got: Double?, _ d: ParityFixtures.SolarDay) {
            let label = "\(name) \(d.date) lat \(d.lat) lon \(d.lon) tz \(d.tz)"
            switch (want, got) {
            case (nil, nil): return
            case (let w?, let g?):
                let diff = abs(w - g)
                worst[name, default: Worst()].note(diff, label)
                if !(diff <= Self.timeTol) {
                    failures += 1
                    if failures <= 20 { Issue.record("\(label): JS \(w), Swift \(g), разница \(diff)") }
                }
            default:
                failures += 1
                if failures <= 20 { Issue.record("\(label): JS \(String(describing: want)), Swift \(String(describing: got)) — null не совпал") }
            }
        }
        func degrees(_ name: String, _ want: Double, _ got: Double, _ d: ParityFixtures.SolarDay) {
            let label = "\(name) \(d.date) lat \(d.lat) lon \(d.lon) tz \(d.tz)"
            let diff = abs(want - got)
            worst[name, default: Worst()].note(diff, label)
            if !(diff <= Self.degTol) {
                failures += 1
                if failures <= 20 { Issue.record("\(label): JS \(want), Swift \(got), разница \(diff)") }
            }
        }

        for d in f.days {
            let s = SolarDay(date: CivilDate(iso: d.date), latitude: d.lat, longitude: d.lon, utcOffsetHours: d.tz)
            degrees("decl", d.decl, s.declination, d)
            time("solarNoon", d.solarNoon, s.solarNoon, d)
            time("mint", d.mint, s.mint, d)
            time("maxt", d.maxt, s.maxt, d)
            time("rise", d.rise, s.rise, d)
            time("set", d.set, s.set, d)
            time("goldA", d.goldA, s.goldenA, d); time("goldB", d.goldB, s.goldenB, d)
            time("blueA", d.blueA, s.blueA, d);   time("blueB", d.blueB, s.blueB, d)
            time("civA", d.civA, s.civilA, d);    time("civB", d.civB, s.civilB, d)
            time("nauA", d.nauA, s.nauticalA, d); time("nauB", d.nauB, s.nauticalB, d)
            time("astA", d.astA, s.astroA, d);    time("astB", d.astB, s.astroB, d)
            degrees("maxElev", d.maxElev, s.maxElevation, d)
            time("arcA", d.arcA, s.arcA, d)
            time("arcB", d.arcB, s.arcB, d)
            if d.polar != s.polar.rawValue {
                failures += 1
                if failures <= 20 { Issue.record("polar \(d.date) lat \(d.lat) lon \(d.lon): JS \(d.polar), Swift \(s.polar.rawValue)") }
            }
        }

        #expect(failures == 0, "расхождений: \(failures)")
        print("solar_day: \(f.days.count) дней")
        for (k, w) in worst.sorted(by: { $0.key < $1.key }) {
            print("  наибольшее расхождение \(k): \(w.value)  [\(w.where_)]")
        }
    }

    // MARK: - Минуты суток

    @Test("solar_sample.json: высота, азимут и тень по всем рядам")
    func sampleFixtures() throws {
        let f = try ParityFixtures.load("solar_sample.json", as: ParityFixtures.SolarSampleFile.self)
        var worstElev = Worst(), worstAz = Worst(), worstShadow = Worst()
        var failures = 0, points = 0, shadowNulls = 0

        for s in f.series {
            let day = SolarDay(date: CivilDate(iso: s.date), latitude: s.lat, longitude: s.lon, utcOffsetHours: s.tz)
            for i in s.t.indices {
                points += 1
                let t = s.t[i]
                let label = "\(s.date) lat \(s.lat) lon \(s.lon) tz \(s.tz) t \(t)"

                let e = day.elevation(at: t)
                let de = abs(e - s.elev[i])
                worstElev.note(de, label)
                if !(de <= Self.degTol) {
                    failures += 1
                    if failures <= 20 { Issue.record("elev \(label): JS \(s.elev[i]), Swift \(e), разница \(de)") }
                }

                /* Азимут — угол на круге: 359.9999999999 и 0.0000000001 — одно
                   и то же направление, поэтому расстояние берётся по кругу. */
                let a = day.azimuth(at: t)
                var da = abs(a - s.az[i])
                da = min(da, 360 - da)
                worstAz.note(da, label)
                if !(da <= Self.degTol) {
                    failures += 1
                    if failures <= 20 { Issue.record("az \(label): JS \(s.az[i]), Swift \(a), разница \(da)") }
                }

                switch (s.shadow[i], day.shadowRatio(at: t)) {
                case (nil, nil): shadowNulls += 1
                case (let w?, let g?):
                    let ds = abs(w - g)
                    worstShadow.note(ds, label)
                    if !(ds <= Self.degTol) {
                        failures += 1
                        if failures <= 20 { Issue.record("shadow \(label): JS \(w), Swift \(g), разница \(ds)") }
                    }
                default:
                    failures += 1
                    if failures <= 20 {
                        Issue.record("shadow \(label): JS \(String(describing: s.shadow[i])), Swift \(String(describing: day.shadowRatio(at: t))) — null не совпал")
                    }
                }
            }
        }

        #expect(failures == 0, "расхождений: \(failures)")
        #expect(points == f.meta.count)
        print("solar_sample: \(f.series.count) рядов, \(points) точек, теней null: \(shadowNulls)")
        print("  наибольшее расхождение elev:   \(worstElev.value)  [\(worstElev.where_)]")
        print("  наибольшее расхождение az:     \(worstAz.value)  [\(worstAz.where_)]")
        print("  наибольшее расхождение shadow: \(worstShadow.value)  [\(worstShadow.where_)]")
    }

    // MARK: - Края, названные в плане

    @Test("В сетке есть края: 66.6°, оба полюса, 29 февраля, дни перевода часов")
    func gridHasTheEdges() throws {
        let days = try ParityFixtures.load("solar_day.json", as: ParityFixtures.SolarDayFile.self).days
        let lats = Set(days.map(\.lat)), dates = Set(days.map(\.date))
        for lat in [66.6, -66.6, 90, -90] { #expect(lats.contains(lat), "нет широты \(lat)") }
        for d in ["2028-02-29", "2026-03-08", "2026-03-29", "2026-10-25", "2026-11-01"] {
            #expect(dates.contains(d), "нет даты \(d)")
        }
        // Дробные пояса дошли до Swift дробными.
        #expect(days.contains { $0.tz == 5.75 } && days.contains { $0.tz == 12.75 })
    }

    @Test("Полюса: обе полярности видны, события нет ни у одной, дуга — вся шкала")
    func poles() throws {
        let days = try ParityFixtures.load("solar_day.json", as: ParityFixtures.SolarDayFile.self).days
        var seen: Set<Int> = []
        for d in days where abs(d.lat) == 90 {
            let s = SolarDay(date: CivilDate(iso: d.date), latitude: d.lat, longitude: d.lon, utcOffsetHours: d.tz)
            #expect(s.rise == nil && s.set == nil)
            #expect(s.arcA == s.mint && s.arcB == s.maxt)
            seen.insert(s.polar.rawValue)
        }
        #expect(seen == [1, -1], "на полюсах видны полярности \(seen)")
    }

    @Test("Номер дня: 1 января — 1, високосные и невисокосные края")
    func ordinal() {
        #expect(CivilDate(year: 2026, month: 1, day: 1).ordinal == 1)
        #expect(CivilDate(year: 2026, month: 12, day: 31).ordinal == 365)
        #expect(CivilDate(year: 2028, month: 2, day: 29).ordinal == 60)
        #expect(CivilDate(year: 2028, month: 12, day: 31).ordinal == 366)
        #expect(CivilDate(year: 1900, month: 3, day: 1).ordinal == 60)   // 1900 не високосный
        #expect(CivilDate(year: 2000, month: 3, day: 1).ordinal == 61)   // 2000 високосный
    }

    // MARK: - Пояс на дату

    /// Мартовский перевод в Берлине — 29 марта 2026 в 01:00 UTC, осенний —
    /// 25 октября. Веб берёт смещение на начало дня (`tzAt(lat, lon, day)`, тот
    /// же `Date`, что уходит в `computeSun(day)`), поэтому в день перевода
    /// действует старое смещение, а со следующего дня — новое.
    @Test("Берлин в дни перевода часов: смещение на дату, как у веба")
    func berlinAcrossDST() throws {
        let berlin = try #require(ZoneID("Europe/Berlin"))
        let place = Place(latitude: 52.52, longitude: 13.405, zone: berlin)
        let cases: [(CivilDate, Double)] = [
            (CivilDate(year: 2026, month: 3, day: 28), 1),
            (CivilDate(year: 2026, month: 3, day: 29), 1),   // день перевода: полночь ещё зимняя
            (CivilDate(year: 2026, month: 3, day: 30), 2),
            (CivilDate(year: 2026, month: 10, day: 24), 2),
            (CivilDate(year: 2026, month: 10, day: 25), 2),  // день перевода: полночь ещё летняя
            (CivilDate(year: 2026, month: 10, day: 26), 1),
        ]
        for (date, offset) in cases {
            #expect(berlin.utcOffsetHours(on: date) == offset, "\(date): смещение не \(offset)")
            let thin = SolarDay(date: date, place: place)
            let core = SolarDay(date: date, latitude: 52.52, longitude: 13.405, utcOffsetHours: offset)
            #expect(thin == core, "\(date): тонкий вход разошёлся с ядром при смещении \(offset)")
        }
        // Смещение действительно меняет день: полдень 29 и 30 марта разделяет ~час.
        let before = SolarDay(date: cases[1].0, place: place).solarNoon
        let after = SolarDay(date: cases[2].0, place: place).solarNoon
        #expect(abs((after - before) - 60) < 2,"перевод часов не сдвинул полдень на час: \(before) → \(after)")
    }

    @Test("Дробные пояса не округляются: Катманду 5.75, Чатем 12.75 и 13.75")
    func fractionalZones() throws {
        #expect(try #require(ZoneID("Asia/Kathmandu")).utcOffsetHours(on: CivilDate(year: 2026, month: 6, day: 21)) == 5.75)
        let chatham = try #require(ZoneID("Pacific/Chatham"))
        #expect(chatham.utcOffsetHours(on: CivilDate(year: 2026, month: 6, day: 21)) == 12.75)
        #expect(chatham.utcOffsetHours(on: CivilDate(year: 2026, month: 1, day: 10)) == 13.75)
    }

    @Test("Незнакомая зона — nil, а не молчаливый UTC")
    func unknownZone() {
        #expect(ZoneID("Mars/Olympus") == nil)
    }

    // MARK: - Скорость

    /// Купол пересчитывается на каждое движение пальца, поэтому 10 000 суток
    /// должны строиться быстрее кадра: iPhone 15 Pro и Pro Max — 120 Гц, 8.3 мс.
    /// В отладочной сборке число ничего не значит (нет оптимизации), потому
    /// проверка порога включена только в релизе:
    /// `swift test -c release --filter SolarParityTests/speed`.
    @Test("10 000 SolarDay строятся быстрее кадра на 120 Гц")
    func speed() throws {
        let n = 10_000
        let zone = try #require(ZoneID("Europe/Moscow"))
        let frame = 1000.0 / 120

        // Входы разные, чтобы компилятор не вынес расчёт из цикла.
        func dates(_ i: Int) -> CivilDate { CivilDate(year: 2026, month: 1 + i % 12, day: 1 + i % 28) }
        func lat(_ i: Int) -> Double { -85 + Double(i % 170) }

        var sink = 0.0
        let clock = ContinuousClock()

        // Ядро: то, чем купол пользуется, когда пояс уже известен.
        let core = clock.measure {
            for i in 0..<n {
                let s = SolarDay(date: dates(i), latitude: lat(i), longitude: Double(i % 360) - 180, utcOffsetHours: 3)
                sink += s.solarNoon + (s.rise ?? 0)
            }
        }
        // Тонкий вход: с зоной, смещение спрашивается на каждую дату.
        let thin = clock.measure {
            for i in 0..<n {
                let s = SolarDay(date: dates(i), place: Place(latitude: lat(i), longitude: 37, zone: zone))
                sink += s.solarNoon + (s.rise ?? 0)
            }
        }

        func ms(_ d: Duration) -> Double {
            Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        }
        print("speed: 10000 SolarDay, ядро \(ms(core)) мс, с зоной места \(ms(thin)) мс (кадр 120 Гц: \(frame) мс), контрольная сумма \(sink)")
        #if !DEBUG
        #expect(ms(core) < frame, "ядро: \(ms(core)) мс, кадр \(frame) мс")
        #endif
    }
}

extension CivilDate {
    /// Из строки фикстуры `YYYY-MM-DD`.
    init(iso: String) {
        let p = iso.split(separator: "-").map { Int($0)! }
        self.init(year: p[0], month: p[1], day: p[2])
    }
}
