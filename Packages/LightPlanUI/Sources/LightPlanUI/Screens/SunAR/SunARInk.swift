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
    /// Дуга (29.8в.3), снизу вверх: тёмная обводка → белая кромка → жила цвета света. До 29.8в.3 было
    /// 7 → 3 (белая линия без жилы); теперь белая кромка шире на жилу, и по 1 pt белого остаётся с каждой стороны.
    static let arcOutlineWidth: CGFloat = 9
    static let arcWidth: CGFloat = 5
    static let arcCoreWidth: CGFloat = 3
    /// Под горизонтом дуга идёт пунктиром: штрих и просвет, pt.
    static let arcDash: [CGFloat] = [7, 6]
    /// Подотрезков цвета на отрезок дуги между двумя точками (шаг 10 минут): переход цвета плавный, не ступенька.
    static let arcColorSteps = 4
    static let horizonWidth: CGFloat = 1.5
    static let horizonOutlineWidth: CGFloat = 4.5

    /// Светлое: линия, текст.
    static let light = Color.white
    /// Диск солнца.
    static let sunFill = Color(hex: 0xFFC24D)
    /// Метки солнца — стеклянные линзы (29.8в.3), диаметр, pt. Было: диск «сейчас» 22 (радиус 11) и кольцо
    /// выбранного момента того же размера.
    static let nowLensDiameter: CGFloat = 48
    static let pickedLensDiameter: CGFloat = 34
    /// Просвет между краем линзы и подписью, pt.
    static let markerLabelGap: CGFloat = 14
    /// Малая метка восхода и заката на горизонте, диаметр, pt.
    static let eventDot: CGFloat = 8
    /// Нижняя панель со временем и таймбаром: тёмная поверхность «Света» (`0F0E0C`) почти без просвета —
    /// чернила таймбара (`ink4` на краях) читаются на любом кадре.
    static let panelOpacity = 0.94
    static let panelColor = Color(hex: 0x0F0E0C)

    /// Цвет состояния света на этой высоте — остановка рельса таймбара «Света» (`PathStops`), без прозрачности.
    static func stateColor(altitude: Double) -> Color {
        let c = PathStops.at(altitude).rgb
        return Color(.sRGB, red: Double(c.0) / 255, green: Double(c.1) / 255, blue: Double(c.2) / 255, opacity: 1)
    }
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
