import Testing
import LightPlanCore
@testable import LightPlanDomain

/// 29.3б: перестановка подборок и числа жеста сортировки (веб `mbMoveTo`, `mbFrame`,
/// `mbAutoScroll`, `mbJiggle`, `mbSetGenreOrder`, `mbSetFolderOrder`).
struct MoodboardSortTests {

    // MARK: перенос i → j

    @Test func moveForwardAndBack() {
        let row = ["a", "b", "c", "d", "e"]
        #expect(MbSortRules.move(row, "a", to: 3) == ["b", "c", "d", "a", "e"])
        #expect(MbSortRules.move(row, "e", to: 1) == ["a", "e", "b", "c", "d"])
    }

    @Test func moveToNeighbour() {
        #expect(MbSortRules.move(["a", "b", "c"], "a", to: 1) == ["b", "a", "c"])
        #expect(MbSortRules.move(["a", "b", "c"], "c", to: 1) == ["a", "c", "b"])
    }

    @Test func moveBounds() {
        let row = ["a", "b", "c"]
        #expect(MbSortRules.move(row, "b", to: 1) == row)                  // на своё место
        #expect(MbSortRules.move(row, "a", to: 9) == ["b", "c", "a"])      // за край — к краю
        #expect(MbSortRules.move(row, "c", to: -4) == ["c", "a", "b"])
        #expect(MbSortRules.move(row, "x", to: 0) == row)                  // чужой — без правки
        #expect(MbSortRules.move(["a"], "a", to: 0) == ["a"])
    }

    // MARK: клетки и место под поднятой

    /// Ряд полосы: ширина 354, рамка «+» на первом месте — плитки 111,33 с шагом 121,33 (замер беты, справка 2.1).
    @Test func cellsOfStripRow() {
        let c = MbSortRules.cells(count: 4, first: 1, width: 354, tileHeight: 147.3)
        #expect(abs(c[0].w - 111.333) < 0.001)
        #expect(abs(c[0].x - 121.333) < 0.001 && c[0].y == 0)
        #expect(abs(c[1].x - 242.667) < 0.001 && c[1].y == 0)
        #expect(c[2].x == 0 && abs(c[2].y - 157.3) < 0.001)
        #expect(MbSortRules.hit(5, 160, cells: c) == 2)
        #expect(MbSortRules.hit(116, 20, cells: c) == nil)                 // зазор между плитками — мимо
    }

    @Test func zoneTakesNearestWithSlack() {
        let c = MbSortRules.cells(count: 3, first: 0, width: 354, tileHeight: 147.3)
        #expect(MbSortRules.zone(centerX: c[1].midX, centerY: c[1].midY, cells: c) == 1)
        // центр в 5 pt за правым краем первой клетки — ещё в ней (допуск 6)
        #expect(MbSortRules.zone(centerX: c[0].x + c[0].w + 5, centerY: c[0].midY, cells: c) == 0)
        // в 8 pt под рядом — ни в одной
        #expect(MbSortRules.zone(centerX: c[0].midX, centerY: c[0].y + c[0].h + 8, cells: c) == nil)
    }

    @Test func neighbourShiftFollowsNewPlace() {
        let c = MbSortRules.cells(count: 4, first: 1, width: 354, tileHeight: 147.3)
        let home = ["a", "b", "c", "d"], order = MbSortRules.move(home, "a", to: 2)   // b c a d
        let b = MbSortRules.shift("b", order: order, home: home, cells: c)
        #expect(abs(b.dx + 121.333) < 0.001 && b.dy == 0)                  // b уехала на клетку влево
        let cc = MbSortRules.shift("c", order: order, home: home, cells: c)
        #expect(abs(cc.dx - 242.667) < 0.001 && abs(cc.dy + 157.3) < 0.001) // c поднялась в первый ряд
        let d = MbSortRules.shift("d", order: order, home: home, cells: c)
        #expect(d.dx == 0 && d.dy == 0)
    }

    // MARK: автопрокрутка

    @Test func edgeSpeedLikeBeta() {
        #expect(MbSortRules.edgeSpeed(top: 20, bottom: 600, armed: false) == 0)   // палец ещё не выходил из полосы
        #expect(MbSortRules.edgeSpeed(top: 70, bottom: 600, armed: true) == -10)  // (120 − 70) / 5
        #expect(MbSortRules.edgeSpeed(top: 0, bottom: 600, armed: true) == -15)   // предел
        #expect(MbSortRules.edgeSpeed(top: 600, bottom: 90, armed: true) == 10)   // (140 − 90) / 5
        #expect(MbSortRules.edgeSpeed(top: 300, bottom: 300, armed: true) == 0)
        #expect(MbSortRules.edgeArms(top: 120, bottom: 140))
        #expect(!MbSortRules.edgeArms(top: 119, bottom: 400))
    }

    // MARK: покачивание

    @Test func jigglePhases() {
        #expect(MbSortRules.jiggleDelay(nth: 1) == 0)
        #expect(MbSortRules.jiggleDelay(nth: 2) == -0.13)
        #expect(MbSortRules.jiggleDelay(nth: 3) == -0.07)
        #expect(MbSortRules.jiggleDelay(nth: 6) == -0.07)                  // 3n перебивает 2n
        #expect(abs(MbSortRules.jiggle(t: 0, nth: 1) + 0.8) < 1e-9)        // старт с −0,8°
        #expect(abs(MbSortRules.jiggle(t: 0.26, nth: 1) - 0.8) < 1e-9)     // полупериод — +0,8°
        #expect(abs(MbSortRules.jiggle(t: 0.13, nth: 1)) < 1e-6)           // середина хода
        #expect(abs(MbSortRules.jiggle(t: 0, nth: 2)) < 1e-6)              // сдвиг на полхода
        #expect(abs(MbSortRules.jiggle(t: 0.52, nth: 1) + 0.8) < 1e-9)     // обратно
    }

    @Test func bezierMatchesCSS() {
        // `ease-in-out` симметрична; лифт беты (.2,1.3,.4,1) перелетает за 1
        #expect(abs(CubicBezier.easeInOut.y(at: 0.5) - 0.5) < 1e-6)
        let lift = CubicBezier(0.2, 1.3, 0.4, 1)
        #expect(lift.y(at: 0.6) > 1.02)
        #expect(lift.y(at: 1) == 1)
    }

    // MARK: запись порядка

    private func library() -> RefLibrary {
        RefLibrary(boards: [
            RefBoard(id: "w1", kind: .tpl, genre: "wedding"),
            RefBoard(id: "sh", kind: .shoot, sid: "s1", genre: "wedding"),
            RefBoard(id: "p", kind: .tpl, genre: "portrait"),
            RefBoard(id: "w2", kind: .tpl, genre: "wedding", name: "На море"),
            RefBoard(id: "f", kind: .tpl, genre: "family"),
            RefBoard(id: "l", kind: .tpl, genre: "love"),
        ])
    }

    @Test func genreOrderMovesWholeGenre() {
        var lib = library()
        lib.setGenreOrder(["portrait", "family", "wedding"])
        // съёмка на месте; «любовь» не в ряду — тоже; свадьба переехала обеими папками, их порядок прежний
        #expect(lib.boards.map(\.id) == ["p", "sh", "f", "w1", "w2", "l"])
    }

    /// Как у беты (устойчивая сортировка по жанру): папки жанра встают подряд, даже если ряд не менялся.
    /// Поэтому запись зовут только при сменившемся порядке (веб `changed` в `mbDrop`).
    @Test func genreOrderGroupsFoldersOfGenre() {
        var lib = library()
        lib.setGenreOrder(["wedding", "portrait", "family", "love"])
        #expect(lib.boards.map(\.id) == ["w1", "sh", "w2", "p", "f", "l"])
    }

    @Test func folderOrderOnShelf() {
        var lib = library()
        let ok = lib.setFolderOrder(["w2", "w1"])
        #expect(ok)
        #expect(lib.boards.map(\.id) == ["w2", "sh", "p", "w1", "f", "l"])
        let bad = lib.setFolderOrder(["w2", "gone"])                       // ряд разошёлся с фондом
        #expect(!bad)
        #expect(lib.boards.map(\.id) == ["w2", "sh", "p", "w1", "f", "l"])
    }

    @Test func orderSurvivesWrite() {
        var lib = library()
        lib.setGenreOrder(["family", "wedding"])
        var extra: [String: JSONValue] = [:]
        lib.write(into: &extra)
        #expect(RefLibrary(extra: extra).boards.map(\.id) == ["f", "sh", "p", "w1", "w2", "l"])
    }
}
