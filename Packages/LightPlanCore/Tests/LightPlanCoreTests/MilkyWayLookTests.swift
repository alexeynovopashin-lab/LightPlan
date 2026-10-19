import Testing
import Foundation
import LightPlanCore

/// Картина Млечного Пути в AR (шаг 29.8в.14): поворот «точка экрана → галактика» сходится с полосой и ядром ядра,
/// гладкая яркость — с формулой шага, видимость — с порогами солнца, правилом луны окна и засветкой атласа.
/// Пиксели шейдера меряет `Tools/ar_milkyway.py` по кадрам симулятора.
struct MilkyWayLookTests {

    struct Moment {
        let name: String
        let place: Place
        let day: CivilDate
        let minutes: Minutes
        /// Куда смотрит камера: на точку полосы с этой галактической долготой, выше на `lift`, с креном.
        let aimLongitude: Degrees
        let lift: Degrees
        let roll: Degrees
    }

    /// Пять моментов: широты от −34° до +64°, разные часы, курсы и крен кадра (те же, что у `ar_milkyway.py`).
    static let moments: [Moment] = [
        Moment(name: "Сочи, ядро", place: Place(latitude: 43.585, longitude: 39.723, zone: ZoneID("Europe/Moscow")!),
               day: CivilDate(year: 2026, month: 8, day: 15), minutes: 1350, aimLongitude: 0, lift: 8, roll: 0),
        Moment(name: "Томск, Лебедь", place: Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!),
               day: CivilDate(year: 2026, month: 9, day: 10), minutes: 1320, aimLongitude: 75, lift: 0, roll: 10),
        Moment(name: "Сидней, ядро в зените", place: Place(latitude: -33.87, longitude: 151.21, zone: ZoneID("Australia/Sydney")!),
               day: CivilDate(year: 2026, month: 6, day: 15), minutes: 1320, aimLongitude: 5, lift: 0, roll: -15),
        Moment(name: "Кито, Щит", place: Place(latitude: -0.18, longitude: -78.47, zone: ZoneID("America/Guayaquil")!),
               day: CivilDate(year: 2026, month: 7, day: 13), minutes: 1260, aimLongitude: 28, lift: 0, roll: 0),
        Moment(name: "Рейкьявик, Персей", place: Place(latitude: 64.15, longitude: -21.94, zone: ZoneID("Atlantic/Reykjavik")!),
               day: CivilDate(year: 2026, month: 11, day: 10), minutes: 1320, aimLongitude: 140, lift: 0, roll: 20),
    ]

    static let viewport = ScreenViewport(width: 440, height: 956)

    static func camera(_ m: Moment) -> (basis: CameraBasis, matrix: [Double], frame: MilkyWayLook.Frame) {
        let center = MilkyWayAR.center(day: m.day, minutes: m.minutes, in: m.place)
        let aim = center[Int(m.aimLongitude / 3)]
        let basis = CameraBasis(azimuth: aim.azimuth, altitude: aim.altitude + m.lift, roll: m.roll)
        return (basis, MilkyWayLook.pixelToSky(basis: basis, optics: .typical, viewport: viewport),
                MilkyWayLook.frame(day: m.day, minutes: m.minutes, in: m.place))
    }

    @Test("середина полосы MilkyWay.band, спроецированная SkyProjection, лежит на b = 0 картины (5 моментов, ≤ 0,5°)",
          arguments: moments.map(\.name))
    func centerLineOnEquator(_ name: String) {
        let m = Self.moments.first { $0.name == name }!
        let (basis, matrix, frame) = Self.camera(m)
        let center = MilkyWayAR.center(day: m.day, minutes: m.minutes, in: m.place)
        var checked = 0, worst = 0.0
        for (i, h) in center.enumerated() {
            guard let p = SkyProjection.project(azimuth: h.azimuth, altitude: h.altitude, basis: basis, optics: .typical,
                                                viewport: Self.viewport),
                  p.x >= 0, p.x <= Self.viewport.width, p.y >= 0, p.y <= Self.viewport.height else { continue }
            let g = frame.galactic(MilkyWayLook.sky(at: p, matrix: matrix))
            let dl = abs(((g.l - MilkyWay.band[i].longitude + 540).truncatingRemainder(dividingBy: 360)) - 180)
            worst = max(worst, abs(g.b), dl)
            checked += 1
        }
        #expect(checked >= 3, "в кадре точек полосы: \(checked)")
        #expect(worst <= 0.5, "\(name): середина полосы мимо b = 0 на \(worst)°")
    }

    @Test("ядро картины (l = 0, b = 0) — там, где MilkyWay.corePosition (≤ 0,5°)", arguments: [0, 2])
    func coreOnCorePosition(_ index: Int) {
        let m = Self.moments[index]
        let (basis, matrix, frame) = Self.camera(m)
        let core = MilkyWay.corePosition(date: m.day, minutes: m.minutes, place: m.place)
        let p = SkyProjection.project(azimuth: core.azimuth, altitude: core.altitude, basis: basis, optics: .typical,
                                      viewport: Self.viewport)!
        let g = frame.galactic(MilkyWayLook.sky(at: p, matrix: matrix))
        let off = max(abs(g.b), abs(((g.l + 180).truncatingRemainder(dividingBy: 360)) - 180))
        #expect(off <= 0.5, "ядро мимо на \(off)°")
    }

    @Test("гладкая яркость: вершина 1 в ядре, на краю MilkyWay.halfWidth — половина, по b убывает")
    func smoothProfile() {
        #expect(abs(MilkyWayLook.smooth(l: 0, b: 0) - 1) < 1e-12)
        for l in [60.0, 120.0, 180.0, 240.0] {
            let hw = MilkyWay.halfWidth(galacticLongitude: l)
            let ratio = MilkyWayLook.smooth(l: l, b: hw) / MilkyWayLook.smooth(l: l, b: 0)
            #expect(abs(ratio - 0.5) < 0.002, "l \(l): на краю \(ratio)")
            var prev = 2.0
            for b in stride(from: 0.0, through: 30, by: 0.5) {
                let v = MilkyWayLook.smooth(l: l, b: b)
                #expect(v < prev)
                #expect(abs(v - MilkyWayLook.smooth(l: l, b: -b)) < 1e-12)
                prev = v
            }
        }
        // К антицентру тусклее и уже.
        #expect(MilkyWayLook.smooth(l: 180, b: 0) < MilkyWayLook.smooth(l: 90, b: 0))
        #expect(MilkyWayLook.sigma(180) < MilkyWayLook.sigma(0) / 3)
    }

    @Test("солнце: выше −6° ноль, к −18° плавно растёт, дальше полная")
    func twilight() {
        let v = { (h: Double) in MilkyWayLook.visibility(sunAltitude: h, moonAltitude: -10, moonFraction: 1, glow: nil) }
        #expect(v(10).factor == 0 && v(10).hidden == .daylight)
        #expect(v(-5.99).factor == 0)
        #expect(v(-6).factor == 0)
        #expect(abs(v(-12).factor - 0.5) < 1e-12)
        #expect(v(-18).factor == 1 && v(-40).factor == 1 && v(-18).hidden == nil)
        var prev = -1.0
        for h in stride(from: -6.0, through: -18, by: -0.5) {
            #expect(v(h).factor >= prev)
            prev = v(h).factor
        }
    }

    @Test("луна — правило окна Млечного Пути: над горизонтом и светлее 40 % — не видно")
    func moonRule() {
        let v = { (alt: Double, f: Double) in MilkyWayLook.visibility(sunAltitude: -30, moonAltitude: alt, moonFraction: f, glow: nil) }
        #expect(v(5, 0.41).hidden == .moon && v(5, 0.41).factor == 0)
        #expect(v(5, 0.4).factor == 1)
        #expect(v(-0.1, 1).factor == 1)
        #expect(MilkyWayWindow.moonBlocks(altitude: 5, fraction: 0.41))
        #expect(!MilkyWayWindow.moonBlocks(altitude: 0, fraction: 1))
    }

    @Test("засветка атласа: контраст 1/(1 + ratio), ступень «дальше пусто» — ноль, атлас молчит — не трогаем")
    func glow() {
        let v = { (r: Double?) in MilkyWayLook.visibility(sunAltitude: -30, moonAltitude: -10, moonFraction: 0, glow: r) }
        #expect(v(nil).factor == 1)
        #expect(v(0).factor == 1)
        #expect(abs(v(3).factor - 0.25) < 1e-12)
        #expect(abs(v(12).factor - 1.0 / 13) < 1e-12)
        #expect(v(26.9).factor > 0)
        #expect(v(27).factor == 0 && v(27).hidden == .glow)
        // Сумерки и засветка множатся.
        let both = MilkyWayLook.visibility(sunAltitude: -12, moonAltitude: -10, moonFraction: 0, glow: 1)
        #expect(abs(both.factor - 0.25) < 1e-12)
    }

    @Test("дымка у горизонта: под горизонтом ноль, к MilkyWayDust.haze — полная")
    func horizon() {
        #expect(MilkyWayLook.horizonFade(altitude: -1) == 0)
        #expect(MilkyWayLook.horizonFade(altitude: 0) == 0)
        #expect(abs(MilkyWayLook.horizonFade(altitude: MilkyWayDust.haze / 2) - 0.5) < 1e-12)
        #expect(MilkyWayLook.horizonFade(altitude: MilkyWayDust.haze) == 1)
    }

    @Test("сцена: картина есть, только когда Млечный Путь включён и подан поворот; видимость — та же функция")
    func sceneCarriesPicture() {
        let m = Self.moments[0]
        let (basis, _, frame) = Self.camera(m)
        let band = MilkyWayAR.band(day: m.day, minutes: m.minutes, in: m.place)
        let core = MilkyWayAR.core(day: m.day, minutes: m.minutes, in: m.place)
        let input = NightSkyARScene.MilkyWayInput(band: band, core: core, sunAltitude: -12, frame: frame, glow: 3,
                                                  center: MilkyWayAR.center(day: m.day, minutes: m.minutes, in: m.place))
        let scene = NightSkyARScene.make(basis: basis, optics: .typical, viewport: Self.viewport, moon: nil, milkyWay: input)
        let pic = try! #require(scene.milkyWayPicture)
        #expect(abs(pic.visibility.factor - 0.125) < 1e-12)
        #expect(pic.centerLine.count > 3)
        let off = NightSkyARScene.make(basis: basis, optics: .typical, viewport: Self.viewport, moon: nil, milkyWay: nil)
        #expect(off.milkyWayPicture == nil)
    }
}
