import Testing
import Foundation
import LightPlanCore
@testable import LightPlanDomain

/// 31.6 «Рассвет — остальные места», правила. Только API, что было и на `c7b1256b`: на старом коде набор падает проверками.
/// Новое API — в `DawnRestDomainNewTests`.
struct DawnRestDomainTests {
    private static let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    /// Время Томска (UTC+7) 18 ноября 2026: восход 09:05, утренний золотой час до 10:12.
    private static func tsk(_ h: Int, _ m: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }

    /// П. 6: утром «Небо закрыто» решает небо рассвета, после утреннего золотого часа — небо заката.
    @Test("большой виджет: дождь на рассвете закрывает небо утром, сухой закат — нет; днём наоборот")
    func closedSkyFollowsTheEventOnTop() throws {
        let wetDawn = WidgetFeed(place: Self.tomsk, forecast: [
            WidgetFeed.Rating(day: "2026-11-18", score: 80, quality: .excellent, sunrise: 20, dawnQuality: .poor)])
        let morning = try #require(BigWidget.lightNow(wetDawn.frame(at: Self.tsk(9, 30))))
        #expect(morning.text == "Небо закрыто", "\(morning.text)")
        let noon = try #require(BigWidget.lightNow(wetDawn.frame(at: Self.tsk(13))))
        #expect(noon.text != "Небо закрыто")

        let wetSunset = WidgetFeed(place: Self.tomsk, forecast: [
            WidgetFeed.Rating(day: "2026-11-18", score: 10, quality: .poor, sunrise: 70, dawnQuality: .good)])
        #expect(try #require(BigWidget.lightNow(wetSunset.frame(at: Self.tsk(9, 30)))).text != "Небо закрыто")
        #expect(try #require(BigWidget.lightNow(wetSunset.frame(at: Self.tsk(13)))).text == "Небо закрыто")
    }

    /// П. 18 на виджете: утром до восхода — «Синий час, ещё» / «Золотой час, ещё», вечером до заката — «Золотой час, ещё».
    @Test("большой виджет: подписи отсчёта — по новой лестнице «Света»")
    func widgetNextLabels() throws {
        let feed = WidgetFeed(place: Self.tomsk)
        #expect(try #require(BigWidget.lightNow(feed.frame(at: Self.tsk(8, 50)))).nextLabel == "Золотой час, ещё")
        #expect(try #require(BigWidget.lightNow(feed.frame(at: Self.tsk(16, 30)))).nextLabel == "Золотой час, ещё")
    }

    /// П. 16: две съёмки дня с пожеланием «Рассвет» спорят за свет, как две закатные.
    @Test("две съёмки на рассвет — предупреждение, как у двух закатных")
    func twoDawnShootsClash() {
        let day = CivilDate(year: 2026, month: 9, day: 10)
        let ctx = ClashContext(zones: DomainOracle.Zones(), appOffsetHours: 3, travel: { _, _ in .pending },
                               travelThreshold: 40, eventsLayer: true)
        var a = Session(id: "a", day: day, start: 360, end: 420)
        var b = Session(id: "b", day: day, start: 540, end: 600)
        a.place = "Лобня"; b.place = "Лобня"
        a.wishes = [.sunrise]; b.wishes = [.sunrise]
        let ab = Overlaps.clashes(ofSessionAt: 0, sessions: [a, b], blocks: [], context: ctx).map(\.kind.rawValue)
        #expect(ab == ["bothSunrise"])
        // Одна на рассвет, другая на закат — спора нет.
        b.wishes = [.sunset]
        #expect(Overlaps.clashes(ofSessionAt: 0, sessions: [a, b], blocks: [], context: ctx).isEmpty)
        // Две закатные — как было.
        a.wishes = [.sunset]
        #expect(Overlaps.clashes(ofSessionAt: 0, sessions: [a, b], blocks: [], context: ctx).map(\.kind) == [.bothSunset])
    }
}
