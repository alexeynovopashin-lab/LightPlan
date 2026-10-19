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

/// Доступ к месту телефона — для переключателя «Следовать за мной» (29.8в.12).
public enum LocationAccess: Sendable, Equatable {
    /// Ещё не спрашивали: первое касание покажет системное окно.
    case notAsked
    case granted
    /// Отказано, ограничено или службы выключены: разрешить можно только в настройках телефона.
    case denied
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
    /// Разрешение ещё не спрашивали. Лист «Где снимаем» тогда сам встаёт на
    /// путь координат и спрашивает (веб, `openLocSheet`: `permissions` →
    /// `prompt`): кнопка живёт там, и просить, не показав кто, нечестно.
    var needsPermission: Bool { get }
    /// Слежение за значимым смещением телефона (сотни метров, без постоянного GPS): каждая новая точка — в
    /// `onFix`. Разрешения не спрашивает; без доступа молчит. Второй вызов заменяет получателя.
    func startWatching(_ onFix: @escaping @MainActor (GeoCoordinate) -> Void)
    func stopWatching()
}

public extension DeviceLocating {
    var isAlreadyAuthorized: Bool { false }
    var needsPermission: Bool { false }
    func startWatching(_ onFix: @escaping @MainActor (GeoCoordinate) -> Void) {}
    func stopWatching() {}
    var access: LocationAccess { isAlreadyAuthorized ? .granted : needsPermission ? .notAsked : .denied }
}

/// `CoreLocation` по запросу: одна точка и тишина. Слежение (29.8в.12) — служба значимых смещений системы
/// (`startMonitoringSignificantLocationChanges`: сотовые вышки и Wi-Fi, точка примерно раз в 500 м пути), не
/// постоянный GPS.
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
    private var watcher: (@MainActor (GeoCoordinate) -> Void)?

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

    public var needsPermission: Bool { manager.authorizationStatus == .notDetermined }

    public func startWatching(_ onFix: @escaping @MainActor (GeoCoordinate) -> Void) {
        watcher = onFix
        guard isAlreadyAuthorized else { return }
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    public func stopWatching() {
        guard watcher != nil else { return }
        watcher = nil
        manager.stopMonitoringSignificantLocationChanges()
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
        // Доступ дали в настройках, пока слежение ждало, — оно начинает работать.
        if watcher != nil, isAlreadyAuthorized, CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
        // Вызывается и при создании менеджера, когда никто ничего не спрашивал.
        guard pending != nil, awaitingAuthorization else { return }
        if manager.authorizationStatus != .notDetermined {
            awaitingAuthorization = false
            proceed()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return finish(.unavailable) }
        let c = GeoCoordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        // Одна и та же служба отвечает и на «где я», и слежению: ответ получают оба.
        finish(.fix(c))
        watcher?(c)
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
