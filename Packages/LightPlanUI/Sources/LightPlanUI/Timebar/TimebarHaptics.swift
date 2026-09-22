#if os(iOS)
import CoreHaptics
import UIKit

/// Отдача таймбара. В вебе её на iPhone нет вовсе (`navigator.vibrate` в
/// Safari не существует) — эталона не было, характер подобран пальцем на
/// живом телефоне (`Spikes/TimebarSpike`, DECISIONS «Отдача таймбара»,
/// «Барабан в нативе»). Числа зашиты и в настройки не выносятся — тем же
/// доводом, что порог и шаг детента передачи разряда.
///
/// Только iOS: `UIImpactFeedbackGenerator` за AppKit не стоит, а Taptic
/// Engine на macOS-таргете нет вовсе — там `TimebarHaptics` молчит (заглушка
/// ниже), барабан и слайдер работают, отдачи не показывая.
@MainActor
final class TimebarHaptics {

    // Трещотка на срыве: три удара с нарастанием и телом в конце.
    private static let snapPower: Float = 1
    // Гудение на взводе: вступает с половины хода, потолок ниже полной силы.
    private static let windDelay = 0.55
    private static let windTop: Float = 0.45

    private var engine: CHHapticEngine?
    private var windPlayer: CHHapticAdvancedPatternPlayer?
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)

    init() {
        heavy.prepare()
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        // Движок глохнет сам: уход в фон, звонок, снятие с руки.
        engine?.isAutoShutdownEnabled = false
        engine?.resetHandler = { [weak self] in
            Task { @MainActor in self?.wake() }
        }
        engine?.stoppedHandler = { _ in
            Task { @MainActor [weak self] in self?.windPlayer = nil }
        }
        wake()
    }

    private func wake() {
        windPlayer = nil
        try? engine?.start()
    }

    // MARK: - Детент

    /// Час пройден, ячейка барабана щёлкнула. Лёгкий, но не слабый: полная
    /// сила с коротким телом 18 мс — вес даёт тело, не одна лишь сила удара.
    func detent() {
        guard !play(events: [
            body(0.45, 0.8, at: 0, for: 0.018),
            hit(1, 0.95, at: 0),
        ]) else { return }
        heavy.impactOccurred(intensity: 0.7)
    }

    // MARK: - Взвод

    private func startBuzz() {
        guard engine != nil, windPlayer == nil else { return }
        // Базовая интенсивность 1: уровень задаётся управляющим параметром на
        // ходу — `hapticIntensityControl` её умножает, не задаёт.
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                .init(parameterID: .hapticIntensity, value: 1),
                .init(parameterID: .hapticSharpness, value: 0.2),
            ],
            relativeTime: 0,
            duration: 6
        )
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine?.makeAdvancedPlayer(with: pattern)
        else { return }
        windPlayer = player
        do {
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            windPlayer = nil
        }
    }

    /// Механизм натягивается: гудение густеет к порогу. До `windDelay`
    /// молчит совсем — задержка задана долей взвода, не секундами, иначе
    /// разъезжается с порогом (взвод копится и от движения, и от удержания).
    func windLevel(_ p: Double) {
        guard p >= Self.windDelay else {
            if windPlayer != nil { windStop() }
            return
        }
        startBuzz()
        guard let windPlayer else { return }
        let span = max(1 - Self.windDelay, 0.01)
        let k = min(max((p - Self.windDelay) / span, 0), 1)
        let level = Float(k) * Self.windTop
        let parameters = [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                     value: level, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                     value: 0.2 + level * 0.6, relativeTime: 0),
        ]
        try? windPlayer.sendParameters(parameters, atTime: CHHapticTimeImmediate)
    }

    func windStop() {
        try? windPlayer?.stop(atTime: CHHapticTimeImmediate)
        windPlayer = nil
    }

    // MARK: - Срыв

    /// Разряд передан: трещотка — три удара подряд.
    func snap() {
        windStop()
        let k = Self.snapPower
        guard !play(events: [
            hit(0.7 * k, 0.95, at: 0),
            hit(0.85 * k, 0.75, at: 0.035),
            hit(1 * k, 0.55, at: 0.075),
            body(0.7 * k, 0.4, at: 0.075, for: 0.05),
        ]) else { return }
        heavy.impactOccurred(intensity: 1)
    }

    // MARK: - Кирпичи

    private func hit(_ intensity: Float, _ sharpness: Float, at time: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                .init(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    /// Тело удара: короткое непрерывное событие. Один транзиент ощущается
    /// щелчком, вес даёт именно оно.
    private func body(_ intensity: Float, _ sharpness: Float,
                      at time: TimeInterval, for duration: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                .init(parameterID: .hapticSharpness, value: sharpness),
                .init(parameterID: .attackTime, value: 0),
                .init(parameterID: .decayTime, value: Float(duration)),
            ],
            relativeTime: time,
            duration: duration
        )
    }

    /// `true` — удар ушёл в Taptic Engine; `false` — бит запасным путём.
    private func play(events: [CHHapticEvent]) -> Bool {
        guard let engine else { return false }
        do {
            try engine.start()
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            return false
        }
    }
}

#else

/// Заглушка на macOS-таргете: Taptic Engine там нет, барабан и слайдер
/// работают молча.
@MainActor
final class TimebarHaptics {
    init() {}
    func detent() {}
    func windLevel(_ p: Double) {}
    func windStop() {}
    func snap() {}
}

#endif
