import Foundation
import LightPlanCore

/// Часовой пояс места, пока настоящий неизвестен, и кэш настоящих.
///
/// Настоящую зону отдаёт геокодер вместе с именем (`CLPlacemark.timeZone`).
/// Без сети приложение обязано считать свет, поэтому запасной путь — оценка по
/// долготе — остаётся: «не знаю пояса» означало бы пустой экран вместо часа
/// неточности (веб, «Модель времени»).
public enum ZoneEstimate {

    /// Дом фотографа: от него и считается оценка (веб `HOME_LON`, `HOME_TZ`).
    public static let homeLongitude = 37.48
    public static let homeOffsetHours = 3

    /// Веб `tzFor`. Целые часы: +5:30 Дели и +5:45 Катманду оценка не выражает,
    /// в Томске она даёт +6 вместо +7 — поэтому это запасной путь, а не ответ.
    public static func offsetHours(longitude: Double) -> Int {
        let raw = Double(homeOffsetHours) + JSNumber.round((longitude - homeLongitude) / 15)
        return Int(max(-12, min(14, raw)))
    }

    /// Зона фиксированного смещения для оценки: «GMT+7». Летнего времени у неё
    /// нет — как и у оценки веба.
    public static func zone(longitude: Double) -> ZoneID {
        let h = offsetHours(longitude: longitude)
        return ZoneID("GMT" + (h < 0 ? "-" : "+") + String(abs(h)))!
    }

    /// Ключ кэша зон: полградуса — меньше любого часового пояса, а запросов на
    /// порядок меньше (веб `zoneKey`).
    public static func cacheKey(_ c: GeoCoordinate) -> String {
        JSNumber.fixed(JSNumber.round(c.latitude * 2) / 2, 1) + "," + JSNumber.fixed(JSNumber.round(c.longitude * 2) / 2, 1)
    }
}

/// Кэш настоящих зон по клеткам в полградуса. Лежит рядом с данными и переживает
/// офлайн; хранит его итерация 12.
public struct ZoneCache: Sendable, Equatable {
    public private(set) var entries: [String: String]

    public init(entries: [String: String] = [:]) { self.entries = entries }

    public func zone(at c: GeoCoordinate) -> ZoneID? {
        entries[ZoneEstimate.cacheKey(c)].flatMap { ZoneID($0) }
    }

    /// «GMT» — заглушка «не знаю»: в кэш не идёт (веб `j.timezone !== "GMT"`).
    public mutating func remember(_ zone: ZoneID, at c: GeoCoordinate) {
        guard zone.identifier != "GMT" else { return }
        entries[ZoneEstimate.cacheKey(c)] = zone.identifier
    }

    /// Веб `tzAt`: настоящая зона, если известна, иначе оценка по долготе.
    public func zoneOrEstimate(at c: GeoCoordinate) -> ZoneID {
        zone(at: c) ?? ZoneEstimate.zone(longitude: c.longitude)
    }
}
