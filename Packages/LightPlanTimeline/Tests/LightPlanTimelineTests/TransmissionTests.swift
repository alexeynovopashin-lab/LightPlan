import Testing
import LightPlanTimeline

/// Передача разряда сама по себе, без слайдера и без окна суток. Числа —
/// плановый DoD итерации 16: «довёл до упора и держал 1.06 с» даёт ровно один
/// переход, «довёл и отпустил через 0.5 с» — ни одного.
struct TransmissionTests {

    static let frame = 1.0 / 60

    @Test func dwellingToThresholdFiresExactlyOnce() {
        var wind = Transmission()
        wind.grab()
        // Довели до упора: сторона взята, сдвига ещё нет.
        #expect(wind.drag(dx: 0, side: 1) == .winding)

        var fired = 0
        var t = 0.0
        while t < 1.1 {
            // `.fire` — только сигнал; `spent` (один срыв за усилие) ставит
            // сам вызывающий через `fired()`, как `fireDay` в `TimelineMachine`.
            if case .fire = wind.dwell(dt: Self.frame) { fired += 1; wind.fired() }
            t += Self.frame
        }
        #expect(fired == 1)
        #expect(wind.spent)
    }

    @Test func releasingAtHalfSecondNeverFires() {
        var wind = Transmission()
        wind.grab()
        #expect(wind.drag(dx: 0, side: 1) == .winding)

        var fired = false
        var t = 0.0
        while t < 0.5 {
            if case .fire = wind.dwell(dt: Self.frame) { fired = true }
            t += Self.frame
        }
        // 0.5 с · 32/с = 16 < порога 34 — взвод не должен был дойти сам.
        #expect(!fired)

        wind.release()
        if case .fire = wind.dwell(dt: Self.frame) { fired = true }
        #expect(!fired)
        #expect(!wind.spent)
    }

    @Test func oneFirePerGrabEvenIfStillHeld() {
        var wind = Transmission()
        wind.grab()
        _ = wind.drag(dx: 0, side: 1)
        var fired = 0
        for _ in 0..<200 {
            if case .fire = wind.dwell(dt: Self.frame) { fired += 1; wind.fired() }
        }
        // Палец всё ещё лежит на упоре, но без нового взятия — новый срыв не
        // копится (иначе за одно удержание дата уехала бы на несколько суток).
        #expect(fired == 1)
    }

    @Test func grabAfterFireAllowsNextFire() {
        var wind = Transmission()
        wind.grab()
        _ = wind.drag(dx: 0, side: 1)
        for _ in 0..<200 {
            if case .fire = wind.dwell(dt: Self.frame) { wind.fired() }
        }
        #expect(wind.spent)

        wind.release()
        wind.grab()
        #expect(!wind.spent)
        _ = wind.drag(dx: 0, side: 1)
        var fired = false
        for _ in 0..<200 {
            if case .fire = wind.dwell(dt: Self.frame) { fired = true; wind.fired() }
        }
        #expect(fired)
    }
}
