import Testing
@testable import LightPlanDomain

/// Итерация 27, шаг 4: сетка референсов, листание, возврат в плитку кадра.
struct RefViewerTests {

    private func f(_ id: String, own: Bool = false, tags: [String] = [], kind: RefFrame.Kind = .img,
                   im: String? = "x", path: String? = nil) -> RefFrame {
        RefFrame(id: id, kind: kind, im: im, path: path, tags: tags, own: own)
    }

    // MARK: листание

    @Test func nextGoesAroundAfterTheLast() {
        var p = RefPager(count: 3, start: 2)
        p.next()
        #expect(p.index == 0)
    }

    @Test func previousGoesAroundBeforeTheFirst() {
        var p = RefPager(count: 3, start: 0)
        p.previous()
        #expect(p.index == 2)
    }

    @Test func oneFrameStaysAndHasNoCounter() {
        var p = RefPager(count: 1, start: 0)
        p.next(); p.previous()
        #expect(p.index == 0)
        #expect(p.counter == nil)
    }

    @Test func counterFromTwoFrames() {
        #expect(RefPager(count: 12, start: 2).counter == "3 / 12")
        #expect(RefPager(count: 2, start: 0).counter == "1 / 2")
    }

    @Test func startIsClamped() {
        #expect(RefPager(count: 4, start: 9).index == 3)
        #expect(RefPager(count: 0, start: 3).index == 0)
    }

    @Test func swipeThresholds() {
        #expect(RefPager.decide(dx: -60, dy: 0) == .next)
        #expect(RefPager.decide(dx: -59, dy: 0) == .stay)
        #expect(RefPager.decide(dx: 60, dy: 0) == .previous)
        #expect(RefPager.decide(dx: 0, dy: 110) == .close)
        #expect(RefPager.decide(dx: 0, dy: 109) == .stay)
        #expect(RefPager.decide(dx: 0, dy: -200) == .stay)   // вверх кадр тянется, не закрывается
        #expect(RefPager.decide(dx: -80, dy: 120) == .close) // где сдвиг больше — та ось
        #expect(RefPager.decide(dx: -130, dy: 120) == .next)
    }

    @Test func tapLadderAndZoomLimit() {
        #expect(RefPager.tap(scale: 1) == .close)
        #expect(RefPager.tap(scale: 2.5) == .stay)
        #expect(RefPager.clampZoom(9) == 6)
        #expect(RefPager.clampZoom(0.4) == 1)
    }

    // MARK: возврат на ту же точку (ошибка веба 21)

    /// Открыли на 1-й плитке, пролистали до 3-й, закрыли — домой едет 3-й кадр.
    @Test func closingHomesToTheFrameWePagedTo() {
        let s = RefSections(frames: [f("a", own: true), f("b", own: true), f("c"), f("d")], tag: nil)
        let list = s.viewable
        var p = RefPager(count: list.count, start: list.firstIndex { $0.id == "a" }!)
        p.next(); p.next()
        #expect(list[p.index].id == "c")
    }

    @Test func homeIsNilWhenTileFarOffScreen() {
        let view = RefBox(x: 0, y: 0, w: 393, h: 852)
        let on = RefBox(x: 20, y: 300, w: 170, h: 200)
        #expect(RefHome.target(tile: on, viewport: view) == on)
        #expect(RefHome.target(tile: RefBox(x: 20, y: 852 + 41, w: 170, h: 200), viewport: view) == nil)
        #expect(RefHome.target(tile: RefBox(x: 20, y: 852 + 39, w: 170, h: 200), viewport: view) != nil)
        #expect(RefHome.target(tile: RefBox(x: 20, y: -200 - 41, w: 170, h: 200), viewport: view) == nil)
        #expect(RefHome.target(tile: nil, viewport: view) == nil)
    }

    // MARK: сетка

    @Test func sectionsSplitOwnAndSetKeepingOrder() {
        let s = RefSections(frames: [f("a", own: true), f("b", own: true), f("c"), f("d")], tag: nil)
        #expect(s.own.map(\.id) == ["a", "b"])
        #expect(s.set.map(\.id) == ["c", "d"])
        #expect(s.flat.map(\.id) == ["a", "b", "c", "d"])
    }

    @Test func viewerListSkipsLinksAndFramesWithoutBytesOrPath() {
        let s = RefSections(frames: [f("a", own: true), f("l", own: true, kind: .link, im: nil),
                                     f("n", im: nil), f("p", im: nil, path: "/d/p.jpg")], tag: nil)
        #expect(s.viewable.map(\.id) == ["a", "p"])
    }

    @Test func folderFilterKeepsRussianAndCodeTags() {
        let all = [f("a", own: true, tags: ["Пара"]), f("b", tags: ["couple", "walk"]), f("c", tags: ["Детали"])]
        let s = RefSections(frames: all, tag: "couple")
        #expect(s.flat.map(\.id) == ["a", "b"])
        #expect(RefSections(frames: all, tag: "details").flat.map(\.id) == ["c"])
        #expect(RefSections(frames: all, tag: "sky").isEmpty)
    }

    @Test func foldersGenreOrderFirstThenForeign() {
        let all = [f("a", tags: ["Вечер", "Моя папка"]), f("b", tags: ["Пара"]), f("c", tags: ["Вечер"])]
        #expect(RefFolders.used(in: all, genre: "wedding") == ["couple", "evening", "Моя папка"])
        #expect(RefFolders.used(in: [f("z")], genre: "wedding").isEmpty)
    }

    @Test func columnsSplitWhereHeightsAreClosest() {
        #expect(RefColumns.firstColumnCount(heights: [100, 100, 100, 100]) == 2)
        #expect(RefColumns.firstColumnCount(heights: [300, 100, 100, 100]) == 1)
        #expect(RefColumns.firstColumnCount(heights: [100]) == 1 || RefColumns.firstColumnCount(heights: [100]) == 0)
        #expect(RefColumns.firstColumnCount(heights: []) == 0)
        #expect(RefColumns.height(w: 200, h: 300, width: 100) == 150)
        #expect(RefColumns.height(w: nil, h: nil, width: 100) == 75)
    }

    @Test func linkTileHostAndTail() {
        #expect(RefLink.host("https://www.pinterest.com/a/b") == "pinterest.com")
        #expect(RefLink.tail("https://www.pinterest.com/pin/123/") == "pin/123")
        #expect(RefLink.tail("https://site.ru/") == "www.site.ru".replacingOccurrences(of: "www.", with: ""))
    }

    /// Ревью GPT к b506d34: плитка за краем — кадр не улетает к ней, а остаётся.
    @Test func farTileMeansShrinkInPlaceNotFlightToTheTile() {
        let fit = RefBox(x: 0, y: 100, w: 393, h: 600)
        let far = RefBox(x: 20, y: 5000, w: 170, h: 200)
        #expect(RefHome.rect(open: true, shrinkingInPlace: true, home: nil, start: far, fit: fit) == fit)
        #expect(RefHome.rect(open: false, shrinkingInPlace: true, home: nil, start: far, fit: fit) == fit)
    }

    @Test func flightRectFollowsOpenAndHome() {
        let fit = RefBox(x: 0, y: 100, w: 393, h: 600)
        let start = RefBox(x: 20, y: 300, w: 170, h: 200)
        let home = RefBox(x: 200, y: 300, w: 170, h: 200)
        #expect(RefHome.rect(open: false, shrinkingInPlace: false, home: nil, start: start, fit: fit) == start)
        #expect(RefHome.rect(open: true, shrinkingInPlace: false, home: nil, start: start, fit: fit) == fit)
        #expect(RefHome.rect(open: false, shrinkingInPlace: false, home: home, start: start, fit: fit) == home)
    }
}
