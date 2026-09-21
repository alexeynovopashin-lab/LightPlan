import SwiftUI
import Synchronization

/// Знак, разобранный из строки библиотеки: части в координатах холста 24×24.
///
/// Строки пишет `Tools/icons2assets.js`; здесь только проигрывание готовых
/// команд пути (`M L C Q Z`, абсолютные). SVG Swift не разбирает — дуги,
/// относительные команды и примитивы сведены к этим пяти командам в генераторе.
struct IconArt: Sendable {

    /// Часть знака. Обычная красится общим цветом; у погоды части названы,
    /// чтобы солнце, облако и осадки красились врозь (`.i-sun` и др. в вебе).
    enum Role: String, Sendable {
        case body = ""
        case sun, cloud, rain
    }

    struct Part: Sendable {
        let role: Role
        /// Своя толщина в единицах холста 24×24; `nil` — толщину задаёт вызывающий.
        let width: CGFloat?
        /// Плоские концы. Нужны единственному знаку — флагу финиша: круглые концы
        /// раздули бы его клетки на полтолщины с каждой стороны.
        let butt: Bool
        let path: Path
    }

    let parts: [Part]

    // MARK: - Разбор

    /// Разбирает строку знака: части через перевод строки, поля части через табуляцию.
    static func decode(_ text: String) -> IconArt {
        var parts: [Part] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard f.count == 4 else { continue }
            parts.append(Part(
                role: Role(rawValue: String(f[0])) ?? .body,
                width: f[1].isEmpty ? nil : Double(f[1]).map { CGFloat($0) },
                butt: f[2] == "b",
                path: path(from: f[3])
            ))
        }
        return IconArt(parts: parts)
    }

    /// Абсолютные команды пути. Числа разделены пробелом, команды идут вплотную:
    /// `M12 3L4 5C1 2 3 4 5 6Z`.
    static func path(from text: Substring) -> Path {
        var path = Path()
        let u = Array(text.utf8)
        var i = 0
        var args: [CGFloat] = []

        func number() -> CGFloat? {
            var j = i
            while j < u.count, u[j] != 0x20, !isCommand(u[j]) { j += 1 }
            defer { i = j }
            guard j > i else { return nil }
            return Double(String(decoding: u[i..<j], as: UTF8.self)).map { CGFloat($0) }
        }
        func isCommand(_ c: UInt8) -> Bool { (c >= 0x41 && c <= 0x5A) }

        while i < u.count {
            let cmd = u[i]
            i += 1
            args.removeAll(keepingCapacity: true)
            while i < u.count {
                if u[i] == 0x20 { i += 1; continue }
                if isCommand(u[i]) { break }
                guard let n = number() else { break }
                args.append(n)
            }
            switch cmd {
            case UInt8(ascii: "M") where args.count >= 2:
                path.move(to: CGPoint(x: args[0], y: args[1]))
            case UInt8(ascii: "L") where args.count >= 2:
                path.addLine(to: CGPoint(x: args[0], y: args[1]))
            case UInt8(ascii: "C") where args.count >= 6:
                path.addCurve(to: CGPoint(x: args[4], y: args[5]),
                              control1: CGPoint(x: args[0], y: args[1]),
                              control2: CGPoint(x: args[2], y: args[3]))
            case UInt8(ascii: "Q") where args.count >= 4:
                path.addQuadCurve(to: CGPoint(x: args[2], y: args[3]),
                                  control: CGPoint(x: args[0], y: args[1]))
            case UInt8(ascii: "Z"):
                path.closeSubpath()
            default:
                assertionFailure("команда пути \(Character(UnicodeScalar(cmd))) с \(args.count) числами")
            }
        }
        return path
    }

    // MARK: - Кэш

    /// Разбор идёт один раз на знак: строк 216, а рисуют их сотни раз в кадре ленты.
    private static let cache = Mutex<[String: IconArt]>([:])

    static func art(namespace: String, name: String, in table: [String: String]) -> IconArt? {
        let key = namespace + ":" + name
        if let hit = cache.withLock({ $0[key] }) { return hit }
        guard let text = table[name] else { return nil }
        let art = decode(text)
        cache.withLock { $0[key] = art }
        return art
    }
}
