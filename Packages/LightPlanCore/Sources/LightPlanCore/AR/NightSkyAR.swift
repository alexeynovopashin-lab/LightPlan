import Foundation

/// Луна и Млечный Путь в слое AR (шаг 29.8в.4). Своих расчётов неба здесь нет: положение и фаза луны —
/// `MoonSample` / `MoonPhase`, ядро и полоса — `MilkyWay`; ниже только то, чего ядру не хватало слою AR:
/// суточная дуга луны шагом дуги солнца, наклон освещённой кромки на экране, контур освещённой части диска,
/// полоса в точках экрана и стрелка к светилу за краем кадра.

// MARK: - Луна

/// Луна в один момент по часам места: положение (`MoonSample`) и, по требованию, фаза.
public struct MoonARSample: Sendable, Equatable {
    /// Минуты от полуночи по часам места.
    public let minutes: Minutes
    public let moon: MoonSample

    public init(minutes: Minutes, moon: MoonSample) {
        self.minutes = minutes
        self.moon = moon
    }

    public var azimuth: Degrees { moon.azimuth }
    /// Геометрическая высота.
    public var altitude: Degrees { moon.altitude }
    /// Видимая высота: добавка рефракции та же, что у солнца (`SunTrack.apparent`).
    public var apparentAltitude: Degrees { SunTrack.apparent(altitude: moon.altitude) }
    /// Освещённая доля и положение в цикле — `MoonPhase` ядра.
    public var phase: MoonPhase { moon.phase }
    /// Под горизонтом луна идёт призраком, а не исчезает (правило «светило не исчезает»).
    public var isGhost: Bool { moon.altitude < 0 }
}

public enum MoonTrack {
    public static func sample(day: CivilDate, minutes: Minutes, in place: Place) -> MoonARSample {
        MoonARSample(minutes: minutes, moon: MoonSample(date: day, minutes: minutes, place: place))
    }

    public static func sample(at moment: Moment, in place: Place) -> MoonARSample {
        let wall = SunTrack.wallClock(of: moment, in: place)
        return sample(day: wall.day, minutes: wall.minutes, in: place)
    }

    /// Дуга суток луны: точки через `step` минут от полуночи до полуночи по часам места, как у дуги солнца.
    /// Смещение пояса берётся один раз на сутки: сотни точек на одну дату.
    public static func arc(day: CivilDate, in place: Place, step: Minutes = SunTrack.arcStep) -> [MoonARSample] {
        let offset = place.zone.utcOffsetHours(on: day)
        var out: [MoonARSample] = []
        var t = 0.0
        while t <= 1440 + 1e-9 {
            let moon = MoonSample(date: day, minutes: t, latitude: place.latitude, longitude: place.longitude,
                                  utcOffsetHours: offset)
            out.append(MoonARSample(minutes: t, moon: moon))
            t += step
        }
        return out
    }
}

public enum MoonLimb {
    /// Куда на экране смотрит светлая кромка луны: направление от луны к солнцу, радианы в обычной математической
    /// оси экрана (0 — вправо, π/2 — вверх). Освещённая сторона луны всегда обращена к солнцу, поэтому по этому
    /// направлению и ставится рисунок фазы; от наклона кадра, широты и часа он не зависит иначе, чем само небо.
    /// `nil` — солнце и луна в одной точке или в противоположных: направления нет.
    ///
    /// Направление берётся в касательной плоскости к небу у луны и переводится в экран маленьким шагом (так
    /// учтена перспектива у края кадра); если шаг не ложится на экран — по осям камеры.
    public static func brightLimbAngle(moon: HorizontalPoint, sun: HorizontalPoint, basis: CameraBasis,
                                       optics: CameraOptics, viewport: ScreenViewport) -> Double? {
        let m = SkyVector(azimuth: moon.azimuth, altitude: moon.altitude)
        let s = SkyVector(azimuth: sun.azimuth, altitude: sun.altitude)
        let k = s.dot(m)
        let t = SkyVector(east: s.east - m.east * k, north: s.north - m.north * k, up: s.up - m.up * k)
        let len = t.dot(t).squareRoot()
        guard len > 1e-6 else { return nil }
        let u = SkyVector(east: t.east / len, north: t.north / len, up: t.up / len)
        // Шаг в 1°: достаточно мал, чтобы быть касательной, и достаточно велик, чтобы разность не потерялась.
        let e = 1.0 * Double.pi / 180
        let moved = SkyVector(east: m.east * cos(e) + u.east * sin(e), north: m.north * cos(e) + u.north * sin(e),
                              up: m.up * cos(e) + u.up * sin(e)).horizontal
        if let p0 = SkyProjection.project(azimuth: moon.azimuth, altitude: moon.altitude, basis: basis,
                                          optics: optics, viewport: viewport),
           let p1 = SkyProjection.project(azimuth: moved.azimuth, altitude: moved.altitude, basis: basis,
                                          optics: optics, viewport: viewport) {
            let dx = p1.x - p0.x, dy = p1.y - p0.y
            if dx * dx + dy * dy > 1e-12 { return atan2(-dy, dx) }
        }
        let x = u.dot(basis.right), y = u.dot(basis.up)
        guard x * x + y * y > 1e-12 else { return nil }
        return atan2(y, x)
    }
}

public enum MoonDisc {
    /// Освещённая часть диска единичного радиуса: ось `+x` смотрит на солнце, `y` вниз, центр в нуле. Контур
    /// замкнут: правая дуга сверху вниз, терминатор снизу вверх. Новолуние (доля < 1 %) — пустой контур: рисующий
    /// оставляет тонкий контур диска, а не пустоту.
    ///
    /// Терминатор — половина эллипса с горизонтальной полуосью `|1 − 2f|`: у четверти он прямой, у серпа
    /// выгнут к кромке, у «почти полной» уходит за центр.
    public static func litOutline(fraction f: Double, steps: Int = 32) -> [ScreenPoint] {
        guard f >= 0.01 else { return [] }
        let t = 1 - 2 * min(1, max(0, f))
        var out: [ScreenPoint] = []
        for i in 0...steps {
            let phi = Double.pi * Double(i) / Double(steps)
            out.append(ScreenPoint(x: sin(phi), y: -cos(phi)))
        }
        for i in 0...steps {
            let phi = Double.pi - Double.pi * Double(i) / Double(steps)
            out.append(ScreenPoint(x: t * sin(phi), y: -cos(phi)))
        }
        return out
    }
}

// MARK: - Млечный Путь

public enum MilkyWayAR {
    /// Край полосы в точке: левый и правый края — линии галактической широты ±полуширина, перевод в экваториальные
    /// координаты — `MilkyWay.equatorial`. Константы неба, считаются один раз.
    private static let edges: [(left: EquatorialPoint, right: EquatorialPoint)] = MilkyWay.band.map { p in
        (MilkyWay.equatorial(galacticLongitude: p.longitude, galacticLatitude: p.halfWidth),
         MilkyWay.equatorial(galacticLongitude: p.longitude, galacticLatitude: -p.halfWidth))
    }

    /// Полоса над головой в этот момент: края по точкам `MilkyWay.band` (121 точка шагом 3°).
    public static func band(day: CivilDate, minutes: Minutes, in place: Place) -> [(left: HorizontalPoint, right: HorizontalPoint)] {
        let d = Sky.days(date: day, minutes: minutes, utcOffsetHours: place.zone.utcOffsetHours(on: day))
        return edges.map { e in
            (Sky.horizontal(e.left, days: d, latitude: place.latitude, longitude: place.longitude),
             Sky.horizontal(e.right, days: d, latitude: place.latitude, longitude: place.longitude))
        }
    }

    /// Середина полосы над головой: точки `MilkyWay.band` (b = 0) через `Sky.horizontal`.
    public static func center(day: CivilDate, minutes: Minutes, in place: Place) -> [HorizontalPoint] {
        let d = Sky.days(date: day, minutes: minutes, utcOffsetHours: place.zone.utcOffsetHours(on: day))
        return MilkyWay.band.map { Sky.horizontal($0.center, days: d, latitude: place.latitude, longitude: place.longitude) }
    }

    /// Ядро — `MilkyWay.corePosition`, второй расчёт не заводится.
    public static func core(day: CivilDate, minutes: Minutes, in place: Place) -> HorizontalPoint {
        MilkyWay.corePosition(date: day, minutes: minutes, place: place)
    }

    /// Небо не тёмное: солнце выше −6° (видимый порог дуги солнца). Днём полоса идёт призраком.
    public static func isGhost(sunAltitude: Degrees) -> Bool { sunAltitude > SunTrack.visibleFrom }

    /// Непрозрачность полосы: ночью 1 (рисующий умножает на свой тон), днём — призрак 0,25.
    public static let ghostOpacity = 0.25
}

// MARK: - Стрелка к светилу за краем кадра

/// Прямоугольник экрана, в котором светило считается «в кадре» и где живёт стрелка: окно без полос под кнопками
/// сверху и под панелью снизу.
public struct ScreenBox: Sendable, Equatable {
    public let minX, minY, maxX, maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
    }

    public func contains(_ p: ScreenPoint) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }
}

public struct EdgePointer: Sendable, Equatable {
    /// Где на краю рамки стоит значок.
    public let point: ScreenPoint
    /// Куда смотрит стрелка на экране: радианы в оси экрана (0 — вправо, π/2 — вниз).
    public let angle: Double

    public init(point: ScreenPoint, angle: Double) {
        self.point = point
        self.angle = angle
    }
}

public enum EdgePointing {
    /// `nil` — светило в рамке: стрелка не нужна. Иначе — точка на краю рамки в сторону светила. За спиной
    /// (глубина ≤ порога проекции) направление берётся по осям камеры: куда повернуть телефон, чтобы вернуть его.
    public static func pointer(azimuth: Degrees, altitude: Degrees, basis: CameraBasis, optics: CameraOptics,
                               viewport: ScreenViewport, box: ScreenBox) -> EdgePointer? {
        let t = SkyVector(azimuth: azimuth, altitude: altitude)
        let z = t.dot(basis.forward)
        let cx = viewport.width / 2, cy = viewport.height / 2
        var dx: Double, dy: Double
        if z > SkyProjection.minDepth,
           let p = SkyProjection.project(azimuth: azimuth, altitude: altitude, basis: basis, optics: optics, viewport: viewport) {
            if box.contains(p) { return nil }
            dx = p.x - cx; dy = p.y - cy
        } else {
            dx = t.dot(basis.right); dy = -t.dot(basis.up)
            // Ровно за спиной: направления нет, стрелка смотрит вниз (повернуть телефон можно в любую сторону).
            if dx * dx + dy * dy < 1e-9 { dx = 0; dy = 1 }
        }
        // Луч из центра окна до границы рамки.
        var s = Double.infinity
        if dx > 1e-12 { s = min(s, (box.maxX - cx) / dx) } else if dx < -1e-12 { s = min(s, (box.minX - cx) / dx) }
        if dy > 1e-12 { s = min(s, (box.maxY - cy) / dy) } else if dy < -1e-12 { s = min(s, (box.minY - cy) / dy) }
        guard s.isFinite, s > 0 else { return nil }
        return EdgePointer(point: ScreenPoint(x: cx + dx * s, y: cy + dy * s), angle: atan2(dy, dx))
    }
}

// MARK: - Сцена

/// Всё, что экран AR рисует для луны и Млечного Пути, в точках окна. Чистая функция, как `SunARScene`.
/// Что выключено переключателем, во вход не подаётся — и в сцене пусто (ни расчёта, ни рисования).
public struct NightSkyARScene: Sendable, Equatable {

    public struct MoonMark: Sendable, Equatable {
        /// Центр метки; `nil` — луна за камерой.
        public let point: ScreenPoint?
        public let azimuth: Degrees
        public let altitude: Degrees
        public let illuminated: Double
        public let waxing: Bool
        /// Радианы в оси экрана (0 — вправо, π/2 — вверх): куда смотрит светлая кромка.
        public let limbAngle: Double?
        public let ghost: Bool
    }

    public struct ArcPoint: Sendable, Equatable {
        public let point: ScreenPoint
        public let isBelowHorizon: Bool
    }

    /// Луна: сутки выбранного дня, выбранный момент, «сейчас» и солнце в эти моменты (по нему ставится кромка).
    public struct MoonInput {
        public let arc: [MoonARSample]
        public let picked: MoonARSample
        public let now: MoonARSample?
        public let sunAtPicked: HorizontalPoint
        public let sunAtNow: HorizontalPoint?

        public init(arc: [MoonARSample], picked: MoonARSample, now: MoonARSample?,
                    sunAtPicked: HorizontalPoint, sunAtNow: HorizontalPoint?) {
            self.arc = arc; self.picked = picked; self.now = now
            self.sunAtPicked = sunAtPicked; self.sunAtNow = sunAtNow
        }
    }

    /// Млечный Путь: края полосы и ядро в этот момент, высота солнца — для призрака днём. Для картины полосы
    /// (29.8в.14): поворот «горизонт → галактика» (`MilkyWayLook.frame`), луна и засветка — для видимости.
    public struct MilkyWayInput {
        public let band: [(left: HorizontalPoint, right: HorizontalPoint)]
        public let core: HorizontalPoint
        public let sunAltitude: Degrees
        public let frame: MilkyWayLook.Frame?
        public let moonAltitude: Degrees
        public let moonFraction: Double
        public let glow: Double?
        /// Середина полосы (`MilkyWayAR.center`) — для проверки картины.
        public let center: [HorizontalPoint]
        /// Суточная дуга ядра выбранной даты и его восходы и заходы (29.8в.17б); `nil` — траектория не рисуется.
        public let track: CoreTrackInput?

        public init(band: [(left: HorizontalPoint, right: HorizontalPoint)], core: HorizontalPoint, sunAltitude: Degrees,
                    frame: MilkyWayLook.Frame? = nil, moonAltitude: Degrees = -90, moonFraction: Double = 0,
                    glow: Double? = nil, center: [HorizontalPoint] = [], track: CoreTrackInput? = nil) {
            self.band = band; self.core = core; self.sunAltitude = sunAltitude
            self.frame = frame; self.moonAltitude = moonAltitude; self.moonFraction = moonFraction; self.glow = glow
            self.center = center; self.track = track
        }
    }

    /// Сутки ядра: дуга точками (`MilkyWayCoreTrack.arc`) и события (`MilkyWayCoreTrack.passage`).
    public struct CoreTrackInput: Sendable, Equatable {
        public let arc: [MilkyWayCoreTrack.Sample]
        public let passage: MilkyWayCoreTrack.Passage

        public init(arc: [MilkyWayCoreTrack.Sample], passage: MilkyWayCoreTrack.Passage) {
            self.arc = arc; self.passage = passage
        }
    }

    /// Траектория ядра на экране (29.8в.17б): дуга суток, подписи часов и точки восхода и захода — как у дуги
    /// солнца и луны. Часы — только там, где ядро не ниже −6° (как часы дуги солнца).
    public struct CoreTrack: Sendable, Equatable {
        public struct Point: Sendable, Equatable {
            public let point: ScreenPoint
            public let minutes: Minutes
            /// Геометрическая высота.
            public let altitude: Degrees
            /// Видимая высота ниже линии горизонта: дуга здесь идёт пунктиром.
            public let isBelowHorizon: Bool
        }
        public struct Hour: Sendable, Equatable {
            public let hour: Int
            public let point: ScreenPoint
            public let altitude: Degrees
        }
        public struct Event: Sendable, Equatable {
            public let kind: MilkyWayCoreTrack.Event.Kind
            public let minutes: Minutes
            public let azimuth: Degrees
            /// Где точка на линии горизонта; `nil` — за камерой.
            public let point: ScreenPoint?
        }
        /// Видимая часть дуги — от верха до −18°, отрезками, разорванными за камерой.
        public let arc: [[Point]]
        public let hours: [Hour]
        public let events: [Event]
    }

    /// Картина полосы для шейдера: два поворота и видимость. Точка окна (x, y) → луч `pixelToSky · (x, y, 1)` в осях
    /// «восток, север, вверх» → галактика `frame`. `centerLine` — середина полосы (`MilkyWay.band`), спроецированная
    /// `SkyProjection` отдельно от шейдера: по ней проверяется, что картина стоит там, где считает ядро.
    public struct MilkyWayPicture: Sendable, Equatable {
        public let pixelToSky: [Double]
        public let frame: MilkyWayLook.Frame
        public let visibility: MilkyWayLook.Visibility
        public let centerLine: [ScreenPoint]
        public let focal: Double
    }

    /// Луна в выбранный момент; `nil` — луна выключена.
    public let picked: MoonMark?
    /// Луна сию минуту; `nil`, когда метки слились или луна выключена.
    public let now: MoonMark?
    /// Дуга луны выбранного дня: видимая часть, отрезками, разорванными за камерой.
    public let arc: [[ArcPoint]]
    /// Полоса Млечного Пути многоугольниками: левый край вперёд, правый назад.
    public let band: [[ScreenPoint]]
    /// Центр ядра на экране; `nil` — за камерой или Млечный Путь выключен.
    public let core: ScreenPoint?
    public let coreAzimuth: Degrees
    public let coreAltitude: Degrees
    /// Млечный Путь включён.
    public let milkyWayOn: Bool
    /// Небо светлое: полоса и ядро идут призраком.
    public let skyGhost: Bool
    /// Картина полосы; `nil` — Млечный Путь выключен или поворот не подан.
    public let milkyWayPicture: MilkyWayPicture?
    /// Траектория ядра выбранной даты; `nil` — Млечный Путь выключен или траектория не подана.
    public let coreTrack: CoreTrack?

    /// Луна ниже −18° (как дуга солнца) не рисуется.
    public static let arcFrom: Degrees = -18

    public static func make(basis: CameraBasis, optics: CameraOptics, viewport: ScreenViewport,
                            moon: MoonInput?, milkyWay: MilkyWayInput?) -> NightSkyARScene {
        func proj(_ az: Degrees, _ alt: Degrees) -> ScreenPoint? {
            SkyProjection.project(azimuth: az, altitude: alt, basis: basis, optics: optics, viewport: viewport)
        }
        func mark(_ m: MoonARSample, sun: HorizontalPoint) -> MoonMark {
            let ph = m.phase
            let visible = HorizontalPoint(altitude: m.apparentAltitude, azimuth: m.azimuth)
            return MoonMark(point: proj(m.azimuth, m.apparentAltitude), azimuth: m.azimuth, altitude: m.altitude,
                            illuminated: ph.fraction, waxing: ph.cycle < 0.5,
                            limbAngle: MoonLimb.brightLimbAngle(moon: visible, sun: sun, basis: basis, optics: optics,
                                                                viewport: viewport),
                            ghost: m.isGhost)
        }

        var segments: [[ArcPoint]] = []
        var pickedMark: MoonMark?, nowMark: MoonMark?
        if let moon {
            var run: [ArcPoint] = []
            for s in moon.arc {
                guard s.altitude >= arcFrom, let p = proj(s.azimuth, s.apparentAltitude) else {
                    if !run.isEmpty { segments.append(run); run = [] }
                    continue
                }
                run.append(ArcPoint(point: p, isBelowHorizon: s.apparentAltitude < 0))
            }
            if !run.isEmpty { segments.append(run) }
            pickedMark = mark(moon.picked, sun: moon.sunAtPicked)
            nowMark = moon.now.map { mark($0, sun: moon.sunAtNow ?? moon.sunAtPicked) }
        }

        // Полоса: подряд идущие точки, у которых оба края ложатся на экран; разрыв — новый многоугольник.
        var polys: [[ScreenPoint]] = []
        var coreOnScreen: ScreenPoint?
        var picture: MilkyWayPicture?
        var track: CoreTrack?
        if let milkyWay {
            var left: [ScreenPoint] = [], right: [ScreenPoint] = []
            func flush() {
                if left.count >= 2 { polys.append(left + right.reversed()) }
                left = []; right = []
            }
            for b in milkyWay.band {
                if let l = proj(b.left.azimuth, b.left.altitude), let r = proj(b.right.azimuth, b.right.altitude) {
                    left.append(l); right.append(r)
                } else { flush() }
            }
            flush()
            coreOnScreen = proj(milkyWay.core.azimuth, milkyWay.core.altitude)
            if let input = milkyWay.track {
                var runs: [[CoreTrack.Point]] = [], run: [CoreTrack.Point] = []
                var hours: [CoreTrack.Hour] = []
                for s in input.arc {
                    guard s.altitude >= MilkyWayCoreTrack.arcFrom, let p = proj(s.azimuth, s.apparentAltitude) else {
                        if !run.isEmpty { runs.append(run); run = [] }
                        continue
                    }
                    run.append(CoreTrack.Point(point: p, minutes: s.minutes, altitude: s.altitude,
                                               isBelowHorizon: s.apparentAltitude < 0))
                    if s.altitude >= SunTrack.visibleFrom, s.minutes.truncatingRemainder(dividingBy: 60) == 0, s.minutes < 1440 {
                        hours.append(CoreTrack.Hour(hour: Int(s.minutes / 60), point: p, altitude: s.altitude))
                    }
                }
                if !run.isEmpty { runs.append(run) }
                let events = input.passage.events.map {
                    CoreTrack.Event(kind: $0.kind, minutes: $0.minutes, azimuth: $0.azimuth, point: proj($0.azimuth, 0))
                }
                track = CoreTrack(arc: runs, hours: hours, events: events)
            }
            if let frame = milkyWay.frame {
                picture = MilkyWayPicture(
                    pixelToSky: MilkyWayLook.pixelToSky(basis: basis, optics: optics, viewport: viewport),
                    frame: frame,
                    visibility: MilkyWayLook.visibility(sunAltitude: milkyWay.sunAltitude,
                                                        moonAltitude: milkyWay.moonAltitude,
                                                        moonFraction: milkyWay.moonFraction, glow: milkyWay.glow),
                    centerLine: milkyWay.center.compactMap { proj($0.azimuth, $0.altitude) },
                    focal: SkyProjection.focalLength(optics: optics, viewport: viewport))
            }
        }
        return NightSkyARScene(picked: pickedMark, now: nowMark, arc: segments, band: polys, core: coreOnScreen,
                               coreAzimuth: milkyWay?.core.azimuth ?? 0, coreAltitude: milkyWay?.core.altitude ?? 0,
                               milkyWayOn: milkyWay != nil,
                               skyGhost: milkyWay.map { MilkyWayAR.isGhost(sunAltitude: $0.sunAltitude) } ?? false,
                               milkyWayPicture: picture, coreTrack: track)
    }
}
