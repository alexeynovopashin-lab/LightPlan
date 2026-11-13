import SwiftUI
import LightPlanCore

/// Гравировка под дорожкой ползунка. Метки и их ярусы даёт шкала (`DayScale.marks`): у «Света» и «Карты» (30з.4) — три яруса,
/// длинные под 0, 6, 12, 18, 24, средние под 3, 9, 15, 21, короткие на остальных часах и на обоих краях (23:00 и 01:00);
/// у AR — прежние два яруса по окну истинного полудня. Место риски — доля окна `start…end` на ширине холста; холст стоит с полем
/// 13 с каждого края (центр ручки на упоре), цифры (`RulerDigits`) считают `x` той же формулой.
struct RulerView: View {
    let marks: [DayScale.Mark]
    let start: Minutes
    let end: Minutes
    @Environment(\.colorScheme) private var colorScheme

    /// Доля высоты холста, которую занимает риска яруса.
    static func height(of tier: DayScale.Tier) -> Double {
        switch tier {
        case .long: 1
        case .medium: 0.7
        case .short: 0.4
        }
    }

    var body: some View {
        let pal = Palette(colorScheme)
        Canvas { context, size in
            for mark in marks {
                let x = DayScale.fraction(of: mark.minute, start: start, end: end) * size.width
                let major = mark.tier != .short
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height * (1 - Self.height(of: mark.tier))))
                path.addLine(to: CGPoint(x: x, y: size.height))
                // `.ruler line` — `--rail-5`, крупная — `--ink-7`.
                context.stroke(path, with: .color(major ? pal.ink7 : pal.rail5), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Цифры над рельсом (30з.1, макет Алексея 12.11; 30з.4 — шкала суток 0…24). Цифра — метка шкалы с `digit`: у «Света» 0, 3, 6, …, 24
/// (над двумя краевыми часами цифр нет), стоят в тех же `x`, что риски (`RulerView`: поле 13 с каждого края, доля окна шкалы).
/// Лежат в слое, который гнёт кольцо бегунка, — под пальцем их закрывает и искажает стекло, цифры не прячутся и не поднимаются
/// (Алексей: «бегунок должен закрывать цифры»). Поле 16 над рельсом уже было пустым — высота шкалы не растёт.
struct RulerDigits: View {
    let marks: [DayScale.Mark]
    let start: Minutes
    let end: Minutes
    /// Подпись метки в часах пользователя (`TimebarState.scaleLabel`).
    let label: (DayScale.Mark) -> String?
    @Environment(\.colorScheme) private var colorScheme

    /// Подписи цифр слева направо — то, что видно над рельсом.
    static func labels(_ marks: [DayScale.Mark]) -> [String] { marks.compactMap(\.digit) }

    /// Кегль и вес цифр шкалы — одно место для вида и для замеров ширины.
    static let font = Font.system(size: 11, weight: .medium).monospacedDigit()

    /// Поле с каждого края: половина ширины ручки (13). Центр ручки на упоре стоит в первой и последней риске.
    static let inset: CGFloat = 13

    var body: some View {
        let pal = Palette(colorScheme)
        Canvas { context, size in
            let track = size.width - 2 * Self.inset
            for mark in marks {
                guard let digit = label(mark) else { continue }
                let x = Self.inset + DayScale.fraction(of: mark.minute, start: start, end: end) * track
                let text = Text(digit)
                    .font(Self.font)
                    .foregroundColor(pal.ink4)
                context.draw(context.resolve(text), at: CGPoint(x: x, y: 8), anchor: .center)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
