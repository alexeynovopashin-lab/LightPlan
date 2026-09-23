import Foundation
import CoreLocation

/// Чем кончился запрос «где я».
public enum DeviceFix: Sendable, Equatable {
    case fix(GeoCoordinate)
    /// Пользователь отказал. Приложение ничего не ломает: место остаётся прежним.
    case denied
    /// Ограничено системой (родительский контроль, профиль) — для приложения то же, что отказ.
    case restricted
    /// Разрешение есть, но координаты не пришли: нет сигнала или вышло время.
    case unavailable
}

@MainActor
public protocol DeviceLocating {
    /// Одна точка «сейчас». Разрешение спрашивается при первом вызове и только
    /// по запросу пользователя — сам по себе запрос никто не делает.
    func currentFix() async -> DeviceFix
    /// Доступ уже дан — спросить точку можно без системного окна. Город по
    /// умолчанию (итерация 19а) берёт место телефона только в этом случае:
    /// новых запросов разрешения правило не добавляет.
    var isAlreadyAuthorized: Bool { get }
}

public extension DeviceLocating {
    var isAlreadyAuthorized: Bool { false }
}

/// `CoreLocation` по запросу. Ничего не слушает постоянно: одна точка и тишина.
///
/// Точность — сотни метров: место нужно, чтобы назвать населённый пункт и
/// посчитать свет, а не проложить маршрут. Ждём не дольше `timeout` — без него
/// запрос в метро висит до закрытия приложения.
@MainActor
public final class CoreLocationProvider: NSObject, DeviceLocating {
    private let manager = CLLocationManager()
    private let timeout: Duration
    private var pending: CheckedContinuation<DeviceFix, Never>?
    private var awaitingAuthorization = false
    private var timeoutTask: Task<Void, Never>?

    public init(timeout: Duration = .seconds(15)) {
        self.timeout = timeout
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    public var isAlreadyAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways: return true
        #if os(iOS)
        case .authorizedWhenInUse: return true
        #endif
        default: return false
        }
    }

    public func currentFix() async -> DeviceFix {
        // Второй вопрос при живом первом не плодим: тому, кто спросил вторым, отвечаем «нет».
        guard pending == nil else { return .unavailable }
        return await withCheckedContinuation { continuation in
            pending = continuation
            timeoutTask = Task { [weak self, timeout] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.finish(.unavailable)
            }
            proceed()
        }
    }

    private func proceed() {
        switch manager.authorizationStatus {
        case .notDetermined:
            awaitingAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .denied: finish(.denied)
        case .restricted: finish(.restricted)
        default: manager.requestLocation()
        }
    }

    private func finish(_ result: DeviceFix) {
        guard let continuation = pending else { return }
        pending = nil
        awaitingAuthorization = false
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: result)
    }
}

extension CoreLocationProvider: @preconcurrency CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Вызывается и при создании менеджера, когда никто ничего не спрашивал.
        guard pending != nil, awaitingAuthorization else { return }
        if manager.authorizationStatus != .notDetermined {
            awaitingAuthorization = false
            proceed()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return finish(.unavailable) }
        finish(.fix(GeoCoordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Отказ пользователя приходит и сюда: ответ — по статусу, а не по тексту ошибки.
        switch manager.authorizationStatus {
        case .denied: finish(.denied)
        case .restricted: finish(.restricted)
        default: finish(.unavailable)
        }
    }
}
