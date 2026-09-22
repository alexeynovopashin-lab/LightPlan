import Foundation
import LightPlanCore

/// Точка на земле: широта и долгота вместе. Координаты в записи живут парой —
/// одинокая широта без долготы считается «точки нет» (форма таких не делает;
/// веб в этом случае местами читает долготу нулём).
public struct GeoPoint: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Пара из двух необязательных полей записи.
    public init?(_ latitude: Double?, _ longitude: Double?) {
        guard let latitude, let longitude else { return nil }
        self.init(latitude: latitude, longitude: longitude)
    }
}

/// Точка съёмки с координатами: место съёмки или этап маршрута.
public struct Stop: Hashable, Sendable {
    public let name: String
    public let address: String
    public let point: GeoPoint
    /// Уточнение места: подъезд, вход.
    public let sub: String
    /// Студия: свой свет и своя погода, закат ей ничего не говорит.
    public let isStudio: Bool
}

/// Где идёт съёмка: у точки маршрута, у записи, у неба.
public enum Stops {

    /// Место точки маршрута (веб `stopPlace`). Своих координат точка не хранит:
    /// ссылается на студию или на сохранённое место. Имя студии берётся со
    /// строки — в ней уже собрано «Томсон, зал Эдисон». Ссылки нет или у места
    /// нет координат — `nil`.
    public static func place(of r: RoutePoint, spots: [Spot], studios: [Studio]) -> Stop? {
        if let st = studio(r.studioId, in: studios), let pt = GeoPoint(st.latitude, st.longitude) {
            return Stop(name: r.placeText.isEmpty ? st.name : r.placeText, address: st.address,
                        point: pt, sub: "", isStudio: true)
        }
        guard let sp = spot(r.spotId, in: spots), let pt = GeoPoint(sp.latitude, sp.longitude) else { return nil }
        return Stop(name: sp.name.isEmpty ? r.placeText : sp.name, address: sp.address,
                    point: pt, sub: sp.sub, isStudio: false)
    }

    /// Все точки съёмки с координатами (веб `recStops`): место съёмки первым,
    /// за ним точки маршрута в порядке списка.
    public static func all(of s: Session, spots: [Spot], studios: [Studio]) -> [Stop] {
        var out: [Stop] = []
        if let pt = GeoPoint(s.latitude, s.longitude) {
            out.append(Stop(name: s.place, address: s.placeAddress, point: pt, sub: "",
                            isStudio: !(s.studioId ?? "").isEmpty))
        }
        for r in s.route {
            if let p = place(of: r, spots: spots, studios: studios) { out.append(p) }
        }
        return out
    }

    /// Место, у которого спрашивают солнце, погоду и пояс (веб `shootAt`): первая
    /// по порядку дня точка под открытым небом; если день весь в залах — первая
    /// попавшаяся, пояс нужен и там. `nil` — точки нет, отвечает место приложения.
    public static func skyPoint(of s: Session, spots: [Spot], studios: [Studio]) -> GeoPoint? {
        let st = all(of: s, spots: spots, studios: studios)
        if let open = st.first(where: { !$0.isStudio }) { return open.point }
        if let first = st.first { return first.point }
        return GeoPoint(s.latitude, s.longitude)
    }

    static func studio(_ id: String?, in studios: [Studio]) -> Studio? {
        guard let id, !id.isEmpty else { return nil }
        return studios.first { $0.id == id }
    }

    static func spot(_ id: String?, in spots: [Spot]) -> Spot? {
        guard let id, !id.isEmpty else { return nil }
        return spots.first { $0.id == id }
    }
}
