import Testing
import Foundation
import CoreGraphics
@testable import LightPlanUI
import LightPlanDomain

/// Шаг 27а.3: живой драг блока карточки — строка идёт за пальцем, соседи расступаются, рука
/// пустеет и при отпускании, и при прерванном жесте, автопрокрутка у краёв листа.
struct CardDragTests {

    private static let ids: [CardBlock] = [.day, .notes, .delivery, .money, .docs]

    private func drag(from: Int, count: Int = 5, startY: CGFloat = 400, scroll: CGFloat = 0) -> CardRowDrag {
        CardRowDrag(block: Self.ids[from], from: from, count: count, startY: startY, startScroll: scroll)
    }

    // MARK: - Строка за пальцем

    @Test func heldRowFollowsFingerOneToOne() {
        var d = drag(from: 2)
        d.follow(finger: 400, scroll: 0)
        #expect(d.dy == 0 && d.to == 2 && d.offset(of: 2) == 0)
        d.follow(finger: 425, scroll: 0)               // 25 pt вниз: строка ровно на 25, место пока своё
        #expect(d.dy == 25 && d.offset(of: 2) == 25 && d.to == 2)
        d.follow(finger: 437, scroll: 0)               // 37 — больше полшага: слот уже на строку ниже
        #expect(d.dy == 37 && d.offset(of: 2) == 37 && d.to == 3)
        d.follow(finger: 340, scroll: 0)               // 60 pt вверх
        #expect(d.dy == -60 && d.offset(of: 2) == -60 && d.to == 1)
    }

    @Test func heldRowStaysInsideTheList() {
        var d = drag(from: 2)
        d.follow(finger: 400 + 5000, scroll: 0)
        #expect(d.dy == 2 * 64 && d.to == 4)           // ниже последнего места не уходит
        d.follow(finger: 400 - 5000, scroll: 0)
        #expect(d.dy == -2 * 64 && d.to == 0)
        #expect(d.fingerY == CGFloat(400 - 5000))               // палец помнится, где он есть
    }

    @Test func listScrollMovesTheRowWithoutTheFinger() {
        var d = drag(from: 1, scroll: 100)
        d.follow(finger: 400, scroll: 100 + 128)       // палец стоит, лист уехал на 128: строка прошла две строки вниз
        #expect(d.dy == 128 && d.to == 3)
        d.follow(finger: 400 + 20, scroll: 100 + 128)  // и палец ушёл на 20
        #expect(d.dy == 148)
    }

    // MARK: - Соседи

    /// Для каждой пары «откуда — куда»: места строк — перестановка, и она та же, что даёт `preview`.
    @Test func placesAreAPermutationEqualToPreview() {
        let rows = Self.ids
        for from in rows.indices {
            for to in rows.indices {
                var d = drag(from: from)
                d.follow(CGFloat(to - from) * 64)
                #expect(d.to == to)
                let places = rows.indices.map { d.place($0) }
                #expect(Set(places) == Set(rows.indices), "from \(from) to \(to): \(places)")
                let arranged = rows.indices.sorted { d.place($0) < d.place($1) }.map { rows[$0] }
                #expect(arranged == CardOrderDrag.preview(rows, moving: rows[from], to: to), "from \(from) to \(to)")
            }
        }
    }

    @Test func neighboursStepByOneRowAndOthersStayPut() {
        var d = drag(from: 1)
        d.follow(2 * 64)                               // со 2-го на 4-е место: строки 2 и 3 поднимаются на шаг
        #expect([0, 2, 3, 4].map(d.offset(of:)) == [0, -64, -64, 0])
        d.follow(-64)                                  // на 1-е: строка 0 уходит на шаг вниз
        #expect([0, 2, 3, 4].map(d.offset(of:)) == [64, 0, 0, 0])
        d.follow(0)
        #expect(Self.ids.indices.map { d.offset(of: $0) } == [0, 0, 0, 0, 0])
    }

    /// Строка идёт за пальцем непрерывно, а соседи — только целыми шагами.
    @Test func neighboursNeverStopBetweenRows() {
        var d = drag(from: 1)
        for dy in stride(from: CGFloat(-80), through: 200, by: 7) {
            d.follow(dy)
            for i in Self.ids.indices where i != 1 {
                let k = d.offset(of: i) / 64
                #expect(k == k.rounded() && abs(k) <= 1, "dy \(dy), row \(i): \(d.offset(of: i))")
            }
        }
    }

    // MARK: - Рука: отпускание и прерванный жест

    @Test func releaseGivesTheMoveAndEmptiesTheHand() {
        var hand = CardHand()
        let lifted = hand.lift(.notes, from: 1, count: 4, startY: 300, startScroll: 0)
        #expect(lifted)
        hand.follow(finger: 380, scroll: 0)
        #expect(hand.isLifted)
        let move = hand.release(finger: 380, scroll: 0)
        #expect(move == CardMove(block: .notes, to: 2))
        #expect(!hand.isLifted && hand.drag == nil)
        hand.interrupt()                                // сброс «палец держит» после конца жеста — холостой
        #expect(!hand.isLifted)
    }

    @Test func interruptedGestureWritesNothingAndLeavesNoLiftedRow() {
        var hand = CardHand()
        hand.lift(.money, from: 3, count: 4, startY: 500, startScroll: 0)
        hand.follow(finger: 100, scroll: 0)             // дотащили до верха — и звонок
        #expect(hand.drag?.to == 0)
        hand.interrupt()
        #expect(!hand.isLifted && hand.drag == nil)     // никакой строки «в руке»
        let late = hand.release(finger: 100, scroll: 0)
        #expect(late == nil)                            // и записывать нечего
        // Следом жест принимается как новый: залипа нет.
        let again = hand.lift(.day, from: 0, count: 4, startY: 300, startScroll: 0)
        #expect(again)
        #expect(hand.drag?.block == .day && hand.drag?.to == 0)
    }

    @Test func handHoldsOneRowAtATime() {
        var hand = CardHand()
        let first = hand.lift(.day, from: 0, count: 4, startY: 300, startScroll: 0)
        let second = hand.lift(.notes, from: 1, count: 4, startY: 360, startScroll: 0)
        #expect(first && !second)
        #expect(hand.drag?.block == .day)
    }

    // MARK: - Автопрокрутка

    @Test func autoscrollZonesAndSpeeds() {
        let top: CGFloat = 100, bottom: CGFloat = 956
        let z = CardAutoScroll.zone, v = CardAutoScroll.maxSpeed
        #expect(CardAutoScroll.velocity(y: 500, top: top, bottom: bottom) == 0)
        #expect(CardAutoScroll.velocity(y: top + z, top: top, bottom: bottom) == 0)          // граница зоны — стоит
        #expect(CardAutoScroll.velocity(y: bottom - z, top: top, bottom: bottom) == 0)
        #expect(CardAutoScroll.velocity(y: top, top: top, bottom: bottom) == -v)             // на самом краю — полная
        #expect(CardAutoScroll.velocity(y: bottom, top: top, bottom: bottom) == v)
        #expect(CardAutoScroll.velocity(y: top - 300, top: top, bottom: bottom) == -v)       // за краем — не быстрее
        #expect(CardAutoScroll.velocity(y: bottom + 300, top: top, bottom: bottom) == v)
        #expect(CardAutoScroll.velocity(y: bottom - z / 2, top: top, bottom: bottom) == v / 2)
        #expect(CardAutoScroll.velocity(y: 10, top: 10, bottom: 10) == 0)                    // окна нет — стоит
    }

    @Test func autoscrollStaysInsideTheSheet() {
        #expect(CardAutoScroll.next(offset: 10, velocity: -420, dt: 1, max: 235) == 0)
        #expect(CardAutoScroll.next(offset: 230, velocity: 420, dt: 1, max: 235) == 235)
        #expect(CardAutoScroll.next(offset: 100, velocity: 420, dt: 0.5, max: 235) == 235)   // 100 + 210 → не дальше конца
        #expect(CardAutoScroll.next(offset: 100, velocity: 420, dt: 0.1, max: 235) == 142)
        #expect(CardAutoScroll.next(offset: 0, velocity: 420, dt: 0.1, max: 0) == 0)
        // Девять строк (572 pt) от нуля до конца листа при полной скорости — за полторы секунды.
        var y: CGFloat = 0
        var t = 0.0
        while y < 572 { y = CardAutoScroll.next(offset: y, velocity: CardAutoScroll.maxSpeed, dt: CardAutoScroll.tick, max: 572); t += CardAutoScroll.tick }
        #expect(t > 1.3 && t < 1.5, "время \(t)")
    }
}
