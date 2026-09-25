import SwiftUI

/// Знаки листа «Где снимаем», которых нет в библиотеке `icons.js`: веб рисует
/// их прямо в разметке листа (`#locSheet`) инлайновым SVG. Пути — те же, в
/// поле 24 × 24; толщина линии — из CSS веба, у каждого своя.
enum PlaceGlyph {
    /// Лупа поиска (`.loc-search svg`): круг r 7 в (11, 11) и ручка до (21, 21).
    case search
    /// Карандаш строки места (`.spot-edit`).
    case pencil
    /// Крестик строки места (`.spot-del`).
    case cross
    /// Прицел «Подставить моё место» (`.loc-detect`): круг r 4 и четыре риски.
    case detect

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        switch self {
        case .search:
            path.addEllipse(in: CGRect(origin: p(4, 4), size: CGSize(width: 14 * k, height: 14 * k)))
            path.move(to: p(16.5, 16.5)); path.addLine(to: p(21, 21))
        case .pencil:
            // M4 20h4L18.5 9.5a2 2 0 0 0-3-3L5 17v3z — дуга r 2 от (18.5, 9.5)
            // к (15.5, 6.5) против часовой: центр (17, 8) — середина хорды.
            path.move(to: p(4, 20)); path.addLine(to: p(8, 20)); path.addLine(to: p(18.5, 9.5))
            path.addArc(center: p(17, 8), radius: 2.121 * k, startAngle: .degrees(45), endAngle: .degrees(225),
                        clockwise: true)
            path.addLine(to: p(5, 17)); path.addLine(to: p(5, 20)); path.closeSubpath()
        case .cross:
            path.move(to: p(6, 6)); path.addLine(to: p(18, 18))
            path.move(to: p(18, 6)); path.addLine(to: p(6, 18))
        case .detect:
            path.addEllipse(in: CGRect(origin: p(8, 8), size: CGSize(width: 8 * k, height: 8 * k)))
            for (a, b) in [(p(12, 2), p(12, 5)), (p(12, 19), p(12, 22)), (p(2, 12), p(5, 12)), (p(19, 12), p(22, 12))] {
                path.move(to: a); path.addLine(to: b)
            }
        }
        return path
    }
}

/// Знак листа линией: размер и толщина — как у веба.
struct PlaceGlyphView: View {
    let glyph: PlaceGlyph
    let size: CGFloat
    let line: CGFloat

    var body: some View {
        GlyphShape(glyph: glyph)
            .stroke(style: StrokeStyle(lineWidth: line * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }

    private struct GlyphShape: Shape {
        let glyph: PlaceGlyph
        func path(in rect: CGRect) -> Path { glyph.path(in: rect) }
    }
}

/// Булавка у имени места в шапке «Света» и «Карты» (`.loc-pin`): 13, линия
/// 1,6, `--ink-6`; пока палец на кнопке — латунь (`.loc:active .loc-pin`).
struct PlacePin: View {
    let pal: Palette
    @Environment(\.placePressed) private var pressed

    var body: some View {
        Icon("pin", size: 13, line: 1.6).foregroundStyle(pressed ? pal.brass : pal.ink6)
    }
}

/// Кнопка места в шапке: сама не тускнеет, нажатие говорит булавкой.
struct PlaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.placePressed, configuration.isPressed)
    }
}

extension EnvironmentValues {
    @Entry var placePressed = false
}
