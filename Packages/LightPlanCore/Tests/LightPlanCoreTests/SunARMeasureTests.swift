import Testing
import Foundation
@testable import LightPlanCore

#if DEBUG
/// Измеритель отклонения компаса в AR (шаг 29.8в.11): на подставных потоках отсчётов — без датчиков и экрана.
struct SunARMeasureTests {

    private let sky = HorizontalPoint(altitude: 30, azimuth: 200)

    /// Поток отсчётов `n` штук с шагом `dt`: центр кадра смещён от расчётного тела на `azOff`, `altOff` (расчёт − кадр
    /// = отклонение), курс компаса — на `compassOff` (`nil` — компас молчит).
    private func stream(expected: HorizontalPoint? = nil, azOff: (Int) -> Double = { _ in 0 }, altOff: Double = 0,
                        compassOff: Double? = nil, n: Int = 26, dt: TimeInterval = 0.1,
                        accuracy: Double? = nil, level: MagneticAccuracy? = nil) -> [MeasureSample] {
        let e = expected ?? sky
        return (0..<n).map { i in
            let aimAz = (e.azimuth - azOff(i) + 720).truncatingRemainder(dividingBy: 360)
            return MeasureSample(
                time: 100 + Double(i) * dt,
                aim: HorizontalPoint(altitude: e.altitude - altOff, azimuth: aimAz),
                compassHeading: compassOff.map { (e.azimuth - $0 + 720).truncatingRemainder(dividingBy: 360) },
                expected: e, headingAccuracy: accuracy, magneticLevel: level)
        }
    }

    private func measure(_ samples: [MeasureSample], body: MeasureBody = .sun) -> MeasureOutcome {
        var m = SunARMeasurer()
        for s in samples { m.add(s) }
        return m.finish(body: body)
    }

    private func result(_ o: MeasureOutcome, sourceLocation: SourceLocation = #_sourceLocation) throws -> MeasureResult {
        guard case .result(let r) = o else {
            Issue.record("ждали результат, получили \(o)", sourceLocation: sourceLocation)
            throw CancellationError()
        }
        return r
    }

    // MARK: - Знак и величина

    @Test("курс совпал с расчётным азимутом: отклонение 0, разброс 0")
    func zeroWhenHeadingMatches() throws {
        let r = try result(measure(stream()))
        #expect(abs(r.motionAzimuth.median) < 1e-9)
        #expect(abs(r.altitude.median) < 1e-9)
        #expect(r.scatter < 1e-9)
    }

    @Test("центр кадра левее солнца на 5°: отклонение +5° (солнце правее), по высоте +2° (выше)")
    func plusFiveRightOfCenter() throws {
        let r = try result(measure(stream(azOff: { _ in 5 }, altOff: 2)))
        #expect(abs(r.motionAzimuth.median - 5) < 1e-9)
        #expect(abs(r.altitude.median - 2) < 1e-9)
    }

    @Test("центр кадра правее солнца: отклонение отрицательное")
    func minusWhenSunIsLeft() throws {
        let r = try result(measure(stream(azOff: { _ in -3.5 }, altOff: -1)))
        #expect(abs(r.motionAzimuth.median + 3.5) < 1e-9)
        #expect(abs(r.altitude.median + 1) < 1e-9)
    }

    @Test("через север: расчёт 1°, кадр 356° — отклонение +5°, а не −355°")
    func wrapsAcrossNorth() throws {
        let e = HorizontalPoint(altitude: 20, azimuth: 1)
        let r = try result(measure(stream(expected: e, azOff: { _ in 5 })))
        #expect(abs(r.motionAzimuth.median - 5) < 1e-9)
        #expect(abs(r.motionHeading - 356) < 1e-9)
    }

    @Test("размах — max минус min за окно, медиана устойчива к одиночному выбросу")
    func rangeAndMedian() throws {
        // Отклонения 4,5 … 5,6 по кругу, один выброс 9°.
        let r = try result(measure(stream(azOff: { i in i == 7 ? 9 : 4.5 + Double(i % 12) * 0.1 })))
        #expect(abs(r.motionAzimuth.range - (9 - 4.5)) < 1e-9)
        #expect(abs(r.motionAzimuth.median - 5.0) < 0.11)
        let calm = try result(measure(stream(azOff: { i in 4.5 + Double(i % 12) * 0.1 })))
        #expect(abs(calm.motionAzimuth.range - 1.1) < 1e-9)
    }

    // MARK: - Два источника курса

    @Test("компас и CoreMotion считаются отдельно: +5° и +3°")
    func sourcesSeparately() throws {
        let r = try result(measure(stream(azOff: { _ in 5 }, compassOff: 3)))
        #expect(abs(r.motionAzimuth.median - 5) < 1e-9)
        let c = try #require(r.compassAzimuth)
        #expect(abs(c.median - 3) < 1e-9)
        #expect(abs((r.compassHeading ?? 0) - 197) < 1e-9)
    }

    @Test("компас молчит: второго источника в итоге нет, первый на месте")
    func compassMissing() throws {
        let r = try result(measure(stream(azOff: { _ in 5 })))
        #expect(r.compassAzimuth == nil)
        #expect(r.compassHeading == nil)
        #expect(abs(r.motionAzimuth.median - 5) < 1e-9)
    }

    @Test("точность от системы — на последнем отсчёте")
    func accuracyAtTheEnd() throws {
        let r = try result(measure(stream(accuracy: 12, level: .medium)))
        #expect(r.headingAccuracy == 12)
        #expect(r.magneticLevel == MagneticAccuracy.medium.rawValue)
    }

    // MARK: - Отказы

    @Test("тело ниже горизонта (высота < −1°): отказ, замер бессмыслен")
    func belowHorizon() {
        let o = measure(stream(expected: HorizontalPoint(altitude: -1.5, azimuth: 250)))
        #expect(o == .refused(.belowHorizon))
    }

    @Test("высота ровно −1° — ещё считается")
    func atTheHorizonLimit() throws {
        _ = try result(measure(stream(expected: HorizontalPoint(altitude: -1, azimuth: 250))))
    }

    @Test("тело дальше 30° от центра: по курсу — отказ, по высоте — отказ, в пределах — принято")
    func offAim() throws {
        #expect(measure(stream(azOff: { _ in 31 })) == .refused(.offAim))
        #expect(measure(stream(azOff: { _ in -31 })) == .refused(.offAim))
        #expect(measure(stream(altOff: 31)) == .refused(.offAim))
        _ = try result(measure(stream(azOff: { _ in 29 }, altOff: 29)))
    }

    @Test("нет отсчётов: отказ «нет данных»")
    func noSamples() {
        #expect(SunARMeasurer().finish(body: .sun) == .refused(.noData))
    }

    // MARK: - Окно 2,5 с и частота 10 Гц

    @Test("из потока 30 Гц берётся 10 Гц; окно закрывается ровно через 2,5 с; в итоге 26 отсчётов")
    func tenHertzWindow() throws {
        var m = SunARMeasurer()
        var accepted = 0
        var done: Int?
        for (i, s) in stream(n: 200, dt: 1.0 / 30).enumerated() {
            if m.add(s) { accepted += 1 }
            if done == nil, m.isComplete { done = i }
            if m.isComplete { break }
        }
        #expect(accepted == 26)
        #expect(m.samples.count == 26)
        // Закрылось на отсчёте с t ≥ 2,5 с от первого: 75-й при 30 Гц.
        #expect(done == 75)
        let r = try result(m.finish(body: .sun))
        #expect(r.samples == 26)
    }

    @Test("прогресс окна растёт от 0 до 1 и не выходит за него")
    func progress() {
        var m = SunARMeasurer()
        #expect(m.progress == 0)
        for s in stream(n: 40) { m.add(s) }
        #expect(m.progress == 1)
        var half = SunARMeasurer()
        for s in stream(n: 14) { half.add(s) }
        #expect(abs(half.progress - 1.3 / 2.5) < 1e-9)
    }

    // MARK: - Тело: солнце и луна

    @Test("расчётная точка: солнце — как диск солнца, луна — как диск луны (видимая высота)")
    func expectedBody() {
        let place = Place(latitude: 53.3548, longitude: 83.7698, zone: ZoneID("Asia/Barnaul")!)
        let moment = Moment(ISO8601DateFormatter().date(from: "2026-09-23T06:00:00Z")!)
        let sun = MeasureBody.sun.expected(at: moment, in: place)
        let s = SunTrack.sample(at: moment, in: place)
        #expect(sun.azimuth == s.azimuth)
        #expect(sun.altitude == s.apparentAltitude)
        let moon = MeasureBody.moon.expected(at: moment, in: place)
        let m = MoonTrack.sample(at: moment, in: place)
        #expect(moon.azimuth == m.azimuth)
        #expect(moon.altitude == m.apparentAltitude)
        #expect(abs(moon.azimuth - sun.azimuth) > 0.5 || abs(moon.altitude - sun.altitude) > 0.5)
    }

    @Test("итог помнит, чем мерили")
    func resultKeepsBody() throws {
        #expect(try result(measure(stream(), body: .moon)).body == .moon)
    }

    // MARK: - CSV

    /// Разбор одной строки CSV с кавычками — ровно столько, сколько пишет `MeasureCSV`.
    private func parse(_ line: String) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        var chars = Array(line), i = 0
        chars.append("\u{0}")
        while i < chars.count - 1 {
            let c = chars[i]
            if quoted {
                if c == "\"" { if chars[i + 1] == "\"" { cur.append("\""); i += 1 } else { quoted = false } }
                else { cur.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { out.append(cur); cur = "" }
            else { cur.append(c) }
            i += 1
        }
        out.append(cur)
        return out
    }

    private func record(label: String, compass: Bool = true) throws -> MeasureRecord {
        let r = try result(measure(stream(azOff: { _ in 4.2 }, altOff: -0.8, compassOff: compass ? 3.9 : nil,
                                         accuracy: 15, level: .high)))
        return MeasureRecord(time: Date(timeIntervalSince1970: 1_790_000_000.25), moment: Date(timeIntervalSince1970: 1_790_000_000),
                             placeSource: "phone", latitude: 55.75, longitude: 37.62, trueNorth: true, caseLabel: label,
                             phone: "iPhone16,2", systemVersion: "26.0", result: r)
    }

    @Test("CSV: заголовок и строка — одно число полей; все поля на месте")
    func csvFields() throws {
        let row = parse(MeasureCSV.row(try record(label: "силикон")))
        let head = parse(MeasureCSV.header)
        #expect(head.count == 24)
        #expect(row.count == head.count)
        let f = Dictionary(uniqueKeysWithValues: zip(head, row))
        #expect(f["body"] == "sun")
        #expect(f["place_source"] == "phone")
        #expect(f["lat"] == "55.75000")
        #expect(f["dev_az_motion"] == "4.20")
        #expect(f["dev_az_compass"] == "3.90")
        #expect(f["dev_alt"] == "-0.80")
        #expect(f["range_az_motion"] == "0.00")
        #expect(f["samples"] == "26")
        #expect(f["accuracy_deg"] == "15.0")
        #expect(f["mag_level"] == "3")
        #expect(f["north"] == "true")
        #expect(f["case"] == "силикон")
        #expect(f["phone"] == "iPhone16,2")
        #expect(f["ios"] == "26.0")
        #expect(f["time_utc"] == "2026-09-21T00:53:20.250Z" || f["time_utc"]?.hasSuffix("Z") == true)
        #expect(!MeasureCSV.row(try record(label: "x")).contains("\n"))
    }

    @Test("CSV: метка чехла с запятой и кавычкой не ломает строку; без компаса поля пустые")
    func csvQuoting() throws {
        let row = parse(MeasureCSV.row(try record(label: "MagSafe, \"Apple\"", compass: false)))
        let head = parse(MeasureCSV.header)
        #expect(row.count == head.count)
        let f = Dictionary(uniqueKeysWithValues: zip(head, row))
        #expect(f["case"] == "MagSafe, \"Apple\"")
        #expect(f["dev_az_compass"] == "")
        #expect(f["heading_compass"] == "")
    }

    @Test("запись замера переживает JSON — из него живёт история на плашке")
    func recordCodable() throws {
        let r = try record(label: "кожа")
        let back = try JSONDecoder().decode(MeasureRecord.self, from: try JSONEncoder().encode(r))
        #expect(back == r)
    }
}
#endif
