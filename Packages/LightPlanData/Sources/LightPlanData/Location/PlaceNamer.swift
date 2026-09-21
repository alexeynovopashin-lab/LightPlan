import Foundation
import LightPlanCore

/// Итог вопроса «как называется это место»: имя (или `nil` — тогда координаты)
/// и настоящая зона, если геокодер её назвал.
public struct PlaceLookup: Sendable, Hashable {
    public let name: PlaceName?
    public let zone: ZoneID?
}

/// Имя места по координатам: кэш, одна повторная попытка, отмена устаревшего.
///
/// Правила веба (`fetchGeoName`), перенесённые как есть:
/// - имя для тех же координат (до тысячной градуса) уже есть — не спрашиваем;
/// - сбой — одна повторная попытка через 1,5 с, второй сбой — имени нет;
/// - ответ про место, откуда карту уже увели, не должен ничего менять — у веба
///   для этого сверка ключа, здесь отмена задачи: `Task.cancel()` на старом
///   вопросе бросает `CancellationError` вместо запоздавшего ответа.
///
/// Отличие от веба: пустой ответ («города нет») — окончательный ответ, а не
/// сбой, и кэшируется. У веба пустой ответ Nominatim гнал вопрос ко второму
/// источнику; источник теперь один, а повторять тот же вопрос ради того же
/// пустого ответа значило бы жечь лимит Apple.
public actor PlaceNamer {
    private let geocoder: any ReverseGeocoding
    private let retryDelay: Duration
    private var cache: [String: PlaceLookup] = [:]

    public init(geocoder: any ReverseGeocoding, retryDelay: Duration = .milliseconds(1500)) {
        self.geocoder = geocoder
        self.retryDelay = retryDelay
    }

    public func lookup(_ c: GeoCoordinate) async throws -> PlaceLookup {
        let key = c.nameKey
        if let hit = cache[key] { return hit }
        for attempt in 0..<2 {
            if attempt > 0 { try await Task.sleep(for: retryDelay) }
            try Task.checkCancellation()
            do {
                let a = try await geocoder.answer(for: c)
                try Task.checkCancellation()
                let found = PlaceLookup(
                    name: PlaceNameRules.name(locality: a.locality, region: a.region, country: a.country),
                    zone: a.zoneIdentifier.flatMap { ZoneID($0) })
                cache[key] = found
                return found
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue          // сбой сети: следующая попытка, если она есть
            }
        }
        // Молчит и со второго раза: остаются координаты. Не кэшируем — сеть вернётся.
        return PlaceLookup(name: nil, zone: nil)
    }
}
