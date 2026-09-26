import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Итерация 23: форма открывается, черновик переживает закрытие приложения,
/// «Сохранить» кладёт запись в снимок.
@MainActor
struct FormFlowTests {

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
    /// «Диск» в памяти: то, что пережило бы перезапуск.
    private final class Disk: DraftStoring, @unchecked Sendable {
        var data: Data?
        func load() -> Data? { data }
        func save(_ data: Data?) { self.data = data }
    }

    private func model(disk: Disk, snapshot: Snapshot = Snapshot()) -> AppModel {
        let app = AppModel(snapshot: snapshot, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
        app.draftStore = disk
        return app
    }

    @Test func opensOnLastGenreWithPresetAndSaves() throws {
        let app = model(disk: Disk())
        app.openForm(day: CivilDate(year: 2026, month: 10, day: 3))
        #expect(app.form?.genre == .portrait && app.form?.duration == 60)
        app.pickFormGenre(.wedding)
        #expect(app.form?.duration == 480 && app.form?.persons.count == 2)
        app.form?.persons[0].name = "Елена Иванова"
        let s = try #require(app.saveForm())
        #expect(app.form == nil)
        #expect(app.sessions.contains { $0.id == s.id && $0.genre == .wedding && $0.contact == "Елена" })
        // Следующая форма открывается на том же жанре
        app.openForm()
        #expect(app.form?.genre == .wedding)
    }

    @Test func draftSurvivesRestartAndIsClearedBySave() throws {
        let disk = Disk()
        let first = model(disk: disk)
        first.openForm(day: CivilDate(year: 2026, month: 10, day: 3))
        first.form?.notes = "рано утром"
        first.closeForm()                              // крестик пишет черновик сразу
        #expect(disk.data != nil)

        let second = model(disk: disk)                 // «после перезапуска»
        second.openForm(day: CivilDate(year: 2026, month: 10, day: 9))
        #expect(second.formIsDraft && second.form?.notes == "рано утром")
        #expect(second.form?.day == CivilDate(year: 2026, month: 10, day: 3), "день черновика главнее кнопки")
        second.saveForm()
        #expect(disk.data == nil)
        #expect(second.sessions.last?.notes == "рано утром")
    }

    @Test func emptyFormLeavesNoDraft() {
        let disk = Disk()
        let app = model(disk: disk)
        app.openForm(day: CivilDate(year: 2026, month: 10, day: 3))
        app.closeForm()
        #expect(disk.data == nil, "жанр, время и засев черновика не делают")
    }

    @Test func draftResetStartsClean() {
        let disk = Disk()
        let app = model(disk: disk)
        app.openForm(day: CivilDate(year: 2026, month: 10, day: 3))
        app.form?.notes = "x"
        app.closeForm()
        app.openForm()
        app.resetDraft()
        #expect(disk.data == nil && app.form?.notes == "" && !app.formIsDraft)
    }

    @Test func editingChangesTheRecordNotAddsOne() throws {
        let app = model(disk: Disk())
        app.openForm(day: CivilDate(year: 2026, month: 10, day: 3))
        let s = try #require(app.saveForm())
        let count = app.sessions.count
        app.openForm(editing: s.id)
        app.form?.notes = "правка"
        app.saveForm()
        #expect(app.sessions.count == count && app.sessions.first { $0.id == s.id }?.notes == "правка")
    }

    // MARK: хвосты 23 (итерация 24, шаг 1)

    @Test func repeatSavesCopiesOnce() throws {
        let app = model(disk: Disk())
        app.openForm(day: CivilDate(year: 2026, month: 10, day: 3))
        app.setFormRepeat(.week)
        app.setFormRepeatCount(3)
        let open = try #require(app.form)
        #expect(app.formRepeatSummary(open) != nil)
        let s = try #require(app.saveForm())
        let group = try #require(s.repeatInfo?.group)
        #expect(app.sessions.filter { $0.repeatInfo?.group == group }.map(\.day)
                == [3, 10, 17].map { CivilDate(year: 2026, month: 10, day: $0) })
        // Правка карточки из группы копий не множит.
        app.openForm(editing: s.id)
        let again = try #require(app.form)
        #expect(!again.repeatEditable && app.formRepeatInfo(again) != nil)
        app.saveForm()
        #expect(app.sessions.count == 3)
    }

    @Test func deleteFromFormClosesItAndRemovesRecord() throws {
        let app = model(disk: Disk())
        app.openForm(day: CivilDate(year: 2026, month: 10, day: 3))
        let s = try #require(app.saveForm())
        app.openForm(editing: s.id)
        app.deleteFormRecord()
        #expect(app.form == nil && !app.sessions.contains { $0.id == s.id })
    }

    @Test func lastGenreCannotBeSwitchedOff() {
        let app = model(disk: Disk())
        for g in Genre.allCases.dropFirst() { app.toggleGenre(g) }
        #expect(app.enabledGenres == [Genre.allCases[0]])
        app.toggleGenre(Genre.allCases[0])
        #expect(app.enabledGenres == [Genre.allCases[0]])
    }

    @Test func wheelShowsLightMinuteBesideTheStep() {
        #expect(FormTimeWheel.minutes(step: 5, current: 37) == [0, 5, 10, 15, 20, 25, 30, 35, 37, 40, 45, 50, 55])
        #expect(FormTimeWheel.minutes(step: 15, current: 30) == [0, 15, 30, 45])
        #expect(FormTimeWheel.hourLabel(7, twelveHour: false, language: "ru") == "07")
        #expect(FormTimeWheel.hourLabel(19, twelveHour: true, language: "en").hasPrefix("7"))
    }

    @Test func newOrgIsCreatedAndChosen() throws {
        let app = model(disk: Disk())
        app.openForm(day: CivilDate(year: 2026, month: 10, day: 3))
        app.pickFormGenre(.report)
        app.setFormOrg(app.addOrg(name: "Вега"))
        app.form?.orderPerson = "Мария"
        let s = try #require(app.saveForm())
        #expect(s.orgId != nil && s.contact == "Вега · Мария")
        #expect(app.orgs.contains { $0.name == "Вега" })
    }

    // MARK: - Профиль: телефон и прежние ID

    @Test func phoneChainKeepsPreviousIds() {
        let app = model(disk: Disk())
        app.setMyPhone("8 916 111-11-11"); app.commitMyPhone()
        #expect(app.myAppId == "id79161111111" && app.myPreviousIds.isEmpty)
        app.setMyPhone("8 916 222-22-22"); app.commitMyPhone()
        #expect(app.myAppId == "id79162222222" && app.myPreviousIds.map(\.was) == ["id79161111111"])
        app.setMyPhone("8 916 333-33-33"); app.commitMyPhone()
        #expect(app.myPreviousIds.map(\.was) == ["id79162222222", "id79161111111"], "новые первыми")
        app.setMyPhone("8 916 111-11-11"); app.commitMyPhone()      // вернулись к первому — цепочка срезана
        #expect(app.myPreviousIds.isEmpty)
    }

    @Test func cityNumberGivesNoId() {
        let app = model(disk: Disk())
        app.setMyPhone("8 495 123-45-67"); app.commitMyPhone()
        #expect(app.myAppId.isEmpty)
    }
}
