import CoreHaptics
import UIKit

/// Отдача. В вебе её на iPhone нет вовсе: `navigator.vibrate` в Safari не
/// существует, и все детенты там немые (DECISIONS, разбор звука детента).
/// Алексей, 20 сентября 2026: «там всё было уже идеально, не хватало только
/// тактильности». Эталона ощущения нет — характер и сила выбираются пальцем.
///
/// Замер 20 сентября: первый заход Алексей не почувствовал вовсе. Причина в
/// гудении нашлась чтением кода: базовая интенсивность непрерывного события
/// стояла нулём, а `hapticIntensityControl` базовую **умножает**, а не задаёт.
/// Ноль на что угодно — ноль, тумблер переключал тишину на тишину.
@MainActor
final class Haptics {

    /// Чем отдаётся срыв. Один короткий удар телефон отдаёт слабо, поэтому у
    /// каждого варианта есть тело — непрерывная часть, которая даёт вес.
    enum Snap: String, CaseIterable, Identifiable {
        /// Резкий щелчок: тонкое короткое тело и острый удар поверх.
        case sharp = "резкий"
        /// Разряд проходит через храповик: три удара подряд.
        case ratchet = "трещотка"
        /// Тяжёлый глухой: длинное низкое тело, удар без резкости.
        case deep = "глухой"

        var id: String { rawValue }
    }

    // Числа выбраны Алексеем пальцем на iPhone 15 Pro Max, 20 сентября 2026,
    // ползунками прямо в песочнице. Дальше они зашиты: тактильную механику не
    // отдают в настройки (DECISIONS, «Передача разряда»).

    /// Срыв отдаётся трещоткой: разряд проходит через храповик.
    var snapKind: Snap = .ratchet
    var windBuzz = true
    /// С какой доли взвода вступает гудение. Первая половина молчит: Алексей
    /// просил «начинать чуть с задержкой». Задержка задана долей взвода, а не
    /// секундами, — иначе она разъезжается с порогом, ведь взвод копится и от
    /// движения пальца, и от удержания.
    var windDelay = 0.55
    /// Потолок гудения. На полной силе оно забивало сам срыв.
    var windTop = 0.45
    /// Общий множитель силы.
    var power = 1.0

    /// Что телефон ответил на последнюю попытку. Нужно, чтобы отличать
    /// «слабо бьёт» от «бьёт запасным путём» и от «не бьёт вовсе».
    private(set) var status = "не проверен"

    private var engine: CHHapticEngine?
    private var windPlayer: CHHapticAdvancedPatternPlayer?
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let light = UIImpactFeedbackGenerator(style: .light)

    init() {
        heavy.prepare()
        light.prepare()
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            status = "телефон не умеет"
            return
        }
        engine = try? CHHapticEngine()
        // Движок глохнет сам: уход в фон, звонок, снятие с руки. Без обоих
        // обработчиков следующий удар молча уходит в никуда.
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
        do {
            try engine?.start()
        } catch {
            status = "движок не стартовал: \(error.localizedDescription)"
        }
    }

    // MARK: - Детент

    /// Час пройден. В вебе это `vibrate(2)` — самый короткий удар.
    func detent() {
        guard !play(events: [hit(0.6 * power, 0.9, at: 0)]) else { return }
        light.impactOccurred(intensity: 0.6 * power)
    }

    // MARK: - Взвод

    /// Взвод пошёл. Сам гул здесь ещё не звучит: он вступает в `windLevel`,
    /// когда взвод перевалит за `windDelay`.
    func windStart() {}

    private func startBuzz() {
        guard windBuzz, engine != nil, windPlayer == nil else { return }
        // Базовая интенсивность 1: уровень задаётся множителем на ходу.
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
            status = "гудение не стартовало"
        }
    }

    /// Механизм натягивается: гудение густеет и становится жёстче к порогу.
    /// До `windDelay` молчит совсем — это и есть задержка вступления.
    func windLevel(_ p: Double) {
        guard windBuzz else { return }
        guard p >= windDelay else {
            if windPlayer != nil { windStop() }
            return
        }
        startBuzz()
        guard let windPlayer else { return }
        // Остаток взвода растягивается на всю шкалу: гул начинается с нуля
        // ровно в точке вступления, а не прыжком.
        let span = max(1 - windDelay, 0.01)
        let k = min(max((p - windDelay) / span, 0), 1)
        let level = Float(k * windTop * power)
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

    /// Разряд передан. В вебе `vibrate(14)` вместе со звуком затвора.
    func snap() {
        windStop()
        guard !play(events: snapEvents()) else { return }
        heavy.impactOccurred(intensity: power)
    }

    private func snapEvents() -> [CHHapticEvent] {
        let k = Float(power)
        switch snapKind {
        case .sharp:
            return [
                body(0.9 * k, 0.9, at: 0, for: 0.045),
                hit(1 * k, 1, at: 0),
            ]
        case .ratchet:
            return [
                hit(0.7 * k, 0.95, at: 0),
                hit(0.85 * k, 0.75, at: 0.035),
                hit(1 * k, 0.55, at: 0.075),
                body(0.7 * k, 0.4, at: 0.075, for: 0.05),
            ]
        case .deep:
            return [
                body(1 * k, 0.05, at: 0, for: 0.13),
                hit(1 * k, 0.25, at: 0.01),
            ]
        }
    }

    // MARK: - Кирпичи

    private func hit(_ intensity: Double, _ sharpness: Float, at time: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: Float(intensity)),
                .init(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    private func hit(_ intensity: Float, _ sharpness: Float, at time: TimeInterval) -> CHHapticEvent {
        hit(Double(intensity), sharpness, at: time)
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

    /// Возвращает `true`, если удар ушёл в Taptic Engine. `false` — надо бить
    /// запасным путём.
    private func play(events: [CHHapticEvent]) -> Bool {
        guard let engine else {
            status = "запасной путь: движка нет"
            return false
        }
        do {
            // Движок мог заглохнуть между ударами — старт идемпотентен.
            try engine.start()
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            status = "Taptic Engine"
            return true
        } catch {
            status = "запасной путь: \(error.localizedDescription)"
            return false
        }
    }
}
