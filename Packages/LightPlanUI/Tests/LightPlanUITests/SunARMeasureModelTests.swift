import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData

#if DEBUG
/// Измеритель отклонения компаса в AR (шаг 29.8в.11), уровень модели: подставной поток датчиков → станция замера →
/// плашка и CSV. Настоящее солнце и датчики — только на телефоне.
@MainActor
struct SunARMeasureModelTests {

    private final class Feed: AttitudeSource {
        var isAvailable = true
        var north: AttitudeNorth? = .trueNorth
        var push: (@MainActor (AttitudeSample) -> Void)?
        func start(_ onSample: @escaping @MainActor (AttitudeSample) -> Void) { push = onSample }
        func stop() { push = nil }
    }

    private final class Flag: ARCalibrationFlag { var seen = true }

    private final class QuietCamera: ARCameraDriving, @unchecked Sendable {
        func authorize() async -> ARCameraAuthorization { .noDevice }
        func run() async -> ARCameraOutcome { ARCameraOutcome(state: .noDevice, optics: nil) }
        func stop() {}
    }

    private final class MemorySettings: ARMeasureSettings {
        var body: MeasureBody = .sun
        var caseLabel = ""
        var history: [MeasureRecord] = []
    }

    private let barnaul = Place(latitude: 53.3548, longitude: 83.7698, zone: ZoneID("Asia/Barnaul")!)
    private let day = "2026-09-23T06:00:00Z"   // 13:00 по Барнаулу: солнце над горизонтом
    private let night = "2026-09-23T20:00:00Z" // 03:00: солнце под горизонтом

    private func moment(_ iso: String) -> Moment { Moment(ISO8601DateFormatter().date(from: iso)!) }

    private func tempLog() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "sunar_measure_\(UUID().uuidString).csv")
    }

    private func make(_ iso: String, source: (any AttitudeSource)?, settings: MemorySettings = MemorySettings(),
                      log: URL? = nil) -> SunARModel {
        let m = SunARModel(target: SunARTarget(place: barnaul, moment: moment(iso)), source: source, camera: QuietCamera(),
                           clock: { Moment(ISO8601DateFormatter().date(from: iso)!) }, calibrationFlag: Flag())
        m.measure = MeasureStation(settings: settings, logURL: log ?? tempLog(), phone: "iPhone16,2", system: "26.0")
        return m
    }

    /// 2,5 с потока 30 Гц: центр кадра смещён от тела на `azOff`, `altOff`; компас — на `compassOff`.
    private func pump(_ feed: Feed, expected: HorizontalPoint, azOff: Double, altOff: Double = 0, compassOff: Double? = nil,
                      from t0: Double = 1000, seconds: Double = 2.6) {
        let n = Int(seconds * 30)
        for i in 0..<n {
            let basis = CameraBasis(azimuth: (expected.azimuth - azOff + 360).truncatingRemainder(dividingBy: 360),
                                    altitude: expected.altitude - altOff)
            let comp = compassOff.map { (expected.azimuth - $0 + 360).truncatingRemainder(dividingBy: 360) }
            feed.push?(AttitudeSample(time: t0 + Double(i) / 30, basis: basis, rotationRate: 0, magneticAccuracy: .high,
                                      headingAccuracy: 14, trueHeading: comp))
        }
    }

    /// Поля одной строки CSV с кавычками (модель телефона `iPhone16,2` пишется в кавычках).
    private func fields(_ line: String) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" { if i + 1 < chars.count, chars[i + 1] == "\"" { cur.append("\""); i += 1 } else { quoted = false } }
                else { cur.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { out.append(cur); cur = "" }
            else { cur.append(c) }
            i += 1
        }
        out.append(cur)
        return out
    }

    private func sunNow(_ iso: String) -> HorizontalPoint { MeasureBody.sun.expected(at: moment(iso), in: barnaul) }

    // MARK: - Итог

    @Test("центр кадра левее солнца на 5°, ниже на 2°: плашка получает +5° по курсу и +2° по высоте")
    func deviationEndToEnd() async throws {
        let feed = Feed()
        let m = make(day, source: feed)
        await m.start()
        m.beginMeasure()
        #expect(m.measure.isCollecting)
        pump(feed, expected: sunNow(day), azOff: 5, altOff: 2, compassOff: 3)
        guard case .done(let rec) = m.measure.state else { Issue.record("ждали итог: \(m.measure.state)"); return }
        #expect(abs(rec.result.motionAzimuth.median - 5) < 0.01)
        #expect(abs(rec.result.altitude.median - 2) < 0.01)
        #expect(abs((rec.result.compassAzimuth?.median ?? 0) - 3) < 0.01)
        #expect(rec.result.scatter < 0.01)
        #expect(rec.result.headingAccuracy == 14)
        #expect(rec.placeSource == "chosen")
        #expect(rec.trueNorth == true)
        #expect(rec.result.samples == 26)
    }

    @Test("курс = расчётному азимуту: отклонение 0")
    func zeroDeviation() async {
        let feed = Feed()
        let m = make(day, source: feed)
        await m.start()
        m.beginMeasure()
        pump(feed, expected: sunNow(day), azOff: 0)
        guard case .done(let rec) = m.measure.state else { Issue.record("нет итога"); return }
        #expect(abs(rec.result.motionAzimuth.median) < 0.01)
        #expect(abs(rec.result.altitude.median) < 0.01)
    }

    @Test("плашка пишет строку так, как в задаче: знаки, запятая, разброс")
    func headlineText() async throws {
        let feed = Feed()
        let m = make(day, source: feed)
        await m.start()
        m.beginMeasure()
        // Курс гуляет на 1,1° вокруг +4,2°, высота +0,8° ниже расчётной.
        let e = sunNow(day)
        for i in 0..<78 {
            let off = 4.2 + (i % 2 == 0 ? -0.55 : 0.55)
            feed.push?(AttitudeSample(time: 1000 + Double(i) / 30, basis: CameraBasis(azimuth: e.azimuth - off, altitude: e.altitude + 0.8),
                                      rotationRate: 0))
        }
        guard case .done(let rec) = m.measure.state else { Issue.record("нет итога"); return }
        let lexicon = Lexicon("ru")
        let line = MeasureText(lexicon: lexicon, language: "ru").headline(rec.result)
        #expect(line == "Отклонение: +4,2° по курсу, −0,8° по высоте, разброс 1,1°")
    }

    // MARK: - Отказы

    @Test("солнце ниже горизонта: отказ с честным словом, в журнал и историю ничего не уходит")
    func belowHorizonRefused() async throws {
        let feed = Feed()
        let log = tempLog()
        let m = make(night, source: feed, log: log)
        await m.start()
        m.beginMeasure()
        pump(feed, expected: sunNow(night), azOff: 0)
        #expect(m.measure.state == .refused(.belowHorizon, .sun))
        #expect(m.measure.history.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: log.path))
        let text = MeasureText(lexicon: Lexicon("ru"), language: "ru")
        #expect(text.refusal(.belowHorizon, body: .sun) == "Солнце ниже горизонта, замер бессмыслен")
    }

    @Test("прицел не на солнце (дальше 30° от центра): отказ «наведите прицел»")
    func offAimRefused() async {
        let feed = Feed()
        let m = make(day, source: feed)
        await m.start()
        m.beginMeasure()
        pump(feed, expected: sunNow(day), azOff: 45)
        #expect(m.measure.state == .refused(.offAim, .sun))
        #expect(MeasureText(lexicon: Lexicon("ru"), language: "ru").refusal(.offAim, body: .sun)
                == "В центре кадра нет солнца по расчёту: наведите прицел на солнце")
    }

    @Test("без датчика (центр кадра ведёт палец): отказ сразу, набор не начинается")
    func noSensorRefused() async {
        let m = make(day, source: nil)
        await m.start()
        m.beginMeasure()
        #expect(m.measure.state == .refused(.noSensor, .sun))
        #expect(!m.measure.isCollecting)
    }

    // MARK: - Луна

    @Test("тело «луна»: расчётная точка — луны (как диск луны), в CSV столбец «тело» = moon")
    func moonBody() async throws {
        let feed = Feed()
        let settings = MemorySettings()
        settings.body = .moon
        // Время, когда луна над горизонтом, ищем по часам места (расчёт тот же, что рисует диск).
        var iso = day
        for h in 0..<24 {
            let t = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_790_000_000 + Double(h) * 3600))
            if MeasureBody.moon.expected(at: moment(t), in: barnaul).altitude > 5 { iso = t; break }
        }
        let log = tempLog()
        let m = make(iso, source: feed, settings: settings, log: log)
        await m.start()
        #expect(m.measure.body == .moon)
        m.beginMeasure()
        let moon = MeasureBody.moon.expected(at: moment(iso), in: barnaul)
        pump(feed, expected: moon, azOff: -2.5, altOff: 1)
        guard case .done(let rec) = m.measure.state else { Issue.record("нет итога: \(m.measure.state)"); return }
        #expect(rec.result.body == .moon)
        #expect(abs(rec.result.motionAzimuth.median + 2.5) < 0.01)
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        let head = fields(lines[0]), row = fields(lines[1])
        #expect(row[head.firstIndex(of: "body")!] == "moon")
    }

    // MARK: - Журнал и история

    @Test("CSV: заголовок один раз, на замер — ровно одна строка; метка чехла и модель телефона на месте")
    func csvOneRowPerMeasure() async throws {
        let feed = Feed()
        let log = tempLog()
        let m = make(day, source: feed, log: log)
        await m.start()
        m.measure.caseLabel = "кожа"
        for _ in 0..<3 {
            m.beginMeasure()
            pump(feed, expected: sunNow(day), azOff: 4)
        }
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines.count == 4)
        #expect(lines[0] == MeasureCSV.header)
        let head = fields(lines[0])
        for row in lines.dropFirst() {
            let f = fields(row)
            #expect(f.count == head.count)
            #expect(f[head.firstIndex(of: "case")!] == "кожа")
            #expect(f[head.firstIndex(of: "phone")!] == "iPhone16,2")
            #expect(f[head.firstIndex(of: "ios")!] == "26.0")
            #expect(f[head.firstIndex(of: "place_source")!] == "chosen")
        }
        #expect(m.measure.logExists)
    }

    @Test("история — последние 10, новые сверху; метка чехла и тело переживают новую станцию")
    func historyAndSettings() async {
        let feed = Feed()
        let settings = MemorySettings()
        let m = make(day, source: feed, settings: settings)
        await m.start()
        m.measure.caseLabel = "MagSafe"
        for i in 0..<12 {
            m.beginMeasure()
            pump(feed, expected: sunNow(day), azOff: Double(i))
        }
        #expect(m.measure.history.count == 10)
        #expect(abs(m.measure.history[0].result.motionAzimuth.median - 11) < 0.01)
        #expect(abs(m.measure.history[9].result.motionAzimuth.median - 2) < 0.01)
        #expect(settings.history.count == 10)
        let again = MeasureStation(settings: settings, logURL: tempLog(), phone: "x", system: "y")
        #expect(again.caseLabel == "MagSafe")
        #expect(again.history.count == 10)
    }

    @Test("экран закрыт посреди набора: замер брошен, итога нет, плашка закрыта")
    func closeAbandons() async {
        let feed = Feed()
        let m = make(day, source: feed)
        await m.start()
        m.beginMeasure()
        pump(feed, expected: sunNow(day), azOff: 3, seconds: 1)
        m.stop()
        #expect(m.measure.state == .idle)
        #expect(!m.measure.plateOpen)
        #expect(m.measure.history.isEmpty)
    }
}
#endif
