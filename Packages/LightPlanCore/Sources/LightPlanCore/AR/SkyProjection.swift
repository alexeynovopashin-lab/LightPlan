import Foundation

/// Проекция направления на небе (азимут, высота) в точку экрана камеры — слой AR (шаг 29.8в).
///
/// Чистая математика: ни камеры, ни датчиков, ни UIKit. Телефон отдаёт поворот, камера — поле зрения, экран —
/// размер; здесь из них получается «куда на экране попадает солнце». Всё проверяется юнит-тестами без устройства
/// (`SkyProjectionTests`): на телефоне остаётся проверить только сами датчики.
///
/// Система осей — «восток, север, вверх» (ENU), правая. Азимут — от истинного севера по часовой стрелке, как
/// у всего приложения (`HorizontalPoint`, `SolarDay.azimuth`).

/// Вектор в осях «восток, север, вверх».
public struct SkyVector: Sendable, Equatable {
    public let east: Double
    public let north: Double
    public let up: Double

    public init(east: Double, north: Double, up: Double) {
        self.east = east
        self.north = north
        self.up = up
    }

    /// Единичный вектор на точку неба.
    public init(azimuth: Degrees, altitude: Degrees) {
        let a = azimuth * Double.pi / 180
        let h = altitude * Double.pi / 180
        self.init(east: cos(h) * sin(a), north: cos(h) * cos(a), up: sin(h))
    }

    public func dot(_ o: SkyVector) -> Double { east * o.east + north * o.north + up * o.up }

    public func cross(_ o: SkyVector) -> SkyVector {
        SkyVector(east: north * o.up - up * o.north,
                  north: up * o.east - east * o.up,
                  up: east * o.north - north * o.east)
    }

    /// Азимут `[0, 360)` и высота этого направления.
    public var horizontal: HorizontalPoint {
        let az = atan2(east, north) * 180 / Double.pi
        let alt = atan2(up, (east * east + north * north).squareRoot()) * 180 / Double.pi
        return HorizontalPoint(altitude: alt, azimuth: (az + 360).truncatingRemainder(dividingBy: 360))
    }
}

/// Поворот телефона из `CMDeviceMotion.attitude.rotationMatrix` при системе отсчёта `xTrueNorthZVertical`:
/// Z — вертикаль вверх, X — истинный север, Y — запад. Девять чисел той же раскладки, что у `CMRotationMatrix`
/// (`mRC`: строка R, столбец C); матрица переводит вектор из системы отсчёта в систему устройства.
public struct DeviceRotation: Sendable, Equatable {
    public let m11, m12, m13: Double
    public let m21, m22, m23: Double
    public let m31, m32, m33: Double

    public init(m11: Double, m12: Double, m13: Double,
                m21: Double, m22: Double, m23: Double,
                m31: Double, m32: Double, m33: Double) {
        self.m11 = m11; self.m12 = m12; self.m13 = m13
        self.m21 = m21; self.m22 = m22; self.m23 = m23
        self.m31 = m31; self.m32 = m32; self.m33 = m33
    }
}

/// Три оси задней камеры телефона в осях «восток, север, вверх»: куда она смотрит, где у кадра право и верх.
public struct CameraBasis: Sendable, Equatable {
    public let forward: SkyVector
    public let right: SkyVector
    public let up: SkyVector

    public init(forward: SkyVector, right: SkyVector, up: SkyVector) {
        self.forward = forward
        self.right = right
        self.up = up
    }

    /// Камера смотрит в `azimuth`/`altitude`; `roll` — наклон кадра по часовой стрелке (градусы, глазами
    /// наблюдателя): положительный — верх кадра уходит вправо. Без наклона правый край кадра — на горизонте.
    public init(azimuth: Degrees, altitude: Degrees, roll: Degrees = 0) {
        let f = SkyVector(azimuth: azimuth, altitude: altitude)
        let a = azimuth * Double.pi / 180
        // Правый край кадра при нулевом крене всегда лежит в горизонтальной плоскости.
        let r0 = SkyVector(east: cos(a), north: -sin(a), up: 0)
        let u0 = r0.cross(f)
        let c = cos(roll * Double.pi / 180), s = sin(roll * Double.pi / 180)
        forward = f
        right = SkyVector(east: r0.east * c - u0.east * s, north: r0.north * c - u0.north * s,
                          up: r0.up * c - u0.up * s)
        up = SkyVector(east: u0.east * c + r0.east * s, north: u0.north * c + r0.north * s,
                       up: u0.up * c + r0.up * s)
    }

    /// Из поворота телефона. Телефон в портрете, задняя камера смотрит вдоль `−Z` устройства; ось `x`
    /// устройства — вправо по экрану, `y` — вверх. Столбцы транспонированной матрицы дают эти оси в системе
    /// отсчёта (X — север, Y — запад, Z — вверх), затем она переводится в «восток, север, вверх».
    public init(rotation m: DeviceRotation) {
        func enu(_ x: Double, _ y: Double, _ z: Double) -> SkyVector {
            SkyVector(east: -y, north: x, up: z)
        }
        forward = enu(-m.m31, -m.m32, -m.m33)
        right = enu(m.m11, m.m12, m.m13)
        up = enu(m.m21, m.m22, m.m23)
    }

    /// Куда смотрит камера.
    public var aim: HorizontalPoint { forward.horizontal }
}

/// Оптика камеры: поле зрения вдоль длинной стороны кадра и отношение сторон кадра.
/// `AVCaptureDevice.activeFormat.videoFieldOfView` отдаёт поле зрения именно по длинной стороне сенсора,
/// ориентированного в альбом; в портрете она идёт по высоте экрана.
public struct CameraOptics: Sendable, Equatable {
    /// Градусы, `0 < … < 180`.
    public let longSideFOV: Degrees
    /// Длинная сторона кадра, делённая на короткую (4 : 3 → 1,333).
    public let aspect: Double

    public init(longSideFOV: Degrees, aspect: Double) {
        self.longSideFOV = longSideFOV
        self.aspect = aspect
    }

    /// Типичная основная камера iPhone в кадре 4 : 3. Берётся, пока настоящей камеры нет (симулятор, отказ):
    /// дуга рисуется по ней, и размер маркера на глаз правдоподобен.
    public static let typical = CameraOptics(longSideFOV: 65, aspect: 4.0 / 3.0)
}

/// Окно, в которое камера показана, в точках. Кадр заполняет его целиком (`resizeAspectFill`), лишнее срезано.
public struct ScreenViewport: Sendable, Equatable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct ScreenPoint: Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum SkyProjection {
    /// Глубина (косинус угла от оси камеры), меньше которой точку не рисуем: на 87° от оси она уезжает на
    /// 19 фокусных расстояний, и дуга от неё — длинная прямая через весь экран.
    public static let minDepth = 0.05

    /// Фокусное расстояние в точках экрана. Кадр, заполняя окно, не меньше окна по обеим осям: масштаб — большее из
    /// «окно по ширине / короткая сторона кадра» и «окно по высоте / длинная».
    public static func focalLength(optics: CameraOptics, viewport: ScreenViewport) -> Double {
        let long = optics.aspect, short = 1.0
        let scale = max(viewport.width / short, viewport.height / long)
        // Длинная сторона кадра в точках = long·scale; она видна под углом longSideFOV.
        return (long * scale / 2) / tan(optics.longSideFOV * Double.pi / 360)
    }

    /// Поле зрения, которое видно в окне, градусы: (по ширине, по высоте).
    public static func visibleFOV(optics: CameraOptics, viewport: ScreenViewport) -> (horizontal: Degrees, vertical: Degrees) {
        let f = focalLength(optics: optics, viewport: viewport)
        let h = 2 * atan(viewport.width / (2 * f)) * 180 / Double.pi
        let v = 2 * atan(viewport.height / (2 * f)) * 180 / Double.pi
        return (h, v)
    }

    /// Точка окна, в которую попадает направление `azimuth`/`altitude`. `nil` — за камерой или слишком
    /// близко к её плоскости: не рисовать. Точка может лежать и за краями окна — решает тот, кто рисует.
    public static func project(azimuth: Degrees, altitude: Degrees, basis: CameraBasis,
                               optics: CameraOptics, viewport: ScreenViewport) -> ScreenPoint? {
        let target = SkyVector(azimuth: azimuth, altitude: altitude)
        let depth = target.dot(basis.forward)
        guard depth > minDepth else { return nil }
        let f = focalLength(optics: optics, viewport: viewport)
        let x = viewport.width / 2 + f * target.dot(basis.right) / depth
        let y = viewport.height / 2 - f * target.dot(basis.up) / depth
        return ScreenPoint(x: x, y: y)
    }
}
