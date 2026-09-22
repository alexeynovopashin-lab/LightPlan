import CoreGraphics
import Testing
import Foundation
import LightPlanCore
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

    private static func build(sun: SolarDay, t: Minutes, weather: WeatherDay, moon: Bool = false, moonSnapshot: MoonSnapshot? = nil) -> LightTelemetry {
        LightTelemetry.build(
            sun: sun, t: t, moon: moon, moonSnapshot: moonSnapshot,
            weather: weather, weatherLive: true, air: nil,
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
            Self.build(sun: sun, t: t, weather: Self.day(quality: .good, trend: trend)).next.trendWord
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
        #expect(!calmNoDir.wind.contains(LightTelemetry.dirOf(90, lexicon: Self.lexicon)))

        let withDir = Self.build(sun: sun, t: t, weather: Self.day(quality: .good, wind: 4, windDirection: 90, gust: 4))
        #expect(withDir.wind.contains(LightTelemetry.dirOf(90, lexicon: Self.lexicon)))
        #expect(!withDir.wind.contains(Self.lexicon.t("wind.gust", ["n": "4"])))

        let withGust = Self.build(sun: sun, t: t, weather: Self.day(quality: .good, wind: 4, windDirection: 90, gust: 8))
        #expect(withGust.wind.contains(Self.lexicon.t("wind.gust", ["n": "8"])))
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
}
