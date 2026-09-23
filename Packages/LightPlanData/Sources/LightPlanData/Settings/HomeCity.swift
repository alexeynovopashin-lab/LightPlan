import Foundation
import LightPlanCore

/// «Мой город» — профиль владельца (`me.city` веба), не настройка карты.
///
/// Имя нужно человеку, координаты — свету и карте, код страны — практике.
/// Набранное руками имя без подсказки справочника координат не несёт: свет
/// по нему не двигается (веб, `takeCity`: «двигать свет наугад нельзя»).
public struct HomeCity: Sendable, Equatable {
    public var name: String
    public var coordinate: GeoCoordinate?
    public var countryCode: String?

    public init(name: String = "", coordinate: GeoCoordinate? = nil, countryCode: String? = nil) {
        self.name = name; self.coordinate = coordinate; self.countryCode = countryCode
    }

    public var isEmpty: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Из объекта `me` снимка: `city`, `cityLat`, `cityLon`, `cityCC`.
    /// Координаты берутся, только если они выданы для этого же имени
    /// (`cityAt`), — иначе имя сменили руками, а точка осталась от прежнего.
    init(me: JSONValue?) {
        guard case .object(let o)? = me else { self.init(); return }
        let name = Self.string(o["city"]) ?? ""
        var c: GeoCoordinate?
        if case .number(let lat)? = o["cityLat"], case .number(let lon)? = o["cityLon"] {
            let at = Self.string(o["cityAt"])
            if at == nil || at == name { c = GeoCoordinate(latitude: lat, longitude: lon) }
        }
        self.init(name: name, coordinate: c, countryCode: Self.string(o["cityCC"]))
    }

    /// Вписать себя в `me`, не трогая чужих ключей (номер, «знакомство»).
    func merged(into me: JSONValue?) -> JSONValue {
        var o: [String: JSONValue] = [:]
        if case .object(let old)? = me { o = old }
        o["city"] = .string(name)
        if let c = coordinate {
            o["cityLat"] = .number(c.latitude); o["cityLon"] = .number(c.longitude); o["cityAt"] = .string(name)
        } else {
            o["cityLat"] = nil; o["cityLon"] = nil; o["cityAt"] = nil
        }
        o["cityCC"] = countryCode.map(JSONValue.string)
        return .object(o)
    }

    /// Первая буква заглавная, остальное как набрано (`cityCap`):
    /// «Ростов-на-Дону» знает о себе больше любого правила.
    public static func cap(_ v: String) -> String {
        let t = v.trimmingCharacters(in: .whitespaces)
        guard let first = t.first else { return "" }
        return String(first).uppercased(with: Locale(identifier: "ru")) + t.dropFirst()
    }

    private static func string(_ v: JSONValue?) -> String? {
        if case .string(let s)? = v { return s }
        return nil
    }
}
