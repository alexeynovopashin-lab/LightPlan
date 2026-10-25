import SwiftUI
import LightPlanDomain

/// Знаки мессенджеров для кнопки «написать» (поле-1, п. 5; Алексей 25.10: «заменять на иконку выбранного мессенджера»).
///
/// Своя таблица, не `IconLibrary`: та генерируется из `beta/icons.js` (`make icons`), а в вебе этих знаков нет и не будет
/// (веб заморожен), — всё, что лежит в генерируемом файле, перезаписывается. Здесь тот же формат строки знака
/// (`IconArt.decode`: части, команды `M L C Q Z`) и тот же холст 24×24, поэтому рисует их тот же `Icon`: линия толщины
/// окружения, цвет из `.foregroundStyle` — как у остальных знаков карточки.
///
/// Это узнаваемые силуэты одной линией, не фирменные логотипы и не цвета брендов (слово Алексея: «одним цветом»):
/// Telegram — бумажный самолётик, WhatsApp — круглое облачко с хвостиком и трубкой, VK — квадрат с буквами, Instagram —
/// квадрат с объективом и точкой, MAX — облачко с буквой «M». Нарисованы вручную; как выглядят на экране — по снимкам
/// `Tools/shots/clients.js` (`head-msg`), на телефоне Алексея не смотрели.
enum MessengerGlyph {

    static func art(_ kind: MessengerKind) -> IconArt {
        IconArt.decode(cache[kind] ?? "")
    }

    /// Строки знаков по виду мессенджера. Часть — одна линия `\t\t\t<команды>`.
    private static let cache: [MessengerKind: String] = {
        func part(_ commands: String...) -> String { commands.map { "\t\t\t" + $0 }.joined(separator: "\n") }
        return [
            .telegram: part("M21 3L14.8 20.8L10.3 13.7L3.2 9.7L21 3Z", "M21 3L10.3 13.7"),
            .whatsapp: part(circle(12, 11.7, 8.6), "M5.5 18.3L3.5 21L8 19.6",
                            "M9.6 8.2C9.1 8.2 8.4 8.8 8.4 9.8C8.4 12.9 11.2 15.4 14.2 15.4C15.2 15.4 15.9 14.8 15.9 14.3L15.9 13.9L13.8 12.9L13 13.7C12.1 13.3 10.9 12.1 10.4 11.1L11.2 10.3L10.2 8.2L9.6 8.2Z"),
            .vk: part(roundRect(2.8, 2.8, 18.4, 18.4, 5), "M6.5 9.3L9 15.2L11.5 9.3", "M13.5 9.3L13.5 15.2", "M18 9.3L14.7 12.2L18.2 15.2"),
            .instagram: part(roundRect(3, 3, 18, 18, 5.4), circle(12, 12, 4.2), "M17.3 6.7L17.4 6.7"),
            .max: part(roundRect(3, 3, 18, 15.6, 6.4), "M8.4 18.6L7.6 21.4L12.2 18.6", "M7.9 14.3L7.9 8.9L12 12.7L16.1 8.9L16.1 14.3"),
        ]
    }()

    // MARK: Заготовки контуров (команды абсолютные, числа через пробел)

    private static func n(_ v: Double) -> String { String(format: "%.2f", v) }

    static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> String {
        let k = 0.5523 * r
        let p: [(Double, Double)] = [
            (cx + r, cy), (cx + r, cy + k), (cx + k, cy + r), (cx, cy + r),
            (cx - k, cy + r), (cx - r, cy + k), (cx - r, cy),
            (cx - r, cy - k), (cx - k, cy - r), (cx, cy - r),
            (cx + k, cy - r), (cx + r, cy - k), (cx + r, cy),
        ]
        func c(_ i: Int) -> String { "C" + (i..<(i + 3)).map { n(p[$0].0) + " " + n(p[$0].1) }.joined(separator: " ") }
        return "M\(n(p[0].0)) \(n(p[0].1))" + c(1) + c(4) + c(7) + c(10) + "Z"
    }

    static func roundRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> String {
        let (x2, y2) = (x + w, y + h)
        return "M\(n(x + r)) \(n(y))L\(n(x2 - r)) \(n(y))Q\(n(x2)) \(n(y)) \(n(x2)) \(n(y + r))"
            + "L\(n(x2)) \(n(y2 - r))Q\(n(x2)) \(n(y2)) \(n(x2 - r)) \(n(y2))"
            + "L\(n(x + r)) \(n(y2))Q\(n(x)) \(n(y2)) \(n(x)) \(n(y2 - r))"
            + "L\(n(x)) \(n(y + r))Q\(n(x)) \(n(y)) \(n(x + r)) \(n(y))Z"
    }
}

extension Icon {
    /// Знак мессенджера для кнопки «написать»; цвет и толщину задаёт окружение, как у любого знака библиотеки.
    init(messenger kind: MessengerKind, size: CGFloat = 22, line: CGFloat = 1.5) {
        self.init(art: MessengerGlyph.art(kind), size: size, line: line, partStyles: [:])
    }
}
