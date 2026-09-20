import CoreHaptics
import UIKit

/// Отдача. В вебе её на iPhone нет вовсе: `navigator.vibrate` в Safari не
/// существует, и все детенты там немые (DECISIONS, разбор звука детента).
/// Алексей, 20 сентября 2026: «там всё было уже идеально, не хватало только
/// тактильности». Значит эталона ощущения нет, и характер удара выбирается
/// пальцем — для этого здесь три варианта, а не один.
@MainActor
final class Haptics {

    /// Чем отдаётся срыв.
    enum Snap: String, CaseIterable, Identifiable {
        /// Одиночный резкий — как защёлка.
        case sharp = "резкий"
        /// Два удара подряд: разряд проходит через трещотку.
        case ratchet = "трещотка"
        /// Глухой тяжёлый — как механизм побольше.
        case deep = "глухой"

        var id: String { rawValue }
    }

    var snapKind: Snap = .sharp
    /// Гудение на взводе, нарастающее к порогу. В вебе такого нет вовсе:
    /// это заявка исполнителя, а не перенос.
    var windBuzz = true

    private var engine: CHHapticEngine?
    private var windPlayer: CHHapticAdvancedPatternPlayer?
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)

    init() {
        light.prepare()
        rigid.prepare()
        heavy.prepare()
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        // Движок засыпает сам: система глушит его, когда приложение уходит в
        // фон или телефон снимают с руки.
        engine?.resetHandler = { [weak self] in
            Task { @MainActor in self?.restart() }
        }
        try? engine?.start()
    }

    private func restart() {
        windPlayer = nil
        try? engine?.start()
    }

    /// Детент: час пройден. В вебе это `vibrate(2)` — самый короткий удар.
    func detent() {
        light.impactOccurred(intensity: 0.5)
    }

    /// Взвод пошёл.
    func windStart() {
        guard windBuzz, let engine, windPlayer == nil else { return }
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                .init(parameterID: .hapticIntensity, value: 0),
                .init(parameterID: .hapticSharpness, value: 0.25),
            ],
            relativeTime: 0,
            duration: 5
        )
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makeAdvancedPlayer(with: pattern)
        else { return }
        windPlayer = player
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    /// Гудение густеет к порогу. `p` — доля взвода, 0…1.
    func windLevel(_ p: Double) {
        guard windBuzz, let windPlayer else { return }
        let parameter = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: Float(p * p * 0.5),
            relativeTime: 0
        )
        try? windPlayer.sendParameters([parameter], atTime: CHHapticTimeImmediate)
    }

    func windStop() {
        try? windPlayer?.stop(atTime: CHHapticTimeImmediate)
        windPlayer = nil
    }

    /// Срыв: разряд передан. В вебе `vibrate(14)` вместе со звуком затвора.
    func snap() {
        windStop()
        guard let engine, let pattern = try? CHHapticPattern(events: events(), parameters: []),
              let player = try? engine.makePlayer(with: pattern),
              (try? player.start(atTime: CHHapticTimeImmediate)) != nil
        else {
            fallback()
            return
        }
    }

    private func events() -> [CHHapticEvent] {
        func hit(_ intensity: Float, _ sharpness: Float, at time: TimeInterval) -> CHHapticEvent {
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: intensity),
                    .init(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: time
            )
        }
        switch snapKind {
        case .sharp:
            return [hit(1, 0.8, at: 0)]
        case .ratchet:
            return [hit(0.55, 0.9, at: 0), hit(1, 0.65, at: 0.045)]
        case .deep:
            return [hit(1, 0.15, at: 0)]
        }
    }

    private func fallback() {
        switch snapKind {
        case .sharp: rigid.impactOccurred()
        case .ratchet:
            rigid.impactOccurred(intensity: 0.6)
            Task {
                try? await Task.sleep(for: .milliseconds(45))
                self.rigid.impactOccurred()
            }
        case .deep: heavy.impactOccurred()
        }
    }
}
