import Testing
import Foundation
import LightPlanCore
import LightPlanData
@testable import LightPlanUI

/// 31.4 «Туман по часам»: Томск, 06.11.2026 — архив прогнозов Open-Meteo того дня (`Fixtures/open_meteo_tomsk_2026-11-06.json`, форма
/// `/v1/forecast`, разобран тем же `FileWeatherSource`): туман (код 45) 09–12 ч, вечером нижнего яруса нет. Веб (туман 5–9 ч → весь день)
/// называл «Туманом» и вечер. Тест собран только из того, что было на main (`buildDays`, `LightTelemetry.build`, `condKey`), — на старом
/// коде он падает проверками, а не сборкой.
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct FogByHourTests {

    static let lexicon = Lexicon("ru")
    static let tomsk = Place(latitude: 56.49, longitude: 84.95, zone: ZoneID(fixedOffsetHours: 7))
    static let date = CivilDate(year: 2026, month: 11, day: 6)

    static func weather() async throws -> WeatherDay {
        let url = TextFixtures.root.appendingPathComponent("Fixtures/open_meteo_tomsk_2026-11-06.json")
        let hourly = try await FileWeatherSource(forecast: url, air: nil).fetchHourly(at: tomsk)
        return try #require(WeatherDay.buildDays(from: hourly, place: tomsk, time: .iau).days[date])
    }

    static func light(at t: Minutes, _ w: WeatherDay) -> LightTelemetry {
        LightTelemetry.build(
            sun: SolarDay(date: date, place: tomsk), t: t, moon: false, moonSnapshot: nil,
            weather: w, weatherStatus: .live(.direct), air: nil,
            headerLocationName: "Томск", headerDateLabel: "ЧТ · 6 ноя", headerNote: "",
            lexicon: lexicon, clock: ClockText(language: "ru"))
    }

    @Test("07:00 — «Туман»; 17:00 — не «Туман»; слово дня — по закату")
    func wordsByHour() async throws {
        let w = try await Self.weather()
        let morning = Self.light(at: 7 * 60, w)
        #expect(morning.header.weather?.condition == "Туман")
        #expect(morning.sky?.iconName == "fog")
        let evening = Self.light(at: 17 * 60, w)
        #expect(evening.header.weather?.condition != "Туман")
        #expect(evening.sky?.iconName != "fog")
        // Слово дня (полоса дней, карточка) — по окну заката 17:28: тумана там нет.
        #expect(Self.lexicon.t(w.condKey) != "Туман")
        #expect(w.signIconName != "fog")
    }
}
