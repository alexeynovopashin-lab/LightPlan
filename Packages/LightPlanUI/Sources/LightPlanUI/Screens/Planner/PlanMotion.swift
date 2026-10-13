import SwiftUI
import LightPlanCore
import LightPlanDomain
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Единая точка выбора движения «Съёмок» (29.2ж, по образцу `PlannerDayBody.flipMotion` из 29.2е): при системном
/// «Уменьшении движения» ничто не едет, не скользит и не пружинит — состояние меняется сразу, как в бете
/// (`@media (prefers-reduced-motion)` гасит переходы). Любая кривая «Съёмок» проходит через `pick`; новое движение
/// без `pick` — ошибка (стенд `Tools/motion_bench.js --reduce` её покажет).
///
/// Стенд движений зовёт ровно те же именованные действия, что и палец (`openCard`, `stats`, `setScope`, …).
enum PlanMotion {
    /// Тесты: свой ответ на «Уменьшить движение»; `nil` — отвечает система.
    nonisolated(unsafe) static var stillOverride: Bool?

    /// «Уменьшение движения» включено у системы (или у теста).
    static var still: Bool {
        if let o = stillOverride { return o }
        #if canImport(UIKit)
        return UIAccessibility.isReduceMotionEnabled
        #elseif canImport(AppKit)
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        return false
        #endif
    }

    /// Кривая, если движение разрешено; `nil` (мгновенно) при «Уменьшении движения».
    static func pick(_ a: Animation, still: Bool = PlanMotion.still) -> Animation? { still ? nil : a }

    // MARK: - Кривые (значения беты, не меняются)

    /// Слой выезжает снизу и карточка открывается (веб `.overlay`: 0,42 с, E1).
    static let overlay = Animation.timingCurve(0.25, 1, 0.4, 1, duration: 0.42)
    /// Слой статистики въезжает справа (`.overlay-right`: 0,36 с).
    static let stats = Animation.timingCurve(0.25, 1, 0.4, 1, duration: 0.36)
    /// Смена вида, тап по ячейке месяца и строке недели, строки листа блока.
    static let snap = Animation.snappy(duration: 0.25)
    /// Веер видов и веер удержания (`.scope-menu`, `.ev-fan`).
    static let fan = Animation.easeOut(duration: 0.16)
    /// Полоса «Вернуть» въезжает и уходит.
    static let undoBar = Animation.timingCurve(0.25, 1, 0.4, 1, duration: 0.32)
    /// Строки корзины, «Вернуть» из корзины.
    static let bin = Animation.easeOut(duration: 0.2)
    /// Кнопка «в конец / в начало» в поиске.
    static let jump = Animation.easeInOut(duration: 0.35)
    /// Зум года: ход, проявление ленты, гашение источника.
    static let yearZoom = Animation.timingCurve(0.3, 0.7, 0.1, 1, duration: 0.46)
    static let yearFadeIn = Animation.linear(duration: 0.16)
    static let yearFadeOut = Animation.linear(duration: 0.2).delay(0.06)

    // MARK: - Действия (палец и стенд зовут одни и те же)

    @MainActor static func openCard(_ app: AppModel, id: String) {
        withAnimation(pick(overlay)) { app.openCard(id: id) }
    }

    @MainActor static func closeCard(_ app: AppModel) {
        withAnimation(pick(overlay)) { app.closeCard() }
    }

    @MainActor static func stats(_ nav: PlannerNav, open: Bool) {
        withAnimation(pick(stats)) { nav.statsOpen = open }
    }

    @MainActor static func search(_ nav: PlannerNav, open: Bool) {
        withAnimation(pick(overlay)) { nav.searchOpen = open }
    }

    @MainActor static func lenta(_ app: AppModel, _ nav: PlannerNav, open: Bool) {
        withAnimation(pick(overlay)) {
            if open { nav.openLenta(from: app.planner.month) } else { nav.lentaOpen = false }
        }
    }

    @MainActor static func year12(_ nav: PlannerNav, open: Bool) {
        withAnimation(pick(overlay)) { nav.year12Open = open }
    }

    @MainActor static func setScope(_ app: AppModel, _ s: CalScope) {
        withAnimation(pick(snap)) { app.planner.setScope(s) }
    }

    @MainActor static func tapMonthCell(_ app: AppModel, _ day: CivilDate) {
        withAnimation(pick(snap)) { _ = app.planner.tapMonthCell(day) }
    }

    @MainActor static func tapWeekRow(_ app: AppModel, _ day: CivilDate) {
        withAnimation(pick(snap)) { app.planner.tapWeekRow(day) }
    }

    @MainActor static func restore(_ app: AppModel, id: String) {
        withAnimation(pick(bin)) { app.restoreSession(id: id) }
    }

    @MainActor static func takeUndo(_ app: AppModel) {
        withAnimation(pick(bin)) { app.takeUndo() }
    }
}

/// Выезд слоя снизу (веб `.overlay`) и слоя статистики справа: глобальные имена остались, кривая — через `pick`.
var overlaySlide: Animation? { PlanMotion.pick(PlanMotion.overlay) }
var statsSlide: Animation? { PlanMotion.pick(PlanMotion.stats) }
