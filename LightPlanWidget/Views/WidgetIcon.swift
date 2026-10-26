import SwiftUI
import Synchronization

/// Знак точки в виджете (30б.2в-2). Расширение `LightPlanUI` не линкует, поэтому знаки лежат в нём отдельно:
/// `WidgetIcons.generated.swift` — строки знаков библиотеки приложения, как они есть (`Tools/widget_icons.py`), а здесь их разбор
/// и рисование. Разбор — тот же, что у `IconArt` приложения; расхождение путей ловит `WidgetIconTests` (пути обоих сравниваются
/// знак за знаком по всей таблице), так что копия не уходит молча.
///
/// Какой знак у точки, решает приложение (`PointSign.name`) и пишет его имя в `widget.json` (`Stop.sign`); нет имени или знака
/// в таблице — кружок.
struct WidgetIcon: View {
    let name: String?
    var size: CGFloat = 16
    var line: CGFloat = 1.7
    /// `name` — код жанра (знак шапки среднего и малого вида, 30б.2в-4), а не знак точки; неизвестный код — камера, как `Icon(genre:)`.
    var genre = false

    var body: some View {
        let parts = genre ? WidgetIconArt.parts(genre: name) : WidgetIconArt.parts(name)
        let k = size / 24
        ZStack {
            ForEach(parts.indices, id: \.self) { i in
                WidgetIconOutline(path: parts[i].path)
                    .stroke(style: StrokeStyle(lineWidth: (parts[i].width ?? line) * k,
                                               lineCap: parts[i].butt ? .butt : .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Путь на холсте 24 × 24, растянутый на прямоугольник.
struct WidgetIconOutline: Shape {
    let path: Path
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        return path.applying(CGAffineTransform(scaleX: k, y: k)).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

enum WidgetIconArt {
    struct Part {
        /// Своя толщина в единицах холста; `nil` — задаёт вызывающий.
        let width: CGFloat?
        let butt: Bool
        let path: Path
    }

    private static let cache = Mutex<[String: [Part]]>([:])

    static func parts(_ name: String?) -> [Part] {
        let key = name.flatMap { WidgetIconTable.common[$0] != nil ? $0 : nil } ?? "dot"
        if let hit = cache.withLock({ $0[key] }) { return hit }
        let decoded = decode(WidgetIconTable.common[key] ?? "")
        cache.withLock { $0[key] = decoded }
        return decoded
    }

    /// Знак жанра по коду (`WidgetIconTable.genres`); нет такого — камера точек.
    static func parts(genre code: String?) -> [Part] {
        guard let code, let text = WidgetIconTable.genres[code] else { return parts("camera") }
        let key = "genre:" + code
        if let hit = cache.withLock({ $0[key] }) { return hit }
        let decoded = decode(text)
        cache.withLock { $0[key] = decoded }
        return decoded
    }

    /// Строка знака: части через перевод строки, поля части (роль, ширина, концы, команды) через табуляцию.
    static func decode(_ text: String) -> [Part] {
        var parts: [Part] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard f.count == 4 else { continue }
            parts.append(Part(width: f[1].isEmpty ? nil : Double(f[1]).map { CGFloat($0) }, butt: f[2] == "b", path: path(from: f[3])))
        }
        return parts
    }

    /// Абсолютные команды `M L C Q Z`, числа через пробел, команды вплотную.
    static func path(from text: Substring) -> Path {
        var path = Path()
        let u = Array(text.utf8)
        var i = 0
        var args: [CGFloat] = []
        func isCommand(_ c: UInt8) -> Bool { c >= 0x41 && c <= 0x5A }
        func number() -> CGFloat? {
            var j = i
            while j < u.count, u[j] != 0x20, !isCommand(u[j]) { j += 1 }
            defer { i = j }
            guard j > i else { return nil }
            return Double(String(decoding: u[i..<j], as: UTF8.self)).map { CGFloat($0) }
        }
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
            case UInt8(ascii: "M") where args.count >= 2: path.move(to: CGPoint(x: args[0], y: args[1]))
            case UInt8(ascii: "L") where args.count >= 2: path.addLine(to: CGPoint(x: args[0], y: args[1]))
            case UInt8(ascii: "C") where args.count >= 6:
                path.addCurve(to: CGPoint(x: args[4], y: args[5]), control1: CGPoint(x: args[0], y: args[1]), control2: CGPoint(x: args[2], y: args[3]))
            case UInt8(ascii: "Q") where args.count >= 4:
                path.addQuadCurve(to: CGPoint(x: args[2], y: args[3]), control: CGPoint(x: args[0], y: args[1]))
            case UInt8(ascii: "Z"): path.closeSubpath()
            default: break
            }
        }
        return path
    }
}
