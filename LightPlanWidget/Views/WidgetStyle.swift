import SwiftUI
import LightPlanDomain

/// Цвета и мелочи виджета. Те же значения, что у `Palette` приложения (тёмная: подложка 0F0E0C, чернила EFEAE0;
/// светлая: FAF8F3 / 17150F), янтарь — свет; расширение не тянет `LightPlanUI`, поэтому числа здесь свои.
struct WidgetStyle {
    let dark: Bool
    var ink: Color { dark ? Color(red: 0xEF / 255, green: 0xEA / 255, blue: 0xE0 / 255) : Color(red: 0x17 / 255, green: 0x15 / 255, blue: 0x0F / 255) }
    var ink2: Color { ink.opacity(0.62) }
    var surface: Color { dark ? Color(red: 0x0F / 255, green: 0x0E / 255, blue: 0x0C / 255) : Color(red: 0xFA / 255, green: 0xF8 / 255, blue: 0xF3 / 255) }
    /// Янтарь света; на светлой подложке темнее, чтобы читался.
    var amber: Color { dark ? Color(red: 0xE2 / 255, green: 0xA4 / 255, blue: 0x4C / 255) : Color(red: 0x9A / 255, green: 0x5F / 255, blue: 0x0A / 255) }
    /// Латунь бирки «α» — как на значке тестовых сборок (`Tools/app_icon_alpha.py`): #E2A44C, буква #0F0E0C.
    static let brass = Color(red: 0xE2 / 255, green: 0xA4 / 255, blue: 0x4C / 255)
    static let brassInk = Color(red: 0x0F / 255, green: 0x0E / 255, blue: 0x0C / 255)
}

/// Латунный кружок с «α» в углу виджета слота. У основного «Light Plan» его нет (`WidgetFeed.isMainApp`).
struct AlphaBadge: View {
    var body: some View {
        Text("α")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(WidgetStyle.brassInk)
            .frame(width: 16, height: 16)
            .background(Circle().fill(WidgetStyle.brass))
            .accessibilityLabel("alpha")
    }
}

/// Отсчёт до `to`, который идёт сам (без обновлений виджета). Промежуток строится от `from` — момента кадра, а
/// `from ≤ to` кадр гарантирует; прошедшая цель — прочерк, а не перевёрнутый диапазон (он ронял расширение в спайке).
struct CountdownText: View {
    let from: Date
    let to: Date
    var body: some View {
        if to > from {
            Text(timerInterval: from...to, countsDown: true, showsHours: to.timeIntervalSince(from) >= 3600)
                .monospacedDigit()
        } else {
            Text("0:00").monospacedDigit()
        }
    }
}
