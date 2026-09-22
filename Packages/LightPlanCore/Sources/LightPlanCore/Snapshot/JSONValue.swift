import Foundation

/// Значение JSON без схемы (итерация 12): поле снимка, которое Swift ещё не
/// разбирает по типам, проходит насквозь — прочитано и записано слово в
/// слово, каким бы оно ни было. Без этого типа `Store` был бы обязан знать
/// форму каждого ключа веба заранее, а веб пишет их десятками (`mapLayers`,
/// `zones`, `notif`, `shots`, `boards`, …) и добавляет новые. Здесь —
/// единственный способ не терять данные до того, как своя итерация даст
/// ключу настоящий тип.
public enum JSONValue: Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "неизвестная форма JSON")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
