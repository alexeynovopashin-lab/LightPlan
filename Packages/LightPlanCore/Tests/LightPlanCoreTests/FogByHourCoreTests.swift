import Testing
import Foundation
@testable import LightPlanCore

/// 31.4 «Туман по часам»: туман судится тем же окном ±2 ч, что осадки 31.2 — у заката (категория дня), у рассвета (`dawnFog`)
/// и у выбранной минуты (`quality(at:)`). Томск 06.11.2026 — `Fixtures/open_meteo_tomsk_2026-11-06.json` (архив прогнозов Open-Meteo
/// того дня в форме `/v1/forecast`): туман (код 45) 09–12 ч, к закату (17:28) нижнего яруса нет, высокие облака.
/// Первые два теста собраны только из того, что было на main (`quality`, `quality(at:)`, `webQuality`, `sunset`), — на старом коде
/// они падают проверками, а не сборкой.
struct FogByHourCoreTests {

    static let tomsk = WeatherTruthCoreTests.tomsk
    static let date = CivilDate(year: 2026, month: 11, day: 6)

    static func tomskDay() throws -> WeatherDay {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        let data = try Data(contentsOf: u.appendingPathComponent("Fixtures/open_meteo_tomsk_2026-11-06.json"))
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

    /// Сутки синтетики, как у 31.2: облачность 20 %, ясный закат; коды по часам (туман — 45/48).
    static func day(_ codes: [Int: Int], place: Place = WeatherTruthCoreTests.tomsk,
                    date: CivilDate = WeatherTruthCoreTests.date) -> WeatherDay {
        WeatherTruthCoreTests.day(codes.mapValues { (0.0, $0) }, place: place, date: date)
    }

    static var setHour: Int {
        get throws { Int((try #require(SolarDay(date: WeatherTruthCoreTests.date, place: tomsk).set) / 60).rounded()) }
    }

    @Test("Томск 06.11: туман утром не делает «Туманом» день и закат; в 07:00 — туман, в 17:00 — нет")
    func tomskMorningFog() throws {
        let w = try Self.tomskDay()
        #expect(w.webQuality == .fog)                                 // веб: туман в 9 ч (окно 5–9) → «туман» на весь день
        #expect(w.quality != .fog)                                    // закат 17:28: окно 15–19 без тумана
        #expect(w.quality == SunsetScore.category(try #require(w.sunset)))
        #expect(w.quality(at: 7 * 60) == .fog)                        // окно 5–9 видит туман 9 ч
        #expect(w.quality(at: 10 * 60 + 30) == .fog)
        #expect(w.quality(at: 17 * 60) != .fog)                       // окно 15–19 — без тумана
        #expect(w.quality(at: 17 * 60) == w.quality)
    }

    @Test("туман 05–09 и ясный вечер: день не «Туман», утро — «Туман»; туман у заката — «Туман»")
    func syntheticWindows() throws {
        let morning = Self.day(Dictionary(uniqueKeysWithValues: (5...9).map { ($0, 45) }))
        #expect(morning.webQuality == .fog)
        let score = try #require(morning.sunset)
        #expect(morning.quality != .fog && morning.quality == SunsetScore.category(score))
        #expect(morning.quality(at: 7 * 60) == .fog)
        #expect(morning.quality(at: 17 * 60) != .fog)
        let setHour = try Self.setHour
        let atSunset = Self.day([setHour: 48])                       // туман с изморозью в час заката
        #expect(atSunset.quality == .fog)
        #expect(atSunset.quality(at: Double(setHour * 60)) == .fog)
        #expect(atSunset.webQuality != .fog)                          // веб смотрел только 5–9 ч
        #expect(Self.day([setHour + WeatherDay.wetWindowHours: 45]).quality == .fog)   // край окна
        #expect(Self.day([setHour + WeatherDay.wetWindowHours + 1: 45]).quality != .fog)
    }

    @Test("поля 31.4: туман у заката, туман у рассвета, туман на минуту")
    func fields() throws {
        let w = try Self.tomskDay()
        let rise = try #require(SolarDay(date: Self.date, place: Self.tomsk).rise)
        #expect(Int((rise / 60).rounded()) == 9)                      // восход 08:39 → окно рассвета 7–11 видит туман 9–11 ч
        #expect(w.fog == false && w.dawnFog == true)
        #expect(w.fog(at: 7 * 60) && !w.fog(at: 17 * 60))
        // Туман только к вечеру: рассвет чистый, день — «Туман».
        let evening = Self.day([try Self.setHour: 45])
        #expect(evening.fog && !evening.dawnFog)
        // Сухой день без тумана.
        let clear = Self.day([:])
        #expect(!clear.fog && !clear.dawnFog && clear.quality != .fog)
    }

    @Test("туман и осадки у заката разом — «Туман», как у веба (туман перебивает дождь)")
    func fogBeatsRain() throws {
        let setHour = try Self.setHour
        let w = WeatherTruthCoreTests.day([setHour: (1.0, 61), setHour + 1: (0, 45)])
        #expect(w.precip == .rain && w.fog && w.quality == .fog)
        #expect(w.quality(at: Double(setHour * 60)) == .fog)
    }

    @Test("без заката (полярная ночь) — туман 5–9 ч, как у веба")
    func polarNight() {
        let north = Place(latitude: 78.2, longitude: 15.6, zone: ZoneID(fixedOffsetHours: 1))
        let dec = CivilDate(year: 2026, month: 12, day: 20)
        let w = Self.day([6: 45], place: north, date: dec)
        #expect(w.fog && w.dawnFog && w.quality == .fog && w.webQuality == .fog)
        #expect(!Self.day([14: 45], place: north, date: dec).fog)
    }

    @Test("выдумка без часов: день тумана туманен и утром, как раньше")
    func mockDay() {
        let d = WeatherDay(quality: .fog, cloud: 50, sunset: nil, layers: nil, temperatureBase: 10, wind: 1,
                           windDirection: nil, gust: 0, trend: [], real: false)
        #expect(d.fog && d.dawnFog && d.quality(at: 17 * 60) == .fog)
        let e = WeatherDay(quality: .good, cloud: 30, sunset: nil, layers: nil, temperatureBase: 10, wind: 1,
                           windDirection: nil, gust: 0, trend: [], real: false)
        #expect(!e.fog && !e.dawnFog && e.quality(at: 7 * 60) == .good)
    }
}
