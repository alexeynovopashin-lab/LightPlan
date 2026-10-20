import Testing
import SwiftUI
@testable import LightPlanUI

/// 29.8в.22: барабаны листа «Когда смотрим» (день, час, минута) тикают за каждую пройденную строку.
/// Тик — `Haptics.play(.wheelRow)`; здесь проверено решение «тикать ли» на последовательностях, снятых с барабана.
struct WheelTickTests {

    private func ticks(_ start: Int, _ steps: [(Int, Bool)]) -> Int {
        var t = WheelTicker(value: start)
        return steps.reduce(0) { $0 + (t.moved(to: $1.0, userDriven: $1.1) ? 1 : 0) }
    }

    @Test("палец ведёт барабан на 5 строк — 5 тиков, на каждой строке по одному")
    func oneTickPerRow() {
        #expect(ticks(10, [(11, true), (12, true), (13, true), (14, true), (15, true)]) == 5)
    }

    @Test("кадры на одной и той же строке не тикают")
    func sameRowIsSilent() {
        #expect(ticks(10, [(10, true), (10, true), (11, true), (11, true), (11, true), (12, true)]) == 2)
    }

    @Test("назад — тоже тик, и через конец кольца (59 → 0 → 1)")
    func backwardAndWrap() {
        #expect(ticks(12, [(11, true), (10, true)]) == 2)
        #expect(ticks(58, [(59, true), (0, true), (1, true)]) == 3)
    }

    @Test("доезд кодом (фишка «Завтра»: десятки строк) не тикает и не оставляет тик на потом")
    func scriptedScrollIsSilent() {
        var t = WheelTicker(value: 30)
        var n = 0
        for v in 31...45 { if t.moved(to: v, userDriven: false) { n += 1 } }
        #expect(n == 0)
        // Палец после доезда: первая же новая строка — тик, а не двойной за старое
        let first = t.moved(to: 46, userDriven: true)
        let again = t.moved(to: 46, userDriven: true)
        #expect(first && !again)
    }

    @Test("возврат закольцованного барабана в среднюю копию: значение то же — тика нет")
    func recycleIsSilent() {
        // Номер строки прыгает на n, значение под полосой то же: барабан отдаёт значение, а не строку
        #expect(ticks(7, [(7, false), (7, false)]) == 0)
    }

    @Test("тикает палец и инерция, не покой и не scrollTo")
    func phases() {
        #expect(ScrollPhase.tracking.isUserDriven && ScrollPhase.interacting.isUserDriven && ScrollPhase.decelerating.isUserDriven)
        #expect(!ScrollPhase.idle.isUserDriven && !ScrollPhase.animating.isUserDriven)
    }

    @Test("слой отдачи знает событие: выбор, без щелчка (у беты на барабане звука нет)")
    func eventIsMapped() {
        #expect(HapticEvent.wheelRow.kind == .selection)
        #expect(HapticEvent.wheelRow.sound == nil)
    }
}
