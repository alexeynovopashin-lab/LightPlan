import Testing
import Foundation
@testable import LightPlanCore

/// Солнце экранов приложения (`SolarDay(.iau)`, шаг 29.8в.25) против JPL Horizons: пять мест × двенадцать дат 2026 года
/// (Томск, Москва, Тромсё, Кейптаун, Гонолулу), 659 событий света и 49 положений Солнца в сутках.
/// Эталон — `Fixtures/sun_horizons.json`, собирается `python3 Tools/sun_horizons_ref.py`.
///
/// **Почему тут два допуска, а в `SolarParityTests` — бит в бит.** Стенд паритета сверяет натив с вебом: порт формул
/// NOAA (склонение и уравнение времени раз в сутки), допуски 1e-6 минуты и 1e-9 градуса. Эта модель — `.web` — осталась
/// как была и держит стенд. Но сам веб ошибается против Horizons (замер ниже: до 0,55° и до 5 минут у событий, до 23
/// у Тромсё), и «Свет» с «Картой» показывали закат на две минуты позже слоя AR. Экраны приложения идут по `.iau` —
/// тому же Солнцу, что рисует AR; оно **точнее веба**, поэтому с вебом не совпадает, и совпадать не должно. Его
/// проверяет не веб, а Horizons — этот файл.
struct SolarDayExactTests {

    struct File: Decodable {
        struct Sample: Decodable { let minute: Double, az: Double, el: Double }
        struct Case: Decodable {
            let place: String, date: String
            let latitude: Double, longitude: Double
            let utcOffsetHours: Double
            let events: [String: Double?]
            let samples: [Sample]
        }
        let cases: [Case]
    }

    static let loaded: Result<File, Error> = Result { try ParityFixtures.load("sun_horizons.json", as: File.self) }
    static var file: File { get throws { try loaded.get() } }

    /// Допуски (проверено измерением, см. `report`): события без Тромсё — 0,12 минуты (измерено 0,114), положение — 0,01°
    /// (измерено 0,0096°). Тромсё — отдельно: Солнце скользит вдоль горизонта, и ошибка в сотую долю градуса — это
    /// десятки секунд времени (измерено 0,54 минуты на закате 25 июля).
    static let eventTolerance = 0.12
    static let polarEventTolerance = 0.6
    static let positionTolerance = 0.01

    static func day(_ c: File.Case, _ time: SkyTime) -> SolarDay {
        SolarDay(date: CivilDate(iso: c.date), latitude: c.latitude, longitude: c.longitude,
                 utcOffsetHours: c.utcOffsetHours, time: time)
    }

    static func event(_ day: SolarDay, _ name: String) -> Minutes? {
        switch name {
        case "rise": return day.rise
        case "set": return day.set
        case "goldA": return day.goldenA
        case "goldB": return day.goldenB
        case "blueA": return day.blueA
        case "blueB": return day.blueB
        case "civA": return day.civilA
        case "civB": return day.civilB
        case "nauA": return day.nauticalA
        case "nauB": return day.nauticalB
        case "astA": return day.astroA
        default: return day.astroB
        }
    }

    static func separation(_ a1: Double, _ e1: Double, _ a2: Double, _ e2: Double) -> Double {
        let r = Double.pi / 180
        let c = sin(e1 * r) * sin(e2 * r) + cos(e1 * r) * cos(e2 * r) * cos((a1 - a2) * r)
        return acos(min(1, max(-1, c))) / r
    }

    struct Stat {
        var max = 0.0, sum = 0.0, n = 0, worst = ""
        mutating func add(_ v: Double, _ label: @autoclosure () -> String) {
            n += 1; sum += v
            if v > max { max = v; worst = label() }
        }
        var mean: Double { n == 0 ? 0 : sum / Double(n) }
    }

    /// Ошибки модели против Horizons: события (все, без Тромсё, Тромсё), положение, события без совпадения по «есть/нет».
    struct Report {
        var events = Stat(), eventsNoPolar = Stat(), eventsPolar = Stat(), position = Stat()
        var existence: [String] = []
    }

    static func measure(_ time: SkyTime) throws -> Report {
        var r = Report()
        for c in try file.cases {
            let d = day(c, time)
            for (name, truth) in c.events {
                let label = "\(name) \(c.place) \(c.date)"
                switch (truth, event(d, name)) {
                case (nil, nil): continue
                case (let t?, let m?):
                    let e = abs(t - m)
                    r.events.add(e, label)
                    if c.place == "tromso" { r.eventsPolar.add(e, label) } else { r.eventsNoPolar.add(e, label) }
                default:
                    r.existence.append("\(label): Horizons \(String(describing: truth)), модель \(String(describing: event(d, name)))")
                }
            }
            for s in c.samples where s.el >= -18 {
                r.position.add(separation(s.az, s.el, d.azimuth(at: s.minute), d.elevation(at: s.minute)),
                               "\(c.place) \(c.date) мин \(s.minute)")
            }
        }
        return r
    }

    @Test("События света: ≤ 0,12 мин против Horizons везде, кроме Тромсё; «есть событие / нет» совпадает во всех 720")
    func eventsAgainstHorizons() throws {
        let r = try Self.measure(.iau)
        #expect(r.existence.isEmpty, "не совпало «есть / нет»: \(r.existence)")
        #expect(r.eventsNoPolar.n >= 540)
        #expect(r.eventsNoPolar.max <= Self.eventTolerance, "хуже всего: \(r.eventsNoPolar.worst) = \(r.eventsNoPolar.max) мин")
    }

    @Test("Тромсё: Солнце скользит по горизонту, события ≤ 0,6 мин, а закат 25 июля (в 00:37) есть — веб-модель его теряет")
    func tromsoPolarEdges() throws {
        let r = try Self.measure(.iau)
        #expect(r.eventsPolar.n >= 90)
        #expect(r.eventsPolar.max <= Self.polarEventTolerance, "хуже всего: \(r.eventsPolar.worst) = \(r.eventsPolar.max) мин")
        let july = try #require(Self.file.cases.first { $0.place == "tromso" && $0.date == "2026-07-25" })
        let truth = try #require(july.events["set"] ?? nil)
        #expect(Self.day(july, .iau).set != nil && Self.day(july, .web).set == nil)
        #expect(abs((Self.day(july, .iau).set ?? 0) - truth) <= Self.polarEventTolerance)
    }

    @Test("Положение Солнца (азимут и высота, 49 точек в сутках, высота ≥ −18°): ≤ 0,01° против Horizons")
    func positionAgainstHorizons() throws {
        let r = try Self.measure(.iau)
        #expect(r.position.n > 1_800)
        #expect(r.position.max <= Self.positionTolerance, "хуже всего: \(r.position.worst) = \(r.position.max)°")
    }

    @Test("До и после: точная модель лучше веб-модели против Horizons в разы; цифры для отчёта шага")
    func beforeAndAfter() throws {
        let before = try Self.measure(.web), after = try Self.measure(.iau)
        func line(_ name: String, _ b: Stat, _ a: Stat, _ unit: String) -> String {
            String(format: "  %-22@ n=%4d  веб-модель макс %7.3f ср %6.3f  →  точная макс %7.3f ср %6.3f %@",
                   name as NSString, a.n, b.max, b.mean, a.max, a.mean, unit as NSString)
        }
        print("solar_day_exact против JPL Horizons:")
        print(line("события, все", before.events, after.events, "мин"))
        print(line("события, без Тромсё", before.eventsNoPolar, after.eventsNoPolar, "мин"))
        print(line("события, Тромсё", before.eventsPolar, after.eventsPolar, "мин"))
        print(line("положение Солнца", before.position, after.position, "°"))
        print("  не совпало «есть / нет»: веб-модель \(before.existence.count), точная \(after.existence.count)")
        #expect(before.eventsNoPolar.max > 10 * after.eventsNoPolar.max)
        #expect(before.position.max > 10 * after.position.max)
        #expect(before.existence.count >= 1, "веб-модель должна терять закат Тромсё 25 июля — иначе тест полярного края ничего не доказывает")
    }

    @Test("Единый вход: SolarDay(.iau) стоит там же, где диск Солнца в AR (SunTrack через SkyFrame) — до 2·10⁻⁵°")
    func sameSunAsAR() throws {
        var worst = 0.0
        for c in try Self.file.cases {
            let d = Self.day(c, .iau)
            let date = CivilDate(iso: c.date)
            for m in stride(from: 0.0, through: 1440, by: 90) {
                let days = Sky.days(date: date, minutes: m, utcOffsetHours: c.utcOffsetHours)
                let ar = SkyFrame(days: days, latitude: c.latitude, longitude: c.longitude)
                    .horizontal(ofDate: SunMoonTheory.sun(days: days))
                worst = max(worst, abs(ar.altitude - d.elevation(at: m)))
                if ar.altitude > -85 && ar.altitude < 85 {
                    var da = abs(ar.azimuth - d.azimuth(at: m)); da = min(da, 360 - da)
                    worst = max(worst, da * cos(ar.altitude * Double.pi / 180))
                }
            }
        }
        #expect(worst < 2e-5, "SolarDay(.iau) разошёлся с SkyFrame на \(worst)°")
    }

    @Test("Входы: ядро сверки с вебом — .web, вход приложения с местом — .iau; модель видна в самом значении")
    func defaults() {
        let moscow = Place(latitude: 55.7558, longitude: 37.6173, zone: ZoneID(fixedOffsetHours: 3))
        let date = CivilDate(year: 2026, month: 9, day: 23)
        #expect(SolarDay(date: date, place: moscow).model == .iau)
        #expect(SolarDay(date: date, place: moscow, time: .web).model == .web)
        #expect(SolarDay(date: date, latitude: 55.7558, longitude: 37.6173, utcOffsetHours: 3).model == .web)
        #expect(SolarDay(date: date, place: moscow) != SolarDay(date: date, place: moscow, time: .web))
    }

    @Test("Точное Солнце: полдень, полночь шкалы и полярные сутки остаются согласованными")
    func invariants() throws {
        for c in try Self.file.cases {
            let d = Self.day(c, .iau)
            #expect(abs(d.maxt - d.mint - 1440) < 1e-9)
            #expect(abs(d.solarNoon - d.mint - 720) < 1e-9)
            // В полдень Солнце — на максимуме высоты суток (на 20 минут в обе стороны ниже).
            #expect(d.elevation(at: d.solarNoon) >= d.elevation(at: d.solarNoon - 20) - 1e-9)
            #expect(d.elevation(at: d.solarNoon) >= d.elevation(at: d.solarNoon + 20) - 1e-9)
            #expect(abs(d.maxElevation - d.elevation(at: d.solarNoon)) < 1e-9)
            if let r = d.rise, let s = d.set { #expect(r < d.solarNoon && d.solarNoon < s) }
            #expect((d.polar == .normal) == (d.rise != nil || d.set != nil))
        }
    }

    @Test("Сетка 21 широта × 52 недели (включая полюса и полярный круг): без NaN, события идут по порядку, полярность согласована с высотой")
    func gridSanity() {
        var checked = 0
        for lat in stride(from: -90.0, through: 90, by: 9) {
            for week in 0..<52 {
                let date = CivilDate(year: 2026, month: 1, day: 1).adding(days: week * 7)
                let d = SolarDay(date: date, latitude: lat, longitude: 37, utcOffsetHours: 3, time: .iau)
                checked += 1
                #expect(d.solarNoon.isFinite && d.maxElevation.isFinite && d.maxElevation >= -90 && d.maxElevation <= 90)
                // Утро по нарастанию, вечер по убыванию: астро < навигационные < гражданские < синий < восход < золотой < полдень.
                let morning = [d.astroA, d.nauticalA, d.civilA, d.blueA, d.rise, d.goldenA].compactMap { $0 }
                let evening = [d.goldenB, d.set, d.blueB, d.civilB, d.nauticalB, d.astroB].compactMap { $0 }
                #expect(morning == morning.sorted() && evening == evening.sorted(), "\(date) lat \(lat): события не по порядку")
                if let first = morning.first { #expect(first < d.solarNoon) }
                if let first = evening.first { #expect(first > d.solarNoon) }
                switch d.polar {
                case .day: #expect(d.maxElevation >= -0.833 && d.rise == nil && d.set == nil)
                case .night: #expect(d.maxElevation < -0.833 && d.rise == nil && d.set == nil)
                case .normal: #expect(d.rise != nil || d.set != nil)
                }
                for t in stride(from: d.mint, through: d.maxt, by: 60) {
                    let e = d.elevation(at: t), a = d.azimuth(at: t)
                    #expect(e.isFinite && a.isFinite && a >= 0 && a < 360)
                }
            }
        }
        #expect(checked == 21 * 52)
    }
}
