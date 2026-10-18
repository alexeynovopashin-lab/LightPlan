import Testing
import Foundation
import LightPlanCore

/// Калибровка компаса (шаги 29.8в.2, 29.8в.8): шкала — охват движения по гироскопу и положению, «Готово» — охват
/// и точность от системы не хуже порога. Подставные потоки датчиков — `CalibrationScript`, без часов и телефона.
struct CompassCalibrationTests {

    /// Точность системы: до `after` секунд `entry`°, потом `final`°.
    private static func accuracy(entry: Degrees?, final: Degrees?, after: TimeInterval)
        -> CalibrationScript.Accuracy {
        { t in (t < after ? entry : final, nil) }
    }

    private func run(_ script: CalibrationScript, seconds: Double, from t0: TimeInterval = 0) -> CompassCalibration {
        var c = CompassCalibration()
        for r in script.readings(from: t0, seconds: seconds) { c.add(r) }
        return c
    }

    @Test("датчика нет — фаза «нет датчика», шкала пуста, отсчёты ничего не меняют")
    func noSensor() {
        var c = CompassCalibration()
        c.markNoSensor()
        #expect(c.phase == .noSensor && c.progress == 0)
        c.add(CalibrationScript(motion: .figureEight(scale: 1)).reading(at: 0))
        #expect(c.phase == .noSensor && c.progress == 0 && !c.canFinish)
    }

    // MARK: - Шкала растёт только от движения

    @Test("неподвижный телефон 60 с: шкала 0, «Готово» нет — даже при отличной точности от системы")
    func stationaryStaysAtZero() {
        for acc: Degrees in [3, 8, 25] {
            let c = run(CalibrationScript(motion: .still, accuracy: Self.accuracy(entry: acc, final: acc, after: 0)),
                        seconds: 60)
            #expect(c.progress == 0, "точность ±\(acc)°: шкала \(c.progress)")
            #expect(c.phase == .measuring && !c.canFinish)
        }
        // То же с «ступенью» поля вместо градусов — как в старой калибровке (она здесь давала «Готово» за 1,6 с).
        let level = CalibrationScript(motion: .still) { _ in (nil, .high) }
        let c = run(level, seconds: 60)
        #expect(c.progress == 0 && c.phase == .measuring)
    }

    @Test("отсчёты редкие и с огромными пропусками времени: время шкалу не двигает")
    func timeAloneDoesNothing() {
        var c = CompassCalibration()
        let s = CalibrationScript(motion: .still, accuracy: { _ in (5, .high) })
        for i in 0..<20 { c.add(s.reading(at: Double(i) * 1000)) }
        #expect(c.progress == 0)
    }

    @Test("тряска на месте 60 с (±3° с частотой 9 Гц, скорость до 170 °/с): шкала почти не растёт")
    func shakeInPlaceBarelyMoves() {
        let c = run(CalibrationScript(motion: .shake, accuracy: { _ in (8, .high) }), seconds: 60)
        #expect(c.progress < 0.05, "шкала \(c.progress)")
        #expect(c.phase == .measuring && !c.canFinish)
    }

    @Test("половинный размах восьмёрки: шкала растёт, но не полная")
    func halfSwingIsPartial() {
        let c = run(CalibrationScript(motion: .figureEight(scale: 0.5), accuracy: { _ in (8, .high) }), seconds: 30)
        #expect(c.progress > 0.3 && c.progress < 0.9, "шкала \(c.progress)")
        #expect(c.phase == .measuring)
    }

    @Test("шкала не идёт назад: рекорд отклонения держится, когда телефон вернулся")
    func progressNeverGoesBack() {
        var c = CompassCalibration()
        let s = CalibrationScript(motion: .figureEight(scale: 1))
        var last = 0.0
        for r in s.readings(seconds: 12) {
            c.add(r)
            #expect(c.progress >= last - 1e-12)
            last = c.progress
        }
        let still = CalibrationScript(motion: .still)
        for r in still.readings(from: 12, seconds: 5) { c.add(r) }
        #expect(c.progress >= last - 1e-12)
    }

    // MARK: - «Готово» и честность

    @Test("полная восьмёрка, точность улучшилась ±25° → ±8°: «Готово», число улучшения 17°")
    func fullEightImprovedIsReady() {
        let s = CalibrationScript(motion: .figureEight(scale: 1), accuracy: Self.accuracy(entry: 25, final: 8, after: 6))
        let c = run(s, seconds: 20)
        #expect(c.progress == 1)
        #expect(c.phase == .ready && c.canFinish)
        let was = try? #require(c.entryAccuracy?.degrees), now = try? #require(c.accuracy?.degrees)
        #expect(was == 25 && now == 8)
        #expect((was ?? 0) - (now ?? 0) == 17, "улучшение курса на подставных данных, градусов")
    }

    @Test("полная восьмёрка, а точность не улучшилась (±25°): не «Готово», а честное «не стало лучше»")
    func fullEightNotImproved() {
        let s = CalibrationScript(motion: .figureEight(scale: 1), accuracy: { _ in (25, .low) })
        var c = CompassCalibration()
        var sawChecking = false
        for r in s.readings(seconds: 40) {
            c.add(r)
            if c.phase == .checking { sawChecking = true }
            #expect(c.phase != .ready, "«Готово» при ±25° недопустимо (порог ±\(CompassCalibration.requiredDegrees)°)")
        }
        #expect(c.progress == 1, "движение сделано полностью")
        #expect(sawChecking, "первые секунды после движения система ещё может ответить")
        #expect(c.phase == .notImproved && !c.canFinish)
    }

    @Test("после «не стало лучше» система всё же ответила лучше — «Готово» приходит само")
    func lateAnswerTurnsReady() {
        let s = CalibrationScript(motion: .figureEight(scale: 1), accuracy: Self.accuracy(entry: 25, final: 10, after: 30))
        let c = run(s, seconds: 20)
        #expect(c.phase == .notImproved)
        var late = c
        for r in s.readings(from: 20, seconds: 15) { late.add(r) }
        #expect(late.phase == .ready)
    }

    @Test("порог: ровно ±15° годится, ±15,1° — нет; без градусов решает ступень поля не ниже средней")
    func thresholdEdges() {
        #expect(CompassAccuracy(degrees: 15, level: nil).isAcceptable)
        #expect(!CompassAccuracy(degrees: 15.1, level: .high).isAcceptable, "градусы решают одни")
        #expect(CompassAccuracy(degrees: nil, level: .medium).isAcceptable)
        #expect(!CompassAccuracy(degrees: nil, level: .low).isAcceptable)
        #expect(!CompassAccuracy(degrees: -1, level: nil).isAcceptable, "отрицательная — курс недействителен")
        #expect(!CompassAccuracy(degrees: nil, level: nil).isAcceptable, "система не отвечает — подтвердить нечем")
    }

    @Test("система точность не сообщает вовсе: движение сделано, а «Готово» нет")
    func noAnswerIsNotReady() {
        let c = run(CalibrationScript(motion: .figureEight(scale: 1)), seconds: 40)
        #expect(c.progress == 1 && c.phase == .notImproved && !c.canFinish)
        #expect(c.accuracy?.isKnown == false)
    }

    @Test("«Готово» раз достигнутое остаётся, даже если точность потом просела")
    func readyLatches() {
        let s = CalibrationScript(motion: .figureEight(scale: 1), accuracy: { _ in (8, nil) })
        var c = run(s, seconds: 20)
        #expect(c.phase == .ready)
        let worse = CalibrationScript(motion: .figureEight(scale: 1), accuracy: { _ in (40, nil) })
        for r in worse.readings(from: 20, seconds: 10) { c.add(r) }
        #expect(c.phase == .ready)
    }

    @Test("«Ещё раз»: шкала и точность при входе заново")
    func resetStartsOver() {
        let s = CalibrationScript(motion: .figureEight(scale: 1), accuracy: { _ in (25, .low) })
        var c = run(s, seconds: 40)
        #expect(c.phase == .notImproved)
        c.reset()
        #expect(c.phase == .measuring && c.progress == 0 && c.entryAccuracy == nil && c.accuracy == nil)
    }

    // MARK: - Сама калибровка не заканчивается

    @Test("ни один сценарий не завершается сам: фазы только меняются, «выхода» у ядра нет, часы не имеют значения")
    func nothingEndsByItself() {
        let scenarios: [CalibrationScript] = [
            CalibrationScript(motion: .still, accuracy: { _ in (5, .high) }),
            CalibrationScript(motion: .shake, accuracy: { _ in (5, .high) }),
            CalibrationScript(motion: .figureEight(scale: 1), accuracy: { _ in (5, .high) }),
            CalibrationScript(motion: .figureEight(scale: 1), accuracy: { _ in (30, .low) }),
        ]
        for s in scenarios {
            // Час отсчётов: ядро не знает слова «закрыть», а «Готово» — только состояние для кнопки (`canFinish`).
            let c = run(s, seconds: 3600)
            #expect(c.phase != .noSensor)
        }
    }

    // MARK: - Подсказки

    @Test("шкала стоит дольше 4 с — подсказка, чего не хватает: наклоны, повороты, «медленнее»")
    func hints() {
        // Телефон лежит: стоит шкала → просим наклонять.
        var c = run(CalibrationScript(motion: .still), seconds: 3)
        #expect(c.hint == nil, "рано: стоит меньше \(CompassCalibration.stallBeforeHint) с")
        for r in CalibrationScript(motion: .still).readings(from: 3, seconds: 3) { c.add(r) }
        #expect(c.hint == .tiltMore)
        // Тряска: быстро, шкала стоит → «медленнее».
        let shaken = run(CalibrationScript(motion: .shake), seconds: 6)
        #expect(shaken.hint == .slower)
        // Идёт движение: подсказки нет.
        let moving = run(CalibrationScript(motion: .figureEight(scale: 1)), seconds: 2)
        #expect(moving.hint == nil)
    }

    @Test("наклоны есть, поворотов нет — просим повернуть")
    func turnHint() {
        var c = CompassCalibration()
        let s = CalibrationScript(motion: .figureEight(scale: 1))
        // Те же наклоны, но без вращения вокруг вертикали.
        for r in s.readings(seconds: 12) {
            c.add(CalibrationReading(time: r.time, gravity: r.gravity, verticalRate: 0, rotationRate: 20))
        }
        for i in 0..<150 {
            let r = s.reading(at: 12 + Double(i) / 30)
            c.add(CalibrationReading(time: r.time, gravity: PhoneVector(x: 0, y: 1, z: 0), verticalRate: 0, rotationRate: 20))
        }
        #expect(c.progress > 0.5 && c.progress < 1)
        #expect(c.hint == .turnMore)
    }
}
