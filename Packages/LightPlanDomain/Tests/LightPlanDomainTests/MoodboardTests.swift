import Testing
import LightPlanCore
@testable import LightPlanDomain

/// Итерация 28, шаг 5а: что стоит на полосе «Съёмок», в галерее и на полке (веб `mbFolders`,
/// `renderMbStrip`, `renderMbTiles`, `renderMbSearchGrid`, `renderMbTagRail`).
struct MoodboardTests {
    private func day(_ d: Int, month: Int = 10) -> CivilDate { CivilDate(year: 2026, month: month, day: d) }
    private func shoot(_ id: String, _ d: CivilDate) -> Session { Session(id: id, day: d, start: 600, genre: .wedding) }

    private func library() -> RefLibrary {
        let shots = [
            RefFrame(id: "a", kind: .link, url: "https://www.pinterest.com/pin/1", tags: ["couple", "walk"]),
            RefFrame(id: "b", kind: .link, url: "https://example.org/x/y", tags: ["couple"]),
            RefFrame(id: "c", kind: .img, im: "c.jpg", tags: ["details"]),
        ]
        let boards = [
            RefBoard(id: "sh1", kind: .shoot, sid: "s1", genre: "wedding", items: ["a", "b"]),
            RefBoard(id: "shEmpty", kind: .shoot, sid: "s2", genre: "wedding", items: []),   // пустая не на ленте
            RefBoard(id: "w", kind: .tpl, genre: "wedding", items: ["c"]),
            RefBoard(id: "sea", kind: .tpl, genre: "wedding", items: ["a"], name: "На море"),
            RefBoard(id: "p", kind: .tpl, genre: "portrait"),
            RefBoard(id: "off", kind: .tpl, genre: "family", items: ["c"]),                   // жанр выключен
        ]
        return RefLibrary(shots: shots, boards: boards)
    }

    // MARK: состав ленты

    @Test func foldersAreShootsWithFramesThenOneShelfPerEnabledGenre() {
        let f = Moodboard.folders(library: library(),
                                  sessions: [shoot("s1", day(5)), shoot("s2", day(6)), shoot("s3", day(7))],
                                  genresOn: ["wedding", "portrait"])
        #expect(f.map(\.boardId) == ["sh1", "w", "p"])          // пустая подборка съёмки, выключенный жанр — нет
        #expect(f.map(\.kind) == [.shoot, .genre, .genre])
        #expect(f[1].boardIds == ["w", "sea"])                  // полка держит обе папки жанра
        #expect(f[2].frameCount == 0)                            // пустой жанр остаётся на глазах
    }

    @Test func tileCountSumsAllFoldersOfTheShelf() {
        let f = Moodboard.folders(library: library(), sessions: [shoot("s1", day(5))], genresOn: ["wedding"])
        #expect(f[0].frameCount == 2)
        #expect(f[1].frameCount == 2)                            // c + a: по всем папкам полки
    }

    @Test func boardOfMissingSessionIsNotShown() {
        let f = Moodboard.folders(library: library(), sessions: [], genresOn: ["wedding"])
        #expect(f.map(\.kind) == [.genre])                       // подборка без съёмки в списке не висит
    }

    @Test func stripSortsNearestFirstAndPastToTail() {
        let ss = [shoot("s1", day(2)), shoot("s2", day(9)), shoot("s3", day(20)), shoot("s4", day(1))]
        let lib = RefLibrary(shots: [RefFrame(id: "x")], boards: ss.map { RefBoard(id: "b" + $0.id, kind: .shoot, sid: $0.id, items: ["x"]) })
        let f = Moodboard.folders(library: lib, sessions: ss, genresOn: [])
        let strip = Moodboard.stripShoots(f, sessions: ss, today: day(5))
        #expect(strip.map(\.sessionId) == ["s2", "s3", "s1", "s4"])   // 9, 20 впереди по возрастанию; прошедшие: 2, потом 1
        let gal = Moodboard.galleryShoots(f, sessions: ss)
        #expect(gal.map(\.sessionId) == ["s3", "s2", "s1", "s4"])     // в галерее — по убыванию даты
    }

    // MARK: ряд полосы

    @Test func rowFitsSixThenAllTileTakesTheLastSlot() {
        let list = (0..<9).map { MbFolder(kind: .genre, boardId: "g\($0)", boardIds: ["g\($0)"], genre: "wedding") }
        // «Подборки»: одно место у плитки «+», влезает 5 → в ряду 4 жанра и «Все» с +N
        let r = Moodboard.row(list, withAdd: true)
        #expect(r.shown.count == 4)
        #expect(r.hidden.count == 5)
        #expect(r.badge == 5)                                    // веб: over + 1, over = 9 − 5 = 4
        // «Съёмки» без «+»: шесть мест, 9 → 5 плиток и «Все» (+4)
        let s = Moodboard.row(list, withAdd: false)
        #expect(s.shown.count == 5 && s.badge == 4)
        // влезло — «Все» нет
        let fit = Moodboard.row(Array(list.prefix(5)), withAdd: true)
        #expect(fit.shown.count == 5 && fit.badge == nil && fit.hidden.isEmpty)
    }

    @Test func measuredStripFourShootsAndTwelveGenres() {
        // Замер беты: «Подборки» — «+», 4 жанра и «+8 Все» при 12 жанрах.
        let g = (0..<12).map { MbFolder(kind: .genre, boardId: "g\($0)", boardIds: ["g\($0)"], genre: "x") }
        let r = Moodboard.row(g, withAdd: true)
        #expect(r.shown.count == 4 && r.badge == 8)
        #expect(Moodboard.row((0..<4).map { g[$0] }, withAdd: false).badge == nil)   // «Съёмки» — 4 плитки
    }

    @Test func mosaicTakesHiddenFirstThenTopUpFromAll() {
        let all = (0..<8).map { MbFolder(kind: .genre, boardId: "g\($0)", boardIds: ["g\($0)"], genre: "x") }
        let hidden = Array(all[4...])
        #expect(Moodboard.mosaic(hidden: hidden, all: all).map(\.boardId) == ["g4", "g5", "g6", "g7"])
        #expect(Moodboard.mosaic(hidden: [all[7]], all: all).map(\.boardId) == ["g7", "g0", "g1", "g2"])
    }

    // MARK: полка и вход

    @Test func openTargetIsShelfOnlyWhenGenreHasSeveralFolders() {
        let lib = library()
        let f = Moodboard.folders(library: lib, sessions: [shoot("s1", day(5))], genresOn: ["wedding", "portrait"])
        #expect(Moodboard.openTarget(f[0], in: lib) == .folder("sh1"))
        #expect(Moodboard.openTarget(f[1], in: lib) == .shelf("wedding"))   // две папки
        #expect(Moodboard.openTarget(f[2], in: lib) == .folder("p"))        // одна — сразу в кадры
    }

    @Test func shelfListsFoldersWithMainFirstAndCounts() {
        let s = Moodboard.shelf(library(), genre: "wedding")
        #expect(s.folders.map(\.id) == ["w", "sea"])
        #expect(s.frameCount == 2)
        #expect(s.folders.map { Moodboard.title(of: $0, genreName: "Свадьба") } == ["Свадьба", "На море"])
    }

    @Test func emptySavedGenresMeansAllTwelveAreOn() {
        // Найдено в симуляторе: у снимка без списка жанров лента была пуста, плиток жанров не было вовсе.
        #expect(Moodboard.enabledGenres([]).count == 12)
        #expect(Moodboard.enabledGenres([.wedding, .portrait]) == [.portrait, .wedding])   // порядок веба, не порядок выбора
    }

    @Test func firstLaunchGivesTwelveGenreTiles() {
        var extra: [String: JSONValue] = [:]
        let genres = ["wedding", "portrait", "family", "love", "kids", "food", "realty", "stars", "sport", "fashion", "event", "animals"]
        var n = 0
        #expect(RefLibrary.seedGenreFolders(in: &extra, genres: genres, newId: { n += 1; return "n\(n)" }))
        let f = Moodboard.folders(library: RefLibrary(extra: extra), sessions: [], genresOn: Set(genres))
        #expect(f.count == 12 && f.allSatisfy { $0.kind == .genre && $0.frameCount == 0 })
    }

    // MARK: цвет неба

    @Test func skyIndexIsFnv1aAndStable() {
        // Замер веба: `(h >>> 16) % 8` от FNV-1a 32 бита по кодам знаков.
        #expect(MbSky.index("") == Int((2166136261 as UInt32) >> 16) % 8)
        #expect(MbSky.index("w") == 4)
        #expect(MbSky.index("sd_sh_wedding") == MbSky.index("sd_sh_wedding"))
        #expect((0..<50).allSatisfy { (0..<8).contains(MbSky.index(String($0 * 7919 + 1_000_003, radix: 36))) })
        #expect(Set((0..<50).map { MbSky.index(String($0 * 7919 + 1_000_003, radix: 36)) }).count > 3)   // соседние подборки не в один цвет
    }

    // MARK: чипы разделов и поиск

    @Test func tagChipsCountAllShotsMostFirstThenAlphabet() {
        let c = Moodboard.tagCounts(library().shots)
        #expect(c.map(\.tag) == ["couple", "details", "walk"])
        #expect(c.map(\.n) == [2, 1, 1])
    }

    private func words(_ code: String) -> String {
        ["couple": "Пара", "walk": "Прогулка", "details": "Детали"][code] ?? code
    }
    private func titles(_ lib: RefLibrary) -> (RefFrame) -> [String] {
        { f in lib.boards.filter { $0.items.contains(f.id) }.map { $0.name ?? ($0.kind == .shoot ? "Аня и Пётр" : "Свадьба") } }
    }

    @Test func searchFindsByRussianTagBoardTitleAndLink() {
        let lib = library()
        func ids(_ q: String, tag: String? = nil) -> [String] {
            Moodboard.search(lib.shots, query: q, tag: tag, tagName: words, boardTitles: titles(lib)).map(\.id)
        }
        #expect(ids("Пара") == ["a", "b"])
        #expect(ids("couple") == [])                             // код раздела не ищется — замер веба, ошибка 27
        #expect(ids("пара") == ["a", "b"])                       // без учёта регистра
        #expect(ids("на море") == ["a"])                         // по имени папки, где кадр лежит
        #expect(ids("аня") == ["a", "b"])                        // по названию съёмки
        #expect(ids("pinterest") == ["a"])                       // по адресу ссылки
        #expect(ids("example.org/x") == ["b"])
        #expect(ids("свадьб") == ["c"])                          // жанр набора (кадр c лежит в «Свадьбе»)
        #expect(ids("нет такого") == [])
    }

    @Test func chipAndFieldAreTwoIndependentInputs() {
        let lib = library()
        func ids(_ q: String, tag: String?) -> [String] {
            Moodboard.search(lib.shots, query: q, tag: tag, tagName: words, boardTitles: titles(lib)).map(\.id)
        }
        #expect(ids("", tag: "walk") == ["a"])
        #expect(ids("", tag: "couple") == ["a", "b"])
        #expect(ids("pinterest", tag: "couple") == ["a"])        // оба условия вместе
        #expect(ids("example", tag: "walk") == [])
        #expect(Moodboard.isSearching(query: "  ", tag: nil) == false)
        #expect(Moodboard.isSearching(query: " x ", tag: nil) && Moodboard.isSearching(query: "", tag: "walk"))
    }

    @Test func chipDisappearsWhenItsTagIsGone() {
        #expect(Moodboard.activeTag("walk", in: Moodboard.tagCounts(library().shots)) == "walk")
        #expect(Moodboard.activeTag("gone", in: Moodboard.tagCounts(library().shots)) == nil)
    }

    // MARK: прыжок

    @Test func jumpShowsWhenScrollableIsAtLeastSixTenthsOfTheWindow() {
        // Веб: прячет при `over < clientHeight * 0,6`; при равенстве кнопка стоит.
        #expect(Moodboard.jumpVisible(scrollable: 480, screen: 800) == true)
        #expect(Moodboard.jumpVisible(scrollable: 479, screen: 800) == false)
        #expect(Moodboard.jumpVisible(scrollable: 5000, screen: 800))
    }

    @Test func jumpGoesWhereYouAreNot() {
        #expect(Moodboard.jumpGoesDown(offset: 0, scrollable: 1000))
        #expect(Moodboard.jumpGoesDown(offset: 499, scrollable: 1000))
        #expect(Moodboard.jumpGoesDown(offset: 500, scrollable: 1000) == false)   // веб: `scrollTop < over / 2`
        #expect(Moodboard.jumpGoesDown(offset: 1000, scrollable: 1000) == false)
    }

    // MARK: новая папка

    @Test func newFolderNeedsAName() {
        var lib = library()
        #expect(lib.addFolder(genre: "portrait", name: "   ", id: "x") == nil)
        #expect(lib.boards.count == 6)
        let b = lib.addFolder(genre: "portrait", name: " Мужской ", id: "m", now: 5)
        #expect(b?.name == "Мужской" && b?.kind == .tpl && b?.genre == "portrait")
        #expect(lib.folders(ofGenre: "portrait").map(\.id) == ["p", "m"])     // основная первая, новая следом
        #expect(Moodboard.openTarget(MbFolder(kind: .genre, boardId: "p", boardIds: ["p", "m"], genre: "portrait"), in: lib) == .shelf("portrait"))
    }
}
