import Foundation
import LightPlanData

/// Раздел «Сеть» (28л.6): режим и состояние детектора доступности зарубежного.
extension AppModel {

    static func netMode(of snapshot: Snapshot) -> NetworkMode {
        if case .string(let raw)? = snapshot.extra["netMode"], let m = NetworkMode(rawValue: raw) { return m }
        return .auto
    }

    /// Выбор человека: пишется в снимок и сразу уходит маршрутизаторам (следующий запрос идёт по новому).
    public func setNetMode(_ mode: NetworkMode) {
        guard netMode != mode else { return }
        netMode = mode
        netHub?.mode = mode
        snapshot.extra["netMode"] = .string(mode.rawValue)
        persist()
    }

    /// Подключить общий для погоды и читалок центр и запустить слежение. Состояние детектора зеркалится в `foreignReach`.
    func attachNetwork(_ hub: NetworkPolicyHub) {
        netHub = hub
        hub.mode = netMode
        reachTask?.cancel()
        reachTask = Task { [weak self] in
            await hub.detector.start()
            for await state in await hub.detector.changes() {
                guard let self else { return }
                self.foreignReach = state
            }
        }
    }

    /// «Проверить снова»: проба сейчас, пока идёт — строка пишет «проверяем».
    public func recheckNetwork() {
        guard let hub = netHub, !netChecking else { return }
        netChecking = true
        Task { [weak self] in
            _ = await hub.detector.recheck()
            self?.netChecking = false
        }
    }

    /// Состояние зарубежного для экрана (снимки и тесты ставят его без сети).
    func useShotNetwork(_ state: ForeignReach) { foreignReach = state }

    /// Слово в строке «Зарубежные сервисы: …»: пока проба не ответила (и пока сети нет) — «проверяем».
    var foreignReachKey: String {
        if netChecking { return "net.checking" }
        switch foreignReach {
        case .reachable: return "net.reachable"
        case .unreachable: return "net.unreachable"
        case .unknown: return "net.checking"
        }
    }
}
