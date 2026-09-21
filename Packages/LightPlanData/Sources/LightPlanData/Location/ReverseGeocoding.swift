import Foundation
import CoreLocation
import LightPlanCore

/// Что отвечает обратный геокодер, сведённое к тому, что читают правила имени.
public struct GeocodeAnswer: Sendable, Hashable {
    public let locality: String?
    public let region: String?
    public let country: String?
    /// Имя зоны IANA — геокодер отдаёт её вместе с именем.
    public let zoneIdentifier: String?

    public init(locality: String?, region: String?, country: String?, zoneIdentifier: String?) {
        self.locality = locality
        self.region = region
        self.country = country
        self.zoneIdentifier = zoneIdentifier
    }
}

/// Обратный геокодер за протоколом: приложение говорит с Apple, тесты — с записью.
public protocol ReverseGeocoding: Sendable {
    /// Бросает при сбое сети и при отказе; пустой ответ — не сбой.
    func answer(for coordinate: GeoCoordinate) async throws -> GeocodeAnswer
}

/// `CLGeocoder` вместо двух веб-геокодеров (docs/17 § 4.7).
///
/// Замер 21.09.2026, десять точек: `locality` — населённый пункт везде, где он
/// есть; регион в `administrativeArea` с заглавными буквами в каждом слове
/// («Московская Область»); `timeZone` приходит с ответом и верна на всех десяти,
/// включая Asia/Tomsk. Apple просит не больше ~50 запросов в минуту — поэтому
/// имя кэшируется и спрашивается после паузы, а не на каждом кадре карты.
public struct AppleReverseGeocoder: ReverseGeocoding {
    /// Язык подписей. Веб просит русский; на других языках интерфейса это
    /// решит итерация 14.
    public let locale: Locale

    public init(locale: Locale = Locale(identifier: "ru_RU")) { self.locale = locale }

    public func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
        // Один `CLGeocoder` на запрос: на одном экземпляре второй запрос отменяет первый.
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: c.latitude, longitude: c.longitude), preferredLocale: locale)
        guard let p = placemarks.first else {
            return GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
        return GeocodeAnswer(locality: p.locality, region: p.administrativeArea,
                             country: p.country, zoneIdentifier: p.timeZone?.identifier)
    }
}
