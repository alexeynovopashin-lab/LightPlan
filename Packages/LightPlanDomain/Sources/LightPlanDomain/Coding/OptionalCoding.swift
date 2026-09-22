import Foundation

extension KeyedDecodingContainer {
    /// `deadlineChoice` (веб): строка `"auto"` или отсутствие ключа — `.auto`;
    /// число — свой срок днями; `null` — без срока.
    public func decodeDeadlineChoice(forKey key: Key, default def: DeadlineChoice = .auto) throws -> DeadlineChoice {
        try decodeDeadlineChoiceIfPresent(forKey: key) ?? def
    }

    /// Как выше, но раз отличает «ключа нет» от «есть значение»: нужно
    /// `GenrePrefs.deadline`, где отсутствие значит «правки нет», а не «как
    /// заведено» — это разные вещи для формы (`docs/17`).
    public func decodeDeadlineChoiceIfPresent(forKey key: Key) throws -> DeadlineChoice? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) { return DeadlineChoice.none }
        if let n = try? decode(Int.self, forKey: key) { return .days(n) }
        return .auto
    }

    /// Троичное поле веба: ключа нет — «правки нет» (`nil`), `null` —
    /// «явно пусто» (`.some(nil)`, «по свету» у `GenrePrefs.duration`),
    /// значение — `.some(.some(v))`.
    public func decodeTriState<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T?? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) { return .some(nil) }
        return .some(try decode(T.self, forKey: key))
    }
}

extension KeyedEncodingContainerProtocol {
    public mutating func encodeDeadlineChoice(_ value: DeadlineChoice, forKey key: Key) throws {
        switch value {
        case .auto: try encode("auto", forKey: key)
        case .days(let n): try encode(n, forKey: key)
        case .none: try encodeNil(forKey: key)
        }
    }

    public mutating func encodeDeadlineChoiceIfPresent(_ value: DeadlineChoice?, forKey key: Key) throws {
        guard let value else { return }
        try encodeDeadlineChoice(value, forKey: key)
    }

    public mutating func encodeTriState<T: Encodable>(_ value: T??, forKey key: Key) throws {
        guard let outer = value else { return }
        guard let inner = outer else { try encodeNil(forKey: key); return }
        try encode(inner, forKey: key)
    }
}
