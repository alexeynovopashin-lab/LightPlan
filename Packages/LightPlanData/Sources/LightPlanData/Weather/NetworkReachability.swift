import Foundation
import Network

/// Слежение за доступностью сети — за протоколом, чтобы хранитель погоды
/// проверялся без сети. Поток отдаёт `true` (сеть есть) и `false` (нет); первое
/// значение — как сейчас, дальше — только перемены.
public protocol NetworkReachability: Sendable {
    func updates() -> AsyncStream<Bool>
}

/// Боевая сборка на `NWPathMonitor`: путь `satisfied` — сеть есть.
public struct SystemReachability: NetworkReachability {
    public init() {}

    public func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "lightplan.reachability"))
        }
    }
}
