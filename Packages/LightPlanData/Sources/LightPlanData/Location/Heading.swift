import Foundation
import CoreLocation

/// Куда смотрит телефон — для живого компаса карты (итерация 20б, веб
/// `setCompassLive`). Показание — градусы от севера по часовой стрелке.
@MainActor
public protocol HeadingSource: AnyObject {
    /// Датчик есть: на Mac и в симуляторе его нет, кнопка тогда молчит.
    var isAvailable: Bool { get }
    func start(_ onHeading: @escaping @MainActor (Double) -> Void)
    func stop()
}

/// Магнитометр через CoreLocation. Истинный север, когда система его знает
/// (нужно место), иначе магнитный — как `webkitCompassHeading` у веба.
/// Азимуты прибора считаются от истинного севера, поэтому истинный первым.
@MainActor
public final class CoreLocationHeading: NSObject, HeadingSource {
    private let manager = CLLocationManager()
    private var onHeading: (@MainActor (Double) -> Void)?

    override public init() {
        super.init()
        manager.delegate = self
    }

    public var isAvailable: Bool {
        #if os(iOS)
        CLLocationManager.headingAvailable()
        #else
        false
        #endif
    }

    public func start(_ onHeading: @escaping @MainActor (Double) -> Void) {
        self.onHeading = onHeading
        #if os(iOS)
        manager.headingFilter = 1
        manager.startUpdatingHeading()
        #endif
    }

    public func stop() {
        onHeading = nil
        #if os(iOS)
        manager.stopUpdatingHeading()
        #endif
    }
}

extension CoreLocationHeading: @preconcurrency CLLocationManagerDelegate {
    #if os(iOS)
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        let deg = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        guard deg >= 0 else { return }
        onHeading?(deg)
    }

    /// Окно калибровки iOS не показываем: оно перекрывало бы карту посреди
    /// съёмки, а неточный компас виден и так — карта дрожит.
    public func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { false }
    #endif
}

/// Подставной компас (итерация 21а): заданные углы по очереди, каждый держится
/// `hold` секунд, потом следующий; после последнего стоит на нём. В симуляторе
/// и на Mac магнитометра нет — этим источником ротор карты крутится так же,
/// как от живого компаса (тот же `start`, то же сглаживание у ротора).
/// Закрывает код ротора, не датчик: компас на телефоне проверяет Алексей.
@MainActor
public final class ScriptedHeading: HeadingSource {
    public let angles: [Double]
    public let hold: Duration
    private var play: Task<Void, Never>?

    public init(angles: [Double], hold: Duration = .seconds(3)) {
        self.angles = angles
        self.hold = hold
    }

    /// `"0,45,90"` → углы; пустое или без чисел — `nil`.
    public nonisolated static func angles(_ list: String) -> [Double]? {
        let a = list.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return a.isEmpty ? nil : a
    }

    public var isAvailable: Bool { true }

    public func start(_ onHeading: @escaping @MainActor (Double) -> Void) {
        play?.cancel()
        let angles = angles, hold = hold
        play = Task { @MainActor in
            for (i, deg) in angles.enumerated() {
                guard !Task.isCancelled else { return }
                onHeading(deg)
                if i < angles.count - 1 { try? await Task.sleep(for: hold) }
            }
        }
    }

    public func stop() {
        play?.cancel()
        play = nil
    }
}
