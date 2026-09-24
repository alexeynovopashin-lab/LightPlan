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
