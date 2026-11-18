import Testing
import Foundation
import LightPlanCore
import LightPlanData
@testable import LightPlanUI

/// 31.5 «Рассвет наравне с закатом» (Алексей 18.11: «закаты и рассветы равнозначны по значению»; «до конца рассвета не переключаемся
/// на закат… после окончания рассвета (рассветный золотой час тоже учитываем), переключаемся на расчет заката для того же дня»).
/// Томск 18.11.2026 — `Fixtures/open_meteo_tomsk_2026-11-18.json` (архив прогнозов Open-Meteo того дня): облачная ночь, утром только
/// перистые 41–48 % — рассвет 61 «с цветом»; к закату чисто — 28 «спокойный». Восход 09:05, утренний золотой час 08:38–10:12, закат 17:05.
/// Тест собран только из того, что было и на main (`buildDays`, `LightTelemetry.build`: `sunset.word`, `golden`, `proGroups`), — на старом
/// коде он падает проверками, а не сборкой. Новое API (`event`, `goldenLabel`, дата) — в `DawnEqualDatedTests`.
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct DawnEqualTests {

    static let lexicon = Lexicon("ru")
    static let clock = ClockText(language: "ru")
    static let tomsk = Place(latitude: 56.49, longitude: 84.95, zone: ZoneID(fixedOffsetHours: 7))
    static let date = CivilDate(year: 2026, month: 11, day: 18)

    static func weather() async throws -> WeatherDay {
        let url = TextFixtures.root.appendingPathComponent("Fixtures/open_meteo_tomsk_2026-11-18.json")
        let hourly = try await FileWeatherSource(forecast: url, air: nil).fetchHourly(at: tomsk)
        return try #require(WeatherDay.buildDays(from: hourly, place: tomsk, time: .iau).days[date])
    }

    static func light(at t: Minutes, _ w: WeatherDay?) -> LightTelemetry {
        LightTelemetry.build(
            sun: SolarDay(date: date, place: tomsk), t: t, moon: false, moonSnapshot: nil,
            weather: w, weatherStatus: .live(.direct), air: nil,
            headerLocationName: "Томск", headerDateLabel: "СР · 18 ноя", headerNote: "сегодня",
            lexicon: lexicon, clock: clock)
    }

    @Test("09:21 — верх о рассвете: слово рассвета у дуги, строка — восход и утренний золотой час")
    func morningIsAboutTheDawn() async throws {
        let w = try await Self.weather()
        #expect(w.sunrise == 61 && w.sunset == 28)
        let t = Self.light(at: 9 * 60 + 21, w)
        #expect(t.sunset.word == Self.lexicon.t("sunsetS.color"))          // 61 — «с цветом» (main: «спокойный», закат 28)
        #expect(t.sunset.text == "с цветом · 61 / 100")
        #expect(t.golden == "09:05 · золотой 08:38–10:12")                 // main: «15:58 – 17:32 · до заката 17:05»
        // До самого конца утреннего золотого часа — рассвет.
        #expect(Self.light(at: 10 * 60 + 11, w).sunset.word == Self.lexicon.t("sunsetS.color"))
        #expect(Self.light(at: 3 * 60, w).sunset.word == Self.lexicon.t("sunsetS.color"))
    }

    @Test("12:00 — верх о закате тех же суток, как было, но строка — закат и вечерний золотой час")
    func afternoonIsAboutTheSunset() async throws {
        let w = try await Self.weather()
        for t: Minutes in [720, 1025, 1380] {
            let l = Self.light(at: t, w)
            #expect(l.sunset.word == Self.lexicon.t("sunsetS.calm"))
            #expect(l.sunset.text == "спокойный · 28 / 100")
            #expect(l.golden == "17:05 · золотой 15:58–17:32")
        }
    }

    @Test("«Подробно»: «Прогноз рассвета» и «Прогноз заката», у каждого своё окно неба; первым — тот, что наверху")
    func detailsHoldBothForecastsTopFirst() async throws {
        let w = try await Self.weather()
        let dawnTitle = Self.lexicon.t("pro.dawnForecast"), setTitle = Self.lexicon.t("pro.sunsetForecast")
        #expect(dawnTitle == "Прогноз рассвета")
        func blocks(_ t: Minutes) -> [LightTelemetry.ProGroup] {
            Self.light(at: t, w).proGroups.filter { $0.title == dawnTitle || $0.title == setTitle }
        }
        let morning = blocks(9 * 60 + 21), noon = blocks(12 * 60)
        #expect(morning.map(\.title) == [dawnTitle, setTitle])
        #expect(noon.map(\.title) == [setTitle, dawnTitle])
        let dawn = try #require(morning.first)
        #expect(dawn.rows.first?.value == "61 / 100 · рассвет с цветом")
        #expect(dawn.rows.map(\.value).contains("41% · подсветка до восхода"))
        #expect(dawn.rows.last?.value == "91%")
        #expect(dawn.swatch?.word == "рассвет с цветом")
        #expect(morning.last?.rows.first?.value == "28 / 100 · спокойный закат")
        #expect(morning.last?.rows.last?.value == "83%")
        // Окна неба разные — у каждого свой час.
        #expect(dawn.swatch?.palette != morning.last?.swatch?.palette)
        #expect(morning.compactMap(\.swatch).count == 2)
        // Блоки стоят там же, где стоял один закатный: сразу после «Погоды».
        let titles = Self.light(at: 9 * 60 + 21, w).proGroups.map(\.title)
        let at = try #require(titles.firstIndex(of: dawnTitle))
        #expect(titles[at - 1] == Self.lexicon.t("pro.weather"))
    }
}

/// Новое API 31.5: событие минуты, подпись строки с датой, окно неба купола.
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct DawnEqualDatedTests {

    static func light(at t: Minutes, _ w: WeatherDay?, date label: String? = "ср 18 ноя", sun: SolarDay? = nil) -> LightTelemetry {
        LightTelemetry.build(
            sun: sun ?? SolarDay(date: DawnEqualTests.date, place: DawnEqualTests.tomsk), t: t, moon: false, moonSnapshot: nil,
            weather: w, weatherStatus: .live(.direct), air: nil,
            headerLocationName: "Томск", headerDateLabel: "СР · 18 ноя", headerNote: "сегодня",
            lexicon: DawnEqualTests.lexicon, clock: DawnEqualTests.clock, eventDateLabel: label)
    }

    @Test("подпись строки — событие с датой: «Рассвет · ср 18 ноя» до 10:12, «Закат · ср 18 ноя» после")
    func labelCarriesTheEventAndTheDate() async throws {
        let w = try await DawnEqualTests.weather()
        let am = Self.light(at: 9 * 60 + 21, w), pm = Self.light(at: 12 * 60, w)
        #expect(am.event == .dawn && pm.event == .sunset)
        #expect(am.goldenLabel == "Рассвет · ср 18 ноя")
        #expect(pm.goldenLabel == "Закат · ср 18 ноя")
        #expect(Self.light(at: 12 * 60, w, date: nil).goldenLabel == "Закат")
        // Дата строки — из `DateText`, тем же видом, что у планировщика: день недели строчными и короткий месяц.
        let d = DateText.carrier(year: 2026, month: 10, day: 18, in: TimeZone(secondsFromGMT: 7 * 3600)!)
        #expect(DateText(language: "ru", timeZone: TimeZone(secondsFromGMT: 7 * 3600)!).wdDayMonShort(d) == "ср 18 ноя")
    }

    @Test("полярная ночь: ни рассвета, ни заката — «Золотой час —», оценки нет")
    func polarNightHasNoEvent() {
        let sun = SolarDay(date: CivilDate(year: 2026, month: 12, day: 21),
                           place: Place(latitude: 78.22, longitude: 15.65, zone: ZoneID(fixedOffsetHours: 1)))
        let l = Self.light(at: 12 * 60, nil, sun: sun)
        #expect(l.event == nil)
        #expect(l.goldenLabel == DawnEqualTests.lexicon.t("tele.golden") && l.golden == "—")
        #expect(l.sunset.word == nil)
    }

    @Test("окно неба купола — прогноз события минуты")
    func domePaletteFollowsTheEvent() async throws {
        let w = try await DawnEqualTests.weather()
        let sun = SolarDay(date: DawnEqualTests.date, place: DawnEqualTests.tomsk)
        #expect(SkyPalette(weather: w, event: SkyEvent.at(9 * 60 + 21, sun: sun) ?? .sunset) == SkyPalette(weather: w, event: .dawn))
        #expect(SkyPalette(weather: w, event: SkyEvent.at(12 * 60, sun: sun) ?? .sunset) == SkyPalette(weather: w))
    }
}
