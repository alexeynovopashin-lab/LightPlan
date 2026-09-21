import Foundation

/// Всё, что стоит на карте точкой. Итерация 11 (домен) делает `Spot` таким же:
/// поиск по допуску не должен знать, чья это запись.
public protocol Located {
    var coordinate: GeoCoordinate { get }
}

/// Сохранённые точки: совпадение с допуском и нумерация одинаковых имён.
public enum SavedPoints {

    /// Индекс первой точки, лежащей в допуске 60 м от места (веб `spotHere`).
    public static func firstIndex<C: Collection>(near place: GeoCoordinate, in points: C) -> Int? where C.Element: Located {
        for (i, p) in points.enumerated() where p.coordinate.isSameSpot(as: place) { return i }
        return nil
    }

    /// Имя, которого ещё нет в списке (веб `uniqueSpotName`): «Лобня» → «Лобня 2».
    ///
    /// Считается по началу имени, а не по точному совпадению — иначе «Лобня 2»
    /// родила бы «Лобня 2» второй раз. Пустое имя не нумеруется: у безымянной
    /// точки в списке стоят координаты. Хвост должен быть ровно «пробел и
    /// цифры»: «Лобня 02» считается двойкой, «Лобня  2» и «Лобня 2x» — нет.
    public static func uniqueName(_ base: String, existing: [String]) -> String {
        if base.isEmpty { return base }
        var busy = false
        var highest = 1
        for name in existing {
            if name == base { busy = true; continue }
            guard name.hasPrefix(base) else { continue }
            let tail = name.dropFirst(base.count)
            guard tail.first == " " else { continue }
            let digits = tail.dropFirst()
            guard !digits.isEmpty, digits.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { continue }
            busy = true
            highest = max(highest, Int(digits) ?? Int.max - 1)
        }
        return busy ? "\(base) \(highest + 1)" : base
    }
}
