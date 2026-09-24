import Foundation

/// Точка на земле: градусы, север и восток положительны.
///
/// Свой тип, а не `CLLocationCoordinate2D`: слой Data остаётся проверяемым без
/// CoreLocation, а `Place` из Core требует ещё и зону.
public struct GeoCoordinate: Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Допуск закладки — «примерно 60 метров»: карта ездит под пальцем, и
    /// попасть в ту же тысячную долю градуса невозможно (веб `sameSpot`).
    /// Квадрат по обеим осям, строго меньше, без поправки на широту — как в вебе.
    public static let sameSpotTolerance = 0.0006

    public func isSameSpot(as other: GeoCoordinate) -> Bool {
        abs(latitude - other.latitude) < Self.sameSpotTolerance
            && abs(longitude - other.longitude) < Self.sameSpotTolerance
    }

    /// Подпись координатами (веб `coordText`): «56.011 N · 37.483 E».
    public var text: String {
        JSNumber.fixed(abs(latitude), 3) + (latitude >= 0 ? " N" : " S")
            + " · " + JSNumber.fixed(abs(longitude), 3) + (longitude >= 0 ? " E" : " W")
    }

    /// Ключ имени места: пока он тот же, спрашивать геокодер не о чем
    /// (веб `LAT.toFixed(3) + "," + LON.toFixed(3)`).
    public var nameKey: String {
        JSNumber.fixed(latitude, 3) + "," + JSNumber.fixed(longitude, 3)
    }
}

/// Числа так, как их печатает JavaScript.
///
/// `String(format:)` округляет ровно посередине к чётному, `toFixed` — вверх, и
/// «0.0625» даёт «0.063» там и «0.062» здесь. Веб — эталон подписей, поэтому
/// правило веба и повторено. Решает первая отброшенная цифра точного
/// десятичного разложения: пять и больше — вверх, включая точную середину.
public enum JSNumber {
    public static func fixed(_ x: Double, _ digits: Int) -> String {
        precondition(digits >= 0 && digits <= 12)
        guard x.isFinite else { return x.isNaN ? "NaN" : (x < 0 ? "-Infinity" : "Infinity") }
        let negative = x < 0                    // −0 знака не получает: `-0 < 0` ложь, как в JS
        let exact = String(format: "%.40f", negative ? -x : x)
        let parts = exact.split(separator: ".", omittingEmptySubsequences: false)
        var kept = Array((parts[0] + parts[1].prefix(digits)).utf8).map { Int($0) - 48 }
        if Int(parts[1].utf8.dropFirst(digits).first ?? 48) - 48 >= 5 {
            var i = kept.count - 1
            while i >= 0 {
                if kept[i] == 9 { kept[i] = 0; i -= 1 } else { kept[i] += 1; break }
            }
            if i < 0 { kept.insert(1, at: 0) }
        }
        let digitsText = kept.map(String.init).joined()
        let intPart = digitsText.dropLast(digits)
        let frac = digitsText.suffix(digits)
        return (negative ? "-" : "") + intPart + (digits > 0 ? "." + frac : "")
    }

    /// `Math.round`: половина уходит к плюс-бесконечности, не от нуля.
    static func round(_ x: Double) -> Double { (x + 0.5).rounded(.down) }
}
