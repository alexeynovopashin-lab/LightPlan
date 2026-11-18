import Testing
import Foundation
@testable import LightPlanDomain
import LightPlanCore

/// 31.5б, п. 3 (Алексей 18.11 «Да, все «б»», DECISIONS 18.11): средний виджет выбирает рассвет или закат тем же правилом, что верх «Света»
/// (`SkyEvent`): до конца утреннего золотого часа рассвет, без +6° за день — до полудня. Архангельск 10.12.2026: солнце встаёт около 10:40,
/// в полдень поднимается на ≈ 2,5°, утреннего золотого часа нет. До 31.5б виджет переключался на закат уже в восход, «Свет» — в полдень.
/// Только API, что было на `eeb05848`: на старом коде тест падает проверками.
struct DawnWidgetNoonTests {

    static let spot = WidgetFeed.Spot(name: "Архангельск", latitude: 64.54, longitude: 40.54, zone: "Europe/Moscow")
    static let feed = WidgetFeed(place: spot, forecast: [WidgetFeed.Rating(day: "2026-12-10", score: 30, quality: .plain, sunrise: 70)])
    static func msk(_ h: Int, _ m: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return c.date(from: DateComponents(year: 2026, month: 12, day: 10, hour: h, minute: m))!
    }

    @Test("Архангельск 10.12: без +6° виджет до полудня оценивает рассвет, как «Свет»")
    func lowSunRatesTheDawnUntilNoonLikeTheLightScreen() throws {
        let day = try #require(Self.feed.frame(at: Self.msk(12)).day)
        let rise = try #require(day.sunrise), set = try #require(day.sunset)
        #expect(day.goldenEnd == nil, "солнце до 6° не поднимается")
        let sun = SolarDay(date: CivilDate(year: 2026, month: 12, day: 10), place: try #require(Self.spot.place))
        #expect(sun.goldenA == nil && sun.polar == .normal)
        // 11:30 — после восхода, до полудня: «Свет» говорит о рассвете…
        let t = Self.msk(11, 30)
        #expect(rise < t && t < set)
        #expect(SkyEvent.at(11 * 60 + 30, sun: sun) == .dawn)
        // …и виджет тоже (до 31.5б — закат 30).
        let e = try #require(BraunIdle.ratedEvent(Self.feed.frame(at: t)))
        #expect(e.kind == .sunrise && !e.tomorrow && e.score == 70)
        #expect(BraunIdle.ratingLine(Self.feed.frame(at: t))?.hasPrefix("рассвет") == true)
        // После полудня — закат того же дня, у обоих.
        let pm = Self.msk(13, 30)
        #expect(SkyEvent.at(13 * 60 + 30, sun: sun) == .sunset)
        let e2 = try #require(BraunIdle.ratedEvent(Self.feed.frame(at: pm)))
        #expect(e2.kind == .sunset && e2.score == 30)
    }

    @Test("виджет просыпается в полдень: смена события на день без +6° стоит в его расписании")
    func theTimelineWakesAtNoonWhenThereIsNoMorningGoldenHour() throws {
        let sun = SolarDay(date: CivilDate(year: 2026, month: 12, day: 10), place: try #require(Self.spot.place))
        let dates = Self.feed.timeline(from: Self.msk(9)).dates
        let solarNoon = Self.msk(0).addingTimeInterval(sun.solarNoon * 60)
        #expect(dates.contains { abs($0.timeIntervalSince(solarNoon)) < 61 }, "в расписании нет полудня \(solarNoon)")
    }
}
