import SwiftUI

/// Цвета веба по именам его CSS-переменных (`:root` и `:root[data-theme="light"]`
/// беты) — общий словарь экранов с итерации 19б. Значения перенесены
/// буквально; имя — переменная без `--` в camelCase (`--ink-4` → `ink4`).
/// Экран берёт палитру из среды: `Palette(scheme)`.
///
/// Не генерируется: веб правит тему редко, а сверка снимков (`Tools/shots`)
/// ловит расхождение цвета числом. Правка токена в вебе — правка здесь.
public struct Palette: Sendable {
    public let dark: Bool

    public init(_ scheme: ColorScheme) { dark = scheme != .light }

    /// `--glyph` веба: тёмная #E2A44C, светлая #8A5A18.
    public var glyph: Color { dark ? Color(hex: 0xE2A44C) : Color(hex: 0x8A5A18) }
    /// `--pin-ring` веба: тёмная #14110E, светлая #3A352E.
    public var pinRing: Color { dark ? Color(hex: 0x14110E) : Color(hex: 0x3A352E) }
    /// `--arc-mid` веба: тёмная #EFEAE0, светлая #17150F.
    public var arcMid: Color { dark ? Color(hex: 0xEFEAE0) : Color(hex: 0x17150F) }
    /// `--knob` веба: тёмная #EFEAE0, светлая #FFFFFF.
    public var knob: Color { dark ? Color(hex: 0xEFEAE0) : Color(hex: 0xFFFFFF) }
    /// `--knob-edge` веба: тёмная #0F0E0C, светлая #C3BBAA.
    public var knobEdge: Color { dark ? Color(hex: 0x0F0E0C) : Color(hex: 0xC3BBAA) }
    /// `--meter-off` веба: тёмная #3A352E, светлая #D2CBBC.
    public var meterOff: Color { dark ? Color(hex: 0x3A352E) : Color(hex: 0xD2CBBC) }
    /// `--bar` веба: тёмная rgba(15,14,12,0.72), светлая rgba(250,248,243,0.78).
    public var bar: Color { dark ? Color(hex: 0x0F0E0C, alpha: 0.72) : Color(hex: 0xFAF8F3, alpha: 0.78) }
    /// `--bar-2` веба: тёмная rgba(23,21,15,0.55), светлая rgba(255,255,255,0.62).
    public var bar2: Color { dark ? Color(hex: 0x17150F, alpha: 0.55) : Color(hex: 0xFFFFFF, alpha: 0.62) }
    /// `--fill-a` веба: тёмная rgba(15,14,12,0.75), светлая rgba(250,248,243,0.8).
    public var fillA: Color { dark ? Color(hex: 0x0F0E0C, alpha: 0.75) : Color(hex: 0xFAF8F3, alpha: 0.8) }
    /// `--fill-b` веба: тёмная rgba(15,14,12,0.6), светлая rgba(237,233,225,0.72).
    public var fillB: Color { dark ? Color(hex: 0x0F0E0C, alpha: 0.6) : Color(hex: 0xEDE9E1, alpha: 0.72) }
    /// `--overlay` веба: тёмная rgba(18,16,14,0.82), светлая rgba(250,248,243,0.86).
    public var overlay: Color { dark ? Color(hex: 0x12100E, alpha: 0.82) : Color(hex: 0xFAF8F3, alpha: 0.86) }
    /// `--overlay-2` веба: тёмная rgba(8,7,6,0.94), светлая rgba(250,248,243,0.96).
    public var overlay2: Color { dark ? Color(hex: 0x080706, alpha: 0.94) : Color(hex: 0xFAF8F3, alpha: 0.96) }
    /// `--overlay-3` веба: тёмная rgba(44,41,36,0.68), светлая rgba(214,208,195,0.74).
    public var overlay3: Color { dark ? Color(hex: 0x2C2924, alpha: 0.68) : Color(hex: 0xD6D0C3, alpha: 0.74) }
    /// `--hair` веба: тёмная rgba(255,255,255,0.05), светлая rgba(0,0,0,0.07).
    public var hair: Color { dark ? Color(hex: 0xFFFFFF, alpha: 0.05) : Color(hex: 0x000000, alpha: 0.07) }
    /// `--sheet-glass` веба: тёмная rgba(23,21,15,0.74), светлая rgba(255,255,255,0.78).
    public var sheetGlass: Color { dark ? Color(hex: 0x17150F, alpha: 0.74) : Color(hex: 0xFFFFFF, alpha: 0.78) }
    /// `--knob-glass` веба: тёмная rgba(239,234,224,0.26), светлая rgba(255,255,255,0.40).
    public var knobGlass: Color { dark ? Color(hex: 0xEFEAE0, alpha: 0.26) : Color(hex: 0xFFFFFF, alpha: 0.40) }
    /// `--drum-face` веба: тёмная rgba(255,255,255,0.05), светлая rgba(23,21,15,0.05).
    public var drumFace: Color { dark ? Color(hex: 0xFFFFFF, alpha: 0.05) : Color(hex: 0x17150F, alpha: 0.05) }
    /// `--map-glass` веба: тёмная rgba(23,21,15,0.30), светлая rgba(255,255,255,0.26).
    public var mapGlass: Color { dark ? Color(hex: 0x17150F, alpha: 0.30) : Color(hex: 0xFFFFFF, alpha: 0.26) }
    /// `--hair-2` веба: тёмная rgba(255,255,255,0.04), светлая rgba(0,0,0,0.06).
    public var hair2: Color { dark ? Color(hex: 0xFFFFFF, alpha: 0.04) : Color(hex: 0x000000, alpha: 0.06) }
    /// `--hair-3` веба: тёмная rgba(255,255,255,0.03), светлая rgba(0,0,0,0.05).
    public var hair3: Color { dark ? Color(hex: 0xFFFFFF, alpha: 0.03) : Color(hex: 0x000000, alpha: 0.05) }
    /// `--hair-4` веба: тёмная rgba(255,255,255,0.07), светлая rgba(0,0,0,0.09).
    public var hair4: Color { dark ? Color(hex: 0xFFFFFF, alpha: 0.07) : Color(hex: 0x000000, alpha: 0.09) }
    /// `--hair-5` веба: тёмная rgba(255,255,255,0.18), светлая rgba(0,0,0,0.20).
    public var hair5: Color { dark ? Color(hex: 0xFFFFFF, alpha: 0.18) : Color(hex: 0x000000, alpha: 0.20) }
    /// `--glass-fill` веба: тёмная rgba(255,255,255,0.07), светлая rgba(23,21,15,0.045).
    public var glassFill: Color { dark ? Color(hex: 0xFFFFFF, alpha: 0.07) : Color(hex: 0x17150F, alpha: 0.045) }
    /// `--glass-shine` веба: тёмная rgba(255,255,255,0.30), светлая rgba(255,255,255,0.95).
    public var glassShine: Color { dark ? Color(hex: 0xFFFFFF, alpha: 0.30) : Color(hex: 0xFFFFFF, alpha: 0.95) }
    /// `--glass-cast` веба: тёмная rgba(0,0,0,0.45), светлая rgba(23,21,15,0.16).
    public var glassCast: Color { dark ? Color(hex: 0x000000, alpha: 0.45) : Color(hex: 0x17150F, alpha: 0.16) }
    /// `--drum-lip` веба: тёмная rgba(255,255,255,0.18), светлая rgba(255,255,255,0.95).
    public var drumLip: Color { dark ? Color(hex: 0xFFFFFF, alpha: 0.18) : Color(hex: 0xFFFFFF, alpha: 0.95) }
    /// `--drum-glass` веба: тёмная rgba(255,255,255,0.13), светлая rgba(255,255,255,0.45).
    public var drumGlass: Color { dark ? Color(hex: 0xFFFFFF, alpha: 0.13) : Color(hex: 0xFFFFFF, alpha: 0.45) }
    /// `--ink-a22` веба: тёмная rgba(239,234,224,0.22), светлая rgba(23,21,15,0.22).
    public var inkA22: Color { dark ? Color(hex: 0xEFEAE0, alpha: 0.22) : Color(hex: 0x17150F, alpha: 0.22) }
    /// `--ink-a20` веба: тёмная rgba(239,234,224,0.2), светлая rgba(23,21,15,0.2).
    public var inkA20: Color { dark ? Color(hex: 0xEFEAE0, alpha: 0.2) : Color(hex: 0x17150F, alpha: 0.2) }
    /// `--ink-a24` веба: тёмная rgba(239,234,224,0.24), светлая rgba(23,21,15,0.24).
    public var inkA24: Color { dark ? Color(hex: 0xEFEAE0, alpha: 0.24) : Color(hex: 0x17150F, alpha: 0.24) }
    /// `--ink-a40` веба: тёмная rgba(239,234,224,0.4), светлая rgba(23,21,15,0.4).
    public var inkA40: Color { dark ? Color(hex: 0xEFEAE0, alpha: 0.4) : Color(hex: 0x17150F, alpha: 0.4) }
    /// `--ink-a12` веба: тёмная rgba(239,234,224,0.12), светлая rgba(23,21,15,0.12).
    public var inkA12: Color { dark ? Color(hex: 0xEFEAE0, alpha: 0.12) : Color(hex: 0x17150F, alpha: 0.12) }
    /// `--ink-a10` веба: тёмная rgba(239,234,224,0.10), светлая rgba(23,21,15,0.10).
    public var inkA10: Color { dark ? Color(hex: 0xEFEAE0, alpha: 0.10) : Color(hex: 0x17150F, alpha: 0.10) }
    /// `--ink-a08` веба: тёмная rgba(239,234,224,0.08), светлая rgba(23,21,15,0.08).
    public var inkA08: Color { dark ? Color(hex: 0xEFEAE0, alpha: 0.08) : Color(hex: 0x17150F, alpha: 0.08) }
    /// `--bg` веба: тёмная #070606, светлая #EDE9E1.
    public var bg: Color { dark ? Color(hex: 0x070606) : Color(hex: 0xEDE9E1) }
    /// `--surface` веба: тёмная #0F0E0C, светлая #FAF8F3.
    public var surface: Color { dark ? Color(hex: 0x0F0E0C) : Color(hex: 0xFAF8F3) }
    /// `--canvas` веба: тёмная #14110E, светлая #14110E (общая).
    public var canvas: Color { dark ? Color(hex: 0x14110E) : Color(hex: 0x14110E) }
    /// `--sheet` веба: тёмная #17150F, светлая #FFFFFF.
    public var sheet: Color { dark ? Color(hex: 0x17150F) : Color(hex: 0xFFFFFF) }
    /// `--sheet-2` веба: тёмная #131109, светлая #F1EDE4.
    public var sheet2: Color { dark ? Color(hex: 0x131109) : Color(hex: 0xF1EDE4) }
    /// `--sheet-3` веба: тёмная #1A1710, светлая #FFFFFF.
    public var sheet3: Color { dark ? Color(hex: 0x1A1710) : Color(hex: 0xFFFFFF) }
    /// `--peek-1` веба: тёмная #1B1811, светлая #FFFFFF.
    public var peek1: Color { dark ? Color(hex: 0x1B1811) : Color(hex: 0xFFFFFF) }
    /// `--peek-2` веба: тёмная #221E16, светлая #F6F2E8.
    public var peek2: Color { dark ? Color(hex: 0x221E16) : Color(hex: 0xF6F2E8) }
    /// `--stack-shade` веба: тёмная rgba(0,0,0,0.55), светлая rgba(23,21,15,0.16).
    public var stackShade: Color { dark ? Color(hex: 0x000000, alpha: 0.55) : Color(hex: 0x17150F, alpha: 0.16) }
    /// `--stack-edge` веба: тёмная rgba(255,255,255,0.07), светлая rgba(23,21,15,0.05).
    public var stackEdge: Color { dark ? Color(hex: 0xFFFFFF, alpha: 0.07) : Color(hex: 0x17150F, alpha: 0.05) }
    /// `--sheet-4` веба: тёмная #1A1712, светлая #FFFFFF.
    public var sheet4: Color { dark ? Color(hex: 0x1A1712) : Color(hex: 0xFFFFFF) }
    /// `--warn-bg` веба: тёмная #191510, светлая #FBF1DE.
    public var warnBg: Color { dark ? Color(hex: 0x191510) : Color(hex: 0xFBF1DE) }
    /// `--bad-bg` веба: тёмная #1D1512, светлая #FBE7DC.
    public var badBg: Color { dark ? Color(hex: 0x1D1512) : Color(hex: 0xFBE7DC) }
    /// `--badge-bg` веба: тёмная #241F17, светлая #F4F0E6.
    public var badgeBg: Color { dark ? Color(hex: 0x241F17) : Color(hex: 0xF4F0E6) }
    /// `--hatch` веба: тёмная #1C1A14, светлая #E7E2D8.
    public var hatch: Color { dark ? Color(hex: 0x1C1A14) : Color(hex: 0xE7E2D8) }
    /// `--hairline` веба: тёмная #1C1913, светлая #E2DCD1.
    public var hairline: Color { dark ? Color(hex: 0x1C1913) : Color(hex: 0xE2DCD1) }
    /// `--on-brass` веба: тёмная #16120C, светлая #FFFFFF.
    public var onBrass: Color { dark ? Color(hex: 0x16120C) : Color(hex: 0xFFFFFF) }
    /// `--field` веба: тёмная #1C1A16, светлая #EAE5DB.
    public var field: Color { dark ? Color(hex: 0x1C1A16) : Color(hex: 0xEAE5DB) }
    /// `--field-press` веба: тёмная #262218, светлая #DCD6C9.
    public var fieldPress: Color { dark ? Color(hex: 0x262218) : Color(hex: 0xDCD6C9) }
    /// `--press` веба: тёмная #221F19, светлая #EDE9E1.
    public var press: Color { dark ? Color(hex: 0x221F19) : Color(hex: 0xEDE9E1) }
    /// `--press-2` веба: тёмная #201C15, светлая #EBE6DC.
    public var press2: Color { dark ? Color(hex: 0x201C15) : Color(hex: 0xEBE6DC) }
    /// `--press-warm` веба: тёмная #221D14, светлая #F6ECD8.
    public var pressWarm: Color { dark ? Color(hex: 0x221D14) : Color(hex: 0xF6ECD8) }
    /// `--press-brass` веба: тёмная #33291A, светлая #F7E9CF.
    public var pressBrass: Color { dark ? Color(hex: 0x33291A) : Color(hex: 0xF7E9CF) }
    /// `--rail` веба: тёмная #2B2822, светлая #DCD6C9.
    public var rail: Color { dark ? Color(hex: 0x2B2822) : Color(hex: 0xDCD6C9) }
    /// `--rail-2` веба: тёмная #2E2A24, светлая #D2CBBC.
    public var rail2: Color { dark ? Color(hex: 0x2E2A24) : Color(hex: 0xD2CBBC) }
    /// `--rail-3` веба: тёмная #2C2820, светлая #D5CEC0.
    public var rail3: Color { dark ? Color(hex: 0x2C2820) : Color(hex: 0xD5CEC0) }
    /// `--rail-4` веба: тёмная #2A261E, светлая #D8D1C3.
    public var rail4: Color { dark ? Color(hex: 0x2A261E) : Color(hex: 0xD8D1C3) }
    /// `--rail-5` веба: тёмная #3A352E, светлая #C3BBAA.
    public var rail5: Color { dark ? Color(hex: 0x3A352E) : Color(hex: 0xC3BBAA) }
    /// `--seg-on` веба: тёмная #2A2724, светлая #DDD6C8.
    public var segOn: Color { dark ? Color(hex: 0x2A2724) : Color(hex: 0xDDD6C8) }
    /// `--bezel` веба: тёмная #1C1A17, светлая #D8D2C6.
    public var bezel: Color { dark ? Color(hex: 0x1C1A17) : Color(hex: 0xD8D2C6) }
    /// `--edge` веба: тёмная #38332B, светлая #CFC8B9.
    public var edge: Color { dark ? Color(hex: 0x38332B) : Color(hex: 0xCFC8B9) }
    /// `--ink` веба: тёмная #EFEAE0, светлая #17150F.
    public var ink: Color { dark ? Color(hex: 0xEFEAE0) : Color(hex: 0x17150F) }
    /// `--ink-2` веба: тёмная #C9C2B6, светлая #3A352E.
    public var ink2: Color { dark ? Color(hex: 0xC9C2B6) : Color(hex: 0x3A352E) }
    /// `--ink-2b` веба: тёмная #C0B8AA, светлая #423C33.
    public var ink2b: Color { dark ? Color(hex: 0xC0B8AA) : Color(hex: 0x423C33) }
    /// `--ink-3` веба: тёмная #A8A093, светлая #55504A.
    public var ink3: Color { dark ? Color(hex: 0xA8A093) : Color(hex: 0x55504A) }
    /// `--ink-3b` веба: тёмная #A89C86, светлая #5A5348.
    public var ink3b: Color { dark ? Color(hex: 0xA89C86) : Color(hex: 0x5A5348) }
    /// `--ink-4` веба: тёмная #8A8478, светлая #6B6559.
    public var ink4: Color { dark ? Color(hex: 0x8A8478) : Color(hex: 0x6B6559) }
    /// `--ink-5` веба: тёмная #6B6559, светлая #857E70.
    public var ink5: Color { dark ? Color(hex: 0x6B6559) : Color(hex: 0x857E70) }
    /// `--ink-5b` веба: тёмная #6E6558, светлая #857E70.
    public var ink5b: Color { dark ? Color(hex: 0x6E6558) : Color(hex: 0x857E70) }
    /// `--ink-6` веба: тёмная #635E54, светлая #8C8578.
    public var ink6: Color { dark ? Color(hex: 0x635E54) : Color(hex: 0x8C8578) }
    /// `--ink-7` веба: тёмная #55504A, светлая #9A9385.
    public var ink7: Color { dark ? Color(hex: 0x55504A) : Color(hex: 0x9A9385) }
    /// `--ink-8` веба: тёмная #4A453E, светлая #ADA697.
    public var ink8: Color { dark ? Color(hex: 0x4A453E) : Color(hex: 0xADA697) }
    /// `--ink-9` веба: тёмная #45403A, светлая #B5AE9F.
    public var ink9: Color { dark ? Color(hex: 0x45403A) : Color(hex: 0xB5AE9F) }
    /// `--ink-10` веба: тёмная #3A352F, светлая #BFB8A9.
    public var ink10: Color { dark ? Color(hex: 0x3A352F) : Color(hex: 0xBFB8A9) }
    /// `--brass` веба: тёмная #E2A44C, светлая #A9721F.
    public var brass: Color { dark ? Color(hex: 0xE2A44C) : Color(hex: 0xA9721F) }
    /// `--brass-soft` веба: тёмная #D9AC6B, светлая #9B6A22.
    public var brassSoft: Color { dark ? Color(hex: 0xD9AC6B) : Color(hex: 0x9B6A22) }
    /// `--brass-deep` веба: тёмная #C9853F, светлая #8A5A18.
    public var brassDeep: Color { dark ? Color(hex: 0xC9853F) : Color(hex: 0x8A5A18) }
    /// `--brass-dark` веба: тёмная #8A4B22, светлая #6E3C15.
    public var brassDark: Color { dark ? Color(hex: 0x8A4B22) : Color(hex: 0x6E3C15) }
    /// `--green` веба: тёмная #A8B49B, светлая #5F6B4E.
    public var green: Color { dark ? Color(hex: 0xA8B49B) : Color(hex: 0x5F6B4E) }
    /// `--blue` веба: тёмная #7C9CC4, светлая #3F6088.
    public var blue: Color { dark ? Color(hex: 0x7C9CC4) : Color(hex: 0x3F6088) }
    /// `--tone-good` веба: тёмная #B5AC9C, светлая #6B6559.
    public var toneGood: Color { dark ? Color(hex: 0xB5AC9C) : Color(hex: 0x6B6559) }
    /// `--terra` веба: тёмная #C9663D, светлая #A84E27.
    public var terra: Color { dark ? Color(hex: 0xC9663D) : Color(hex: 0xA84E27) }
    /// `--terra-2` веба: тёмная #B9603D, светлая #9E4722.
    public var terra2: Color { dark ? Color(hex: 0xB9603D) : Color(hex: 0x9E4722) }
    /// `--bad-ink` веба: тёмная #D9A08A, светлая #8A3F22.
    public var badInk: Color { dark ? Color(hex: 0xD9A08A) : Color(hex: 0x8A3F22) }
    /// `--warn-ink` веба: тёмная #D9C2A0, светлая #7A5A22.
    public var warnInk: Color { dark ? Color(hex: 0xD9C2A0) : Color(hex: 0x7A5A22) }
    /// `--moon` веба: тёмная #A8BDD8, светлая #A8BDD8 (общая).
    public var moon: Color { dark ? Color(hex: 0xA8BDD8) : Color(hex: 0xA8BDD8) }
    /// `--moon-lit` веба: тёмная #CFD6DE, светлая #CFD6DE (общая).
    public var moonLit: Color { dark ? Color(hex: 0xCFD6DE) : Color(hex: 0xCFD6DE) }
    /// `--moon-dark` веба: тёмная #16161A, светлая #16161A (общая).
    public var moonDark: Color { dark ? Color(hex: 0x16161A) : Color(hex: 0x16161A) }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}
