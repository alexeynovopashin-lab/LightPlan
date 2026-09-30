import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 28, шаг 5б: папка мудборда в хозяине приложения — открытие, разделы и поле,
/// выбор, «Убрать N», просмотрщик по картинкам в порядке сетки.
@MainActor
struct MoodboardFolderStateTests {

    private struct NoWeather: WeatherSource {
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            HourlyWeather(time: [], cloud: [], temperature: [], windSpeed: [], precipitation: [], weatherCode: [])
        }
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

    private static let day = CivilDate(year: 2026, month: 10, day: 1)

    private func s(_ id: String, _ kind: String, tags: [String] = [], url: String? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["id": .string(id), "k": .string(kind), "tags": .array(tags.map { .string($0) })]
        if kind == "img" { o["im"] = .string(id) }
        if let url { o["url"] = .string(url) }
        return .object(o)
    }

    private func board(_ id: String, _ kind: String, _ items: [String], sid: String? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["id": .string(id), "kind": .string(kind), "genre": .string("wedding"),
                                      "items": .array(items.map { .string($0) })]
        if let sid { o["sid"] = .string(sid) }
        return .object(o)
    }

    /// Съёмка «w» с подборкой «sh» (a-ссылка, b, c — картинки, d — в «sh» и в жанровой «tpl»).
    private func model() -> AppModel {
        var snap = Snapshot()
        snap.sessions = [Session(id: "w", kind: .shoot, day: Self.day, start: 600, end: 1380, duration: 780, genre: .wedding)]
        snap.extra["shots"] = .array([
            s("a", "link", tags: ["couple"], url: "https://www.pinterest.com/pin/1"),
            s("b", "img", tags: ["couple", "bride"]), s("c", "img", tags: ["details"]), s("d", "img"),
        ])
        snap.extra["boards"] = .array([board("sh", "shoot", ["a", "b", "c", "d"], sid: "w"), board("tpl", "tpl", ["d"])])
        let now = ISO8601DateFormatter().date(from: "2026-09-30T09:00:00+03:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func scene(_ app: AppModel) -> MbFolderScene { app.mbFolderScene(app.mbLibrary())! }

    // MARK: вход

    @Test func openingAFolderShowsItsFramesSectionsAndLabel() {
        let app = model(); app.openMbFolder(boardId: "sh")
        let sc = scene(app)
        #expect(app.mb.isOpen && app.mb.folder == "sh")
        #expect(sc.list.map(\.id) == ["a", "b", "c", "d"])
        #expect(sc.sections.map(\.tag) == ["couple", "bride", "details"])
        #expect(sc.label == .count(4))
        #expect(sc.genre == "wedding")
    }

    @Test func shootFolderHeaderUsesTypeDateAndYear() {
        let app = model(); app.openMbFolder(boardId: "sh")
        let sc = scene(app)
        #expect(sc.sub.hasPrefix("Свадьба · 1 окт"))
        #expect(sc.sub.contains("2026"))
    }

    @Test func genreFolderHeaderIsGenreNameAndSetWord() {
        let app = model(); app.openMbFolder(boardId: "tpl")
        let sc = scene(app)
        #expect(sc.title == "Свадьба")
        #expect(sc.sub == app.lexicon.t("mb.genreSet"))
    }

    @Test func openingFolderClearsForeignQuerySectionAndPick() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.mb.folderQuery = "пара"; app.mb.folderTag = "couple"; app.mb.folderSearchOpen = true
        app.toggleMbPicking(); app.toggleMbPick("a")
        app.closeMbFolder(); app.openMbFolder(boardId: "tpl")
        #expect(app.mb.folderQuery.isEmpty && app.mb.folderTag == nil && !app.mb.folderSearchOpen && app.mb.pick == nil)
    }

    // MARK: разделы и поле

    @Test func sectionChipFiltersAndSecondTapClearsIt() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.setMbFolderTag("couple")
        #expect(scene(app).shown.map(\.id) == ["a", "b"])
        #expect(scene(app).label == .some(shown: 2, total: 4))
        app.setMbFolderTag("couple")
        #expect(scene(app).shown.count == 4)
    }

    @Test func lensClosesAndClearsTheField() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.toggleMbFolderSearch()
        app.mb.folderQuery = "pinterest"
        #expect(scene(app).shown.map(\.id) == ["a"])
        app.toggleMbFolderSearch()
        #expect(app.mb.folderQuery.isEmpty && !app.mb.folderSearchOpen)
        #expect(scene(app).shown.count == 4)
    }

    // MARK: выбор и «Убрать N»

    @Test func selectAllUnderFilterPicksOnlyWhatIsShown() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.setMbFolderTag("couple")
        app.toggleMbPicking()
        app.toggleMbPickAll(scene(app).shown)
        #expect(app.mb.pick?.ids == ["a", "b"])
        #expect(scene(app).label == .picked(2))
    }

    @Test func doneEndsPickingAndKeepsFrames() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.toggleMbPicking(); app.toggleMbPick("a")
        app.toggleMbPicking()
        #expect(app.mb.pick == nil && scene(app).list.count == 4)
    }

    @Test func removePickedTakesFramesOffAndDropsOnlyOrphans() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.toggleMbPicking(); app.toggleMbPick("a"); app.toggleMbPick("d")
        app.mbRemovePicked()
        let lib = app.mbLibrary()
        #expect(lib.board("sh")?.items == ["b", "c"])
        #expect(lib.shot("a") == nil)                     // «a» лежал только тут — ушёл совсем
        #expect(lib.shot("d") != nil)                     // «d» лежит ещё в жанровой — остался
        #expect(app.mb.pick == nil && app.mb.folder == "sh")
    }

    @Test func removingAllFromShootFolderClosesItBecauseTheBoardIsGone() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.toggleMbPicking()
        app.toggleMbPickAll(scene(app).shown)
        app.mbRemovePicked()
        #expect(app.mbLibrary().board("sh") == nil)
        #expect(app.mb.folder == nil)
    }

    @Test func removingAllFromGenreFolderKeepsItEmpty() {
        let app = model(); app.openMbFolder(boardId: "tpl")
        app.toggleMbPicking(); app.toggleMbPick("d")
        app.mbRemovePicked()
        #expect(app.mb.folder == "tpl" && scene(app).list.isEmpty && scene(app).label == .hidden)
    }

    @Test func leavingFolderPrunesEmptyShootBoardButNotGenreOne() {
        let app = model()
        app.mbEdit { lib, _ in lib.take("a", from: "sh"); lib.take("b", from: "sh"); lib.take("c", from: "sh"); lib.take("d", from: "sh") }
        app.openMbFolder(boardId: "sh"); app.closeMbFolder()
        #expect(app.mbLibrary().board("sh") == nil)
        app.mbEdit { lib, _ in lib.take("d", from: "tpl") }
        app.openMbFolder(boardId: "tpl"); app.closeMbFolder()
        #expect(app.mbLibrary().board("tpl") != nil)
    }

    // MARK: просмотрщик

    @Test func tapOnPictureOpensViewerOverPicturesInScreenOrder() {
        let app = model(); app.openMbFolder(boardId: "sh")
        let r = app.openMbFrame("c", shown: scene(app).shown)
        #expect(r == .viewer)
        #expect(app.mb.viewerIds == ["b", "c", "d"])       // ссылка «a» в списке просмотрщика нет
        #expect(app.mbViewerFrameId == "c" && app.mb.pager?.counter == "2 / 3")
    }

    @Test func viewerFollowsFilteredOrderedGrid() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.mbEdit { lib, _ in if let i = lib.boards.firstIndex(where: { $0.id == "sh" }) { lib.boards[i].sort = 1 } }
        _ = app.openMbFrame("b", shown: scene(app).shown)   // «новые сверху»: d, c, b, a
        #expect(app.mb.viewerIds == ["d", "c", "b"] && app.mbViewerFrameId == "b")
    }

    @Test func swipeTurnsPagesAndCloseEndsViewer() {
        let app = model(); app.openMbFolder(boardId: "sh")
        _ = app.openMbFrame("b", shown: scene(app).shown)
        app.mbViewerSwipe(dx: -RefPager.pageShift, dy: 0)
        #expect(app.mbViewerFrameId == "c")
        app.closeMbViewer()
        #expect(app.mb.pager == nil && app.mbViewerFrameId == nil)
    }

    @Test func tapOnBareLinkGivesItsAddressAndNoViewer() {
        let app = model(); app.openMbFolder(boardId: "sh")
        #expect(app.openMbFrame("a", shown: scene(app).shown) == .url(URL(string: "https://www.pinterest.com/pin/1")!))
        #expect(app.mb.pager == nil)
    }

    @Test func closingFolderEndsViewerAndPicking() {
        let app = model(); app.openMbFolder(boardId: "sh")
        _ = app.openMbFrame("b", shown: scene(app).shown)
        app.closeMbFolder()
        #expect(app.mb.pager == nil && app.mb.folder == nil)
    }
}
