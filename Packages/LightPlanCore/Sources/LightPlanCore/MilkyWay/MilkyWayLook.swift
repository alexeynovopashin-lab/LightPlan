import Foundation

/// Как Млечный Путь выглядит на экране AR (шаг 29.8в.14): процедурная картина полосы.
///
/// Слово Алексея 18.10: «Б я за имитацию млечного пути» — рисуем сами, по формуле, снимок неба не берём.
/// Расчётное здесь — только положение: галактические координаты точки неба получаются тем же поворотом, что у
/// `Sky.horizontal` и `MilkyWay.equatorial`, ширина — `MilkyWay.halfWidth`, ядро — точка l = 0, b = 0 (то же, что
/// `MilkyWay.core`). Яркость поперёк полосы, выпуклость ядра, цвет, зерно звёзд и прожилки пыли — имитация вида:
/// формулы ниже (гладкая часть) и шейдер `MilkyWaySky.metal` (зерно и пыль) её задают, небо их не измеряло.
///
/// Видимость — по правилам, которые уже есть в ядре: порог солнца дуги (−6°) и астрономическая темнота (−18°),
/// луна как у окна Млечного Пути (`MilkyWayWindow.moonBlocks`), засветка по атласу (`Glow`), дымка у горизонта
/// (`MilkyWayDust.haze`).
public enum MilkyWayLook {

    // MARK: - Поворот «горизонт → галактика»

    /// Оси галактики в осях «восток, север, вверх» в этот момент: `x` — на ядро (l = 0, b = 0), `y` — на l = 90°,
    /// `z` — на северный галактический полюс. Каждая ось — точка неба, переведённая `MilkyWay.equatorial` и
    /// `SkyFrame`, как полоса и ядро: второго расчёта неба не заводится. Поворот ортонормирован, поэтому
    /// галактические координаты направления `e` — это три скалярных произведения.
    public struct Frame: Sendable, Equatable {
        public let x: SkyVector
        public let y: SkyVector
        public let z: SkyVector

        /// Галактические координаты направления неба: l в `[0, 360)`, b в `[−90, 90]`.
        public func galactic(_ e: SkyVector) -> (l: Degrees, b: Degrees) {
            let gx = e.dot(x), gy = e.dot(y), gz = e.dot(z)
            let l = atan2(gy, gx) * 180 / Double.pi
            let b = atan2(gz, (gx * gx + gy * gy).squareRoot()) * 180 / Double.pi
            return ((l + 360).truncatingRemainder(dividingBy: 360), b)
        }
    }

    public static func frame(day: CivilDate, minutes: Minutes, in place: Place) -> Frame {
        let d = Sky.days(date: day, minutes: minutes, utcOffsetHours: place.zone.utcOffsetHours(on: day))
        let sky = SkyFrame(days: d, latitude: place.latitude, longitude: place.longitude)
        func axis(_ l: Degrees, _ b: Degrees) -> SkyVector {
            let h = sky.horizontal(j2000: MilkyWay.equatorial(galacticLongitude: l, galacticLatitude: b))
            return SkyVector(azimuth: h.azimuth, altitude: h.altitude)
        }
        return Frame(x: axis(0, 0), y: axis(90, 0), z: axis(0, 90))
    }

    /// Луч из точки окна в осях «восток, север, вверх», не нормированный: `P · (x, y, 1)`. Обратное к
    /// `SkyProjection.project`: `x = w/2 + f·(e·right)/(e·forward)`, `y = h/2 − f·(e·up)/(e·forward)`.
    /// Девять чисел по строкам (строка — восток, север, вверх; столбец — множитель при x, y, 1).
    public static func pixelToSky(basis: CameraBasis, optics: CameraOptics, viewport: ScreenViewport) -> [Double] {
        let f = SkyProjection.focalLength(optics: optics, viewport: viewport)
        let cx = viewport.width / 2, cy = viewport.height / 2
        let r = basis.right, u = basis.up, fw = basis.forward
        func row(_ k: KeyPath<SkyVector, Double>) -> [Double] {
            [r[keyPath: k] / f, -u[keyPath: k] / f, fw[keyPath: k] - cx / f * r[keyPath: k] + cy / f * u[keyPath: k]]
        }
        return row(\.east) + row(\.north) + row(\.up)
    }

    /// Направление неба в точке окна.
    public static func sky(at p: ScreenPoint, matrix m: [Double]) -> SkyVector {
        let e = SkyVector(east: m[0] * p.x + m[1] * p.y + m[2],
                          north: m[3] * p.x + m[4] * p.y + m[5],
                          up: m[6] * p.x + m[7] * p.y + m[8])
        let n = e.dot(e).squareRoot()
        return SkyVector(east: e.east / n, north: e.north / n, up: e.up / n)
    }

    // MARK: - Гладкая яркость (то, что меряется по кадру)

    /// Угол от ядра по долготе, `[0, 180]`.
    public static func fromCore(_ l: Degrees) -> Degrees {
        abs(((l + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) - 180)
    }

    /// Ширина гауссова профиля по b. Край полосы `MilkyWay.halfWidth` — полуширина на половине яркости:
    /// σ = halfWidth / √(2 ln 2). У ядра 9,8°, у антицентра 2,5°.
    public static func sigma(_ l: Degrees) -> Degrees {
        MilkyWay.halfWidth(galacticLongitude: l) / (2 * log(2.0)).squareRoot()
    }

    /// Яркость по долготе: та же, что у облака точек прибора (`MilkyWayDust`, 0,35 + 0,65·cos(Δl/2)).
    public static func along(_ l: Degrees) -> Double {
        0.35 + 0.65 * cos(fromCore(l) * Double.pi / 360)
    }

    /// Выпуклость ядра: эллипс σ 7° по долготе и 5° по широте, сверх полосы.
    public static let bulgeAmplitude = 0.75
    public static let bulgeSigmaL: Degrees = 7
    public static let bulgeSigmaB: Degrees = 5

    /// Гладкая яркость `0…1` (1 — ядро): полоса и выпуклость, без зерна и пыли. Её же считает шейдер.
    public static func smooth(l: Degrees, b: Degrees) -> Double {
        let s = sigma(l), dl = fromCore(l)
        let band = along(l) * exp(-b * b / (2 * s * s))
        let bulge = bulgeAmplitude * exp(-dl * dl / (2 * bulgeSigmaL * bulgeSigmaL) - b * b / (2 * bulgeSigmaB * bulgeSigmaB))
        return (band + bulge) / (1 + bulgeAmplitude)
    }

    /// Непрозрачность света полосы при яркости 1 и полной видимости (свет складывается с небом кадра).
    public static let peakAlpha = 0.55

    // MARK: - Видимость

    public enum Hidden: String, Sendable {
        /// Солнце выше −6°: небо светлое.
        case daylight
        /// Луна над горизонтом и освещена больше чем на 40 % — правило окна Млечного Пути.
        case moon
        /// Засветка выше 27 (атлас): «дальше пусто», ступень `Glow.Level.none`.
        case glow
    }

    public struct Visibility: Sendable, Equatable {
        /// Множитель яркости `0…1`.
        public let factor: Double
        /// Почему не видно; `nil` — видно (хотя бы слабо).
        public let hidden: Hidden?
        public var isVisible: Bool { factor > 0 }
    }

    /// Ниже этой высоты солнца небо по-настоящему тёмное (как у окна Млечного Пути).
    public static let darkFrom: Degrees = -18

    /// Сумерки: солнце выше −6° (порог дуги `SunTrack.visibleFrom`) — ноль; до −18° яркость растёт плавно
    /// (кубическая ступень), ниже — полная.
    public static func twilight(sunAltitude h: Degrees) -> Double {
        let top = SunTrack.visibleFrom
        if h >= top { return 0 }
        if h <= darkFrom { return 1 }
        let t = (top - h) / (top - darkFrom)
        return t * t * (3 - 2 * t)
    }

    /// Засветка: зарево `ratio` в долях природного фона, фон становится `1 + ratio` — контраст полосы делится на
    /// него. Ступень `Glow.Level.none` («дальше пусто») — ноль. `nil` — атлас молчит (офлайн, вне атласа): не знаем,
    /// яркость не трогаем.
    public static func glowFactor(_ ratio: Double?) -> Double {
        guard let ratio else { return 1 }
        if Glow.level(ratio) == Glow.Level.none { return 0 }
        return 1 / (1 + ratio)
    }

    public static func visibility(sunAltitude: Degrees, moonAltitude: Degrees, moonFraction: Double,
                                  glow: Double?) -> Visibility {
        let tw = twilight(sunAltitude: sunAltitude)
        if tw <= 0 { return Visibility(factor: 0, hidden: .daylight) }
        if MilkyWayWindow.moonBlocks(altitude: moonAltitude, fraction: moonFraction) {
            return Visibility(factor: 0, hidden: .moon)
        }
        let g = glowFactor(glow)
        if g <= 0 { return Visibility(factor: 0, hidden: .glow) }
        return Visibility(factor: tw * g, hidden: nil)
    }

    /// Дымка у горизонта: под горизонтом нуль, от 0 до `MilkyWayDust.haze` градусов — плавный рост.
    public static func horizonFade(altitude: Degrees) -> Double {
        if altitude <= 0 { return 0 }
        if altitude >= MilkyWayDust.haze { return 1 }
        let t = altitude / MilkyWayDust.haze
        return t * t * (3 - 2 * t)
    }

    // MARK: - Полоса для планирования (29.8в.17б)

    /// Полоса и подпись «ядро» рисуются всегда, пока слой включён: день, город, Луна — всё равно. Слово Алексея
    /// 20.10: «Я должен выехать на точку, днем, поставить телефон на штатив, заранее замерить положение». Правила
    /// видимости (солнце, засветка, Луна, дымка) гасят только реалистичную часть — зерно звёзд и пыль, — а не саму
    /// полосу: яркость гладкой полосы постоянна (`peakAlpha`), она не умножается на `Visibility.factor`.
    ///
    /// Светлая заливка добавляется к кадру (`plusLighter`) и на белом небе незаметна, поэтому по краям полосы,
    /// на `|b| = MilkyWay.halfWidth`, идёт тёмный контур — как чёрная обводка у дуги солнца: на светлом фоне читается он,
    /// на тёмном — заливка. Это временное решение до отрисовки картой реальных звёзд (шаг 29.8в.18).
    public static let edgeOpacity = 0.6
    /// Толщина контура по краям полосы, pt экрана.
    public static let edgeWidth = 1.5

    /// Справка о видимости глазом: число и причины словами (строка списка «Слоёв»). Те же правила, что у картины:
    /// солнце (`twilight`), луна (`MilkyWayWindow.moonBlocks`), засветка атласа (`glowFactor`), дымка у горизонта
    /// (`horizonFade` на высоте ядра). Справка, а не условие рисования.
    public struct EyeNote: Sendable, Equatable {
        public enum Cause: Sendable, Equatable {
            /// Солнце выше −6°: небо светлое.
            case daylight(sun: Degrees)
            /// Сумерки: солнце между −6° и −18°.
            case twilight(sun: Degrees)
            /// Луна над горизонтом, освещена больше чем на 40 %.
            case moon(percent: Int)
            /// Засветка атласа: ступень и число (`ratio`); ступень `none` — «дальше пусто», ноль.
            case glow(Glow.Level, value: Double)
            /// Ядро ниже 8°: дымка у горизонта.
            case haze
            /// Ядро под горизонтом.
            case belowHorizon
        }
        /// Видимость глазом, `0…100`.
        public let percent: Int
        public let causes: [Cause]
    }

    public static func eyeNote(sunAltitude: Degrees, moonAltitude: Degrees, moonFraction: Double, glow: Double?,
                               coreAltitude: Degrees) -> EyeNote {
        if twilight(sunAltitude: sunAltitude) <= 0 {
            return EyeNote(percent: 0, causes: [.daylight(sun: sunAltitude)])
        }
        if MilkyWayWindow.moonBlocks(altitude: moonAltitude, fraction: moonFraction) {
            return EyeNote(percent: 0, causes: [.moon(percent: Int((moonFraction * 100).rounded()))])
        }
        var causes: [EyeNote.Cause] = []
        let tw = twilight(sunAltitude: sunAltitude)
        if tw < 1 { causes.append(.twilight(sun: sunAltitude)) }
        if let glow, let level = Glow.level(glow) {
            if level == Glow.Level.none { return EyeNote(percent: 0, causes: [.glow(level, value: glow)]) }
            causes.append(.glow(level, value: glow))
        }
        let horizon = horizonFade(altitude: coreAltitude)
        if coreAltitude <= 0 { causes.append(.belowHorizon) } else if horizon < 1 { causes.append(.haze) }
        let factor = tw * glowFactor(glow) * horizon
        return EyeNote(percent: Int((factor * 100).rounded()), causes: causes)
    }
}
