import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// 29.8в.22: кнопка «Запланировать съёмку» на «Свете» открывала пустоту (`Button(action: {})`).
/// Веб (`#planToday`): `openForm(selDate, Math.round(SUN.goldB || viewMin), null, true)`.
@MainActor
struct LightPlanShootButtonTests {

    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }
    private final class Disk: DraftStoring, @unchecked Sendable {
        var data: Data?
        func load() -> Data? { data }
        func save(_ data: Data?) { self.data = data }
    }

    private func app() -> AppModel {
        let app = AppModel(snapshot: Snapshot(), store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
        app.draftStore = Disk()
        return app
    }

    /// То, что делает кнопка: `LightScreenView.actionButton` → `model.planShoot` → `RootView.onPlan`.
    private func tap(_ app: AppModel) {
        let r = app.light.planShoot
        app.openForm(day: r.day, start: r.start, fromLight: true)
    }

    @Test("тап открывает форму на выбранный день «Света» с началом золотого часа, время от света")
    func opensOnSelectedDayAtGoldenHour() throws {
        let app = app()
        let day = CivilDate(year: 2026, month: 10, day: 24)
        app.light.timebar.show(day: day, minute: 13 * 60)
        // Выбранный день «Света» не день «Съёмок»: форма берёт первый.
        #expect(app.planner.selected != day)
        let golden = try #require(app.light.timebar.solarDay.goldenB)

        tap(app)

        let f = try #require(app.form)
        #expect(f.day == day)
        #expect(f.start == Int(golden.rounded()))
        // `fromLight`: начало не округляется до шага и следует за светом (`fAuto` веба).
        #expect(f.timeFromLight && f.timeIsProposed)
        #expect(f.start != 13 * 60)
    }

    @Test("золотого часа в этот день нет — кнопка называет минуту таймбара, день тот же")
    func fallsBackToViewMinute() throws {
        let app = app()
        // Шпицберген, декабрь: полярная ночь, солнце не поднимается — золотого часа нет.
        app.light.timebar.setPlace(Place(latitude: 78.22, longitude: 15.65, zone: ZoneID("Arctic/Longyearbyen")!))
        let day = CivilDate(year: 2026, month: 12, day: 21)
        app.light.timebar.show(day: day, minute: 11 * 60 + 17)
        try #require(app.light.timebar.solarDay.goldenB == nil)

        let r = app.light.planShoot
        #expect(r.day == day && r.start == 11 * 60 + 17)

        // Форма берёт день из запроса; своё время она ставит по окну света места приложения (`applyPreset`,
        // веб `applyGenrePreset`) — в тесте это Барнаул, а не Шпицберген таймбара, поэтому начало формы тут не сверяется.
        tap(app)
        let f = try #require(app.form)
        #expect(f.day == day)
    }
}
