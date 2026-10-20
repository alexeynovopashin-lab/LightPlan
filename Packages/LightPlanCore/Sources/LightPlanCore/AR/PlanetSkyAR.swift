import Foundation

/// Планеты в слое AR (шаг 29.8в.15). Положение — `PlanetEphemeris` (формулы Schlyter, без каталога), проекция на экран и
/// добавка рефракции те же, что у звёзд и луны (`SkyProjection`, `SunTrack.apparent`). Слой рисуется всегда, день и
/// ночь (29.8в.18, `SkyEyeNote` — справка о видимости); одно исключение: планета ближе 15° к Солнцу не рисуется вовсе.

// MARK: - Вид точки

public enum PlanetLook {
    /// Радиус точки, pt: Венера (−4,4) ≈ 4,6; Юпитер (−2,5) ≈ 3,6; Сатурн и Марс около 2; слабее — 1,6 (меньше точка
    /// теряется). Больше 5 не бывает: планета остаётся точкой, а не диском.
    public static func radius(magnitude m: Double) -> Double { min(5, max(1.6, 2.4 - 0.5 * m)) }

    /// Яркость точки `0,4 … 1`: та же кривая, что у звёзд, чтобы планета и звезда одной величины были одинаково яркими.
    public static func brightness(magnitude m: Double) -> Double { StarLook.brightness(magnitude: m) }

    /// Цвет точки: Венера почти белая, Марс красноватый, Юпитер кремовый, Сатурн бледно-жёлтый, Меркурий серый.
    public static func tint(_ planet: Planet) -> (red: Double, green: Double, blue: Double) {
        switch planet {
        case .mercury: return (0.74, 0.74, 0.76)
        case .venus: return (1.00, 0.99, 0.95)
        case .mars: return (1.00, 0.52, 0.38)
        case .jupiter: return (1.00, 0.92, 0.76)
        case .saturn: return (0.96, 0.89, 0.60)
        }
    }

    /// Ореол — у планет ярче этой величины (как у звёзд ярче 1,5: блеск читается по размеру пятна).
    public static let haloMagnitude = 1.5
}

// MARK: - Видимость

public enum PlanetVisibility {
    /// Ближе этого к Солнцу планета «в лучах»: не видна, не рисуется, в списке «Слоёв» подписана.
    public static let nearSun: Degrees = 15

    public static func isNearSun(elongation: Degrees) -> Bool { elongation < nearSun }
}

// MARK: - Расчёт и сцена

/// Планета на момент и место: то, что от поворота телефона не зависит и считается один раз на минуту.
public struct PlanetSample: Sendable, Equatable {
    public let planet: Planet
    /// Геометрические высота и азимут, без рефракции.
    public let horizontal: HorizontalPoint
    public let magnitude: Double
    /// Удаление от Солнца на небе, градусы.
    public let elongation: Degrees

    public init(planet: Planet, horizontal: HorizontalPoint, magnitude: Double, elongation: Degrees) {
        self.planet = planet; self.horizontal = horizontal; self.magnitude = magnitude; self.elongation = elongation
    }
}

public enum PlanetSkyAR {
    /// Пять планет на момент «день плюс минуты шкалы» по часам места.
    public static func samples(day: CivilDate, minutes: Minutes, in place: Place) -> [PlanetSample] {
        let d = Sky.days(date: day, minutes: minutes, utcOffsetHours: place.zone.utcOffsetHours(on: day))
        return samples(days: d, latitude: place.latitude, longitude: place.longitude)
    }

    public static func samples(days d: Double, latitude: Double, longitude: Double) -> [PlanetSample] {
        PlanetEphemeris.all(days: d).map {
            PlanetSample(planet: $0.planet,
                         horizontal: PlanetEphemeris.horizontal($0, days: d, latitude: latitude, longitude: longitude),
                         magnitude: $0.magnitude, elongation: $0.elongation)
        }
    }

    public static func make(samples: [PlanetSample], basis: CameraBasis, optics: CameraOptics,
                            viewport: ScreenViewport) -> PlanetSkyARScene {
        var dots: [PlanetSkyARScene.Dot] = []
        for s in samples where !PlanetVisibility.isNearSun(elongation: s.elongation) {
            let seen = HorizontalPoint(altitude: SunTrack.apparent(altitude: s.horizontal.altitude), azimuth: s.horizontal.azimuth)
            // Под горизонтом планета не рисуется (видимая высота, как у звёзд).
            guard seen.altitude >= 0,
                  let p = SkyProjection.project(azimuth: seen.azimuth, altitude: seen.altitude, basis: basis, optics: optics,
                                                viewport: viewport) else { continue }
            dots.append(.init(planet: s.planet, point: p, magnitude: s.magnitude,
                              radius: PlanetLook.radius(magnitude: s.magnitude),
                              brightness: PlanetLook.brightness(magnitude: s.magnitude),
                              azimuth: s.horizontal.azimuth, altitude: s.horizontal.altitude))
        }
        return PlanetSkyARScene(dots: dots,
                                nearSun: samples.filter { PlanetVisibility.isNearSun(elongation: $0.elongation) }.map(\.planet))
    }
}

/// Всё, что экран AR рисует для планет, в точках окна. Чистая функция, как `StarSkyARScene`.
public struct PlanetSkyARScene: Sendable, Equatable {
    public struct Dot: Sendable, Equatable {
        public let planet: Planet
        public let point: ScreenPoint
        public let magnitude: Double
        public let radius: Double
        /// Яркость по величине `0,4 … 1`. От солнца не зависит: слой рисуется всегда (29.8в.18).
        public let brightness: Double
        public let azimuth: Degrees
        /// Геометрическая высота.
        public let altitude: Degrees

        public init(planet: Planet, point: ScreenPoint, magnitude: Double, radius: Double, brightness: Double,
                    azimuth: Degrees, altitude: Degrees) {
            self.planet = planet; self.point = point; self.magnitude = magnitude; self.radius = radius
            self.brightness = brightness; self.azimuth = azimuth; self.altitude = altitude
        }
    }

    public let dots: [Dot]
    /// Планеты ближе 15° к Солнцу в этот момент (независимо от горизонта): список «Слоёв» подписывает каждую.
    public let nearSun: [Planet]

    public init(dots: [Dot], nearSun: [Planet]) {
        self.dots = dots; self.nearSun = nearSun
    }
}
