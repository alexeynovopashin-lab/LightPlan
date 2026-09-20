import CoreHaptics
import UIKit

/// Отдача. В вебе её на iPhone нет вовсе: `navigator.vibrate` в Safari не
/// существует, и все детенты там немые (DECISIONS, разбор звука детента).
/// Значит эталона ощущения у нас нет — эти два удара калибруются на телефоне
/// с нуля, и их сила остаётся открытым вопросом к Алексею.
@MainActor
final class Haptics {
    private var engine: CHHapticEngine?
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)

    init() {
        light.prepare()
        rigid.prepare()
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        // Движок засыпает сам: система глушит его, когда приложение уходит в
        // фон или телефон снимают с руки.
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        engine?.stoppedHandler = { _ in }
        try? engine?.start()
    }

    /// Детент: час пройден. В вебе это `vibrate(2)` — самый короткий удар.
    func detent() {
        light.impactOccurred(intensity: 0.5)
    }

    /// Срыв: разряд передан. В вебе `vibrate(14)` вместе со звуком затвора.
    func snap() {
        guard let engine else {
            rigid.impactOccurred()
            return
        }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: 1),
                .init(parameterID: .hapticSharpness, value: 0.8),
            ],
            relativeTime: 0
        )
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makePlayer(with: pattern),
              (try? player.start(atTime: CHHapticTimeImmediate)) != nil
        else {
            rigid.impactOccurred()
            return
        }
    }
}
