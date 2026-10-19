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
    /// Слово «Сейчас» в таймбаре AR: латунь `brassSoft` (`--brass-soft` веба, тёмная #D9AC6B) вместо `brassDeep`. Панель
    /// лежит на тёмном стекле над любым небом (его яркость под словом 0,056 над белым небом и 0,036 над голубым), а
    /// `brassDeep` держала на нём 3,26 и 4,01 к 1; у этого оттенка 4,7 и 5,8 (цель 4,5 для мелкого текста).
    static let nowTone = Color(hex: 0xD9AC6B)
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
    /// Оттенок системного стекла диска (`SunARSystemGlassMark`, шаг 29.8в.9а): та же доля, что у налёта своего.
    static let systemGlassTint = 0.42
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
    /// Радиус пятна ядра Млечного Пути для проверки «виден целиком» у стрелки: условный (у ядра нет рамки диска,
    /// замера нет).
    static let coreGlyphRadius: CGFloat = 13
    /// Стрелка у края: диаметр стеклянного кружка, pt.
    static let pointerDiameter: CGFloat = 44
    /// Вид кнопок AR: стекло и тень значка (`SunARButtonLook`; выбран замером `Tools/ar_contrast.py`).
    static let look = SunARButtonLook.current
    static var buttonGlass: Glass { look.glass }
    /// Чернила значков и подписей кнопок AR.
    static var buttonInk: Color { look.inkColor }
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

    // MARK: Насыщенность диска (шаг 29.8в.6)

    // Слово Алексея 17.10: «слабая насыщенность солнечного маркера, на закате и перед закатом, он не сильно меняет
    // оттенок». Замер 17.10 (`Tools/ar_disc_sat.py`, сплошной фон, камера на солнце): налёт 0,42 с обычным
    // смешиванием разбеливается фоном — золотой час +3° (насыщенность цвета 0,66) стоял на белом 0,24, на сером
    // 0,34, на чёрном 0,55; синий час −5° (цвет 0,27) — 0,12 / 0,15 / 0,23. Сверху белый налёт 0,07 и затухание
    // призрака ×0,4 на всё сразу. Теперь диск — окрашенное стекло: слой «умножение» цветом света (на любом сером
    // фоне это тот же цвет, только темнее, насыщенность не теряется) и обычный налёт поверх, чтобы диск был виден
    // и на чёрном. Белого налёта у солнца нет: на чёрном он снимал ≈0,1 насыщенности.

    /// Непрозрачность слоя «умножение» у диска солнца (у луны слоя нет). У призрака она умножается на затухание
    /// (`SunARMarks.ghostFade`): слой «умножение» лежит вне группы затухания и без этого затемнял кадр под призраком
    /// так же, как под обычным солнцем (замер 17.10: яркость внутри диска / вне на белом — золотой час 0,67, призрак
    /// −12° 0,41, −20° 0,24; ревью GPT к f18b07f).
    static let sunMultiply = 1.0
    static func sunMultiplyOpacity(fade: Double) -> Double { sunMultiply * fade }
    /// Белый налёт стекла: у луны прежний, у солнца нет.
    static let moonVeil = 0.07
    static let sunVeil = 0.0

    /// Нижняя граница насыщенности цвета стекла по высоте солнца, узлы (высота → граница), между ними линейно.
    /// Ниже золотого часа таблица «Света» бледна (синий час −5° — 0,27), и цвет того же тона доводится до границы;
    /// от −1° и выше таблица сама насыщеннее, поправка молчит. Днём границы нет: диск остаётся светло-жёлтым.
    static let glassSaturationKnots: [(altitude: Double, floor: Double)] = [
        (-30, 0.42), (-4, 0.42), (-1.2, 0.55), (-1, 0.55), (0, 0),
    ]
    /// Полуширина сглаживания таблицы по высоте, градусы. Рельс «Света» ломается у −4° («перелом к синему»: за 2°
    /// красно-розовый становится синим), а поднятая насыщенность умножает этот излом: без сглаживания канал за
    /// минуту суток уходил на 10,9 из 255, со сглаживанием — меньше 8 (тест `glassTintIsContinuous`).
    static let glassSmoothing = 1.0

    static func glassSaturationFloor(altitude: Double) -> Double {
        let k = glassSaturationKnots
        if altitude <= k[0].altitude { return k[0].floor }
        for i in 1..<k.count where altitude <= k[i].altitude {
            let (lo, hi) = (k[i - 1], k[i])
            return lo.floor + (hi.floor - lo.floor) * (altitude - lo.altitude) / (hi.altitude - lo.altitude)
        }
        return 0
    }

    /// Цвет стекла солнца на этой геометрической высоте: цвет света (`sunDiscRGB`), усреднённый по высоте на
    /// ±`glassSmoothing`, и поднятая до `glassSaturationFloor` насыщенность — тон и яркость те же (HSV).
    static func sunGlassRGB(altitude: Double) -> (r: Double, g: Double, b: Double) {
        let n = 9
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        for i in 0..<n {
            let c = sunDiscRGB(altitude: altitude + glassSmoothing * (2 * Double(i) / Double(n - 1) - 1))
            sum = (sum.r + c.r, sum.g + c.g, sum.b + c.b)
        }
        let c = (r: sum.r / Double(n), g: sum.g / Double(n), b: sum.b / Double(n))
        let v = max(c.r, c.g, c.b)
        let s = v == 0 ? 0 : (v - min(c.r, c.g, c.b)) / v
        let want = glassSaturationFloor(altitude: altitude)
        guard s > 0, want > s else { return c }
        // Насыщенность растёт, тон и яркость v стоят: расстояние канала до v умножается на want / s.
        let k = want / s
        func lift(_ x: Double) -> Double { min(1, max(0, v - (v - x) * k)) }
        return (lift(c.r), lift(c.g), lift(c.b))
    }

    /// Цвет слоя «умножение». У обычного солнца — цвет стекла. У призрака тот же тон, но чистый (V = 1, S = 1): при
    /// множителе 0,4 такой слой даёт насыщенность 0,40 (тон по таблице тот же), а затемняет кадр на ≈ 0,3 вместо
    /// ≈ 0,6 (вариант «чистый тон ×0,4», решение 17.10). Без «чистоты» множитель 0,4 давал насыщенность 0,17.
    static func sunMultiplyRGB(altitude: Double, fade: Double) -> (r: Double, g: Double, b: Double) {
        let c = sunGlassRGB(altitude: altitude)
        guard fade < 1 else { return c }
        let v = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        guard v > mn else { return (1, 1, 1) }
        // Тон (HSV) тот же, насыщенность и яркость — предельные: канал максимума → 1, минимума → 0.
        func pure(_ x: Double) -> Double { (x - mn) / (v - mn) }
        return (pure(c.r), pure(c.g), pure(c.b))
    }

    static func sunMultiplyTint(altitude: Double, fade: Double) -> Color {
        let c = sunMultiplyRGB(altitude: altitude, fade: fade)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }

    static func sunGlassTint(altitude: Double) -> Color {
        let c = sunGlassRGB(altitude: altitude)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }

    /// Цвет диска солнца на сером фоне яркости `backdrop` (канал 0…1) — тот же рецепт слоёв, что рисует `LensGlass`:
    /// «умножение» цветом, затем налёт `glassTintOpacity` и белый налёт под общим затуханием призрака `fade`.
    /// Для юнит-теста: на экране то же самое меряет `Tools/ar_disc_sat.py`.
    static func sunDiscOnBackdrop(altitude: Double, fade: Double, backdrop: Double) -> (r: Double, g: Double, b: Double) {
        let t = sunGlassRGB(altitude: altitude), m = sunMultiplyRGB(altitude: altitude, fade: fade)
        let k = sunMultiplyOpacity(fade: fade)
        func channel(_ tint: Double, _ multiply: Double) -> Double {
            let multiplied = backdrop * (1 - k + k * multiply)
            let tinted = multiplied * (1 - glassTintOpacity * fade) + tint * glassTintOpacity * fade
            return tinted * (1 - sunVeil * fade) + sunVeil * fade
        }
        return (channel(t.r, m.r), channel(t.g, m.g), channel(t.b, m.b))
    }

    /// Насыщенность HSV: `0…1`.
    static func saturation(_ c: (r: Double, g: Double, b: Double)) -> Double {
        let mx = max(c.r, c.g, c.b)
        return mx == 0 ? 0 : (mx - min(c.r, c.g, c.b)) / mx
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
