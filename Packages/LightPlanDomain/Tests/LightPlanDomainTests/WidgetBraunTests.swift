import Testing
import Foundation
@testable import LightPlanDomain

/// 30б.2в-4: числа и правила среднего и малого виджета «Braun» — демка Алексея 26.10 (`Spec.dc.html`, `renderVals()`, `ticks()`, `fit()`).
struct WidgetBraunTests {

    // MARK: Правило круга (вариант А)

    @Test func theDialLightsTheLastMinutesCountedCounterClockwiseFromSixty() {
        // Обед 13:48 → 12 минут: горят точки 48…59, нулевая (сверху) погасла.
        let lit = (0..<60).filter { BraunDial.isLit(dot: $0, minutesLeft: 12) }
        #expect(lit == Array(48..<60), "горят \(lit)")
        #expect(BraunDial.lit(minutesLeft: 12) == 12)
        #expect(BraunDial.lit(minutesLeft: 0) == 0 && (0..<60).allSatisfy { !BraunDial.isLit(dot: $0, minutesLeft: 0) }, "0 мин — все погасли")
        #expect(BraunDial.lit(minutesLeft: 60) == 60 && BraunDial.lit(minutesLeft: 102) == 60, "больше часа горят все")
        #expect((0..<60).allSatisfy { BraunDial.isLit(dot: $0, minutesLeft: 102) })
        #expect(BraunDial.isLit(dot: 59, minutesLeft: 1) && !BraunDial.isLit(dot: 58, minutesLeft: 1), "одна минута — последняя точка перед верхней")
        #expect(BraunDial.lit(minutesLeft: -5) == 0)
    }

    @Test func theDialGeometryIsTheDemos() {
        #expect(BraunPlate.dialDiameter(plateHeight: 170, headerHeight: 18) == 116, "Pro Max")
        #expect(BraunPlate.dialDiameter(plateHeight: 158, headerHeight: 18) == 104, "обычный")
        #expect(BraunPlate.dialDiameter(plateHeight: 170, headerHeight: 32) == 102, "малый, имена в две строки")
        #expect(BraunDial.dotRadius(diameter: 116) == 52 && BraunDial.dotRadius(diameter: 104) == 46)
        #expect((0..<60).filter { BraunDial.dotSize($0) == 3.2 } == Array(stride(from: 0, to: 60, by: 5)), "каждая пятая крупнее")
        #expect((0..<60).filter { BraunDial.dotSize($0) == 2 }.count == 48)
        let top = BraunDial.dotCenter(0, diameter: 116), right = BraunDial.dotCenter(15, diameter: 116)
        #expect(abs(top.x) < 1e-9 && abs(top.y + 52) < 1e-9, "нулевая — сверху")
        #expect(abs(right.x - 52) < 1e-9 && abs(right.y) < 1e-9, "15-я — справа, по часовой")
        #expect(BraunDial.numberSize(diameter: 116) == 22 && BraunDial.unitSize(diameter: 116) == 13)
        #expect(BraunDial.numberSize(diameter: 104) == 20 && BraunDial.unitSize(diameter: 104) == 12, "при D < 112 — 20 / 12")
    }

    @Test func theCountdownSaysMinutesThenHoursAndMinutes() {
        #expect(BraunDial.countdown(minutes: 12) == [.init(12, .minute)])
        #expect(BraunDial.countdown(minutes: 0) == [.init(0, .minute)])
        #expect(BraunDial.countdown(minutes: 59) == [.init(59, .minute)])
        #expect(BraunDial.countdown(minutes: 102) == [.init(1, .hour), .init(42, .minute)], "«1 ч 42 мин»")
        #expect(BraunDial.countdown(minutes: 120) == [.init(2, .hour)], "ровный час — без «0 мин»")
        #expect(BraunDial.countdown(minutes: 150) == [.init(2, .hour), .init(30, .minute)])
    }

    // MARK: Барабан

    @Test func theDrumLeavesAnEmptyRowWhereThereIsNoNeighbour() {
        let route = ["Сборы", "Обед", "Прогулка", "Фотозона", "Банкет", "Танцы"]
        #expect(BraunDrum.neighbours(route, current: 1) == [nil, "Сборы", "Обед", "Прогулка", "Фотозона"], "вторая точка: сверху пусто")
        #expect(BraunDrum.neighbours(route, current: 0) == [nil, nil, "Сборы", "Обед", "Прогулка"], "первая: две пустые сверху")
        #expect(BraunDrum.neighbours(route, current: 5) == ["Фотозона", "Банкет", "Танцы", nil, nil], "последняя: две пустые снизу")
        #expect(BraunDrum.neighbours(route, current: 4) == ["Прогулка", "Фотозона", "Банкет", "Танцы", nil])
        #expect(BraunDrum.neighbours(route, current: 2) == ["Сборы", "Обед", "Прогулка", "Фотозона", "Банкет"], "середина: все пять")
        #expect(BraunDrum.neighbours([String](), current: nil) == [nil, nil, nil, nil, nil])
        #expect(BraunDrum.neighbours(route, current: nil) == [nil, nil, nil, "Сборы", "Обед"], "точка ещё не началась: центр пуст, ниже ближайшие")
    }

    @Test func theDrumRowsKeepTheirPlacesAndHeights() {
        let pro = BraunDrum.slots(diameter: 116, centerLines: 1)
        #expect(pro.map(\.offset) == [-2, -1, 0, 1, 2])
        #expect(pro.map(\.height) == [17, 22, 28, 22, 17], "Pro Max: 17 / 22 / 28")
        let proY: [Double] = pro.map(\.y)
        let wantY: [Double] = [5, 22, 44, 72, 94]
        #expect(proY == wantY, "центр на середине колонки, остальные встык: \(proY)")
        let regular = BraunDrum.slots(diameter: 104, centerLines: 1)
        #expect(regular.map(\.height) == [16, 21, 28, 21, 16], "обычный: 16 / 21 / 28")
        // Две строки в центре: 42, соседи на своих высотах, сдвинуты, центр по-прежнему на середине.
        let two = BraunDrum.slots(diameter: 116, centerLines: 2)
        #expect(two[2].height == 42 && two[2].y == 58 - 21 && two[1].y + two[1].height == two[2].y && two[3].y == two[2].y + 42)
        #expect(BraunDrum.nameWidth(column: 202) == 128 && BraunDrum.nameWidth(column: 188) == 114, "под название: колонка − 10 − 46 − 8 − 10")
    }

    // MARK: Риски

    @Test func theTicksMarkEveryWholeHourWithTheNearestTick() {
        // Свадьба 12:00–00:30 (750 минут): шаг 5 минут, часовая риска — каждая 12-я, 0-я и 144-я (24:00).
        let hours = BraunTicks.hourIndexes(start: 12 * 3600, duration: 750 * 60)
        #expect(hours == Set(stride(from: 0, to: 145, by: 12)), "\(hours.sorted())")
        #expect(hours.count == 13)
        // Начало не с ровного часа: 12:20–00:30 — первая часовая 13:00 (риска 8: 40 мин / 5), последняя 00:00.
        let late = BraunTicks.hourIndexes(start: 12 * 3600 + 20 * 60, duration: 730 * 60)
        #expect(late.min() == Int((40.0 / 730 * 150).rounded()) && late.count == 12, "\(late.sorted())")
        #expect(BraunTicks.hourIndexes(start: 0, duration: 0).isEmpty)
        #expect(BraunTicks.count == 150)
    }

    @Test func aTickIsPastOnceItsMomentHasPassed() {
        let duration = 750.0 * 60, elapsed = 108.0 * 60   // 13:48 от 12:00
        let past = (0..<150).filter { BraunTicks.isPast(index: $0, duration: duration, elapsed: elapsed) }
        #expect(past == Array(0...21), "108 / 5 = 21,6 → риски 0…21 прошли")
        #expect((0..<150).allSatisfy { BraunTicks.isPast(index: $0, duration: duration, elapsed: duration + 1) }, "после конца все погасли")
        #expect((0..<150).allSatisfy { !BraunTicks.isPast(index: $0, duration: duration, elapsed: 0) })
    }

    // MARK: Плашка и подбор шрифта

    @Test func thePlateCornerFollowsTheHeight() {
        #expect(BraunPlate.cornerRadius(plateHeight: 170) == 22 && BraunPlate.cornerRadius(plateHeight: 158) == 20.5)
        #expect(BraunPlate.cornerRadius(plateHeight: 164) == 21.25 && BraunPlate.cornerRadius(plateHeight: 200) == 22 && BraunPlate.cornerRadius(plateHeight: 100) == 20.5)
        #expect(BraunPlate.headerHeight(lines: 1) == 18 && BraunPlate.headerHeight(lines: 2) == 32)
    }

    @Test func fontStepsDownThenWrapsToTwoLinesNeverCutting() {
        // Ширина имени = 10 pt на пункт кегля: 15 → 150, 13 → 130, 12 → 120.
        func pick(_ chain: [BraunFit.Step], _ avail: Double) -> BraunFit.Step { BraunFit.pick(chain, avail: avail) { $0 * 10 } }
        #expect(pick(BraunFit.headerMedium, 160).size == 15)
        #expect(pick(BraunFit.headerMedium, 140).size == 13)
        #expect(pick(BraunFit.headerMedium, 125).size == 12)
        #expect(pick(BraunFit.headerMedium, 50).size == 12 && pick(BraunFit.headerMedium, 50).lines == 1, "среднему две строки не положены")
        let small = pick(BraunFit.headerSmall, 100)
        #expect(small.size == 13 && small.lines == 2 && small.lineHeight == 16, "малый: 13 в две строки")
        #expect(pick(BraunFit.centerRow, 170).size == 16 && pick(BraunFit.centerRow, 150).size == 14)
        let wrapped = pick(BraunFit.centerRow, 100)
        #expect(wrapped.size == 13 && wrapped.lines == 2, "центр барабана: 16 → 14 → 13 в две строки")
        #expect(pick(BraunFit.nearRow, 125).size == 12 && pick(BraunFit.nearRow, 10).size == 11)
        #expect(pick(BraunFit.farRow, 105).size == 10 && pick(BraunFit.farRow, 115).size == 11)
    }

    // MARK: Окошко свадьбы

    @Test func theWindowShowsHoursOnlyWhileMoreThanAnHourIsLeft() {
        #expect(BraunWindow.text(remaining: 10 * 3600 + 42 * 60) == "10:42:00" && BraunWindow.text(remaining: 42 * 60) == "42:00")
        #expect(BraunWindow.text(remaining: 59 * 60 + 59) == "59:59" && BraunWindow.text(remaining: 0) == "0:00" && BraunWindow.text(remaining: -5) == "0:00")
        #expect(BraunWindow.text(remaining: 3601) == "1:00:01")
        // Ровно час — уже без часов: запись ленты, что начинается на этой минуте, не покажет «0:59:59» до следующей записи.
        #expect(!BraunWindow.showsHours(remaining: 3600) && BraunWindow.text(remaining: 3600) == "60:00")
        #expect(BraunWindow.showsHours(remaining: 3660) && !BraunWindow.showsHours(remaining: 3540))
    }

    @Test func theNotchBandLosesTheRingWidthAtTheTopOnlyInTheDarkWindow() {
        #expect(BraunWindow.ringWidth == 0.5)
        #expect(BraunWindow.notchBandInsetTop(ringed: true) == 0.5 && BraunWindow.notchBandInsetTop(ringed: false) == 0)
    }
}
