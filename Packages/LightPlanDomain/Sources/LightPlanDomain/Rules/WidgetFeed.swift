import Foundation
import LightPlanCore

/// Что приложение оставляет виджету в общей папке (итерация 30б, `docs/30b_widget_cut.md` § «Data»).
///
/// Виджет сам считает свет (`SolarDay` в расширении), а то, чего не вычислит, берёт из одного маленького файла
/// `widget.json` в `group.<адрес приложения>`. 30б.1: только место «Света»; 30б.2 добавит съёмки ближайших дней.
/// Правило и формат здесь, в Domain (только Foundation): пишет приложение, читает расширение — одним кодом.
public struct WidgetFeed: Codable, Sendable, Equatable {
    public static let fileName = "widget.json"

    /// Место «Света»: имя для подписи, координаты и зона IANA (или `fixed:<секунды>` — запасная зона без сети).
    public struct Spot: Codable, Sendable, Equatable {
        public var name: String
        public var latitude: Double
        public var longitude: Double
        public var zone: String

        public init(name: String, latitude: Double, longitude: Double, zone: String) {
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.zone = zone
        }

        public init(name: String, place: Place) {
            self.init(name: name, latitude: place.latitude, longitude: place.longitude, zone: place.zone.identifier)
        }
    }

    public var place: Spot

    public init(place: Spot) {
        self.place = place
    }

    /// Общая папка приложения и его виджета: адрес расширения — адрес приложения + `.Widget` (`Config/Widget.xcconfig`).
    public static func groupID(bundleID: String) -> String {
        let suffix = ".Widget"
        let app = bundleID.hasSuffix(suffix) ? String(bundleID.dropLast(suffix.count)) : bundleID
        return "group." + app
    }

    public func encoded() -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(self)) ?? Data()
    }

    /// `nil` — файла нет или он чужого вида: виджет тогда показывает пустую плашку, а не падает.
    public static func decode(_ data: Data) -> WidgetFeed? {
        try? JSONDecoder().decode(WidgetFeed.self, from: data)
    }
}

extension WidgetFeed.Spot {
    /// `nil`, если зоны нет ни в базе системы, ни в виде `fixed:<секунды>`.
    public var zoneID: ZoneID? {
        if let z = ZoneID(zone) { return z }
        guard zone.hasPrefix("fixed:"), let s = Double(zone.dropFirst("fixed:".count)) else { return nil }
        return ZoneID(fixedOffsetHours: s / 3600)
    }

    public var place: Place? {
        zoneID.map { Place(latitude: latitude, longitude: longitude, zone: $0) }
    }

    /// Сегодняшний день по часам места (не телефона): виджет в Москве про Томск показывает томское «сегодня».
    public func today(at now: Date) -> CivilDate? {
        guard let zone = zoneID, let tz = Self.timeZone(zone) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day], from: now)
        return CivilDate(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Начало вечернего золотого часа (солнце опускается до 6°) в день `day` по часам места; `nil` — в этот день
    /// солнце 6° сверху вниз не проходит (полярный день или ночь). Солнце то же, что на экранах (`.iau`).
    public func goldenStart(on day: CivilDate) -> Date? {
        guard let place, let minutes = SolarDay(date: day, place: place).goldenB else { return nil }
        let offset = place.zone.utcOffsetHours(on: day)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: DateComponents(year: day.year, month: day.month, day: day.day))!
        // Минуты `SolarDay` идут от полуночи дня по смещению зоны на начало дня — так их читают экраны.
        return midnight.addingTimeInterval((minutes - offset * 60) * 60)
    }

    /// Пояс для часов на плашке: те же правила, что у `ZoneID`.
    public var timeZone: TimeZone? { zoneID.flatMap(Self.timeZone) }

    private static func timeZone(_ zone: ZoneID) -> TimeZone? {
        if zone.identifier.hasPrefix("fixed:"), let s = Int(zone.identifier.dropFirst("fixed:".count)) {
            return TimeZone(secondsFromGMT: s)
        }
        return TimeZone(identifier: zone.identifier)
    }
}
