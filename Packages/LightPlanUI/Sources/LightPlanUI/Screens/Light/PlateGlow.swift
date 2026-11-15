import SwiftUI
import LightPlanCore

/// 30з.3 (макет 4 Алексея 12.11, пункт 6 записки): «свет из-под верхнего края первой плашки: его источник — солнце, ушедшее под
/// горизонт; цвет и сила по состоянию неба, не постоянный янтарь».
///
/// Форма снята с `mock_4_glow.jpg` против `mock_2_plates.jpg` (разность по пикселям, ширина 924 px = 393 pt, 2,35 px/pt):
/// свет начинается ровно на верхней кромке плашки (над ней — 0, y 650: 0; y 658: −5) и затухает вниз внутри плашки: у центра
/// 100 % на кромке → 60 % на 7 pt → 47 % на 24 pt → 13 % на 58 pt → 0 на ≈ 80 pt (`vertical`); по ширине — почти ровная
/// середина (≥ 88 % в пределах ±0,2 ширины от центра) и спад к краям (`horizontal`). Пик макета — (99, 80, 48) на плашке
/// (23, 22, 20): это цвет `SkyPalette.horizonStop` (247, 196, 118) при непрозрачности 0,33 — **столько и берётся за «полный»
/// свет** (`peakMock`). Рисунок макета лежит над заливкой плашки и под её содержимым, в её скруглении.
///
/// Свет лежит поверх тона плашки, а не под стеклом: тон `sheetGlass` в тёмной теме держит 0,74, и свет, посаженный под стекло, потерял
/// бы три четверти силы. Это свет, не тень: в обеих темах он светлее плашки (в светлой теме — тёплый оттенок поверх #F3F3F5).
/// Нарисованного блика нет (`Tools/check_glass.sh`): кант плашки — системное стекло и белый обод, свет их не заменяет.
struct PlateGlowSpec: Equatable {
    /// Цвет света — зарево неба в этот момент (`DomeSky.glowColor`: цвет ступени высоты, смешанный с горизонтом прогноза).
    let color: SkyColor
    /// Непрозрачность в самой яркой точке (кромка плашки, под центром света), 0…`peakCap`.
    let peak: Double
    /// Где свет по ширине плашки, 0…1: под солнцем, как зарево купола.
    let centre: Double

    var isVisible: Bool { peak > 0.002 }

    /// Максимум на «полном» небе: солнце только что село, небо живое. Выше макетного 0,33 — но не сплошной цвет.
    static let peakCap: Double = 0.55
    /// Макетная непрозрачность и плотность зарева купола, при которой она достигается (чистое небо, глубокие сумерки, 0,13 × 1,2).
    static let peakMock: Double = 0.33
    static let mockGlow: Double = 0.156
    /// Насыщение: 0,55 × (1 − e^(−k · плотность)) = 0,33 при плотности 0,156. Слабое небо (серый закат) гаснет заметно, яркий закат
    /// упирается в 0,5, а не в сплошную заливку.
    static var k: Double { -log(1 - peakMock / peakCap) / mockGlow }

    /// Доля света по высоте солнца: ноль на горизонте и выше, полная с −2°. «Только пока солнце под горизонтом».
    static func below(elevation e: Double) -> Double { min(1, max(0, -e / 2)) }

    /// Светлая тема: плашка почти белая (#F3F3F5, яркость 0,89), а зарево неба в сумерках темнее неё — серо-синее пятно на ней читалось бы
    /// тенью. «Свет — не тень»: цвет света поднимается к белому, пока его яркость не дойдёт до `lightFloor` яркости плашки, — остаётся
    /// оттенок (персиковый на закате), не потемнение; непрозрачность в светлой теме во столько же раз больше (`lightGain`), потолок `lightCap`.
    static let plateLuminanceLight: Double = 0.89
    static let lightFloor: Double = 0.7
    static let lightGain: Double = 1.4
    static let lightCap: Double = 0.7

    static func lifted(_ c: SkyColor, toLuminance target: Double) -> SkyColor {
        if DomeSky.luminance(c) >= target { return c }
        var lo = 0.0, hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if DomeSky.luminance(LightPalette.lerp(c, SkyColor(255, 255, 255), mid)) < target { lo = mid } else { hi = mid }
        }
        return LightPalette.lerp(c, SkyColor(255, 255, 255), hi)
    }

    /// `nil` — света нет: небо без модели (`sky == nil`), солнце над горизонтом, астрономическая ночь (`DomeSky.glowOpacity` гаснет к −18°).
    static func make(sky: DomeSky?, elevation e: Double, centre: Double, lightTheme: Bool = false) -> PlateGlowSpec? {
        guard let sky, e.isFinite else { return nil }
        let gate = below(elevation: e)
        guard gate > 0 else { return nil }
        let density = max(0, sky.glowOpacity)
        var peak = peakCap * (1 - exp(-k * density)) * gate
        var color = sky.glowColor
        if lightTheme {
            color = lifted(color, toLuminance: plateLuminanceLight * lightFloor)
            peak = min(lightCap * gate, peak * lightGain)
        }
        let spec = PlateGlowSpec(color: color, peak: peak, centre: min(1, max(0, centre)))
        return spec.isVisible ? spec : nil
    }

    // MARK: Профили макета

    /// Доля пика на `d` pt ниже кромки (из столбцов x = 200 и x = 462 макета, обе кривые усреднены).
    static let vertical: [(d: Double, a: Double)] = [
        (0, 1), (3.5, 0.74), (7, 0.6), (14, 0.53), (24, 0.47), (37, 0.35), (44, 0.27), (58, 0.13), (71, 0.06), (80, 0),
    ]
    /// Доля пика на `dx` ширины от центра света (строка y = 668 макета).
    static let horizontal: [(d: Double, a: Double)] = [
        (0, 1), (0.1, 0.97), (0.2, 0.88), (0.27, 0.75), (0.31, 0.6), (0.35, 0.45), (0.4, 0.15), (0.46, 0.05), (0.7, 0),
    ]
    static let reach: CGFloat = 80

    static func sample(_ table: [(d: Double, a: Double)], _ x: Double) -> Double {
        let x = abs(x)
        guard let last = table.last else { return 0 }
        if x >= last.d { return last.a }
        for i in 1..<table.count where x <= table[i].d {
            let a = table[i - 1], b = table[i]
            return a.a + (b.a - a.a) * (x - a.d) / (b.d - a.d)
        }
        return last.a
    }
}

struct PlateGlow: View {
    let spec: PlateGlowSpec

    var body: some View {
        let colour = Color(spec.color)
        let vertical = PlateGlowSpec.vertical.map {
            Gradient.Stop(color: colour.opacity(spec.peak * $0.a), location: $0.d / Double(PlateGlowSpec.reach))
        }
        let steps = 40
        let horizontal = (0...steps).map { i -> Gradient.Stop in
            let x = Double(i) / Double(steps)
            return Gradient.Stop(color: .black.opacity(PlateGlowSpec.sample(PlateGlowSpec.horizontal, x - spec.centre)), location: x)
        }
        Rectangle()
            .fill(LinearGradient(stops: vertical, startPoint: .top, endPoint: .bottom))
            .mask(LinearGradient(stops: horizontal, startPoint: .leading, endPoint: .trailing))
            .frame(height: PlateGlowSpec.reach)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
    }
}
