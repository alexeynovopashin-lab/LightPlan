import SwiftUI
import LightPlanCore

/// Цветовые токены экрана «Свет», перенесённые буквально из CSS веба
/// (`--ink`, `--ink-3`, `--ink-4`, `--brass`, `--green`, `--blue`,
/// `--tone-good`, `--moon`, `--meter-off`). Экран ещё не заводит общую тему
/// пакета (её нет ни у одного экрана — «Свет» первый), поэтому токены живут
/// здесь тем же приёмом, каким `DomeView` уже завёл свои несколько цветов
/// (комментарий там же: «купол ещё не заведён в общий словарь тем»).
enum LightScreenTheme {
    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color(hex: 0x17150F) : Color(hex: 0xEFEAE0)
    }
    static func ink3(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color(hex: 0x55504A) : Color(hex: 0xA8A093)
    }
    static func ink4(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color(hex: 0x6B6559) : Color(hex: 0x8A8478)
    }
    static func brass(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color(hex: 0xA9721F) : Color(hex: 0xE2A44C)
    }
    static func green(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color(hex: 0x5F6B4E) : Color(hex: 0xA8B49B)
    }
    static func blue(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color(hex: 0x3F6088) : Color(hex: 0x7C9CC4)
    }
    static func toneGood(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color(hex: 0x6B6559) : Color(hex: 0xB5AC9C)
    }
    /// `--moon` веба не переопределяется в светлой теме — один и тот же
    /// голубоватый цвет в обеих.
    static let moon = Color(hex: 0xA8BDD8)
    static func meterOff(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color(hex: 0xD2CBBC) : Color(hex: 0x3A352E)
    }
    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.07) : Color.white.opacity(0.07)
    }

    /// `TONE` веба плюс «отличный» тон, который берёт цвет состояния
    /// напрямую, а не фиксированный токен (веб: `tone==='excellent' ? col : TONE[tone]`).
    static func toneColor(_ tone: LightTone, state: SkyColor, scheme: ColorScheme) -> Color {
        switch tone {
        case .excellent: Color(state)
        case .good: toneGood(scheme)
        case .neutral: ink4(scheme)
        case .stars: moon
        }
    }

    static func sunsetColor(_ tone: LightTelemetry.SunsetTone, scheme: ColorScheme) -> Color {
        switch tone {
        case .brass: brass(scheme)
        case .green: green(scheme)
        case .ink: ink(scheme)
        case .blue: blue(scheme)
        case .muted: ink4(scheme)
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
