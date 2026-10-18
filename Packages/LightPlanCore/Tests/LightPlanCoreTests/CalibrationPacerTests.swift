import Testing
import Foundation
import LightPlanCore

/// Когда калибровка щёлкает и когда сигналит (шаг 29.8в.8а): по отсчётам, без телефона.
struct CalibrationPacerTests {

    private func ticks(_ script: CalibrationScript, seconds: Double) -> (ticks: [TimeInterval], done: [TimeInterval], percent: Int) {
        var c = CompassCalibration(), p = CalibrationPacer()
        var t: [TimeInterval] = [], d: [TimeInterval] = []
        for r in script.readings(seconds: seconds) {
            c.add(r)
            switch p.step(time: r.time, percent: c.percent, movementDone: c.movementDone) {
            case .tick: t.append(r.time)
            case .done: d.append(r.time)
            case nil: break
            }
        }
        return (t, d, c.percent)
    }

    @Test("неподвижно и тряска на месте: ни щелчка, ни сигнала")
    func silentWithoutMovement() {
        let still = ticks(CalibrationScript(motion: .still), seconds: 60)
        #expect(still.ticks.isEmpty && still.done.isEmpty)
        let shake = ticks(CalibrationScript(motion: .shake), seconds: 60)
        #expect(shake.ticks.count <= 1 && shake.done.isEmpty, "щелчков \(shake.ticks.count) на 1 % шкалы")
    }

    @Test("восьмёрка: щелчки идут, пока шкала растёт, один сигнал на 100 %, после него тишина")
    func eightTicksThenDone() {
        let r = ticks(CalibrationScript(motion: .figureEight(scale: 1)), seconds: 30)
        #expect(r.percent == 100 && r.done.count == 1)
        #expect(r.ticks.count > 10, "щелчков \(r.ticks.count)")
        #expect(r.ticks.allSatisfy { $0 < r.done[0] }, "после сигнала щелчков нет")
    }

    @Test("не залипает: не чаще 50 мс между щелчками (на отсчётах через 33 мс — 15 в секунду)")
    func rateLimit() {
        let r = ticks(CalibrationScript(motion: .figureEight(scale: 1)), seconds: 30)
        for (a, b) in zip(r.ticks, r.ticks.dropFirst()) {
            #expect(b - a >= CalibrationPacer.minGap - 1e-9, "щелчки через \(b - a) с")
        }
        let perSecond = Dictionary(grouping: r.ticks, by: { Int($0) }).values.map(\.count).max() ?? 0
        #expect(perSecond <= 15, "в одну секунду \(perSecond) щелчков")
    }

    @Test("медленное движение щёлкает на каждый процент: шкала растёт 1 % за отсчёт раз в 0,1 с — щелчок на каждый")
    func oneTickPerPercentWhenSlow() {
        var p = CalibrationPacer()
        var n = 0
        for i in 1...60 where p.step(time: Double(i) * 0.1, percent: i, movementDone: false) == .tick { n += 1 }
        #expect(n == 60)
    }

    @Test("«Ещё раз» начинает счёт заново: щелчки и сигнал снова")
    func resetStartsAgain() {
        var p = CalibrationPacer()
        #expect(p.step(time: 0, percent: 100, movementDone: true) == .done)
        #expect(p.step(time: 1, percent: 100, movementDone: true) == nil)
        p.reset()
        #expect(p.step(time: 2, percent: 1, movementDone: false) == .tick)
        #expect(p.step(time: 3, percent: 100, movementDone: true) == .done)
    }
}
