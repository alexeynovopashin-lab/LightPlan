import SwiftUI

/// 28к.2 — варианты светлой темы для досок Алексея (DECISIONS 12.11 «три варианта картинками»). Только Debug:
/// аргумент запуска `-LPLightVariant A|B|C|D`. Без аргумента и в Release `current == nil`, и экран ровно как был:
/// `Palette` отдаёт свои значения, точечные приёмы (`lvPlate`, `lvRaised`, чёрные «+ Съёмка» и выбранный день)
/// ничего не добавляют. Тёмная тема не меняется ни в одном варианте.
///
/// - A «Бумага поправленная»: тёплый серый фон на ступень темнее, белые плашки с мягкой тенью, латунь текстом — медь.
/// - B «Как на образцах»: нейтральный светло-серый фон, белые плашки со светлым кантом и мягкой широкой тенью, стекло
///   на плашках «Съёмок» и карточки, один яркий оранжевый для действий и выбранного, чёрные «+ Съёмка» и выбранный день.
/// - C: как B, акцент красный. D: как B, акцент кислотно-зелёный (заливки; текст акцента — тёмно-зелёный).
/// Во всех: выбранное выпуклое (белое с тенью), пояснения темнее до 4,5:1, подписи разделов тихие, блики белые
/// (`stackEdge`, `glassFill` — свет, а не тень). Значения — `docs/light_theme_2026-11/variants/README.md`.
public enum LightVariant: String, Sendable, CaseIterable {
    case a = "A", b = "B", c = "C", d = "D"

    /// Вариант этого запуска. В Release всегда `nil`.
    public static let current: LightVariant? = {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "LPLightVariant").flatMap(LightVariant.init(rawValue:))
        #else
        return nil
        #endif
    }()

    /// Вариант, если экран в светлой теме.
    @inline(__always)
    public static func lit(_ pal: Palette) -> LightVariant? {
        #if DEBUG
        return pal.dark ? nil : current
        #else
        return nil
        #endif
    }

    public struct Tone: Sendable, Equatable {
        public let hex: UInt32
        public let alpha: Double
        init(_ hex: UInt32, _ alpha: Double = 1) { self.hex = hex; self.alpha = alpha }
        var color: Color { Color(hex: hex, alpha: alpha) }
    }

    /// Светлое значение токена `Palette` (имя свойства) в этом варианте; `nil` — токен как был.
    public func tone(_ token: String) -> Tone? { table[token] }

    /// Все подменённые светлые токены варианта.
    public var table: [String: Tone] {
        var t = Self.common
        switch self {
        case .a: t.merge(Self.paper) { $1 }
        case .b, .c, .d: t.merge(Self.neutral) { $1 }
        }
        switch self {
        case .a: break
        case .b: t.merge(Self.accent(0xE4570B, press: 0xFFE7D9, dark: 0xB8440A)) { $1 }
        case .c: t.merge(Self.accent(0xE0282E, press: 0xFDE3E3, dark: 0xA81C22)) { $1 }
        case .d: t.merge(Self.accent(0x3A6B0C, press: 0xD6F66A, dark: 0x2C520A)) { $1 }
        }
        return t
    }

    /// Белая плашка с мягкой тенью (все варианты).
    public var shadow: Bool { true }
    /// Светлый кант 1,5 pt по краю плашки (B, C, D).
    public var rim: Bool { self != .a }
    /// Стекло на плашках «Съёмок» и карточки (B, C, D).
    public var glass: Bool { self != .a }
    /// Сплошные чёрные «+ Съёмка» и выбранный день (B, C, D).
    public var black: Bool { self != .a }
    /// Чернила чёрных элементов.
    public static let blackFill = Color(hex: 0x141416)
    /// Акцент как заливка или знак на чёрном: у D — кислотно-зелёный, у остальных — сам акцент.
    public var accentFill: Color {
        switch self {
        case .a: Color(hex: 0x8F5D17)
        case .b: Color(hex: 0xE4570B)
        case .c: Color(hex: 0xE0282E)
        case .d: Color(hex: 0xC6F135)
        }
    }

    // MARK: - Таблицы

    /// Во всех вариантах: блики белые (принцип 26.08), выбранное — белое (выпуклое, тень даёт `lvRaised`).
    private static let common: [String: Tone] = [
        "stackEdge": Tone(0xFFFFFF, 0.85),
        "glassFill": Tone(0xFFFFFF, 0.30),
        "segOn": Tone(0xFFFFFF),
    ]

    /// A: тёплая серая бумага на ступень темнее (`#FAF8F3` → `#F0ECE5`), лист карточки светлее фона,
    /// латунь текстом — медь (5,6:1 на белом, 4,8:1 на фоне), пояснения 4,7:1, подписи разделов 3,0:1.
    private static let paper: [String: Tone] = [
        "surface": Tone(0xF0ECE5), "bg": Tone(0xE6E1D8),
        "bar": Tone(0xF0ECE5, 0.80), "fillA": Tone(0xF0ECE5, 0.80), "fillB": Tone(0xE6E1D8, 0.72),
        "overlay": Tone(0xF0ECE5, 0.86), "overlay2": Tone(0xF0ECE5, 0.96),
        "sheet2": Tone(0xF7F5F0), "peek2": Tone(0xF4F1EB),
        // Пилюли и плитки знаков на `press`: прежний `#EDE9E1` на новом фоне растворялся («Заполнить» карточки) — ступень ниже.
        "press": Tone(0xE6E1D8),
        "brass": Tone(0x8F5D17), "brassSoft": Tone(0x94601A),
        "ink5": Tone(0x6F685C), "ink5b": Tone(0x6F685C), "ink6": Tone(0x6F685C), "ink7": Tone(0x8E877A),
    ]

    /// B, C, D: нейтральный светло-серый фон `#EDEDF0`, серые без тёплого оттенка; плашки «Съёмок» и карточки
    /// (`sheet3`, `sheet4`) полупрозрачные — под ними стекло.
    private static let neutral: [String: Tone] = [
        "surface": Tone(0xEDEDF0), "bg": Tone(0xE3E3E7),
        "bar": Tone(0xEDEDF0, 0.80), "fillA": Tone(0xEDEDF0, 0.80), "fillB": Tone(0xE3E3E7, 0.72),
        "overlay": Tone(0xEDEDF0, 0.86), "overlay2": Tone(0xEDEDF0, 0.96), "overlay3": Tone(0xD3D3D8, 0.74),
        "sheet": Tone(0xFFFFFF), "sheet2": Tone(0xF6F6F8), "sheet3": Tone(0xFFFFFF, 0.72), "sheet4": Tone(0xFFFFFF, 0.72),
        "peek1": Tone(0xFFFFFF), "peek2": Tone(0xF2F2F5), "badgeBg": Tone(0xF2F2F5), "hatch": Tone(0xE5E5E9),
        "field": Tone(0xE9E9ED), "fieldPress": Tone(0xDADADF), "press": Tone(0xE2E2E6), "press2": Tone(0xE8E8EC),
        "hairline": Tone(0xE0E0E4), "rail": Tone(0xD9D9DE), "rail2": Tone(0xCFCFD4), "rail3": Tone(0xD3D3D8),
        "rail4": Tone(0xD6D6DB), "rail5": Tone(0xC2C2C7), "edge": Tone(0xCBCBD0), "bezel": Tone(0xD6D6DB),
        "meterOff": Tone(0xCFCFD4), "knobEdge": Tone(0xC2C2C7),
        "ink": Tone(0x141416), "arcMid": Tone(0x141416), "ink2": Tone(0x3A3A3E), "ink2b": Tone(0x424246),
        "ink3": Tone(0x545458), "ink3b": Tone(0x5A5A5E), "ink4": Tone(0x626267),
        "ink5": Tone(0x69696E), "ink5b": Tone(0x69696E), "ink6": Tone(0x69696E), "ink7": Tone(0x86868B),
        "ink8": Tone(0xA1A1A6), "ink9": Tone(0xACACB1), "ink10": Tone(0xBABABF),
    ]

    /// Акцент действий и выбранного. Латунь остаётся выходным (`brassDeep` = `weekend`) и золотому часу (небо).
    private static func accent(_ hex: UInt32, press: UInt32, dark: UInt32) -> [String: Tone] {
        ["brass": Tone(hex), "brassSoft": Tone(hex), "glyph": Tone(hex), "pressBrass": Tone(press), "brassDark": Tone(dark)]
    }
}

public extension View {
    /// Плашка варианта 28к.2: мягкая тень снаружи (все варианты), светлый кант (B, C, D), стекло под полупрозрачной
    /// заливкой (B, C, D, только где `glass`). Без варианта, в тёмной теме и в Release — ничего.
    @ViewBuilder
    func lvPlate(_ pal: Palette, radius: CGFloat, glass: Bool = false) -> some View {
        #if DEBUG
        if let v = LightVariant.lit(pal) {
            modifier(LightVariantPlate(v: v, radius: radius, glass: glass && v.glass, lift: 1))
        } else { self }
        #else
        self
        #endif
    }

    /// Выбранное и поднятое варианта 28к.2: короткая тень под белым (выпуклое). Без варианта — ничего.
    @ViewBuilder
    func lvRaised(_ pal: Palette, radius: CGFloat, on: Bool = true) -> some View {
        #if DEBUG
        if on, LightVariant.lit(pal) != nil {
            modifier(LightVariantPlate(v: .a, radius: radius, glass: false, lift: 0.5))
        } else { self }
        #else
        self
        #endif
    }
}

#if DEBUG
/// Тень только снаружи контура (как у подложки месяца): полупрозрачная заливка над ней не темнеет.
private struct LightVariantPlate: ViewModifier {
    let v: LightVariant
    let radius: CGFloat
    let glass: Bool
    /// 1 — плашка (широкая мягкая тень), 0,5 — выбранное (короче и плотнее).
    let lift: CGFloat

    func body(content: Content) -> some View {
        let r = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if glass { Color.clear.glassEffect(.regular, in: r) }
            }
            .overlay {
                if v.rim && lift == 1 { r.strokeBorder(Color.white.opacity(0.95), lineWidth: 1.5).allowsHitTesting(false) }
            }
            .background {
                ZStack {
                    r.fill(Color.black).shadow(color: .black.opacity(lift == 1 ? (v.rim ? 0.10 : 0.09) : 0.16),
                                                radius: lift == 1 ? (v.rim ? 16 : 12) : 5, y: lift == 1 ? (v.rim ? 8 : 5) : 2)
                    r.fill(Color.black).shadow(color: .black.opacity(lift == 1 ? 0.05 : 0.10), radius: 1, y: 1)
                }
                .mask {
                    ZStack {
                        Rectangle().padding(-60)
                        r.blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
                .allowsHitTesting(false)
            }
    }
}
#endif
