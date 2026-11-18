import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// 31.6в на новом API (на `1403a320` не собирается): подсказка времени формы — солнце и погода места съёмки.
@MainActor
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct DawnRest6cNewTests {

    /// Город приложения Москва (сухо), место съёмки Киев (дождь у заката, рассвет сухой), 21.09.2026: окно — утреннее, по солнцу
    /// Киева; без места — вечернее московское, как было.
    @Test("подсказка времени: окно по солнцу и небу места съёмки; без места — города")
    func formWindowAtTheShootPlace() async throws {
        let app = DawnRest6bTests.app(DawnRest6bTests.Sky(southRain: true))
        await app.light.weather.settled()
        let kyiv = GeoPoint(latitude: 50.45, longitude: 30.52)
        app.pointWeather.ask(app.cardPlace(kyiv))
        await app.pointWeather.settled()
        let day = DawnRest6bTests.moscowDay
        let there = SolarDay(date: day, place: app.cardPlace(kyiv)), here = SolarDay(date: day, place: app.place.place)
        let w = try #require(app.formLight(on: day, start: 18 * 60, at: kyiv))
        #expect(w.dawn && !w.poor && w.start == there.blueA && w.end == there.goldenA, "\(w)")
        #expect(there.blueA != here.blueA, "солнце Киева и Москвы разное — иначе тест ни о чём")
        let home = try #require(app.formLight(on: day, start: 18 * 60))
        #expect(!home.dawn && home.start == here.goldenB, "\(home)")
    }
}
