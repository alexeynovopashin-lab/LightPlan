#if os(iOS)
import ActivityKit
import Foundation
import LightPlanDomain

/// Свойства экрана активности (30б.3): они не меняются за жизнь активности, меняется только кадр (`ActivityFrame`).
///
/// **Один файл на два модуля:** расширение компилирует его само (синхронизируемая папка `LightPlanWidget/`), а приложению он виден как
/// ссылка в `Packages/LightPlanUI/Sources/LightPlanUI/Activity/`. Система сопоставляет активность с её видом по имени типа, поэтому
/// имя и кодирование должны быть одни — второй копии не должно быть.
struct ShootActivityAttributes: ActivityAttributes {
    typealias ContentState = ActivityFrame

    /// Съёмка, ради которой запущено: по ней приложение узнаёт свою активность после перезапуска.
    var shootId: String
    /// Когда запрошена: от этого момента система считает свои 8 часов, а длинный день продлевается перезапуском.
    var startedAt: Date
}
#endif
