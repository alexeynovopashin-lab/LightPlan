import SwiftUI

/// Прозрачное стекло окна барабана и кольца ручки — шейдеры `Glass.metal`
/// (DECISIONS «Прозрачное стекло: окно барабана и кольцо ручки», 23 сентября
/// 2026). Системное `.glassEffect` размывает то, что под ним, всегда — дата
/// под окном становилась нечитаемой (снимок 19б). Это стекло не размывает:
/// в середине картинка один к одному, у кромки гнётся.
enum GlassOptics {
    private static let library = ShaderLibrary.bundle(.module)

    /// `--glass-optic` веба: тёмная `saturate(1.5) brightness(1.06)`,
    /// светлая `saturate(1.4) brightness(0.98)`.
    static func optic(_ scheme: ColorScheme) -> (saturation: Double, brightness: Double) {
        scheme == .light ? (1.4, 0.98) : (1.5, 1.06)
    }

    /// Окно барабана. Боковая кромка 10 pt со сдвигом до 3: числа, заезжающие
    /// под край, гнутся, а выбранная дата (32 pt в ячейке 50, поля по 9)
    /// в покое почти вся в ровной середине. Первая проба — кромка 7 и сдвиг
    /// 5 — двоила у края целую букву («СЕНН»): сдвиг шире буквы. Верх и
    /// низ — 3 pt и 1,5: окно почти во всю высоту ячейки, и дата со знаком
    /// не должны гнуться.
    static let sideBand = 10.0, sideShift = 3.0, capBand = 3.0, capShift = 1.5

    static func slab(center: CGPoint, size: CGSize, radius: Double, scheme: ColorScheme) -> Shader {
        let o = optic(scheme)
        return library.glassSlab(.float2(center), .float2(size.width / 2, size.height / 2), .float(radius),
                                 .float(sideBand), .float(sideShift), .float(capBand), .float(capShift),
                                 .float(o.saturation), .float(o.brightness))
    }

    /// Кольцо ручки: 3 pt у края (бывший глухой кант `--knob-edge`),
    /// сдвиг до 3 — риски и дорожка под кольцом гнутся, когда ручка едет.
    static let ringShift = 3.0

    static func ring(center: CGPoint, radii: CGSize, width: Double, scheme: ColorScheme) -> Shader {
        let o = optic(scheme)
        return library.glassRing(.float2(center), .float2(radii.width, radii.height), .float(width),
                                 .float(ringShift), .float(o.saturation), .float(o.brightness))
    }
}

/// Тень фигуры только СНАРУЖИ, как CSS `box-shadow`: внешняя тень веба
/// обрезана по краю элемента и под полупрозрачное стекло не заходит. Холст
/// шире фигуры на запас под размытие; сама фигура вычитается после тени.
struct OuterShadow<S: Shape>: View {
    var shape: S
    var color: Color
    var radius: CGFloat
    var y: CGFloat

    var body: some View {
        let pad = radius * 3 + abs(y)
        Canvas { ctx, size in
            let body = shape.path(in: CGRect(origin: .zero, size: size).insetBy(dx: pad, dy: pad))
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: color, radius: radius, x: 0, y: y, options: .shadowOnly))
                layer.fill(body, with: .color(.black))
            }
            ctx.blendMode = .destinationOut
            ctx.fill(body, with: .color(.black))
        }
        .padding(-pad)
        .allowsHitTesting(false)
    }
}

/// Матовое стекло ручки ползунка на малом предмете «Карты» — головка
/// булавки (20г) и центр компаса (20д; Алексей 24.09: «Центр компаса -
/// матовое стекло, как на ползунке, по сути мы дублируем этот элемент»):
/// `knobGlass` на `.glassEffect(.clear)`, кромка света сверху, волосок
/// чернил снаружи и тень только снаружи. Блик — часть рецепта ручки
/// (решения 19б), поэтому рецепт живёт здесь: `Tools/check_glass.sh` вне
/// `Timebar/` нарисованный блик не пускает.
struct KnobGlass<S: Shape>: View {
    let shape: S
    let pal: Palette

    var body: some View {
        shape.fill(pal.knobGlass)
            .glassEffect(.clear, in: shape)
            .overlay(shape.stroke(LinearGradient(
                stops: [.init(color: pal.glassShine, location: 0),
                        .init(color: pal.glassShine.opacity(0), location: 0.4)],
                startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(shape.stroke(pal.inkA22, lineWidth: 1).opacity(0.8))
            .background(OuterShadow(shape: shape, color: .black.opacity(0.4), radius: 3, y: 2))
    }
}
