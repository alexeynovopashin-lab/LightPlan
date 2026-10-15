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
    /// Диск солнца (в калибровке).
    static let sunFill = Color(hex: 0xFFC24D)
    /// Метки солнца и луны — стеклянные диски (29.8в.4; до этого были кольца, 29.8в.3), диаметр, pt:
    /// «сейчас» крупнее выбранного момента.
    static let nowLensDiameter: CGFloat = 48
    static let pickedLensDiameter: CGFloat = 34
    static let moonNowDiameter: CGFloat = 40
    static let moonPickedDiameter: CGFloat = 30
    /// Тёплый оттенок стекла солнца и холодный серебристый — луны. Одним цветом ночью их не различить
    /// (в астро-ночь цвета тёмные), поэтому различает ещё и форма: у солнца лучики, у луны — фаза.
    static let sunTint = Color(hex: 0xFFC24D)
    static let moonTint = Color(hex: 0xC9D6EA)
    static let glassTintOpacity = 0.30
    /// Лучики солнца по кромке: число, просвет от края диска и длина, pt.
    static let rayCount = 8
    static let rayGap: CGFloat = 3
    static let rayLength: CGFloat = 7
    /// Внутренний отступ рисунка фазы от края стекла луны, pt.
    static let moonInset: CGFloat = 4.5
    /// Дуга луны — тоньше солнечной: обводка и жила, pt.
    static let moonArcOutlineWidth: CGFloat = 3.5
    static let moonArcWidth: CGFloat = 1.5
    /// Просвет между краем метки и подписью, pt.
    static let markerLabelGap: CGFloat = 14
    /// Малая метка восхода и заката на горизонте, диаметр, pt.
    static let eventDot: CGFloat = 8
    /// Полоса Млечного Пути и ядро: тон и непрозрачность слоёв ночью (днём — на `MilkyWayAR.ghostOpacity`).
    static let milkyWayTone = Color(hex: 0xDCE6FF)
    static let coreTone = Color(hex: 0xFFEBC2)
    /// Стрелка у края: диаметр стеклянного кружка, pt.
    static let pointerDiameter: CGFloat = 44
    /// Стекло кнопок: стандартное `.glassEffect`, но с тёмным оттенком. Над белым небом чистое стекло светлое и
    /// белый текст на нём исчезал (измерено 1,02 : 1); с оттенком — `Tools/ar_contrast.py`.
    static let buttonGlass = Glass.regular.tint(Color.black.opacity(0.7))
    /// Высота касания кнопок (HIG), pt.
    static let touch: CGFloat = 44

    /// Ширина гнущей кромки диска: у 48 pt — 7, у 30 pt — 6 (не больше пятой части диаметра).
    static func rim(for diameter: CGFloat) -> CGFloat { min(7, diameter * 0.2) }

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
