import SwiftUI

/// Каким стеклом нарисованы диски солнца и луны (шаг 29.8в.9а). Слово Алексея 18.10: «возможно когда корректировали
/// отрисовку использовали не нативное стекло». Опыт: системное `.glassEffect` против своего (слой Metal по кадру,
/// линза-копия дуги, налёт). Выбор — флаг устройства, как луна и калибровка; в выпуске всегда по умолчанию.
enum SunARGlassStyle: String, CaseIterable {
    /// Своё: кадр камеры гнёт слой Metal (`ARLensRenderer`), дугу — линза-копия (`LensRefraction`), налёт рисован.
    case own
    /// Системное `.glassEffect` на круге: гнёт то, что под ним в окне, блик и кромка у стекла свои.
    case system

    static let key = "lightplan.native.sunar.glass"
    static let fallback: SunARGlassStyle = .system

    /// Выбранное стекло. В отладке — флаг устройства (`-lightplan.native.sunar.glass system` или переключатель на
    /// экране AR); в выпуске — `fallback`.
    static func current(_ defaults: UserDefaults = .standard) -> SunARGlassStyle {
        #if DEBUG
        return defaults.string(forKey: key).flatMap(SunARGlassStyle.init(rawValue:)) ?? fallback
        #else
        return fallback
        #endif
    }

    #if DEBUG
    static func set(_ style: SunARGlassStyle, _ defaults: UserDefaults = .standard) {
        defaults.set(style.rawValue, forKey: key)
    }
    #endif
}

/// Диск системным стеклом: круг `.glassEffect(.clear)` с оттенком метки, двигается только положением (правило 28п:
/// под `scaleEffect`/`rotationEffect` стекло раздувается в прямоугольник слоя). Стекло само гнёт всё, что под ним в
/// окне: кадр, дугу, другой диск (замер `Tools/ar_glass.py`, 29.8в.9а); блик и кромка у него свои, тени нет.
///
/// Солнце — окрашенное стекло, как в 29.8в.6: цвет света слоем «умножение» ПОВЕРХ стекла. Без него системное стекло
/// на белом небе выцветает (насыщенность золотого часа 0,26 при цели 0,55); слой под стеклом не спасает синий час и
/// призрак (0,26–0,38 при цели 0,40); поверх — все цели выполнены (`Tools/ar_disc_sat.py`). Блик под «умножением»
/// окрашивается, но остаётся светлее диска. Луна — фаза поверх стекла. Призрак — тише оттенок и фаза.
struct SunARSystemGlassMark: View {
    let mark: SunARMark
    var shotText: String?

    var body: some View {
        let d = mark.diameter
        ZStack {
            Color.clear
                .frame(width: d, height: d)
                .glassEffect(.clear.tint(mark.tint.opacity(SunARInk.systemGlassTint * mark.fade)), in: Circle())
            if mark.isSun {
                Circle().fill(mark.multiplyTint).opacity(SunARInk.sunMultiplyOpacity(fade: mark.fade))
                    .blendMode(.multiply)
            }
            if case .moon(let illuminated, let waxing, let limb) = mark.kind {
                MoonPhaseGlyph(illuminated: illuminated, waxing: waxing, limb: limb)
                    .frame(width: d - 2 * SunARInk.moonInset, height: d - 2 * SunARInk.moonInset)
                    .opacity(mark.fade)
            }
            if mark.dashedContour {
                // Пунктир внутри кромки: снаружи диска фон не темнеет.
                Circle().inset(by: 0.75)
                    .stroke(Color.white.opacity(SunARInk.ghostContour),
                            style: StrokeStyle(lineWidth: 1.25, lineCap: .butt, dash: SunARInk.ghostDash))
            }
        }
        .frame(width: d, height: d)
        .shotNode("ar.mark." + mark.id, text: shotText)
        .position(x: mark.center.x, y: mark.center.y)
        .allowsHitTesting(false)
    }
}
