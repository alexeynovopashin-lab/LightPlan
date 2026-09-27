import Foundation
import LightPlanCore

/// Выезд, дорога и бронь в форме (итерация 24, шаг 4б; веб `tripAuto`,
/// `renderTripRow`, `roadBlocksNear`, `linkStops`).
extension EventForm {

    /// Город без регистра, «ё» и знаков (веб `cityNorm`): «Санкт-Петербург» и
    /// «санкт петербург» — один город.
    public static func cityNorm(_ v: String) -> String {
        let low = v.lowercased().replacingOccurrences(of: "ё", with: "е")
        let parts = low.split { !($0.isLetter || $0.isNumber || $0 == "_") }
        return parts.joined(separator: " ")
    }

    /// Выезд по паре «город съёмки — родной город» (веб `tripAuto`): не знаем
    /// одного из двух — молчим.
    public func tripAuto(home: String) -> Bool {
        let h = Self.cityNorm(home), t = Self.cityNorm(sessionPlace.town)
        guard !h.isEmpty, !t.isEmpty else { return false }
        return h != t
    }

    /// Выезд сейчас: правили руками — ответ человека, иначе — по городам.
    public func trip(home: String) -> Bool { tripManual ? tripOn : tripAuto(home: home) }

    /// Строка «Выезд» видна, пока город чужой, или выезд включён руками (веб `renderTripRow`).
    public func tripRowShown(home: String) -> Bool { mode != .meet && (tripAuto(home: home) || trip(home: home)) }

    /// Тумблер «Выезд»: с этого момента приложение держит ответ человека.
    public mutating func setTrip(_ on: Bool) {
        tripOn = on
        tripManual = true
    }

    /// Дорога этой поездки (веб `roadBlocksNear`): «Дорога» и «Перелёт» в трёх днях
    /// от съёмки или накрывающие её день. Связи «блок ↔ съёмка» нет намеренно.
    public static func roadBlocks(near day: CivilDate, in blocks: [Block]) -> [Block] {
        let t = day.ordinal
        return blocks.filter { b in
            guard b.kind == .road || b.kind == .flight else { return false }
            let d = b.from.ordinal
            let last = d + (b.allDay ? max(1, b.days) : 1) - 1
            return (t - d <= 3 && d - t <= 3) || (t >= d && t <= last)
        }.sorted { $0.from.ordinal < $1.from.ordinal }
    }

    /// Студия, которую спрашивают о брони: только студия первой точки и только
    /// с ключом (веб `linkStops`).
    public func linkStudio(studios: [Studio]) -> Studio? {
        guard mode != .meet, let r = route.first, let st = Stops.studio(r.studioId, in: studios),
              !st.key.isEmpty else { return nil }
        return st
    }

    /// Ответ студии о брони ложится в первую точку (веб `#fLinkRow`): бронь —
    /// источник правды о зале и часах.
    public mutating func applyBooking(ref: String, hallId: String?, start: Int?, end: Int?,
                                      label: (String, String) -> String, spots: [Spot], studios: [Studio]) {
        bookingRef = ref
        guard let st = Stops.studio(route.first?.studioId, in: studios) else { return }
        editStop(0, spots: spots, studios: studios) { r in
            if let h = hallId {
                r.hallId = h
                if let hall = st.halls.first(where: { $0.id == h }) { r.placeText = label(st.name, hall.name) }
            }
            if let start { r.start = start }
            if let end { r.end = end }
        }
    }
}
