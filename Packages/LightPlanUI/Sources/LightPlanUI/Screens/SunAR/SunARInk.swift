import SwiftUI

/// Чернила слоя AR (шаг 29.8в). Дуга и подписи лежат на живом кадре, а фон у него любой: белое небо, чёрная
/// комната, серый асфальт. Поэтому всё нарисованное — светлое на тёмной подложке или с тёмной обводкой, и
/// одинаково в обеих темах приложения: цвет слоя задаёт кадр, а не тема (светлая тема — не инверсия).
///
/// Числа — те, что видит `SunARInkTests`: контраст считается по этим константам на белом, сером и чёрном фоне.
enum SunARInk {
    /// Тёмная подложка под текстом и под панелью: чёрный с этой непрозрачностью.
    static let plateOpacity = 0.6
    /// Тёмная обводка под линией дуги и горизонта.
    static let outlineOpacity = 0.6
    /// Ширина светлой линии дуги и её обводки, pt.
    static let arcWidth: CGFloat = 3
    static let arcOutlineWidth: CGFloat = 7
    static let horizonWidth: CGFloat = 1.5
    static let horizonOutlineWidth: CGFloat = 4.5

    /// Светлое: линия, текст.
    static let light = Color.white
    /// Диск солнца.
    static let sunFill = Color(hex: 0xFFC24D)
    /// Земля под горизонтом в состоянии «нет камеры».
    static let groundOpacity = 0.42

    /// WCAG: относительная яркость sRGB-канала `0…1`.
    static func luminance(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Контраст светлого элемента (белый) с тёмной подложкой чёрного `alpha`, лежащей на фоне яркости `bg`
    /// (канал `0…1`, серый). Подложка сама смешивается с фоном: на белом небе она светлее, чем на чёрной комнате.
    static func contrast(onBackground bg: Double, plate alpha: Double) -> Double {
        let plate = luminance(bg * (1 - alpha))
        return (luminance(1) + 0.05) / (plate + 0.05)
    }

    /// Контраст обводки с фоном — по ней глаз отделяет линию от кадра.
    static func outlineContrast(onBackground bg: Double, plate alpha: Double) -> Double {
        let outline = luminance(bg * (1 - alpha))
        let back = luminance(bg)
        let (hi, lo) = (max(outline, back), min(outline, back))
        return (hi + 0.05) / (lo + 0.05)
    }
}
