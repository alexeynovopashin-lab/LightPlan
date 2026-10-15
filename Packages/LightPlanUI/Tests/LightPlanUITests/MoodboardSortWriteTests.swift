import Testing
import Foundation
import CoreGraphics
@testable import LightPlanUI
import LightPlanDomain

/// Ревью GPT к 29.3б: порядок подборок пишется через 0,32 с после отпускания — только если ряд за это время
/// не менялся (`lift.home`). Как у кадров: разошёлся — не пишем, на экране актуальный порядок.
@MainActor
struct MoodboardSortWriteTests {

    /// Подставные часы: отложенные вызовы копятся, тест сам решает, когда их «наступило».
    private final class FakeClock {
        var queue: [(delay: Double, run: @MainActor () -> Void)] = []
        @MainActor func fire(_ i: Int) { if i < queue.count { queue[i].run() } }
    }

    private let keys = ["a", "b", "c", "d"]

    /// Ряд из четырёх плиток, «a» поднята и отпущена в клетке «c»; возвращает записанное и часы.
    private func gesture(rowChanges changed: [String]?) -> (sort: MbSort, wrote: [[String]], landing: [String]) {
        let sort = MbSort()
        let clock = FakeClock()
        sort.after = { d, run in clock.queue.append((d, run)) }
        sort.rows["r"] = MbSort.RowSize(width: 300, tileH: 120)
        sort.track("r", keys: keys)
        let box = Box()   // замыкание записи живёт дольше этого вызова
        #expect(sort.begin(row: "r", key: "a", keys: keys, first: 0) { box.wrote.append($0) })
        let cells = sort.cells("r", count: keys.count, first: 0)
        sort.move(CGSize(width: cells[2].midX - cells[0].midX, height: cells[2].midY - cells[0].midY))
        #expect(sort.order == ["b", "c", "a", "d"])
        if let changed { sort.track("r", keys: changed) }
        sort.drop()
        let landing = sort.order   // куда плитка едет, пока ждём запись
        #expect(clock.queue.map(\.delay) == [MbSortRules.settleDelay])
        clock.fire(0)
        return (sort, box.wrote, landing)
    }

    private final class Box { var wrote: [[String]] = [] }

    /// Порядок не менялся за время жеста — записалось то, что в руке.
    @Test func unchangedRowIsWritten() {
        let g = gesture(rowChanges: nil)
        #expect(g.wrote == [["b", "c", "a", "d"]])
        #expect(g.landing == ["b", "c", "a", "d"], "плитка садится в новую клетку")
        #expect(g.sort.lift == nil && g.sort.order.isEmpty && !g.sort.settling)
    }

    /// Порядок изменился за время жеста — запись не прошла, ряд показывает актуальный порядок, не руку.
    @Test func changedRowIsRefusedAndShowsLive() {
        let live = ["d", "a", "b", "c"]
        let g = gesture(rowChanges: live)
        #expect(g.wrote.isEmpty, "записано чужое: \(g.wrote)")
        #expect(g.landing == keys, "плитка ложится туда, откуда взята")
        #expect(g.sort.lift == nil && g.sort.order.isEmpty && !g.sort.settling, "жест кончился")
        #expect(g.sort.live["r"] == live, "на экране актуальный порядок ряда")
    }

    /// Ряд поменяли уже после отпускания, до записи, — то же: не пишем.
    @Test func changeDuringSettleIsRefused() {
        let sort = MbSort()
        let clock = FakeClock()
        sort.after = { d, run in clock.queue.append((d, run)) }
        sort.rows["r"] = MbSort.RowSize(width: 300, tileH: 120)
        let box = Box()
        #expect(sort.begin(row: "r", key: "a", keys: keys, first: 0) { box.wrote.append($0) })
        let cells = sort.cells("r", count: keys.count, first: 0)
        sort.move(CGSize(width: cells[1].midX - cells[0].midX, height: 0))
        sort.drop()
        sort.track("r", keys: ["a", "c", "b", "d"])   // за 0,32 с
        clock.fire(0)
        #expect(box.wrote.isEmpty)
    }
}
