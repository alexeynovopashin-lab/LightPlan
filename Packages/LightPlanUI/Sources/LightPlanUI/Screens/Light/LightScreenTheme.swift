import SwiftUI
import LightPlanCore

/// Цветовые токены экрана «Свет», перенесённые буквально из CSS веба
/// (`--ink`, `--ink-3`, `--ink-4`, `--brass`, `--green`, `--blue`,
/// `--tone-good`, `--moon`, `--meter-off`). Экран ещё не заводит общую тему
/// пакета (её нет ни у одного экрана — «Свет» первый), поэтому токены живут
/// здесь тем же приёмом, каким `DomeView` уже завёл свои несколько цветов
/// (комментарий там же: «купол ещё не заведён в общий словарь тем»).
/// Цвета экрана «Свет». С итерации 19б — тонкая обёртка над общей
/// `Palette` (переменные CSS веба по именам): до неё токены жили здесь
/// своими копиями, и фон светлой темы был `--bg` (#EDE9E1) вместо
/// поверхности экрана `--surface` (#FAF8F3) — сверка снимков дала Δ 27.
enum LightScreenTheme {
    static func ink(_ s: ColorScheme) -> Color { Palette(s).ink }
    static func ink2(_ s: ColorScheme) -> Color { Palette(s).ink2 }
    static func ink3(_ s: ColorScheme) -> Color { Palette(s).ink3 }
    static func ink4(_ s: ColorScheme) -> Color { Palette(s).ink4 }
    static func ink6(_ s: ColorScheme) -> Color { Palette(s).ink6 }
    static func brass(_ s: ColorScheme) -> Color { Palette(s).brass }
    static func green(_ s: ColorScheme) -> Color { Palette(s).green }
    static func blue(_ s: ColorScheme) -> Color { Palette(s).blue }
    static func toneGood(_ s: ColorScheme) -> Color { Palette(s).toneGood }
    /// `--moon` веба не переопределяется в светлой теме — один и тот же
    /// голубоватый цвет в обеих.
    static let moon = Palette(.dark).moon
    static func meterOff(_ s: ColorScheme) -> Color { Palette(s).meterOff }
    /// Фон экрана — `--surface`: на телефоне `.device` заливает весь экран
    /// им, `--bg` виден только вокруг «корпуса» на широком окне.
    static func background(_ s: ColorScheme) -> Color { Palette(s).surface }
    static func hairline(_ s: ColorScheme) -> Color { Palette(s).hair2 }

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
