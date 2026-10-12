import Testing
import CoreGraphics
@testable import LightPlanUI

/// Свайп влево по строке съёмки (29.3г): пороги, решение на отпускании, одна открытая строка.
@MainActor
struct RowSwipeTests {
    /// Строка дня под месяцем на 17 Pro Max: 440 − 2 × 24.
    static let w: CGFloat = 392

    @Test func thresholds() {
        #expect(RowSwipeRule.button == 88)
        #expect(RowSwipeRule.openAt == 44)
        #expect(RowSwipeRule.fireAt(width: Self.w) == 196)          // половина строки
        #expect(RowSwipeRule.fireAt(width: 200) == 128)             // узкая: кнопка + 40
        #expect(RowSwipeRule.flick == 300)
    }

    @Test func releaseDecides() {
        typealias R = RowSwipeRule
        #expect(R.release(offset: -20, velocity: 0, width: Self.w) == .idle)      // чуть тронули — назад
        #expect(R.release(offset: -43, velocity: 0, width: Self.w) == .idle)
        #expect(R.release(offset: -44, velocity: 0, width: Self.w) == .open)      // полкнопки — держит
        #expect(R.release(offset: -195, velocity: 0, width: Self.w) == .open)     // до порога — только кнопка
        #expect(R.release(offset: -196, velocity: 0, width: Self.w) == .fired)    // порог — удаление
        #expect(R.release(offset: -30, velocity: -300, width: Self.w) == .open)   // бросок влево
        #expect(R.release(offset: -88, velocity: 300, width: Self.w) == .idle)    // бросок вправо закрывает
        #expect(R.release(offset: -200, velocity: 900, width: Self.w) == .fired)  // за порогом бросок не спасает
    }

    @Test func offsetStaysInRow() {
        #expect(RowSwipeRule.offset(base: 0, dx: 30, width: Self.w) == 0)          // вправо из покоя — никуда
        #expect(RowSwipeRule.offset(base: -88, dx: 50, width: Self.w) == -38)      // вправо по открытой
        #expect(RowSwipeRule.offset(base: 0, dx: -600, width: Self.w) == -Self.w)  // не дальше ширины
    }

    @Test func beginsOnlySideways() {
        typealias R = RowSwipeRule
        #expect(R.begins(dx: -12, dy: 3, isOpen: false, startX: 200))
        #expect(!R.begins(dx: -6, dy: 12, isOpen: false, startX: 200))   // вдоль списка — прокрутка
        #expect(!R.begins(dx: 12, dy: 0, isOpen: false, startX: 200))    // вправо по закрытой — не наш
        #expect(R.begins(dx: 12, dy: 0, isOpen: true, startX: 200))      // вправо по открытой — закрыть
        #expect(!R.begins(dx: -12, dy: 0, isOpen: false, startX: 10))    // у края — жест «назад»
    }

    @Test func oneOpenRowAtATime() {
        let s = RowSwipe()
        var t: Double = 100
        s.clock = { t }
        s.began("m.a")
        #expect(!s.moved("m.a", dx: -60, width: Self.w))
        #expect(s.moved("m.a", dx: -90, width: Self.w))             // кнопка целиком — тик
        #expect(!s.moved("m.a", dx: -100, width: Self.w))           // тик один на жест
        #expect(s.blocksSwipe)                                      // свайп экрана молчит
        let r = s.ended("m.a", velocity: 0, width: Self.w)
        #expect(r.phase == .open && !r.tick)
        #expect(s.open == "m.a" && s.offset("m.a") == -88)
        t += 0.3; #expect(s.blocksSwipe)
        t += 0.2; #expect(!s.blocksSwipe)
        // Жест по другой строке закрывает первую.
        s.began("w.b")
        #expect(s.open == nil && s.offset("m.a") == 0)
        _ = s.moved("w.b", dx: -50, width: Self.w)
        let r2 = s.ended("w.b", velocity: 0, width: Self.w)
        #expect(r2.phase == .open && r2.tick)                       // открылась на отпускании — тик здесь
        // Касание другой строки закрывает и глотает её тап; касание мимо строк — закрывает.
        s.touchDown("m.c", stamp: 1)
        #expect(s.open == nil)
        #expect(s.takesTap("m.c"))
        t += 1; #expect(!s.takesTap("m.c"))
    }

    @Test func tapOnOpenRowClosesIt() {
        let s = RowSwipe()
        s.began("m.a"); _ = s.moved("m.a", dx: -70, width: Self.w)
        _ = s.ended("m.a", velocity: 0, width: Self.w)
        s.touchDown("m.a", stamp: 5)
        #expect(s.open == "m.a")                                    // своя строка касанием не закрывается
        s.outsideTouch(stamp: 5)                                    // сторож видит то же касание — строка его
        #expect(s.open == "m.a")
        #expect(s.takesTap("m.a"))                                  // тап закрывает, карточку не открывает
        #expect(s.open == nil)
        s.began("m.a"); _ = s.moved("m.a", dx: -70, width: Self.w); _ = s.ended("m.a", velocity: 0, width: Self.w)
        s.outsideTouch(stamp: 6)
        #expect(s.open == nil)
    }

    @Test func fullSwipeHoldsRowUntilGone() {
        let s = RowSwipe()
        s.began("s.a"); _ = s.moved("s.a", dx: -250, width: Self.w)
        #expect(s.isArmed("s.a"))
        let r = s.ended("s.a", velocity: 0, width: Self.w)
        #expect(r.phase == .fired && s.open == nil)
        #expect(s.offset("s.a") == -250)                            // не отъезжает, пока летит в корзину
        s.unhold("s.a")
        #expect(s.offset("s.a") == 0)
    }

    @Test func cancelledGestureCloses() {
        let s = RowSwipe()
        s.began("m.a"); _ = s.moved("m.a", dx: -300, width: Self.w)
        #expect(s.ended("m.a", velocity: 0, width: Self.w, cancelled: true).phase == .idle)
        #expect(s.offset("m.a") == 0)
    }
}
