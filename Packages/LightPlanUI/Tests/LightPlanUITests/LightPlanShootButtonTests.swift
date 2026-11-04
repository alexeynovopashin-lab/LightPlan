import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// 29.8в.22: кнопка «Запланировать съёмку» на «Свете» открывала пустоту (`Button(action: {})`).
/// Шаг 30д (слово Алексея 04.11): «выставили время ползунком — на это время заводится съёмка»; у веба был золотой час.
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

    /// «Сейчас» приложения закреплено. День «Съёмок» — «сегодня» по часам в поясе места приложения (без сохранённого
    /// места — столица языка, Москва), и с настоящими часами 24.10.2026 он совпал с выбранным днём «Света» первого теста:
    /// тест краснел с 00:00 МСК 24.10 (замер: 23.10 23:59 МСК — зелёный, 24.10 00:01 МСК — красный; 790f4c1 и 7819edb одинаково).
    private static let now = ISO8601DateFormatter().date(from: "2026-10-20T12:00:00+03:00")!

    private func app() -> AppModel {
        let now = Self.now
        let app = AppModel(snapshot: Snapshot(), store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather(),
                           now: { now })
        app.draftStore = Disk()
        return app
    }

    /// То, что делает кнопка: `LightScreenView.actionButton` → `model.planShoot` → `RootView.onPlan`.
    private func tap(_ app: AppModel) {
        let r = app.light.planShoot
        app.openForm(day: r.day, start: r.start, fromLight: true)
    }

    @Test("тап заводит съёмку ровно на время ползунка, а не на золотой час")
    func opensAtSliderMinute() throws {
        let app = app()
        let day = CivilDate(year: 2026, month: 10, day: 24)
        app.light.timebar.show(day: day, minute: 13 * 60 + 47)
        #expect(app.planner.selected != day)                // выбранный день «Света» не день «Съёмок»: форма берёт первый

        tap(app)

        let f = try #require(app.form)
        #expect(f.day == day)
        #expect(f.start == 13 * 60 + 47)                    // минута точно, без округления к шагу
        #expect(!f.timeIsProposed)                          // время названо, жанр и свет его не двигают
        #expect(app.light.planShootTime == "13:47")         // то же, что написано на кнопке
    }

    @Test("у свадьбы время с ползунка тоже не подменяется полднем")
    func weddingKeepsSliderMinute() throws {
        let app = app()
        app.lastFormGenre = .wedding
        let day = CivilDate(year: 2026, month: 10, day: 24)
        app.light.timebar.show(day: day, minute: 15 * 60 + 3)
        tap(app)
        #expect(app.form?.start == 15 * 60 + 3)
    }

    @Test("ширина кнопки — по дуге купола")
    func buttonIsAsWideAsTheArc() {
        #expect(LightScreenView.actionWidth(dome: 440) == 326)
        #expect(LightScreenView.actionWidth(dome: 390) == 326)
        #expect(abs(LightScreenView.actionWidth(dome: 375) - 326 * 375 / 390) < 0.01)
    }
}
