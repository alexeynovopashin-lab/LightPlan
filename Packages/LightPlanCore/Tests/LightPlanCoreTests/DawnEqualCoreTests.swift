import Testing
import Foundation
@testable import LightPlanCore

/// 31.5 «Рассвет наравне с закатом» (Алексей 18.11: «закаты и рассветы равнозначны»). Томск 18.11.2026 —
/// `Fixtures/open_meteo_tomsk_2026-11-18.json` (архив прогнозов Open-Meteo того дня в форме `/v1/forecast`): облачная ночь
/// (00–05 ч облачность 88–100 %, средний ярус до 88 %), к утру — только перистые 41–48 %, влажность 91 %; к закату — чисто, 83 %.
struct DawnEqualCoreTests {

    static let tomsk = WeatherTruthCoreTests.tomsk
    static let date = CivilDate(year: 2026, month: 11, day: 18)

    static func tomskDay() throws -> WeatherDay {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        let data = try Data(contentsOf: u.appendingPathComponent("Fixtures/open_meteo_tomsk_2026-11-18.json"))
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

    @Test("Томск 18.11: рассвет — своим часом и своей оценкой, закат — своим")
    func tomskDawnAndSunset() throws {
        let w = try Self.tomskDay()
        let sun = SolarDay(date: Self.date, place: Self.tomsk)
        let rise = try #require(sun.rise), set = try #require(sun.set)
        #expect(Int((rise / 60).rounded()) == 9 && Int((set / 60).rounded()) == 17)
        // Час восхода (9 ч): перистые 41 %, ни нижнего, ни среднего, влажность 91 % → 30 + 45·0,914 + 25·0,105 − 12,6 = 61.
        let dawn = try #require(w.dawnLayers)
        #expect(dawn.high == 41 && dawn.mid == 0 && dawn.low == 0 && dawn.humidity == 91)
        #expect(w.sunrise == 61)
        #expect(w.dawnQuality == .good && w.dawnPrecip == nil && !w.dawnFog)
        // Час заката (17 ч): чистое небо, 83 % → 30 + 45·0,062 + 25·0,105 − 7,8 = 28 — «спокойный», не «с цветом».
        #expect(w.layers?.high == 0 && w.sunset == 28 && w.quality == .plain)
        #expect(w.score(.dawn) == 61 && w.score(.sunset) == 28)
        #expect(w.layers(.dawn) == w.dawnLayers && w.layers(.sunset) == w.layers)
    }

    @Test("окно неба рассвета — та же формула на ярусах часа восхода: утро Томска живее вечера")
    func dawnPaletteFollowsDawnLayers() throws {
        let w = try Self.tomskDay()
        let dawn = try #require(SkyPalette(weather: w, event: .dawn))
        let set = try #require(SkyPalette(weather: w, event: .sunset))
        #expect(set == SkyPalette(weather: w), "по умолчанию — закат, как было")
        #expect(dawn != set)
        #expect(dawn.life > set.life)
        // Рассвета в прогнозе нет — окна нет (число не выдумывается).
        let noDawn = WeatherDay(quality: .good, cloud: 20, sunset: 60, layers: w.layers, temperatureBase: 0, wind: 0,
                                windDirection: nil, gust: 0, trend: [], real: true)
        #expect(SkyPalette(weather: noDawn, event: .dawn) == nil && SkyPalette(weather: noDawn) != nil)
    }

    @Test("дождь у восхода портит рассвет, а не вечер; дождь у заката — вечер, а не рассвет")
    func dawnSkyHasItsOwnWindow() throws {
        let sun = SolarDay(date: WeatherTruthCoreTests.date, place: Self.tomsk)
        let riseHour = Int((try #require(sun.rise) / 60).rounded())
        let setHour = Int((try #require(sun.set) / 60).rounded())
        let morning = WeatherTruthCoreTests.day([riseHour: (1.2, 61)])
        #expect(morning.dawnPrecip == .rain && morning.dawnQuality == .poor)
        #expect(morning.precip == nil && morning.quality != .poor)
        let evening = WeatherTruthCoreTests.day([setHour: (1.2, 61)])
        #expect(evening.precip == .rain && evening.quality == .poor)
        let eveningDawn = try #require(evening.sunrise)
        #expect(evening.dawnPrecip == nil && evening.dawnQuality == SunsetScore.category(eveningDawn))
        let fog = WeatherTruthCoreTests.day([riseHour: (0, 45)])
        #expect(fog.dawnFog && fog.dawnQuality == .fog && fog.quality != .fog)
    }

    @Test("событие минуты: рассвет до конца утреннего золотого часа, дальше — закат тех же суток; полярная ночь — никакого")
    func skyEventSwitchesAtMorningGoldenEnd() throws {
        let sun = SolarDay(date: Self.date, place: Self.tomsk)
        let end = try #require(sun.goldenA)
        #expect(SkyEvent.morningEnd(sun) == end)
        #expect(SkyEvent.at(0, sun: sun) == .dawn)                    // ночь до рассвета — уже рассвет этих суток
        #expect(SkyEvent.at(try #require(sun.rise), sun: sun) == .dawn)
        #expect(SkyEvent.at(end - 1, sun: sun) == .dawn)
        #expect(SkyEvent.at(end, sun: sun) == .sunset)
        #expect(SkyEvent.at(12 * 60, sun: sun) == .sunset)
        #expect(SkyEvent.at(23 * 60 + 59, sun: sun) == .sunset)        // после заката — закат тех же суток
        let polar = SolarDay(date: CivilDate(year: 2026, month: 12, day: 21),
                             place: Place(latitude: 78.22, longitude: 15.65, zone: ZoneID(fixedOffsetHours: 1)))
        #expect(polar.polar == .night && SkyEvent.at(12 * 60, sun: polar) == nil)
        // Солнце не поднимается до +6° (Мурманск, 10.12): рассвет держится до полудня.
        let low = SolarDay(date: CivilDate(year: 2026, month: 12, day: 10),
                           place: Place(latitude: 67.6, longitude: 33.1, zone: ZoneID(fixedOffsetHours: 3)))
        if low.polar == .normal, low.rise != nil, low.goldenA == nil {
            #expect(SkyEvent.at(low.solarNoon - 1, sun: low) == .dawn && SkyEvent.at(low.solarNoon, sun: low) == .sunset)
        }
    }
}
