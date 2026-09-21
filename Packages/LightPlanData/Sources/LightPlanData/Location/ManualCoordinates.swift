import Foundation

/// Ручной ввод координат: два поля, широта и долгота.
///
/// В вебе разбора нет — место берётся с карты, поиска и геолокации. Правило
/// здесь новое и сделано узким: то, что печатает `GeoCoordinate.text`, читается
/// обратно, остальное отвергается с названием причины, а не молча превращается
/// в ноль.
public enum ManualCoordinates {

    public enum Failure: Error, Equatable, Sendable {
        case empty(Field)
        case notANumber(Field)
        case outOfRange(Field)
        /// Буква не той оси: «56.0 E» в поле широты.
        case wrongHemisphere(Field)
    }

    public enum Field: Sendable, Equatable { case latitude, longitude }

    public static func parse(latitude: String, longitude: String) -> Result<GeoCoordinate, Failure> {
        switch value(latitude, .latitude, positive: "N", negative: "S", limit: 90) {
        case .failure(let e): return .failure(e)
        case .success(let la):
            switch value(longitude, .longitude, positive: "E", negative: "W", limit: 180) {
            case .failure(let e): return .failure(e)
            case .success(let lo): return .success(GeoCoordinate(latitude: la, longitude: lo))
            }
        }
    }

    private static func value(_ raw: String, _ field: Field, positive: Character, negative: Character, limit: Double) -> Result<Double, Failure> {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: "\u{2212}", with: "-")     // типографский минус
        if s.isEmpty { return .failure(.empty(field)) }
        var sign = 1.0
        if let last = s.last, last.isLetter {
            switch last.uppercased() {
            case String(positive): break
            case String(negative): sign = -1
            case "N", "S", "E", "W": return .failure(.wrongHemisphere(field))
            default: return .failure(.notANumber(field))
            }
            s = String(s.dropLast()).trimmingCharacters(in: .whitespaces)
            // Буква и минус вместе («-33.8 S») читаются двояко — не угадываем.
            if s.hasPrefix("-") || s.hasPrefix("+") { return .failure(.notANumber(field)) }
        }
        // Запятая — десятичный разделитель, как в русской клавиатуре.
        s = s.replacingOccurrences(of: ",", with: ".")
        guard let number = strictDouble(s) else { return .failure(.notANumber(field)) }
        let v = number * sign
        guard abs(v) <= limit else { return .failure(.outOfRange(field)) }
        return .success(v)
    }

    /// `Double("1e5")` и `Double("0x10")` читаются, а место так вводить не станут.
    private static func strictDouble(_ s: String) -> Double? {
        var body = Substring(s)
        if body.first == "-" || body.first == "+" { body = body.dropFirst() }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, !body.isEmpty,
              parts.allSatisfy({ $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }),
              parts.contains(where: { !$0.isEmpty }) else { return nil }
        return Double(s)
    }
}
