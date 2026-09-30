import Testing
import LightPlanCore
@testable import LightPlanDomain

/// Итерация 28, шаг 5б: папка мудборда — разделы, поиск, порядок, выбор, подписи, «Убрать N»
/// (веб `renderMbFolder`, `mbPickToggle`, `mbSelDel`).
struct MoodboardFolderTests {
    private func name(_ code: String) -> String {
        ["couple": "Пара", "bride": "Невеста", "walk": "Прогулка", "details": "Детали"][code] ?? code
    }

    /// Пять кадров: две ссылки без картинки, два фото, кадр без слов.
    private func list() -> [RefFrame] {
        [
            RefFrame(id: "a", kind: .link, url: "https://www.pinterest.com/pin/1", tags: ["walk", "couple"]),
            RefFrame(id: "b", kind: .img, im: "b.jpg", tags: ["details"]),
            RefFrame(id: "c", kind: .link, url: "https://example.org/wed/idea", tags: ["couple"]),
            RefFrame(id: "d", kind: .img, im: "d.jpg", tags: ["bride", "couple"], extra: ["name": .string("Утро у окна")]),
            RefFrame(id: "e", kind: .img, im: "e.jpg"),
        ]
    }

    private func ids(_ l: [RefFrame]) -> [String] { l.map(\.id) }

    // MARK: разделы

    @Test func sectionsAreOnlyUsedWordsGenreFirstWithCounts() {
        let s = MbFolderView.sections(list(), genre: "wedding")
        // порядок слов свадьбы: couple, bride, walk, details (у жанра: gathering, couple, bride, groom, walk, evening, details)
        #expect(s.map(\.tag) == ["couple", "bride", "walk", "details"])
        #expect(s.map(\.n) == [3, 1, 1, 1])
    }

    @Test func foreignWordsGoAfterGenreWords() {
        var l = list(); l.append(RefFrame(id: "z", tags: ["моя-идея"]))
        #expect(MbFolderView.sections(l, genre: "wedding").last?.tag == "моя-идея")
    }

    @Test func noWordsNoSections() {
        #expect(MbFolderView.sections([RefFrame(id: "x")], genre: "wedding").isEmpty)
    }

    @Test func russianLegacyWordCountsUnderItsCode() {
        let l = [RefFrame(id: "x", tags: ["Пара"]), RefFrame(id: "y", tags: ["couple"])]
        #expect(MbFolderView.sections(l, genre: "wedding") == [.init(tag: "couple", n: 2)])
    }

    @Test func activeTagResetsWhenItsSectionIsGone() {
        let s = MbFolderView.sections(list(), genre: "wedding")
        #expect(MbFolderView.activeTag("bride", in: s) == "bride")
        #expect(MbFolderView.activeTag("groom", in: s) == nil)
        #expect(MbFolderView.activeTag(nil, in: s) == nil)
    }

    // MARK: показанное

    @Test func sectionFilterKeepsFramesWithThatWord() {
        let r = MbFolderView.shown(list(), tag: "couple", query: "", sort: 0, tagName: name)
        #expect(ids(r) == ["a", "c", "d"])
    }

    @Test func queryFindsWordNoteAndLinkAddress() {
        func q(_ s: String) -> [String] { ids(MbFolderView.shown(list(), tag: nil, query: s, sort: 0, tagName: name)) }
        #expect(q("невест") == ["d"])                // название слова, не код
        #expect(q("окна") == ["d"])                  // заметка кадра
        #expect(q("pinterest") == ["a"])             // сайт ссылки
        #expect(q("wed/idea") == ["c"])              // адрес ссылки
        #expect(q("  ПАРА ") == ["a", "c", "d"])     // регистр и пробелы
        #expect(q("нет такого").isEmpty)
    }

    @Test func tagAndQueryWorkTogether() {
        #expect(ids(MbFolderView.shown(list(), tag: "couple", query: "pinterest", sort: 0, tagName: name)) == ["a"])
    }

    @Test func sortNewestFirstReversesAndManualKeepsOrder() {
        #expect(ids(MbFolderView.shown(list(), tag: nil, query: "", sort: 0, tagName: name)) == ["a", "b", "c", "d", "e"])
        #expect(ids(MbFolderView.shown(list(), tag: nil, query: "", sort: 1, tagName: name)) == ["e", "d", "c", "b", "a"])
    }

    @Test func sortByWordUsesFirstTranslatedWordAndPutsBareFramesLast() {
        // первые слова по алфавиту: a — «Пара»/«Прогулка» → «Пара»; b — «Детали»; c — «Пара»; d — «Невеста»; e — нет
        let r = MbFolderView.shown(list(), tag: nil, query: "", sort: 2, tagName: name)
        #expect(ids(r) == ["b", "d", "a", "c", "e"])   // Детали, Невеста, Пара(a), Пара(c) — как в подборке, без слова — в конец
    }

    // MARK: подписи и плитки

    @Test func gridLabelByState() {
        #expect(MbFolderView.gridLabel(total: 0, shown: 0, filtered: false, picked: nil) == .hidden)
        #expect(MbFolderView.gridLabel(total: 10, shown: 10, filtered: false, picked: nil) == .count(10))
        #expect(MbFolderView.gridLabel(total: 10, shown: 3, filtered: true, picked: nil) == .some(shown: 3, total: 10))
        #expect(MbFolderView.gridLabel(total: 10, shown: 3, filtered: true, picked: 2) == .picked(2))
        #expect(MbFolderView.gridLabel(total: 10, shown: 10, filtered: false, picked: 0) == .picked(0))
    }

    @Test func addTileOnlyInCalmUnfilteredNonEmptyGrid() {
        #expect(MbFolderView.showsAddTile(filtered: false, picking: false, shownCount: 3))
        #expect(!MbFolderView.showsAddTile(filtered: true, picking: false, shownCount: 3))
        #expect(!MbFolderView.showsAddTile(filtered: false, picking: true, shownCount: 3))
        #expect(!MbFolderView.showsAddTile(filtered: false, picking: false, shownCount: 0))
    }

    @Test func bareLinkIsSquareOtherTilesFollowRatio() {
        let l = list()
        #expect(MbFolderView.tileHeight(l[0], width: 158) == 158)                       // ссылка без картинки
        #expect(MbFolderView.tileHeight(l[1], width: 158) == 158 * 0.75)                 // размеров нет — 4:3
        let tall = RefFrame(id: "t", im: "t.jpg", w: 100, h: 200)
        #expect(MbFolderView.tileHeight(tall, width: 158) == 316)
        let linkWithPic = RefFrame(id: "u", kind: .link, im: "u.jpg", url: "https://a.b/c")
        #expect(!MbFolderView.isBareLink(linkWithPic))
    }

    /// Ревью GPT к e86c946: у веба `!im` охватывает и пустую строку — ссылка с `im: ""` тоже плитка-надпись.
    @Test func linkWithEmptyImageNameIsStillBareLink() {
        let empty = RefFrame(id: "e", kind: .link, im: "", url: "https://a.b/c")
        #expect(MbFolderView.isBareLink(empty))
        #expect(MbFolderView.tileHeight(empty, width: 158) == 158)
    }

    @Test func viewerListIsPicturesInScreenOrder() {
        let r = MbFolderView.shown(list(), tag: nil, query: "", sort: 1, tagName: name)
        #expect(ids(MbFolderView.viewerList(r)) == ["e", "d", "b"])
    }

    @Test func framesOfBoardSkipMissingShotsAndKeepBoardOrder() {
        let b = RefBoard(id: "x", kind: .tpl, items: ["c", "ghost", "a"])
        #expect(ids(MbFolderView.frames(of: b, in: list())) == ["c", "a"])
    }

    // MARK: выбор

    @Test func pickToggleAddsAndRemoves() {
        var p = MbPick()
        p.toggle("a"); p.toggle("b")
        #expect(p.ids == ["a", "b"] && p.count == 2)
        p.toggle("a")
        #expect(p.ids == ["b"] && !p.contains("a"))
    }

    @Test func selectAllMeansWhatIsOnScreenAndSecondTapClears() {
        var p = MbPick(ids: ["z"])                      // z — вне экрана (под фильтром)
        let shown = ["a", "b", "c"]
        #expect(!p.allOn(shown: shown))
        p.toggleAll(shown: shown)
        #expect(p.ids == shown)                          // выбрано ровно видимое, «z» не остаётся
        #expect(p.allOn(shown: shown))
        p.toggleAll(shown: shown)
        #expect(p.ids.isEmpty)
    }

    @Test func allOnIsFalseForEmptyScreen() {
        #expect(!MbPick().allOn(shown: []))
    }

    // MARK: «Убрать N»

    @Test func removeTakesFramesOffBoardAndDropsOnlyOrphans() {
        var lib = RefLibrary(shots: list(), boards: [
            RefBoard(id: "sh", kind: .shoot, sid: "s1", items: ["a", "b", "c"]),
            RefBoard(id: "w", kind: .tpl, genre: "wedding", items: ["b"]),
        ])
        let gone = lib.remove(["a", "b"], from: "sh")
        #expect(gone == ["a"])                                   // b лежит ещё в «w» — остаётся в фонде
        #expect(lib.board("sh")?.items == ["c"])
        #expect(lib.shot("a") == nil && lib.shot("b") != nil)
        #expect(lib.board("w")?.items == ["b"])
    }

    @Test func removingEverythingPrunesShootBoardButKeepsGenreFolder() {
        var lib = RefLibrary(shots: list(), boards: [
            RefBoard(id: "sh", kind: .shoot, sid: "s1", items: ["a"]),
            RefBoard(id: "w", kind: .tpl, genre: "wedding", items: ["b"]),
        ])
        lib.remove(["a"], from: "sh")
        lib.remove(["b"], from: "w")
        #expect(lib.board("sh") == nil)                          // опустевшая съёмка без имени исчезла
        #expect(lib.board("w")?.items == [])                     // жанровая пустая остаётся
    }

    @Test func removeIgnoresFramesNotOnTheBoard() {
        var lib = RefLibrary(shots: list(), boards: [RefBoard(id: "w", kind: .tpl, genre: "wedding", items: ["b"])])
        #expect(lib.remove(["a"], from: "w").isEmpty)            // «a» в подборке не лежит — фонд не тронут
        #expect(lib.shot("a") != nil)
    }
}
