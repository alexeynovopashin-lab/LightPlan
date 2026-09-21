import Foundation
import Observation
import LightPlanCore

/// «Где мы»: координаты, имя, зона — и то, как они меняются.
///
/// Правила веба (`setLocation`, `applyGeoNames`), перенесённые как есть:
/// - координаты и зона меняются сразу, имя — позже, одним движением;
/// - пока имя в пути, показывается **прежнее** (`isNameStale`): при панораме
///   ближайшая известная правда точнее координат, и шапка не прыгает;
/// - имя не пришло вовсе — тогда координаты (`name == nil`);
/// - отказ в разрешении или нет сигнала место **не** меняют: оно остаётся
///   последним сохранённым.
@MainActor
@Observable
public final class CurrentPlace {
    public private(set) var coordinate: GeoCoordinate
    /// `nil` — имени нет и показывать надо `coordinate.text`.
    public private(set) var name: PlaceName?
    public private(set) var zone: ZoneID
    public private(set) var isNameStale = false
    /// Чем кончилась последняя просьба «найди меня»; для подсказки на экране.
    public private(set) var lastDeviceResult: DeviceFix?
    /// Кэш настоящих зон — хранить его будет итерация 12.
    public private(set) var zones: ZoneCache

    /// Место для расчётов света: координаты и зона.
    public var place: Place {
        Place(latitude: coordinate.latitude, longitude: coordinate.longitude, zone: zone)
    }

    private let namer: PlaceNamer
    private let locator: any DeviceLocating
    private let debounce: Duration
    private var lookupTask: Task<Void, Never>?

    /// - Parameters:
    ///   - initial: последнее сохранённое место.
    ///   - debounce: пауза перед вопросом к геокодеру. Веб ждёт 0,9 с: имя нужно
    ///     после того, как карту отпустили, а не на каждом кадре.
    public init(initial: GeoCoordinate, name: PlaceName? = nil, zones: ZoneCache = ZoneCache(),
                namer: PlaceNamer, locator: any DeviceLocating, debounce: Duration = .milliseconds(900)) {
        self.coordinate = initial
        self.name = name
        self.zones = zones
        self.zone = zones.zoneOrEstimate(at: initial)
        self.namer = namer
        self.locator = locator
        self.debounce = debounce
    }

    /// Сменить место: карту отпустили, выбрали закладку, набрали координаты.
    public func move(to c: GeoCoordinate) {
        coordinate = c
        zone = zones.zoneOrEstimate(at: c)
        isNameStale = true
        scheduleNaming(for: c)
    }

    /// Ручной ввод. Ошибка ввода место не трогает.
    @discardableResult
    public func setManual(latitude: String, longitude: String) -> ManualCoordinates.Failure? {
        switch ManualCoordinates.parse(latitude: latitude, longitude: longitude) {
        case .success(let c): move(to: c); return nil
        case .failure(let f): return f
        }
    }

    /// «Найти меня». Разрешение спрашивается здесь и только здесь.
    public func useDeviceLocation() async {
        let result = await locator.currentFix()
        lastDeviceResult = result
        if case .fix(let c) = result { move(to: c) }
    }

    /// Дождаться, пока имя для текущего места придёт (для тестов и для экранов,
    /// которым нужно закрыть спиннер).
    public func settled() async { await lookupTask?.value }

    private func scheduleNaming(for c: GeoCoordinate) {
        lookupTask?.cancel()                     // ответ про прежнее место уже не нужен
        lookupTask = Task { [namer, debounce] in
            do {
                try await Task.sleep(for: debounce)
                let found = try await namer.lookup(c)
                try Task.checkCancellation()
                self.apply(found, for: c)
            } catch {
                // Отменён новым местом: тот, кто отменил, сам назначил следующий вопрос.
            }
        }
    }

    private func apply(_ found: PlaceLookup, for c: GeoCoordinate) {
        guard c == coordinate else { return }
        name = found.name
        isNameStale = false
        if let z = found.zone {
            zones.remember(z, at: c)
            zone = z
        }
    }
}
