import Testing
import Foundation
@testable import LightPlanCore

/// 31.2 «Погода по правде»: температура из часов прогноза, осадки — в окне вокруг заката и момента, снег — снегом.
/// Томск 17.11.2026 — `Fixtures/open_meteo_tomsk_2026-11-17.json` (архив Open-Meteo того дня в форме `/v1/forecast`).
struct WeatherTruthCoreTests {

    static let tomsk = Place(latitude: 56.49, longitude: 84.95, zone: ZoneID(fixedOffsetHours: 7))
    static let date = CivilDate(year: 2026, month: 11, day: 17)

    static func tomskDay() throws -> WeatherDay {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        let data = try Data(contentsOf: u.appendingPathComponent("Fixtures/open_meteo_tomsk_2026-11-17.json"))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let h = try #require(root["hourly"] as? [String: Any])
        func nums(_ k: String) -> [Double] { (h[k] as? [NSNumber] ?? []).map(\.doubleValue) }
        let hourly = HourlyWeather(
            time: h["time"] as? [String] ?? [], cloud: nums("cloud_cover"), cloudLow: nums("cloud_cover_low"),
            cloudMid: nums("cloud_cover_mid"), cloudHigh: nums("cloud_cover_high"), humidity: nums("relative_humidity_2m"),
            temperature: nums("temperature_2m"), windSpeed: nums("wind_speed_10m"), windDirection: nums("wind_direction_10m"),
            windGusts: nums("wind_gusts_10m"), precipitation: nums("precipitation"), weatherCode: nums("weather_code").map { Int($0) })
        return try #require(WeatherDay.buildDays(from: hourly, place: tomsk, time: .iau).days[date])
    }

    /// Сутки синтетики: облачность 20 % (ясный закат), осадки и коды по часам.
    static func day(_ wet: [Int: (mm: Double, code: Int)], place: Place = tomsk, date: CivilDate = date) -> WeatherDay {
        let key = String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
        let time = (0..<24).map { String(format: "%@T%02d:00", key, $0) }
        let n = 24
        return WeatherDay.buildDays(from: HourlyWeather(
            time: time, cloud: Array(repeating: 20, count: n), cloudLow: Array(repeating: 0, count: n),
            cloudMid: Array(repeating: 10, count: n), cloudHigh: Array(repeating: 40, count: n),
            humidity: Array(repeating: 50, count: n), temperature: (0..<n).map { Double($0) - 10 },
            windSpeed: Array(repeating: 2, count: n),
            precipitation: (0..<n).map { wet[$0]?.mm ?? 0 }, weatherCode: (0..<n).map { wet[$0]?.code ?? 1 }),
            place: place, time: .iau).days[date]!
    }

    @Test("коды WMO: 71–77 и 85–86 — снег, прочее от 51 — дождь, до 51 — сухо")
    func codes() {
        for c in [71, 73, 75, 77, 85, 86] { #expect(Precip.of(code: c) == .snow) }
        for c in [51, 55, 61, 65, 66, 80, 82, 95, 99] { #expect(Precip.of(code: c) == .rain) }
        for c in [0, 1, 2, 3, 45, 48] { #expect(Precip.of(code: c) == nil) }
    }

    @Test("Томск 17.11: снег ночью не делает плохим закат, вечером сухо, утром — снег")
    func tomskPrecipitation() throws {
        let w = try Self.tomskDay()
        #expect(w.webQuality == .poor)                 // веб: 3,4 мм за сутки → «плохо» на весь день
        #expect(w.precip == nil)                       // закат 17:07 → окно 15–19 ч сухое
        #expect(w.quality == w.sky)                    // категория — по ярусам часа заката
        #expect(w.quality == SunsetScore.category(try #require(w.sunset)))
        #expect(w.precip(at: 6 * 60) == .snow)         // 06:00 — снег (код 73)
        #expect(w.quality(at: 6 * 60) == .poor)
        #expect(w.precip(at: 17 * 60 + 5) == nil)      // 17:05 — сухо
        #expect(w.precip(at: 14 * 60) == nil)          // 12–16 ч сухо: последний снег в 11 ч
        #expect(w.precip(at: 13 * 60) == .snow)        // окно 11–15 ещё видит снег 11 ч
    }

    @Test("Томск 17.11: температура — из часов, между часами по прямой; мин и макс — часы суток")
    func tomskTemperature() throws {
        let w = try Self.tomskDay()
        #expect(w.temperature(at: 17 * 60) == -0.8)
        let t1705 = try #require(w.temperature(at: 17 * 60 + 5))
        #expect(abs(t1705 - (-0.8 + (-1.0 + 0.8) * 5 / 60)) < 1e-9)
        #expect(Int(t1705.rounded()) == -1)
        let range = try #require(w.temperatureRange)
        #expect(range.low == -3.6 && range.high == -0.5)
        // Следующих суток в файле нет: после 23:00 держится 23:00, а не выдумывается.
        #expect(w.temperature(at: 23 * 60 + 40) == -3.6)
        #expect(w.temperature(at: -40) == -1.4)
    }

    @Test("полночь следующих суток продолжает прямую после 23:00")
    func nextMidnight() {
        let d0 = CivilDate(year: 2026, month: 6, day: 10), d1 = d0.adding(days: 1)
        let time = [d0, d1].flatMap { d in (0..<24).map { String(format: "%04d-%02d-%02dT%02d:00", d.year, d.month, d.day, $0) } }
        let temps = (0..<48).map { Double($0) }
        let n = time.count
        let days = WeatherDay.buildDays(from: HourlyWeather(
            time: time, cloud: Array(repeating: 20, count: n), temperature: temps, windSpeed: Array(repeating: 1, count: n),
            precipitation: Array(repeating: 0, count: n), weatherCode: Array(repeating: 1, count: n)),
            place: Self.tomsk, time: .iau).days
        #expect(days[d0]?.nextMidnight == 24)
        #expect(days[d0]?.temperature(at: 23 * 60 + 30) == 23.5)
        #expect(days[d1]?.nextMidnight == nil)
    }

    @Test("окно осадков ±2 ч вокруг заката: дождь утром не портит закат, дождь в час заката — портит")
    func sunsetWindow() throws {
        let set = try #require(SolarDay(date: Self.date, place: Self.tomsk).set)
        let setHour = Int((set / 60).rounded())
        let morning = Self.day(Dictionary(uniqueKeysWithValues: (1...11).map { ($0, (2.0, 63)) }))
        #expect(morning.webQuality == .poor && morning.precip == nil && morning.quality != .poor)
        let atSunset = Self.day([setHour: (1.0, 61)])
        #expect(atSunset.precip == .rain && atSunset.quality == .poor)
        let justBefore = Self.day([setHour - WeatherDay.wetWindowHours: (0.4, 71)])
        #expect(justBefore.precip == .snow && justBefore.quality == .poor)
        let earlier = Self.day([setHour - WeatherDay.wetWindowHours - 1: (0.4, 71)])
        #expect(earlier.precip == nil)
        // Сумма без кода (морось без кода от модели) считается от 0,5 мм за окно.
        #expect(Self.day([setHour: (0.3, 1), setHour + 1: (0.3, 1)]).precip == .rain)
        #expect(Self.day([setHour: (0.3, 1)]).precip == nil)
    }

    @Test("смешанные осадки: вид — по большинству часов, поровну — снег")
    func mixed() {
        let rec = { (code: Int) in HourRecord(cloud: 90, code: code, temperature: 0, low: 90, mid: 0, high: 0,
                                              humidity: 90, windSpeed: 1, windDirection: nil, windGusts: nil, precipitation: 0.3) }
        #expect(WeatherDay.wet([10: rec(61), 11: rec(71)], around: 10) == .snow)
        #expect(WeatherDay.wet([10: rec(61), 11: rec(61), 12: rec(71)], around: 11) == .rain)
        #expect(WeatherDay.wet([10: rec(3)], around: 10) == nil)
    }

    @Test("без заката (полярная ночь) — осадки по суткам, как у веба")
    func polarNight() {
        let north = Place(latitude: 78.2, longitude: 15.6, zone: ZoneID(fixedOffsetHours: 1))
        let dec = CivilDate(year: 2026, month: 12, day: 20)
        #expect(SolarDay(date: dec, place: north).set == nil)
        let w = Self.day([3: (1.0, 73)], place: north, date: dec)
        #expect(w.precip == .snow && w.quality == .poor && w.webQuality == .poor)
        #expect(Self.day([:], place: north, date: dec).precip == nil)
    }
}
