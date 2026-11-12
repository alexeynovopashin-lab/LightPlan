import Foundation
import Testing
import LightPlanCore
import LightPlanDomain
import LightPlanData
@testable import LightPlanUI

/// 30г.14 (Алексей 12.11, «да, так»): плашка предупреждения стоит под блоком, к которому относится. Про время (занято,
/// наложение, чужой календарь) — под временем; про погоду (погода, луна, Млечный Путь) — под пожеланиями, пока форма
/// открыта; при следующем открытии — наверху, под временем. Поменяли пожелание после открытия — снова под пожеланиями.
/// Форма у дома в «Астро», белая ночь 21.06.2027 (прогноза нет), «Звёзды»: «Млечного Пути не будет видно».
@MainActor
struct FormWarnPlaceTests {
    private struct NoWeather: WeatherSource {
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw URLError(.notConnectedToInternet) }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { [:] }
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

    private static let june = CivilDate(year: 2027, month: 6, day: 21)
    private static let starsTitle = "Млечного Пути не будет видно"

    private func model() -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00+03:00")!
        let app = AppModel(snapshot: Snapshot(), store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: NoWeather(), now: { now })
        app.draftStore = Disk()
        app.update { $0.mode = .astro }
        return app
    }

    /// Другая съёмка ровно на время открытой формы: мягкое наложение, сохранить можно.
    private func addClash(_ app: AppModel) throws {
        let f = try #require(app.form)
        app.snapshot.sessions.append(Session(id: "other", kind: .shoot, day: f.day, start: f.start,
                                             end: f.start + f.duration, duration: f.duration, genre: .portrait))
    }

    /// «Сохранить» и открыть ту же съёмку снова.
    private func saveAndReopen(_ app: AppModel) throws {
        let id = try #require(app.form?.id)
        #expect(app.saveForm() != nil, "сохранить можно")
        #expect(app.form == nil)
        app.openForm(editing: id)
        #expect(app.form?.id == id)
    }

    /// Сколько раз плашка про «Звёзды» стоит на форме — дублей нет.
    private func starsCount(_ w: FormWarnings) -> Int {
        (w.top + [w.underWishes].compactMap { $0 }).filter { $0.title == Self.starsTitle }.count
    }

    // MARK: - Случай 1: новая съёмка

    /// Новая форма открывается без пожеланий — плашки нет. Нажали «Звёзды» — плашка под пожеланиями, наверху пусто.
    @Test func newShootWeatherPlateStandsUnderWishes() async throws {
        let app = model()
        await app.light.weather.settled()
        app.openForm(day: Self.june)
        var f = try #require(app.form)
        #expect(f.wishes.isEmpty)
        #expect(app.formWarnings(f) == FormWarnings(top: [], underWishes: nil))
        app.toggleFormWish(.stars)
        f = try #require(app.form)
        let w = app.formWarnings(f)
        #expect(w.top.isEmpty, "\(w.top.map(\.title))")
        #expect(w.underWishes?.title == Self.starsTitle)
        #expect(w.underWishes == app.formWishWarning(f), "та же плашка, что считает «замысел против прогноза»")
        #expect(starsCount(w) == 1)
    }

    // MARK: - Случай 2: повторное открытие

    /// Сохранённая съёмка со «Звёздами», открытая снова: плашка наверху, под пожеланиями пусто.
    @Test func reopenedShootShowsWeatherPlateOnTop() async throws {
        let app = model()
        await app.light.weather.settled()
        app.openForm(day: Self.june)
        app.toggleFormWish(.stars)
        try saveAndReopen(app)
        let f = try #require(app.form)
        #expect(f.wishes == [.stars])
        let w = app.formWarnings(f)
        #expect(w.top.map(\.title) == [Self.starsTitle])
        #expect(w.underWishes == nil)
        #expect(starsCount(w) == 1)
    }

    /// Черновик тоже открытие: набрали «Звёзды», закрыли крестиком, открыли тот же день — плашка наверху.
    @Test func reopenedDraftShowsWeatherPlateOnTop() async throws {
        let app = model()
        await app.light.weather.settled()
        app.openForm(day: Self.june)
        app.toggleFormWish(.stars)
        app.closeForm()
        app.openForm(day: Self.june)
        #expect(app.formIsDraft, "поднялся черновик")
        let f = try #require(app.form)
        #expect(f.wishes == [.stars])
        let w = app.formWarnings(f)
        #expect(w.top.map(\.title) == [Self.starsTitle])
        #expect(w.underWishes == nil)
    }

    // MARK: - Случай 3: пожелание поменяли после повторного открытия

    /// После повторного открытия тронули пожелания — плашка снова под пожеланиями и наверх не возвращается до следующего
    /// открытия, даже если пожелания вернули как было. Следующее открытие — снова наверху.
    @Test func wishChangedAfterReopenMovesPlateUnderWishesUntilNextOpening() async throws {
        let app = model()
        await app.light.weather.settled()
        app.openForm(day: Self.june)
        app.toggleFormWish(.stars)
        try saveAndReopen(app)
        app.toggleFormWish(.sunset)               // поменяли пожелание: «Звёзды» остались, добавился закат
        var f = try #require(app.form)
        var w = app.formWarnings(f)
        #expect(w.top.isEmpty, "\(w.top.map(\.title))")
        #expect(w.underWishes == app.formWishWarning(f))
        #expect(w.underWishes != nil)
        app.toggleFormWish(.sunset)               // вернули как было — плашка всё равно под пожеланиями
        f = try #require(app.form)
        #expect(f.wishes == [.stars])
        w = app.formWarnings(f)
        #expect(w.top.isEmpty, "\(w.top.map(\.title))")
        #expect(w.underWishes?.title == Self.starsTitle)
        #expect(starsCount(w) == 1)
        try saveAndReopen(app)                    // следующее открытие — наверху
        w = app.formWarnings(try #require(app.form))
        #expect(w.top.map(\.title) == [Self.starsTitle])
        #expect(w.underWishes == nil)
    }

    // MARK: - Две беды сразу

    /// Наложение и «Звёзды»: пока форма открыта, наложение под временем, звёзды под пожеланиями (раньше была видна только
    /// одна плашка — наложение). Сохранили, открыли снова: обе наверху, сначала время, под ней погода.
    @Test func twoTroublesGiveTwoPlatesEachUnderItsBlock() async throws {
        let app = model()
        await app.light.weather.settled()
        app.openForm(day: Self.june)
        app.toggleFormWish(.stars)
        try addClash(app)                         // после пожелания: оно может сдвинуть время формы
        var f = try #require(app.form)
        let clash = try #require(app.formClashWarning(f))
        var w = app.formWarnings(f)
        #expect(w.top == [clash], "\(w.top.map(\.title))")
        #expect(w.underWishes?.title == Self.starsTitle)
        #expect(starsCount(w) == 1)
        try saveAndReopen(app)
        f = try #require(app.form)
        w = app.formWarnings(f)
        #expect(w.top.count == 2)
        #expect(w.top.first == app.formClashWarning(f), "первой — плашка про время")
        #expect(w.top.last?.title == Self.starsTitle, "под ней — про погоду")
        #expect(w.underWishes == nil)
        #expect(starsCount(w) == 1)
    }

    /// Встреча: пожеланий нет — плашка про время на месте, про погоду её нет нигде.
    @Test func meetingKeepsOnlyTheTimePlate() async throws {
        let app = model()
        await app.light.weather.settled()
        app.openForm(day: Self.june, mode: .meet)
        try addClash(app)
        let f = try #require(app.form)
        let w = app.formWarnings(f)
        #expect(w.top == [app.formClashWarning(f)].compactMap { $0 })
        #expect(w.top.count == 1)
        #expect(w.underWishes == nil)
    }
}
