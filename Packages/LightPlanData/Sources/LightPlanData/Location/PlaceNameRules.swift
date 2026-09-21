import Foundation

/// Имя места: крупно город, мелко уточнение (область или страна).
public struct PlaceName: Sendable, Hashable {
    public let city: String
    public let sub: String

    public init(city: String, sub: String) {
        self.city = city
        self.sub = sub
    }
}

/// Правила выбора и чистки имени — продукт, а не деталь геокодера
/// (`docs/17` § 4.7; веб `cleanPlace`, `fetchGeoName`).
///
/// **Место — населённый пункт.** Область и район местом не являются:
/// «Московская область» — не то, куда едут снимать. Заглушки вроде «Место не
/// определено» отбрасываются: пусть остаются координаты. Курорт, гору и
/// урочище именуют руками — там геокодеру верить нечему.
public enum PlaceNameRules {

    /// Веб `cleanPlace`. Пустая строка — «это не место».
    public static func cleanPlace(_ raw: String?) -> String {
        let n = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || n.contains(placeholder) { return "" }
        // Геокодер кладёт в поле города административную единицу целиком:
        // «Городской округ город Томск». Населённый пункт внутри неё есть.
        if let m = n.firstMatch(of: embedded) { return String(m.1).trimmingCharacters(in: .whitespacesAndNewlines) }
        // Единица без имени населённого пункта местом не является.
        if n.contains(unit) { return "" }
        return n
    }

    /// Что показать по ответу геокодера: город из `locality`, уточнение — регион,
    /// иначе страна. Нет города — `nil`: шапка остаётся на координатах.
    ///
    /// Не перенесено намеренно: правило веба «имя равно региону — это область,
    /// выданная за город, кроме столиц» (`settlement`/`isCity`). Оно читает
    /// справку BigDataCloud, которой у `CLPlacemark` нет, а `locality` у Apple
    /// населённый пункт по построению; Москва, Берлин, Севастополь, Петербург
    /// назвали бы себя областью и потерялись (замер 21.09.2026, DECISIONS
    /// «Локация»).
    public static func name(locality: String?, region: String?, country: String?) -> PlaceName? {
        let city = cleanPlace(locality)
        guard !city.isEmpty else { return nil }
        // `a || b` в JS пропускает только пустую строку, не «пробелы»: тримим после выбора.
        let pick = (region ?? "").isEmpty ? (country ?? "") : (region ?? "")
        var sub = pick.trimmingCharacters(in: .whitespacesAndNewlines)
        // У городов федерального значения регион зовётся так же, как город, и
        // уточнение повторяло бы имя: «Санкт-Петербург» под «Санкт-Петербургом».
        if sub == city { sub = "" }
        return PlaceName(city: city, sub: sub)
    }

    // JS без флага `u`: `i` сравнивает по верхнему регистру, кириллица работает.
    nonisolated(unsafe) private static let placeholder = /не опред|неизвест|unknown/.ignoresCase()
    nonisolated(unsafe) private static let embedded =
        /(?:^|\s)(?:город|посёлок|поселок|село|деревня|станица|хутор|аул|слобода)\s+([А-ЯЁ][^,]*)$/
    nonisolated(unsafe) private static let unit =
        /район|округ|поселени|сельсовет|муниципальн|область|край|республик|улус/.ignoresCase()
}
