import SwiftUI
import LightPlanDomain

/// Какой вид стоит на какой форме виджета (30б.2в) — одним местом, чтобы расширение и тесты видели одно и то же.
///
/// - Малый и средний: идёт съёмка — кольцо (`SmallLiveView`, `MediumLiveView`; выбор Алексея 26.10); иначе то, что было в 30б.2:
///   свет и ближайшие съёмки (кольцу без съёмки нечего считать). Кольцу нужны все поля плашки под деления, поэтому виджет
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
            if frame.kind == .live { MediumLiveView(frame: frame, alpha: alpha) }
            else { MediumView(frame: frame, alpha: alpha).padding(Self.margin) }
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
