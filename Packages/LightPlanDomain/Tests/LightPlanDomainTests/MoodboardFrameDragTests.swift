import Testing
import LightPlanCore
@testable import LightPlanDomain

/// 29.3в: перестановка кадров в папке мудборда пальцем (веб `mbGridDrag`, `mbFlipReorder`).
/// Числа замера — Playwright на живой бете 13.10: папка из пяти кадров 400 × 600/900/500/700/600 и плитки «+»,
/// колонка 172; кадр 0 тянут прямо к середине кадра 2 за 20 шагов — порядок 0,1,2,3,4 → 1,2,0,3,4.
struct MoodboardFrameDragTests {
    private let w = 172.0
    private let ids = ["a", "b", "c", "d", "e"]
    /// Высоты кадров, замеренные на бете при ширине 172 (снимки Playwright чуть выше своих 600/900/… px).
    private let heights: [Double] = [258.6, 386.5, 215, 301.8, 258.6]

    private func layout(_ order: [String]) -> [MbFrameDragRules.Cell] {
        let h = Dictionary(uniqueKeysWithValues: zip(ids, heights))
        return MbFrameDragRules.layout(ids: order + ["+add"], heights: order.map { h[$0]! } + [w], column: w).cells
    }

    @Test func layoutIsTheBetaColumns() {
        let c = layout(ids)
        // Замер беты: в первой колонке кадры 0, 1, 2 (y 186 / 452,6 / 847,2 от верха сетки 186), во второй 3, 4.
        #expect(c.map(\.x) == [0, 0, 0, 180, 180, 180])
        #expect(abs(c[1].y - (452.6 - 186)) < 0.2)
        #expect(abs(c[2].y - (847.2 - 186)) < 0.2)
        #expect(abs(c[4].y - (495.8 - 186)) < 0.2)
        let tall = MbFrameDragRules.layout(ids: ids + ["+add"], heights: heights + [w], column: w).height
        #expect(abs(tall - (c[2].y + c[2].h)) < 0.01)
    }

    /// Путь пальца беты: от середины кадра 0 к середине кадра 2, 20 шагов; места пересчитываются после каждой
    /// перестановки, поднятый кадр в поиске не участвует.
    @Test func betaPathGivesTheBetaOrder() {
        let start = layout(ids)
        let (ax, ay) = (start[0].midX, start[0].midY), (bx, by) = (start[2].midX, start[2].midY)
        var order = ids, skip: String? = nil, swaps = 0
        for i in 1...20 {
            let x = ax + (bx - ax) * Double(i) / 20, y = ay + (by - ay) * Double(i) / 20
            let others = layout(order).filter { $0.id != "a" }
            let s = MbFrameDragRules.step(order, moving: "a", over: MbFrameDragRules.hit(x, y, cells: others), skip: skip)
            order = s.order; skip = s.skip
            if s.changed { swaps += 1 }
        }
        #expect(order == ["b", "c", "a", "d", "e"])
        #expect(swaps == 2)
    }

    @Test func stepSplicesIntoTheNeighboursPlace() {
        let s = MbFrameDragRules.step(["a", "b", "c", "d"], moving: "d", over: "b", skip: nil)
        #expect(s == .init(order: ["a", "d", "b", "c"], skip: "b", changed: true))
        let back = MbFrameDragRules.step(["a", "b", "c", "d"], moving: "a", over: "c", skip: nil)
        #expect(back.order == ["b", "c", "a", "d"])
    }

    /// С кем только что поменялись — того не трогаем, пока палец с него не ушёл (веб `skip`): иначе пара менялась
    /// бы на каждом движении туда-обратно.
    @Test func justSwappedNeighbourIsSkippedUntilFingerLeaves() {
        var s = MbFrameDragRules.step(["a", "b"], moving: "a", over: "b", skip: nil)
        #expect(s.order == ["b", "a"])
        s = MbFrameDragRules.step(s.order, moving: "a", over: "b", skip: s.skip)
        #expect(s.order == ["b", "a"] && !s.changed)
        s = MbFrameDragRules.step(s.order, moving: "a", over: nil, skip: s.skip)
        #expect(s.skip == nil)
        s = MbFrameDragRules.step(s.order, moving: "a", over: "b", skip: s.skip)
        #expect(s.order == ["a", "b"] && s.changed)
    }

    @Test func overTileOutsideOrderChangesNothing() {
        let s = MbFrameDragRules.step(["a", "b"], moving: "a", over: "+add", skip: nil)
        #expect(!s.changed && s.order == ["a", "b"])
    }

    @Test func hitIncludesEdges() {
        let cells = [MbFrameDragRules.Cell(id: "x", x: 10, y: 20, w: 100, h: 50)]
        #expect(MbFrameDragRules.hit(10, 20, cells: cells) == "x")
        #expect(MbFrameDragRules.hit(110, 70, cells: cells) == "x")
        #expect(MbFrameDragRules.hit(110.1, 70, cells: cells) == nil)
    }

    @Test func onlyBareGridReorders() {
        #expect(MbFrameDragRules.reorderable(picking: false, filtered: false, sort: 0))
        #expect(!MbFrameDragRules.reorderable(picking: true, filtered: false, sort: 0))
        #expect(!MbFrameDragRules.reorderable(picking: false, filtered: true, sort: 0))
        #expect(!MbFrameDragRules.reorderable(picking: false, filtered: false, sort: 1))
        #expect(!MbFrameDragRules.reorderable(picking: false, filtered: false, sort: 2))
    }

    @Test func numbersAreTheBetas() {
        #expect(MbFrameDragRules.hold == 0.42)
        #expect(MbFrameDragRules.slop == 8)
        #expect(MbFrameDragRules.liftScale == 1.06)
        #expect(MbFrameDragRules.edge == 56 && MbFrameDragRules.edgeStep == 12)
    }

    /// Край включается, только когда палец из полосы вышел; дальше 12 pt за кадр 60 Гц в сторону края.
    @Test func edgeArmsOutsideBandAndScrollsTwelvePerFrame() {
        #expect(!MbFrameDragRules.edgeArms(top: 30, bottom: 600))
        #expect(MbFrameDragRules.edgeArms(top: 56, bottom: 56))
        #expect(MbFrameDragRules.edgeSpeed(top: 30, bottom: 600, armed: false) == 0)
        #expect(abs(MbFrameDragRules.edgeSpeed(top: 30, bottom: 600, armed: true) + 720) < 1e-9)
        #expect(abs(MbFrameDragRules.edgeSpeed(top: 600, bottom: 10, armed: true) - 720) < 1e-9)
        #expect(MbFrameDragRules.edgeSpeed(top: 300, bottom: 300, armed: true) == 0)
    }

    // MARK: запись порядка

    private func library() -> RefLibrary {
        RefLibrary(shots: ["a", "b", "c"].map { RefFrame(id: $0, kind: .img, im: "\($0).jpg") },
                   boards: [RefBoard(id: "B", kind: .tpl, genre: "wedding", items: ["a", "b", "c"])])
    }

    @Test func reorderWritesPermutationAndStampsTime() {
        var lib = library()
        do { let ok = lib.reorder(["c", "a", "b"], of: "B", now: 42); #expect(ok) }
        #expect(lib.board("B")?.items == ["c", "a", "b"])
        #expect(lib.board("B")?.mt == 42)
    }

    /// Подборку поменяли за время жеста (новый кадр, снятый кадр) — старый порядок её не затирает.
    @Test func reorderRefusesStaleOrSameOrder() {
        var lib = library()
        do { let ok = lib.reorder(["a", "b", "c"], of: "B", now: 1); #expect(!ok) }
        do { let ok = lib.reorder(["b", "a"], of: "B", now: 1); #expect(!ok) }
        do { let ok = lib.reorder(["b", "a", "c", "d"], of: "B", now: 1); #expect(!ok) }
        do { let ok = lib.reorder(["b", "a", "a"], of: "B", now: 1); #expect(!ok) }
        do { let ok = lib.reorder(["c", "b", "a"], of: "nope", now: 1); #expect(!ok) }
        #expect(lib.board("B")?.items == ["a", "b", "c"])
        #expect(lib.board("B")?.mt == nil)
    }

    /// Подборку переставили за время жеста (другое устройство) — порядок жеста её не затирает.
    @Test func reorderRefusesWhenBoardChangedSinceLift() {
        var lib = library()
        do { let ok = lib.reorder(["b", "a", "c"], of: "B", expecting: ["a", "b", "c"], now: 1); #expect(ok) }
        do { let ok = lib.reorder(["c", "a", "b"], of: "B", expecting: ["a", "b", "c"], now: 2); #expect(!ok) }
        #expect(lib.board("B")?.items == ["b", "a", "c"])
    }
}
