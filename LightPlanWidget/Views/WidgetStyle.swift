import SwiftUI
import LightPlanDomain

/// Цвета и мелочи виджета. С 30и.13 (слово Алексея 15.11: «у всех виджетов разный цвет и подложка, надо как у Braun») — палитра Braun
/// (`BraunPalette`: тёмная #161616 / ECECEA / жёлтый F4B400, светлая «Braun белый» #E4E4E2 / 111111, акцент чёрный); раньше была тёплая
/// 0F0E0C/FAF8F3. Расширение не тянет `LightPlanUI`, поэтому числа здесь свои. Подложку рисует сам вид (`WidgetRoot`), не `containerBackground`:
/// на «Домой» система его осветляет (26.10, #161616 → #2E2E2E).
struct WidgetStyle {
    let dark: Bool
    private var pal: BraunPalette { BraunPalette(dark: dark) }
    var ink: Color { pal.text }
    var ink2: Color { pal.muted }
    var surface: Color { pal.bg }
    /// Акцент: жёлтый Braun на тёмной, чёрный на светлой (там жёлтым стоит только таблетка).
    var amber: Color { pal.amber }
    /// Заливка кружков ленты экрана активности (эскиз 14.11, `--app-bg`): тёмная #121110 на светлее подложке плашки.
    var surfaceOnPlate: Color { Color(red: 0x12 / 255, green: 0x11 / 255, blue: 0x10 / 255) }
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
