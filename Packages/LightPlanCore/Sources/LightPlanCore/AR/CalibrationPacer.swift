import Foundation

/// Когда отдавать тактильный отклик калибровки (шаг 29.8в.8а): щелчок на каждый процент шкалы и один сигнал,
/// когда движение закончено — «можно остановиться».
///
/// Решает по отсчётам (время датчика, не часы), поэтому проверяется без телефона. Щелчок — только вперёд: шкала
/// не идёт назад, а после «Ещё раз» счёт начинается заново (`reset`).
///
/// **Не залипает.** Датчик отдаёт 30 отсчётов в секунду, и щелчок на каждый из них слился бы в гудение, по которому
/// не сосчитать проценты. Поэтому щелчки не чаще раза в `minGap` = 50 мс: при отсчётах через 33 мс это каждый
/// второй — 15 щелчков в секунду. Шкала, что растёт медленнее 15 % в секунду (а ровное движение — это 5–10 %/с:
/// сто процентов за 10–20 с), щёлкает на каждый процент; быстрее — 15 в секунду. Пропущенные проценты в долг не
/// записываются: щелчки после остановки руки сбили бы с толку, отклик кончается вместе со шкалой.
public struct CalibrationPacer: Sendable {
    public static let minGap: TimeInterval = 0.05

    public enum Pulse: Sendable, Equatable {
        /// Шкала прибавила процент.
        case tick
        /// Движение закончено (все ячейки закрыты): один раз за заход.
        case done
    }

    private var percent = 0
    private var lastTick: TimeInterval = -.infinity
    private var doneSent = false

    public init() {}

    public mutating func step(time: TimeInterval, percent now: Int, movementDone: Bool) -> Pulse? {
        if movementDone {
            percent = now
            guard !doneSent else { return nil }
            doneSent = true
            return .done
        }
        defer { percent = now }
        guard now > percent, time - lastTick >= Self.minGap else { return nil }
        lastTick = time
        return .tick
    }

    public mutating func reset() {
        self = CalibrationPacer()
    }
}
