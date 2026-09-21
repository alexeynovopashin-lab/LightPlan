import Foundation

/// Имя зоны IANA — свойство места (docs/17 § 5).
///
/// Минимум, который нужен солнцу: имя и смещение на дату. Итерация 11
/// расширяет тип вместе с `WallTime` и `Moment`, не меняя того, что здесь.
public struct ZoneID: Sendable, Hashable {
    public let identifier: String
    private let zone: TimeZone

    /// `nil`, если такой зоны в базе системы нет.
    public init?(_ identifier: String) {
        guard let zone = TimeZone(identifier: identifier) else { return nil }
        self.identifier = identifier
        self.zone = zone
    }

    /// Смещение от UTC в часах на **начало** этого дня в этой зоне.
    ///
    /// Именно на дату, а не постоянное: в марте и в июле у Берлина оно разное
    /// (`docs/16`). Момент отсчёта — полночь дня по часам самой зоны: так веб
    /// зовёт `tzAt(lat, lon, day)` — тот же `Date`, что уходит в
    /// `computeSun(day)`, то есть начало дня. Календарь строится с зоной места,
    /// поэтому зона машины не участвует.
    public func utcOffsetHours(on date: CivilDate) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = calendar.date(from: DateComponents(
            timeZone: zone, year: date.year, month: date.month, day: date.day
        ))!
        return Double(zone.secondsFromGMT(for: start)) / 3600
    }

    public static func == (a: ZoneID, b: ZoneID) -> Bool { a.identifier == b.identifier }
    public func hash(into hasher: inout Hasher) { hasher.combine(identifier) }
}

/// Место: координаты и зона. Итерация 11 добавляет остальное.
public struct Place: Sendable, Hashable {
    /// Градусы, север положителен.
    public let latitude: Double
    /// Градусы, восток положителен.
    public let longitude: Double
    public let zone: ZoneID

    public init(latitude: Double, longitude: Double, zone: ZoneID) {
        self.latitude = latitude
        self.longitude = longitude
        self.zone = zone
    }
}
