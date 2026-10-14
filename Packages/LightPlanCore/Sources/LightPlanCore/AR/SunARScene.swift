import Foundation

/// Всё, что экран AR рисует поверх кадра, посчитанное в точках окна (шаг 29.8в). Чистая функция от поворота
/// телефона, оптики, размера окна и дуги — без UIKit и без датчиков, поэтому проверяется юнит-тестами:
/// где встанет маркер, где оборвётся дуга за спиной камеры, сколько подписей часов видно.
public struct SunARScene: Sendable, Equatable {

    /// Подпись часа на дуге.
    public struct Hour: Sendable, Equatable {
        public let hour: Int
        public let point: ScreenPoint
        /// Геометрическая высота солнца в этот час: ниже 0 подпись тише.
        public let altitude: Degrees
    }

    /// Сторона света на линии горизонта: 0 — С, 1 — В, 2 — Ю, 3 — З.
    public struct Cardinal: Sendable, Equatable {
        public let index: Int
        public let point: ScreenPoint
    }

    /// Линия горизонта: отрезки, разорванные там, где она уходит за камеру.
    public let horizon: [[ScreenPoint]]
    /// Видимая часть дуги (высота не ниже порога), тоже отрезками.
    public let arc: [[ScreenPoint]]
    public let hours: [Hour]
    public let cardinals: [Cardinal]
    /// Положение солнца в выбранный момент; `nil` — за камерой.
    public let marker: ScreenPoint?
    /// Солнце ниже порога видимости дуги: маркер идёт призраком, а не пропадает.
    public let markerGhost: Bool
    /// Выбранный момент — это «сейчас»: маркер один, и он же «сейчас» (метки сливаются, подпись одна).
    public let markerIsNow: Bool
    /// Солнце прямо сейчас (второй маркер); `nil` — за камерой, или метки слились, или «сейчас» не передали.
    public let nowMarker: ScreenPoint?
    public let nowGhost: Bool
    /// Многоугольник «земли» под горизонтом — для фона без камеры. `nil`, когда земли в кадре нет.
    public let ground: [ScreenPoint]?

    /// Шаг точек линии горизонта, градусы. Горизонт в центральной проекции — прямая, точек нужно мало,
    /// но разрыв за камерой ловится по ним.
    public static let horizonStep: Degrees = 5

    /// - Parameters:
    ///   - sun: солнце в выбранный момент (маркер «выбранный», дуга — этого дня).
    ///   - now: солнце сию минуту; `nil` — «сейчас» экрану не передали.
    ///   - pickedIsNow: выбранный момент равен «сейчас» — второго маркера нет, подпись одна.
    public static func make(basis: CameraBasis, optics: CameraOptics, viewport: ScreenViewport,
                            arc: [SunSample], sun: SunSample, now: SunSample? = nil,
                            pickedIsNow: Bool = false) -> SunARScene {
        func proj(_ az: Degrees, _ alt: Degrees) -> ScreenPoint? {
            SkyProjection.project(azimuth: az, altitude: alt, basis: basis, optics: optics, viewport: viewport)
        }

        // Горизонт.
        var horizon: [[ScreenPoint]] = []
        var run: [ScreenPoint] = []
        var az = 0.0
        while az <= 360 + 1e-9 {
            if let p = proj(az, 0) { run.append(p) } else if !run.isEmpty { horizon.append(run); run = [] }
            az += horizonStep
        }
        if !run.isEmpty { horizon.append(run) }

        // Дуга: высота — видимая (с рефракцией), порог — геометрический, как в приложении.
        var segments: [[ScreenPoint]] = []
        run = []
        var hours: [Hour] = []
        for s in arc {
            guard s.altitude >= SunTrack.visibleFrom, let p = proj(s.azimuth, s.apparentAltitude) else {
                if !run.isEmpty { segments.append(run); run = [] }
                continue
            }
            run.append(p)
            if s.minutes.truncatingRemainder(dividingBy: 60) == 0, s.minutes < 1440 {
                hours.append(Hour(hour: Int(s.minutes / 60), point: p, altitude: s.altitude))
            }
        }
        if !run.isEmpty { segments.append(run) }

        // Стороны света — на горизонте.
        var cardinals: [Cardinal] = []
        for (i, a) in [0.0, 90, 180, 270].enumerated() {
            if let p = proj(a, 0) { cardinals.append(Cardinal(index: i, point: p)) }
        }

        let marker = proj(sun.azimuth, sun.apparentAltitude)
        // Метка «сейчас» — отдельная, когда выбранный момент не сейчас.
        var nowMarker: ScreenPoint?
        var nowGhost = false
        if let now, !pickedIsNow {
            nowMarker = proj(now.azimuth, now.apparentAltitude)
            nowGhost = now.altitude < SunTrack.visibleFrom
        }

        return SunARScene(horizon: horizon, arc: segments, hours: hours, cardinals: cardinals,
                          marker: marker, markerGhost: sun.altitude < SunTrack.visibleFrom,
                          markerIsNow: pickedIsNow, nowMarker: nowMarker, nowGhost: nowGhost,
                          ground: groundPolygon(basis: basis, horizon: horizon, viewport: viewport))
    }

    /// Земля под горизонтом как большой четырёхугольник по сторону «вниз» от линии горизонта.
    private static func groundPolygon(basis: CameraBasis, horizon: [[ScreenPoint]], viewport: ScreenViewport) -> [ScreenPoint]? {
        guard let run = horizon.max(by: { $0.count < $1.count }), run.count >= 2 else {
            // Горизонта в кадре нет вовсе: смотрим вниз — земля на весь экран, вверх — её нет.
            return basis.forward.up < 0
                ? [ScreenPoint(x: 0, y: 0), ScreenPoint(x: viewport.width, y: 0),
                   ScreenPoint(x: viewport.width, y: viewport.height), ScreenPoint(x: 0, y: viewport.height)]
                : nil
        }
        let a = run[0], b = run[run.count - 1]
        var dx = b.x - a.x, dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 1e-9 else { return nil }
        dx /= len; dy /= len
        // «Вниз» по миру в осях экрана: x — минус вертикальная составляющая правого края кадра,
        // y — вертикальная составляющая верха кадра (на ровном кадре — прямо вниз).
        let downX = -basis.right.up, downY = basis.up.up
        // Нормаль берём перпендикулярно линии и в сторону «вниз».
        var nx = -dy, ny = dx
        if nx * downX + ny * downY < 0 { nx = -nx; ny = -ny }
        let r = 4000.0
        return [
            ScreenPoint(x: a.x - dx * r, y: a.y - dy * r),
            ScreenPoint(x: b.x + dx * r, y: b.y + dy * r),
            ScreenPoint(x: b.x + dx * r + nx * r, y: b.y + dy * r + ny * r),
            ScreenPoint(x: a.x - dx * r + nx * r, y: a.y - dy * r + ny * r),
        ]
    }
}
