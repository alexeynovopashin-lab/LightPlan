import Foundation

/// Снисходительное чтение снимка (итерация 12, `docs/17` § 6: «читается
/// только текущий формат»). «Текущий формат» не значит «доверяем слепо»:
/// файл мог прийти с телефона другой версии или пострадать в пути. Каждое
/// поле-код здесь заводится так же, как в модели — незнакомое или пустое
/// становится `nil`/умолчанием, а не роняет весь импорт (`Session.swift`,
/// «незнакомый или пустой — nil»). Кидает только явная порча значения
/// (строка вместо числа, число вместо строки) — не порча *словаря*.
extension KeyedDecodingContainer {
    /// Код есть, но незнакомый (веб `warn`, `type` без соответствия) — `nil`,
    /// как у пустого поля. Ключа нет вовсе — тоже `nil`.
    public func decodeLenient<T: RawRepresentable & Sendable>(
        _ type: T.Type, forKey key: Key
    ) throws -> T? where T.RawValue == String {
        guard let raw = try decodeIfPresent(String.self, forKey: key), !raw.isEmpty else { return nil }
        return T(rawValue: raw)
    }

    /// Как выше, но со своим умолчанием у поля без `nil` в домене (веб
    /// «отсутствие ключа — …», `RecordKind.shoot`).
    public func decodeLenient<T: RawRepresentable & Sendable>(
        _ type: T.Type, forKey key: Key, default def: T
    ) throws -> T where T.RawValue == String {
        try decodeLenient(type, forKey: key) ?? def
    }

    /// Список кодов, отбрасывая незнакомые молча (веб `equipment[]`,
    /// `genres[]`): один чужой код не должен стереть весь список.
    public func decodeLenientArray<T: RawRepresentable & Sendable>(
        _ type: T.Type, forKey key: Key
    ) throws -> [T] where T.RawValue == String {
        let raw = try decodeIfPresent([String].self, forKey: key) ?? []
        return raw.compactMap(T.init(rawValue:))
    }

    /// Словарь, ключи которого — коды (веб `genrePrefs{}`). Значение не
    /// разбирается само — вызывающий решает, чем декодировать.
    public func decodeLenientDictionary<Code: RawRepresentable & Sendable, Value: Decodable>(
        keyedBy keyType: Code.Type, valueType: Value.Type, forKey key: Key
    ) throws -> [Code: Value] where Code.RawValue == String {
        guard let raw = try decodeIfPresent([String: Value].self, forKey: key) else { return [:] }
        var out: [Code: Value] = [:]
        for (k, v) in raw { if let code = Code(rawValue: k) { out[code] = v } }
        return out
    }

    /// Словарь код → список кодов (веб `cardOrder{}`, `cardOff{}`): и ключ
    /// группы, и элемент списка — коды, оба снисходительные. Правка блоков
    /// карточки — не то, из-за чего стоит терять всю запись.
    public func decodeLenientDictionaryOfArrays<Code: RawRepresentable & Sendable, Element: RawRepresentable & Sendable>(
        keyedBy keyType: Code.Type, elementType: Element.Type, forKey key: Key
    ) throws -> [Code: [Element]] where Code.RawValue == String, Element.RawValue == String {
        guard let raw = try decodeIfPresent([String: [String]].self, forKey: key) else { return [:] }
        var out: [Code: [Element]] = [:]
        for (k, list) in raw { if let code = Code(rawValue: k) { out[code] = list.compactMap(Element.init(rawValue:)) } }
        return out
    }
}

extension KeyedEncodingContainerProtocol {
    public mutating func encodeLenient<T: RawRepresentable>(
        _ value: T?, forKey key: Key
    ) throws where T.RawValue == String {
        try encodeIfPresent(value?.rawValue, forKey: key)
    }

    public mutating func encodeLenientArray<T: RawRepresentable>(
        _ value: [T], forKey key: Key
    ) throws where T.RawValue == String {
        try encode(value.map(\.rawValue), forKey: key)
    }

    public mutating func encodeLenientDictionary<K: RawRepresentable, V: Encodable>(
        _ value: [K: V], forKey key: Key
    ) throws where K.RawValue == String {
        var out: [String: V] = [:]
        for (k, v) in value { out[k.rawValue] = v }
        try encode(out, forKey: key)
    }

    public mutating func encodeLenientDictionaryOfArrays<K: RawRepresentable, V: RawRepresentable>(
        _ value: [K: [V]], forKey key: Key
    ) throws where K.RawValue == String, V.RawValue == String {
        var out: [String: [String]] = [:]
        for (k, list) in value { out[k.rawValue] = list.map(\.rawValue) }
        try encode(out, forKey: key)
    }
}
