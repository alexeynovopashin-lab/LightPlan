import SwiftUI
import LightPlanDomain

/// Какой вид стоит на какой форме виджета (30б.2в) — одним местом, чтобы расширение и тесты видели одно и то же.
///
/// - Малый и средний: идёт съёмка — демка Алексея 26.10, палитра Braun (`SmallLiveView`, `MediumLiveView` → `BraunWidget.swift`); иначе у малого то,
///   что было в 30б.2: свет и ближайшие съёмки (идущей съёмки нет — нечего считать). Средний с 30б.2в-5 и без идущей съёмки — Braun
///   (`BraunIdleView`, «Семья виджетов» 27.10): слева свет, справа неделя съёмок; прежний `MediumView` остался для плашки без места. Рискам нужны все поля плашки, поэтому виджет
///   отключает системные поля (`.contentMarginsDisabled()`), а остальным видам их ставит этот корень.
/// - Большой: день со съёмкой, а без съёмок — дуга солнца.
/// - Экран блокировки: круг (до золотого часа), прямоугольник (как у Календаря), строка. **Имена клиентов — только на «Домой»**
///   (малый, средний, большой): виды блокировки их не читают.
struct WidgetRoot: View {
    let frame: WidgetFrame
    let shape: WidgetShape
    let alpha: Bool

    /// Системные поля плашки «Домой», когда вид их не отключает.
    static let margin: CGFloat = 16

    var body: some View {
        switch shape {
        case .small:
            if frame.kind == .live { SmallLiveView(frame: frame, alpha: alpha) }
            else { SmallView(frame: frame, alpha: alpha).padding(Self.margin) }
        case .medium:
            switch frame.kind {
            case .live: MediumLiveView(frame: frame, alpha: alpha)
            // 30б.2в-5: съёмка впереди, свободный день и вечер — Braun, свет слева, неделя справа (Г, Д, Е «Семьи виджетов»).
            case .upcoming, .light: BraunIdleView(frame: frame, alpha: alpha)
            // Приложение ещё не оставило места: показывать нечего.
            case .blank: MediumView(frame: frame, alpha: alpha).padding(Self.margin)
            }
        case .large:
            LargeView(frame: frame, alpha: alpha)
        case .circular:
            LockCircularView(frame: frame, alpha: alpha)
        case .rectangular:
            LockRectangularView(frame: frame, alpha: alpha)
        case .inline:
            LockInlineView(frame: frame, alpha: alpha)
        }
    }
}
