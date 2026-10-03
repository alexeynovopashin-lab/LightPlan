import CoreGraphics
import Testing
import Foundation
import LightPlanCore
import LightPlanData
@testable import LightPlanUI

/// Итерация 19: экран «Свет». Строит `LightTelemetry` на контрольных сутках
/// и проверяет числами то, что план назвал критерием готовности — состав и
/// вес семи строк телеметрии, а не пиксели (снимка веба этот экран пока не
/// умеет снять, см. отчёт итерации в `SWIFT_MIGRATION_PLAN.md`).
///
/// Использует настоящий словарь (`Lexicon`), поэтому, как и `LexiconParityTests`,
/// идёт только через `xcodebuild test` — на хосте каталог не собран.
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct LightTelemetryTests {

    static let lexicon = Lexicon("ru")
    static let clock = ClockText(language: "ru")

    /// Барнаул, тот же ориентир, что у стенда паритета и у демо-места RootView.
    static func barnaul(_ date: CivilDate) -> SolarDay {
        SolarDay(date: date, latitude: 53.3481, longitude: 83.7798, utcOffsetHours: 7)
    }

    static func day(quality: DayQuality, sunset: Int? = nil, layers: HourRecord? = nil,
                     wind: Int = 3, windDirection: Double? = nil, gust: Int = 0,
                     trend: [Double] = [40, 40, 40, 40, 40, 40]) -> WeatherDay {
        WeatherDay(quality: quality, cloud: 45, sunset: sunset, layers: layers,
                   temperatureBase: 20, wind: wind, windDirection: windDirection, gust: gust,
                   trend: trend, real: true)
    }

    private static func build(sun: SolarDay, t: Minutes, weather: WeatherDay?, status: WeatherStatus = .live(.direct),
                              moon: Bool = false, moonSnapshot: MoonSnapshot? = nil) -> LightTelemetry {
        LightTelemetry.build(
            sun: sun, t: t, moon: moon, moonSnapshot: moonSnapshot,
            weather: weather, weatherStatus: status, air: nil,
            headerLocationName: "Барнаул", headerDateLabel: "ПН · 21 июн", headerNote: "сегодня",
            lexicon: lexicon, clock: clock
        )
    }

    // MARK: - Плохая погода топит экспонометр в самый низ

    @Test func poorWeatherForcesMeterEvenAtNight() {
        // Глубокая ночь: без непогоды состояние было бы «звёзды», не деление.
        let sun = Self.barnaul(CivilDate(year: 2026, month: 12, day: 21))
        let night = sun.mint + 60   // час после полуночи — глубокая астрономическая ночь
        let clear = Self.build(sun: sun, t: night, weather: Self.day(quality: .good))
        #expect(clear.condition.gauge == .stars)

        let poor = Self.build(sun: sun, t: night, weather: Self.day(quality: .poor))
        #expect(poor.condition.gauge == .level(1))
        #expect(poor.tone == .neutral)
        #expect(poor.condition.text == Self.lexicon.t("sun.overcast.rec"))
    }

    // MARK: - Закат: цвет строки по трём порогам балла

    @Test func sunsetToneThresholds() {
        let sun = Self.barnaul(CivilDate(year: 2026, month: 6, day: 21))
        let noon = sun.solarNoon
        func tone(_ score: Int) -> LightTelemetry.SunsetTone {
            Self.build(sun: sun, t: noon, weather: Self.day(quality: .good, sunset: score)).sunset.tone
        }
        #expect(tone(100) == .brass)
        #expect(tone(75) == .brass)
        #expect(tone(74) == .green)
        #expect(tone(50) == .green)
        #expect(tone(49) == .ink)
        #expect(tone(28) == .ink)
        #expect(tone(27) == .blue)
        #expect(tone(0) == .blue)

        let missing = Self.build(sun: sun, t: noon, weather: Self.day(quality: .good, sunset: nil))
        #expect(missing.sunset.tone == .muted)
        #expect(missing.sunset.text == Self.lexicon.t("card.noDataDay"))
    }

    // MARK: - «Что дальше»: слово тренда облачности

    @Test func nextLightTrendWord() {
        let sun = Self.barnaul(CivilDate(year: 2026, month: 6, day: 21))
        let t = sun.solarNoon
        func word(_ trend: [Double]) -> String {
            Self.build(sun: sun, t: t, weather: Self.day(quality: .good, trend: trend)).next.trendWord!
        }
        #expect(word([50, 50, 50, 50, 50, 30]) == Self.lexicon.t("trend.clearing"))   // упала больше чем на 12
        #expect(word([30, 30, 30, 30, 30, 50]) == Self.lexicon.t("trend.closing"))    // выросла больше чем на 12
        #expect(word([40, 40, 40, 40, 40, 45]) == Self.lexicon.t("trend.same"))       // в пределах 12
    }

    // MARK: - Ветер: направление и порывы — не всегда в строке

    @Test func windLineOmitsDirectionAndGustWhenNotMeaningful() {
        let sun = Self.barnaul(CivilDate(year: 2026, month: 6, day: 21))
        let t = sun.solarNoon
        let calmNoDir = Self.build(sun: sun, t: t, weather: Self.day(quality: .good, wind: 1, windDirection: 90, gust: 1))
        #expect(!calmNoDir.wind!.contains(LightTelemetry.dirOf(90, lexicon: Self.lexicon)))

        let withDir = Self.build(sun: sun, t: t, weather: Self.day(quality: .good, wind: 4, windDirection: 90, gust: 4))
        #expect(withDir.wind!.contains(LightTelemetry.dirOf(90, lexicon: Self.lexicon)))
        #expect(!withDir.wind!.contains(Self.lexicon.t("wind.gust", ["n": "4"])))

        let withGust = Self.build(sun: sun, t: t, weather: Self.day(quality: .good, wind: 4, windDirection: 90, gust: 8))
        #expect(withGust.wind!.contains(Self.lexicon.t("wind.gust", ["n": "8"])))
    }

    // MARK: - Румб по азимуту (16 делений)

    @Test func compassDirectionsAtCardinalPoints() {
        let dirs = Self.lexicon.t("dirs").split(separator: ",").map(String.init)
        #expect(dirs.count == 16)
        #expect(LightTelemetry.dirOf(0, lexicon: Self.lexicon) == dirs[0])     // север
        #expect(LightTelemetry.dirOf(90, lexicon: Self.lexicon) == dirs[4])    // восток
        #expect(LightTelemetry.dirOf(180, lexicon: Self.lexicon) == dirs[8])   // юг
        #expect(LightTelemetry.dirOf(270, lexicon: Self.lexicon) == dirs[12])  // запад
        #expect(LightTelemetry.dirOf(360, lexicon: Self.lexicon) == dirs[0])   // оборот на месте севера
    }

    // MARK: - Спойлер: луна первой группой только в лунном режиме

    @Test func moonGroupOnlyWhenSnapshotGiven() {
        let sun = Self.barnaul(CivilDate(year: 2026, month: 6, day: 21))
        let t = sun.solarNoon
        let snapshot = MoonSnapshot(phase: MoonPhase(date: CivilDate(year: 2026, month: 6, day: 21), minutes: t, utcOffsetHours: 7),
                                     azimuth: 120, altitude: 20, distance: 384_000, arc: nil, riseAzimuth: nil, setAzimuth: nil)

        let sunMode = Self.build(sun: sun, t: t, weather: Self.day(quality: .good), moon: false, moonSnapshot: nil)
        #expect(sunMode.proGroups.first?.title == Self.lexicon.t("pro.sunNow"))

        let moonMode = Self.build(sun: sun, t: t, weather: Self.day(quality: .good), moon: true, moonSnapshot: snapshot)
        #expect(moonMode.proGroups.first?.title == Self.lexicon.t("pro.moonNow"))
    }

    // MARK: - Астрономическая ночь: «белая ночь» вместо прочерка

    @Test func astroNightRowFallsBackToWhiteNight() {
        // Высокие широты летом: тьмы −18° не бывает вовсе — тот самый случай,
        // где `astroB == nil` и веб подставляет особое слово, а не «—».
        let sun = SolarDay(date: CivilDate(year: 2026, month: 6, day: 21), latitude: 65, longitude: 60, utcOffsetHours: 3)
        #expect(sun.astroB == nil)
        let t = sun.solarNoon
        let telemetry = Self.build(sun: sun, t: t, weather: Self.day(quality: .good))
        let twilight = telemetry.proGroups.first { $0.title == Self.lexicon.t("pro.twilight") }
        let astroNightRow = twilight?.rows.first { $0.label == Self.lexicon.t("pro.astroNight") }
        #expect(astroNightRow?.value == Self.lexicon.t("pro.whiteNight"))
    }

    // MARK: - Спарклайн: та же ломаная, что и `sparkline(vals)` веба

    @Test func sparklineMatchesWebFormula() {
        let values: [Double] = [10, 90, 50, 20, 70, 40]
        let shape = SparklineShape(values: values)
        let rect = CGRect(x: 0, y: 0, width: 42, height: 14)
        var points: [CGPoint] = []
        shape.path(in: rect).forEach { element in
            switch element {
            case .move(let p), .line(let p): points.append(p)
            default: break
            }
        }
        #expect(points.count == values.count)
        for (i, v) in values.enumerated() {
            let wantX = Double(i) / Double(values.count - 1) * 42
            let wantY = 14 - v / 100 * (14 - 2) - 1
            #expect(abs(Double(points[i].x) - wantX) < 1e-4)
            #expect(abs(Double(points[i].y) - wantY) < 1e-4)
        }
    }

    // MARK: - 28е: плашка палитры неба над «Прогнозом заката»

    private static let layers = HourRecord(cloud: 20, code: 0, temperature: 10, low: 10, mid: 40, high: 50,
                                           humidity: 60, windSpeed: 0, windDirection: nil, windGusts: nil)

    private static func swatch(_ w: WeatherDay, t: Minutes, sun: SolarDay) -> LightTelemetry.Swatch? {
        build(sun: sun, t: t, weather: w).proGroups.compactMap(\.swatch).first
    }

    /// Веб: `skySwatch` рисуется там же и при том же условии, что группа «Прогноз
    /// заката» — у дня есть балл и ярусы. Времени суток условие не знает.
    @Test func swatchFollowsTheForecastGroupAndStandsAfterWeather() {
        let sun = Self.barnaul(CivilDate(year: 2026, month: 10, day: 3))
        let w = Self.day(quality: .good, sunset: 31, layers: Self.layers)
        let groups = Self.build(sun: sun, t: sun.solarNoon, weather: w).proGroups
        let titles = groups.map(\.title)
        let at = titles.firstIndex(of: Self.lexicon.t("pro.sunsetForecast"))!
        #expect(groups[at].swatch?.word == Self.lexicon.t("sunsetW.calm"))
        #expect(groups[at].swatch?.palette == SkyPalette(weather: w))
        #expect(titles[at - 1] == Self.lexicon.t("pro.weather"))
        #expect(groups.filter { $0.swatch != nil }.count == 1)
    }

    @Test func swatchNeedsBothScoreAndLayers() {
        let sun = Self.barnaul(CivilDate(year: 2026, month: 10, day: 3))
        let t = sun.solarNoon
        #expect(Self.swatch(Self.day(quality: .good), t: t, sun: sun) == nil)
        #expect(Self.swatch(Self.day(quality: .good, sunset: 60), t: t, sun: sun) == nil)
        #expect(Self.swatch(Self.day(quality: .good, layers: Self.layers), t: t, sun: sun) == nil)
        // День без прогноза (выдумка) — у прошедших дней и за окном в 16 суток.
        for d in [1, 20] {
            let mock = MockWeather.day(for: CivilDate(year: 2026, month: 10, day: d))
            #expect(Self.swatch(mock, t: t, sun: sun) == nil)
        }
    }

    @Test func swatchDoesNotDependOnTimeOfDayIncludingSunsetEdge() {
        let sun = Self.barnaul(CivilDate(year: 2026, month: 10, day: 3))
        let w = Self.day(quality: .good, sunset: 80, layers: Self.layers)
        var minutes = Array(stride(from: sun.mint, through: sun.mint + 1440, by: 10))
        if let set = sun.set { minutes += [set - 1, set, set + 1] }
        for t in minutes { #expect(Self.swatch(w, t: t, sun: sun) != nil) }
        // Слово — по баллу, как `sunsetWord`.
        for (score, key) in [(80, "beautiful"), (50, "color"), (28, "calm"), (27, "none")] {
            let word = Self.swatch(Self.day(quality: .good, sunset: score, layers: Self.layers), t: sun.solarNoon, sun: sun)?.word
            #expect(word == Self.lexicon.t("sunsetW.\(key)"))
        }
    }

    // MARK: - 28ж: нет настоящего прогноза — нет и выдумки

    private static func noForecast(_ status: WeatherStatus = .unavailable, moon: Bool = false) -> (LightTelemetry, LightTelemetry, SolarDay) {
        let sun = barnaul(CivilDate(year: 2026, month: 10, day: 3))
        let t = sun.solarNoon
        return (build(sun: sun, t: t, weather: nil, status: status, moon: moon),
                build(sun: sun, t: t, weather: day(quality: .good, sunset: 60, layers: layers), moon: moon), sun)
    }

    @Test func noForecastShowsTheHonestNoteAndNoMadeUpWeather() {
        let (none, _, _) = Self.noForecast()
        let note = Self.lexicon.t("wx.unavailable")
        #expect(note == "Прогноз недоступен")
        #expect(none.forecastNote == note)
        #expect(none.header.weather == nil, "ни знака, ни градусов, ни облачности, ни мин/макс")
        #expect(none.sky == nil && none.wind == nil)
        #expect(none.next.trend == nil && none.next.trendWord == nil, "ни искры тренда облачности, ни слова")
        #expect(none.sunset.text == note && none.sunset.tone == .muted, "плашка заката — надпись, не оценка")
    }

    @Test func whileLoadingTheNoteSaysSo() {
        let (loading, _, _) = Self.noForecast(.loading)
        #expect(loading.forecastNote == Self.lexicon.t("wx.loading"))
        #expect(loading.forecastNote != Self.lexicon.t("wx.unavailable"))
    }

    @Test func withAForecastThereIsNoNote() {
        let (_, real, _) = Self.noForecast()
        #expect(real.forecastNote == nil)
        #expect(real.header.weather != nil && real.sky != nil && real.wind != nil && real.next.trend != nil)
    }

    /// Астрономия остаётся: то, что считается по солнцу, не зависит от того, есть ли прогноз.
    @Test func astronomyIsTheSameWithAndWithoutAForecast() {
        let (none, real, sun) = Self.noForecast()
        #expect(none.golden == real.golden && none.golden != "—")
        #expect(none.light == real.light && none.shadow == real.shadow)
        #expect(none.readout == real.readout)
        #expect(none.next.label == real.next.label && none.next.value == real.next.value)
        #expect(none.actionSubtitle == real.actionSubtitle)
        #expect(none.condition == real.condition, "хорошая погода в этом тесте экспонометр не меняет — значит и без прогноза он прежний")
        let titles = none.proGroups.map(\.title)
        for key in ["pro.sunNow", "pro.dayCourse", "pro.goldenBlue", "pro.twilight"] {
            #expect(titles.contains(Self.lexicon.t(key)), "\(key): группа астрономии пропала")
        }
        _ = sun
    }

    /// Без прогноза нет и «плохого неба»: экспонометр не топится, а идёт по солнцу.
    @Test func withoutAForecastTheMeterFollowsTheSunNotAMadeUpOvercast() {
        let sun = Self.barnaul(CivilDate(year: 2026, month: 12, day: 21))
        let noon = sun.solarNoon
        let none = Self.build(sun: sun, t: noon, weather: nil, status: .unavailable)
        let poor = Self.build(sun: sun, t: noon, weather: Self.day(quality: .poor))
        let good = Self.build(sun: sun, t: noon, weather: Self.day(quality: .good))
        #expect(none.condition == good.condition)
        #expect(none.condition != poor.condition)
    }

    @Test func sourceRowIsHonestAboutThePath() {
        func source(_ status: WeatherStatus, weather: Bool = true) -> String {
            let sun = Self.barnaul(CivilDate(year: 2026, month: 10, day: 3))
            let t = Self.build(sun: sun, t: sun.solarNoon, weather: weather ? Self.day(quality: .good) : nil, status: status)
            let row = t.proGroups.first { $0.title == Self.lexicon.t("pro.weather") }!.rows.first { $0.label == Self.lexicon.t("pro.source") }!
            return row.value
        }
        #expect(source(.live(.direct)) == "Open-Meteo · прогноз")
        #expect(source(.live(.proxy)) == "Наш сервер · прогноз")
        #expect(source(.unavailable, weather: false) == "нет прогноза")
        #expect(source(.loading, weather: false) == "нет прогноза")
        // В группе «Погода» без прогноза — одна строка «Источник»: ни неба, ни облачности, ни градусов.
        let sun = Self.barnaul(CivilDate(year: 2026, month: 10, day: 3))
        let none = Self.build(sun: sun, t: sun.solarNoon, weather: nil, status: .unavailable)
        #expect(none.proGroups.first { $0.title == Self.lexicon.t("pro.weather") }!.rows.count == 1)
        #expect(none.proGroups.compactMap(\.swatch).isEmpty)
        #expect(!none.proGroups.map(\.title).contains(Self.lexicon.t("pro.sunsetForecast")))
    }

    /// Градусы шапки и спойлера идут через настройку единиц: Цельсий и Фаренгейт различаются (раньше это
    /// проверялось по выдуманной погоде в `AppModelTests`).
    @Test func temperatureUnitReachesTheHeader() {
        let sun = Self.barnaul(CivilDate(year: 2026, month: 10, day: 3))
        func head(_ f: Bool) -> LightTelemetry {
            LightTelemetry.build(sun: sun, t: sun.solarNoon, moon: false, moonSnapshot: nil,
                                 weather: Self.day(quality: .good), weatherStatus: .live(.direct), air: nil,
                                 headerLocationName: "", headerDateLabel: "", headerNote: "",
                                 lexicon: Self.lexicon, clock: Self.clock, fahrenheit: f)
        }
        #expect(head(false).header.weather?.temperature != head(true).header.weather?.temperature)
        #expect(head(true).header.weather?.temperature == "\(LightTelemetry.tempOut(20, sun.solarNoon, true))°")
    }

    @Test func theNewWordsExistInEveryLanguage() {
        for code in ["ru", "en", "es", "ja", "zh"] {
            let l = Lexicon(code)
            for key in ["wx.unavailable", "wx.loading", "pro.srcProxy", "pro.srcNone"] {
                #expect(l.t(key) != key && !l.t(key).isEmpty, "\(code): нет слова \(key)")
            }
            #expect(l.t("wx.unavailable") != l.t("wx.loading"))
        }
    }
}
