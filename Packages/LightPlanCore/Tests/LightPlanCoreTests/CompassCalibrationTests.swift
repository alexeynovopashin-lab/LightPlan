import Testing
import Foundation
import LightPlanCore

/// Калибровка «восьмёркой» (шаг 29.8в.2): шкала — по отсчётам датчика, не по времени.
struct CompassCalibrationTests {

    /// Подаёт спокойные отсчёты: курс стоит, телефон почти не вращается; 30 Гц.
    private func feed(_ c: inout CompassCalibration, from t0: TimeInterval, seconds: Double,
                      accuracy: MagneticAccuracy?, heading: Degrees = 120) -> TimeInterval {
        var t = t0
        let end = t0 + seconds
        while t < end - 1e-9 {
            c.add(time: t, accuracy: accuracy, heading: heading, rate: 1)
            t += 1.0 / 30
        }
        return t
    }

    @Test("датчика нет — фаза «нет датчика», шкала пуста, отсчёты ничего не меняют")
    func noSensor() {
        var c = CompassCalibration()
        c.markNoSensor()
        #expect(c.phase == .noSensor)
        #expect(c.progress == 0)
        c.add(time: 0, accuracy: .high, heading: 10, rate: 0)
        #expect(c.phase == .noSensor && c.progress == 0)
    }

    @Test("точность low → medium: до medium «Готово» нет, как бы долго курс ни стоял; с medium — через 1,5 с устойчивости")
    func lowThenMedium() {
        var c = CompassCalibration()
        var t = feed(&c, from: 0, seconds: 6, accuracy: .low)
        #expect(c.phase == .measuring, "low не годится сколько ни жди")
        let lowProgress = c.progress
        #expect(lowProgress < 1 && lowProgress >= 0.5, "половина (низкая точность) + устойчивость: \(lowProgress)")
        // Точность выросла — курс уже устойчив больше 1,5 с, готово сразу на первом отсчёте.
        c.add(time: t, accuracy: .medium, heading: 120, rate: 1)
        #expect(c.phase == .ready)
        #expect(c.progress == 1)
        t += 1.0 / 30
        // Раз достигнуто — держится.
        c.add(time: t, accuracy: .low, heading: 120, rate: 1)
        #expect(c.phase == .ready)
    }

    @Test("медиум, но курс прыгает — не готово; устойчивость считается заново с последнего прыжка")
    func unsteadyBlocksReady() {
        var c = CompassCalibration()
        var t = 0.0
        // 3 секунды прыжков ±8° при неподвижном телефоне.
        for i in 0..<90 {
            c.add(time: t, accuracy: .high, heading: i % 2 == 0 ? 100 : 116, rate: 1)
            t += 1.0 / 30
        }
        #expect(c.phase == .measuring)
        #expect(c.steadyFor < CompassCalibration.steadyHold)
        // Курс успокоился: ровно 1,5 с спустя — готово, а на 1,0 с — ещё нет.
        let calmStart = t
        t = feed(&c, from: calmStart, seconds: 1.0, accuracy: .high)
        #expect(c.phase == .measuring, "1,0 с устойчивости мало: \(c.steadyFor)")
        t = feed(&c, from: t, seconds: 1.2, accuracy: .high)
        #expect(c.phase == .ready, "через 2,2 с покоя (0,5 с окна + 1,5 с): \(c.steadyFor)")
    }

    @Test("шкала растёт с точностью: 0 → ½ → 1; без отсчётов и с неподвижным временем она стоит")
    func progressFollowsAccuracy() {
        var c = CompassCalibration()
        #expect(c.progress == 0)
        // Точность «не откалиброван», курс устойчив долго — шкала упирается в ½.
        var t = feed(&c, from: 0, seconds: 5, accuracy: .uncalibrated)
        #expect(abs(c.progress - 0.5) < 1e-9, "uncalibrated: \(c.progress)")
        c.add(time: t, accuracy: .low, heading: 120, rate: 1)
        t += 1.0 / 30
        #expect(abs(c.progress - 0.75) < 1e-9, "low: \(c.progress)")
        #expect(c.phase == .measuring)
    }

    @Test("точность система не сообщает — решает одна устойчивость курса")
    func accuracyUnknown() {
        var c = CompassCalibration()
        _ = feed(&c, from: 0, seconds: 1.0, accuracy: nil)
        #expect(c.phase == .measuring)
        _ = feed(&c, from: 1.0, seconds: 1.0, accuracy: nil)
        #expect(c.phase == .ready)
    }

    @Test("телефон у зенита: курс не определён — устойчивость сбрасывается, а готовым он не становится")
    func zenithResets() {
        var c = CompassCalibration()
        var t = feed(&c, from: 0, seconds: 1.0, accuracy: .high)
        c.add(time: t, accuracy: .high, heading: nil, rate: 0)
        t += 1.0 / 30
        #expect(c.steadyFor == 0)
        #expect(c.phase == .measuring)
    }

    @Test("повернули телефон быстро — разброс курса объяснён вращением и устойчивостью не считается нарушением")
    func rotationIsNotUnsteady() {
        var c = CompassCalibration()
        var t = 0.0
        for _ in 0..<90 {
            c.add(time: t, accuracy: .high, heading: 100 + 40 * t, rate: 40)
            t += 1.0 / 30
        }
        #expect(c.phase == .ready)
    }

    @Test("reset: заново с нуля")
    func resetStartsOver() {
        var c = CompassCalibration()
        _ = feed(&c, from: 0, seconds: 3, accuracy: .high)
        #expect(c.phase == .ready)
        c.reset()
        #expect(c.phase == .measuring && c.progress == 0 && c.steadyFor == 0)
    }
}
