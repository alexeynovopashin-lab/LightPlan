import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 28, шаг 5в: листы мудборда в хозяине приложения — «Новая подборка», «Добавить в…»,
/// «Переместить…», удаление и слияние из папки, обложка, порядок, имя, лист кадра и теги.
@MainActor
struct MoodboardSheetsStateTests {

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

    private func lib(_ app: AppModel) -> RefLibrary { app.mbLibrary() }
    private func scene(_ app: AppModel) -> MbFolderScene { app.mbFolderScene(app.mbLibrary())! }

    // MARK: «Новая подборка»

    @Test func newPickAsksForNameWhenGenreHasFolders() {
        let app = model()
        app.mbNewPick(.wedding)
        #expect(app.mb.sheet == .newFolder(genre: "wedding"))
        #expect(lib(app).folders(ofGenre: "wedding").count == 1)      // ничего не записано до имени
    }

    @Test func newPickOnGenreWithoutFolderCreatesEmptyOneAndOpensIt() {
        let app = model()
        app.mbNewPick(.street)
        let made = lib(app).folders(ofGenre: "street")
        #expect(made.count == 1 && made[0].items.isEmpty && made[0].name == nil)
        #expect(app.mb.sheet == nil && app.mb.folder == made[0].id)
    }

    @Test func createFolderWritesNamedFolderAndOpensIt() {
        let app = model()
        app.mb.sheet = .newFolder(genre: "wedding")
        app.mbCreateFolder(genre: "wedding", name: "  на море ")
        let f = lib(app).folders(ofGenre: "wedding")
        #expect(f.count == 2 && f[1].name == "на море")
        #expect(app.mb.folder == f[1].id && app.mb.sheet == nil)
    }

    @Test func createFolderWithEmptyNameWritesNothing() {
        let app = model()
        app.mb.sheet = .newFolder(genre: "wedding")
        app.mbCreateFolder(genre: "wedding", name: "   ")
        #expect(lib(app).folders(ofGenre: "wedding").count == 1)
        #expect(app.mb.folder == nil && app.mb.sheet == nil)
    }

    // MARK: «Добавить в…» / «Переместить…»

    @Test func moveFromPickedPutsFramesIntoTargetAndTakesThemFromFolder() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.toggleMbPicking(); app.toggleMbPick("b"); app.toggleMbPick("c")
        app.openMbAddPicked(move: true)
        guard case .add(let mode)? = app.mb.sheet else { Issue.record("лист не открылся"); return }
        #expect(mode.many == ["b", "c"] && mode.move && mode.from == "sh")
        let rows = app.mbAddRows(mode, lib(app))
        #expect(!rows.contains { $0.target == .board("sh") })                 // текущей папки в списке нет
        app.mbAddTap(rows.first { $0.target == .board("tpl") }!, mode: mode)
        #expect(lib(app).board("tpl")?.items == ["d", "b", "c"])
        #expect(lib(app).board("sh")?.items == ["a", "d"])
        #expect(lib(app).shots.count == 4)                                    // кадры остались, копий нет
        #expect(app.mb.sheet == nil && app.mb.pick == nil && app.mb.folder == "sh")
    }

    @Test func addFromPickedKeepsFramesInFolder() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.toggleMbPicking(); app.toggleMbPick("b")
        app.openMbAddPicked(move: false)
        guard case .add(let mode)? = app.mb.sheet else { Issue.record("лист не открылся"); return }
        app.mbAddTap(app.mbAddRows(mode, lib(app)).first { $0.target == .board("tpl") }!, mode: mode)
        #expect(lib(app).board("tpl")?.items == ["d", "b"] && lib(app).board("sh")?.items == ["a", "b", "c", "d"])
    }

    @Test func movingEverythingOutOfShootFolderClosesTheEmptiedFolder() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.toggleMbPicking(); app.toggleMbPickAll(scene(app).shown)
        app.openMbAddPicked(move: true)
        guard case .add(let mode)? = app.mb.sheet else { Issue.record("лист не открылся"); return }
        app.mbAddTap(app.mbAddRows(mode, lib(app)).first { $0.target == .board("tpl") }!, mode: mode)
        #expect(lib(app).board("sh") == nil)                                   // опустевшая съёмочная подборка исчезла
        #expect(app.mb.folder == nil)
        #expect(lib(app).board("tpl")?.items == ["d", "a", "b", "c"])
    }

    @Test func moveIntoNewGenreCreatesItsMainFolder() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.toggleMbPicking(); app.toggleMbPick("c")
        app.openMbAddPicked(move: true)
        guard case .add(let mode)? = app.mb.sheet else { Issue.record("лист не открылся"); return }
        let free = app.mbAddRows(mode, lib(app)).first { $0.target == .newGenre("street") }
        #expect(free != nil)
        app.mbAddTap(free!, mode: mode)
        let made = lib(app).folders(ofGenre: "street")
        #expect(made.count == 1 && made[0].items == ["c"])
        #expect(lib(app).board("sh")?.items == ["a", "b", "d"])
    }

    @Test func singleShotTapPutsThenTakesWithoutAskingWhenItLiesElsewhere() {
        let app = model()
        app.openMbAdd(shot: "c")
        let mode = MbAddMode(shot: "c")
        let rows = app.mbAddRows(mode, lib(app))
        #expect(rows.first { $0.target == .board("sh") }?.checked == true)
        #expect(rows.first { $0.target == .board("tpl") }?.checked == false)
        app.mbAddTap(rows.first { $0.target == .board("tpl") }!, mode: mode)      // положили
        #expect(lib(app).board("tpl")?.items == ["d", "c"])
        let again = app.mbAddRows(mode, lib(app))
        app.mbAddTap(again.first { $0.target == .board("tpl") }!, mode: mode)     // сняли: «c» ещё в съёмке
        #expect(lib(app).board("tpl")?.items == ["d"])
        #expect(lib(app).shot("c") != nil)
        #expect(app.mb.sheet == .add(mode))                                       // лист остался
    }

    @Test func removingTheLastPlaceOfAShotAsksFirstAndThenDropsIt() {
        let app = model()
        app.openMbAdd(shot: "a")
        let mode = MbAddMode(shot: "a")
        app.mbAddTap(app.mbAddRows(mode, lib(app)).first { $0.target == .board("sh") }!, mode: mode)
        #expect(app.mb.sheet == .loneConfirm(shot: "a", board: "sh"))
        #expect(lib(app).shot("a") != nil && lib(app).board("sh")?.items.contains("a") == true)   // пока ничего не тронуто
        app.mbConfirmLone(shot: "a", board: "sh")
        #expect(lib(app).shot("a") == nil && lib(app).board("sh")?.items == ["b", "c", "d"])
        #expect(app.mb.sheet == nil)
    }

    // MARK: карточка, меню

    @Test func boardCardSubtitleCountsFramesThatLeaveWithTheBoard() {
        let app = model()
        #expect(app.mbBoardCardSub(lib(app).board("sh")!) == "4 кадра · 3 только здесь")   // «d» лежит и в жанровой
        #expect(app.mbBoardCardSub(lib(app).board("tpl")!) == "1 кадр")
    }

    @Test func deleteFromInsideFolderClosesItAndDropsOnlyLoneFrames() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.toggleMbPicking()
        app.openMbBoardCard("sh")
        app.mbConfirmDelete("sh")
        #expect(lib(app).board("sh") == nil && app.mb.folder == nil && app.mb.pick == nil && app.mb.sheet == nil)
        #expect(lib(app).shots.map(\.id) == ["d"])                                // «d» лежит ещё в жанровой
    }

    @Test func mergeFromInsideFolderClosesItAndMovesFrames() {
        let app = model()
        var extra = app.snapshot.extra
        var l = lib(app)
        l.boards.append(RefBoard(id: "t2", kind: .tpl, genre: "wedding", items: ["a"], name: "На море"))
        l.write(into: &extra); app.snapshot.extra = extra
        app.openMbFolder(boardId: "t2")
        app.mb.sheet = .mergeConfirm(from: "t2", to: "tpl")
        app.mbConfirmMerge(from: "t2", into: "tpl")
        #expect(lib(app).board("t2") == nil && app.mb.folder == nil && app.mb.sheet == nil)
        #expect(lib(app).board("tpl")?.items == ["d", "a"])
    }

    @Test func mergeOffersUndoAndTakingItBringsTheBoardAndOldFramesBack() {
        let app = model()
        var extra = app.snapshot.extra
        var l = lib(app)
        l.boards.append(RefBoard(id: "t2", kind: .tpl, genre: "wedding", items: ["a"], name: "На море"))
        l.write(into: &extra); app.snapshot.extra = extra
        let before = lib(app).boards
        app.mbConfirmMerge(from: "t2", into: "tpl")
        #expect(app.undo != nil && app.undo?.text.contains("На море") == false)   // в подписи — целевая, не исчезнувшая
        #expect(lib(app).board("t2") == nil && lib(app).board("tpl")?.items == ["d", "a"])
        app.takeUndo()
        let shape = { (bs: [RefBoard]) in bs.map { [$0.id, $0.name ?? "", $0.items.joined(separator: ",")] } }
        #expect(shape(lib(app).boards) == shape(before) && app.undo == nil)          // откат — свежая правка: отметки `mt` новые
        #expect(lib(app).board("tpl")?.mt != before.first { $0.id == "tpl" }?.mt)
    }

    @Test func mergeOfAlreadyPresentFramesSaysSoAndStillOffersUndo() {
        let app = model()
        var extra = app.snapshot.extra
        var l = lib(app)
        l.boards.append(RefBoard(id: "t2", kind: .tpl, genre: "wedding", items: ["d"], name: "Копия"))   // «d» уже в жанровой
        l.write(into: &extra); app.snapshot.extra = extra
        app.mbConfirmMerge(from: "t2", into: "tpl")
        #expect(app.undo?.text == app.lexicon.t("mb.mergedIntoNone", ["name": app.mbBoardTitle(lib(app).board("tpl")!)]))
        app.takeUndo()
        #expect(lib(app).board("t2")?.items == ["d"])
    }

    @Test func tagsRowOfViewerOpensTheFrameSheetOverTheView() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.openMbItem(shot: "b", overView: true)
        #expect(app.mb.sheet == .item(shot: "b", board: "sh", overView: true))
    }

    @Test func menuSheetOfShootFolderHasNoNewFolderAndNoMerge() {
        let app = model()
        let l = lib(app)
        let b = l.board("sh")!
        #expect(MbSheets.menu(b, frames: 4, mergeTargets: MbSheets.mergeTargets(of: b, in: l).count)
                == [.sort, .cover, .pick, .rename, .delete])
    }

    @Test func sortRenameAndCoverAreWrittenAndCloseTheSheet() {
        let app = model()
        app.mb.sheet = .menu("tpl")
        app.mbSetSort(2, of: "tpl")
        #expect(lib(app).board("tpl")?.sort == 2 && app.mb.sheet == nil)
        app.mbRename("tpl", to: " Золото ")
        #expect(lib(app).board("tpl")?.name == "Золото")
        app.mbRename("tpl", to: "")
        #expect(lib(app).board("tpl")?.name == nil)
        app.mbSetCover("d", of: "tpl")
        #expect(lib(app).board("tpl")?.cover == "d")
        app.mbSetCover(nil, of: "tpl")
        #expect(lib(app).board("tpl")?.cover == nil)
        #expect(lib(app).coverCandidates("sh").map(\.id) == ["b", "c", "d"])      // ссылка без картинки обложкой не бывает
    }

    // MARK: лист кадра

    @Test func tagsToggleByCodeAndTypedWordBecomesKnownCode() {
        let app = model()
        app.mbToggleTag("couple", on: "b")
        #expect(lib(app).shot("b")?.tags == ["bride"])
        app.mbToggleTag("couple", on: "b")
        #expect(lib(app).shot("b")?.tags == ["bride", "couple"])
        app.mbAddTypedTag(" Невеста", to: "c")
        app.mbAddTypedTag("Закат", to: "c")
        #expect(lib(app).shot("c")?.tags == ["details", "bride", "закат"])
    }

    @Test func itemSheetMoveToGenreKeepsFrameInShoot() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.openMbItem(shot: "c")
        #expect(app.mb.sheet == .item(shot: "c", board: "sh", overView: false))
        app.mbItemToGenre(shot: "c", genre: "wedding")
        #expect(lib(app).board("tpl")?.items == ["d", "c"] && lib(app).board("sh")?.items.contains("c") == true)
        #expect(app.mb.sheet == nil)
    }

    @Test func itemSheetGenreFollowsTheShootNotTheGenreStoredOnTheBoard() {
        let app = model()
        #expect(app.mbItemToGenreTarget(lib(app).board("sh")!) == "wedding")
        app.snapshot.sessions[0].genre = .portrait                       // жанр съёмки поменяли, подборка помнит старый
        #expect(lib(app).board("sh")?.genre == "wedding")
        #expect(app.mbItemToGenreTarget(lib(app).board("sh")!) == "portrait")
        #expect(app.mbItemToGenreTarget(lib(app).board("tpl")!) == nil)  // у жанровой папки строки нет
    }

    @Test func itemSheetRemoveTakesFrameOutAndClosesViewer() {
        let app = model(); app.openMbFolder(boardId: "sh")
        app.openMbItem(shot: "c")
        app.mb.pager = RefPager(count: 3, start: 1); app.mb.viewerIds = ["b", "c", "d"]
        app.mbItemRemove(shot: "c", board: "sh")
        #expect(lib(app).board("sh")?.items == ["a", "b", "d"] && lib(app).shot("c") == nil)    // «c» больше нигде не лежал
        #expect(app.mb.pager == nil && app.mb.viewerIds.isEmpty && app.mb.sheet == nil && app.mb.folder == "sh")
    }
}
