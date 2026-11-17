import Testing
import Foundation
import LightPlanCore
import LightPlanData
@testable import LightPlanUI

/// 31.2 «Погода по правде»: Томск, 17.11.2026 — Алексей сравнил экран «Свет» с небом («на улице было −2, приложение показывало +3 и дождь»).
/// Вход — настоящий ответ Open-Meteo (архив того дня, форма `/v1/forecast`: `Fixtures/open_meteo_tomsk_2026-11-17.json`), разобранный тем же
/// `FileWeatherSource`, что у снимков: ночной снег 01–11 ч (3,4 мм, коды 71–73), с 12 ч сухо (код 3); температура −3,6…−0,5, в 17:00 −0,8.
/// Тест собран только из того, что было и до 31.2 (`buildDays`, `LightTelemetry.build`), — поэтому на старом коде он падает числами, а не сборкой.
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct WeatherTruthTests {

    static let lexicon = Lexicon("ru")
    static let clock = ClockText(language: "ru")
    static let tomsk = Place(latitude: 56.49, longitude: 84.95, zone: ZoneID(fixedOffsetHours: 7))
    static let date = CivilDate(year: 2026, month: 11, day: 17)

    static func weather() async throws -> WeatherDay {
        let url = TextFixtures.root.appendingPathComponent("Fixtures/open_meteo_tomsk_2026-11-17.json")
        let hourly = try await FileWeatherSource(forecast: url, air: nil).fetchHourly(at: tomsk)
        return try #require(WeatherDay.buildDays(from: hourly, place: tomsk, time: .iau).days[date])
    }

    static func light(at t: Minutes, _ w: WeatherDay, fahrenheit: Bool = false) -> LightTelemetry {
        LightTelemetry.build(
            sun: SolarDay(date: date, place: tomsk), t: t, moon: false, moonSnapshot: nil,
            weather: w, weatherStatus: .live(.direct), air: nil,
            headerLocationName: "Томск", headerDateLabel: "ВТ · 17 ноя", headerNote: "сегодня",
            lexicon: lexicon, clock: clock, fahrenheit: fahrenheit)
    }

    @Test("17:05 — температура из часов прогноза, мин и макс — из часов суток")
    func temperatureFromTheHours() async throws {
        let w = try await Self.weather()
        let head = try #require(Self.light(at: 17 * 60 + 5, w).header.weather)
        // 17:00 −0,8, 18:00 −1,0 → 17:05 −0,82 → «−1°» (до 31.2: средняя −1,76 → −2, синус +5 в 16 ч → «3°»).
        #expect(head.temperature == "-1°")
        #expect(head.low == "↓ -4°")     // 23:00 −3,6 (было «↓ -7°»: −2 − 5)
        #expect(head.high == "↑ -1°")    // 16:00 −0,5, округление от нуля, как у градусов везде (было «↑ 3°»)
        // Строка «Подробно» «Температура» — тот же час.
        let rows = Self.light(at: 17 * 60 + 5, w).proGroups.flatMap(\.rows)
        #expect(rows.contains { $0.label == Self.lexicon.t("pro.temp") && $0.value == "-1 °C" })
        // Фаренгейт — из неокруглённого значения: −0,82 °C = 30,5 °F → 31.
        #expect(Self.light(at: 17 * 60 + 5, w, fahrenheit: true).header.weather?.temperature == "31°")
    }

    @Test("вечером сухо: не «Дождь», ночной снег не топит экспонометр и закат")
    func eveningIsNotRain() async throws {
        let w = try await Self.weather()
        let evening = Self.light(at: 17 * 60 + 5, w)
        let head = try #require(evening.header.weather)
        #expect(head.condition != "Дождь")
        #expect(head.condition == "Пасмурно")       // закат 17:07, нижний ярус 100 % в 15–19 ч: небо закрыто, но без осадков
        #expect(evening.sky.map { !$0.text.contains("Дождь") } ?? false)
        // Балл заката — ярусы часа заката (17 ч, балл 0), осадки ночи его не трогают.
        let set = try #require(SolarDay(date: Self.date, place: Self.tomsk).set)
        let lay = try #require(Weather.nearHour(try await Self.hours(), Int((set / 60).rounded())))
        #expect(w.sunset == SunsetScore.score(low: lay.low, mid: lay.mid, high: lay.high, humidity: lay.humidity))
        // Категория дня (полоса дней, карточка, виджеты) — по окну заката: сухо, значит «плохо» только от облаков, не от снега ночью.
        #expect(w.quality == SunsetScore.category(w.sunset ?? -1))
    }

    @Test("утром идёт снег — «Снег», не «Дождь»")
    func morningSnowIsSnow() async throws {
        let w = try await Self.weather()
        let morning = Self.light(at: 6 * 60, w)
        #expect(morning.header.weather?.condition == "Снег")
        #expect(morning.condition.gauge == .level(1))
        #expect(morning.sky?.iconName == "snow")
    }

    static func hours() async throws -> [Int: HourRecord] {
        let url = TextFixtures.root.appendingPathComponent("Fixtures/open_meteo_tomsk_2026-11-17.json")
        let hourly = try await FileWeatherSource(forecast: url, air: nil).fetchHourly(at: tomsk)
        return WeatherDay.buildDays(from: hourly, place: tomsk, time: .iau).hourly[date] ?? [:]
    }
}
