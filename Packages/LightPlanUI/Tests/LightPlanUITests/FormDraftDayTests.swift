import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Шаг 28о (П5): «Съёмка» из календаря на 29 октября открывала форму на дне старого
/// черновика. Теперь, если день черновика другой, приложение спрашивает.
@MainActor
struct FormDraftDayTests {

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

    private let sept27 = CivilDate(year: 2026, month: 9, day: 27)
    private let oct29 = CivilDate(year: 2026, month: 10, day: 29)

    private func model(disk: Disk) -> AppModel {
        let app = AppModel(snapshot: Snapshot(), store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
        app.draftStore = disk
        return app
    }

    /// Черновик «27 сентября» с набранным текстом лежит на диске, форма закрыта.
    private func appWithDraft(_ disk: Disk, notes: String = "рано утром") -> AppModel {
        let app = model(disk: disk)
        app.openForm(day: sept27)
        app.form?.notes = notes
        app.closeForm()
        return app
    }

    @Test func draftOfAnotherDayAsksInsteadOfOpening() throws {
        let disk = Disk()
        let app = appWithDraft(disk)
        app.openForm(day: oct29)
        #expect(app.form == nil, "форма не открывается, пока человек не ответил")
        let ask = try #require(app.draftAsk)
        #expect(ask.draftDay == sept27 && ask.askedDay == oct29)
        #expect(disk.data != nil)
    }

    @Test func newShootOpensCleanOnPickedDayAndKeepsDraft() throws {
        let disk = Disk()
        let app = appWithDraft(disk)
        let kept = disk.data
        app.openForm(day: oct29)
        app.startNewOverDraft()
        let f = try #require(app.form)
        #expect(f.day == oct29 && f.notes == "" && !app.formIsDraft && app.draftAsk == nil)
        #expect(disk.data == kept, "выбор «новая» черновик не стирает")
        app.closeForm()
        #expect(disk.data == kept, "и пустая новая форма, закрытая крестиком, тоже")
        app.openForm(day: oct29)
        #expect(app.draftAsk != nil, "черновик жив — вопрос задаётся снова")
    }

    @Test func continueDraftOpensTheDraft() throws {
        let disk = Disk()
        let app = appWithDraft(disk)
        app.openForm(day: oct29)
        app.continueDraft()
        #expect(app.form?.day == sept27 && app.form?.notes == "рано утром" && app.formIsDraft && app.draftAsk == nil)
    }

    @Test func sameDayRestoresWithoutAsking() {
        let disk = Disk()
        let app = appWithDraft(disk)
        app.openForm(day: sept27)
        #expect(app.draftAsk == nil && app.formIsDraft && app.form?.notes == "рано утром")
    }

    @Test func draftWithoutTypedTextDoesNotAsk() throws {
        let disk = Disk()
        let app = model(disk: disk)
        app.openForm(day: sept27)
        let bare = try #require(app.form?.draftData())            // жанр и время без единого слова
        app.closeForm()
        disk.data = bare
        app.openForm(day: oct29)
        #expect(app.draftAsk == nil && app.form?.day == oct29 && !app.formIsDraft)
    }

    @Test func savingTheNewShootClearsTheDraft() throws {
        let disk = Disk()
        let app = appWithDraft(disk)
        app.openForm(day: oct29)
        app.startNewOverDraft()
        app.saveForm()
        #expect(disk.data == nil)
    }

    @Test func resetAfterContinueClearsTheDraft() {
        let disk = Disk()
        let app = appWithDraft(disk)
        app.openForm(day: oct29)
        app.continueDraft()
        app.resetDraft()
        #expect(disk.data == nil && app.form?.day == sept27 && app.form?.notes == "")
    }

    @Test func stripNamesTheDraftDay() throws {
        let app = appWithDraft(Disk())
        app.openForm(day: sept27)
        let f = try #require(app.form)
        let text = app.draftStripText(f)
        #expect(text.contains("Черновик восстановлен") && text.contains("27") && text.contains("сентября"), "\(text)")
    }

    @Test func questionNamesBothDays() throws {
        let app = appWithDraft(Disk())
        app.openForm(day: oct29)
        let ask = try #require(app.draftAsk)
        let q = app.draftAskTitle(ask)
        #expect(q.contains("27 сентября") && q.contains("29 октября"), "\(q)")
    }
}
