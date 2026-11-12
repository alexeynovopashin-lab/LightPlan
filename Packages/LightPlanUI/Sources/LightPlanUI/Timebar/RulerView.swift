import SwiftUI
import LightPlanCore

/// Гравировка над дорожкой ползунка: риски каждый час, крупные каждые
/// шесть. Порт `drawRuler` (веб): часовые метки идут по настенным часам
/// (`h·60`), а не по окну суток, и рисуются только там, где час укладывается
/// в `mint…maxt` — окно бывает уже или шире полных суток.
struct RulerView: View {
    let solarDay: SolarDay
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme)
        Canvas { context, size in
            for h in 0..<48 {
                let t = Double(h) * 60
                guard t >= solarDay.mint, t <= solarDay.maxt else { continue }
                let x = (t - solarDay.mint) / 1440 * size.width
                let major = h % 6 == 0
                var path = Path()
                path.move(to: CGPoint(x: x, y: major ? 0 : size.height * 0.4))
                path.addLine(to: CGPoint(x: x, y: size.height))
                // `.ruler line` — `--rail-5`, крупная — `--ink-7`.
                context.stroke(path, with: .color(major ? pal.ink7 : pal.rail5), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 30з.1: цифры часов над рельсом, как на макете Алексея (12.11). Цифра — час риски по модулю 24: шкала идёт от истинного
/// полудня ±12 ч (`mint…maxt`), левого «0» у неё нет, полночь стоит там, где час 24 → «0». Каждые три часа, в тех же `x`, что риски
/// (`RulerView`: поле 13 с каждого края). Лежат в слое, который гнёт кольцо бегунка, — под пальцем их закрывает и искажает стекло,
/// цифры не прячутся и не поднимаются (Алексей: «бегунок должен закрывать цифры»). Поле 16 над рельсом уже было пустым — высота шкалы не растёт.
struct RulerDigits: View {
    let solarDay: SolarDay
    @Environment(\.colorScheme) private var colorScheme

    /// Час на цифре: каждые три, включая крайние, если те лежат на целом часе окна.
    static func hours(mint: Double, maxt: Double) -> [Int] {
        (0..<48).filter { h in h % 3 == 0 && Double(h) * 60 >= mint && Double(h) * 60 <= maxt }
    }

    static func label(_ h: Int) -> String { String(h % 24) }

    var body: some View {
        let pal = Palette(colorScheme)
        Canvas { context, size in
            let track = size.width - 26
            for h in Self.hours(mint: solarDay.mint, maxt: solarDay.maxt) {
                let x = 13 + (Double(h) * 60 - solarDay.mint) / 1440 * track
                let text = Text(Self.label(h))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(pal.ink4)
                context.draw(context.resolve(text), at: CGPoint(x: x, y: 8), anchor: .center)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
