import Foundation
import CoreLocation

/// Ответ поиска места по названию (`searchPlace` веба): имя, где оно, точка.
public struct PlaceHit: Sendable, Hashable {
    public let name: String
    /// «Томск, Томская область» — две части адреса после имени, как у веба.
    public let area: String
    public let coordinate: GeoCoordinate
    /// Как назвать это место в шапке «Света» и «Карты» (30и.1): город, который нашёл поиск, а не то, как
    /// обратный геокодер назовёт его точку — у «Токио» это точка ратуши в районе Синдзюку. `nil` — поиск
    /// города не назвал, имя спросят у обратного геокодера, как раньше.
    public let city: PlaceName?

    public init(name: String, area: String, coordinate: GeoCoordinate, city: PlaceName? = nil) {
        self.name = name; self.area = area; self.coordinate = coordinate; self.city = city
    }
}

/// Одна метка геокодера, сведённая к тому, что читают правила ответа поиска.
public struct PlaceMark: Sendable, Hashable {
    public var name: String?
    public var locality: String?
    public var region: String?
    public var country: String?
    /// Две буквы ISO (30и.12: подсказка города хранит код страны).
    public var isoCode: String?
    public var coordinate: GeoCoordinate

    public init(name: String?, locality: String?, region: String?, country: String? = nil,
                isoCode: String? = nil, coordinate: GeoCoordinate) {
        self.name = name; self.locality = locality; self.region = region
        self.country = country; self.isoCode = isoCode; self.coordinate = coordinate
    }
}

/// Поиск места листа «Где снимаем», путь «Место»: человек думает «Лагерный
/// сад», а не координатами. В отличие от `CityLookup`, отвечает чем угодно —
/// сквер, улица, дом, — а не только городом.
public protocol PlaceSearch: Sendable {
    /// До шести мест по набранной строке. Пустой ответ — не сбой.
    func places(matching query: String) async throws -> [PlaceHit]
}

/// Слова запроса и ответов: чем сверить «набрал — нашёл», как записать запасной запрос латиницей и как
/// вылечить имена, которые Apple отдаёт с латинскими буквами внутри кириллического слова.
public enum PlaceQuery {
    /// Латинские буквы, неотличимые на глаз от кириллических.
    private static let lookalike: [Character: Character] = [
        "A": "А", "B": "В", "C": "С", "E": "Е", "H": "Н", "K": "К", "M": "М", "O": "О", "P": "Р", "T": "Т",
        "X": "Х", "Y": "У", "a": "а", "c": "с", "e": "е", "o": "о", "p": "р", "x": "х", "y": "у",
    ]

    private static func isCyrillic(_ s: Unicode.Scalar) -> Bool { (0x400...0x4FF).contains(s.value) }
    private static func isLatin(_ s: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(s.value) || (0x61...0x7A).contains(s.value) || (0xC0...0x24F).contains(s.value)
    }

    /// «Toкиo» (замер 14.11.2026: у Apple «Токио» записан смесью — T, o, o латинские, к, и кириллические)
    /// → «Токио». Слово чинится, только если в нём есть кириллица и каждая латинская буква имеет двойника;
    /// «iPhone», «Москва-City» не трогаются.
    public static func cleaned(_ s: String) -> String {
        s.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let sc = word.unicodeScalars
            guard sc.contains(where: isCyrillic), sc.contains(where: isLatin) else { return String(word) }
            var out = ""
            for ch in word {
                if ch.unicodeScalars.allSatisfy(isLatin) {
                    guard let twin = lookalike[ch] else { return String(word) }
                    out.append(twin)
                } else { out.append(ch) }
            }
            return out
        }.joined(separator: " ")
    }

    /// Строка для сверки: регистр, «ё», двойники букв не мешают.
    public static func folded(_ s: String) -> String {
        cleaned(s).lowercased().replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Хватает ли набранного для вопроса геокодеру: три знака, а для китайских, японских и корейских
    /// названий — два (замер 14.11.2026: «東京» и «北京» — два знака, порог в три их не пускал вовсе).
    public static func isAskable(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.count >= 3 { return true }
        return q.count == 2 && q.unicodeScalars.allSatisfy { (0x3040...0x30FF).contains($0.value)
            || (0x3400...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) }
    }

    /// Запасной запрос латиницей. Замер 14.11.2026 (регион телефона — Россия): на «Токио» геокодер отвечал
    /// «Токи» (префектура Гифу), на «Tokio» — Токио. Только для названия места из одного-двух слов:
    /// адреса, номера домов и «Лагерный сад, Томск» латиница не лечит, а запрос стоит лимита Apple.
    public static func transliteration(of query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3, q.count <= 30, q.unicodeScalars.contains(where: isCyrillic) else { return nil }
        guard q.unicodeScalars.allSatisfy({ $0.properties.isAlphabetic || $0 == " " || $0 == "-" }) else { return nil }
        guard q.split(whereSeparator: { $0 == " " }).count <= 2 else { return nil }
        guard let latin = q.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false)
        else { return nil }
        // Знаки мягкости транслитерация оставляет буквами-модификаторами (U+02B9…): «Nʹu-Jork».
        let plain = String(latin.unicodeScalars.filter { !(0x2B0...0x2FF).contains($0.value) })
        return plain.count >= 3 ? plain : nil
    }

    /// Назвал ли ответ то, что набрали: по имени места или по его городу.
    public static func names(_ mark: PlaceMark, query: String) -> Bool {
        let q = folded(query)
        return [mark.name, mark.locality].compactMap { $0 }.contains { folded($0) == q }
    }

    /// Ответы, названные в точности как запрос, — вперёд; порядок внутри групп прежний.
    public static func exactFirst(_ marks: [PlaceMark], query: String) -> [PlaceMark] {
        marks.filter { names($0, query: query) } + marks.filter { !names($0, query: query) }
    }
}

/// `CLGeocoder` вместо Nominatim `search` веба — тот же геокодер, что у
/// `AppleCityLookup`, без фильтра «только город». Имя — `name` метки (у
/// сквера — его название, у дома — улица и номер), область — город и регион.
///
/// 30и.1: когда ни одна метка не названа так, как набрано, и запрос похож на название города, спрашивается
/// ещё раз — латиницей (`PlaceQuery.transliteration`); совпавшие по имени ответы идут первыми.
public struct ApplePlaceSearch: PlaceSearch {
    public let locale: Locale
    /// Страна, которую в подписи не повторяют (по умолчанию — страна региона телефона).
    public let homeCountry: String?

    public init(locale: Locale = Locale(identifier: "ru_RU"), homeCountry: String? = nil) {
        self.locale = locale
        self.homeCountry = homeCountry ?? Self.deviceCountry(in: locale)
    }

    /// «Россия» для телефона с регионом «Россия»; нет региона — подпись всегда с страной.
    public static func deviceCountry(in locale: Locale, region: String? = Locale.current.region?.identifier) -> String? {
        region.flatMap { locale.localizedString(forRegionCode: $0) }
    }

    public func places(matching query: String) async throws -> [PlaceHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard PlaceQuery.isAskable(q) else { return [] }
        let marks = try await Self.marks(matching: q, locale: locale)
        return Self.hits(marks, homeCountry: homeCountry)
    }

    /// Метки по набранной строке — один путь и для «Где снимаем», и для поиска города (30и.12): вопрос как
    /// набрано, при нужде второй — латиницей; названные как набрано идут первыми. Все ответы пусты и был
    /// сбой — сбой выбрасывается.
    public static func marks(matching q: String, locale: Locale) async throws -> [PlaceMark] {
        var marks: [PlaceMark] = []
        var failure: Error?
        do { marks = try await ask(q, locale: locale) } catch { failure = error }
        if let latin = PlaceQuery.transliteration(of: q), !marks.contains(where: { PlaceQuery.names($0, query: q) }) {
            do { marks += try await ask(latin, locale: locale) } catch { failure = failure ?? error }
        }
        if marks.isEmpty, let failure { throw failure }
        return PlaceQuery.exactFirst(marks, query: q)
    }

    private static func ask(_ text: String, locale: Locale) async throws -> [PlaceMark] {
        // Один `CLGeocoder` на запрос: на одном экземпляре второй запрос отменяет первый.
        let marks = try await CLGeocoder().geocodeAddressString(text, in: nil, preferredLocale: locale)
        return marks.compactMap { p in
            p.location.map { PlaceMark(name: p.name, locality: p.locality, region: p.administrativeArea,
                                       country: p.country, isoCode: p.isoCountryCode,
                                       coordinate: GeoCoordinate(latitude: $0.coordinate.latitude,
                                                                 longitude: $0.coordinate.longitude)) }
        }
    }

    /// Разбор меток отдельно от геокодера — его проверяют тесты.
    ///
    /// Показанное имя — `name` метки, а не её район: `subLocality` не читается нигде (замер 14.11.2026: у
    /// «Tokyo» его нет, «Синдзюку» приходит только из обратного геокодера по точке ответа). Район виден,
    /// лишь когда его набрали: тогда он и есть имя или город метки.
    static func hits(_ marks: [PlaceMark], homeCountry: String? = nil) -> [PlaceHit] {
        var seen = Set<String>()
        var out: [PlaceHit] = []
        for m in marks {
            let locality = m.locality.map(PlaceQuery.cleaned)
            let region = m.region.map(PlaceQuery.cleaned)
            let country = m.country.map(PlaceQuery.cleaned)
            guard let name = (m.name.map(PlaceQuery.cleaned) ?? locality)?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { continue }
            let foreign = country.flatMap { $0 == homeCountry ? nil : $0 }
            let area = [locality, region, foreign].compactMap { $0 }.filter { !$0.isEmpty && $0 != name }
                .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                .joined(separator: ", ")
            guard seen.insert(name + "|" + area).inserted else { continue }
            // Нет города у метки (Токио, Бали, страна) — она сама и есть «город».
            let city = PlaceNameRules.name(locality: (locality?.isEmpty == false ? locality : nil) ?? name,
                                           region: region, country: country)
            out.append(PlaceHit(name: name, area: area, coordinate: m.coordinate, city: city))
            if out.count == 6 { break }
        }
        return out
    }
}
