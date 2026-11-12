import Testing
import Foundation
import SwiftUI
@testable import LightPlanUI

/// 28к.3: светлая тема — вариант «Б» (Алексей 12.11 «Б, тёмный оранжевый») в токенах `Palette`, без флага.
/// Три вещи: (1) значения светлых токенов и числа норм (справка 28к.1, § 1); (2) тёмная ветка байт в байт как в `d468b34`;
/// (3) новые токены тёмного не меняют. Что экран пиксель в пиксель прежний в тёмной — доказано кадрами
/// (`docs/light_theme_2026-11/tokens/README.md`).
struct LightTokensTests {
    // MARK: - Помощники

    private typealias RGB = (r: Double, g: Double, b: Double, a: Double)

    private static func rgb(_ c: Color) -> RGB {
        let x = c.resolve(in: EnvironmentValues())
        return (Double(x.red), Double(x.green), Double(x.blue), Double(x.opacity))
    }
    private static func hex(_ c: Color) -> UInt32 {
        let v = rgb(c)
        func b(_ x: Double) -> UInt32 { UInt32((x * 255).rounded()) }
        return b(v.r) << 16 | b(v.g) << 8 | b(v.b)
    }
    private static func over(_ top: Color, _ back: Color) -> RGB {
        let t = rgb(top), k = rgb(back)
        return (t.r * t.a + k.r * (1 - t.a), t.g * t.a + k.g * (1 - t.a), t.b * t.a + k.b * (1 - t.a), 1)
    }
    private static func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func Y(_ v: RGB) -> Double { 0.2126 * lin(v.r) + 0.7152 * lin(v.g) + 0.0722 * lin(v.b) }
    private static func ratio(_ a: RGB, _ b: RGB) -> Double {
        let ya = Y(a), yb = Y(b)
        return (max(ya, yb) + 0.05) / (min(ya, yb) + 0.05)
    }
    private static func lstar(_ v: RGB) -> Double {
        let y = Y(v)
        let f = y > 0.008856 ? cbrt(y) : 7.787 * y + 16.0 / 116
        return 116 * f - 16
    }
    /// Контраст `fg` (с прозрачностью) на `back`.
    private static func cr(_ fg: Color, _ back: Color) -> Double { ratio(over(fg, back), rgb(back)) }

    private static let L = Palette(.light), D = Palette(.dark)
    private static let white = Color.white

    // MARK: - Значения

    @Test func lightValuesAreVariantB() {
        let p = Self.L
        #expect(Self.hex(p.surface) == 0xEDEDF0)     // фон страницы
        #expect(Self.hex(p.bg) == 0xE3E3E7)
        #expect(Self.hex(p.sheet) == 0xFFFFFF)
        #expect(Self.hex(p.brass) == 0xE4570B)        // яркий оранжевый: заливки, обводки, крупные знаки
        #expect(Self.hex(p.glyph) == 0xE4570B)
        #expect(Self.hex(p.brassInk) == 0xB83C00)     // тёмный оранжевый: текст
        #expect(Self.hex(p.brassSoftInk) == 0xB83C00)
        #expect(Self.hex(p.pressBrass) == 0xFFE7D9)
        #expect(Self.hex(p.onBrass) == 0x141416)      // текст на оранжевой заливке — чернила, не белое
        #expect(Self.hex(p.segOn) == 0xFFFFFF)
        #expect(Self.hex(p.ink) == 0x141416)
        #expect(Self.hex(p.weekend) == 0x8A5A18)      // выходные остаются латунью
        #expect(abs(Self.rgb(p.sheet3).a - 0.72) < 0.001 && abs(Self.rgb(p.sheet4).a - 0.72) < 0.001)  // под ними стекло
        #expect(Self.hex(p.stackEdge) == 0xFFFFFF && Self.hex(p.glassFill) == 0xFFFFFF)  // блик белый
    }

    @Test(arguments: paletteTable.indices)
    func everyTokenKeepsItsValue(_ i: Int) {
        let t = paletteTable[i]
        let d = Self.rgb(Self.D[keyPath: t.key]), l = Self.rgb(Self.L[keyPath: t.key])
        #expect(Self.hex(Self.D[keyPath: t.key]) == t.dark, "\(t.name): тёмная изменилась")
        #expect(abs(d.a - t.darkA) < 0.001, "\(t.name): прозрачность тёмной изменилась")
        #expect(Self.hex(Self.L[keyPath: t.key]) == t.light, "\(t.name): светлая изменилась")
        #expect(abs(l.a - t.lightA) < 0.001, "\(t.name): прозрачность светлой изменилась")
    }

    @Test func darkThemeIsUntouched() {
        // Новые токены в тёмной — значения старых: ничего нового не рисуется.
        #expect(Self.hex(Self.D.brassInk) == Self.hex(Self.D.brass))
        #expect(Self.hex(Self.D.brassSoftInk) == Self.hex(Self.D.brassSoft))
        let dim = Self.rgb(Self.D.onBrassDim), on = Self.rgb(Self.D.onBrass)
        #expect(abs(dim.a - 0.6) < 0.001 && dim.r == on.r)
        // Приёмы глубины в тёмной ничего не добавляют: условие в одном месте.
        let src = (try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/LightPlanUI/Theme/Plate.swift").standardizedFileURL, encoding: .utf8)) ?? ""
        #expect(src.contains("if pal.dark { self }"))
        #expect(src.contains("if on, !pal.dark"))
    }

    // MARK: - Нормы (справка 28к.1, § 1)

    @Test func textNorms() {
        let p = Self.L
        let page = p.surface, plate = p.sheet
        for (name, c) in [("ink", p.ink), ("ink2", p.ink2), ("ink3", p.ink3), ("ink4", p.ink4), ("ink5", p.ink5), ("ink6", p.ink6)] {
            #expect(Self.cr(c, plate) >= 4.5, "\(name) на плашке")
            #expect(Self.cr(c, page) >= 4.5, "\(name) на фоне")
        }
        // Подпись раздела — тихая, 3:1 (знак и крупный/служебный текст).
        #expect(Self.cr(p.ink7, page) >= 3.0)
    }

    @Test func orangeTextNorms() {
        let p = Self.L
        // Тёмный оранжевый — текст: на белом, на фоне, на бледной заливке пилюли, на листе карточки.
        #expect(Self.cr(p.brassInk, p.sheet) >= 4.5)
        #expect(Self.cr(p.brassInk, p.surface) >= 4.5)
        #expect(Self.cr(p.brassInk, p.pressBrass) >= 4.5)
        #expect(Self.cr(p.brassInk, p.sheet2) >= 4.5)
        // Яркий — только заливки и крупные знаки: 3:1 на белом и на фоне.
        #expect(Self.cr(p.brass, p.sheet) >= 3.0)
        #expect(Self.cr(p.brass, p.surface) >= 3.0)
        // Текст на оранжевой заливке: чернила 4,96, приглушённые тоже ≥ 4,5. Белое (3,71) для мелкого не годится.
        #expect(Self.cr(p.onBrass, p.brass) >= 4.5)
        #expect(Self.cr(p.onBrassDim, p.brass) >= 4.5)
        #expect(Self.cr(Self.white, p.brass) < 4.5)
        // Оранжевое на чёрном («+ Съёмка», выбранный день).
        #expect(Self.cr(p.brass, PlateTokens.blackFill) >= 4.5)
        #expect(Self.cr(Self.white, PlateTokens.blackFill) >= 4.5)
    }

    @Test func plateAndSelectionNorms() {
        let p = Self.L
        let page = Self.rgb(p.surface), plate = Self.rgb(p.sheet)
        // Плашка: ≥ 1,12:1 и ΔL* ≥ 4 к странице, и тень (PlateTokens.plate) поверх.
        #expect(Self.ratio(plate, page) >= 1.12)
        #expect(Self.lstar(plate) - Self.lstar(page) >= 4)
        #expect(PlateTokens.plate.opacity >= 0.10 && PlateTokens.plate.radius >= 16)
        // Плашка «Съёмок» (белое 0,72 над стеклом над страницей) не тусклее нормы к странице.
        let glassRow = Self.over(p.sheet4, p.surface)
        #expect(Self.ratio(glassRow, page) >= 1.08)
        // Выбранный сегмент к жёлобу: ≥ 1,2:1 и ΔL* ≥ 7.
        let sel = Self.rgb(p.segOn), trough = Self.rgb(p.bg)
        #expect(Self.ratio(sel, trough) >= 1.2)
        #expect(Self.lstar(sel) - Self.lstar(trough) >= 7)
        // Выбранный день — чёрный на подложке месяца: далеко за нормой.
        #expect(Self.ratio(Self.rgb(PlateTokens.blackFill), Self.over(p.sheetGlass, p.surface)) >= 1.2)
    }

    @Test func principleShineIsWhiteShadowIsDark() {
        #expect(Self.hex(PlateTokens.rimColor) == 0xFFFFFF)
        #expect(Self.hex(PlateTokens.shadowInk) == 0x000000)
        #expect(PlateTokens.glassVeil == 0.72)
    }
}

// Сгенерировано из Palette.swift (тёмные — коммит d468b34, светлые — 28к.3). Не править руками: тёмная тема не меняется.
nonisolated(unsafe) let paletteTable: [(name: String, key: KeyPath<Palette, Color>, dark: UInt32, darkA: Double, light: UInt32, lightA: Double)] = [
    ("glyph", \.glyph, 0xE2A44C, 1, 0xE4570B, 1),
    ("pinRing", \.pinRing, 0x14110E, 1, 0x3A352E, 1),
    ("arcMid", \.arcMid, 0xEFEAE0, 1, 0x141416, 1),
    ("knob", \.knob, 0xEFEAE0, 1, 0xFFFFFF, 1),
    ("knobEdge", \.knobEdge, 0x0F0E0C, 1, 0xC2C2C7, 1),
    ("meterOff", \.meterOff, 0x3A352E, 1, 0xCFCFD4, 1),
    ("bar", \.bar, 0x0F0E0C, 0.72, 0xEDEDF0, 0.8),
    ("bar2", \.bar2, 0x17150F, 0.55, 0xFFFFFF, 0.62),
    ("fillA", \.fillA, 0x0F0E0C, 0.75, 0xEDEDF0, 0.8),
    ("fillB", \.fillB, 0x0F0E0C, 0.6, 0xE3E3E7, 0.72),
    ("overlay", \.overlay, 0x12100E, 0.82, 0xEDEDF0, 0.86),
    ("overlay2", \.overlay2, 0x080706, 0.94, 0xEDEDF0, 0.96),
    ("overlay3", \.overlay3, 0x2C2924, 0.68, 0xD3D3D8, 0.74),
    ("hair", \.hair, 0xFFFFFF, 0.05, 0x000000, 0.07),
    ("sheetGlass", \.sheetGlass, 0x17150F, 0.74, 0xFFFFFF, 0.78),
    ("knobGlass", \.knobGlass, 0xEFEAE0, 0.26, 0xFFFFFF, 0.40),
    ("drumFace", \.drumFace, 0xFFFFFF, 0.05, 0x17150F, 0.05),
    ("mapGlass", \.mapGlass, 0x17150F, 0.30, 0xFFFFFF, 0.26),
    ("hair2", \.hair2, 0xFFFFFF, 0.04, 0x000000, 0.06),
    ("hair3", \.hair3, 0xFFFFFF, 0.03, 0x000000, 0.05),
    ("hair4", \.hair4, 0xFFFFFF, 0.07, 0x000000, 0.09),
    ("hair5", \.hair5, 0xFFFFFF, 0.18, 0x000000, 0.20),
    ("glassFill", \.glassFill, 0xFFFFFF, 0.07, 0xFFFFFF, 0.3),
    ("glassShine", \.glassShine, 0xFFFFFF, 0.30, 0xFFFFFF, 0.95),
    ("glassCast", \.glassCast, 0x000000, 0.45, 0x17150F, 0.16),
    ("drumLip", \.drumLip, 0xFFFFFF, 0.18, 0xFFFFFF, 0.95),
    ("drumGlass", \.drumGlass, 0xFFFFFF, 0.13, 0xFFFFFF, 0.45),
    ("inkA22", \.inkA22, 0xEFEAE0, 0.22, 0x17150F, 0.22),
    ("inkA20", \.inkA20, 0xEFEAE0, 0.2, 0x17150F, 0.2),
    ("inkA24", \.inkA24, 0xEFEAE0, 0.24, 0x17150F, 0.24),
    ("inkA40", \.inkA40, 0xEFEAE0, 0.4, 0x17150F, 0.4),
    ("inkA12", \.inkA12, 0xEFEAE0, 0.12, 0x17150F, 0.12),
    ("inkA10", \.inkA10, 0xEFEAE0, 0.10, 0x17150F, 0.10),
    ("inkA08", \.inkA08, 0xEFEAE0, 0.08, 0x17150F, 0.08),
    ("bg", \.bg, 0x070606, 1, 0xE3E3E7, 1),
    ("surface", \.surface, 0x0F0E0C, 1, 0xEDEDF0, 1),
    ("canvas", \.canvas, 0x14110E, 1, 0x14110E, 1),
    ("sheet", \.sheet, 0x17150F, 1, 0xFFFFFF, 1),
    ("sheet2", \.sheet2, 0x131109, 1, 0xF6F6F8, 1),
    ("sheet3", \.sheet3, 0x1A1710, 1, 0xFFFFFF, 0.72),
    ("peek1", \.peek1, 0x1B1811, 1, 0xFFFFFF, 1),
    ("peek2", \.peek2, 0x221E16, 1, 0xF2F2F5, 1),
    ("stackShade", \.stackShade, 0x000000, 0.55, 0x17150F, 0.16),
    ("stackEdge", \.stackEdge, 0xFFFFFF, 0.07, 0xFFFFFF, 0.85),
    ("sheet4", \.sheet4, 0x1A1712, 1, 0xFFFFFF, 0.72),
    ("warnBg", \.warnBg, 0x191510, 1, 0xFBF1DE, 1),
    ("badBg", \.badBg, 0x1D1512, 1, 0xFBE7DC, 1),
    ("badgeBg", \.badgeBg, 0x241F17, 1, 0xF2F2F5, 1),
    ("hatch", \.hatch, 0x1C1A14, 1, 0xE5E5E9, 1),
    ("hairline", \.hairline, 0x1C1913, 1, 0xE0E0E4, 1),
    ("onBrass", \.onBrass, 0x16120C, 1, 0x141416, 1),
    ("field", \.field, 0x1C1A16, 1, 0xE9E9ED, 1),
    ("fieldPress", \.fieldPress, 0x262218, 1, 0xDADADF, 1),
    ("press", \.press, 0x221F19, 1, 0xE2E2E6, 1),
    ("press2", \.press2, 0x201C15, 1, 0xE8E8EC, 1),
    ("pressWarm", \.pressWarm, 0x221D14, 1, 0xF6ECD8, 1),
    ("pressBrass", \.pressBrass, 0x33291A, 1, 0xFFE7D9, 1),
    ("rail", \.rail, 0x2B2822, 1, 0xD9D9DE, 1),
    ("rail2", \.rail2, 0x2E2A24, 1, 0xCFCFD4, 1),
    ("rail3", \.rail3, 0x2C2820, 1, 0xD3D3D8, 1),
    ("rail4", \.rail4, 0x2A261E, 1, 0xD6D6DB, 1),
    ("rail5", \.rail5, 0x3A352E, 1, 0xC2C2C7, 1),
    ("segOn", \.segOn, 0x2A2724, 1, 0xFFFFFF, 1),
    ("bezel", \.bezel, 0x1C1A17, 1, 0xD6D6DB, 1),
    ("edge", \.edge, 0x38332B, 1, 0xCBCBD0, 1),
    ("ink", \.ink, 0xEFEAE0, 1, 0x141416, 1),
    ("ink2", \.ink2, 0xC9C2B6, 1, 0x3A3A3E, 1),
    ("ink2b", \.ink2b, 0xC0B8AA, 1, 0x424246, 1),
    ("ink3", \.ink3, 0xA8A093, 1, 0x545458, 1),
    ("ink3b", \.ink3b, 0xA89C86, 1, 0x5A5A5E, 1),
    ("ink4", \.ink4, 0x8A8478, 1, 0x626267, 1),
    ("ink5", \.ink5, 0x6B6559, 1, 0x69696E, 1),
    ("ink5b", \.ink5b, 0x6E6558, 1, 0x69696E, 1),
    ("ink6", \.ink6, 0x635E54, 1, 0x69696E, 1),
    ("ink7", \.ink7, 0x55504A, 1, 0x86868B, 1),
    ("ink8", \.ink8, 0x4A453E, 1, 0xA1A1A6, 1),
    ("ink9", \.ink9, 0x45403A, 1, 0xACACB1, 1),
    ("ink10", \.ink10, 0x3A352F, 1, 0xBABABF, 1),
    ("brass", \.brass, 0xE2A44C, 1, 0xE4570B, 1),
    ("brassSoft", \.brassSoft, 0xD9AC6B, 1, 0xE4570B, 1),
    ("brassDeep", \.brassDeep, 0xC9853F, 1, 0x8A5A18, 1),
    ("brassDark", \.brassDark, 0x8A4B22, 1, 0xB8440A, 1),
    ("green", \.green, 0xA8B49B, 1, 0x5F6B4E, 1),
    ("blue", \.blue, 0x7C9CC4, 1, 0x3F6088, 1),
    ("toneGood", \.toneGood, 0xB5AC9C, 1, 0x6B6559, 1),
    ("terra", \.terra, 0xC9663D, 1, 0xA84E27, 1),
    ("terra2", \.terra2, 0xB9603D, 1, 0x9E4722, 1),
    ("badInk", \.badInk, 0xD9A08A, 1, 0x8A3F22, 1),
    ("warnInk", \.warnInk, 0xD9C2A0, 1, 0x7A5A22, 1),
    ("moon", \.moon, 0xA8BDD8, 1, 0xA8BDD8, 1),
    ("moonLit", \.moonLit, 0xCFD6DE, 1, 0xCFD6DE, 1),
    ("moonDark", \.moonDark, 0x16161A, 1, 0x16161A, 1),
]