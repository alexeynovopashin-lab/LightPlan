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
    /// Оттенок стекла солнца «по умолчанию» (в калибровке и у стрелки за краем) и холодный серебристый — луны.
    /// Метка солнца на экране берёт оттенок по состоянию света (`sunDiscTint`). Солнце и луну различает не
    /// только цвет: у луны внутри фаза, у солнца под горизонтом контур пунктирный (шаг 29.8в.5).
    static let sunTint = Color(hex: 0xFFC24D)
    static let moonTint = Color(hex: 0xC9D6EA)
    static let glassTintOpacity = 0.42
    /// Призрак (светило под горизонтом): прозрачность заливки диска и контура. Контур держится заметнее заливки —
    /// пунктир читается и на тёмном небе, и на светлом.
    static let ghostFill = 0.4
    static let ghostContour = 0.85
    /// Пунктир контура призрака: штрих и просвет, pt.
    static let ghostDash: [CGFloat] = [3.5, 3]
    /// Линза диска (шаг 29.8в.5): гнущая кромка и сдвиг у самого края, pt. Одни числа у слоя Metal (кадр камеры),
    /// у `LensRefraction` (дуга и подписи под диском) и у юнит-теста.
    static let lensShift: CGFloat = 8
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

    /// Ширина гнущей кромки диска: у 48 pt — 9, у 30 pt — 7,5 (не больше четверти диаметра).
    static func rim(for diameter: CGFloat) -> CGFloat { min(9, diameter * 0.25) }

    /// Цвет состояния света на этой высоте — остановка рельса таймбара «Света» (`PathStops`), без прозрачности.
    static func stateColor(altitude: Double) -> Color {
        let c = PathStops.at(altitude).rgb
        return Color(.sRGB, red: Double(c.0) / 255, green: Double(c.1) / 255, blue: Double(c.2) / 255, opacity: 1)
    }
    /// Оттенок диска солнца на этой геометрической высоте (шаг 29.8в.5, слово Алексея 15.10: «должно переходить
    /// в рассветные/закатные цвета»). Основа — остановки рельса «Света» (`PathStops`), те же, что красят дугу в
    /// этой точке; цвет меняется непрерывно по высоте, а значит и по ручке таймбара.
    ///
    /// Две поправки поверх таблицы, обе по слову задачи: (1) выше золотого часа таблица идёт в серо-бежевый
    /// (138, 132, 120) — оттенок рельса, а не солнца; диск плавно уходит от янтаря к светло-жёлтому между 6° и 30°;
    /// (2) у самого горизонта — красно-оранжевая примесь («закат — красно-оранжевый»), пик у −0,8° (центр диска
    /// на горизонте, когда виден край), ширина ±3°. Ниже горизонта — таблица как есть: розово-синий −4…−6°,
    /// тёмно-синий −12…−18°.
    static func sunDiscRGB(altitude: Double) -> (r: Double, g: Double, b: Double) {
        let stop = PathStops.at(altitude).rgb
        var c = (r: Double(stop.0), g: Double(stop.1), b: Double(stop.2))
        func mix(_ to: (Double, Double, Double), _ k: Double) {
            c = (c.r + (to.0 - c.r) * k, c.g + (to.1 - c.g) * k, c.b + (to.2 - c.b) * k)
        }
        // Выше золотого часа: янтарь → светло-жёлтый, гладкая ступенька (3t² − 2t³).
        let t = min(1, max(0, (altitude - 6) / (30 - 6)))
        mix((255, 233, 160), t * t * (3 - 2 * t))
        // Красно-оранжевый у горизонта: треугольник с пиком 0,55 у −0,8°.
        let tri = max(0, 1 - abs(altitude + 0.8) / 3)
        mix((232, 98, 52), 0.55 * tri)
        return (c.r / 255, c.g / 255, c.b / 255)
    }

    static func sunDiscTint(altitude: Double) -> Color {
        let c = sunDiscRGB(altitude: altitude)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
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
