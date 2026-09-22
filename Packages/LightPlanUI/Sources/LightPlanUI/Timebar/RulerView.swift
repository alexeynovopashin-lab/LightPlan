import SwiftUI
import LightPlanCore

/// Гравировка над дорожкой ползунка: риски каждый час, крупные каждые
/// шесть. Порт `drawRuler` (веб): часовые метки идут по настенным часам
/// (`h·60`), а не по окну суток, и рисуются только там, где час укладывается
/// в `mint…maxt` — окно бывает уже или шире полных суток.
struct RulerView: View {
    let solarDay: SolarDay

    var body: some View {
        Canvas { context, size in
            for h in 0..<48 {
                let t = Double(h) * 60
                guard t >= solarDay.mint, t <= solarDay.maxt else { continue }
                let x = (t - solarDay.mint) / 1440 * size.width
                let major = h % 6 == 0
                var path = Path()
                path.move(to: CGPoint(x: x, y: major ? 0 : size.height * 0.4))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(Color(white: major ? 0.75 : 0.4)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}
