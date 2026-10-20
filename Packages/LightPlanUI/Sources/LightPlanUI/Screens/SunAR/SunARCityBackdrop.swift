#if DEBUG
import SwiftUI

/// Отладочный кадр «город днём» (`-LPSunARBackdrop city`, шаг 29.8в.18): светлое голубое небо и силуэт зданий — тёмные
/// блоки с окнами. На нём мерится затемняющая маска (`Tools/ar_mask.py`): остаток яркости неба и разница небо − здание, по
/// которой контуры зданий угадываются сквозь маску. Области замера — узлы `ar.city.sky` и `ar.city.building`.
struct SunARCityBackdrop: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(.sRGB, red: 0.45, green: 0.68, blue: 0.93), Color(.sRGB, red: 0.78, green: 0.88, blue: 0.97)],
                               startPoint: .top, endPoint: .bottom)
                // Силуэт: пять блоков разной высоты от нижнего края. Крыша каждого — резкая кромка на фоне неба.
                ForEach(Array([(0.00, 0.34, 0.55), (0.30, 0.26, 0.48), (0.52, 0.22, 0.60), (0.70, 0.18, 0.50), (0.86, 0.14, 0.56)].enumerated()), id: \.offset) { _, b in
                    Rectangle().fill(Color(.sRGB, white: 0.22))
                        .frame(width: w * b.1, height: h * (1 - b.2))
                        .offset(x: w * b.0, y: h * b.2)
                }
                // Окна — светлее стены, но темнее неба.
                ForEach(0..<40, id: \.self) { i in
                    Rectangle().fill(Color(.sRGB, white: 0.45))
                        .frame(width: 10, height: 14)
                        .offset(x: w * 0.04 + CGFloat(i % 8) * 30, y: h * 0.66 + CGFloat(i / 8) * 40)
                }
                // Области замера: небо — над крышами, где нет кнопок и панели; здание — стена третьего блока (окон там нет).
                Color.clear.frame(width: w * 0.5, height: h * 0.06)
                    .shotNode("ar.city.sky", text: "sky")
                    .offset(x: w * 0.25, y: h * 0.30)
                Color.clear.frame(width: w * 0.14, height: h * 0.04)
                    .shotNode("ar.city.building", text: "building")
                    .offset(x: w * 0.56, y: h * 0.66)
            }
            .frame(width: w, height: h)
        }
    }
}
#endif
