import Foundation
import Testing
@testable import LightPlanDomain

/// Свет в окнах зала (шаг 31в) против `Fixtures/window_light.json`. Эталон
/// собирает `Tools/parity/window_light.js` (`make parity`): высоту и азимут
/// солнца сверяет с блоками беты, ответы берёт из JS-копии для BroniOS. Не
/// сошлось — ошибка переноса, пока не доказано обратное.
struct WindowLightTests {
    static let file: J = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        let url = u.appendingPathComponent("Fixtures/window_light.json")
        do { return try JSONDecoder().decode(J.self, from: Data(contentsOf: url)) }
        catch { fatalError("нет или не читается \(url.path): \(error). Собрать: make parity") }
    }()
    let f = WindowLightTests.file

    /// Код ответа в эталоне → вид и золотая половина.
    func code(_ a: WindowLightAnswer) -> Int {
        switch a.kind {
        case .diffuse: return 0
        case .direct: return 1
        case .sunrise: return 2
        case .sunset: return 3
        case .none: return 4
        case .unknown: return 5
        }
    }

    func moment(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }

    // MARK: - Пороги

    @Test func thresholdsMatchFixture() {
        #expect(f["meta"]["range"]["from"].double! * 0.001 == WindowLight.instantRange.lowerBound)
        #expect(f["meta"]["range"]["to"].double! * 0.001 == WindowLight.instantRange.upperBound)
        let t = f["meta"]["thresholds"]
        #expect(t["minElevation"].double == WindowLight.minElevation)
        #expect(t["goldElevation"].double == WindowLight.goldElevation)
        #expect(t["maxOffset"].double == WindowLight.maxOffset)
    }

    // MARK: - Сетка: места × даты × моменты × азимуты окон

    @Test func gridMatchesFixture() {
        let azimuths = f["meta"]["azimuths"].array!.map { $0.double! }
        var total = 0
        var bad: [String] = []
        var seen = Set<Int>()
        var worst = 0.0
        for day in f["days"].array! {
            for row in day["rows"].array! {
                let ms = row[0].double!
                let wantOffsetMs = row[1].double!
                for (i, wa) in azimuths.enumerated() {
                    total += 1
                    let got = WindowLight.at(moment(ms), latitude: day["lat"].double, longitude: day["lon"].double,
                                             zone: day["zone"].string, windowsAzimuth: wa, hasWindows: true)
                    let want = row[4 + i].int!
                    seen.insert(want)
                    if code(got) != want {
                        bad.append("\(day["place"].string!) \(day["date"].string!) \(Int(ms)) окно \(wa)°: \(code(got)) вместо \(want)")
                        continue
                    }
                    worst = max(worst, abs(got.sunElevation! - row[2].double!), abs(got.sunAzimuth! - row[3].double!))
                    /* Сдвиг пояса: Foundation и ICU узла знают одни и те же правила */
                    if i == 0, let tz = TimeZone(identifier: day["zone"].string!),
                       Double(tz.secondsFromGMT(for: moment(ms))) * 1000 != wantOffsetMs {
                        bad.append("сдвиг пояса \(day["zone"].string!) \(Int(ms))")
                    }
                }
            }
        }
        #expect(total > 9000, "в эталоне \(total) строк")
        #expect(bad.isEmpty, "расхождений \(bad.count) из \(total)\n  \(bad.prefix(5).joined(separator: "\n  "))")
        #expect(worst <= 1e-9, "солнце расходится на \(worst)°")
        /* Сетка обязана задевать все исходы, иначе совпадение ничего не доказывает */
        #expect(seen == [0, 1, 2, 3], "в сетке есть не все исходы: \(seen)")
    }

    // MARK: - Пробы порога угла и приведение азимута

    @Test func edgeAndNormalizationMatchFixture() {
        var bad: [String] = []
        for key in ["edge", "norm", "far"] {
            let rows = f[key].array!
            #expect(rows.count >= 5, "в «\(key)» пусто")
            for r in rows {
                let got = WindowLight.at(moment(r["ms"].double!), latitude: r["lat"].double, longitude: r["lon"].double,
                                         zone: r["zone"].string, windowsAzimuth: r["windowsAzimuth"].double, hasWindows: true)
                if code(got) != r["code"].int! || abs(got.offsetFromWindow! - r["offset"].double!) > 1e-9 {
                    bad.append("\(key): \(r["why"].string!) в \(r["place"].string!): \(code(got)) вместо \(r["code"].int!)")
                }
            }
        }
        #expect(bad.isEmpty, "\(bad.joined(separator: "\n  "))")
        /* Пробы по обе стороны порога дают оба исхода */
        let codes = Set(f["edge"].array!.map { $0["code"].int! })
        #expect(codes == [0, 1], "пробы порога угла дали только \(codes)")
    }

    // MARK: - «Нет данных» и «нет окон»

    @Test func gapsMatchFixture() {
        let cases = f["gaps"].array!
        #expect(cases.count >= 10)
        var kinds = Set<String>()
        for c in cases {
            let i = c["input"]
            let got = WindowLight.at(i["ms"].double.map(moment), latitude: i["lat"].double, longitude: i["lon"].double,
                                     zone: i["zone"].string, windowsAzimuth: i["windowsAzimuth"].double,
                                     hasWindows: i["hasWindows"].bool)
            #expect(got.kind.rawValue == c["kind"].string!, "\(c["why"].string!)")
            #expect(got.reason?.rawValue == c["reason"].string, "\(c["why"].string!)")
            #expect(got.sunElevation == nil && got.sunAzimuth == nil && got.offsetFromWindow == nil, "\(c["why"].string!)")
            kinds.insert(got.kind.rawValue)
        }
        #expect(kinds == ["none", "unknown"])
    }

    // MARK: - Смысл правила, не из фикстуры

    /// 21 июня 2026, Томск (UTC+7), 13:00 по часам зала.
    let tomskNoon = Date(timeIntervalSince1970: 1_782_021_600) // 2026-06-21T06:00:00Z

    func tomsk(_ m: Date?, _ az: Double?, windows: Bool? = true) -> WindowLightAnswer {
        WindowLight.at(m, latitude: 56.4847, longitude: 84.9482, zone: "Asia/Tomsk", windowsAzimuth: az, hasWindows: windows)
    }

    @Test func noonSouthIsDirectNorthIsDiffuse() {
        #expect(tomsk(tomskNoon, 180).kind == .direct)
        #expect(tomsk(tomskNoon, 0).kind == .diffuse)
        #expect(tomsk(tomskNoon, 0).offsetFromWindow! > 150)
    }

    @Test func nightIsDiffuseInEveryDirection() {
        let night = tomskNoon.addingTimeInterval(12 * 3600)   // 01:00 следующих суток
        for az in [0.0, 90, 180, 270] { #expect(tomsk(night, az).kind == .diffuse) }
    }

    @Test func nothingIsInventedWithoutData() {
        #expect(tomsk(tomskNoon, nil).reason == .noAzimuth)
        #expect(tomsk(tomskNoon, .nan).reason == .noAzimuth)
        #expect(tomsk(tomskNoon, 180, windows: nil).reason == .noWindowsFlag)
        #expect(tomsk(nil, 180).reason == .badMoment)
        #expect(tomsk(Date(timeIntervalSince1970: .infinity), 180).reason == .badMoment)
        #expect(tomsk(tomskNoon, 180, windows: false).kind == .none)
        #expect(WindowLight.at(tomskNoon, latitude: nil, longitude: nil, zone: nil, windowsAzimuth: nil, hasWindows: false).kind == .none)
        #expect(WindowLight.at(tomskNoon, latitude: 56, longitude: 84, zone: "Мордор/Ородруин", windowsAzimuth: 180, hasWindows: true).reason == .badZone)
    }

    @Test func goldenHourIsSunriseInTheMorningSunsetInTheEvening() {
        /* Томск, 21 июня: перебор суток по минутам. Окно на восток видит только рассветный, на запад — только закатный */
        func kinds(_ az: Double) -> Set<WindowLightKind> {
            var out = Set<WindowLightKind>()
            for k in stride(from: 0, to: 24 * 60, by: 5) {
                let a = tomsk(tomskNoon.addingTimeInterval(Double(k - 6 * 60) * 60), az)
                if a.kind == .sunrise { #expect(a.half == .morning) }
                else if a.kind == .sunset { #expect(a.half == .evening) }
                else { #expect(a.half == nil) }
                if a.kind == .sunrise || a.kind == .sunset { #expect(a.sunElevation! >= 2 && a.sunElevation! <= 6) }
                out.insert(a.kind)
            }
            return out
        }
        let east = kinds(90), west = kinds(270)
        #expect(east.contains(.sunrise) && !east.contains(.sunset), "окно на восток: \(east)")
        #expect(west.contains(.sunset) && !west.contains(.sunrise), "окно на запад: \(west)")
    }

    @Test func hugeAndOutOfRangeMomentsAreNoData() {
        /* Год ≈ 275000 и дальше: умножение секунд на 1000 и разбор календаря раньше ломались */
        for secs in [8.64e15, -8.64e15, 8.64e18, 1e300, Double.greatestFiniteMagnitude, 4_102_444_800, -1] {
            let a = tomsk(Date(timeIntervalSince1970: secs), 180)
            #expect(a.kind == .unknown && a.reason == .momentOutOfRange, "\(secs): \(a)")
            #expect(a.sunElevation == nil && a.sunAzimuth == nil && a.offsetFromWindow == nil)
        }
        #expect(tomsk(Date(timeIntervalSince1970: .infinity), 180).reason == .badMoment)
        #expect(tomsk(Date(timeIntervalSince1970: .nan), 180).reason == .badMoment)
        /* Края внутри диапазона считаются */
        #expect(tomsk(Date(timeIntervalSince1970: 0), 180).kind != .unknown)
        #expect(tomsk(Date(timeIntervalSince1970: 4_102_444_799.999), 180).kind != .unknown)
        /* Окон нет — ответ и так готов, момент не смотрим */
        #expect(tomsk(Date(timeIntervalSince1970: 8.64e18), 180, windows: false).kind == .none)
    }

    @Test func southernHemisphereFlipsTheSun() {
        /* Сидней, декабрь: в полдень солнце на севере, окно на север — прямой, на юг — рассеянный */
        let noon = Date(timeIntervalSince1970: 1_797_822_000)   // 2026-12-21T03:00:00Z = 14:00 AEDT
        let n = WindowLight.at(noon, latitude: -33.8688, longitude: 151.2093, zone: "Australia/Sydney", windowsAzimuth: 0, hasWindows: true)
        let s = WindowLight.at(noon, latitude: -33.8688, longitude: 151.2093, zone: "Australia/Sydney", windowsAzimuth: 180, hasWindows: true)
        #expect(n.kind == .direct)
        #expect(s.kind == .diffuse)
    }
}
