import Testing
import Foundation
import LightPlanCore
@testable import LightPlanDomain

/// 30и.16: «свет сейчас» большого виджета — правилами экрана «Свет» — и облачность в строках закатов.
struct WidgetLightNowTests {
    private static let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    /// Время Томска (UTC+7) 16 ноября 2026 — день снимков Алексея.
    private static func tsk(_ h: Int, _ m: Int = 0, day d: Int = 16) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }

    /// Снимок «Света» Алексея 16.11, 14:50 в Томске: «до золотого часа 1 ч 13 м», «Условия · Мягкий свет». Виджет говорит то же.
    @Test func theWidgetSaysWhatTheLightScreenSaidAtTenToThree() throws {
        let now = try #require(BigWidget.lightNow(WidgetFeed(place: Self.tomsk).frame(at: Self.tsk(14, 50))))
        #expect(now.nextLabel == "До золотого часа")
        #expect(now.nextValue == "1 ч 13 м")
        #expect(now.text == "Мягкий свет")
        #expect(now.level != nil, "днём — деления, не звезда")
    }

    /// Правило одно с экраном «Свет»: состояние и отсчёт — `SolarDay.state(at:)` / `nextLight(at:)` той же минуты, весь день по 10 минут.
    @Test func everyTenMinutesTheRuleIsTheLightScreens() throws {
        let place = try #require(Self.tomsk.place)
        let sun = SolarDay(date: CivilDate(year: 2026, month: 11, day: 16), place: place)
        let feed = WidgetFeed(place: Self.tomsk)
        for t in stride(from: 0, to: 1440, by: 10) {
            let now = try #require(BigWidget.lightNow(feed.frame(at: Self.tsk(t / 60, t % 60))))
            let raw = sun.state(at: Double(t)), next = sun.nextLight(at: Double(t))
            #expect(now.level == (raw.stars ? nil : (raw.level ?? 1)), "\(t): деления")
            #expect(now.tone == raw.tone, "\(t): тон")
            #expect(now.text == BigWidget.fallbackRec[raw.code], "\(t): слово")
            #expect(now.nextLabel == BigWidget.fallbackNext[next.key], "\(t): подпись отсчёта")
            #expect(now.nextValue == next.minutes.map { BigWidget.shortSpan(feed.frame(at: Self.tsk(0)), minutes: $0) }, "\(t): отсчёт")
        }
    }

    /// Закрытое небо дня перебивает свет, как на «Свете»: «Небо закрыто», одно деление, нейтральный тон, без звезды ночью.
    @Test func aClosedSkyOverridesTheLight() throws {
        let feed = WidgetFeed(place: Self.tomsk, forecast: [WidgetFeed.Rating(day: "2026-11-16", score: 5, quality: .poor)])
        for at in [Self.tsk(12), Self.tsk(23)] {
            let now = try #require(BigWidget.lightNow(feed.frame(at: at)))
            #expect(now.text == "Небо закрыто" && now.level == 1 && now.tone == .neutral)
        }
        let clear = try #require(BigWidget.lightNow(WidgetFeed(place: Self.tomsk).frame(at: Self.tsk(23))))
        #expect(clear.level == nil, "ясной ночью — звезда")
    }

    @Test func theAppsWordsWinAndTheSpanFollowsItsTemplates() throws {
        var w = WidgetFeed.Words()
        w.table["next.toGolden"] = "Until golden hour"
        w.table["rec.evening"] = "Soft light"
        w.table["durS.hoursMins"] = "{h} h {m} m"
        let now = try #require(BigWidget.lightNow(WidgetFeed(place: Self.tomsk, words: w).frame(at: Self.tsk(14, 50))))
        #expect(now.nextLabel == "Until golden hour" && now.text == "Soft light" && now.nextValue == "1 h 13 m")
        let f = WidgetFeed(place: Self.tomsk).frame(at: Self.tsk(12))
        #expect(BigWidget.shortSpan(f, minutes: 40.4) == "40 мин" && BigWidget.shortSpan(f, minutes: 120) == "2 ч")
    }

    @Test func noPlaceNoLightNow() {
        #expect(BigWidget.lightNow(WidgetFeed(place: WidgetFeed.Spot(name: "", latitude: 0, longitude: 0, zone: "Nowhere/Zone")).frame(at: Self.tsk(12))) == nil)
    }

    /// Строки закатов несут облачность часа заката из того же прогноза; нет её в прогнозе — `nil`, не выдумывается.
    @Test func sunsetRowsCarryTheSunsetHourClouds() {
        let forecast = [WidgetFeed.Rating(day: "2026-11-17", score: 8, quality: .poor, clouds: 96),
                        WidgetFeed.Rating(day: "2026-11-18", score: 59, quality: .good, clouds: 40),
                        WidgetFeed.Rating(day: "2026-11-19", score: 67, quality: .good)]
        let rows = BraunIdle.sunsetRows(WidgetFeed(place: Self.tomsk, forecast: forecast).frame(at: Self.tsk(11, 30)))
        #expect(rows.map(\.clouds) == [96, 40, nil])
        #expect(rows.map(\.score) == [8, 59, 67])
    }

    /// Старый файл без облачности читается: поле необязательное.
    @Test func anOldRatingWithoutCloudsDecodes() throws {
        let json = #"{"day":"2026-11-17","score":8,"quality":"poor"}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(WidgetFeed.Rating.self, from: json)
        #expect(r.clouds == nil && r.score == 8)
    }
}
