import SwiftUI

/// Цвета веба по именам его CSS-переменных (`:root` и `:root[data-theme="light"]`
/// беты) — общий словарь экранов с итерации 19б. Значения перенесены
/// буквально; имя — переменная без `--` в camelCase (`--ink-4` → `ink4`).
/// Экран берёт палитру из среды: `Palette(scheme)`.
///
/// Светлая тема натива с 28к.4 — палитра «Д» (Алексей 13.11, DECISIONS «палитра Д, по образцу, как есть»): цвета сняты с образца
/// дизайнера по пикселям и перенесены буквально, без подгонки под контраст. Фон страницы #E6E6E7, блок #F3F3F5 (белый кант и
/// тень держат его на фоне, 1,1 : 1 — так задумано), оранжевый #F29230 в заливках и знаках и #F09329 в тексте и линиях, чёрная
/// кнопка #010101 с белым знаком, чернила #000000, вторые чернила #5C5C62. Токены между ними (поля, нажатия, рельсы, кант листа)
/// пересчитаны от прежней «Б» тем же отступом от страницы (таблица «было → стало» — `docs/light_palette_d_2026-11/README.md`).
/// В 28к.3 была «Б» (#EDEDF0, #E4570B, `brassInk` #B83C00); комментарий «Светлая натива с 28к.3» хранит её значение.
/// Тёмная ветка — как в вебе, не тронута.
///
/// Не генерируется: веб правит тему редко, а сверка снимков (`Tools/shots`)
/// ловит расхождение цвета числом. Правка токена в вебе — правка здесь.
public struct Palette: Sendable {
    public let dark: Bool

    public init(_ scheme: ColorScheme) { dark = scheme != .light }

    /// `--glyph` веба: тёмная #E2A44C, светлая #8A5A18. Светлая натива с 28к.3 — #E4570B. Светлая с 28к.4 (палитра Д) — #F29230.
    public var glyph: Color { dark ? Color(hex: 0xE2A44C) : Color(hex: 0xF29230) }
    /// `--pin-ring` веба: тёмная #14110E, светлая #3A352E.
    public var pinRing: Color { dark ? Color(hex: 0x14110E) : Color(hex: 0x3A352E) }
    /// `--arc-mid` веба: тёмная #EFEAE0, светлая #17150F. Светлая натива с 28к.3 — #141416. Светлая с 28к.4 (палитра Д) — #000000.
    public var arcMid: Color { dark ? Color(hex: 0xEFEAE0) : Color(hex: 0x000000) }
    /// `--knob` веба: тёмная #EFEAE0, светлая #FFFFFF.
    public var knob: Color { dark ? Color(hex: 0xEFEAE0) : Color(hex: 0xFFFFFF) }
    /// `--knob-edge` веба: тёмная #0F0E0C, светлая #C3BBAA. Светлая натива с 28к.3 — #C2C2C7. Светлая с 28к.4 (палитра Д) — #BBBBBE.
    public var knobEdge: Color { dark ? Color(hex: 0x0F0E0C) : Color(hex: 0xBBBBBE) }
    /// `--meter-off` веба: тёмная #3A352E, светлая #D2CBBC. Светлая натива с 28к.3 — #CFCFD4. Светлая с 28к.4 (палитра Д) — #C8C8CB.
    public var meterOff: Color { dark ? Color(hex: 0x3A352E) : Color(hex: 0xC8C8CB) }
    /// `--bar` веба: тёмная rgba(15,14,12,0.72), светлая rgba(250,248,243,0.78). Светлая натива с 28к.3 — #EDEDF0 (0.8). Светлая с 28к.4 (палитра Д) — #E6E6E7.
    public var bar: Color { dark ? Color(hex: 0x0F0E0C, alpha: 0.72) : Color(hex: 0xE6E6E7, alpha: 0.8) }
    /// `--bar-2` веба: тёмная rgba(23,21,15,0.55), светлая rgba(255,255,255,0.62).
    public var bar2: Color { dark ? Color(hex: 0x17150F, alpha: 0.55) : Color(hex: 0xFFFFFF, alpha: 0.62) }
    /// `--fill-a` веба: тёмная rgba(15,14,12,0.75), светлая rgba(250,248,243,0.8). Светлая натива с 28к.3 — #EDEDF0 (0.8). Светлая с 28к.4 (палитра Д) — #E6E6E7.
    public var fillA: Color { dark ? Color(hex: 0x0F0E0C, alpha: 0.75) : Color(hex: 0xE6E6E7, alpha: 0.8) }
    /// `--fill-b` веба: тёмная rgba(15,14,12,0.6), светлая rgba(237,233,225,0.72). Светлая натива с 28к.3 — #E3E3E7 (0.72). Светлая с 28к.4 (палитра Д) — #DCDCDE.
    public var fillB: Color { dark ? Color(hex: 0x0F0E0C, alpha: 0.6) : Color(hex: 0xDCDCDE, alpha: 0.72) }
    /// `--overlay` веба: тёмная rgba(18,16,14,0.82), светлая rgba(250,248,243,0.86). Светлая натива с 28к.3 — #EDEDF0 (0.86). Светлая с 28к.4 (палитра Д) — #E6E6E7.
    public var overlay: Color { dark ? Color(hex: 0x12100E, alpha: 0.82) : Color(hex: 0xE6E6E7, alpha: 0.86) }
    /// `--overlay-2` веба: тёмная rgba(8,7,6,0.94), светлая rgba(250,248,243,0.96). Светлая натива с 28к.3 — #EDEDF0 (0.96). Светлая с 28к.4 (палитра Д) — #E6E6E7.
    public var overlay2: Color { dark ? Color(hex: 0x080706, alpha: 0.94) : Color(hex: 0xE6E6E7, alpha: 0.96) }
    /// `--overlay-3` веба: тёмная rgba(44,41,36,0.68), светлая rgba(214,208,195,0.74). Светлая натива с 28к.3 — #D3D3D8 (0.74). Светлая с 28к.4 (палитра Д) — #CCCCCF.
    public var overlay3: Color { dark ? Color(hex: 0x2C2924, alpha: 0.68) : Color(hex: 0xCCCCCF, alpha: 0.74) }
    /// `--hair` веба: тёмная rgba(255,255,255,0.05), светлая rgba(0,0,0,0.07).
    public var hair: Color { dark ? Color(hex: 0xFFFFFF, alpha: 0.05) : Color(hex: 0x000000, alpha: 0.07) }
    /// `--sheet-glass` веба: тёмная rgba(23,21,15,0.74), светлая rgba(255,255,255,0.78). Светлая с 28к.4 (палитра Д) — #F3F3F5.
    public var sheetGlass: Color { dark ? Color(hex: 0x17150F, alpha: 0.74) : Color(hex: 0xF3F3F5, alpha: 0.78) }
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
    /// `--glass-fill` веба: тёмная rgba(255,255,255,0.07), светлая rgba(23,21,15,0.045). Светлая натива с 28к.3 — #FFFFFF (0.3).
    public var glassFill: Color { dark ? Color(hex: 0xFFFFFF, alpha: 0.07) : Color(hex: 0xFFFFFF, alpha: 0.3) }
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
    /// `--bg` веба: тёмная #070606, светлая #EDE9E1. Светлая натива с 28к.3 — #E3E3E7. Светлая с 28к.4 (палитра Д) — #DCDCDE.
    public var bg: Color { dark ? Color(hex: 0x070606) : Color(hex: 0xDCDCDE) }
    /// `--surface` веба: тёмная #0F0E0C, светлая #FAF8F3. Светлая натива с 28к.3 — #EDEDF0. Светлая с 28к.4 (палитра Д) — #E6E6E7.
    public var surface: Color { dark ? Color(hex: 0x0F0E0C) : Color(hex: 0xE6E6E7) }
    /// `--canvas` веба: тёмная #14110E, светлая #14110E (общая).
    public var canvas: Color { dark ? Color(hex: 0x14110E) : Color(hex: 0x14110E) }
    /// `--sheet` веба: тёмная #17150F, светлая #FFFFFF. Светлая с 28к.4 (палитра Д) — #F3F3F5.
    public var sheet: Color { dark ? Color(hex: 0x17150F) : Color(hex: 0xF3F3F5) }
    /// `--sheet-2` веба: тёмная #131109, светлая #F1EDE4. Светлая натива с 28к.3 — #F6F6F8. Светлая с 28к.4 (палитра Д) — #ECECEE.
    public var sheet2: Color { dark ? Color(hex: 0x131109) : Color(hex: 0xECECEE) }
    /// `--sheet-3` веба: тёмная #1A1710, светлая #FFFFFF. Светлая натива с 28к.3 — #FFFFFF (0.72). Светлая с 28к.4 (палитра Д) — #F3F3F5.
    public var sheet3: Color { dark ? Color(hex: 0x1A1710) : Color(hex: 0xF3F3F5, alpha: 0.72) }
    /// `--peek-1` веба: тёмная #1B1811, светлая #FFFFFF. Светлая с 28к.4 (палитра Д) — #F3F3F5.
    public var peek1: Color { dark ? Color(hex: 0x1B1811) : Color(hex: 0xF3F3F5) }
    /// `--peek-2` веба: тёмная #221E16, светлая #F6F2E8. Светлая натива с 28к.3 — #F2F2F5. Светлая с 28к.4 (палитра Д) — #EAEAEC.
    public var peek2: Color { dark ? Color(hex: 0x221E16) : Color(hex: 0xEAEAEC) }
    /// `--stack-shade` веба: тёмная rgba(0,0,0,0.55), светлая rgba(23,21,15,0.16).
    public var stackShade: Color { dark ? Color(hex: 0x000000, alpha: 0.55) : Color(hex: 0x17150F, alpha: 0.16) }
    /// `--stack-edge` веба: тёмная rgba(255,255,255,0.07), светлая rgba(23,21,15,0.05). Светлая натива с 28к.3 — #FFFFFF (0.85).
    public var stackEdge: Color { dark ? Color(hex: 0xFFFFFF, alpha: 0.07) : Color(hex: 0xFFFFFF, alpha: 0.85) }
    /// `--sheet-4` веба: тёмная #1A1712, светлая #FFFFFF. Светлая натива с 28к.3 — #FFFFFF (0.72). Светлая с 28к.4 (палитра Д) — #F3F3F5.
    public var sheet4: Color { dark ? Color(hex: 0x1A1712) : Color(hex: 0xF3F3F5, alpha: 0.72) }
    /// `--warn-bg` веба: тёмная #191510, светлая #FBF1DE.
    public var warnBg: Color { dark ? Color(hex: 0x191510) : Color(hex: 0xFBF1DE) }
    /// `--bad-bg` веба: тёмная #1D1512, светлая #FBE7DC.
    public var badBg: Color { dark ? Color(hex: 0x1D1512) : Color(hex: 0xFBE7DC) }
    /// `--badge-bg` веба: тёмная #241F17, светлая #F4F0E6. Светлая натива с 28к.3 — #F2F2F5. Светлая с 28к.4 (палитра Д) — #EAEAEC.
    public var badgeBg: Color { dark ? Color(hex: 0x241F17) : Color(hex: 0xEAEAEC) }
    /// `--hatch` веба: тёмная #1C1A14, светлая #E7E2D8. Светлая натива с 28к.3 — #E5E5E9. Светлая с 28к.4 (палитра Д) — #DEDEE0.
    public var hatch: Color { dark ? Color(hex: 0x1C1A14) : Color(hex: 0xDEDEE0) }
    /// `--hairline` веба: тёмная #1C1913, светлая #E2DCD1. Светлая натива с 28к.3 — #E0E0E4. Светлая с 28к.4 (палитра Д) — #D9D9DB.
    public var hairline: Color { dark ? Color(hex: 0x1C1913) : Color(hex: 0xD9D9DB) }
    /// `--on-brass` веба: тёмная #16120C, светлая #FFFFFF. Светлая натива с 28к.3 — чернила #141416 (на «Б»). Светлая с 28к.4 (палитра Д) — чернила #000000, как `chipInk` образца: чёрное на оранжевой заливке #F29230 — 9,0:1 (посчитано, не мерено на телефоне). Чёрные кнопки (`PlateTokens.blackFill`) несут белый знак, не оранжевый.
    public var onBrass: Color { dark ? Color(hex: 0x16120C) : Color(hex: 0x000000) }
    /// Приглушённая надпись на акценте (счётчики в выбранных чипах). Тёмная — `onBrass` 0,6 (как было); светлая — 0,92: при 0,6
    /// чернила на оранжевом дают 2,8:1, при 0,92 — 4,6:1 (мелкий текст).
    public var onBrassDim: Color { dark ? onBrass.opacity(0.6) : onBrass.opacity(0.92) }
    /// `--field` веба: тёмная #1C1A16, светлая #EAE5DB. Светлая натива с 28к.3 — #E9E9ED. Светлая с 28к.4 (палитра Д) — #E2E2E4.
    public var field: Color { dark ? Color(hex: 0x1C1A16) : Color(hex: 0xE2E2E4) }
    /// `--field-press` веба: тёмная #262218, светлая #DCD6C9. Светлая натива с 28к.3 — #DADADF. Светлая с 28к.4 (палитра Д) — #D3D3D6.
    public var fieldPress: Color { dark ? Color(hex: 0x262218) : Color(hex: 0xD3D3D6) }
    /// `--press` веба: тёмная #221F19, светлая #EDE9E1. Светлая натива с 28к.3 — #E2E2E6. Светлая с 28к.4 (палитра Д) — #DBDBDD.
    public var press: Color { dark ? Color(hex: 0x221F19) : Color(hex: 0xDBDBDD) }
    /// `--press-2` веба: тёмная #201C15, светлая #EBE6DC. Светлая натива с 28к.3 — #E8E8EC. Светлая с 28к.4 (палитра Д) — #E1E1E3.
    public var press2: Color { dark ? Color(hex: 0x201C15) : Color(hex: 0xE1E1E3) }
    /// `--press-warm` веба: тёмная #221D14, светлая #F6ECD8.
    public var pressWarm: Color { dark ? Color(hex: 0x221D14) : Color(hex: 0xF6ECD8) }
    /// `--press-brass` веба: тёмная #33291A, светлая #F7E9CF. Светлая натива с 28к.3 — #FFE7D9. Светлая с 28к.4 (палитра Д) — #F3E4D7.
    public var pressBrass: Color { dark ? Color(hex: 0x33291A) : Color(hex: 0xF3E4D7) }
    /// `--rail` веба: тёмная #2B2822, светлая #DCD6C9. Светлая натива с 28к.3 — #D9D9DE. Светлая с 28к.4 (палитра Д) — #D2D2D5.
    public var rail: Color { dark ? Color(hex: 0x2B2822) : Color(hex: 0xD2D2D5) }
    /// `--rail-2` веба: тёмная #2E2A24, светлая #D2CBBC. Светлая натива с 28к.3 — #CFCFD4. Светлая с 28к.4 (палитра Д) — #C8C8CB.
    public var rail2: Color { dark ? Color(hex: 0x2E2A24) : Color(hex: 0xC8C8CB) }
    /// `--rail-3` веба: тёмная #2C2820, светлая #D5CEC0. Светлая натива с 28к.3 — #D3D3D8. Светлая с 28к.4 (палитра Д) — #CCCCCF.
    public var rail3: Color { dark ? Color(hex: 0x2C2820) : Color(hex: 0xCCCCCF) }
    /// `--rail-4` веба: тёмная #2A261E, светлая #D8D1C3. Светлая натива с 28к.3 — #D6D6DB. Светлая с 28к.4 (палитра Д) — #CFCFD2.
    public var rail4: Color { dark ? Color(hex: 0x2A261E) : Color(hex: 0xCFCFD2) }
    /// `--rail-5` веба: тёмная #3A352E, светлая #C3BBAA. Светлая натива с 28к.3 — #C2C2C7. Светлая с 28к.4 (палитра Д) — #BBBBBE.
    public var rail5: Color { dark ? Color(hex: 0x3A352E) : Color(hex: 0xBBBBBE) }
    /// `--seg-on` веба: тёмная #2A2724, светлая #DDD6C8. Светлая натива с 28к.3 — #FFFFFF. Светлая с 28к.4 (палитра Д) — #F3F3F5.
    public var segOn: Color { dark ? Color(hex: 0x2A2724) : Color(hex: 0xF3F3F5) }
    /// `--bezel` веба: тёмная #1C1A17, светлая #D8D2C6. Светлая натива с 28к.3 — #D6D6DB. Светлая с 28к.4 (палитра Д) — #CFCFD2.
    public var bezel: Color { dark ? Color(hex: 0x1C1A17) : Color(hex: 0xCFCFD2) }
    /// `--edge` веба: тёмная #38332B, светлая #CFC8B9. Светлая натива с 28к.3 — #CBCBD0. Светлая с 28к.4 (палитра Д) — #C4C4C7.
    public var edge: Color { dark ? Color(hex: 0x38332B) : Color(hex: 0xC4C4C7) }
    /// `--ink` веба: тёмная #EFEAE0, светлая #17150F. Светлая натива с 28к.3 — #141416. Светлая с 28к.4 (палитра Д) — #000000.
    public var ink: Color { dark ? Color(hex: 0xEFEAE0) : Color(hex: 0x000000) }
    /// `--ink-2` веба: тёмная #C9C2B6, светлая #3A352E. Светлая натива с 28к.3 — #3A3A3E.
    public var ink2: Color { dark ? Color(hex: 0xC9C2B6) : Color(hex: 0x3A3A3E) }
    /// `--ink-2b` веба: тёмная #C0B8AA, светлая #423C33. Светлая натива с 28к.3 — #424246.
    public var ink2b: Color { dark ? Color(hex: 0xC0B8AA) : Color(hex: 0x424246) }
    /// `--ink-3` веба: тёмная #A8A093, светлая #55504A. Светлая натива с 28к.3 — #545458. Светлая с 28к.4 (палитра Д) — #5C5C62.
    public var ink3: Color { dark ? Color(hex: 0xA8A093) : Color(hex: 0x5C5C62) }
    /// `--ink-3b` веба: тёмная #A89C86, светлая #5A5348. Светлая натива с 28к.3 — #5A5A5E.
    public var ink3b: Color { dark ? Color(hex: 0xA89C86) : Color(hex: 0x5A5A5E) }
    /// `--ink-4` веба: тёмная #8A8478, светлая #6B6559. Светлая натива с 28к.3 — #626267.
    public var ink4: Color { dark ? Color(hex: 0x8A8478) : Color(hex: 0x626267) }
    /// `--ink-5` веба: тёмная #6B6559, светлая #857E70. Светлая натива с 28к.3 — #69696E.
    public var ink5: Color { dark ? Color(hex: 0x6B6559) : Color(hex: 0x69696E) }
    /// `--ink-5b` веба: тёмная #6E6558, светлая #857E70. Светлая натива с 28к.3 — #69696E.
    public var ink5b: Color { dark ? Color(hex: 0x6E6558) : Color(hex: 0x69696E) }
    /// `--ink-6` веба: тёмная #635E54, светлая #8C8578. Светлая натива с 28к.3 — #69696E.
    public var ink6: Color { dark ? Color(hex: 0x635E54) : Color(hex: 0x69696E) }
    /// `--ink-7` веба: тёмная #55504A, светлая #9A9385. Светлая натива с 28к.3 — #86868B.
    public var ink7: Color { dark ? Color(hex: 0x55504A) : Color(hex: 0x86868B) }
    /// `--ink-8` веба: тёмная #4A453E, светлая #ADA697. Светлая натива с 28к.3 — #A1A1A6.
    public var ink8: Color { dark ? Color(hex: 0x4A453E) : Color(hex: 0xA1A1A6) }
    /// `--ink-9` веба: тёмная #45403A, светлая #B5AE9F. Светлая натива с 28к.3 — #ACACB1.
    public var ink9: Color { dark ? Color(hex: 0x45403A) : Color(hex: 0xACACB1) }
    /// `--ink-10` веба: тёмная #3A352F, светлая #BFB8A9. Светлая натива с 28к.3 — #BABABF.
    public var ink10: Color { dark ? Color(hex: 0x3A352F) : Color(hex: 0xBABABF) }
    /// `--brass` веба: тёмная #E2A44C, светлая #A9721F. Светлая натива с 28к.3 — #E4570B. Светлая с 28к.4 (палитра Д) — #F29230.
    public var brass: Color { dark ? Color(hex: 0xE2A44C) : Color(hex: 0xF29230) }
    /// Текст акцента. Тёмная — тот же `brass` (тёмная тема не меняется). Светлая с 28к.4 — #F09329, оранжевый образца «как есть»:
    /// на блоке #F3F3F5 2,1:1 и на фоне #E6E6E7 2,0:1 (посчитано) — это вид образца, Алексей числа видел и выбрал Д без затемнённых тонов.
    /// Список мест с мелким оранжевым текстом — в отчёте 28к.4. В «Б» было #B83C00 (5,7:1 на белом).
    public var brassInk: Color { dark ? Color(hex: 0xE2A44C) : Color(hex: 0xF09329) }
    /// Мягкий акцент как текст (28к.3): тёмная — `brassSoft`, светлая — тёмный оранжевый, как `brassInk`. Светлая с 28к.4 (палитра Д) — #F09329.
    public var brassSoftInk: Color { dark ? Color(hex: 0xD9AC6B) : Color(hex: 0xF09329) }
    /// `--brass-soft` веба: тёмная #D9AC6B, светлая #9B6A22. Светлая натива с 28к.3 — #E4570B. Светлая с 28к.4 (палитра Д) — #F29230.
    public var brassSoft: Color { dark ? Color(hex: 0xD9AC6B) : Color(hex: 0xF29230) }
    /// `--brass-deep` веба: тёмная #C9853F, светлая #8A5A18.
    public var brassDeep: Color { dark ? Color(hex: 0xC9853F) : Color(hex: 0x8A5A18) }
    /// Числа и подписи субботы и воскресенья (только натив, Алексей 28.10: «выделить выходные»). Не новый цвет, а
    /// `brassDeep`: из янтарных токенов только он держит контраст ≥ 4,5:1 к фону, листу и подложке месяца в обеих
    /// темах (тёмная 6,2–6,7, светлая 4,9–5,7; `brass` в светлой — 3,4–3,9, `brassSoft` — 3,9–4,5).
    public var weekend: Color { brassDeep }
    /// Знак солнца у основания дуги (восход, закат) и на ленте «Света» (28к.4, слово Алексея 13.11: «значки солнца под дугой плохие»).
    /// Светлая — оранжевый дуги #F09329, тот же, что у её концов; прежний `brassDeep` (#8A5A18) читался бурым. Тёмная — `brassDeep`, как было.
    public var sunSign: Color { dark ? Color(hex: 0xC9853F) : Color(hex: 0xF09329) }
    /// `--brass-dark` веба: тёмная #8A4B22, светлая #6E3C15. Светлая натива с 28к.3 — #B83C00. Светлая с 28к.4 (палитра Д) — #F09329.
    public var brassDark: Color { dark ? Color(hex: 0x8A4B22) : Color(hex: 0xF09329) }
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
