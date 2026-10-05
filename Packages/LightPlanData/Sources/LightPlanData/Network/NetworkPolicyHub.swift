import Foundation

/// Общий для погоды и читалок ответ на вопрос «каким путём идти сейчас»: режим человека плюс то, что видит
/// детектор. Режим читается из любого потока (замок), состояние детектора — у него самого.
public final class NetworkPolicyHub: @unchecked Sendable {
    public let detector: ForeignReachDetector
    private let lock = NSLock()
    private var _mode: NetworkMode

    public init(mode: NetworkMode = .auto, detector: ForeignReachDetector) {
        self._mode = mode
        self.detector = detector
    }

    public var mode: NetworkMode {
        get { lock.lock(); defer { lock.unlock() }; return _mode }
        set { lock.lock(); _mode = newValue; lock.unlock() }
    }

    public func policy() async -> NetworkPolicy {
        NetworkPolicy(mode: mode, foreign: await detector.state)
    }
}
